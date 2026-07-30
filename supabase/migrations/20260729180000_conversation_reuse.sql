-- Uma conversa por par cliente<->advogado (e cliente<->escritorio)
--
-- Bug (print do Samuel, 29/07): o mesmo cliente acumulava varias conversas
-- com o mesmo advogado. Causa: o lookup de "conversa existente" nos dois
-- start_or_get_* exigia `case_id is null` — quando o cliente aceita um caso,
-- respond_to_case_request grava conversations.case_id, a conversa sai do
-- radar do lookup e o proximo "Enviar mensagem" cria uma conversa nova.
-- Cada caso aceito "consumia" o chat e forcava um novo.
--
-- Decisao de produto: o historico e UM SO por par. O lookup passa a reusar a
-- conversa do par independentemente de caso vinculado (preferindo a do
-- escritorio correspondente e a mais recente, como antes). Consequencia
-- aceita: ao aceitar um segundo caso na mesma conversa, conversations.case_id
-- passa a apontar para o caso mais novo (respond_to_case_request ja
-- sobrescrevia; os consumidores de case_id sao predicados de acesso — as
-- mesmas pessoas — e o vinculo com o caso ativo mais recente e o semanticamente
-- util).
--
-- Conversas duplicadas ja existentes NAO sao fundidas (o schema permite so um
-- case_id por conversa; fundir quebraria o vinculo dos casos antigos). Elas
-- permanecem na lista; o que muda e que nenhuma NOVA duplicata nasce — o
-- "Enviar mensagem" passa a cair sempre na mais recente do par.
--
-- Corpos VERBATIM das definicoes vigentes (baseline 20260711190000:4474 e
-- :9952), mudando SO a remocao do `and case_id is null` nos dois lookups.

create or replace function public.start_or_get_law_firm_conversation(
  law_firm_id_value uuid,
  initial_message_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  firm_row public.law_firms%rowtype;
  conversation_id_value uuid;
  clean_message text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into firm_row
  from public.law_firms
  where id = law_firm_id_value
    and is_active = true;

  if not found then
    raise exception 'Law firm not found';
  end if;

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and law_firm_id = law_firm_id_value
    and lawyer_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      law_firm_id,
      title,
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      law_firm_id_value,
      firm_row.name,
      firm_row.specialty,
      'Conversa iniciada.',
      now()
    )
    returning id into conversation_id_value;
  end if;

  clean_message := nullif(trim(coalesce(initial_message_value, '')), '');

  if clean_message is not null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      conversation_id_value,
      auth.uid(),
      'client',
      clean_message
    );
  end if;

  return conversation_id_value;
end;
$$;

create or replace function public.start_or_get_lawyer_conversation(
  lawyer_profile_id_value uuid,
  initial_message_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  lawyer_row public.lawyer_profiles%rowtype;
  profile_row public.profiles%rowtype;
  conversation_id_value uuid;
  clean_message text;
  firm_id_value uuid;
  firm_joined_at_value timestamptz;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into lawyer_row
  from public.lawyer_profiles
  where id = lawyer_profile_id_value;

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  select *
  into profile_row
  from public.profiles
  where id = lawyer_profile_id_value
    and lawyer_status = 'approved';

  if not found then
    raise exception 'Lawyer profile is not approved';
  end if;

  select
    lfm.law_firm_id,
    coalesce(lfm.joined_at, lfm.created_at, now())
  into firm_id_value, firm_joined_at_value
  from public.law_firm_members lfm
  where coalesce(lfm.lawyer_id, lfm.profile_id) = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
  order by
    case
      when 'owner' = any(lfm.roles) then 1
      when 'admin' = any(lfm.roles) then 2
      else 3
    end,
    coalesce(lfm.joined_at, lfm.created_at, now()) desc
  limit 1;

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and type = 'client_firm'
    and (
      (
        firm_id_value is not null
        and law_firm_id = firm_id_value
      )
      or (
        firm_id_value is not null
        and law_firm_id is null
        and created_at >= firm_joined_at_value
      )
      or (
        firm_id_value is null
        and law_firm_id is null
      )
    )
  order by
    case when law_firm_id = firm_id_value then 0 else 1 end,
    updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      law_firm_id,
      title,
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      firm_id_value,
      profile_row.full_name,
      lawyer_row.primary_area,
      'Conversa iniciada.',
      now()
    )
    returning id into conversation_id_value;
  elsif firm_id_value is not null then
    update public.conversations
    set
      law_firm_id = firm_id_value,
      updated_at = now()
    where id = conversation_id_value
      and law_firm_id is null;
  end if;

  clean_message := nullif(trim(coalesce(initial_message_value, '')), '');

  if clean_message is not null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      conversation_id_value,
      auth.uid(),
      'client',
      clean_message
    );
  end if;

  return conversation_id_value;
end;
$$;

revoke all on function public.start_or_get_law_firm_conversation(uuid, text)
  from public, anon;
grant execute on function public.start_or_get_law_firm_conversation(uuid, text)
  to authenticated;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
  from public, anon;
grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
  to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificacao pos-push (SQL Editor):
--   select prosrc from pg_proc
--   where proname = 'start_or_get_lawyer_conversation';  -- sem 'case_id is null'
-- ---------------------------------------------------------------------------
