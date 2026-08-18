-- Documentos do caso.
--
-- A tabela existia desde a baseline com INSERT/SELECT e nunca recebeu uma
-- linha (o app não tinha a tela). A 20260910120000 fechou o que faltava para
-- a feature nascer: remoção pelo autor, CHECKs de sanidade e a regra de que o
-- caminho no storage pertence à pasta de quem subiu.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

-- ---------------------------------------------------------------------------
-- Cenário: um caso com cliente e advogada
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a0000000-0000-4000-8000-00000000000a','authenticated','authenticated','cliente@doc.test','',now(),'{}','{"full_name":"Cliente Doc"}',now(),now()),
  ('a0000000-0000-4000-8000-00000000000b','authenticated','authenticated','advogada@doc.test','',now(),'{}','{"full_name":"Advogada Doc"}',now(),now()),
  ('a0000000-0000-4000-8000-00000000000c','authenticated','authenticated','intruso@doc.test','',now(),'{}','{"full_name":"Intruso Doc"}',now(),now());

update public.profiles set lawyer_status = 'approved'
where id = 'a0000000-0000-4000-8000-00000000000b';

-- assigned_lawyer_id referencia lawyer_profiles, nao profiles.
insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values ('a0000000-0000-4000-8000-00000000000b','616161','RS','Direito Cível',
        array['Direito Cível'], now());

insert into public.legal_cases (id, client_id, assigned_lawyer_id, title, area, status)
values ('ca000000-0000-4000-8000-00000000000a',
        'a0000000-0000-4000-8000-00000000000a',
        'a0000000-0000-4000-8000-00000000000b',
        'Caso com documentos','Direito Cível','open');

insert into public.case_participants (case_id, profile_id, role)
values
  ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000a','client'),
  ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b','lawyer');

-- ---------------------------------------------------------------------------
-- 1. Subir e listar
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select lives_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path, mime_type, file_size_bytes)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b',
            'Procuração assinada','a0000000-0000-4000-8000-00000000000b/ca-doc-1.pdf','application/pdf', 120000)$$,
  'a advogada anexa um documento ao caso dela');

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  1,
  'e ela ve o documento na lista');

reset role;

-- O cliente do MESMO caso também vê.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  1,
  'o cliente do caso ve o mesmo documento');

select lives_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path, mime_type, file_size_bytes)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000a',
            'RG e CPF','a0000000-0000-4000-8000-00000000000a/ca-doc-2.pdf','application/pdf', 90000)$$,
  'e o cliente tambem anexa');

reset role;

-- Quem não é do caso não vê nada e não insere nada.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000c', true);
set local role authenticated;

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  0,
  'quem nao e do caso ve lista vazia');

select throws_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000c',
            'Intrusao','a0000000-0000-4000-8000-00000000000c/x.pdf')$$,
  '42501',
  'new row violates row-level security policy for table "case_documents"',
  'e nao consegue anexar em caso alheio');

-- E NÃO SE ANEXA EM NOME DOS OUTROS: uploaded_by é quem está logado.
select throws_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b',
            'Falsificada','a0000000-0000-4000-8000-00000000000b/f.pdf')$$,
  '42501',
  'new row violates row-level security policy for table "case_documents"',
  'assinar o upload com o uid de outra pessoa e recusado');

reset role;

-- ---------------------------------------------------------------------------
-- 2. Remover: quem subiu, remove; o outro lado não
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

-- Tentar apagar o documento DA ADVOGADA: o delete roda e não leva nada.
delete from public.case_documents
where title = 'Procuração assinada';

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  2,
  'o cliente NAO apaga o documento que a advogada subiu');

delete from public.case_documents where title = 'RG e CPF';

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  1,
  'mas apaga o que ele mesmo subiu');

reset role;

-- ---------------------------------------------------------------------------
-- 3. Os CHECKs de sanidade
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select throws_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b',
            '   ','a0000000-0000-4000-8000-00000000000b/t.pdf')$$,
  '23514',
  null,
  'titulo em branco nao entra');

select throws_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path, file_size_bytes)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b',
            'Grande demais','a0000000-0000-4000-8000-00000000000b/g.pdf', 999999999)$$,
  '23514',
  null,
  'tamanho acima do teto do bucket nao entra');

select throws_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path, file_size_bytes)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b',
            'Negativo','a0000000-0000-4000-8000-00000000000b/n.pdf', -5)$$,
  '23514',
  null,
  'tamanho negativo nao entra');

-- O caminho pertence à pasta de quem sobe. Uma linha apontando para a pasta
-- de OUTRA pessoa faria a leitura do bucket servir objeto alheio.
select throws_ok(
  $$insert into public.case_documents (case_id, uploaded_by, title, storage_path)
    values ('ca000000-0000-4000-8000-00000000000a','a0000000-0000-4000-8000-00000000000b',
            'Pasta alheia','a0000000-0000-4000-8000-00000000000a/roubado.pdf')$$,
  '23514',
  null,
  'caminho fora da propria pasta nao entra');

reset role;

-- ---------------------------------------------------------------------------
-- 4. Caso encerrado: ler sim, e o resto acompanha o acesso ao caso
-- ---------------------------------------------------------------------------
--
-- Encerrar caso não apaga o acesso (can_access_case segue true para os
-- participantes), então documentos seguem legíveis: prontuário não evapora.
update public.legal_cases set status = 'closed'
where id = 'ca000000-0000-4000-8000-00000000000a';

select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000a', true);
set local role authenticated;

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  1,
  'caso encerrado continua com os documentos legiveis');

reset role;

-- ---------------------------------------------------------------------------
-- 5. O storage acompanha: escrever e apagar só na pasta própria
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_policy
   where polrelid = 'storage.objects'::regclass
     and polname in ('case_documents_storage_own_folder_write',
                     'case_documents_storage_own_folder_delete',
                     'case_documents_storage_related_read')),
  3,
  'as tres policies do bucket existem (escrita, remocao e leitura)');

select is(
  (select count(*)::int from public.case_documents cd
   where cd.storage_path not like (cd.uploaded_by::text || '/%')),
  0,
  'nenhuma linha aponta para fora da pasta do proprio autor');

-- ---------------------------------------------------------------------------
-- 6. Quem saiu do caso leva junto o direito de remover
-- ---------------------------------------------------------------------------
--
-- Advogado trocado: sai da atribuição e da lista de participantes. O
-- documento que ele subiu FICA (é prontuário do caso), e ele não pode mais
-- removê-lo de lá de fora.
update public.legal_cases set assigned_lawyer_id = null
where id = 'ca000000-0000-4000-8000-00000000000a';
delete from public.case_participants
where case_id = 'ca000000-0000-4000-8000-00000000000a'
  and profile_id = 'a0000000-0000-4000-8000-00000000000b';

select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

delete from public.case_documents where title = 'Procuração assinada';

reset role;

select is(
  (select count(*)::int from public.case_documents
   where case_id = 'ca000000-0000-4000-8000-00000000000a'),
  1,
  'advogado que saiu do caso nao apaga nem o proprio documento');

-- ---------------------------------------------------------------------------
-- 7. A guarda do bucket: objeto LIGADO a uma linha não sai por fora
-- ---------------------------------------------------------------------------
--
-- A API de Storage consulta estes helpers na hora do DELETE. Documento com
-- linha viva é peça do caso (ou da revisão de verificação): apagar o objeto
-- por baixo deixaria um item listado que nunca abre.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-00000000000b', true);
set local role authenticated;

select is(
  public.can_delete_unlinked_case_document(
    'a0000000-0000-4000-8000-00000000000b/ca-doc-1.pdf'),
  false,
  'documento de caso COM linha nao pode sair do bucket');

select is(
  public.can_delete_unlinked_case_document(
    'a0000000-0000-4000-8000-00000000000b/orfao-de-rollback.pdf'),
  true,
  'orfao de rollback na propria pasta pode');

select is(
  public.can_delete_unlinked_case_document(
    'a0000000-0000-4000-8000-00000000000a/arquivo-alheio.pdf'),
  false,
  'e a pasta dos outros nunca');

reset role;

select * from finish();
rollback;
