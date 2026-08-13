-- A equipe da Jurii revisa verificações, e a autoridade continua no BANCO.
--
-- O PROBLEMA: approve_/reject_lawyer_verification e as irmãs do escritório
-- são service_role, e NADA as chama (medido em 13/08/2026: nem app, nem
-- edge function, nem webapp). As 81 aprovações que existem foram feitas
-- fora do produto, pelo dashboard. Com o webapp agora enviando verificação
-- de OAB e pedido de escritório, começam a chegar submissões pendentes sem
-- lugar nenhum para analisá-las.
--
-- O CAMINHO NÃO ESCOLHIDO: pôr a service_role no servidor do webapp e
-- checar "é da equipe?" no código. Essa chave passa por cima da RLS de
-- TODAS as tabelas; um erro de dependência, de log ou de rota deixaria de
-- ser um bug e viraria acesso total. E a decisão de quem manda sairia do
-- banco para o código do app, o que contraria a regra que este produto
-- seguiu até aqui: quem decide é o servidor, do lado do dado.
--
-- O CAMINHO DAQUI: a equipe vira um papel no banco. O webapp continua
-- falando com o Supabase como qualquer pessoa autenticada, e são estas
-- funções que abrem a porta, depois de conferir quem bate.

-- ---------------------------------------------------------------------------
-- Quem é da equipe
-- ---------------------------------------------------------------------------

create table if not exists public.jurii_staff (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  note text
);

alter table public.jurii_staff enable row level security;

-- SEM POLICY, de propósito: com RLS ligada e nenhuma policy permissiva,
-- nenhum cliente lê, insere ou apaga esta tabela. Entrar na equipe é ato
-- deliberado por migration ou dashboard, e não algo que uma falha na
-- aplicação possa provocar. Nem a própria pessoa consegue se listar.

comment on table public.jurii_staff is
  'Quem pode revisar verificações. RLS sem policy: invisível e imutável por qualquer cliente.';

create or replace function public.is_jurii_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.jurii_staff where profile_id = auth.uid()
  );
$$;

revoke all on function public.is_jurii_staff() from public;
grant execute on function public.is_jurii_staff() to authenticated;

-- ---------------------------------------------------------------------------
-- A fila
-- ---------------------------------------------------------------------------

create or replace function public.fetch_pending_verifications()
returns table (
  kind text,
  id uuid,
  subject_id uuid,
  person_name text,
  person_email text,
  title text,
  detail text,
  status text,
  submitted_at timestamptz,
  documents jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  return query
  -- Advogados
  select
    'lawyer'::text,
    lv.id,
    lv.user_id,
    coalesce(p.full_name, 'Sem nome'),
    u.email::text,
    'OAB ' || coalesce(lv.oab_number, '?') || '/' || coalesce(lv.oab_state::text, '?'),
    coalesce(lv.practice_area, 'Sem área informada'),
    lv.status::text,
    lv.submitted_at,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'tipo', vd.document_type,
            'titulo', vd.title,
            'caminho', vd.storage_path,
            'bucket', 'verification-documents'
          )
          order by vd.document_type
        )
        from public.verification_documents vd
        where vd.verification_id = lv.id
      ),
      '[]'::jsonb
    )
  from public.lawyer_verifications lv
  join public.profiles p on p.id = lv.user_id
  left join auth.users u on u.id = lv.user_id
  where lv.status = 'pending'

  union all

  -- Escritórios
  select
    'law_firm'::text,
    lfv.id,
    lfv.owner_profile_id,
    coalesce(p.full_name, 'Sem nome'),
    coalesce(lfv.email, u.email::text),
    coalesce(lfv.firm_name, 'Escritório sem nome'),
    'CNPJ ' || coalesce(lfv.cnpj, '?'),
    lfv.status::text,
    lfv.created_at,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'tipo', lvd.document_type,
            'titulo', lvd.title,
            'caminho', lvd.storage_path,
            -- MESMO balde do advogado: law_firm_verification_documents
            -- guarda o caminho devolvido por documentStorage.upload, que
            -- escreve em verification-documents. O balde law-firm-avatars
            -- guarda só o LOGOTIPO, que é outra coisa.
            'bucket', 'verification-documents'
          )
          order by lvd.document_type
        )
        from public.law_firm_verification_documents lvd
        where lvd.verification_id = lfv.id
      ),
      '[]'::jsonb
    )
  from public.law_firm_verifications lfv
  join public.profiles p on p.id = lfv.owner_profile_id
  left join auth.users u on u.id = lfv.owner_profile_id
  where lfv.status = 'pending'

  order by 9 asc nulls last;
end;
$$;

revoke all on function public.fetch_pending_verifications() from public;
grant execute on function public.fetch_pending_verifications() to authenticated;

-- ---------------------------------------------------------------------------
-- A decisão
-- ---------------------------------------------------------------------------

-- Estas duas NÃO reimplementam a regra: chamam as funções que já existem e
-- que o app usa desde a baseline. Ter uma segunda cópia da aprovação seria
-- garantir que as duas divergissem com o tempo.
--
-- Elas são SECURITY DEFINER e o dono é postgres, então alcançam as
-- service_role sem que o revisor precise dessa chave: o EXECUTE é checado
-- contra o dono da função, não contra quem chamou.
--
-- O reviewer_id_value vai preenchido com auth.uid(): decisão sobre a
-- carteira profissional de alguém tem que dizer quem decidiu.

create or replace function public.review_lawyer_verification(
  verification_id_value uuid,
  approve_value boolean,
  reason_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  if approve_value then
    return public.approve_lawyer_verification(verification_id_value, auth.uid());
  end if;

  if nullif(trim(coalesce(reason_value, '')), '') is null then
    raise exception 'Rejection reason is required';
  end if;

  return public.reject_lawyer_verification(
    verification_id_value,
    reason_value,
    auth.uid()
  );
end;
$$;

revoke all on function public.review_lawyer_verification(uuid, boolean, text) from public;
grant execute on function public.review_lawyer_verification(uuid, boolean, text) to authenticated;

create or replace function public.review_law_firm_verification(
  verification_id_value uuid,
  approve_value boolean,
  reason_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review verifications';
  end if;

  if approve_value then
    return public.approve_law_firm_verification(verification_id_value, auth.uid());
  end if;

  if nullif(trim(coalesce(reason_value, '')), '') is null then
    raise exception 'Rejection reason is required';
  end if;

  return public.reject_law_firm_verification(
    verification_id_value,
    reason_value,
    auth.uid()
  );
end;
$$;

revoke all on function public.review_law_firm_verification(uuid, boolean, text) from public;
grant execute on function public.review_law_firm_verification(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Os documentos
-- ---------------------------------------------------------------------------

-- Sem isto, a equipe veria a fila e não conseguiria abrir o RG: o bucket é
-- privado e a URL assinada só sai para quem consegue LER o objeto. A leitura
-- é restrita a quem é da equipe; ninguém mais ganha nada.

drop policy if exists "jurii_staff_reads_verification_documents" on storage.objects;
create policy "jurii_staff_reads_verification_documents"
  on storage.objects for select
  to authenticated
  using (
    bucket_id in ('verification-documents', 'law-firm-avatars')
    and public.is_jurii_staff()
  );

notify pgrst, 'reload schema';
