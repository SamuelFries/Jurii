-- Messaging integration for client, lawyer and office areas.
--
-- Run after patch_005. If you use the office area, run patches 006 and 007
-- before this one.

alter type public.conversation_type add value if not exists 'firm_internal';

create or replace function public.can_access_conversation(
  conversation_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = conversation_id_value
      and (
        c.client_id = auth.uid()
        or c.lawyer_id = auth.uid()
        or (
          c.law_firm_id is not null
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = c.law_firm_id
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          c.case_id is not null
          and public.can_access_case(c.case_id)
        )
      )
  );
$$;

create or replace function public.can_manage_conversation(
  conversation_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_conversation(conversation_id_value);
$$;

drop policy if exists "conversations_select_related" on public.conversations;
create policy "conversations_select_related"
on public.conversations for select
to authenticated
using (public.can_access_conversation(conversations.id));

drop policy if exists "conversations_insert_as_client" on public.conversations;
create policy "conversations_insert_as_client"
on public.conversations for insert
to authenticated
with check (
  client_id = auth.uid()
  or (
    law_firm_id is not null
    and exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = conversations.law_firm_id
        and lfm.profile_id = auth.uid()
        and lfm.status = 'active'
    )
  )
);

drop policy if exists "conversations_update_related" on public.conversations;
create policy "conversations_update_related"
on public.conversations for update
to authenticated
using (public.can_manage_conversation(conversations.id))
with check (public.can_manage_conversation(conversations.id));

drop policy if exists "messages_select_related" on public.messages;
create policy "messages_select_related"
on public.messages for select
to authenticated
using (public.can_access_conversation(messages.conversation_id));

drop policy if exists "messages_insert_related" on public.messages;
create policy "messages_insert_related"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_conversation(messages.conversation_id)
);

create or replace function public.set_conversation_last_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
  set
    last_message = new.body,
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  return new;
end;
$$;

drop trigger if exists messages_set_conversation_last_message on public.messages;
create trigger messages_set_conversation_last_message
after insert on public.messages
for each row execute function public.set_conversation_last_message();
