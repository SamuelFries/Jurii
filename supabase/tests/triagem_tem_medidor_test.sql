-- O taxímetro da triagem por IA.
--
-- Cada chamada da Edge Function custa dinheiro na API da Anthropic, e a
-- chave anon é pública. O que este arquivo trava: o teto por hora e por dia
-- valem de verdade, anônimo não chama, ninguém lê o taxímetro, e a janela
-- passa e devolve o direito (teto não é banimento).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a1a00000-0000-4000-8000-00000000000a','authenticated','authenticated','cliente@triagem.test','',now(),'{}','{"full_name":"Cliente Triagem"}',now(),now()),
  ('a1a00000-0000-4000-8000-00000000000b','authenticated','authenticated','vizinho@triagem.test','',now(),'{}','{"full_name":"Vizinho"}',now(),now());

-- ---------------------------------------------------------------------------
-- 1. Quem chama, e quanto
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','a1a00000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select lives_ok(
  'select public.registrar_chamada_de_triagem()',
  'usuario autenticado registra a chamada'
);

-- Consome o resto do teto da hora (11 restantes).
do $$
begin
  for i in 1..11 loop
    perform public.registrar_chamada_de_triagem();
  end loop;
end;
$$;

select throws_ok(
  'select public.registrar_chamada_de_triagem()',
  'Intake AI hourly limit reached. Try again later',
  'a decima terceira na mesma hora e recusada'
);

-- O vizinho nao paga pelo teto alheio.
select set_config('request.jwt.claim.sub','a1a00000-0000-4000-8000-00000000000b', true);
select lives_ok(
  'select public.registrar_chamada_de_triagem()',
  'o teto e por usuario: o vizinho continua com o dele'
);

reset role;

-- ---------------------------------------------------------------------------
-- 2. A janela passa e devolve o direito; o teto do dia segura
-- ---------------------------------------------------------------------------
-- Envelhece as chamadas da hora para 2h atras: a janela da hora libera.
update public.intake_ai_calls
set called_at = now() - interval '2 hours'
where profile_id = 'a1a00000-0000-4000-8000-00000000000a';

select set_config('request.jwt.claim.sub','a1a00000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select lives_ok(
  'select public.registrar_chamada_de_triagem()',
  'passada a hora, o usuario chama de novo (teto nao e banimento)'
);

reset role;

-- Enche o dia: 30 chamadas nas ultimas 24h (12 velhas de 2h + as novas).
insert into public.intake_ai_calls (profile_id, called_at)
select 'a1a00000-0000-4000-8000-00000000000a', now() - interval '3 hours'
from generate_series(1, 17);

select set_config('request.jwt.claim.sub','a1a00000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select throws_ok(
  'select public.registrar_chamada_de_triagem()',
  'Intake AI daily limit reached. Try again tomorrow',
  'o teto do dia segura mesmo com a hora livre'
);

-- ---------------------------------------------------------------------------
-- 3. Portas fechadas
-- ---------------------------------------------------------------------------
select throws_ok(
  'select count(*) from public.intake_ai_calls',
  '42501',
  'permission denied for table intake_ai_calls',
  'nem o dono le o proprio taximetro (sem grant, sem policy)'
);

reset role;
set local role anon;

select throws_ok(
  'select public.registrar_chamada_de_triagem()',
  '42501',
  'permission denied for function registrar_chamada_de_triagem',
  'anonimo nao tem nem o execute'
);

reset role;

-- A faxina de passagem: registro com mais de 48h some na proxima chamada.
insert into public.intake_ai_calls (profile_id, called_at)
values ('a1a00000-0000-4000-8000-00000000000b', now() - interval '3 days');

select set_config('request.jwt.claim.sub','a1a00000-0000-4000-8000-00000000000b', true);
set local role authenticated;
select public.registrar_chamada_de_triagem();
reset role;

select is(
  (select count(*)::int from public.intake_ai_calls
   where profile_id = 'a1a00000-0000-4000-8000-00000000000b'
     and called_at < now() - interval '48 hours'),
  0,
  'a chamada faz a faxina dos proprios registros velhos (sem cron)'
);

select * from finish();
rollback;
