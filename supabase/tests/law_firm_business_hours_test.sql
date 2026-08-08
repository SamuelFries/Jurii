-- Testes da migration 20260820120000: horarios de atendimento.
--
-- O horario existe para o CLIENTE responder "adianta escrever agora?". Entao
-- as duas coisas que precisam estar travadas sao: quem pode ESCREVER (so quem
-- fala pelo escritorio) e quem pode LER (todo mundo, senao a informacao nao
-- serve para o que ela existe).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'dono@horario.test', '', now(), '{}'::jsonb,
   '{"full_name":"Dono Horario"}'::jsonb, now(), now()),
  ('f1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'secretaria@horario.test', '', now(), '{}'::jsonb,
   '{"full_name":"Secretaria"}'::jsonb, now(), now()),
  ('f1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'cliente@horario.test', '', now(), '{}'::jsonb,
   '{"full_name":"Cliente"}'::jsonb, now(), now());

insert into public.law_firms
  (id, name, initials, specialty, practice_areas, is_active)
values
  ('f2000000-0000-0000-0000-000000000001', 'Firma Horario', 'FH',
   'Direito Cível', array['Direito Cível'], true),
  ('f2000000-0000-0000-0000-000000000002', 'Outra Firma', 'OF',
   'Direito Cível', array['Direito Cível'], true);

insert into public.law_firm_members
  (law_firm_id, profile_id, member_role, roles, status)
values
  ('f2000000-0000-0000-0000-000000000001',
   'f1000000-0000-0000-0000-000000000001', 'owner', array['owner'], 'active'),
  ('f2000000-0000-0000-0000-000000000001',
   'f1000000-0000-0000-0000-000000000002', 'secretary', array['secretary'],
   'active');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Gravacao
-- ---------------------------------------------------------------------------

select results_eq(
  $$select weekday, opens_at, closes_at
    from public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001',
      '[{"weekday":1,"opens_at":"09:00","closes_at":"18:00"},
        {"weekday":2,"opens_at":"09:00","closes_at":"18:00"}]'::jsonb)$$,
  $$values (1::smallint, '09:00'::time, '18:00'::time),
           (2::smallint, '09:00'::time, '18:00'::time)$$,
  'grava os intervalos e devolve o conjunto ordenado');

-- Substituir tudo, e nao editar linha a linha, e o que evita o cliente ver um
-- estado intermediario — sexta sumida por um instante porque a tela ainda
-- estava gravando.
select is(
  (select count(*)::int from public.law_firm_business_hours
    where law_firm_id = 'f2000000-0000-0000-0000-000000000001'),
  2,
  'o conjunto anterior e substituido, nao somado');

select lives_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001',
      '[{"weekday":3,"opens_at":"09:00","closes_at":"12:00"},
        {"weekday":3,"opens_at":"13:30","closes_at":"18:00"}]'::jsonb)$$,
  'dois intervalos no MESMO dia passam (escritorio que fecha para almoco)');

select is(
  (select count(*)::int from public.law_firm_business_hours
    where law_firm_id = 'f2000000-0000-0000-0000-000000000001'),
  2,
  'e a gravacao anterior saiu junto');

-- Dia fechado simplesmente nao tem linha. Mandar item sem horario e o jeito
-- natural de a tela dizer isso.
select lives_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001',
      '[{"weekday":1,"opens_at":"09:00","closes_at":"18:00"},
        {"weekday":6,"opens_at":null,"closes_at":null}]'::jsonb)$$,
  'item sem horario e descartado em vez de estourar');

select is(
  (select count(*)::int from public.law_firm_business_hours
    where law_firm_id = 'f2000000-0000-0000-0000-000000000001'),
  1,
  'so o dia com horario virou linha');

-- Esvaziar e uma operacao legitima: escritorio que so atende sob agendamento.
select lives_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'lista vazia limpa os horarios');

select is(
  (select count(*)::int from public.law_firm_business_hours
    where law_firm_id = 'f2000000-0000-0000-0000-000000000001'),
  0,
  'e limpa de verdade');

-- ---------------------------------------------------------------------------
-- Validacao
-- ---------------------------------------------------------------------------

-- Intervalo invertido nao e "fecha no dia seguinte", e digitacao errada: a
-- tela nao oferece virada de meia-noite, e aceitar deixaria um horario que
-- nunca esta aberto.
select throws_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001',
      '[{"weekday":1,"opens_at":"18:00","closes_at":"09:00"}]'::jsonb)$$,
  '23514',
  null,
  'fechamento antes da abertura e recusado pelo banco');

select throws_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001',
      '[{"weekday":8,"opens_at":"09:00","closes_at":"18:00"}]'::jsonb)$$,
  '23514',
  null,
  'dia da semana fora de 1..7 e recusado');

-- ---------------------------------------------------------------------------
-- Portao: quem escreve, e quem le
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

-- Mesmo portao do cadastro, da apresentacao e do painel de alcance.
select throws_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000001',
      '[{"weekday":1,"opens_at":"09:00","closes_at":"18:00"}]'::jsonb)$$,
  'Not allowed',
  'secretaria NAO grava horario');

reset role;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select throws_ok(
  $$select public.set_law_firm_business_hours(
      'f2000000-0000-0000-0000-000000000002',
      '[{"weekday":1,"opens_at":"09:00","closes_at":"18:00"}]'::jsonb)$$,
  'Not allowed',
  'estranho NAO grava horario de escritorio que nao e dele');

reset role;
insert into public.law_firm_business_hours (law_firm_id, weekday, opens_at, closes_at)
values ('f2000000-0000-0000-0000-000000000001', 1, '09:00', '18:00');
set local role authenticated;

-- Leitura e PUBLICA para autenticado de proposito: o horario existe para o
-- cliente ver ANTES de escrever. Esconde-lo de quem procura advogado seria
-- guardar justamente a unica coisa que ele serve para responder.
select is(
  (select count(*)::int from public.law_firm_business_hours
    where law_firm_id = 'f2000000-0000-0000-0000-000000000001'),
  1,
  'o CLIENTE le o horario do escritorio');

select * from finish();
rollback;
