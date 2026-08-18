-- Documentos do caso: a metade que faltava para a feature existir.
--
-- A tabela case_documents, as policies de INSERT/SELECT e o bucket
-- case-documents (25MB, PDF/imagem/DOC) existem desde a baseline, e NENHUMA
-- linha foi escrita até hoje: o app nunca ganhou a tela. Antes de ele ganhar,
-- dois buracos do desenho original precisam fechar.
--
-- 1. NÃO EXISTIA COMO REMOVER. Nem policy de DELETE na tabela, nem no
--    storage. Num produto jurídico isso não é rigor, é armadilha: quem anexa
--    a procuração do cliente ERRADO precisa poder tirá-la, e a alternativa
--    (chamar a gente para apagar à mão) é pior para a privacidade, não
--    melhor. A regra é a mínima: cada um remove O QUE ELE MESMO subiu.
--
-- 2. A tabela aceitava qualquer coisa nas colunas que o app vai exibir:
--    título vazio, tamanho negativo, tamanho maior do que o bucket deixa
--    entrar. CHECKs baratos agora, enquanto a tabela tem zero linhas.

-- ---------------------------------------------------------------------------
-- 1. Remover: quem subiu, remove
-- ---------------------------------------------------------------------------
drop policy if exists case_documents_delete_own on public.case_documents;
create policy case_documents_delete_own
on public.case_documents
for delete
to authenticated
using (
  uploaded_by = (select auth.uid())
  -- E ainda com acesso ao caso: quem saiu do caso (advogado trocado, membro
  -- desligado) leva junto o direito de mexer no arquivo dele ali dentro.
  and public.can_access_case(case_id)
);

grant delete on public.case_documents to authenticated;

-- O objeto no bucket sai pela regra do chat: pasta própria E sem linha
-- apontando para ele. A ordem do app (linha primeiro, objeto depois) faz o
-- objeto estar sempre "solto" na hora de sair, e a exigência de estar solto
-- impede o inverso: apagar o objeto por fora e deixar uma linha viva
-- apontando para arquivo morto, um documento listado que nunca abre.
create or replace function public.can_delete_unlinked_case_document(
  storage_path_value text
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select auth.uid() is not null
    and (storage.foldername(coalesce(storage_path_value, '')))[1]
        = auth.uid()::text
    and not exists (
      select 1
      from public.case_documents cd
      where cd.storage_path = storage_path_value
    );
$$;

drop policy if exists case_documents_storage_own_folder_delete on storage.objects;
create policy case_documents_storage_own_folder_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'case-documents'
  and public.can_delete_unlinked_case_document(name)
);

-- E A LEITURA DA PRÓPRIA PASTA, que é a metade que faz o DELETE funcionar.
--
-- MEDIDO contra a API de Storage local: apagar exige ENXERGAR o objeto, e a
-- única leitura que existia (a da linha relacionada) morre junto com a
-- linha. Sem esta policy, todo delete respondia 403 "Access denied" e todo
-- rollback de upload deixava um órfão. Ler a própria pasta não expõe nada:
-- são os arquivos que a própria pessoa subiu.
drop policy if exists case_documents_storage_own_folder_read on storage.objects;
create policy case_documents_storage_own_folder_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'case-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- ---------------------------------------------------------------------------
-- 2. O que a tabela aceita
-- ---------------------------------------------------------------------------
--
-- `not valid` não é preciso: a tabela tem zero linhas em qualquer ambiente
-- (a feature nunca existiu no app), então validar tudo custa nada.
alter table public.case_documents
  drop constraint if exists case_documents_title_sane;
alter table public.case_documents
  add constraint case_documents_title_sane
  check (length(btrim(title)) between 1 and 200);

alter table public.case_documents
  drop constraint if exists case_documents_size_sane;
alter table public.case_documents
  add constraint case_documents_size_sane
  check (
    file_size_bytes is null
    or (file_size_bytes > 0 and file_size_bytes <= 26214400)
  );

-- O caminho no storage é sempre {uid do autor}/..., que é o que a policy de
-- escrita do bucket exige. Gravar na tabela um caminho fora da pasta do autor
-- criaria uma linha que aponta para objeto de OUTRA pessoa, e a leitura do
-- bucket confia na linha.
alter table public.case_documents
  drop constraint if exists case_documents_path_own_folder;
alter table public.case_documents
  add constraint case_documents_path_own_folder
  check (storage_path like (uploaded_by::text || '/%'));

-- ---------------------------------------------------------------------------
-- 3. Índice do caminho quente: a lista de documentos de um caso
-- ---------------------------------------------------------------------------
create index if not exists case_documents_case_recentes_idx
  on public.case_documents (case_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 4. O mesmo furo nos OUTROS buckets privados, descoberto pela mesma prova
-- ---------------------------------------------------------------------------
--
-- A prova de ponta a ponta desta feature mediu a regra geral: a API de
-- Storage exige SELECT no objeto para deixar apagá-lo. Dois rollbacks antigos
-- nunca funcionaram por causa disso, e os dois falham em silêncio
-- (try/catch com debugPrint):
--
--   chat-attachments: a policy chat_attachments_storage_unlinked_own_delete
--   existe desde a 20260801120000 e NUNCA deixou apagar nada, porque objeto
--   sem linha não é visível pela única policy de leitura (a relacionada).
--   O rollback de upload de anexo que falha no meio sempre deixou órfão.
--
--   verification-documents: tem leitura da própria pasta, mas NENHUMA policy
--   de delete. O rollback do submit de verificação
--   (VerificationDocumentStorage.remove) sempre respondeu 403.
--
-- Órfão em bucket privado não vaza para ninguém; o custo é armazenamento
-- crescendo para sempre e um "rollback" que mente no nome. Uma policy em
-- cada bucket fecha.
drop policy if exists chat_attachments_storage_own_folder_read on storage.objects;
create policy chat_attachments_storage_own_folder_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Verificação: apagar só o que ainda não virou documento de verificação
-- formal (linha nas tabelas). Depois que a linha existe, o arquivo é peça do
-- processo de revisão e não sai pela mão de quem o subiu.
create or replace function public.can_delete_unlinked_verification_document(
  storage_path_value text
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select auth.uid() is not null
    and (storage.foldername(coalesce(storage_path_value, '')))[1]
        = auth.uid()::text
    and not exists (
      select 1
      from public.verification_documents vd
      where vd.storage_path = storage_path_value
    )
    and not exists (
      select 1
      from public.law_firm_verification_documents lfvd
      where lfvd.storage_path = storage_path_value
    );
$$;

drop policy if exists verification_documents_storage_unlinked_own_delete on storage.objects;
create policy verification_documents_storage_unlinked_own_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'verification-documents'
  and public.can_delete_unlinked_verification_document(name)
);

notify pgrst, 'reload schema';
