-- O acervo não é catálogo, e a pasta tem teto.
--
-- DUAS PONTAS DO MESMO BALDE, achadas na auditoria de storage.
--
-- 1. LISTAGEM ANÔNIMA. profile_avatars_public_read e
--    law_firm_avatars_public_read davam select ao papel `public` no balde
--    INTEIRO, sem olhar caminho. Isso libera o download, que é o objetivo,
--    mas libera junto o endpoint de listagem. Reproduzido sem login nenhum,
--    só com a chave publicável: POST /storage/v1/object/list/profile-avatars
--    com prefixo vazio devolve a pasta de cada usuário, isto é o uuid de todo
--    perfil que já subiu foto. Em law-firm-avatars o caminho é
--    {dono}/{verificacao}/arquivo, então a mesma listagem entrega quem tem
--    verificação de escritório em andamento e quando ela começou.
--
--    Não vaza conteúdo que já não fosse público (a foto é pública de
--    propósito), mas entrega um censo: quem tem conta, quantos são, e quais
--    escritórios estão em processo de verificação agora. Enumeração é o
--    primeiro passo de qualquer ataque dirigido, e não custa nada fechar.
--
--    O download continua igual: balde com public=true serve
--    /storage/v1/object/public/... sem passar por RLS, e é assim que as duas
--    telas mostram avatar (safe_law_firm_logo_url monta exatamente essa URL).
--    A leitura autenticada passa a ser só da própria pasta, que é o que o
--    app precisa para apagar o próprio arquivo (DELETE no storage exige
--    enxergar o objeto, como a 20260910120000 aprendeu).
--
-- 2. COTA POR CONTA. As policies de INSERT de case-documents e
--    chat-attachments exigem só que a primeira pasta seja o auth.uid(). Não
--    há vínculo com caso ou conversa, nem teto total. Reproduzido: conta
--    recém-criada, sem nenhum caso e sem nenhuma conversa, subiu 100 MB em
--    quatro arquivos. Os objetos ficam órfãos (sem linha em case_documents ou
--    message_attachments), então não aparecem em tela nenhuma e ninguém
--    percebe. O teto por arquivo existe (26 MB no balde) e funciona; o que
--    faltava era teto por conta.
--
--    ARMADILHA, e é por isso que existe teste: storage.objects tem RLS e
--    pertence a supabase_storage_admin, que NÃO tem bypassrls. Se a função
--    de soma pertencer a um papel sem bypass, o sum volta nulo, o coalesce
--    vira zero, e a cota nunca dispara: fica tudo liberado sem erro nenhum,
--    em silêncio. Aqui a função nasce de postgres (bypassrls), e o teste
--    grava acima do teto e exige a recusa, justamente para pegar essa
--    regressão se alguém recriar a função com outro dono.

-- ---------------------------------------------------------------------------
-- 1. Leitura: própria pasta, e não o balde inteiro
-- ---------------------------------------------------------------------------
drop policy if exists "profile_avatars_public_read" on storage.objects;
create policy "profile_avatars_own_folder_read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'profile-avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "law_firm_avatars_public_read" on storage.objects;
create policy "law_firm_avatars_own_folder_read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'law-firm-avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- ---------------------------------------------------------------------------
-- 2. Teto por conta nos baldes privados
-- ---------------------------------------------------------------------------
create or replace function public.storage_cota_disponivel(
  bucket_value text,
  teto_bytes bigint
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce((
    select sum(coalesce((o.metadata ->> 'size')::bigint, 0))
    from storage.objects o
    where o.bucket_id = bucket_value
      and (storage.foldername(o.name))[1] = (select auth.uid())::text
  ), 0) < teto_bytes;
$$;

comment on function public.storage_cota_disponivel(text, bigint) is
  'Quanto a pessoa já ocupa neste balde ainda cabe no teto. Teto MOLE: o '
  'último arquivo pode passar em até um arquivo, o que é aceitável e evita '
  'ter de saber o tamanho antes de aceitar. Precisa pertencer a papel com '
  'bypassrls, senão a soma volta vazia e a cota nunca dispara.';

revoke all on function public.storage_cota_disponivel(text, bigint)
  from public, anon;
grant execute on function public.storage_cota_disponivel(text, bigint)
  to authenticated;

-- 500 MB por conta por balde. Generoso para um escritório que trabalha (o
-- teto por arquivo é 26 MB, então são quase vinte anexos cheios) e curto
-- para quem está usando a conta como disco de graça.
drop policy if exists "case_documents_storage_own_folder_write" on storage.objects;
create policy "case_documents_storage_own_folder_write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'case-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.storage_cota_disponivel('case-documents', 524288000)
);

drop policy if exists "chat_attachments_storage_own_folder_write" on storage.objects;
create policy "chat_attachments_storage_own_folder_write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.storage_cota_disponivel('chat-attachments', 524288000)
);
