#!/bin/bash
# A corrida de decisão do pedido de entrada, com DUAS SESSÕES DE VERDADE.
#
# POR QUE ELA EXISTE FORA DO pgTAP: pgTAP roda tudo numa transação só, então
# `FOR UPDATE` é INOBSERVÁVEL lá — remover a trava não faz teste nenhum
# falhar, porque nunca há duas sessões disputando. Medido: a sabotagem que
# tira o FOR UPDATE passa incólume na suíte inteira.
#
# Aqui dois psql concorrem pelo mesmo pedido. Com a trava, o segundo espera o
# primeiro commitar e ouve QUEM decidiu. Sem ela, os dois leem 'pending' e os
# dois seguem.
set -u
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
ok=0; falha=0
confere() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "ok   $1"; else falha=$((falha+1)); echo "FALHA $1 (esperado $3, veio $2)"; fi; }

limpa() {
  psql "$DB" -q -c "delete from auth.users where email like '%@corrida.test';
                    delete from public.law_firms where id='ec000000-0000-4000-8000-00000000000c';" 2>/dev/null
}
limpa; trap limpa EXIT

psql "$DB" -q <<SQL
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ec100000-0000-4000-8000-00000000000a','authenticated','authenticated','socia@corrida.test','',now(),'{}','{"full_name":"Socia Um"}',now(),now()),
  ('ec100000-0000-4000-8000-00000000000b','authenticated','authenticated','admin@corrida.test','',now(),'{}','{"full_name":"Admin Dois"}',now(),now()),
  ('ec100000-0000-4000-8000-00000000000c','authenticated','authenticated','pede@corrida.test','',now(),'{}','{"full_name":"Quem Pede"}',now(),now());
insert into public.law_firms (id, name, initials, specialty, is_active, cep, oab_state)
values ('ec000000-0000-4000-8000-00000000000c','Banca da Corrida','BC','Direito Cível',true,'90540140','RS');
insert into public.law_firm_members (law_firm_id, profile_id, roles, member_role, role, status)
values
  ('ec000000-0000-4000-8000-00000000000c','ec100000-0000-4000-8000-00000000000a',array['owner'],'owner','owner','active'),
  ('ec000000-0000-4000-8000-00000000000c','ec100000-0000-4000-8000-00000000000b',array['admin'],'admin','admin','active');
SQL

TOKEN=$(psql "$DB" -tAc "
  select set_config('request.jwt.claim.sub','ec100000-0000-4000-8000-00000000000a', true);
  set local role authenticated;
  select token from public.criar_link_de_convite('ec000000-0000-4000-8000-00000000000c','secretary');" | tail -1)

PEDIDO=$(psql "$DB" -tAc "
  select set_config('request.jwt.claim.sub','ec100000-0000-4000-8000-00000000000c', true);
  set local role authenticated;
  select public.solicitar_entrada_por_link('$TOKEN');" | tail -1)
[ -n "$PEDIDO" ] && confere "o pedido foi criado" "sim" "sim" || confere "o pedido foi criado" "nao" "sim"

# Sessão A abre transação, decide, e SEGURA por 2s antes do commit.
psql "$DB" > /tmp/corrida-a.txt 2>&1 <<SQL &
begin;
select set_config('request.jwt.claim.sub','ec100000-0000-4000-8000-00000000000a', true);
set local role authenticated;
select public.decidir_entrada_no_escritorio('$PEDIDO', true) as sessao_a;
select pg_sleep(2);
commit;
SQL
sleep 0.4

# Sessão B entra no meio, com a A ainda sem commitar.
psql "$DB" > /tmp/corrida-b.txt 2>&1 <<SQL
begin;
select set_config('request.jwt.claim.sub','ec100000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select public.decidir_entrada_no_escritorio('$PEDIDO', true) as sessao_b;
commit;
SQL
wait

grep -q "approved" /tmp/corrida-a.txt && A="approved" || A="outro"
confere "a sessao A aprovou" "$A" "approved"

grep -q "already decided by Socia Um" /tmp/corrida-b.txt && B="bloqueada" || B="passou"
confere "a sessao B esperou e ouviu QUEM decidiu" "$B" "bloqueada"

N=$(psql "$DB" -tAc "select count(*) from public.law_firm_members
     where law_firm_id='ec000000-0000-4000-8000-00000000000c'
       and profile_id='ec100000-0000-4000-8000-00000000000c';")
confere "a pessoa entrou UMA vez" "$N" "1"

D=$(psql "$DB" -tAc "select count(*) from public.law_firm_join_requests
     where id='$PEDIDO' and status='approved';")
confere "o pedido tem UMA decisao" "$D" "1"

echo; echo "=== $ok ok, $falha falhas ==="
[ $falha -eq 0 ]
