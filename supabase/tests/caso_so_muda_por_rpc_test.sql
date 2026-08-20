-- O ciclo de vida do caso é o que as RPCs contam.
--
-- Antes da 20260918 o cliente fechava, reabria e renomeava o próprio caso
-- direto na tabela, contornando close_legal_case e reopen_legal_case: sem
-- aviso ao advogado, sem registro de quem fechou, sem convite de avaliação.
-- Este arquivo trava as duas metades: a escrita direta não passa, e a RPC
-- continua passando para quem pode.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ca100000-0000-4000-8000-00000000000a','authenticated','authenticated','cli@rpc.test','',now(),'{}','{"full_name":"Cliente do Caso"}',now(),now()),
  ('ca100000-0000-4000-8000-00000000000b','authenticated','authenticated','adv@rpc.test','',now(),'{}','{"full_name":"Advogada do Caso"}',now(),now());

insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas)
values ('ca100000-0000-4000-8000-00000000000b','848484','RS','Direito Trabalhista',
        array['Direito Trabalhista']);

insert into public.legal_cases (id, client_id, assigned_lawyer_id, title, area, status)
values ('cc100000-0000-4000-8000-000000000001','ca100000-0000-4000-8000-00000000000a',
        'ca100000-0000-4000-8000-00000000000b','Acao trabalhista','Direito Trabalhista','open');

-- ---------------------------------------------------------------------------
-- 1. O cliente não mexe na tabela
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$update public.legal_cases set status='closed'
      where id='cc100000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table legal_cases',
  'o cliente NAO fecha o proprio caso por escrita direta'
);

select throws_ok(
  $$update public.legal_cases set title='Titulo reescrito pelo cliente'
      where id='cc100000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table legal_cases',
  'nem reescreve o titulo do caso que a advogada trabalha'
);

select throws_ok(
  $$insert into public.legal_cases (client_id, title, area, status)
    values ('ca100000-0000-4000-8000-00000000000a','Caso forjado','Direito Civel','open')$$,
  '42501',
  'permission denied for table legal_cases',
  'nem cria caso direto na tabela'
);

-- Ler continua valendo: o portão é a escrita.
select is(
  (select status from public.legal_cases
   where id='cc100000-0000-4000-8000-000000000001'),
  'open',
  'mas o cliente continua LENDO o proprio caso'
);

-- ---------------------------------------------------------------------------
-- 2. A advogada também não escreve direto (o portão não é sobre o cliente)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-00000000000b', true);

select throws_ok(
  $$update public.legal_cases set status='closed'
      where id='cc100000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table legal_cases',
  'a advogada tambem nao fecha por escrita direta'
);

-- ---------------------------------------------------------------------------
-- 3. E a RPC continua fazendo o trabalho
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select public.close_legal_case('cc100000-0000-4000-8000-000000000001')$$,
  'a advogada fecha pela RPC, que e o caminho com aviso e registro'
);

reset role;

select is(
  (select status::text from public.legal_cases
   where id='cc100000-0000-4000-8000-000000000001'),
  'closed',
  'e o caso fecha de verdade'
);

-- A barreira de novo, em forma de invariante: nenhuma coluna de legal_cases
-- fica gravável por quem está logado. Se alguém reconceder uma delas, cai.
select is(
  (select coalesce(string_agg(column_name, ', ' order by column_name), '')
   from information_schema.column_privileges
   where table_name = 'legal_cases' and grantee = 'authenticated'
     and privilege_type in ('INSERT', 'UPDATE')),
  '',
  'nenhuma coluna de legal_cases fica gravavel direto por authenticated'
);

-- ---------------------------------------------------------------------------
-- 4. A mesma regra na fila da revisão (20260919)
--
-- O candidato reescrevia o próprio submitted_at e passava na frente na fila
-- que a equipe Jurii revisa por ordem de envio.
-- ---------------------------------------------------------------------------
insert into public.lawyer_verifications
  (id, user_id, oab_number, oab_state, practice_area, status, submitted_at)
values ('cd100000-0000-4000-8000-000000000001','ca100000-0000-4000-8000-00000000000a',
        '959595','RS','Direito Civel','pending', now());

select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$update public.lawyer_verifications set submitted_at = now() - interval '30 days'
      where id='cd100000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table lawyer_verifications',
  'o candidato NAO reescreve o proprio submitted_at para furar a fila'
);

select is(
  (select count(*)::int from public.lawyer_verifications
   where id='cd100000-0000-4000-8000-000000000001'),
  1,
  'mas continua enxergando a propria verificacao'
);

select is(
  (select coalesce(string_agg(column_name, ', ' order by column_name), '')
   from information_schema.column_privileges
   where table_name = 'lawyer_verifications' and grantee = 'authenticated'
     and privilege_type in ('INSERT', 'UPDATE')),
  '',
  'e nenhuma coluna da verificacao fica gravavel direto (tudo por RPC)'
);

reset role;

select * from finish();
rollback;
