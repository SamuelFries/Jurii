-- Security hardening round 2
--
-- Fecha as pendencias de seguranca restantes antes do piloto:
--   1. limita SELECT direto em profiles a colunas publicas;
--   2. restringe o roster de escritorios aos proprios membros;
--   3. remove autoridade herdada de verificacoes antigas de escritorio;
--   4. obriga criacao de conversas por RPC e fecha escrita direta na agenda;
--   5. impede apagar anexo de chat depois que ele foi entregue;
--   6. remove o oraculo direto do convite por OAB, limita tentativas e
--      impede promocao de status.

-- ---------------------------------------------------------------------------
-- 1. PII de profiles
--
-- RLS filtra linhas, nao colunas. A policy can_select_profile permitia que uma
-- contraparte de caso/conversa lesse a linha inteira, incluindo email, CPF e
-- telefone. O acesso direto agora expoe apenas o retrato publico. O titular
-- carrega a propria linha completa por fetch_current_profile() e a atualiza
-- por upsert_current_profile(), que fixa o alvo no usuario autenticado.
-- ---------------------------------------------------------------------------

revoke select on public.profiles from authenticated;

grant select (
  id,
  full_name,
  initials,
  avatar_url,
  lawyer_status,
  member_since,
  deleted_at,
  deleted_display_name
)
on public.profiles to authenticated;

-- A escrita de identidade/PII tambem passa pela RPC abaixo. O unico update
-- direto mantido e o avatar, usado depois do upload da foto profissional.
revoke insert, update on public.profiles from authenticated;

grant update (avatar_url)
on public.profiles to authenticated;

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
to authenticated
using (
  id = auth.uid()
  and deleted_at is null
)
with check (
  id = auth.uid()
  and deleted_at is null
);

create or replace function public.fetch_current_profile()
returns table (
  id uuid,
  full_name text,
  email text,
  initials text,
  cpf text,
  phone text,
  avatar_url text,
  lawyer_status public.lawyer_status,
  member_since date,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz,
  deleted_display_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    p.email,
    p.initials,
    p.cpf,
    p.phone,
    p.avatar_url,
    p.lawyer_status,
    p.member_since,
    p.created_at,
    p.updated_at,
    p.deleted_at,
    p.deleted_display_name
  from public.profiles p
  where auth.uid() is not null
    and p.id = auth.uid();
$$;

revoke all on function public.fetch_current_profile()
from public, anon;

grant execute on function public.fetch_current_profile()
to authenticated;

-- O upsert direto do PostgREST precisa de SELECT nas colunas usadas pelo
-- ON CONFLICT e, por isso, deixou de ser compativel com o bloqueio de PII.
-- Esta RPC mantem a escrita no proprio perfil sem devolver nem liberar dados
-- privados de nenhuma linha. O email vem exclusivamente de auth.users e
-- perfis ja excluidos nao podem ser reativados.
create or replace function public.upsert_current_profile(
  full_name_value text,
  cpf_value text default null,
  phone_value text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id_value uuid := auth.uid();
  auth_email_value text;
  normalized_name_value text;
  normalized_initials_value text;
  name_parts text[];
begin
  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_name_value := nullif(
    btrim(
      regexp_replace(
        coalesce(full_name_value, ''),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ),
    ''
  );

  if normalized_name_value is null then
    raise exception 'Full name is required';
  end if;

  select nullif(trim(auth_user.email), '')
  into auth_email_value
  from auth.users auth_user
  where auth_user.id = profile_id_value;

  if not found or auth_email_value is null then
    raise exception 'Authenticated user was not found';
  end if;

  name_parts := regexp_split_to_array(normalized_name_value, '[[:space:]]+');
  normalized_initials_value := upper(
    left(name_parts[1], 1)
    || case
      when array_length(name_parts, 1) > 1
        then left(name_parts[array_upper(name_parts, 1)], 1)
      else ''
    end
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    cpf,
    phone
  )
  values (
    profile_id_value,
    normalized_name_value,
    auth_email_value,
    normalized_initials_value,
    nullif(trim(cpf_value), ''),
    nullif(trim(phone_value), '')
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    initials = excluded.initials,
    cpf = coalesce(excluded.cpf, public.profiles.cpf),
    phone = coalesce(excluded.phone, public.profiles.phone)
  where public.profiles.deleted_at is null;

  if not found then
    raise exception 'Deleted profile cannot be restored';
  end if;
end;
$$;

revoke all on function public.upsert_current_profile(
  text, text, text
)
from public, anon;

grant execute on function public.upsert_current_profile(
  text, text, text
)
to authenticated;

-- Perfis publicos de colegas do mesmo escritorio continuam disponiveis para
-- montar a equipe, mas somente nas colunas publicas concedidas acima.
create or replace function public.can_select_profile(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles target_profile
    where target_profile.id = profile_id_value
      and target_profile.deleted_at is null
  )
  and (
    profile_id_value = auth.uid()
    or exists (
      select 1
      from public.legal_cases lc
      where (
        lc.client_id = auth.uid()
        and lc.assigned_lawyer_id = profile_id_value
      )
      or (
        lc.assigned_lawyer_id = auth.uid()
        and lc.client_id = profile_id_value
      )
    )
    or exists (
      select 1
      from public.case_participants cp
      where cp.profile_id = profile_id_value
        and public.can_access_case(cp.case_id)
    )
    or exists (
      select 1
      from public.conversations c
      where (
        c.client_id = auth.uid()
        and c.lawyer_id = profile_id_value
      )
      or (
        c.lawyer_id = auth.uid()
        and c.client_id = profile_id_value
      )
    )
    or exists (
      select 1
      from public.law_firm_members requester
      join public.law_firm_members target
        on target.law_firm_id = requester.law_firm_id
      where requester.profile_id = auth.uid()
        and requester.status = 'active'
        and target.status = 'active'
        and coalesce(target.profile_id, target.lawyer_id) = profile_id_value
    )
  );
$$;

revoke all on function public.can_select_profile(uuid)
from public, anon;

grant execute on function public.can_select_profile(uuid)
to authenticated;

-- Mantem o contrato consumido pelo app, mas o email da contraparte nao sai do
-- servidor. A comunicacao deve permanecer dentro do chat da Jurii.
create or replace function public.fetch_chat_profile(
  profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  email text,
  initials text,
  member_since date,
  lawyer_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.full_name,
    ''::text as email,
    p.initials,
    p.member_since,
    p.lawyer_status::text
  from public.profiles p
  where p.id = profile_id_value
    and p.deleted_at is null
    and public.can_select_profile(p.id)
  limit 1;
$$;

revoke all on function public.fetch_chat_profile(uuid)
from public, anon;

grant execute on function public.fetch_chat_profile(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Roster privado
--
-- Antes, qualquer autenticado podia ler law_firm_members de todo escritorio
-- ativo. Agora cada pessoa ve a propria linha/convite e membros ativos veem a
-- equipe do proprio escritorio. Listagens publicas futuras devem usar RPC com
-- campos explicitamente permitidos.
-- ---------------------------------------------------------------------------

-- Mantem a assinatura usada pelo codigo legado, mas impede que um chamador
-- forneca o UUID de outra pessoa para consultar seus cargos.
create or replace function public.current_law_firm_member_roles(
  law_firm_id_value uuid,
  profile_id_value uuid default auth.uid()
)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null or profile_id_value is distinct from auth.uid()
      then '{}'::text[]
    else coalesce((
      select lfm.roles
      from public.law_firm_members lfm
      where lfm.law_firm_id = law_firm_id_value
        and lfm.profile_id = auth.uid()
        and lfm.status = 'active'
      limit 1
    ), '{}'::text[])
  end;
$$;

revoke all on function public.current_law_firm_member_roles(uuid, uuid)
from public, anon;

grant execute on function public.current_law_firm_member_roles(uuid, uuid)
to authenticated;

revoke all on function public.has_law_firm_role(uuid, text, uuid)
from public, anon;

grant execute on function public.has_law_firm_role(uuid, text, uuid)
to authenticated;

drop policy if exists "law_firm_members_read_related"
on public.law_firm_members;

create policy "law_firm_members_read_related"
on public.law_firm_members for select
to authenticated
using (
  profile_id = auth.uid()
  or lawyer_id = auth.uid()
  or pending_lawyer_id = auth.uid()
  or coalesce(
    array_length(
      public.current_law_firm_member_roles(law_firm_id, auth.uid()),
      1
    ),
    0
  ) > 0
);

-- Escritas de equipe ja passam pelas RPCs de convite, resposta e edicao de
-- cargos. Remover grants diretos reduz a superficie sem afetar essas funcoes
-- SECURITY DEFINER.
revoke insert, update on public.law_firm_members from authenticated;

-- ---------------------------------------------------------------------------
-- 3. Autoridade somente por membership ativo
--
-- A verificacao aprovada prova que o escritorio existe; ela nao e uma fonte
-- permanente de autorizacao. Dono/admin/secretaria precisam constar em
-- law_firm_members com status active.
-- ---------------------------------------------------------------------------

create or replace function public.is_active_law_firm_manager(
  law_firm_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.roles && array['owner', 'admin']::text[]
  );
$$;

create or replace function public.is_active_law_firm_case_manager(
  law_firm_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.roles && array['owner', 'admin', 'secretary']::text[]
  );
$$;

create or replace function public.can_recommend_law_firm_lawyer(
  law_firm_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.roles && array['owner', 'admin', 'lawyer', 'secretary']::text[]
  );
$$;

revoke all on function public.is_active_law_firm_manager(uuid)
from public, anon;

grant execute on function public.is_active_law_firm_manager(uuid)
to authenticated;

revoke all on function public.is_active_law_firm_case_manager(uuid)
from public, anon;

grant execute on function public.is_active_law_firm_case_manager(uuid)
to authenticated;

revoke all on function public.can_recommend_law_firm_lawyer(uuid)
from public, anon;

grant execute on function public.can_recommend_law_firm_lawyer(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Conversas e agenda
--
-- start_or_get_lawyer_conversation e start_or_get_law_firm_conversation ja
-- validam o destino no servidor. Remove-se o INSERT/UPDATE direto que deixava
-- o cliente fabricar uma conversa apontando para qualquer UUID.
--
-- A agenda ainda e somente leitura no app. Ate existir uma RPC de agendamento
-- que valide conversa/caso, nenhuma das partes pode criar ou alterar reunioes
-- diretamente pelo PostgREST.
-- ---------------------------------------------------------------------------

drop policy if exists "conversations_insert_as_client"
on public.conversations;

drop policy if exists "conversations_update_related"
on public.conversations;

revoke insert, update on public.conversations from authenticated;

drop policy if exists "appointments_insert_as_related"
on public.appointments;

drop policy if exists "appointments_update_related"
on public.appointments;

revoke insert, update on public.appointments from authenticated;

-- ---------------------------------------------------------------------------
-- 5. Anexos entregues sao imutaveis no Storage
--
-- O upload continua removivel durante rollback. Depois que storage_path ganha
-- uma linha em message_attachments, nem mesmo o uploader pode apagar o objeto.
-- ---------------------------------------------------------------------------

create or replace function public.can_delete_unlinked_chat_attachment(
  storage_path_value text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and (storage.foldername(coalesce(storage_path_value, '')))[1] = auth.uid()::text
    and not exists (
      select 1
      from public.message_attachments ma
      where ma.storage_path = storage_path_value
    );
$$;

revoke all on function public.can_delete_unlinked_chat_attachment(text)
from public, anon;

grant execute on function public.can_delete_unlinked_chat_attachment(text)
to authenticated;

drop policy if exists "chat_attachments_storage_own_folder_delete"
on storage.objects;

drop policy if exists "chat_attachments_storage_unlinked_own_delete"
on storage.objects;

create policy "chat_attachments_storage_unlinked_own_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'chat-attachments'
  and public.can_delete_unlinked_chat_attachment(storage.objects.name)
);

-- ---------------------------------------------------------------------------
-- 6. Convite por OAB com resposta opaca, rate limit e sem promocao de status
--
-- Para chamadas autorizadas, entradas bem-formadas e dentro do rate limit, a
-- funcao sempre devolve um UUID opaco novo. O retorno direto nao revela se a
-- OAB existe, esta aprovada, ja esta ativa ou ja foi convidada. Para alvos
-- inelegiveis retorna-se um UUID sem persistir convite.
--
-- Importante: convite nao atualiza profiles.lawyer_status e nao cria
-- lawyer_profiles. Isso pertence exclusivamente a aprovacao da verificacao.
-- ---------------------------------------------------------------------------

create table if not exists public.law_firm_invitation_attempts (
  id bigint generated always as identity primary key,
  actor_profile_id uuid not null references public.profiles(id) on delete cascade,
  law_firm_id uuid not null references public.law_firms(id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index if not exists law_firm_invitation_attempts_actor_time_idx
on public.law_firm_invitation_attempts(actor_profile_id, attempted_at desc);

alter table public.law_firm_invitation_attempts enable row level security;

revoke all on public.law_firm_invitation_attempts from anon, authenticated;

-- Convite e aceite ficam separados no tempo. Revalida o status profissional
-- no aceite para que uma recusa posterior ao convite nao ative o membership.
create or replace function public.respond_to_law_firm_invite(
  membership_id_value uuid,
  accepted_value boolean
)
returns public.law_firm_member_status
language plpgsql
security definer
set search_path = public
as $$
declare
  membership_row public.law_firm_members%rowtype;
  invitee_profile_id uuid;
  next_status public.law_firm_member_status;
  is_manager_membership boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into membership_row
  from public.law_firm_members
  where id = membership_id_value
  for update;

  if not found then
    raise exception 'Invite not found';
  end if;

  -- pending_lawyer_id cobre convites legados feitos sobre uma membership
  -- administrativa; profile_id/lawyer_id cobrem os formatos atuais e antigos.
  -- IS DISTINCT FROM falha fechado quando a linha nao identifica destinatario.
  invitee_profile_id := coalesce(
    membership_row.pending_lawyer_id,
    membership_row.profile_id,
    membership_row.lawyer_id
  );

  if invitee_profile_id is distinct from auth.uid() then
    raise exception 'Only the invited lawyer can respond to this invite';
  end if;

  if membership_row.status <> 'invited'
      and membership_row.lawyer_invite_status <> 'invited' then
    raise exception 'Invite is no longer pending';
  end if;

  if accepted_value and not exists (
    select 1
    from public.profiles p
    join public.lawyer_profiles lp on lp.id = p.id
    where p.id = auth.uid()
      and p.lawyer_status = 'approved'
      and p.deleted_at is null
  ) then
    raise exception 'Invite is not eligible for acceptance';
  end if;

  is_manager_membership :=
    membership_row.status = 'active'
    and membership_row.roles && array['owner', 'admin', 'secretary']::text[];

  next_status := case
    when accepted_value then 'active'::public.law_firm_member_status
    else 'disabled'::public.law_firm_member_status
  end;

  if accepted_value then
    update public.law_firm_members
    set
      status = case
        when is_manager_membership then status
        else 'active'::public.law_firm_member_status
      end,
      roles = case
        when is_manager_membership then
          public.normalize_law_firm_member_roles(roles || array['lawyer']::text[])
        else array['lawyer']::text[]
      end,
      lawyer_id = coalesce(pending_lawyer_id, lawyer_id, profile_id),
      pending_lawyer_id = null,
      lawyer_invite_status = 'active'
    where id = membership_id_value;
  else
    update public.law_firm_members
    set
      status = case
        when is_manager_membership then status
        else 'disabled'::public.law_firm_member_status
      end,
      lawyer_id = case
        when is_manager_membership
             and lawyer_invite_status = 'invited'
             and pending_lawyer_id is not null then null
        else lawyer_id
      end,
      pending_lawyer_id = null,
      lawyer_invite_status = 'disabled'
    where id = membership_id_value;
  end if;

  update public.notifications
  set
    read_at = coalesce(read_at, now()),
    metadata = metadata ||
      jsonb_build_object(
        'membership_id', membership_id_value,
        'invite_status', case when accepted_value then 'accepted' else 'declined' end,
        'lawyer_invite_status', case when accepted_value then 'active' else 'disabled' end
      )
  where recipient_profile_id = auth.uid()
    and type = 'team_invite'
    and metadata ->> 'membership_id' = membership_id_value::text;

  return next_status;
end;
$$;

revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
from public, anon;

grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
to authenticated;

-- Mantem o ciclo de recusa coerente: convites ainda nao aceitos deixam de ser
-- acionaveis assim que o perfil profissional volta para client.
create or replace function public.reject_lawyer_verification(
  verification_id_value uuid,
  reason_value text default null,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.lawyer_verifications%rowtype;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  update public.lawyer_verifications
  set
    status = 'rejected',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = nullif(trim(coalesce(reason_value, '')), '')
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'client'
  where id = verification_row.user_id;

  -- Revoga tambem a capacidade profissional dentro dos escritorios. Papeis
  -- administrativos independentes (owner/admin/secretary) sao preservados;
  -- membership exclusivamente de advogado e desativado.
  update public.law_firm_members
  set
    status = case
      when coalesce(
        array_length(array_remove(roles, 'lawyer'), 1),
        0
      ) = 0 then 'disabled'::public.law_firm_member_status
      else status
    end,
    roles = case
      when coalesce(
        array_length(array_remove(roles, 'lawyer'), 1),
        0
      ) = 0 then roles
      else public.normalize_law_firm_member_roles(
        array_remove(roles, 'lawyer')
      )
    end,
    lawyer_id = null,
    pending_lawyer_id = null,
    lawyer_invite_status = 'disabled'
  where (
      profile_id = verification_row.user_id
      or lawyer_id = verification_row.user_id
      or pending_lawyer_id = verification_row.user_id
    )
    and (
      'lawyer' = any(roles)
      or lawyer_invite_status = 'invited'
    );

  return verification_row.user_id;
end;
$$;

revoke all on function public.reject_lawyer_verification(uuid, text, uuid)
from public, anon, authenticated;

grant execute on function public.reject_lawyer_verification(uuid, text, uuid)
to service_role;

create or replace function public.invite_verified_lawyer_to_law_firm(
  law_firm_id_value uuid,
  oab_state_value text,
  oab_number_value text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  latest_verification public.lawyer_verifications%rowtype;
  existing_member public.law_firm_members%rowtype;
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
  target_profile_id uuid;
  existing_is_manager boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can invite lawyers';
  end if;

  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')));
  normalized_oab_number := regexp_replace(
    upper(coalesce(oab_number_value, '')),
    '[^A-Z0-9]',
    '',
    'g'
  );

  if length(normalized_oab_state) <> 2 or normalized_oab_number = '' then
    raise exception 'Invalid OAB';
  end if;

  -- Serializa tentativas do mesmo ator para que chamadas concorrentes nao
  -- atravessem juntas o contador antes do INSERT.
  perform pg_catalog.pg_advisory_xact_lock(
    17001,
    pg_catalog.hashtext(auth.uid()::text)
  );

  if (
    select count(*)
    from public.law_firm_invitation_attempts attempt
    where attempt.actor_profile_id = auth.uid()
      and attempt.attempted_at >= now() - interval '1 hour'
  ) >= 20 then
    raise exception 'Too many invite attempts. Try again later';
  end if;

  insert into public.law_firm_invitation_attempts (
    actor_profile_id,
    law_firm_id
  )
  values (auth.uid(), law_firm_id_value);

  -- Dois managers do mesmo escritorio tambem podem tentar a mesma OAB ao
  -- mesmo tempo. Este lock torna a criacao/reutilizacao do convite atomica;
  -- colisoes de hash apenas serializam escopos independentes, sem liberar dado.
  perform pg_catalog.pg_advisory_xact_lock(
    17002,
    pg_catalog.hashtext(
      law_firm_id_value::text || ':' ||
      normalized_oab_state || ':' ||
      normalized_oab_number
    )
  );

  -- Primeiro resolve o perfil profissional aprovado pela OAB unica. Assim uma
  -- solicitacao posterior feita por terceiro com OAB alheia nao bloqueia o
  -- profissional legitimo.
  select lp.id
  into target_profile_id
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where p.lawyer_status = 'approved'
    and p.deleted_at is null
    and upper(trim(lp.oab_state)) = normalized_oab_state
    and regexp_replace(
      upper(coalesce(lp.oab_number, '')),
      '[^A-Z0-9]',
      '',
      'g'
    ) = normalized_oab_number
  order by lp.approved_at desc nulls last, lp.created_at desc, lp.id
  limit 1;

  if not found then
    return gen_random_uuid();
  end if;

  -- Em seguida considera a decisao mais recente somente daquele titular. Uma
  -- recusa posterior nunca pode reutilizar uma aprovacao antiga.
  select lv.*
  into latest_verification
  from public.lawyer_verifications lv
  where lv.user_id = target_profile_id
    and upper(trim(lv.oab_state)) = normalized_oab_state
    and regexp_replace(
      upper(coalesce(lv.oab_number, '')),
      '[^A-Z0-9]',
      '',
      'g'
    ) = normalized_oab_number
  order by
    coalesce(lv.reviewed_at, lv.submitted_at, lv.created_at) desc,
    lv.created_at desc,
    lv.id desc
  limit 1;

  if not found or latest_verification.status <> 'approved' then
    return gen_random_uuid();
  end if;

  select *
  into existing_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_profile_id
      or lawyer_id = target_profile_id
      or pending_lawyer_id = target_profile_id
    )
  limit 1;

  -- Resposta idempotente e indistinguivel: nao revela se o alvo ja esta ativo
  -- ou se ja recebeu convite.
  if found
      and existing_member.lawyer_id = target_profile_id
      and existing_member.lawyer_invite_status = 'active' then
    return gen_random_uuid();
  end if;

  if found
      and existing_member.lawyer_invite_status = 'invited'
      and (
        existing_member.lawyer_id = target_profile_id
        or existing_member.pending_lawyer_id = target_profile_id
      ) then
    return gen_random_uuid();
  end if;

  if not found then
    insert into public.law_firm_members (
      law_firm_id,
      lawyer_id,
      profile_id,
      role,
      member_role,
      roles,
      status,
      lawyer_invite_status,
      pending_lawyer_id
    )
    values (
      law_firm_id_value,
      target_profile_id,
      target_profile_id,
      'lawyer',
      'lawyer',
      array['lawyer']::text[],
      'invited',
      'invited',
      null
    )
    returning id into membership_id_value;
  else
    existing_is_manager :=
      existing_member.status = 'active'
      and existing_member.roles && array['owner', 'admin', 'secretary']::text[];

    update public.law_firm_members
    set
      profile_id = target_profile_id,
      lawyer_id = case
        when existing_is_manager then lawyer_id
        else target_profile_id
      end,
      pending_lawyer_id = case
        when existing_is_manager then target_profile_id
        else null
      end,
      lawyer_invite_status = 'invited',
      roles = case
        when existing_is_manager then roles
        else array['lawyer']::text[]
      end,
      status = case
        when existing_is_manager then status
        else 'invited'::public.law_firm_member_status
      end
    where id = existing_member.id
    returning id into membership_id_value;
  end if;

  select name
  into firm_name_value
  from public.law_firms
  where id = law_firm_id_value;

  insert into public.notifications (
    recipient_profile_id,
    actor_profile_id,
    law_firm_id,
    type,
    title,
    body,
    metadata
  )
  values (
    target_profile_id,
    auth.uid(),
    law_firm_id_value,
    'team_invite',
    'Convite para escritorio',
    coalesce(firm_name_value, 'Um escritorio') ||
      ' convidou voce para integrar a equipe.',
    jsonb_build_object(
      'membership_id', membership_id_value,
      'invite_status', null,
      'lawyer_invite_status', 'invited'
    )
  );

  return gen_random_uuid();
end;
$$;

revoke all on function public.invite_verified_lawyer_to_law_firm(
  uuid,
  text,
  text
)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(
  uuid,
  text,
  text
)
to authenticated;

notify pgrst, 'reload schema';
