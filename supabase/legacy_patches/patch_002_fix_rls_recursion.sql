-- Run this patch if you see:
-- "infinite recursion detected in policy for relation legal_cases"
--
-- It replaces recursive RLS policies with SECURITY DEFINER helper functions.

create or replace function public.can_access_case(case_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.legal_cases lc
      where lc.id = case_id_value
        and (
          lc.client_id = auth.uid()
          or lc.assigned_lawyer_id = auth.uid()
        )
    )
    or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = case_id_value
        and cp.profile_id = auth.uid()
    );
$$;

create or replace function public.can_manage_case(case_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.legal_cases lc
      where lc.id = case_id_value
        and (
          lc.client_id = auth.uid()
          or lc.assigned_lawyer_id = auth.uid()
        )
    )
    or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = case_id_value
        and cp.profile_id = auth.uid()
        and cp.role in ('lawyer', 'firm_member')
    );
$$;

create or replace function public.can_access_conversation(conversation_id_value uuid)
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
          c.case_id is not null
          and public.can_access_case(c.case_id)
        )
      )
  );
$$;

create or replace function public.can_select_profile(profile_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
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
    );
$$;

drop policy if exists "profiles_select_related_case_or_conversation" on public.profiles;
create policy "profiles_select_related_case_or_conversation"
on public.profiles for select
to authenticated
using (public.can_select_profile(profiles.id));

drop policy if exists "legal_cases_select_related" on public.legal_cases;
create policy "legal_cases_select_related"
on public.legal_cases for select
to authenticated
using (public.can_access_case(legal_cases.id));

drop policy if exists "legal_cases_update_related" on public.legal_cases;
create policy "legal_cases_update_related"
on public.legal_cases for update
to authenticated
using (public.can_manage_case(legal_cases.id));

drop policy if exists "case_participants_select_related" on public.case_participants;
create policy "case_participants_select_related"
on public.case_participants for select
to authenticated
using (
  profile_id = auth.uid()
  or public.can_access_case(case_participants.case_id)
);

drop policy if exists "case_documents_select_related" on public.case_documents;
create policy "case_documents_select_related"
on public.case_documents for select
to authenticated
using (
  uploaded_by = auth.uid()
  or public.can_access_case(case_documents.case_id)
);

drop policy if exists "case_documents_insert_related" on public.case_documents;
create policy "case_documents_insert_related"
on public.case_documents for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and public.can_access_case(case_documents.case_id)
);

drop policy if exists "conversations_select_related" on public.conversations;
create policy "conversations_select_related"
on public.conversations for select
to authenticated
using (public.can_access_conversation(conversations.id));

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

drop policy if exists "case_documents_storage_related_read" on storage.objects;
create policy "case_documents_storage_related_read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'case-documents'
  and exists (
    select 1
    from public.case_documents cd
    where cd.storage_path = storage.objects.name
      and public.can_access_case(cd.case_id)
  )
);
