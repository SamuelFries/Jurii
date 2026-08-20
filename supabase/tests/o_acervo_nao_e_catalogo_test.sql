-- O acervo não é catálogo, e a pasta tem teto.
--
-- Duas barreiras de storage, cada uma com a sabotagem correspondente: a
-- listagem que entregava o censo de usuários, e a conta sem teto que usava
-- os baldes privados como disco de graça.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('fa000000-0000-4000-8000-00000000000a','authenticated','authenticated','dono@acervo.test','',now(),'{}','{"full_name":"Dono"}',now(),now()),
  ('fa000000-0000-4000-8000-00000000000b','authenticated','authenticated','curioso@acervo.test','',now(),'{}','{"full_name":"Curioso"}',now(),now());

insert into storage.objects (bucket_id, name, owner, metadata)
values
  ('profile-avatars','fa000000-0000-4000-8000-00000000000a/avatar.png',
   'fa000000-0000-4000-8000-00000000000a', '{"size": 1024}'::jsonb),
  ('profile-avatars','fa000000-0000-4000-8000-00000000000b/avatar.png',
   'fa000000-0000-4000-8000-00000000000b', '{"size": 1024}'::jsonb),
  ('law-firm-avatars','fa000000-0000-4000-8000-00000000000a/fb000000-0000-4000-8000-000000000001/logo.png',
   'fa000000-0000-4000-8000-00000000000a', '{"size": 2048}'::jsonb);

-- ---------------------------------------------------------------------------
-- 1. A listagem não entrega o censo
-- ---------------------------------------------------------------------------
set local role anon;

select is(
  (select count(*)::int from storage.objects where bucket_id = 'profile-avatars'),
  0,
  'anonimo nao LISTA os avatares (o censo de quem tem conta)'
);

select is(
  (select count(*)::int from storage.objects where bucket_id = 'law-firm-avatars'),
  0,
  'nem as verificacoes de escritorio em andamento'
);

reset role;

select set_config('request.jwt.claim.sub','fa000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select is(
  (select count(*)::int from storage.objects
   where bucket_id = 'profile-avatars'
     and name like 'fa000000-0000-4000-8000-00000000000a/%'),
  0,
  'quem esta logado nao lista a pasta alheia'
);

select is(
  (select count(*)::int from storage.objects
   where bucket_id = 'profile-avatars'
     and name like 'fa000000-0000-4000-8000-00000000000b/%'),
  1,
  'mas enxerga a propria (apagar o proprio arquivo depende disso)'
);

reset role;

-- O download público não passa por RLS: o balde é public=true, e é por
-- /object/public/... que as duas telas mostram avatar.
select is(
  (select public::text from storage.buckets where id = 'profile-avatars'),
  'true',
  'o balde continua publico: o download do avatar nao depende da policy'
);

-- ---------------------------------------------------------------------------
-- 2. A cota
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','fa000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select ok(
  public.storage_cota_disponivel('case-documents', 524288000),
  'com a pasta vazia, ha cota'
);

reset role;

-- 500 MB já ocupados por esta conta.
insert into storage.objects (bucket_id, name, owner, metadata)
values ('case-documents','fa000000-0000-4000-8000-00000000000a/gordo.pdf',
        'fa000000-0000-4000-8000-00000000000a', '{"size": 524288000}'::jsonb);

select set_config('request.jwt.claim.sub','fa000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

-- ESTA É A ASSERÇÃO QUE PEGA A ARMADILHA: se a função de soma perder o dono
-- com bypassrls, o sum volta vazio, o coalesce vira zero e a cota passa a
-- liberar tudo em silêncio. Aqui ela precisa dizer "não".
select ok(
  not public.storage_cota_disponivel('case-documents', 524288000),
  'estourado o teto, a funcao diz nao (se ela perder bypassrls, cai aqui)'
);

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner, metadata)
    values ('case-documents','fa000000-0000-4000-8000-00000000000a/mais-um.pdf',
            'fa000000-0000-4000-8000-00000000000a', '{"size": 1024}'::jsonb)$$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'e o upload seguinte e recusado'
);

-- A cota é por balde e por conta: o vizinho não paga pelo excesso alheio.
select set_config('request.jwt.claim.sub','fa000000-0000-4000-8000-00000000000b', true);
select ok(
  public.storage_cota_disponivel('case-documents', 524288000),
  'e a conta do lado continua com a cota dela inteira'
);

reset role;

select * from finish();
rollback;
