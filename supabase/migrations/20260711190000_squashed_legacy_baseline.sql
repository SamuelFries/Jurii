-- Jurii Supabase baseline migration (squashed legacy SQL).
-- Generated on 2026-07-11 from supabase/schema.sql + patch_001 through patch_045.
-- Use this for new environments. Existing production already had these changes applied manually.
-- Future database changes should be new timestamped files in supabase/migrations/.


-- ============================================================================
-- Source: supabase/schema.sql
-- ============================================================================

-- Jurii Supabase schema
-- Paste this file into Supabase SQL Editor and run it once on a new project.
-- It creates the app tables, enums, indexes, Storage buckets and RLS policies.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'lawyer_status') then
    create type public.lawyer_status as enum ('client', 'pending', 'approved');
  end if;

  if not exists (select 1 from pg_type where typname = 'verification_status') then
    create type public.verification_status as enum ('draft', 'pending', 'approved', 'rejected');
  end if;

  if not exists (select 1 from pg_type where typname = 'verification_document_type') then
    create type public.verification_document_type as enum ('identity', 'oab_card', 'professional_photo');
  end if;

  if not exists (select 1 from pg_type where typname = 'lawyer_case_status') then
    create type public.lawyer_case_status as enum ('open', 'new_message', 'deadline', 'closed');
  end if;

  if not exists (select 1 from pg_type where typname = 'case_participant_role') then
    create type public.case_participant_role as enum ('client', 'lawyer', 'firm_member');
  end if;

  if not exists (select 1 from pg_type where typname = 'conversation_type') then
    create type public.conversation_type as enum ('client_firm', 'case_thread');
  end if;

  if not exists (select 1 from pg_type where typname = 'message_sender_type') then
    create type public.message_sender_type as enum ('client', 'lawyer', 'system');
  end if;

  if not exists (select 1 from pg_type where typname = 'appointment_role') then
    create type public.appointment_role as enum ('client', 'lawyer');
  end if;

  if not exists (select 1 from pg_type where typname = 'appointment_status') then
    create type public.appointment_status as enum ('confirmed', 'pending', 'done', 'cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'law_firm_member_role') then
    create type public.law_firm_member_role as enum ('owner', 'admin', 'secretary', 'lawyer', 'intern');
  end if;

  if not exists (select 1 from pg_type where typname = 'law_firm_member_status') then
    create type public.law_firm_member_status as enum ('invited', 'active', 'disabled');
  end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  full_name_value text;
begin
  full_name_value := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    split_part(new.email, '@', 1),
    'Usuário Jurii'
  );

  insert into public.profiles (id, full_name, email, initials)
  values (
    new.id,
    full_name_value,
    new.email,
    upper(left(full_name_value, 1))
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  initials text not null,
  cpf text,
  phone text,
  avatar_url text,
  lawyer_status public.lawyer_status not null default 'client',
  member_since date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create table if not exists public.legal_categories (
  id text primary key,
  title text not null,
  icon_name text not null,
  is_highlighted boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.law_firms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  initials text not null,
  specialty text not null,
  practice_areas text[] not null default '{}'::text[],
  description text,
  rating numeric(2, 1) not null default 0 check (rating >= 0 and rating <= 5),
  reviews_count int not null default 0 check (reviews_count >= 0),
  distance_label text,
  avatar_type text not null default 'blue',
  phone text,
  email text,
  website_url text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.law_firm_categories (
  law_firm_id uuid not null references public.law_firms(id) on delete cascade,
  category_id text not null references public.legal_categories(id) on delete restrict,
  primary key (law_firm_id, category_id)
);

create table if not exists public.lawyer_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,
  oab_number text not null,
  oab_state char(2) not null,
  primary_area text not null,
  practice_areas text[] not null default '{}'::text[],
  bio text,
  professional_photo_url text,
  is_available boolean not null default true,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (oab_number, oab_state)
);

create table if not exists public.law_firm_members (
  id uuid primary key default gen_random_uuid(),
  law_firm_id uuid not null references public.law_firms(id) on delete cascade,
  lawyer_id uuid references public.lawyer_profiles(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete cascade,
  role text not null default 'lawyer',
  member_role public.law_firm_member_role not null default 'lawyer',
  roles text[] not null default array['lawyer']::text[],
  status public.law_firm_member_status not null default 'active',
  lawyer_invite_status public.law_firm_member_status,
  pending_lawyer_id uuid references public.lawyer_profiles(id) on delete set null,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (law_firm_id, lawyer_id),
  check (
    coalesce(array_length(roles, 1), 0) > 0
    and roles <@ array['owner', 'admin', 'lawyer', 'secretary', 'intern']::text[]
  )
);

create index if not exists law_firm_members_profile_idx
on public.law_firm_members(profile_id);

create unique index if not exists law_firm_members_firm_profile_unique
on public.law_firm_members(law_firm_id, profile_id)
where profile_id is not null;

create index if not exists law_firm_members_roles_gin_idx
on public.law_firm_members using gin (roles);

create index if not exists law_firm_members_pending_lawyer_idx
on public.law_firm_members(pending_lawyer_id)
where pending_lawyer_id is not null;

create table if not exists public.lawyer_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  oab_number text not null,
  oab_state char(2) not null,
  practice_area text not null,
  practice_areas text[] not null default '{}'::text[],
  status public.verification_status not null default 'pending',
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewer_id uuid references public.profiles(id) on delete set null,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.verification_documents (
  id uuid primary key default gen_random_uuid(),
  verification_id uuid not null references public.lawyer_verifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  document_type public.verification_document_type not null,
  title text not null,
  storage_path text not null,
  mime_type text,
  file_size_bytes bigint,
  uploaded_at timestamptz not null default now(),
  unique (verification_id, document_type)
);

create table if not exists public.legal_cases (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  area text not null,
  status public.lawyer_case_status not null default 'open',
  client_id uuid not null references public.profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  assigned_lawyer_id uuid references public.lawyer_profiles(id) on delete set null,
  description text,
  last_update_label text,
  deadline_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.case_participants (
  case_id uuid not null references public.legal_cases(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role public.case_participant_role not null,
  created_at timestamptz not null default now(),
  primary key (case_id, profile_id)
);

create table if not exists public.case_documents (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.legal_cases(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  storage_path text not null,
  mime_type text,
  file_size_bytes bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  type public.conversation_type not null default 'client_firm',
  client_id uuid not null references public.profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  lawyer_id uuid references public.lawyer_profiles(id) on delete set null,
  case_id uuid references public.legal_cases(id) on delete set null,
  title text not null,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  sender_type public.message_sender_type not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  role public.appointment_role not null,
  client_id uuid not null references public.profiles(id) on delete cascade,
  lawyer_id uuid references public.lawyer_profiles(id) on delete set null,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  case_id uuid references public.legal_cases(id) on delete set null,
  title text not null,
  area text not null,
  counterpart_name text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text not null,
  status public.appointment_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profiles_lawyer_status_idx on public.profiles(lawyer_status);
create index if not exists law_firms_active_idx on public.law_firms(is_active);
create index if not exists lawyer_profiles_oab_idx on public.lawyer_profiles(oab_state, oab_number);
create index if not exists lawyer_profiles_practice_areas_idx on public.lawyer_profiles using gin (practice_areas);
create index if not exists law_firms_practice_areas_idx on public.law_firms using gin (practice_areas);
create index if not exists lawyer_verifications_user_idx on public.lawyer_verifications(user_id);
create index if not exists lawyer_verifications_status_idx on public.lawyer_verifications(status);
create index if not exists legal_cases_client_idx on public.legal_cases(client_id);
create index if not exists legal_cases_lawyer_idx on public.legal_cases(assigned_lawyer_id);
create index if not exists conversations_client_idx on public.conversations(client_id);
create index if not exists conversations_lawyer_idx on public.conversations(lawyer_id);
create index if not exists messages_conversation_created_idx on public.messages(conversation_id, created_at);
create index if not exists appointments_client_starts_idx on public.appointments(client_id, starts_at);
create index if not exists appointments_lawyer_starts_idx on public.appointments(lawyer_id, starts_at);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists law_firms_set_updated_at on public.law_firms;
create trigger law_firms_set_updated_at
before update on public.law_firms
for each row execute function public.set_updated_at();

drop trigger if exists lawyer_profiles_set_updated_at on public.lawyer_profiles;
create trigger lawyer_profiles_set_updated_at
before update on public.lawyer_profiles
for each row execute function public.set_updated_at();

drop trigger if exists lawyer_verifications_set_updated_at on public.lawyer_verifications;
create trigger lawyer_verifications_set_updated_at
before update on public.lawyer_verifications
for each row execute function public.set_updated_at();

drop trigger if exists legal_cases_set_updated_at on public.legal_cases;
create trigger legal_cases_set_updated_at
before update on public.legal_cases
for each row execute function public.set_updated_at();

drop trigger if exists conversations_set_updated_at on public.conversations;
create trigger conversations_set_updated_at
before update on public.conversations
for each row execute function public.set_updated_at();

drop trigger if exists appointments_set_updated_at on public.appointments;
create trigger appointments_set_updated_at
before update on public.appointments
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.legal_categories enable row level security;
alter table public.law_firms enable row level security;
alter table public.law_firm_categories enable row level security;
alter table public.lawyer_profiles enable row level security;
alter table public.law_firm_members enable row level security;
alter table public.lawyer_verifications enable row level security;
alter table public.verification_documents enable row level security;
alter table public.legal_cases enable row level security;
alter table public.case_participants enable row level security;
alter table public.case_documents enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.appointments enable row level security;

create policy "profiles_select_own"
on public.profiles for select
to authenticated
using (id = auth.uid());

create policy "profiles_insert_own"
on public.profiles for insert
to authenticated
with check (id = auth.uid());

create policy "profiles_update_own"
on public.profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Helper functions must exist before policies reference them.
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

create policy "profiles_select_related_case_or_conversation"
on public.profiles for select
to authenticated
using (public.can_select_profile(profiles.id));

create policy "legal_categories_public_read"
on public.legal_categories for select
to authenticated
using (true);

create policy "law_firms_public_read"
on public.law_firms for select
to authenticated
using (is_active = true);

create policy "law_firm_categories_public_read"
on public.law_firm_categories for select
to authenticated
using (true);

create policy "lawyer_profiles_public_read_approved"
on public.lawyer_profiles for select
to authenticated
using (
  id = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.id = lawyer_profiles.id
      and p.lawyer_status = 'approved'
  )
);

create policy "lawyer_profiles_insert_own"
on public.lawyer_profiles for insert
to authenticated
with check (id = auth.uid());

create policy "lawyer_profiles_update_own"
on public.lawyer_profiles for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "law_firm_members_read_related"
on public.law_firm_members for select
to authenticated
using (
  profile_id = auth.uid()
  or lawyer_id = auth.uid()
  or exists (
    select 1 from public.law_firms lf
    where lf.id = law_firm_members.law_firm_id
      and lf.is_active = true
  )
);

create policy "lawyer_verifications_select_own"
on public.lawyer_verifications for select
to authenticated
using (user_id = auth.uid());

create policy "lawyer_verifications_insert_own"
on public.lawyer_verifications for insert
to authenticated
with check (user_id = auth.uid());

create policy "lawyer_verifications_update_own_pending"
on public.lawyer_verifications for update
to authenticated
using (user_id = auth.uid() and status in ('draft', 'pending'))
with check (user_id = auth.uid());

create policy "verification_documents_select_own"
on public.verification_documents for select
to authenticated
using (user_id = auth.uid());

create policy "verification_documents_insert_own"
on public.verification_documents for insert
to authenticated
with check (user_id = auth.uid());

create policy "legal_cases_select_related"
on public.legal_cases for select
to authenticated
using (public.can_access_case(legal_cases.id));

create policy "legal_cases_insert_as_client"
on public.legal_cases for insert
to authenticated
with check (client_id = auth.uid());

create policy "legal_cases_update_related"
on public.legal_cases for update
to authenticated
using (public.can_manage_case(legal_cases.id));

create policy "case_participants_select_related"
on public.case_participants for select
to authenticated
using (
  profile_id = auth.uid()
  or public.can_access_case(case_participants.case_id)
);

create policy "case_documents_select_related"
on public.case_documents for select
to authenticated
using (
  uploaded_by = auth.uid()
  or public.can_access_case(case_documents.case_id)
);

create policy "case_documents_insert_related"
on public.case_documents for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and public.can_access_case(case_documents.case_id)
);

create policy "conversations_select_related"
on public.conversations for select
to authenticated
using (public.can_access_conversation(conversations.id));

create policy "conversations_insert_as_client"
on public.conversations for insert
to authenticated
with check (client_id = auth.uid());

create policy "messages_select_related"
on public.messages for select
to authenticated
using (public.can_access_conversation(messages.conversation_id));

create policy "messages_insert_related"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_conversation(messages.conversation_id)
);

create policy "appointments_select_related"
on public.appointments for select
to authenticated
using (client_id = auth.uid() or lawyer_id = auth.uid());

create policy "appointments_insert_as_related"
on public.appointments for insert
to authenticated
with check (client_id = auth.uid() or lawyer_id = auth.uid());

create policy "appointments_update_related"
on public.appointments for update
to authenticated
using (client_id = auth.uid() or lawyer_id = auth.uid())
with check (client_id = auth.uid() or lawyer_id = auth.uid());

insert into storage.buckets (id, name, public)
values
  ('verification-documents', 'verification-documents', false),
  ('case-documents', 'case-documents', false),
  ('profile-avatars', 'profile-avatars', true)
on conflict (id) do nothing;

create policy "verification_documents_storage_own_folder_read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "verification_documents_storage_own_folder_write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

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

create policy "case_documents_storage_own_folder_write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'case-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "profile_avatars_public_read"
on storage.objects for select
to public
using (bucket_id = 'profile-avatars');

create policy "profile_avatars_own_folder_write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'profile-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

insert into public.legal_categories (id, title, icon_name, is_highlighted, sort_order)
values
  ('divorcio', 'Divórcio', 'family_restroom', false, 10),
  ('pensao', 'Pensão Alimentícia', 'child_care_outlined', true, 20),
  ('trabalhista', 'Trabalhista', 'work_outline', false, 30),
  ('imobiliario', 'Imobiliário', 'home_outlined', true, 40),
  ('acidente', 'Acidente de Trânsito', 'directions_car_outlined', false, 50),
  ('consumidor', 'Direito do Consumidor', 'shopping_bag_outlined', true, 60)
on conflict (id) do update set
  title = excluded.title,
  icon_name = excluded.icon_name,
  is_highlighted = excluded.is_highlighted,
  sort_order = excluded.sort_order;

insert into public.law_firms (
  id,
  name,
  initials,
  specialty,
  practice_areas,
  rating,
  reviews_count,
  distance_label,
  avatar_type
)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'Fries Advogados',
    'FA',
    'Direito Trabalhista',
    array['Direito Trabalhista', 'Direito Empresarial'],
    4.9,
    128,
    '1,8 km',
    'navy'
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    'Silva & Associados',
    'SA',
    'Direito de Família',
    array['Direito de Família', 'Direito Cível'],
    4.8,
    94,
    '2,4 km',
    'blue'
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    'Moura Advogados',
    'MA',
    'Direito do Consumidor',
    array['Direito do Consumidor', 'Direito Digital'],
    4.7,
    76,
    '3,1 km',
    'gold'
  )
on conflict (id) do update set
  name = excluded.name,
  initials = excluded.initials,
  specialty = excluded.specialty,
  practice_areas = excluded.practice_areas,
  rating = excluded.rating,
  reviews_count = excluded.reviews_count,
  distance_label = excluded.distance_label,
  avatar_type = excluded.avatar_type;

insert into public.law_firm_categories (law_firm_id, category_id)
values
  ('11111111-1111-4111-8111-111111111111', 'trabalhista'),
  ('22222222-2222-4222-8222-222222222222', 'divorcio'),
  ('22222222-2222-4222-8222-222222222222', 'pensao'),
  ('33333333-3333-4333-8333-333333333333', 'consumidor')
on conflict do nothing;

-- ============================================================================
-- Source: supabase/patch_001_auth_profile_trigger.sql
-- ============================================================================

-- Run this if you already executed schema.sql before this patch existed.
-- It creates a profile row automatically when a user signs up.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  full_name_value text;
begin
  full_name_value := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    split_part(new.email, '@', 1),
    'Usuário Jurii'
  );

  insert into public.profiles (id, full_name, email, initials)
  values (
    new.id,
    full_name_value,
    new.email,
    upper(left(full_name_value, 1))
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- ============================================================================
-- Source: supabase/patch_002_fix_rls_recursion.sql
-- ============================================================================

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

-- ============================================================================
-- Source: supabase/patch_003_auth_profile_cpf.sql
-- ============================================================================

-- Run this if you already executed schema.sql before CPF metadata was added.
-- It keeps sign-up compatible with email confirmation enabled by copying CPF
-- from auth metadata into public.profiles during user creation.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  full_name_value text;
  cpf_value text;
begin
  full_name_value := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    split_part(new.email, '@', 1),
    'Usuário Jurii'
  );

  cpf_value := new.raw_user_meta_data ->> 'cpf';

  insert into public.profiles (id, full_name, email, initials, cpf)
  values (
    new.id,
    full_name_value,
    new.email,
    upper(left(full_name_value, 1)),
    cpf_value
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    initials = excluded.initials,
    cpf = coalesce(excluded.cpf, public.profiles.cpf);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- ============================================================================
-- Source: supabase/patch_004_law_firm_verification.sql
-- ============================================================================

-- Adds the office verification flow and updates firm membership so owners,
-- admins and secretaries can access the future office area without OAB.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'law_firm_member_role') then
    create type public.law_firm_member_role as enum ('owner', 'admin', 'secretary', 'lawyer');
  end if;

  if not exists (select 1 from pg_type where typname = 'law_firm_member_status') then
    create type public.law_firm_member_status as enum ('invited', 'active', 'disabled');
  end if;

  if not exists (select 1 from pg_type where typname = 'law_firm_document_type') then
    create type public.law_firm_document_type as enum (
      'cnpj_registration',
      'articles_of_association',
      'address_proof',
      'owner_identity'
    );
  end if;
end $$;

alter table public.law_firm_members
add column if not exists profile_id uuid references public.profiles(id) on delete cascade;

alter table public.law_firm_members
alter column lawyer_id drop not null;

alter table public.law_firm_members
add column if not exists member_role public.law_firm_member_role not null default 'lawyer';

alter table public.law_firm_members
add column if not exists status public.law_firm_member_status not null default 'active';

update public.law_firm_members
set profile_id = lawyer_id
where profile_id is null
  and lawyer_id is not null;

update public.law_firm_members
set member_role = case
  when role = 'owner' then 'owner'::public.law_firm_member_role
  when role = 'admin' then 'admin'::public.law_firm_member_role
  when role = 'secretary' then 'secretary'::public.law_firm_member_role
  else 'lawyer'::public.law_firm_member_role
end;

create table if not exists public.law_firm_verifications (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  firm_name text not null,
  cnpj text not null,
  phone text,
  email text,
  address text,
  status public.verification_status not null default 'pending',
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewer_id uuid references public.profiles(id) on delete set null,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.law_firm_verification_documents (
  id uuid primary key default gen_random_uuid(),
  verification_id uuid not null references public.law_firm_verifications(id) on delete cascade,
  owner_profile_id uuid not null references public.profiles(id) on delete cascade,
  document_type public.law_firm_document_type not null,
  title text not null,
  storage_path text not null,
  mime_type text,
  created_at timestamptz not null default now()
);

create index if not exists law_firm_members_profile_idx
on public.law_firm_members(profile_id);

create unique index if not exists law_firm_members_firm_profile_unique
on public.law_firm_members(law_firm_id, profile_id)
where profile_id is not null;

create index if not exists law_firm_verifications_owner_idx
on public.law_firm_verifications(owner_profile_id);

create index if not exists law_firm_verifications_status_idx
on public.law_firm_verifications(status);

drop trigger if exists law_firm_verifications_set_updated_at on public.law_firm_verifications;
create trigger law_firm_verifications_set_updated_at
before update on public.law_firm_verifications
for each row execute function public.set_updated_at();

alter table public.law_firm_verifications enable row level security;
alter table public.law_firm_verification_documents enable row level security;

drop policy if exists "law_firm_members_read_related" on public.law_firm_members;
create policy "law_firm_members_read_related"
on public.law_firm_members for select
to authenticated
using (
  profile_id = auth.uid()
  or lawyer_id = auth.uid()
  or exists (
    select 1 from public.law_firms lf
    where lf.id = law_firm_members.law_firm_id
      and lf.is_active = true
  )
);

drop policy if exists "law_firm_verifications_select_own" on public.law_firm_verifications;
create policy "law_firm_verifications_select_own"
on public.law_firm_verifications for select
to authenticated
using (owner_profile_id = auth.uid());

drop policy if exists "law_firm_verifications_insert_own" on public.law_firm_verifications;
create policy "law_firm_verifications_insert_own"
on public.law_firm_verifications for insert
to authenticated
with check (owner_profile_id = auth.uid());

drop policy if exists "law_firm_verifications_update_own_pending" on public.law_firm_verifications;
create policy "law_firm_verifications_update_own_pending"
on public.law_firm_verifications for update
to authenticated
using (owner_profile_id = auth.uid() and status in ('draft', 'pending'))
with check (owner_profile_id = auth.uid());

drop policy if exists "law_firm_verification_documents_select_own" on public.law_firm_verification_documents;
create policy "law_firm_verification_documents_select_own"
on public.law_firm_verification_documents for select
to authenticated
using (owner_profile_id = auth.uid());

drop policy if exists "law_firm_verification_documents_insert_own" on public.law_firm_verification_documents;
create policy "law_firm_verification_documents_insert_own"
on public.law_firm_verification_documents for insert
to authenticated
with check (owner_profile_id = auth.uid());

-- ============================================================================
-- Source: supabase/patch_005_public_grants.sql
-- ============================================================================

-- Grants required table privileges for Supabase API roles.
--
-- RLS policies decide which rows each user can access, but PostgreSQL still
-- requires table-level privileges for the anon/authenticated roles first.
-- Run this patch if the app logs errors like:
-- "permission denied for table profiles"
-- "Grant SELECT ON public.profiles TO authenticated"

grant usage on schema public to anon, authenticated;

grant select on public.profiles to anon;

grant select, insert, update on public.profiles to authenticated;

grant select on public.legal_categories to anon, authenticated;
grant select on public.law_firms to anon, authenticated;
grant select on public.law_firm_categories to anon, authenticated;
grant select on public.lawyer_profiles to anon, authenticated;

grant select, insert, update on public.lawyer_verifications to authenticated;
grant select, insert on public.verification_documents to authenticated;

grant select, insert, update on public.law_firm_verifications to authenticated;
grant select, insert on public.law_firm_verification_documents to authenticated;
grant select, insert, update on public.law_firm_members to authenticated;

grant select, insert, update on public.legal_cases to authenticated;
grant select, insert, update on public.case_participants to authenticated;
grant select, insert, update on public.case_documents to authenticated;

grant select, insert, update on public.conversations to authenticated;
grant select, insert, update on public.messages to authenticated;
grant select, insert, update on public.appointments to authenticated;

-- ============================================================================
-- Source: supabase/patch_006_approve_law_firm_verification.sql
-- ============================================================================

-- Administrative helper for approving office verification requests.
--
-- Run patch_004 and patch_005 first. Then approve a request from the SQL
-- Editor with:
--
-- select public.approve_law_firm_verification('VERIFICATION_ID_HERE');
--
-- This creates/updates the public law firm, links it back to the verification,
-- and creates the owner membership used by the app's office area.

create or replace function public.approve_law_firm_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.law_firm_verifications%rowtype;
  firm_id_value uuid;
  initials_value text;
  existing_member_id uuid;
begin
  select *
  into verification_row
  from public.law_firm_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Law firm verification not found: %', verification_id_value;
  end if;

  initials_value := upper(left(trim(verification_row.firm_name), 1));
  if initials_value is null or initials_value = '' then
    initials_value := 'E';
  end if;

  if verification_row.law_firm_id is null then
    insert into public.law_firms (
      name,
      initials,
      specialty,
      rating,
      reviews_count,
      distance_label,
      avatar_type,
      phone,
      email,
      address,
      is_active
    )
    values (
      verification_row.firm_name,
      initials_value,
      'Escritório jurídico',
      0,
      0,
      '',
      'purple',
      nullif(verification_row.phone, ''),
      nullif(verification_row.email, ''),
      nullif(verification_row.address, ''),
      true
    )
    returning id into firm_id_value;
  else
    firm_id_value := verification_row.law_firm_id;

    update public.law_firms
    set
      name = verification_row.firm_name,
      initials = initials_value,
      phone = nullif(verification_row.phone, ''),
      email = nullif(verification_row.email, ''),
      address = nullif(verification_row.address, ''),
      avatar_type = 'purple',
      is_active = true,
      updated_at = now()
    where id = firm_id_value;
  end if;

  update public.law_firm_verifications
  set
    status = 'approved',
    law_firm_id = firm_id_value,
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  select id
  into existing_member_id
  from public.law_firm_members
  where law_firm_id = firm_id_value
    and profile_id = verification_row.owner_profile_id
  limit 1;

  if existing_member_id is null then
    insert into public.law_firm_members (
      law_firm_id,
      profile_id,
      role,
      member_role,
      status
    )
    values (
      firm_id_value,
      verification_row.owner_profile_id,
      'owner',
      'owner',
      'active'
    );
  else
    update public.law_firm_members
    set
      role = 'owner',
      member_role = 'owner',
      status = 'active'
    where id = existing_member_id;
  end if;

  return firm_id_value;
end;
$$;

revoke all on function public.approve_law_firm_verification(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.approve_law_firm_verification(uuid, uuid)
to service_role;

-- ============================================================================
-- Source: supabase/patch_007_team_invites_notifications.sql
-- ============================================================================

-- Adds office team invitations by OAB and app notifications.
--
-- Run after patch_004, patch_005 and patch_006.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  actor_profile_id uuid references public.profiles(id) on delete set null,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  type text not null default 'system',
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_created_idx
on public.notifications(recipient_profile_id, created_at desc);

create index if not exists notifications_recipient_unread_idx
on public.notifications(recipient_profile_id)
where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications for select
to authenticated
using (recipient_profile_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
on public.notifications for update
to authenticated
using (recipient_profile_id = auth.uid())
with check (recipient_profile_id = auth.uid());

grant select, update on public.notifications to authenticated;

update public.law_firm_members lfm
set lawyer_id = lfm.profile_id
where lfm.lawyer_id is null
  and lfm.profile_id is not null
  and lfm.member_role in ('owner', 'admin')
  and exists (
    select 1
    from public.lawyer_profiles lp
    where lp.id = lfm.profile_id
  );

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
    )
    or exists (
      select 1
      from public.law_firm_members viewer
      join public.law_firm_members target
        on target.law_firm_id = viewer.law_firm_id
      where viewer.profile_id = auth.uid()
        and viewer.status in ('active', 'invited')
        and target.profile_id = profile_id_value
        and target.status in ('active', 'invited')
    );
$$;

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
      and lfm.member_role in ('owner', 'admin')
  );
$$;

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
  target_verification public.lawyer_verifications%rowtype;
  target_profile public.profiles%rowtype;
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
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

  select *
  into target_verification
  from public.lawyer_verifications lv
  where lv.status = 'approved'
    and upper(trim(lv.oab_state)) = normalized_oab_state
    and regexp_replace(upper(coalesce(lv.oab_number, '')), '[^A-Z0-9]', '', 'g')
      = normalized_oab_number
  order by lv.reviewed_at desc nulls last, lv.submitted_at desc
  limit 1;

  if not found then
    raise exception 'Lawyer not found or not approved for this OAB';
  end if;

  select *
  into target_profile
  from public.profiles
  where id = target_verification.user_id;

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  update public.profiles
  set lawyer_status = 'approved'
  where id = target_verification.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    approved_at
  )
  values (
    target_verification.user_id,
    target_verification.oab_number,
    target_verification.oab_state,
    target_verification.practice_area,
    coalesce(target_verification.reviewed_at, now())
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    approved_at = coalesce(public.lawyer_profiles.approved_at, excluded.approved_at);

  select id
  into membership_id_value
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_verification.user_id
      or lawyer_id = target_verification.user_id
    )
  limit 1;

  if membership_id_value is null then
    insert into public.law_firm_members (
      law_firm_id,
      lawyer_id,
      profile_id,
      role,
      member_role,
      status
    )
    values (
      law_firm_id_value,
      target_verification.user_id,
      target_verification.user_id,
      'lawyer',
      'lawyer',
      'invited'
    )
    returning id into membership_id_value;
  else
    update public.law_firm_members
    set
      lawyer_id = target_verification.user_id,
      profile_id = target_verification.user_id,
      role = case
        when member_role in ('owner', 'admin') then role
        else 'lawyer'
      end,
      member_role = case
        when member_role in ('owner', 'admin') then member_role
        else 'lawyer'::public.law_firm_member_role
      end,
      status = case
        when status = 'active' then 'active'::public.law_firm_member_status
        else 'invited'::public.law_firm_member_status
      end
    where id = membership_id_value;
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
    target_verification.user_id,
    auth.uid(),
    law_firm_id_value,
    'team_invite',
    'Convite para escritório',
    coalesce(firm_name_value, 'Um escritório') ||
      ' convidou você para integrar a equipe.',
    jsonb_build_object('membership_id', membership_id_value)
  );

  return membership_id_value;
end;
$$;

revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
to authenticated;

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
  next_status public.law_firm_member_status;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into membership_row
  from public.law_firm_members
  where id = membership_id_value;

  if not found then
    raise exception 'Invite not found';
  end if;

  if membership_row.profile_id <> auth.uid() then
    raise exception 'Only the invited lawyer can respond to this invite';
  end if;

  if membership_row.status <> 'invited' then
    raise exception 'Invite is no longer pending';
  end if;

  next_status := case
    when accepted_value then 'active'::public.law_firm_member_status
    else 'disabled'::public.law_firm_member_status
  end;

  update public.law_firm_members
  set status = next_status
  where id = membership_id_value;

  update public.notifications
  set
    read_at = coalesce(read_at, now()),
    metadata = metadata ||
      jsonb_build_object(
        'membership_id', membership_id_value,
        'invite_status', case when accepted_value then 'accepted' else 'declined' end
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

-- ============================================================================
-- Source: supabase/patch_008_messaging_integration.sql
-- ============================================================================

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

-- ============================================================================
-- Source: supabase/patch_009_profile_conversation_entrypoints.sql
-- ============================================================================

-- Profile entry points for starting conversations from client-facing profiles.
--
-- Run after patch_008.

drop policy if exists "profiles_select_approved_lawyers_public"
on public.profiles;

create policy "profiles_select_approved_lawyers_public"
on public.profiles for select
to authenticated
using (
  lawyer_status = 'approved'
  and exists (
    select 1
    from public.lawyer_profiles lp
    where lp.id = profiles.id
  )
);

create or replace function public.approve_lawyer_verification(
  verification_id_value uuid,
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
    status = 'approved',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'approved'
  where id = verification_row.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    approved_at
  )
  values (
    verification_row.user_id,
    verification_row.oab_number,
    verification_row.oab_state,
    verification_row.practice_area,
    now()
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    approved_at = coalesce(public.lawyer_profiles.approved_at, excluded.approved_at);

  return verification_row.user_id;
end;
$$;

revoke all on function public.approve_lawyer_verification(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.approve_lawyer_verification(uuid, uuid)
to service_role;

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
    and case_id is null
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

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and case_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      title,
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      profile_row.full_name,
      lawyer_row.primary_area,
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

revoke all on function public.start_or_get_law_firm_conversation(uuid, text)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

grant execute on function public.start_or_get_law_firm_conversation(uuid, text)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_010_realtime_messages_profiles.sql
-- ============================================================================

-- Enables realtime chat updates and lets office members display client names
-- in firm conversations.
--
-- Run after patch_009.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

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
    )
    or exists (
      select 1
      from public.law_firm_members viewer
      join public.law_firm_members target
        on target.law_firm_id = viewer.law_firm_id
      where viewer.profile_id = auth.uid()
        and viewer.status in ('active', 'invited')
        and target.profile_id = profile_id_value
        and target.status in ('active', 'invited')
    )
    or exists (
      select 1
      from public.conversations c
      join public.law_firm_members viewer
        on viewer.law_firm_id = c.law_firm_id
      where c.client_id = profile_id_value
        and c.law_firm_id is not null
        and viewer.profile_id = auth.uid()
        and viewer.status = 'active'
    );
$$;

-- ============================================================================
-- Source: supabase/patch_011_recommended_lawyers_rpc.sql
-- ============================================================================

-- Stable entry point for the client home recommended lawyers section.
--
-- Run after patch_010. This avoids the app depending on multiple client-side
-- RLS reads across lawyer_profiles and profiles just to render public cards.

create or replace function public.fetch_recommended_lawyers(
  limit_value int default 6
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.is_available = true
  order by lp.approved_at desc nulls last, lp.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

revoke all on function public.fetch_recommended_lawyers(int)
from public, anon, authenticated;

grant execute on function public.fetch_recommended_lawyers(int)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_012_conversation_display_names_rpc.sql
-- ============================================================================

-- Context-aware conversation listing for client, lawyer and office inboxes.
--
-- Run after patch_011. The stored conversation title is client-facing, so
-- lawyer and office inboxes need a server-side display name for the other side.

create or replace function public.fetch_conversations_for_current_user(
  scope_value text,
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  with scoped_conversations as (
    select c.*
    from public.conversations c
    where auth.uid() is not null
      and (
        (
          scope_value = 'client'
          and c.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and c.lawyer_id = auth.uid()
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  )
  select
    c.id,
    c.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.full_name, 'Cliente')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.full_name, c.title)
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(c.title), 2))
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Conversa iniciada.') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from scoped_conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  order by c.last_message_at desc nulls last, c.updated_at desc;
$$;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_013_chat_profile_entrypoints.sql
-- ============================================================================

-- Profile entry points opened from chat headers.
--
-- Run after patch_012.

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
    p.email,
    p.initials,
    p.member_since,
    p.lawyer_status::text
  from public.profiles p
  where p.id = profile_id_value
    and public.can_select_profile(p.id)
  limit 1;
$$;

create or replace function public.fetch_lawyer_public_profile(
  lawyer_profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
  limit 1;
$$;

revoke all on function public.fetch_chat_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_chat_profile(uuid)
to authenticated;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_014_cases_integration.sql
-- ============================================================================

-- Case listing entry points for client, lawyer and office areas.
--
-- Run after patch_013.

create or replace function public.case_status_label(status_value public.lawyer_case_status)
returns text
language sql
immutable
set search_path = public
as $$
  select case status_value
    when 'new_message' then 'Nova mensagem'
    when 'deadline' then 'Prazo crítico'
    when 'closed' then 'Encerrado'
    else 'Em andamento'
  end;
$$;

create or replace function public.fetch_client_cases()
returns table (
  id uuid,
  title text,
  area text,
  status text,
  status_label text,
  last_update_label text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lc.id,
    lc.title,
    lc.area,
    lc.status::text as status,
    public.case_status_label(lc.status) as status_label,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.updated_at
  from public.legal_cases lc
  where lc.client_id = auth.uid()
  order by lc.updated_at desc;
$$;

create or replace function public.fetch_lawyer_cases()
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  area text,
  last_update_label text,
  status text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lc.id,
    lc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    lc.area,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.status::text as status,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.assigned_lawyer_id = auth.uid()
     or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = lc.id
        and cp.profile_id = auth.uid()
     )
  order by lc.updated_at desc;
$$;

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lc.id,
    lc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    coalesce(lawyer_profile.full_name, 'Sem advogado definido') as assigned_lawyer,
    lc.area,
    public.case_status_label(lc.status) as status_label,
    coalesce(lc.last_update_label, 'Atualizado hoje') as next_step,
    lc.status = 'deadline' as urgent,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = lc.assigned_lawyer_id
  where lc.law_firm_id = law_firm_id_value
    and exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = law_firm_id_value
        and lfm.profile_id = auth.uid()
        and lfm.status = 'active'
    )
  order by lc.updated_at desc;
$$;

revoke all on function public.case_status_label(public.lawyer_case_status)
from public, anon, authenticated;

revoke all on function public.fetch_client_cases()
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_client_cases()
to authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_015_case_requests_updates.sql
-- ============================================================================

-- Case request and case update workflow.
--
-- Run after patch_014. Lawyers and office members can propose a case from a
-- client conversation. Clients accept or decline. Accepted requests become
-- legal_cases, and professionals can add progress updates.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'case_request_status') then
    create type public.case_request_status as enum (
      'pending',
      'accepted',
      'declined',
      'cancelled'
    );
  end if;
end $$;

create table if not exists public.case_requests (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete set null,
  lawyer_id uuid references public.lawyer_profiles(id) on delete set null,
  requested_by_profile_id uuid references public.profiles(id) on delete set null,
  legal_case_id uuid references public.legal_cases(id) on delete set null,
  title text not null,
  area text not null,
  summary text,
  status public.case_request_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.case_updates (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.legal_cases(id) on delete cascade,
  author_profile_id uuid references public.profiles(id) on delete set null,
  title text not null,
  body text,
  created_at timestamptz not null default now()
);

create index if not exists case_requests_client_status_idx
on public.case_requests(client_id, status);

create index if not exists case_requests_conversation_status_idx
on public.case_requests(conversation_id, status);

create index if not exists case_updates_case_created_idx
on public.case_updates(case_id, created_at desc);

drop trigger if exists case_requests_set_updated_at on public.case_requests;
create trigger case_requests_set_updated_at
before update on public.case_requests
for each row execute function public.set_updated_at();

alter table public.case_requests enable row level security;
alter table public.case_updates enable row level security;

create or replace function public.can_manage_case_updates(case_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.legal_cases lc
    where lc.id = case_id_value
      and (
        lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
            and cp.role in ('lawyer', 'firm_member')
        )
        or (
          lc.law_firm_id is not null
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = lc.law_firm_id
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  );
$$;

create or replace function public.create_case_request(
  conversation_id_value uuid,
  title_value text,
  area_value text,
  summary_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  request_id_value uuid;
  clean_title text;
  clean_area text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  clean_area := nullif(trim(coalesce(area_value, '')), '');

  if clean_title is null or clean_area is null then
    raise exception 'Title and area are required';
  end if;

  select *
  into conversation_row
  from public.conversations
  where id = conversation_id_value;

  if not found then
    raise exception 'Conversation not found';
  end if;

  if not (
    conversation_row.lawyer_id = auth.uid()
    or (
      conversation_row.law_firm_id is not null
      and exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = conversation_row.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
    )
  ) then
    raise exception 'Only the responsible professional can request case acceptance';
  end if;

  select id
  into request_id_value
  from public.case_requests
  where conversation_id = conversation_id_value
    and status = 'pending'
  order by created_at desc
  limit 1;

  if request_id_value is not null then
    update public.case_requests
    set
      title = clean_title,
      area = clean_area,
      summary = nullif(trim(coalesce(summary_value, '')), ''),
      requested_by_profile_id = auth.uid()
    where id = request_id_value;

    return request_id_value;
  end if;

  insert into public.case_requests (
    conversation_id,
    client_id,
    law_firm_id,
    lawyer_id,
    requested_by_profile_id,
    title,
    area,
    summary
  )
  values (
    conversation_row.id,
    conversation_row.client_id,
    conversation_row.law_firm_id,
    conversation_row.lawyer_id,
    auth.uid(),
    clean_title,
    clean_area,
    nullif(trim(coalesce(summary_value, '')), '')
  )
  returning id into request_id_value;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body
  )
  values (
    conversation_row.id,
    auth.uid(),
    'system',
    'Solicitação de caso enviada: ' || clean_title
  );

  return request_id_value;
end;
$$;

create or replace function public.fetch_case_requests_for_client()
returns table (
  id uuid,
  conversation_id uuid,
  title text,
  area text,
  summary text,
  status text,
  requested_by text,
  requester_initials text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cr.id,
    cr.conversation_id,
    cr.title,
    cr.area,
    cr.summary,
    cr.status::text as status,
    case
      when cr.law_firm_id is not null then coalesce(lf.name, requester.full_name, 'Jurii')
      else coalesce(requester.full_name, lawyer_profile.full_name, 'Advogado Jurii')
    end as requested_by,
    case
      when cr.law_firm_id is not null then coalesce(lf.initials, requester.initials, 'JE')
      else coalesce(requester.initials, lawyer_profile.initials, 'AJ')
    end as requester_initials,
    cr.created_at
  from public.case_requests cr
  left join public.profiles requester
    on requester.id = cr.requested_by_profile_id
  left join public.law_firms lf
    on lf.id = cr.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = cr.lawyer_id
  where cr.client_id = auth.uid()
    and cr.status = 'pending'
  order by cr.created_at desc;
$$;

create or replace function public.respond_to_case_request(
  request_id_value uuid,
  accepted_value boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  case_id_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into request_row
  from public.case_requests
  where id = request_id_value
  for update;

  if not found then
    raise exception 'Case request not found';
  end if;

  if request_row.client_id <> auth.uid() then
    raise exception 'Only the client can respond to this case request';
  end if;

  if request_row.status <> 'pending' then
    raise exception 'This case request has already been answered';
  end if;

  if not accepted_value then
    update public.case_requests
    set status = 'declined',
        responded_at = now()
    where id = request_id_value;

    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      request_row.conversation_id,
      auth.uid(),
      'system',
      'Solicitação de caso recusada pelo cliente.'
    );

    return null;
  end if;

  insert into public.legal_cases (
    title,
    area,
    status,
    client_id,
    law_firm_id,
    assigned_lawyer_id,
    description,
    last_update_label
  )
  values (
    request_row.title,
    request_row.area,
    'open',
    request_row.client_id,
    request_row.law_firm_id,
    request_row.lawyer_id,
    request_row.summary,
    'Caso aceito pelo cliente'
  )
  returning id into case_id_value;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, request_row.client_id, 'client')
  on conflict (case_id, profile_id) do nothing;

  if request_row.lawyer_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (case_id_value, request_row.lawyer_id, 'lawyer')
    on conflict (case_id, profile_id) do nothing;
  end if;

  if request_row.requested_by_profile_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (
      case_id_value,
      request_row.requested_by_profile_id,
      case
        when request_row.requested_by_profile_id = request_row.lawyer_id then 'lawyer'
        else 'firm_member'
      end::public.case_participant_role
    )
    on conflict (case_id, profile_id) do nothing;
  end if;

  insert into public.case_updates (
    case_id,
    author_profile_id,
    title,
    body
  )
  values (
    case_id_value,
    auth.uid(),
    'Caso iniciado',
    'O cliente aceitou a solicitação e o caso foi criado na Jurii.'
  );

  update public.conversations
  set case_id = case_id_value,
      updated_at = now()
  where id = request_row.conversation_id;

  update public.case_requests
  set status = 'accepted',
      legal_case_id = case_id_value,
      responded_at = now()
  where id = request_id_value;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body
  )
  values (
    request_row.conversation_id,
    auth.uid(),
    'system',
    'Solicitação de caso aceita pelo cliente.'
  );

  return case_id_value;
end;
$$;

create or replace function public.fetch_case_updates(case_id_value uuid)
returns table (
  id uuid,
  case_id uuid,
  title text,
  body text,
  author_name text,
  author_initials text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cu.id,
    cu.case_id,
    cu.title,
    cu.body,
    coalesce(author.full_name, 'Jurii') as author_name,
    coalesce(author.initials, 'JR') as author_initials,
    cu.created_at
  from public.case_updates cu
  left join public.profiles author
    on author.id = cu.author_profile_id
  where cu.case_id = case_id_value
    and public.can_access_case(cu.case_id)
  order by cu.created_at desc;
$$;

create or replace function public.add_case_update(
  case_id_value uuid,
  title_value text,
  body_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  update_id_value uuid;
  clean_title text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.can_manage_case_updates(case_id_value) then
    raise exception 'Only professionals assigned to this case can add updates';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  if clean_title is null then
    raise exception 'Title is required';
  end if;

  insert into public.case_updates (
    case_id,
    author_profile_id,
    title,
    body
  )
  values (
    case_id_value,
    auth.uid(),
    clean_title,
    nullif(trim(coalesce(body_value, '')), '')
  )
  returning id into update_id_value;

  update public.legal_cases
  set last_update_label = clean_title,
      updated_at = now()
  where id = case_id_value;

  return update_id_value;
end;
$$;

drop policy if exists "case_requests_select_related" on public.case_requests;
create policy "case_requests_select_related"
on public.case_requests for select
to authenticated
using (
  client_id = auth.uid()
  or lawyer_id = auth.uid()
  or requested_by_profile_id = auth.uid()
  or (
    law_firm_id is not null
    and exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = case_requests.law_firm_id
        and lfm.profile_id = auth.uid()
        and lfm.status = 'active'
    )
  )
);

drop policy if exists "case_updates_select_related" on public.case_updates;
create policy "case_updates_select_related"
on public.case_updates for select
to authenticated
using (public.can_access_case(case_updates.case_id));

drop policy if exists "case_updates_insert_professional" on public.case_updates;
create policy "case_updates_insert_professional"
on public.case_updates for insert
to authenticated
with check (
  author_profile_id = auth.uid()
  and public.can_manage_case_updates(case_updates.case_id)
);

grant select, insert, update on public.case_requests to authenticated;
grant select, insert on public.case_updates to authenticated;

revoke all on function public.can_manage_case_updates(uuid)
from public, anon, authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

revoke all on function public.fetch_case_requests_for_client()
from public, anon, authenticated;

revoke all on function public.respond_to_case_request(uuid, boolean)
from public, anon, authenticated;

revoke all on function public.fetch_case_updates(uuid)
from public, anon, authenticated;

revoke all on function public.add_case_update(uuid, text, text)
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

grant execute on function public.fetch_case_requests_for_client()
to authenticated;

grant execute on function public.respond_to_case_request(uuid, boolean)
to authenticated;

grant execute on function public.fetch_case_updates(uuid)
to authenticated;

grant execute on function public.add_case_update(uuid, text, text)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_016_case_request_actions.sql
-- ============================================================================

-- Makes case requests actionable from notifications and chat.
--
-- Run after patch_015. The original case request flow stays the same, but
-- each request now owns one chat system message and one client notification.

alter table public.messages
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.case_requests
add column if not exists message_id uuid references public.messages(id) on delete set null;

alter table public.case_requests
add column if not exists notification_id uuid references public.notifications(id) on delete set null;

create index if not exists case_requests_message_idx
on public.case_requests(message_id);

create index if not exists case_requests_notification_idx
on public.case_requests(notification_id);

create or replace function public.sync_case_request_action_surfaces(
  request_id_value uuid,
  status_value public.case_request_status,
  legal_case_id_value uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  metadata_value jsonb;
  status_label text;
  message_body text;
  notification_title text;
  notification_body text;
begin
  select *
  into request_row
  from public.case_requests
  where id = request_id_value;

  if not found then
    return;
  end if;

  status_label := case status_value
    when 'accepted' then 'accepted'
    when 'declined' then 'declined'
    when 'cancelled' then 'cancelled'
    else 'pending'
  end;

  metadata_value := jsonb_strip_nulls(jsonb_build_object(
    'type', 'case_request',
    'case_request_id', request_row.id,
    'request_status', status_label,
    'conversation_id', request_row.conversation_id,
    'legal_case_id', coalesce(legal_case_id_value, request_row.legal_case_id),
    'title', request_row.title,
    'area', request_row.area
  ));

  message_body := case status_value
    when 'accepted' then 'Caso aceito: ' || request_row.title
    when 'declined' then 'Caso recusado: ' || request_row.title
    when 'cancelled' then 'Solicitação cancelada: ' || request_row.title
    else 'Solicitação de aceite do caso: ' || request_row.title
  end;

  notification_title := case status_value
    when 'accepted' then 'Caso aceito'
    when 'declined' then 'Caso recusado'
    when 'cancelled' then 'Solicitação cancelada'
    else 'Solicitação de caso'
  end;

  notification_body := case status_value
    when 'accepted' then 'Você aceitou o caso "' || request_row.title || '".'
    when 'declined' then 'Você recusou o caso "' || request_row.title || '".'
    when 'cancelled' then 'A solicitação do caso "' || request_row.title || '" foi cancelada.'
    else 'Revise e responda a solicitação do caso "' || request_row.title || '".'
  end;

  if request_row.message_id is not null then
    update public.messages
    set body = message_body,
        metadata = metadata_value
    where id = request_row.message_id;
  end if;

  if request_row.notification_id is not null then
    update public.notifications
    set title = notification_title,
        body = notification_body,
        metadata = metadata_value,
        read_at = case
          when status_value = 'pending' then null
          else coalesce(read_at, now())
        end
    where id = request_row.notification_id;
  end if;
end;
$$;

create or replace function public.create_case_request(
  conversation_id_value uuid,
  title_value text,
  area_value text,
  summary_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  request_row public.case_requests%rowtype;
  request_id_value uuid;
  message_id_value uuid;
  notification_id_value uuid;
  effective_law_firm_id uuid;
  clean_title text;
  clean_area text;
  requester_name text;
  metadata_value jsonb;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  clean_area := nullif(trim(coalesce(area_value, '')), '');

  if clean_title is null or clean_area is null then
    raise exception 'Title and area are required';
  end if;

  select *
  into conversation_row
  from public.conversations
  where id = conversation_id_value;

  if not found then
    raise exception 'Conversation not found';
  end if;

  effective_law_firm_id := conversation_row.law_firm_id;

  if effective_law_firm_id is null and conversation_row.lawyer_id = auth.uid() then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = auth.uid()
      and lfm.status = 'active'
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    lfm.created_at
    limit 1;
  end if;

  if not (
    conversation_row.lawyer_id = auth.uid()
    or (
      conversation_row.law_firm_id is not null
      and exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = conversation_row.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
    )
  ) then
    raise exception 'Only the responsible professional can request case acceptance';
  end if;

  select *
  into request_row
  from public.case_requests
  where conversation_id = conversation_id_value
    and status = 'pending'
  order by created_at desc
  limit 1;

  if found then
    request_id_value := request_row.id;

    update public.case_requests
    set
      title = clean_title,
      area = clean_area,
      summary = nullif(trim(coalesce(summary_value, '')), ''),
      law_firm_id = effective_law_firm_id,
      requested_by_profile_id = auth.uid()
    where id = request_id_value;
  else
    insert into public.case_requests (
      conversation_id,
      client_id,
      law_firm_id,
      lawyer_id,
      requested_by_profile_id,
      title,
      area,
      summary
    )
    values (
      conversation_row.id,
      conversation_row.client_id,
      effective_law_firm_id,
      conversation_row.lawyer_id,
      auth.uid(),
      clean_title,
      clean_area,
      nullif(trim(coalesce(summary_value, '')), '')
    )
    returning id into request_id_value;

    request_row.message_id := null;
    request_row.notification_id := null;
  end if;

  select case
    when effective_law_firm_id is not null then
      coalesce(lf.name, requester.full_name, 'Jurii')
    else
      coalesce(requester.full_name, 'Advogado Jurii')
    end
  into requester_name
  from public.profiles requester
  left join public.law_firms lf
    on lf.id = effective_law_firm_id
  where requester.id = auth.uid();

  metadata_value := jsonb_build_object(
    'type', 'case_request',
    'case_request_id', request_id_value,
    'request_status', 'pending',
    'conversation_id', conversation_row.id,
    'title', clean_title,
    'area', clean_area
  );

  if request_row.message_id is not null then
    update public.messages
    set body = 'Solicitação de aceite do caso: ' || clean_title,
        metadata = metadata_value
    where id = request_row.message_id
    returning id into message_id_value;
  end if;

  if message_id_value is null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    values (
      conversation_row.id,
      auth.uid(),
      'system',
      'Solicitação de aceite do caso: ' || clean_title,
      metadata_value
    )
    returning id into message_id_value;
  end if;

  if request_row.notification_id is not null then
    update public.notifications
    set
      title = 'Solicitação de caso',
      body = coalesce(requester_name, 'Jurii') || ' pediu seu aceite para o caso "' || clean_title || '".',
      type = 'case_request',
      actor_profile_id = auth.uid(),
      law_firm_id = effective_law_firm_id,
      metadata = metadata_value,
      read_at = null
    where id = request_row.notification_id
    returning id into notification_id_value;
  end if;

  if notification_id_value is null then
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
      conversation_row.client_id,
      auth.uid(),
      effective_law_firm_id,
      'case_request',
      'Solicitação de caso',
      coalesce(requester_name, 'Jurii') || ' pediu seu aceite para o caso "' || clean_title || '".',
      metadata_value
    )
    returning id into notification_id_value;
  end if;

  update public.case_requests
  set message_id = message_id_value,
      notification_id = notification_id_value
  where id = request_id_value;

  return request_id_value;
end;
$$;

create or replace function public.respond_to_case_request(
  request_id_value uuid,
  accepted_value boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  case_id_value uuid;
  effective_law_firm_id uuid;
  client_name_value text;
  lawyer_name_value text;
  response_status public.case_request_status;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into request_row
  from public.case_requests
  where id = request_id_value
  for update;

  if not found then
    raise exception 'Case request not found';
  end if;

  if request_row.client_id <> auth.uid() then
    raise exception 'Only the client can respond to this case request';
  end if;

  if request_row.status <> 'pending' then
    return request_row.legal_case_id;
  end if;

  effective_law_firm_id := request_row.law_firm_id;

  if effective_law_firm_id is null and request_row.lawyer_id is not null then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = request_row.lawyer_id
      and lfm.status = 'active'
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    lfm.created_at
    limit 1;

    if effective_law_firm_id is not null then
      update public.case_requests
      set law_firm_id = effective_law_firm_id
      where id = request_id_value;
    end if;
  end if;

  select coalesce(full_name, 'Cliente')
  into client_name_value
  from public.profiles
  where id = request_row.client_id;

  select coalesce(full_name, 'Advogado')
  into lawyer_name_value
  from public.profiles
  where id = request_row.lawyer_id;

  if not accepted_value then
    response_status := 'declined';

    update public.case_requests
    set status = response_status,
        responded_at = now()
    where id = request_id_value;

    perform public.sync_case_request_action_surfaces(
      request_id_value,
      response_status,
      null
    );

    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body
    )
    values (
      request_row.conversation_id,
      auth.uid(),
      'system',
      'Solicitação de caso recusada pelo cliente.'
    );

    insert into public.notifications (
      recipient_profile_id,
      actor_profile_id,
      law_firm_id,
      type,
      title,
      body,
      metadata
    )
    select distinct recipient_id,
      auth.uid(),
      effective_law_firm_id,
      'case_request_response',
      'Solicitação recusada',
      coalesce(client_name_value, 'Cliente') || ' recusou o caso "' || request_row.title || '".',
      jsonb_build_object(
        'case_request_id', request_row.id,
        'request_status', 'declined',
        'conversation_id', request_row.conversation_id,
        'title', request_row.title,
        'area', request_row.area
      )
    from (
      values (request_row.lawyer_id), (request_row.requested_by_profile_id)
    ) as recipients(recipient_id)
    where recipient_id is not null
      and recipient_id <> auth.uid();

    return null;
  end if;

  response_status := 'accepted';

  insert into public.legal_cases (
    title,
    area,
    status,
    client_id,
    law_firm_id,
    assigned_lawyer_id,
    description,
    last_update_label
  )
  values (
    request_row.title,
    request_row.area,
    'open',
    request_row.client_id,
    effective_law_firm_id,
    request_row.lawyer_id,
    request_row.summary,
    'Caso aceito pelo cliente'
  )
  returning id into case_id_value;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, request_row.client_id, 'client')
  on conflict (case_id, profile_id) do nothing;

  if request_row.lawyer_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (case_id_value, request_row.lawyer_id, 'lawyer')
    on conflict (case_id, profile_id) do nothing;
  end if;

  if request_row.requested_by_profile_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (
      case_id_value,
      request_row.requested_by_profile_id,
      case
        when request_row.requested_by_profile_id = request_row.lawyer_id then 'lawyer'
        else 'firm_member'
      end::public.case_participant_role
    )
    on conflict (case_id, profile_id) do nothing;
  end if;

  insert into public.case_updates (
    case_id,
    author_profile_id,
    title,
    body
  )
  values (
    case_id_value,
    auth.uid(),
    'Caso iniciado',
    'O cliente aceitou a solicitação e o caso foi criado na Jurii.'
  );

  update public.conversations
  set case_id = case_id_value,
      updated_at = now()
  where id = request_row.conversation_id;

  update public.case_requests
  set status = response_status,
      legal_case_id = case_id_value,
      responded_at = now()
  where id = request_id_value;

  perform public.sync_case_request_action_surfaces(
    request_id_value,
    response_status,
    case_id_value
  );

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body
  )
  values (
    request_row.conversation_id,
    auth.uid(),
    'system',
    'Solicitação de caso aceita pelo cliente.'
  );

  insert into public.notifications (
    recipient_profile_id,
    actor_profile_id,
    law_firm_id,
    type,
    title,
    body,
    metadata
  )
  select distinct recipient_id,
    auth.uid(),
    effective_law_firm_id,
    'case_request_response',
    'Caso aceito',
    coalesce(client_name_value, 'Cliente') || ' aceitou o caso "' || request_row.title || '".',
    jsonb_build_object(
      'case_request_id', request_row.id,
      'request_status', 'accepted',
      'conversation_id', request_row.conversation_id,
      'legal_case_id', case_id_value,
      'title', request_row.title,
      'area', request_row.area
    )
  from (
    values (request_row.lawyer_id), (request_row.requested_by_profile_id)
  ) as recipients(recipient_id)
  where recipient_id is not null
    and recipient_id <> auth.uid();

  if effective_law_firm_id is not null then
    insert into public.notifications (
      recipient_profile_id,
      actor_profile_id,
      law_firm_id,
      type,
      title,
      body,
      metadata
    )
    select distinct
      lfm.profile_id,
      request_row.client_id,
      effective_law_firm_id,
      'firm_case_started',
      'Novo caso no escritório',
      coalesce(lawyer_name_value, 'Advogado') || ' iniciou um novo caso com ' || coalesce(client_name_value, 'Cliente') || '.',
      jsonb_build_object(
        'case_id', case_id_value,
        'case_request_id', request_row.id,
        'request_status', 'accepted',
        'conversation_id', request_row.conversation_id,
        'law_firm_id', effective_law_firm_id,
        'title', request_row.title,
        'area', request_row.area
      )
    from public.law_firm_members lfm
    where lfm.law_firm_id = effective_law_firm_id
      and lfm.profile_id is not null
      and lfm.status = 'active'
      and lfm.member_role in ('owner', 'admin', 'secretary');
  end if;

  return case_id_value;
end;
$$;

create or replace function public.fetch_lawyer_cases()
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  area text,
  last_update_label text,
  status text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lc.id,
    lc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    lc.area,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.status::text as status,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.assigned_lawyer_id = auth.uid()
     or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = lc.id
        and cp.profile_id = auth.uid()
        and cp.role in ('lawyer', 'firm_member')
     )
  order by lc.updated_at desc;
$$;

revoke all on function public.sync_case_request_action_surfaces(
  uuid,
  public.case_request_status,
  uuid
) from public, anon, authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

revoke all on function public.respond_to_case_request(uuid, boolean)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

grant execute on function public.respond_to_case_request(uuid, boolean)
to authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

-- ============================================================================
-- Source: supabase/patch_017_fix_profile_rls_lawyer_verification_submit.sql
-- ============================================================================

-- Fixes profile RLS recursion during lawyer verification submission.
--
-- Run after patch_016. The main issue is a recursive policy chain:
-- profiles -> lawyer_profiles -> profiles. This patch makes lawyer_profiles
-- readable without checking profiles and moves verification submission into a
-- SECURITY DEFINER RPC.

drop policy if exists "lawyer_profiles_public_read_approved"
on public.lawyer_profiles;

create policy "lawyer_profiles_public_read_approved"
on public.lawyer_profiles for select
to authenticated
using (
  id = auth.uid()
  or approved_at is not null
);

create or replace function public.submit_lawyer_verification(
  oab_number_value text,
  oab_state_value text,
  practice_area_value text
)
returns table (
  id uuid,
  user_id uuid,
  oab_number text,
  oab_state char(2),
  practice_area text,
  status public.verification_status,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  user_id_value uuid;
  email_value text;
  full_name_value text;
  verification_id_value uuid;
  submitted_at_value timestamptz;
  normalized_oab_number text;
  normalized_oab_state char(2);
  normalized_practice_area text;
  status_value public.verification_status := 'pending';
begin
  user_id_value := auth.uid();

  if user_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_oab_number := nullif(trim(coalesce(oab_number_value, '')), '');
  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')))::char(2);
  normalized_practice_area := nullif(trim(coalesce(practice_area_value, '')), '');

  if normalized_oab_number is null then
    raise exception 'OAB number is required';
  end if;

  if nullif(trim(coalesce(oab_state_value, '')), '') is null then
    raise exception 'OAB state is required';
  end if;

  if normalized_practice_area is null then
    raise exception 'Practice area is required';
  end if;

  email_value := coalesce(auth.jwt() ->> 'email', '');
  full_name_value := coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'full_name', ''),
    nullif(auth.jwt() -> 'user_metadata' ->> 'name', ''),
    nullif(split_part(email_value, '@', 1), ''),
    'Usuário Jurii'
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    lawyer_status
  )
  values (
    user_id_value,
    full_name_value,
    email_value,
    upper(left(full_name_value, 1)),
    'pending'
  )
  on conflict on constraint profiles_pkey do update
  set
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
    email = coalesce(nullif(public.profiles.email, ''), excluded.email),
    initials = coalesce(nullif(public.profiles.initials, ''), excluded.initials),
    lawyer_status = case
      when public.profiles.lawyer_status = 'approved' then 'approved'::public.lawyer_status
      else 'pending'::public.lawyer_status
    end,
    updated_at = now();

  insert into public.lawyer_verifications (
    user_id,
    oab_number,
    oab_state,
    practice_area,
    status
  )
  values (
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    status_value
  )
  returning
    public.lawyer_verifications.id,
    public.lawyer_verifications.submitted_at
  into verification_id_value, submitted_at_value;

  return query
  select
    verification_id_value,
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    status_value,
    submitted_at_value;
end;
$$;

revoke all on function public.submit_lawyer_verification(text, text, text)
from public, anon, authenticated;

grant execute on function public.submit_lawyer_verification(text, text, text)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_018_fix_lawyer_verification_rpc_ambiguity.sql
-- ============================================================================

-- Fixes ambiguous "id" references in submit_lawyer_verification.
--
-- Run after patch_017 if lawyer verification submit fails with:
-- column reference "id" is ambiguous

create or replace function public.submit_lawyer_verification(
  oab_number_value text,
  oab_state_value text,
  practice_area_value text
)
returns table (
  id uuid,
  user_id uuid,
  oab_number text,
  oab_state char(2),
  practice_area text,
  status public.verification_status,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  user_id_value uuid;
  email_value text;
  full_name_value text;
  verification_id_value uuid;
  submitted_at_value timestamptz;
  normalized_oab_number text;
  normalized_oab_state char(2);
  normalized_practice_area text;
  status_value public.verification_status := 'pending';
begin
  user_id_value := auth.uid();

  if user_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_oab_number := nullif(trim(coalesce(oab_number_value, '')), '');
  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')))::char(2);
  normalized_practice_area := nullif(trim(coalesce(practice_area_value, '')), '');

  if normalized_oab_number is null then
    raise exception 'OAB number is required';
  end if;

  if nullif(trim(coalesce(oab_state_value, '')), '') is null then
    raise exception 'OAB state is required';
  end if;

  if normalized_practice_area is null then
    raise exception 'Practice area is required';
  end if;

  email_value := coalesce(auth.jwt() ->> 'email', '');
  full_name_value := coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'full_name', ''),
    nullif(auth.jwt() -> 'user_metadata' ->> 'name', ''),
    nullif(split_part(email_value, '@', 1), ''),
    'Usuário Jurii'
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    lawyer_status
  )
  values (
    user_id_value,
    full_name_value,
    email_value,
    upper(left(full_name_value, 1)),
    'pending'
  )
  on conflict on constraint profiles_pkey do update
  set
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
    email = coalesce(nullif(public.profiles.email, ''), excluded.email),
    initials = coalesce(nullif(public.profiles.initials, ''), excluded.initials),
    lawyer_status = case
      when public.profiles.lawyer_status = 'approved' then 'approved'::public.lawyer_status
      else 'pending'::public.lawyer_status
    end,
    updated_at = now();

  insert into public.lawyer_verifications (
    user_id,
    oab_number,
    oab_state,
    practice_area,
    status
  )
  values (
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    status_value
  )
  returning
    public.lawyer_verifications.id,
    public.lawyer_verifications.submitted_at
  into verification_id_value, submitted_at_value;

  return query
  select
    verification_id_value,
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    status_value,
    submitted_at_value;
end;
$$;

revoke all on function public.submit_lawyer_verification(text, text, text)
from public, anon, authenticated;

grant execute on function public.submit_lawyer_verification(text, text, text)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_019_hide_empty_conversation_drafts.sql
-- ============================================================================

-- Keeps profile chat drafts out of inboxes until a real message exists.
--
-- Run after patch_018. Opening a professional or office profile can create a
-- technical conversation draft so the chat screen has an id, but inboxes should
-- only show conversations after at least one message has been sent.

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
    and case_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      law_firm_id,
      title,
      specialty
    )
    values (
      'client_firm',
      auth.uid(),
      law_firm_id_value,
      firm_row.name,
      firm_row.specialty
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

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and case_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      title,
      specialty
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      profile_row.full_name,
      lawyer_row.primary_area
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

create or replace function public.fetch_conversations_for_current_user(
  scope_value text,
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  with scoped_conversations as (
    select c.*
    from public.conversations c
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages m
        where m.conversation_id = c.id
      )
      and (
        (
          scope_value = 'client'
          and c.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and c.lawyer_id = auth.uid()
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  )
  select
    c.id,
    c.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.full_name, 'Cliente')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.full_name, c.title)
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(c.title), 2))
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from scoped_conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  order by c.last_message_at desc nulls last, c.updated_at desc;
$$;

revoke all on function public.start_or_get_law_firm_conversation(uuid, text)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

grant execute on function public.start_or_get_law_firm_conversation(uuid, text)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_020_restore_chat_draft_metadata.sql
-- ============================================================================

-- Restores conversation draft metadata while keeping empty drafts hidden.
--
-- Run after patch_019. Patch 019 correctly hides conversations that have no
-- real messages from inboxes, so the start RPCs can keep the previous draft
-- metadata expected by the chat flow without making abandoned drafts visible.

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
    and case_id is null
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

  select id
  into conversation_id_value
  from public.conversations
  where client_id = auth.uid()
    and lawyer_id = lawyer_profile_id_value
    and case_id is null
    and type = 'client_firm'
  order by updated_at desc
  limit 1;

  if conversation_id_value is null then
    insert into public.conversations (
      type,
      client_id,
      lawyer_id,
      title,
      specialty,
      last_message,
      last_message_at
    )
    values (
      'client_firm',
      auth.uid(),
      lawyer_profile_id_value,
      profile_row.full_name,
      lawyer_row.primary_area,
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

revoke all on function public.start_or_get_law_firm_conversation(uuid, text)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

grant execute on function public.start_or_get_law_firm_conversation(uuid, text)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;

-- ============================================================================
-- Source: supabase/patch_021_ensure_message_metadata.sql
-- ============================================================================

-- Ensures chat messages have metadata required by case requests and chat UI.
--
-- Run after patch_020 if sending a chat message fails with:
-- column messages.metadata does not exist

alter table public.messages
add column if not exists metadata jsonb;

update public.messages
set metadata = '{}'::jsonb
where metadata is null;

alter table public.messages
alter column metadata set default '{}'::jsonb;

alter table public.messages
alter column metadata set not null;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_022_firm_case_operations.sql
-- ============================================================================

-- Strengthens office case visibility and real operation metrics.
--
-- Run after patch_021. This patch makes accepted cases created by lawyers who
-- belong to an office visible in that office's case area, and exposes real
-- counters for the office home operation section.

alter table public.law_firm_members
add column if not exists created_at timestamptz;

update public.law_firm_members
set created_at = coalesce(created_at, joined_at, now());

alter table public.law_firm_members
alter column created_at set default now();

alter table public.law_firm_members
alter column created_at set not null;

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  scoped_cases as (
    select distinct lc.*
    from public.legal_cases lc
    where exists (
      select 1
      from active_members viewer
      where viewer.profile_id = auth.uid()
    )
    and (
      lc.law_firm_id = law_firm_id_value
      or exists (
        select 1
        from active_members assigned_member
        where assigned_member.profile_id = lc.assigned_lawyer_id
      )
      or exists (
        select 1
        from public.case_participants cp
        join active_members participant_member
          on participant_member.profile_id = cp.profile_id
        where cp.case_id = lc.id
          and cp.role in ('lawyer', 'firm_member')
      )
    )
  )
  select
    sc.id,
    sc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    coalesce(lawyer_profile.full_name, 'Sem advogado definido') as assigned_lawyer,
    sc.area,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    sc.status = 'deadline' as urgent,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$$;

create or replace function public.fetch_law_firm_operation_metrics(
  law_firm_id_value uuid
)
returns table (
  client_messages int,
  team_messages int,
  active_cases int,
  team_members int
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  scoped_cases as (
    select distinct lc.id
    from public.legal_cases lc
    where lc.status <> 'closed'
      and (
        lc.law_firm_id = law_firm_id_value
        or exists (
          select 1
          from active_members assigned_member
          where assigned_member.profile_id = lc.assigned_lawyer_id
        )
        or exists (
          select 1
          from public.case_participants cp
          join active_members participant_member
            on participant_member.profile_id = cp.profile_id
          where cp.case_id = lc.id
            and cp.role in ('lawyer', 'firm_member')
        )
      )
  )
  select
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type <> 'firm_internal'
        and exists (
          select 1
          from public.messages m
          where m.conversation_id = c.id
        )
    ) as client_messages,
    (
      select count(distinct c.id)::int
      from public.conversations c
      where c.law_firm_id = law_firm_id_value
        and c.type = 'firm_internal'
        and exists (
          select 1
          from public.messages m
          where m.conversation_id = c.id
        )
    ) as team_messages,
    (select count(*)::int from scoped_cases) as active_cases,
    (select count(*)::int from active_members) as team_members
  where exists (
    select 1
    from active_members viewer
    where viewer.profile_id = auth.uid()
  );
$$;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_law_firm_operation_metrics(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

grant execute on function public.fetch_law_firm_operation_metrics(uuid)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_023_notifications_realtime.sql
-- ============================================================================

-- Enables realtime delivery for notifications used by the home bell.
--
-- Run after patch_022 if notifications are created in the database but the
-- in-app bell does not update until a manual refresh/rebuild.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_024_case_request_surfaces_repair.sql
-- ============================================================================

-- Repairs and hardens client-facing case request surfaces.
--
-- Run after patch_023 if a lawyer can create a case request but the client
-- does not see a notification or an actionable card in chat.

alter table public.messages
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.case_requests
add column if not exists message_id uuid references public.messages(id) on delete set null;

alter table public.case_requests
add column if not exists notification_id uuid references public.notifications(id) on delete set null;

create index if not exists case_requests_message_idx
on public.case_requests(message_id);

create index if not exists case_requests_notification_idx
on public.case_requests(notification_id);

create or replace function public.ensure_case_request_client_surfaces(
  request_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  actor_name text;
  actor_initials text;
  firm_name text;
  firm_initials text;
  sender_id_value uuid;
  message_id_value uuid;
  notification_id_value uuid;
  status_value text;
  message_body text;
  notification_title text;
  notification_body text;
  metadata_value jsonb;
begin
  select *
  into request_row
  from public.case_requests
  where id = request_id_value;

  if not found then
    return;
  end if;

  select full_name, initials
  into actor_name, actor_initials
  from public.profiles
  where id = coalesce(request_row.requested_by_profile_id, request_row.lawyer_id);

  select name, initials
  into firm_name, firm_initials
  from public.law_firms
  where id = request_row.law_firm_id;

  sender_id_value := coalesce(
    request_row.requested_by_profile_id,
    request_row.lawyer_id,
    request_row.client_id
  );

  status_value := request_row.status::text;

  metadata_value := jsonb_strip_nulls(jsonb_build_object(
    'type', 'case_request',
    'case_request_id', request_row.id,
    'request_status', status_value,
    'conversation_id', request_row.conversation_id,
    'legal_case_id', request_row.legal_case_id,
    'title', request_row.title,
    'area', request_row.area
  ));

  message_body := case request_row.status
    when 'accepted' then 'Caso aceito: ' || request_row.title
    when 'declined' then 'Caso recusado: ' || request_row.title
    when 'cancelled' then 'Solicitação cancelada: ' || request_row.title
    else 'Solicitação de aceite do caso: ' || request_row.title
  end;

  notification_title := case request_row.status
    when 'accepted' then 'Caso aceito'
    when 'declined' then 'Caso recusado'
    when 'cancelled' then 'Solicitação cancelada'
    else 'Solicitação de caso'
  end;

  notification_body := case request_row.status
    when 'accepted' then 'Você aceitou o caso "' || request_row.title || '".'
    when 'declined' then 'Você recusou o caso "' || request_row.title || '".'
    when 'cancelled' then 'A solicitação do caso "' || request_row.title || '" foi cancelada.'
    else coalesce(firm_name, actor_name, 'Jurii') || ' pediu seu aceite para o caso "' || request_row.title || '".'
  end;

  if request_row.message_id is null then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    values (
      request_row.conversation_id,
      sender_id_value,
      'system',
      message_body,
      metadata_value
    )
    returning id into message_id_value;
  else
    update public.messages
    set body = message_body,
        metadata = metadata_value
    where id = request_row.message_id
    returning id into message_id_value;
  end if;

  if request_row.notification_id is null and request_row.status = 'pending' then
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
      request_row.client_id,
      sender_id_value,
      request_row.law_firm_id,
      'case_request',
      notification_title,
      notification_body,
      metadata_value
    )
    returning id into notification_id_value;
  elsif request_row.notification_id is not null then
    update public.notifications
    set title = notification_title,
        body = notification_body,
        metadata = metadata_value,
        read_at = case
          when request_row.status = 'pending' then null
          else coalesce(read_at, now())
        end
    where id = request_row.notification_id
    returning id into notification_id_value;
  end if;

  if message_id_value is not null
      and message_id_value is distinct from request_row.message_id then
    update public.case_requests
    set message_id = message_id_value
    where id = request_row.id;
  end if;

  if notification_id_value is not null
      and notification_id_value is distinct from request_row.notification_id then
    update public.case_requests
    set notification_id = notification_id_value
    where id = request_row.id;
  end if;
end;
$$;

create or replace function public.case_requests_ensure_client_surfaces()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  perform public.ensure_case_request_client_surfaces(new.id);
  return new;
end;
$$;

create or replace function public.create_case_request(
  conversation_id_value uuid,
  title_value text,
  area_value text,
  summary_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  request_row public.case_requests%rowtype;
  request_id_value uuid;
  effective_law_firm_id uuid;
  clean_title text;
  clean_area text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  clean_area := nullif(trim(coalesce(area_value, '')), '');

  if clean_title is null or clean_area is null then
    raise exception 'Title and area are required';
  end if;

  select *
  into conversation_row
  from public.conversations
  where id = conversation_id_value;

  if not found then
    raise exception 'Conversation not found';
  end if;

  effective_law_firm_id := conversation_row.law_firm_id;

  if effective_law_firm_id is null and conversation_row.lawyer_id = auth.uid() then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = auth.uid()
      and lfm.status = 'active'
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    coalesce(lfm.created_at, lfm.joined_at)
    limit 1;
  end if;

  if not (
    conversation_row.lawyer_id = auth.uid()
    or (
      conversation_row.law_firm_id is not null
      and exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = conversation_row.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
    )
  ) then
    raise exception 'Only the responsible professional can request case acceptance';
  end if;

  select *
  into request_row
  from public.case_requests
  where conversation_id = conversation_id_value
    and status = 'pending'
  order by created_at desc
  limit 1;

  if found then
    request_id_value := request_row.id;

    update public.case_requests
    set
      title = clean_title,
      area = clean_area,
      summary = nullif(trim(coalesce(summary_value, '')), ''),
      law_firm_id = effective_law_firm_id,
      requested_by_profile_id = auth.uid()
    where id = request_id_value;
  else
    insert into public.case_requests (
      conversation_id,
      client_id,
      law_firm_id,
      lawyer_id,
      requested_by_profile_id,
      title,
      area,
      summary
    )
    values (
      conversation_row.id,
      conversation_row.client_id,
      effective_law_firm_id,
      conversation_row.lawyer_id,
      auth.uid(),
      clean_title,
      clean_area,
      nullif(trim(coalesce(summary_value, '')), '')
    )
    returning id into request_id_value;
  end if;

  perform public.ensure_case_request_client_surfaces(request_id_value);

  return request_id_value;
end;
$$;

create or replace function public.respond_to_case_request(
  request_id_value uuid,
  accepted_value boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.case_requests%rowtype;
  case_id_value uuid;
  effective_law_firm_id uuid;
  client_name_value text;
  lawyer_name_value text;
  response_status public.case_request_status;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into request_row
  from public.case_requests
  where id = request_id_value
  for update;

  if not found then
    raise exception 'Case request not found';
  end if;

  if request_row.client_id <> auth.uid() then
    raise exception 'Only the client can respond to this case request';
  end if;

  if request_row.status <> 'pending' then
    return request_row.legal_case_id;
  end if;

  effective_law_firm_id := request_row.law_firm_id;

  if effective_law_firm_id is null and request_row.lawyer_id is not null then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = request_row.lawyer_id
      and lfm.status = 'active'
    order by case lfm.member_role
      when 'owner' then 1
      when 'admin' then 2
      when 'lawyer' then 3
      else 4
    end,
    coalesce(lfm.created_at, lfm.joined_at)
    limit 1;

    if effective_law_firm_id is not null then
      update public.case_requests
      set law_firm_id = effective_law_firm_id
      where id = request_id_value;
    end if;
  end if;

  select coalesce(full_name, 'Cliente')
  into client_name_value
  from public.profiles
  where id = request_row.client_id;

  select coalesce(full_name, 'Advogado')
  into lawyer_name_value
  from public.profiles
  where id = request_row.lawyer_id;

  if not accepted_value then
    response_status := 'declined';

    update public.case_requests
    set status = response_status,
        responded_at = now()
    where id = request_id_value;

    perform public.ensure_case_request_client_surfaces(request_id_value);

    insert into public.notifications (
      recipient_profile_id,
      actor_profile_id,
      law_firm_id,
      type,
      title,
      body,
      metadata
    )
    select distinct recipient_id,
      auth.uid(),
      effective_law_firm_id,
      'case_request_response',
      'Solicitação recusada',
      coalesce(client_name_value, 'Cliente') || ' recusou o caso "' || request_row.title || '".',
      jsonb_build_object(
        'case_request_id', request_row.id,
        'request_status', 'declined',
        'conversation_id', request_row.conversation_id,
        'title', request_row.title,
        'area', request_row.area
      )
    from (
      values (request_row.lawyer_id), (request_row.requested_by_profile_id)
    ) as recipients(recipient_id)
    where recipient_id is not null
      and recipient_id <> auth.uid();

    return null;
  end if;

  response_status := 'accepted';

  insert into public.legal_cases (
    title,
    area,
    status,
    client_id,
    law_firm_id,
    assigned_lawyer_id,
    description,
    last_update_label
  )
  values (
    request_row.title,
    request_row.area,
    'open',
    request_row.client_id,
    effective_law_firm_id,
    request_row.lawyer_id,
    request_row.summary,
    'Caso aceito pelo cliente'
  )
  returning id into case_id_value;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, request_row.client_id, 'client')
  on conflict (case_id, profile_id) do nothing;

  if request_row.lawyer_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (case_id_value, request_row.lawyer_id, 'lawyer')
    on conflict (case_id, profile_id) do nothing;
  end if;

  if request_row.requested_by_profile_id is not null then
    insert into public.case_participants (case_id, profile_id, role)
    values (
      case_id_value,
      request_row.requested_by_profile_id,
      case
        when request_row.requested_by_profile_id = request_row.lawyer_id then 'lawyer'
        else 'firm_member'
      end::public.case_participant_role
    )
    on conflict (case_id, profile_id) do nothing;
  end if;

  insert into public.case_updates (
    case_id,
    author_profile_id,
    title,
    body
  )
  values (
    case_id_value,
    auth.uid(),
    'Caso iniciado',
    'O cliente aceitou a solicitação e o caso foi criado na Jurii.'
  );

  update public.conversations
  set case_id = case_id_value,
      updated_at = now()
  where id = request_row.conversation_id;

  update public.case_requests
  set status = response_status,
      legal_case_id = case_id_value,
      responded_at = now()
  where id = request_id_value;

  perform public.ensure_case_request_client_surfaces(request_id_value);

  insert into public.notifications (
    recipient_profile_id,
    actor_profile_id,
    law_firm_id,
    type,
    title,
    body,
    metadata
  )
  select distinct recipient_id,
    auth.uid(),
    effective_law_firm_id,
    'case_request_response',
    'Caso aceito',
    coalesce(client_name_value, 'Cliente') || ' aceitou o caso "' || request_row.title || '".',
    jsonb_build_object(
      'case_request_id', request_row.id,
      'request_status', 'accepted',
      'conversation_id', request_row.conversation_id,
      'legal_case_id', case_id_value,
      'title', request_row.title,
      'area', request_row.area
    )
  from (
    values (request_row.lawyer_id), (request_row.requested_by_profile_id)
  ) as recipients(recipient_id)
  where recipient_id is not null
    and recipient_id <> auth.uid();

  if effective_law_firm_id is not null then
    insert into public.notifications (
      recipient_profile_id,
      actor_profile_id,
      law_firm_id,
      type,
      title,
      body,
      metadata
    )
    select distinct
      lfm.profile_id,
      request_row.client_id,
      effective_law_firm_id,
      'firm_case_started',
      'Novo caso no escritório',
      coalesce(lawyer_name_value, 'Advogado') || ' iniciou um novo caso com ' || coalesce(client_name_value, 'Cliente') || '.',
      jsonb_build_object(
        'case_id', case_id_value,
        'case_request_id', request_row.id,
        'request_status', 'accepted',
        'conversation_id', request_row.conversation_id,
        'law_firm_id', effective_law_firm_id,
        'title', request_row.title,
        'area', request_row.area
      )
    from public.law_firm_members lfm
    where lfm.law_firm_id = effective_law_firm_id
      and lfm.profile_id is not null
      and lfm.status = 'active'
      and lfm.member_role in ('owner', 'admin', 'secretary');
  end if;

  return case_id_value;
end;
$$;

drop trigger if exists case_requests_ensure_client_surfaces on public.case_requests;
create trigger case_requests_ensure_client_surfaces
after insert or update of title, area, status, legal_case_id, message_id, notification_id
on public.case_requests
for each row execute function public.case_requests_ensure_client_surfaces();

do $$
declare
  request_record record;
begin
  for request_record in
    select id
    from public.case_requests
    where status = 'pending'
       or message_id is null
       or notification_id is null
  loop
    perform public.ensure_case_request_client_surfaces(request_record.id);
  end loop;
end $$;

revoke all on function public.ensure_case_request_client_surfaces(uuid)
from public, anon, authenticated;

revoke all on function public.case_requests_ensure_client_surfaces()
from public, anon, authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

revoke all on function public.respond_to_case_request(uuid, boolean)
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

grant execute on function public.respond_to_case_request(uuid, boolean)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_025_notification_scopes.sql
-- ============================================================================

-- Segments notifications by app flow.
--
-- Run after patch_024. Notifications are now scoped to the area that should
-- display them: client, lawyer or firm. The app filters each bell by this
-- scope, and the cards use the matching visual theme as reinforcement.

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'notification_scope'
  ) then
    create type public.notification_scope as enum ('client', 'lawyer', 'firm');
  end if;
end $$;

alter table public.notifications
add column if not exists scope public.notification_scope not null default 'client';

create or replace function public.infer_notification_scope(
  type_value text,
  current_scope public.notification_scope default null
)
returns public.notification_scope
language sql
immutable
set search_path = public
as $$
  select case
    when type_value in ('team_invite', 'case_request_response') then 'lawyer'::public.notification_scope
    when type_value in ('firm_case_started') then 'firm'::public.notification_scope
    when type_value in ('case_request', 'message', 'case_update') then 'client'::public.notification_scope
    else coalesce(current_scope, 'client'::public.notification_scope)
  end;
$$;

create or replace function public.notifications_set_scope()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.scope := public.infer_notification_scope(new.type, new.scope);
  return new;
end;
$$;

drop trigger if exists notifications_set_scope on public.notifications;
create trigger notifications_set_scope
before insert or update of type, scope
on public.notifications
for each row execute function public.notifications_set_scope();

update public.notifications
set scope = public.infer_notification_scope(type, scope);

create index if not exists notifications_recipient_scope_created_idx
on public.notifications(recipient_profile_id, scope, created_at desc);

create index if not exists notifications_recipient_scope_unread_idx
on public.notifications(recipient_profile_id, scope)
where read_at is null;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_026_practice_area_tags_search.sql
-- ============================================================================

-- Multi-area practice tags for lawyer and law firm onboarding/search.
--
-- Run after patch_025. This keeps the legacy primary area fields for existing
-- screens, while adding practice_areas arrays for multi-tag search.

alter table public.lawyer_verifications
add column if not exists practice_areas text[] not null default '{}'::text[];

alter table public.lawyer_profiles
add column if not exists practice_areas text[] not null default '{}'::text[];

alter table public.law_firm_verifications
add column if not exists practice_areas text[] not null default '{}'::text[];

alter table public.law_firms
add column if not exists practice_areas text[] not null default '{}'::text[];

update public.lawyer_verifications
set practice_areas = array[practice_area]
where cardinality(practice_areas) = 0
  and nullif(trim(coalesce(practice_area, '')), '') is not null;

update public.lawyer_profiles
set practice_areas = array[primary_area]
where cardinality(practice_areas) = 0
  and nullif(trim(coalesce(primary_area, '')), '') is not null;

update public.law_firms
set practice_areas = array[specialty]
where cardinality(practice_areas) = 0
  and nullif(trim(coalesce(specialty, '')), '') is not null;

create index if not exists lawyer_profiles_practice_areas_idx
on public.lawyer_profiles using gin (practice_areas);

create index if not exists law_firms_practice_areas_idx
on public.law_firms using gin (practice_areas);

create or replace function public.normalize_practice_area_search(value text)
returns text
language sql
immutable
as $$
  select translate(
    lower(trim(coalesce(value, ''))),
    'áàâãéêíóôõúüç',
    'aaaaeeiooouuc'
  );
$$;

drop function if exists public.submit_lawyer_verification(text, text, text);

create or replace function public.submit_lawyer_verification(
  oab_number_value text,
  oab_state_value text,
  practice_area_value text,
  practice_areas_value text[] default null
)
returns table (
  id uuid,
  user_id uuid,
  oab_number text,
  oab_state char(2),
  practice_area text,
  practice_areas text[],
  status public.verification_status,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  user_id_value uuid;
  email_value text;
  full_name_value text;
  verification_id_value uuid;
  submitted_at_value timestamptz;
  normalized_oab_number text;
  normalized_oab_state char(2);
  normalized_practice_area text;
  normalized_practice_areas text[];
  status_value public.verification_status := 'pending';
begin
  user_id_value := auth.uid();

  if user_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_oab_number := nullif(trim(coalesce(oab_number_value, '')), '');
  normalized_oab_state := upper(trim(coalesce(oab_state_value, '')))::char(2);
  normalized_practice_area :=
    nullif(trim(coalesce(practice_area_value, '')), '');

  select coalesce(array_agg(area order by first_ordinal), '{}'::text[])
  into normalized_practice_areas
  from (
    select trim(area_value) as area, min(ordinality) as first_ordinal
    from unnest(coalesce(practice_areas_value, '{}'::text[]))
      with ordinality as areas(area_value, ordinality)
    where nullif(trim(area_value), '') is not null
    group by trim(area_value)
  ) clean_areas;

  if cardinality(normalized_practice_areas) = 0
      and normalized_practice_area is not null then
    normalized_practice_areas := array[normalized_practice_area];
  end if;

  if normalized_practice_area is null
      and cardinality(normalized_practice_areas) > 0 then
    normalized_practice_area := normalized_practice_areas[1];
  end if;

  if normalized_oab_number is null then
    raise exception 'OAB number is required';
  end if;

  if nullif(trim(coalesce(oab_state_value, '')), '') is null then
    raise exception 'OAB state is required';
  end if;

  if normalized_practice_area is null then
    raise exception 'Practice area is required';
  end if;

  email_value := coalesce(auth.jwt() ->> 'email', '');
  full_name_value := coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'full_name', ''),
    nullif(auth.jwt() -> 'user_metadata' ->> 'name', ''),
    nullif(split_part(email_value, '@', 1), ''),
    'Usuário Jurii'
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    lawyer_status
  )
  values (
    user_id_value,
    full_name_value,
    email_value,
    upper(left(full_name_value, 1)),
    'pending'
  )
  on conflict on constraint profiles_pkey do update
  set
    full_name = coalesce(
      nullif(public.profiles.full_name, ''),
      excluded.full_name
    ),
    email = coalesce(nullif(public.profiles.email, ''), excluded.email),
    initials = coalesce(
      nullif(public.profiles.initials, ''),
      excluded.initials
    ),
    lawyer_status = case
      when public.profiles.lawyer_status = 'approved' then
        'approved'::public.lawyer_status
      else 'pending'::public.lawyer_status
    end,
    updated_at = now();

  insert into public.lawyer_verifications (
    user_id,
    oab_number,
    oab_state,
    practice_area,
    practice_areas,
    status
  )
  values (
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    normalized_practice_areas,
    status_value
  )
  returning
    public.lawyer_verifications.id,
    public.lawyer_verifications.submitted_at
  into verification_id_value, submitted_at_value;

  return query
  select
    verification_id_value,
    user_id_value,
    normalized_oab_number,
    normalized_oab_state,
    normalized_practice_area,
    normalized_practice_areas,
    status_value,
    submitted_at_value;
end;
$$;

create or replace function public.approve_lawyer_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.lawyer_verifications%rowtype;
  areas_value text[];
  primary_area_value text;
begin
  select *
  into verification_row
  from public.lawyer_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Lawyer verification not found: %', verification_id_value;
  end if;

  areas_value := coalesce(verification_row.practice_areas, '{}'::text[]);
  primary_area_value :=
    nullif(trim(coalesce(verification_row.practice_area, '')), '');

  if cardinality(areas_value) = 0 and primary_area_value is not null then
    areas_value := array[primary_area_value];
  end if;

  if primary_area_value is null and cardinality(areas_value) > 0 then
    primary_area_value := areas_value[1];
  end if;

  primary_area_value := coalesce(primary_area_value, 'Atendimento jurídico');

  update public.lawyer_verifications
  set
    status = 'approved',
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  update public.profiles
  set lawyer_status = 'approved'
  where id = verification_row.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    practice_areas,
    approved_at
  )
  values (
    verification_row.user_id,
    verification_row.oab_number,
    verification_row.oab_state,
    primary_area_value,
    areas_value,
    now()
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    practice_areas = excluded.practice_areas,
    approved_at = coalesce(
      public.lawyer_profiles.approved_at,
      excluded.approved_at
    );

  return verification_row.user_id;
end;
$$;

create or replace function public.approve_law_firm_verification(
  verification_id_value uuid,
  reviewer_id_value uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  verification_row public.law_firm_verifications%rowtype;
  firm_id_value uuid;
  initials_value text;
  existing_member_id uuid;
  areas_value text[];
  specialty_value text;
begin
  select *
  into verification_row
  from public.law_firm_verifications
  where id = verification_id_value;

  if not found then
    raise exception 'Law firm verification not found: %',
      verification_id_value;
  end if;

  initials_value := upper(left(trim(verification_row.firm_name), 1));
  if initials_value is null or initials_value = '' then
    initials_value := 'E';
  end if;

  areas_value := coalesce(verification_row.practice_areas, '{}'::text[]);
  if cardinality(areas_value) = 0 then
    areas_value := array['Escritório jurídico'];
  end if;
  specialty_value := coalesce(areas_value[1], 'Escritório jurídico');

  if verification_row.law_firm_id is null then
    insert into public.law_firms (
      name,
      initials,
      specialty,
      practice_areas,
      rating,
      reviews_count,
      distance_label,
      avatar_type,
      phone,
      email,
      address,
      is_active
    )
    values (
      verification_row.firm_name,
      initials_value,
      specialty_value,
      areas_value,
      0,
      0,
      '',
      'purple',
      nullif(verification_row.phone, ''),
      nullif(verification_row.email, ''),
      nullif(verification_row.address, ''),
      true
    )
    returning id into firm_id_value;
  else
    firm_id_value := verification_row.law_firm_id;

    update public.law_firms
    set
      name = verification_row.firm_name,
      initials = initials_value,
      specialty = specialty_value,
      practice_areas = areas_value,
      phone = nullif(verification_row.phone, ''),
      email = nullif(verification_row.email, ''),
      address = nullif(verification_row.address, ''),
      avatar_type = 'purple',
      is_active = true,
      updated_at = now()
    where id = firm_id_value;
  end if;

  update public.law_firm_verifications
  set
    status = 'approved',
    law_firm_id = firm_id_value,
    reviewed_at = now(),
    reviewer_id = reviewer_id_value,
    rejection_reason = null
  where id = verification_id_value;

  select id
  into existing_member_id
  from public.law_firm_members
  where law_firm_id = firm_id_value
    and profile_id = verification_row.owner_profile_id
  limit 1;

  if existing_member_id is null then
    insert into public.law_firm_members (
      law_firm_id,
      profile_id,
      role,
      member_role,
      status
    )
    values (
      firm_id_value,
      verification_row.owner_profile_id,
      'owner',
      'owner',
      'active'
    );
  else
    update public.law_firm_members
    set
      role = 'owner',
      member_role = 'owner',
      status = 'active'
    where id = existing_member_id;
  end if;

  return firm_id_value;
end;
$$;

drop function if exists public.fetch_recommended_lawyers(int);

create or replace function public.fetch_recommended_lawyers(
  limit_value int default 6,
  search_value text default null
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  )
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    case
      when cardinality(lp.practice_areas) > 0 then lp.practice_areas
      else array[lp.primary_area]
    end as practice_areas,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  cross join search
  where lp.is_available = true
    and (
      search.q is null
      or public.normalize_practice_area_search(p.full_name)
        like '%' || search.q || '%'
      or public.normalize_practice_area_search(lp.primary_area)
        like '%' || search.q || '%'
      or exists (
        select 1
        from unnest(coalesce(lp.practice_areas, '{}'::text[])) as area
        where public.normalize_practice_area_search(area)
          like '%' || search.q || '%'
      )
    )
  order by lp.approved_at desc nulls last, lp.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

drop function if exists public.fetch_lawyer_public_profile(uuid);

create or replace function public.fetch_lawyer_public_profile(
  lawyer_profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    case
      when cardinality(lp.practice_areas) > 0 then lp.practice_areas
      else array[lp.primary_area]
    end as practice_areas,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
  limit 1;
$$;

create or replace function public.fetch_recommended_law_firms(
  limit_value int default 10,
  search_value text default null
)
returns table (
  id uuid,
  name text,
  initials text,
  rating numeric,
  distance_label text,
  specialty text,
  practice_areas text[],
  reviews_count int,
  avatar_type text,
  description text,
  phone text,
  email text,
  website_url text,
  address text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  )
  select
    lf.id,
    lf.name,
    lf.initials,
    lf.rating,
    lf.distance_label,
    lf.specialty,
    case
      when cardinality(lf.practice_areas) > 0 then lf.practice_areas
      else array[lf.specialty]
    end as practice_areas,
    lf.reviews_count,
    lf.avatar_type,
    lf.description,
    lf.phone,
    lf.email,
    lf.website_url,
    lf.address
  from public.law_firms lf
  cross join search
  where lf.is_active = true
    and (
      search.q is null
      or public.normalize_practice_area_search(lf.name)
        like '%' || search.q || '%'
      or public.normalize_practice_area_search(lf.specialty)
        like '%' || search.q || '%'
      or exists (
        select 1
        from unnest(coalesce(lf.practice_areas, '{}'::text[])) as area
        where public.normalize_practice_area_search(area)
          like '%' || search.q || '%'
      )
    )
  order by lf.rating desc, lf.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;

revoke all on function public.normalize_practice_area_search(text)
from public, anon, authenticated;

revoke all on function public.submit_lawyer_verification(text, text, text, text[])
from public, anon, authenticated;

revoke all on function public.approve_lawyer_verification(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.approve_law_firm_verification(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_lawyers(int, text)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon, authenticated;

grant execute on function public.submit_lawyer_verification(text, text, text, text[])
to authenticated;

grant execute on function public.approve_lawyer_verification(uuid, uuid)
to service_role;

grant execute on function public.approve_law_firm_verification(uuid, uuid)
to service_role;

grant execute on function public.fetch_recommended_lawyers(int, text)
to authenticated;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_027_strict_lawyer_case_scope.sql
-- ============================================================================

-- Ensures the professional case list never includes cases where the current
-- user only participates as the client.
--
-- Run after patch_026 if a user who is also a lawyer sees their own client
-- cases inside the lawyer flow. The client flow continues to use
-- fetch_client_cases().

create or replace function public.fetch_lawyer_cases()
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  area text,
  last_update_label text,
  status text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct
    lc.id,
    lc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    lc.area,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.status::text as status,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.assigned_lawyer_id = auth.uid()
     or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = lc.id
        and cp.profile_id = auth.uid()
        and cp.role in ('lawyer', 'firm_member')
     )
  order by lc.updated_at desc;
$$;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_028_self_lawyer_invite_requires_acceptance.sql
-- ============================================================================

-- Requires explicit lawyer acceptance even when an office owner/admin invites
-- their own verified lawyer profile by OAB.
--
-- Run after patch_027. This keeps the office leadership membership active,
-- but tracks the lawyer association as a separate pending invite until the
-- lawyer accepts it from the notification bell.

alter table public.law_firm_members
add column if not exists lawyer_invite_status public.law_firm_member_status;

alter table public.law_firm_members
add column if not exists pending_lawyer_id uuid references public.lawyer_profiles(id) on delete set null;

create index if not exists law_firm_members_pending_lawyer_idx
on public.law_firm_members(pending_lawyer_id)
where pending_lawyer_id is not null;

update public.law_firm_members
set lawyer_invite_status = case
  when status = 'invited' then 'invited'::public.law_firm_member_status
  when status = 'disabled' then 'disabled'::public.law_firm_member_status
  when lawyer_id is not null then 'active'::public.law_firm_member_status
  else lawyer_invite_status
end
where lawyer_invite_status is null;

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
  target_verification public.lawyer_verifications%rowtype;
  target_profile public.profiles%rowtype;
  existing_member public.law_firm_members%rowtype;
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
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

  select *
  into target_verification
  from public.lawyer_verifications lv
  where lv.status = 'approved'
    and upper(trim(lv.oab_state)) = normalized_oab_state
    and regexp_replace(upper(coalesce(lv.oab_number, '')), '[^A-Z0-9]', '', 'g')
      = normalized_oab_number
  order by lv.reviewed_at desc nulls last, lv.submitted_at desc
  limit 1;

  if not found then
    raise exception 'Lawyer not found or not approved for this OAB';
  end if;

  select *
  into target_profile
  from public.profiles
  where id = target_verification.user_id;

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  update public.profiles
  set lawyer_status = 'approved'
  where id = target_verification.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    approved_at
  )
  values (
    target_verification.user_id,
    target_verification.oab_number,
    target_verification.oab_state,
    target_verification.practice_area,
    coalesce(target_verification.reviewed_at, now())
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    approved_at = coalesce(public.lawyer_profiles.approved_at, excluded.approved_at);

  select *
  into existing_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_verification.user_id
      or lawyer_id = target_verification.user_id
      or pending_lawyer_id = target_verification.user_id
    )
  limit 1;

  if found
      and existing_member.lawyer_id = target_verification.user_id
      and existing_member.lawyer_invite_status = 'active' then
    raise exception 'Lawyer already active in this office';
  end if;

  if found
      and existing_member.pending_lawyer_id = target_verification.user_id
      and existing_member.lawyer_invite_status = 'invited' then
    raise exception 'Lawyer invite already pending';
  end if;

  if not found then
    insert into public.law_firm_members (
      law_firm_id,
      lawyer_id,
      profile_id,
      role,
      member_role,
      status,
      lawyer_invite_status,
      pending_lawyer_id
    )
    values (
      law_firm_id_value,
      target_verification.user_id,
      target_verification.user_id,
      'lawyer',
      'lawyer',
      'invited',
      'invited',
      null
    )
    returning id into membership_id_value;
  else
    existing_is_manager :=
      existing_member.status = 'active'
      and existing_member.member_role in ('owner', 'admin', 'secretary');

    update public.law_firm_members
    set
      profile_id = target_verification.user_id,
      lawyer_id = case
        when existing_is_manager then lawyer_id
        else target_verification.user_id
      end,
      pending_lawyer_id = case
        when existing_is_manager then target_verification.user_id
        else null
      end,
      lawyer_invite_status = 'invited',
      role = case
        when existing_is_manager then role
        else 'lawyer'
      end,
      member_role = case
        when existing_is_manager then member_role
        else 'lawyer'::public.law_firm_member_role
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
    target_verification.user_id,
    auth.uid(),
    law_firm_id_value,
    'team_invite',
    'Convite para escritório',
    coalesce(firm_name_value, 'Um escritório') ||
      ' convidou você para integrar a equipe.',
    jsonb_build_object(
      'membership_id', membership_id_value,
      'invite_status', null,
      'lawyer_invite_status', 'invited'
    )
  );

  return membership_id_value;
end;
$$;

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

  if membership_row.profile_id <> auth.uid() then
    raise exception 'Only the invited lawyer can respond to this invite';
  end if;

  if membership_row.status <> 'invited'
      and membership_row.lawyer_invite_status <> 'invited' then
    raise exception 'Invite is no longer pending';
  end if;

  is_manager_membership :=
    membership_row.status = 'active'
    and membership_row.member_role in ('owner', 'admin', 'secretary');

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

with frozen_self_invites as (
  select
    n.id as notification_id,
    n.recipient_profile_id,
    (n.metadata ->> 'membership_id')::uuid as membership_id
  from public.notifications n
  join public.law_firm_members lfm
    on lfm.id = (n.metadata ->> 'membership_id')::uuid
  where n.type = 'team_invite'
    and n.read_at is null
    and n.actor_profile_id = n.recipient_profile_id
    and n.metadata ->> 'membership_id' is not null
    and n.metadata ->> 'invite_status' is null
    and lfm.profile_id = n.recipient_profile_id
    and lfm.status = 'active'
    and lfm.member_role in ('owner', 'admin', 'secretary')
)
update public.law_firm_members lfm
set
  pending_lawyer_id = frozen_self_invites.recipient_profile_id,
  lawyer_invite_status = 'invited',
  lawyer_id = case
    when lfm.lawyer_id = frozen_self_invites.recipient_profile_id then null
    else lfm.lawyer_id
  end
from frozen_self_invites
where lfm.id = frozen_self_invites.membership_id;

with frozen_self_invites as (
  select n.id
  from public.notifications n
  join public.law_firm_members lfm
    on lfm.id = (n.metadata ->> 'membership_id')::uuid
  where n.type = 'team_invite'
    and n.read_at is null
    and n.actor_profile_id = n.recipient_profile_id
    and n.metadata ->> 'membership_id' is not null
    and n.metadata ->> 'invite_status' is null
    and lfm.profile_id = n.recipient_profile_id
    and lfm.lawyer_invite_status = 'invited'
)
update public.notifications n
set metadata = n.metadata || jsonb_build_object('lawyer_invite_status', 'invited')
from frozen_self_invites
where n.id = frozen_self_invites.id;

revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
to authenticated;

revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
from public, anon;

grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_029_legal_search_intents.sql
-- ============================================================================

-- Adds intent-based legal search on top of practice-area tags.
--
-- Run after patch_028. It lets the client search describe a problem in plain
-- language, such as "Maria da Penha" or "estupro", and still match lawyers
-- and firms tagged as Direito Criminal.

create table if not exists public.legal_search_intents (
  id uuid primary key default gen_random_uuid(),
  phrase text not null,
  normalized_phrase text not null,
  practice_area text not null,
  related_tags text[] not null default '{}'::text[],
  weight int not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (normalized_phrase, practice_area)
);

create index if not exists legal_search_intents_normalized_phrase_idx
on public.legal_search_intents(normalized_phrase);

create index if not exists legal_search_intents_practice_area_idx
on public.legal_search_intents(practice_area);

alter table public.legal_search_intents enable row level security;

drop policy if exists "legal_search_intents_read_active"
on public.legal_search_intents;

create policy "legal_search_intents_read_active"
on public.legal_search_intents for select
to authenticated
using (is_active = true);

create or replace function public.normalize_practice_area_search(value text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(
    regexp_replace(
      translate(
        lower(trim(coalesce(value, ''))),
        'áàâãéêíóôõúüç',
        'aaaaeeiooouuc'
      ),
      '[^a-z0-9]+',
      ' ',
      'g'
    ),
    '[[:space:]]+',
    ' ',
    'g'
  ));
$$;

create or replace function public.legal_search_term_matches(
  normalized_query text,
  normalized_term text
)
returns boolean
language sql
immutable
as $$
  with cleaned as (
    select
      nullif(trim(coalesce(normalized_query, '')), '') as q,
      nullif(trim(coalesce(normalized_term, '')), '') as term
  ),
  query_tokens as (
    select query_token.token
    from cleaned,
      regexp_split_to_table(cleaned.q, ' ') as query_token(token)
    where length(query_token.token) >= 3
  ),
  term_tokens as (
    select term_token.token
    from cleaned,
      regexp_split_to_table(cleaned.term, ' ') as term_token(token)
    where length(term_token.token) >= 3
  ),
  term_count as (
    select count(*) as total
    from term_tokens
  )
  select coalesce(
    cleaned.q like '%' || cleaned.term || '%'
    or cleaned.term like '%' || cleaned.q || '%'
    or (
      (select total from term_count) >= 2
      and not exists (
        select 1
        from term_tokens
        where not exists (
          select 1
          from query_tokens
          where query_tokens.token = term_tokens.token
        )
      )
    ),
    false
  )
  from cleaned;
$$;

with seed(practice_areas, weight, terms) as (
  values
    (
      array['Direito Criminal']::text[],
      130,
      array[
        'advogado criminal',
        'advogado criminalista',
        'direito penal',
        'processo criminal',
        'processo penal',
        'acusado',
        'acusação',
        'acusaram',
        'réu',
        'réu primário',
        'vítima de crime',
        'crime',
        'crime grave',
        'denúncia criminal',
        'queixa crime',
        'Maria da Penha',
        'Lei Maria da Penha',
        'violência doméstica',
        'violência contra mulher',
        'violência contra a mulher',
        'violência familiar',
        'mulher agredida',
        'apanhei do marido',
        'marido bateu',
        'marido me bateu',
        'meu marido me bateu',
        'namorado me bateu',
        'ex me bateu',
        'ex me ameaça',
        'ex me ameaçou',
        'meu ex me persegue',
        'perseguição',
        'stalking',
        'medida protetiva',
        'descumpriu medida protetiva',
        'quebrou medida protetiva',
        'estupro',
        'estupro de vulnerável',
        'abuso sexual',
        'assédio sexual',
        'importunação sexual',
        'crime sexual',
        'violência sexual',
        'toque sem consentimento',
        'fui abusada',
        'fui abusado',
        'ameaça',
        'ameaçaram',
        'fui ameaçado',
        'fui ameaçada',
        'ameaça pelo whatsapp',
        'agressão',
        'agressão física',
        'fui agredido',
        'fui agredida',
        'me bateram',
        'lesão corporal',
        'homicídio',
        'tentativa de homicídio',
        'briga',
        'briga de rua',
        'roubo',
        'furto',
        'assalto',
        'fui assaltado',
        'fui assaltada',
        'me roubaram',
        'roubaram meu celular',
        'invadiram minha casa',
        'arrombamento',
        'receptação',
        'estelionato',
        'golpe',
        'caí em golpe',
        'fraude',
        'extorsão',
        'chantagem',
        'sequestro',
        'cárcere privado',
        'prisão',
        'preso',
        'foi preso',
        'prenderam',
        'flagrante',
        'prisão em flagrante',
        'audiência de custódia',
        'habeas corpus',
        'fiança',
        'tornozeleira eletrônica',
        'regime aberto',
        'regime semiaberto',
        'execução penal',
        'delegacia',
        'intimação policial',
        'depoimento na delegacia',
        'inquérito policial',
        'boletim de ocorrência',
        'b o',
        'fazer boletim',
        'trafico de drogas',
        'tráfico de drogas',
        'porte de droga',
        'porte de maconha',
        'drogas',
        'lei seca',
        'embriaguez ao volante',
        'calúnia',
        'injúria',
        'difamação',
        'falsa acusação',
        'nudes vazados',
        'vazaram nudes',
        'pornografia de vingança'
      ]::text[]
    ),
    (
      array['Direito de Família']::text[],
      125,
      array[
        'advogado de família',
        'direito de família',
        'divórcio',
        'divorciar',
        'quero divorciar',
        'quero me separar',
        'separação',
        'separação amigável',
        'separação litigiosa',
        'divórcio amigável',
        'divórcio litigioso',
        'fim do casamento',
        'casamento acabou',
        'pensão alimentícia',
        'pensão',
        'pensão atrasada',
        'não paga pensão',
        'não pagou pensão',
        'pai não paga pensão',
        'mãe não paga pensão',
        'aumentar pensão',
        'diminuir pensão',
        'revisão de pensão',
        'execução de alimentos',
        'alimentos',
        'alimentos gravídicos',
        'guarda',
        'guarda compartilhada',
        'guarda unilateral',
        'guarda dos filhos',
        'pegar guarda',
        'perder guarda',
        'visitas',
        'direito de visita',
        'regulamentação de visitas',
        'mãe não deixa ver filho',
        'pai não deixa ver filho',
        'não consigo ver meu filho',
        'união estável',
        'dissolução de união estável',
        'contrato de união estável',
        'alienação parental',
        'partilha',
        'partilha de bens',
        'dividir bens',
        'bens do casal',
        'regime de bens',
        'pacto antenupcial',
        'paternidade',
        'reconhecimento de paternidade',
        'exame de dna',
        'dna',
        'nome do pai',
        'adoção',
        'adotar',
        'tutela',
        'curatela',
        'interdição familiar',
        'inventário familiar',
        'herança de família',
        'briga de herança',
        'testamento da família'
      ]::text[]
    ),
    (
      array['Direito Trabalhista']::text[],
      120,
      array[
        'advogado trabalhista',
        'direito trabalhista',
        'trabalho',
        'emprego',
        'patrão',
        'empresa não pagou',
        'patrão não pagou',
        'chefe',
        'demissão',
        'fui demitido',
        'fui demitida',
        'me mandaram embora',
        'mandaram embora',
        'demitido sem receber',
        'demitida sem receber',
        'não recebi acerto',
        'acerto trabalhista',
        'acordo trabalhista',
        'rescisão',
        'rescisão trabalhista',
        'fgts',
        'fgts atrasado',
        'fgts não depositado',
        'não depositaram fgts',
        'horas extras',
        'hora extra',
        'banco de horas',
        'jornada de trabalho',
        'intervalo',
        'não tenho intervalo',
        'trabalho demais',
        'assédio moral',
        'humilhação no trabalho',
        'chefe humilha',
        'chefe grita',
        'perseguição no trabalho',
        'assédio sexual no trabalho',
        'chefe me assedia',
        'salário atrasado',
        'salário não pago',
        'pagamento atrasado',
        'décimo terceiro',
        '13 atrasado',
        'férias',
        'férias vencidas',
        'férias não pagas',
        'verbas rescisórias',
        'justa causa',
        'demissão por justa causa',
        'reverter justa causa',
        'carteira assinada',
        'trabalho sem carteira',
        'não assinaram carteira',
        'vínculo empregatício',
        'pejotização',
        'mei obrigado',
        'sou mei mas sou empregado',
        'autônomo mas empregado',
        'desvio de função',
        'acúmulo de função',
        'equiparação salarial',
        'adicional noturno',
        'periculosidade',
        'insalubridade',
        'acidente de trabalho',
        'doença ocupacional',
        'estabilidade gestante',
        'licença maternidade',
        'cipa',
        'sindicato',
        'doméstica',
        'empregada doméstica',
        'diarista',
        'motorista de aplicativo',
        'entregador de aplicativo',
        'processo trabalhista',
        'reclamação trabalhista'
      ]::text[]
    ),
    (
      array['Direito do Consumidor']::text[],
      115,
      array[
        'advogado consumidor',
        'direito do consumidor',
        'procon',
        'juizado consumidor',
        'pequenas causas consumidor',
        'produto defeituoso',
        'produto com defeito',
        'produto quebrado',
        'comprei e não chegou',
        'compra não chegou',
        'pedido não chegou',
        'loja não entregou',
        'atraso na entrega',
        'loja não troca',
        'troca negada',
        'garantia',
        'garantia negada',
        'cobrança indevida',
        'cobraram errado',
        'boleto indevido',
        'fatura errada',
        'cobrança abusiva',
        'juros abusivos',
        'nome sujo',
        'negativação',
        'negativação indevida',
        'serasa',
        'spc',
        'protesto indevido',
        'cartão de crédito',
        'cartão clonado',
        'plano de saúde',
        'convênio médico',
        'plano negou cirurgia',
        'plano negou tratamento',
        'plano negou exame',
        'cirurgia negada',
        'tratamento negado',
        'banco',
        'banco bloqueou conta',
        'conta bloqueada',
        'empréstimo não contratado',
        'empréstimo consignado',
        'desconto indevido',
        'financiamento',
        'consórcio',
        'seguro',
        'seguradora não paga',
        'viagem cancelada',
        'passagem cancelada',
        'voo cancelado',
        'voo atrasado',
        'bagagem extraviada',
        'overbooking',
        'hotel cancelado',
        'mensalidade',
        'faculdade',
        'escola',
        'curso online',
        'assinatura',
        'cancelar assinatura',
        'cobrança de assinatura',
        'telefone',
        'internet',
        'operadora',
        'energia elétrica',
        'conta de luz',
        'água',
        'conta de água',
        'marketplace',
        'app de entrega',
        'compra online',
        'propaganda enganosa',
        'fraude bancária',
        'pix errado',
        'golpe do pix'
      ]::text[]
    ),
    (
      array['Direito Previdenciário']::text[],
      115,
      array[
        'advogado previdenciário',
        'direito previdenciário',
        'previdência',
        'inss',
        'meu inss',
        'aposentadoria',
        'aposentadoria negada',
        'aposentar',
        'aposentadoria por idade',
        'aposentadoria por tempo',
        'aposentadoria especial',
        'tempo de contribuição',
        'revisão da aposentadoria',
        'revisão da vida toda',
        'auxílio doença',
        'auxílio por incapacidade',
        'benefício por incapacidade',
        'bpc',
        'loas',
        'benefício negado',
        'benefício cortado',
        'meu benefício foi cortado',
        'pente fino',
        'perícia',
        'perícia negada',
        'perícia médica',
        'laudo médico',
        'incapacidade',
        'auxílio acidente',
        'pensão por morte',
        'salário maternidade',
        'salario maternidade',
        'recurso inss',
        'indeferido inss',
        'pedido indeferido',
        'cnis',
        'contribuição não aparece',
        'tempo rural',
        'trabalhador rural',
        'segurado especial',
        'ppp',
        'insalubridade inss',
        'aposentadoria rural',
        'deficiente',
        'idoso bpc',
        'aposentadoria pessoa com deficiência'
      ]::text[]
    ),
    (
      array['Direito Imobiliário']::text[],
      110,
      array[
        'advogado imobiliário',
        'direito imobiliário',
        'imóvel',
        'casa',
        'apartamento',
        'terreno',
        'lote',
        'aluguel',
        'aluguel atrasado',
        'contrato de aluguel',
        'despejo',
        'ordem de despejo',
        'ação de despejo',
        'inquilino não paga',
        'inquilino não sai',
        'proprietário',
        'locador',
        'locatário',
        'condomínio',
        'taxa de condomínio',
        'síndico',
        'locação',
        'compra de imóvel',
        'venda de imóvel',
        'escritura',
        'registro de imóvel',
        'matrícula do imóvel',
        'regularizar imóvel',
        'habite-se',
        'usucapião',
        'posse',
        'posse de terreno',
        'invasão de terreno',
        'invasão de imóvel',
        'construtora',
        'obra atrasada',
        'atraso na obra',
        'imóvel na planta',
        'distrato imobiliário',
        'financiamento imobiliário',
        'financiamento caixa',
        'corretor',
        'comissão de corretagem',
        'caução',
        'fiador',
        'vistoria',
        'infiltração',
        'vício construtivo',
        'reforma',
        'vizinho barulhento',
        'barulho de vizinho'
      ]::text[]
    ),
    (
      array['Acidente de Trânsito']::text[],
      110,
      array[
        'advogado de trânsito',
        'direito de trânsito',
        'acidente de trânsito',
        'batida',
        'bati o carro',
        'bateram no meu carro',
        'bateram na minha moto',
        'colisão',
        'engavetamento',
        'acidente de carro',
        'acidente de moto',
        'acidente de ônibus',
        'acidente com uber',
        'acidente aplicativo',
        'atropelamento',
        'fui atropelado',
        'fui atropelada',
        'trânsito',
        'seguradora',
        'seguro do carro',
        'seguro não pagou',
        'indenização acidente',
        'danos no carro',
        'conserto do carro',
        'perda total',
        'dpvat',
        'boletim de acidente',
        'culpa no acidente',
        'motorista bêbado',
        'multa de trânsito',
        'multa de transito',
        'cnh suspensa',
        'cnh cassada',
        'pontos na carteira',
        'bafômetro',
        'recusei bafômetro',
        'lei seca',
        'carro apreendido',
        'guincho',
        'licenciamento',
        'recurso de multa'
      ]::text[]
    ),
    (
      array['Direito Empresarial']::text[],
      105,
      array[
        'advogado empresarial',
        'direito empresarial',
        'empresa',
        'abrir empresa',
        'fechar empresa',
        'cnpj',
        'contrato social',
        'alteração contrato social',
        'alterar contrato social',
        'sócio',
        'sócios',
        'briga de sócios',
        'briga com sócio',
        'tirar sócio',
        'retirada de sócio',
        'entrada de sócio',
        'sociedade',
        'dissolução de sociedade',
        'acordo de sócios',
        'quotas',
        'ltda',
        'mei',
        'microempresa',
        'holding',
        'startup',
        'franquia',
        'contrato empresarial',
        'fornecedor',
        'cliente não pagou empresa',
        'cobrança empresarial',
        'recuperação judicial',
        'falência',
        'marca',
        'registro de marca',
        'pro labore',
        'compliance',
        'licitação',
        'contrato de prestação de serviço',
        'contrato com fornecedor',
        'contrato de parceria',
        'distribuição',
        'representação comercial'
      ]::text[]
    ),
    (
      array['Direito Tributário']::text[],
      105,
      array[
        'advogado tributário',
        'direito tributário',
        'imposto',
        'impostos',
        'tributo',
        'tributos',
        'dívida ativa',
        'execução fiscal',
        'cobrança da prefeitura',
        'cobrança do estado',
        'cobrança da receita',
        'iptu',
        'ipva',
        'icms',
        'iss',
        'irpf',
        'irpj',
        'imposto de renda',
        'receita federal',
        'malha fina',
        'simples nacional',
        'mei imposto',
        'pis',
        'cofins',
        'darf',
        'das',
        'parcelamento fiscal',
        'multa fiscal',
        'autuação fiscal',
        'fiscalização',
        'nota fiscal',
        'sonegação',
        'cnd',
        'certidão negativa',
        'recuperar imposto',
        'restituição',
        'taxa',
        'itcmd',
        'itbi',
        'protesto da prefeitura',
        'regularizar imposto'
      ]::text[]
    ),
    (
      array['Direito Cível']::text[],
      105,
      array[
        'advogado cível',
        'direito civil',
        'processo civil',
        'juizado especial',
        'pequenas causas',
        'indenização',
        'danos morais',
        'dano moral',
        'danos materiais',
        'dano material',
        'cobrança',
        'cobrar dívida',
        'alguém me deve',
        'me devem dinheiro',
        'calote',
        'levei calote',
        'emprestei dinheiro',
        'não me pagaram',
        'contrato',
        'quebra de contrato',
        'descumprimento de contrato',
        'rescisão de contrato',
        'responsabilidade civil',
        'erro médico',
        'erro odontológico',
        'acidente em loja',
        'queda em estabelecimento',
        'queda no mercado',
        'herança',
        'inventário',
        'testamento',
        'partilha de herança',
        'briga de herança',
        'registro civil',
        'alterar nome',
        'alteração de nome',
        'retificar documento',
        'retificação de registro',
        'interdição',
        'curatela',
        'vizinho',
        'briga com vizinho',
        'barulho de vizinho',
        'direito de imagem',
        'uso indevido de imagem',
        'calúnia',
        'injúria',
        'difamação',
        'cobrança judicial',
        'notificação extrajudicial',
        'contrato de compra e venda',
        'contrato de prestação de serviço'
      ]::text[]
    ),
    (
      array['Direito Digital']::text[],
      115,
      array[
        'advogado digital',
        'direito digital',
        'crime virtual',
        'crime na internet',
        'internet',
        'rede social',
        'lgpd',
        'vazamento de dados',
        'dados vazados',
        'privacidade',
        'proteção de dados',
        'perfil hackeado',
        'conta hackeada',
        'instagram hackeado',
        'facebook hackeado',
        'whatsapp clonado',
        'clonaram whatsapp',
        'conta invadida',
        'golpe do pix',
        'pix',
        'pix errado',
        'fraude online',
        'golpe online',
        'loja falsa',
        'site falso',
        'cyberbullying',
        'nudes vazados',
        'vazaram nudes',
        'fotos vazadas',
        'vídeo vazado',
        'pornografia de vingança',
        'difamação na internet',
        'post ofensivo',
        'comentário ofensivo',
        'fake news',
        'deepfake',
        'remover conteúdo',
        'tirar conteúdo do ar',
        'remover foto',
        'remover vídeo',
        'uso indevido de imagem',
        'direito autoral',
        'plágio',
        'software',
        'contrato de software',
        'aplicativo',
        'termos de uso',
        'e-commerce'
      ]::text[]
    )
),
expanded_terms as (
  select
    areas.practice_area,
    terms.phrase,
    public.normalize_practice_area_search(terms.phrase) as normalized_phrase,
    seed.weight
  from seed
  cross join unnest(seed.practice_areas) as areas(practice_area)
  cross join unnest(seed.terms) as terms(phrase)
  where nullif(trim(terms.phrase), '') is not null
),
deduplicated_terms as (
  select
    expanded_terms.practice_area,
    expanded_terms.normalized_phrase,
    min(expanded_terms.phrase) as phrase,
    max(expanded_terms.weight) as weight
  from expanded_terms
  where expanded_terms.normalized_phrase <> ''
  group by
    expanded_terms.practice_area,
    expanded_terms.normalized_phrase
)
insert into public.legal_search_intents (
  phrase,
  normalized_phrase,
  practice_area,
  related_tags,
  weight
)
select
  deduplicated_terms.phrase,
  deduplicated_terms.normalized_phrase,
  deduplicated_terms.practice_area,
  '{}'::text[],
  deduplicated_terms.weight
from deduplicated_terms
on conflict (normalized_phrase, practice_area) do update
set
  phrase = excluded.phrase,
  related_tags = excluded.related_tags,
  weight = greatest(public.legal_search_intents.weight, excluded.weight),
  is_active = true;

create or replace function public.infer_legal_search_areas(search_value text)
returns table (
  practice_area text,
  weight int
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  ),
  matches as (
    select
      lsi.practice_area,
      max(lsi.weight) as weight
    from public.legal_search_intents lsi
    cross join search
    where lsi.is_active = true
      and search.q is not null
      and length(search.q) >= 3
      and (
        public.legal_search_term_matches(search.q, lsi.normalized_phrase)
        or exists (
          select 1
          from unnest(lsi.related_tags) as tags(tag_value)
          where public.legal_search_term_matches(
            search.q,
            public.normalize_practice_area_search(tags.tag_value)
          )
        )
      )
    group by lsi.practice_area
  )
  select matches.practice_area, matches.weight
  from matches
  order by matches.weight desc, matches.practice_area;
$$;

create or replace function public.fetch_recommended_lawyers(
  limit_value int default 6,
  search_value text default null
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  ),
  inferred as (
    select *
    from public.infer_legal_search_areas(search_value)
  ),
  base as (
    select
      lp.id,
      coalesce(p.full_name, 'Advogado Jurii') as full_name,
      coalesce(p.initials, 'AJ') as initials,
      lp.oab_number,
      lp.oab_state::text as oab_state,
      lp.primary_area,
      case
        when cardinality(lp.practice_areas) > 0 then lp.practice_areas
        else array[lp.primary_area]
      end as practice_areas,
      coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
      4.8::numeric as rating,
      0::int as reviews_count,
      'navy'::text as avatar_type,
      lp.approved_at,
      lp.created_at
    from public.lawyer_profiles lp
    join public.profiles p on p.id = lp.id
    where lp.is_available = true
  ),
  ranked as (
    select
      base.*,
      coalesce(
        public.normalize_practice_area_search(base.full_name)
          like '%' || search.q || '%'
        or public.normalize_practice_area_search(base.primary_area)
          like '%' || search.q || '%'
        or exists (
          select 1
          from unnest(base.practice_areas) as areas(area_value)
          where public.normalize_practice_area_search(areas.area_value)
            like '%' || search.q || '%'
        ),
        false
      ) as direct_match,
      coalesce((
        select max(inferred.weight)
        from inferred
        where public.normalize_practice_area_search(base.primary_area) =
          public.normalize_practice_area_search(inferred.practice_area)
          or exists (
            select 1
            from unnest(base.practice_areas) as areas(area_value)
            where public.normalize_practice_area_search(areas.area_value) =
              public.normalize_practice_area_search(inferred.practice_area)
          )
      ), 0) as intent_weight
    from base
    cross join search
  )
  select
    ranked.id,
    ranked.full_name,
    ranked.initials,
    ranked.oab_number,
    ranked.oab_state,
    ranked.primary_area,
    ranked.practice_areas,
    ranked.bio,
    ranked.rating,
    ranked.reviews_count,
    ranked.avatar_type
  from ranked
  cross join search
  where search.q is null
    or ranked.direct_match
    or ranked.intent_weight > 0
  order by
    ranked.intent_weight desc,
    ranked.direct_match desc,
    ranked.approved_at desc nulls last,
    ranked.created_at desc
  limit least(greatest(coalesce(limit_value, 6), 1), 20);
$$;

create or replace function public.fetch_recommended_law_firms(
  limit_value int default 10,
  search_value text default null
)
returns table (
  id uuid,
  name text,
  initials text,
  rating numeric,
  distance_label text,
  specialty text,
  practice_areas text[],
  reviews_count int,
  avatar_type text,
  description text,
  phone text,
  email text,
  website_url text,
  address text
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  ),
  inferred as (
    select *
    from public.infer_legal_search_areas(search_value)
  ),
  base as (
    select
      lf.id,
      lf.name,
      lf.initials,
      lf.rating,
      lf.distance_label,
      lf.specialty,
      case
        when cardinality(lf.practice_areas) > 0 then lf.practice_areas
        else array[lf.specialty]
      end as practice_areas,
      lf.reviews_count,
      lf.avatar_type,
      lf.description,
      lf.phone,
      lf.email,
      lf.website_url,
      lf.address,
      lf.created_at
    from public.law_firms lf
    where lf.is_active = true
  ),
  ranked as (
    select
      base.*,
      coalesce(
        public.normalize_practice_area_search(base.name)
          like '%' || search.q || '%'
        or public.normalize_practice_area_search(base.specialty)
          like '%' || search.q || '%'
        or exists (
          select 1
          from unnest(base.practice_areas) as areas(area_value)
          where public.normalize_practice_area_search(areas.area_value)
            like '%' || search.q || '%'
        ),
        false
      ) as direct_match,
      coalesce((
        select max(inferred.weight)
        from inferred
        where public.normalize_practice_area_search(base.specialty) =
          public.normalize_practice_area_search(inferred.practice_area)
          or exists (
            select 1
            from unnest(base.practice_areas) as areas(area_value)
            where public.normalize_practice_area_search(areas.area_value) =
              public.normalize_practice_area_search(inferred.practice_area)
          )
      ), 0) as intent_weight
    from base
    cross join search
  )
  select
    ranked.id,
    ranked.name,
    ranked.initials,
    ranked.rating,
    ranked.distance_label,
    ranked.specialty,
    ranked.practice_areas,
    ranked.reviews_count,
    ranked.avatar_type,
    ranked.description,
    ranked.phone,
    ranked.email,
    ranked.website_url,
    ranked.address
  from ranked
  cross join search
  where search.q is null
    or ranked.direct_match
    or ranked.intent_weight > 0
  order by
    ranked.intent_weight desc,
    ranked.direct_match desc,
    ranked.rating desc,
    ranked.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;

revoke all on function public.normalize_practice_area_search(text)
from public, anon, authenticated;

revoke all on function public.legal_search_term_matches(text, text)
from public, anon, authenticated;

revoke all on function public.infer_legal_search_areas(text)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_lawyers(int, text)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon, authenticated;

grant select on public.legal_search_intents to authenticated;

grant execute on function public.infer_legal_search_areas(text)
to authenticated;

grant execute on function public.fetch_recommended_lawyers(int, text)
to authenticated;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_030_firm_member_multi_roles.sql
-- ============================================================================

-- Adds multi-role office memberships and role-based office permissions.
--
-- Run after patch_029. This keeps the legacy role/member_role columns synced,
-- but makes roles text[] the source of truth for app permissions.

do $$
begin
  if exists (select 1 from pg_type where typname = 'law_firm_member_role') then
    execute 'alter type public.law_firm_member_role add value if not exists ''intern''';
  end if;
end $$;

alter table public.law_firm_members
add column if not exists roles text[] not null default array['lawyer']::text[];

create or replace function public.normalize_practice_areas(
  practice_areas_value text[]
)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(area order by first_ordinal), '{}'::text[])
  from (
    select area, min(ordinality) as first_ordinal
    from (
      select nullif(trim(area_value), '') as area, ordinality
      from unnest(coalesce(practice_areas_value, '{}'::text[]))
        with ordinality as areas(area_value, ordinality)
    ) cleaned_areas
    where area is not null
    group by area
  ) distinct_areas;
$$;

create or replace function public.normalize_law_firm_member_roles(
  roles_value text[]
)
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_roles text[];
  invalid_roles text[];
begin
  with raw_roles as (
    select lower(trim(role_value)) as role_value
    from unnest(coalesce(roles_value, '{}'::text[])) as role_value
    where nullif(trim(role_value), '') is not null
  ),
  distinct_roles as (
    select distinct role_value
    from raw_roles
  )
  select coalesce(
    array_agg(
      role_value
      order by case role_value
        when 'owner' then 1
        when 'admin' then 2
        when 'lawyer' then 3
        when 'secretary' then 4
        when 'intern' then 5
        else 99
      end
    ),
    '{}'::text[]
  )
  into normalized_roles
  from distinct_roles
  where role_value in ('owner', 'admin', 'lawyer', 'secretary', 'intern');

  with raw_roles as (
    select lower(trim(role_value)) as role_value
    from unnest(coalesce(roles_value, '{}'::text[])) as role_value
    where nullif(trim(role_value), '') is not null
  ),
  invalid as (
    select distinct role_value
    from raw_roles
    where role_value not in ('owner', 'admin', 'lawyer', 'secretary', 'intern')
  )
  select coalesce(array_agg(role_value), '{}'::text[])
  into invalid_roles
  from invalid;

  if coalesce(array_length(invalid_roles, 1), 0) > 0 then
    raise exception 'Invalid firm roles: %', array_to_string(invalid_roles, ', ');
  end if;

  if coalesce(array_length(normalized_roles, 1), 0) = 0 then
    return array['lawyer']::text[];
  end if;

  return normalized_roles;
end;
$$;

create or replace function public.primary_law_firm_member_role(
  roles_value text[]
)
returns text
language sql
immutable
set search_path = public
as $$
  select (public.normalize_law_firm_member_roles(roles_value))[1];
$$;

update public.law_firm_members
set roles = public.normalize_law_firm_member_roles(
  case
    when roles is not null
         and coalesce(array_length(roles, 1), 0) > 0
         and not (
           roles = array['lawyer']::text[]
           and coalesce(member_role::text, role) in ('owner', 'admin', 'secretary', 'intern')
         ) then roles
    else array[
      coalesce(
        nullif(member_role::text, ''),
        nullif(role, ''),
        'lawyer'
      )
    ]::text[]
  end
);

alter table public.law_firm_members
alter column roles set default array['lawyer']::text[];

alter table public.law_firm_members
alter column roles set not null;

alter table public.law_firm_members
drop constraint if exists law_firm_members_roles_allowed;

alter table public.law_firm_members
add constraint law_firm_members_roles_allowed
check (
  coalesce(array_length(roles, 1), 0) > 0
  and roles <@ array['owner', 'admin', 'lawyer', 'secretary', 'intern']::text[]
);

create index if not exists law_firm_members_roles_gin_idx
on public.law_firm_members using gin (roles);

create or replace function public.sync_law_firm_member_roles_legacy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_roles text[];
  primary_role text;
  legacy_role text;
begin
  legacy_role := case
    when new.member_role::text in ('owner', 'admin', 'secretary', 'intern') then new.member_role::text
    when new.role in ('owner', 'admin', 'secretary', 'intern') then new.role
    when new.member_role::text in ('lawyer') then new.member_role::text
    when new.role in ('lawyer') then new.role
    else 'lawyer'
  end;

  normalized_roles := public.normalize_law_firm_member_roles(
    case
      when new.roles is not null
           and coalesce(array_length(new.roles, 1), 0) > 0
           and not (
             new.roles = array['lawyer']::text[]
             and legacy_role in ('owner', 'admin', 'secretary', 'intern')
           ) then new.roles
      else array[legacy_role]::text[]
    end
  );
  primary_role := public.primary_law_firm_member_role(normalized_roles);

  new.roles := normalized_roles;
  new.role := primary_role;
  new.member_role := primary_role::public.law_firm_member_role;

  return new;
end;
$$;

drop trigger if exists law_firm_members_sync_roles_legacy
on public.law_firm_members;

create trigger law_firm_members_sync_roles_legacy
before insert or update of roles, role, member_role
on public.law_firm_members
for each row execute function public.sync_law_firm_member_roles_legacy();

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
  select coalesce((
    select lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = profile_id_value
      and lfm.status = 'active'
    limit 1
  ), '{}'::text[]);
$$;

create or replace function public.has_law_firm_role(
  law_firm_id_value uuid,
  role_value text,
  profile_id_value uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(trim(role_value)) = any(
    public.current_law_firm_member_roles(law_firm_id_value, profile_id_value)
  );
$$;

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

create or replace function public.update_law_firm_member_roles(
  law_firm_id_value uuid,
  member_profile_id_value uuid,
  roles_value text[]
)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  target_member public.law_firm_members%rowtype;
  normalized_roles text[];
  primary_role text;
  actor_is_owner boolean;
  target_has_owner boolean;
  target_will_have_owner boolean;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if coalesce(array_length(roles_value, 1), 0) = 0 then
    raise exception 'At least one firm role is required';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only active office owners and admins can edit member roles';
  end if;

  actor_is_owner := public.has_law_firm_role(law_firm_id_value, 'owner');
  normalized_roles := public.normalize_law_firm_member_roles(roles_value);
  primary_role := public.primary_law_firm_member_role(normalized_roles);

  select *
  into target_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and profile_id = member_profile_id_value
    and status <> 'disabled'
  for update;

  if not found then
    raise exception 'Firm member not found';
  end if;

  target_has_owner := 'owner' = any(target_member.roles);
  target_will_have_owner := 'owner' = any(normalized_roles);

  if target_has_owner and not actor_is_owner then
    raise exception 'Only owners can grant or remove owner role';
  end if;

  if target_has_owner is distinct from target_will_have_owner
      and not actor_is_owner then
    raise exception 'Only owners can grant or remove owner role';
  end if;

  if target_has_owner and not target_will_have_owner and not exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id <> member_profile_id_value
      and lfm.status = 'active'
      and 'owner' = any(lfm.roles)
  ) then
    raise exception 'Office must keep at least one owner';
  end if;

  update public.law_firm_members
  set
    roles = normalized_roles,
    role = primary_role,
    member_role = primary_role::public.law_firm_member_role
  where id = target_member.id;

  return normalized_roles;
end;
$$;

drop function if exists public.fetch_law_firm_cases(uuid);

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer_id uuid,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id, lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  viewer as (
    select *
    from active_members
    where profile_id = auth.uid()
    limit 1
  ),
  scoped_cases as (
    select distinct lc.*
    from public.legal_cases lc
    where exists (select 1 from viewer)
      and (
        (
          exists (
            select 1
            from viewer
            where roles && array['owner', 'admin', 'secretary']::text[]
          )
          and (
            lc.law_firm_id = law_firm_id_value
            or exists (
              select 1
              from active_members assigned_member
              where assigned_member.profile_id = lc.assigned_lawyer_id
            )
            or exists (
              select 1
              from public.case_participants cp
              join active_members participant_member
                on participant_member.profile_id = cp.profile_id
              where cp.case_id = lc.id
                and cp.role in ('lawyer', 'firm_member')
            )
          )
        )
        or lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
        )
      )
  )
  select
    sc.id,
    sc.title,
    coalesce(client_profile.full_name, 'Cliente') as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    coalesce(lawyer_profile.full_name, 'Sem advogado definido') as assigned_lawyer,
    sc.area,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    sc.status = 'deadline' as urgent,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$$;

create or replace function public.assign_law_firm_case(
  law_firm_id_value uuid,
  case_id_value uuid,
  lawyer_profile_id_value uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
  old_lawyer_id uuid;
  target_lawyer_id uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_case_manager(law_firm_id_value) then
    raise exception 'Only office case managers can assign cases';
  end if;

  select *
  into case_row
  from public.legal_cases
  where id = case_id_value
  for update;

  if not found then
    raise exception 'Case not found';
  end if;

  if not (
    case_row.law_firm_id = law_firm_id_value
    or exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = law_firm_id_value
        and lfm.profile_id = case_row.assigned_lawyer_id
        and lfm.status = 'active'
    )
    or exists (
      select 1
      from public.case_participants cp
      join public.law_firm_members lfm
        on lfm.profile_id = cp.profile_id
      where cp.case_id = case_row.id
        and cp.role in ('lawyer', 'firm_member')
        and lfm.law_firm_id = law_firm_id_value
        and lfm.status = 'active'
    )
  ) then
    raise exception 'Case does not belong to this office';
  end if;

  select coalesce(lfm.lawyer_id, lfm.profile_id)
  into target_lawyer_id
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  where lfm.law_firm_id = law_firm_id_value
    and lfm.profile_id = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(lfm.lawyer_invite_status, 'active'::public.law_firm_member_status)
      = 'active'
  limit 1;

  if target_lawyer_id is null then
    raise exception 'Target member must be an active lawyer';
  end if;

  old_lawyer_id := case_row.assigned_lawyer_id;

  update public.legal_cases
  set
    law_firm_id = coalesce(law_firm_id, law_firm_id_value),
    assigned_lawyer_id = target_lawyer_id,
    last_update_label = 'Caso atribuido',
    updated_at = now()
  where id = case_id_value;

  if old_lawyer_id is not null and old_lawyer_id <> target_lawyer_id then
    delete from public.case_participants
    where case_id = case_id_value
      and profile_id = old_lawyer_id
      and role = 'lawyer';
  end if;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, target_lawyer_id, 'lawyer')
  on conflict (case_id, profile_id) do update
  set role = 'lawyer';

  return target_lawyer_id;
end;
$$;

create or replace function public.can_manage_case_updates(case_id_value uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.legal_cases lc
    where lc.id = case_id_value
      and (
        lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
            and cp.role = 'lawyer'
        )
      )
  );
$$;

create or replace function public.create_case_request(
  conversation_id_value uuid,
  title_value text,
  area_value text,
  summary_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  request_row public.case_requests%rowtype;
  request_id_value uuid;
  effective_law_firm_id uuid;
  clean_title text;
  clean_area text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  clean_title := nullif(trim(coalesce(title_value, '')), '');
  clean_area := nullif(trim(coalesce(area_value, '')), '');

  if clean_title is null or clean_area is null then
    raise exception 'Title and area are required';
  end if;

  select *
  into conversation_row
  from public.conversations
  where id = conversation_id_value;

  if not found then
    raise exception 'Conversation not found';
  end if;

  effective_law_firm_id := conversation_row.law_firm_id;

  if effective_law_firm_id is null and conversation_row.lawyer_id = auth.uid() then
    select lfm.law_firm_id
    into effective_law_firm_id
    from public.law_firm_members lfm
    where lfm.profile_id = auth.uid()
      and lfm.status = 'active'
      and lfm.roles && array['owner', 'admin', 'lawyer', 'secretary']::text[]
    order by case
      when 'owner' = any(lfm.roles) then 1
      when 'admin' = any(lfm.roles) then 2
      when 'lawyer' = any(lfm.roles) then 3
      when 'secretary' = any(lfm.roles) then 4
      else 5
    end,
    coalesce(lfm.created_at, lfm.joined_at)
    limit 1;
  end if;

  if not (
    conversation_row.lawyer_id = auth.uid()
    or (
      conversation_row.law_firm_id is not null
      and public.is_active_law_firm_case_manager(conversation_row.law_firm_id)
    )
  ) then
    raise exception 'Only the responsible professional can request case acceptance';
  end if;

  select *
  into request_row
  from public.case_requests
  where conversation_id = conversation_id_value
    and status = 'pending'
  order by created_at desc
  limit 1;

  if found then
    request_id_value := request_row.id;

    update public.case_requests
    set
      title = clean_title,
      area = clean_area,
      summary = nullif(trim(coalesce(summary_value, '')), ''),
      law_firm_id = effective_law_firm_id,
      requested_by_profile_id = auth.uid()
    where id = request_id_value;
  else
    insert into public.case_requests (
      conversation_id,
      client_id,
      law_firm_id,
      lawyer_id,
      requested_by_profile_id,
      title,
      area,
      summary
    )
    values (
      conversation_row.id,
      conversation_row.client_id,
      effective_law_firm_id,
      conversation_row.lawyer_id,
      auth.uid(),
      clean_title,
      clean_area,
      nullif(trim(coalesce(summary_value, '')), '')
    )
    returning id into request_id_value;
  end if;

  perform public.ensure_case_request_client_surfaces(request_id_value);

  return request_id_value;
end;
$$;

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
  target_verification public.lawyer_verifications%rowtype;
  target_profile public.profiles%rowtype;
  existing_member public.law_firm_members%rowtype;
  firm_name_value text;
  normalized_oab_state text;
  normalized_oab_number text;
  membership_id_value uuid;
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

  select *
  into target_verification
  from public.lawyer_verifications lv
  where lv.status = 'approved'
    and upper(trim(lv.oab_state)) = normalized_oab_state
    and regexp_replace(upper(coalesce(lv.oab_number, '')), '[^A-Z0-9]', '', 'g')
      = normalized_oab_number
  order by lv.reviewed_at desc nulls last, lv.submitted_at desc
  limit 1;

  if not found then
    raise exception 'Lawyer not found or not approved for this OAB';
  end if;

  select *
  into target_profile
  from public.profiles
  where id = target_verification.user_id;

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  update public.profiles
  set lawyer_status = 'approved'
  where id = target_verification.user_id;

  insert into public.lawyer_profiles (
    id,
    oab_number,
    oab_state,
    primary_area,
    practice_areas,
    approved_at
  )
  values (
    target_verification.user_id,
    target_verification.oab_number,
    target_verification.oab_state,
    target_verification.practice_area,
    public.normalize_practice_areas(target_verification.practice_areas),
    coalesce(target_verification.reviewed_at, now())
  )
  on conflict (id) do update
  set
    oab_number = excluded.oab_number,
    oab_state = excluded.oab_state,
    primary_area = excluded.primary_area,
    practice_areas = excluded.practice_areas,
    approved_at = coalesce(public.lawyer_profiles.approved_at, excluded.approved_at);

  select *
  into existing_member
  from public.law_firm_members
  where law_firm_id = law_firm_id_value
    and (
      profile_id = target_verification.user_id
      or lawyer_id = target_verification.user_id
      or pending_lawyer_id = target_verification.user_id
    )
  limit 1;

  if found
      and existing_member.lawyer_id = target_verification.user_id
      and existing_member.lawyer_invite_status = 'active' then
    raise exception 'Lawyer already active in this office';
  end if;

  if found
      and existing_member.pending_lawyer_id = target_verification.user_id
      and existing_member.lawyer_invite_status = 'invited' then
    raise exception 'Lawyer invite already pending';
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
      target_verification.user_id,
      target_verification.user_id,
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
      profile_id = target_verification.user_id,
      lawyer_id = case
        when existing_is_manager then lawyer_id
        else target_verification.user_id
      end,
      pending_lawyer_id = case
        when existing_is_manager then target_verification.user_id
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
    target_verification.user_id,
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

  return membership_id_value;
end;
$$;

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

  if membership_row.profile_id <> auth.uid() then
    raise exception 'Only the invited lawyer can respond to this invite';
  end if;

  if membership_row.status <> 'invited'
      and membership_row.lawyer_invite_status <> 'invited' then
    raise exception 'Invite is no longer pending';
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

revoke all on function public.update_law_firm_member_roles(uuid, uuid, text[])
from public, anon;

grant execute on function public.update_law_firm_member_roles(uuid, uuid, text[])
to authenticated;

revoke all on function public.assign_law_firm_case(uuid, uuid, uuid)
from public, anon;

grant execute on function public.assign_law_firm_case(uuid, uuid, uuid)
to authenticated;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

revoke all on function public.create_case_request(uuid, text, text, text)
from public, anon, authenticated;

grant execute on function public.create_case_request(uuid, text, text, text)
to authenticated;

revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
from public, anon;

grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
to authenticated;

revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
from public, anon;

grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_031_repair_firm_owner_roles.sql
-- ============================================================================

-- Repairs office owners after patch_030 and hardens role sync.
--
-- Run after patch_030 if an office creator cannot invite/manage members.
-- This is safe to run even if the bug did not happen.

create or replace function public.sync_law_firm_member_roles_legacy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_roles text[];
  primary_role text;
  legacy_role text;
begin
  legacy_role := case
    when new.member_role::text in ('owner', 'admin', 'secretary', 'intern') then new.member_role::text
    when new.role in ('owner', 'admin', 'secretary', 'intern') then new.role
    when new.member_role::text = 'lawyer' then new.member_role::text
    when new.role = 'lawyer' then new.role
    else 'lawyer'
  end;

  normalized_roles := public.normalize_law_firm_member_roles(
    case
      when new.roles is not null
           and coalesce(array_length(new.roles, 1), 0) > 0
           and not (
             new.roles = array['lawyer']::text[]
             and legacy_role in ('owner', 'admin', 'secretary', 'intern')
           ) then new.roles
      else array[legacy_role]::text[]
    end
  );
  primary_role := public.primary_law_firm_member_role(normalized_roles);

  new.roles := normalized_roles;
  new.role := primary_role;
  new.member_role := primary_role::public.law_firm_member_role;

  return new;
end;
$$;

update public.law_firm_members lfm
set
  roles = public.normalize_law_firm_member_roles(
    array[
      case
        when lfm.member_role::text in ('owner', 'admin', 'secretary', 'intern') then lfm.member_role::text
        when lfm.role in ('owner', 'admin', 'secretary', 'intern') then lfm.role
        else 'lawyer'
      end
    ]::text[]
  )
where lfm.roles = array['lawyer']::text[]
  and (
    lfm.member_role::text in ('owner', 'admin', 'secretary', 'intern')
    or lfm.role in ('owner', 'admin', 'secretary', 'intern')
  );

insert into public.law_firm_members (
  law_firm_id,
  profile_id,
  role,
  member_role,
  roles,
  status
)
select
  lfv.law_firm_id,
  lfv.owner_profile_id,
  'owner',
  'owner'::public.law_firm_member_role,
  array['owner']::text[],
  'active'::public.law_firm_member_status
from public.law_firm_verifications lfv
where lfv.status = 'approved'
  and lfv.law_firm_id is not null
  and not exists (
    select 1
    from public.law_firm_members lfm
    where lfm.law_firm_id = lfv.law_firm_id
      and lfm.profile_id = lfv.owner_profile_id
  );

update public.law_firm_members lfm
set
  roles = public.normalize_law_firm_member_roles(array['owner']::text[]),
  role = 'owner',
  member_role = 'owner'::public.law_firm_member_role,
  status = 'active'::public.law_firm_member_status
from public.law_firm_verifications lfv
where lfv.law_firm_id = lfm.law_firm_id
  and lfv.owner_profile_id = lfm.profile_id
  and lfv.status = 'approved'
  and not ('owner' = any(lfm.roles));

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
  )
  or exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.law_firm_id = law_firm_id_value
      and lfv.owner_profile_id = auth.uid()
      and lfv.status = 'approved'
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
  )
  or exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.law_firm_id = law_firm_id_value
      and lfv.owner_profile_id = auth.uid()
      and lfv.status = 'approved'
  );
$$;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_032_firm_invite_rpc_grants.sql
-- ============================================================================

-- Repairs execute grants and schema cache for office invite RPCs.
--
-- Run after patch_030 and patch_031 if inviting a lawyer still fails with a
-- function/schema/permission error.

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'invite_verified_lawyer_to_law_firm'
      and pg_get_function_identity_arguments(p.oid) = 'law_firm_id_value uuid, oab_state_value text, oab_number_value text'
  ) then
    revoke all on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
    from public, anon;

    grant execute on function public.invite_verified_lawyer_to_law_firm(uuid, text, text)
    to authenticated;
  else
    raise exception 'Missing invite_verified_lawyer_to_law_firm(uuid, text, text). Run patch_030 first.';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'respond_to_law_firm_invite'
      and pg_get_function_identity_arguments(p.oid) = 'membership_id_value uuid, accepted_value boolean'
  ) then
    revoke all on function public.respond_to_law_firm_invite(uuid, boolean)
    from public, anon;

    grant execute on function public.respond_to_law_firm_invite(uuid, boolean)
    to authenticated;
  end if;
end $$;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_033_repair_invite_practice_area_normalizer.sql
-- ============================================================================

-- Repairs the missing practice-area normalizer used by the office invite RPC.
--
-- Run after patch_032 if inviting a lawyer fails with:
-- function public.normalize_practice_areas(text[]) does not exist.

create or replace function public.normalize_practice_areas(
  practice_areas_value text[]
)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(area order by first_ordinal), '{}'::text[])
  from (
    select area, min(ordinality) as first_ordinal
    from (
      select nullif(trim(area_value), '') as area, ordinality
      from unnest(coalesce(practice_areas_value, '{}'::text[]))
        with ordinality as areas(area_value, ordinality)
    ) cleaned_areas
    where area is not null
    group by area
  ) distinct_areas;
$$;

revoke all on function public.normalize_practice_areas(text[])
from public, anon;

grant execute on function public.normalize_practice_areas(text[])
to authenticated;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  actor_profile_id uuid references public.profiles(id) on delete set null,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  type text not null default 'system',
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_created_idx
on public.notifications(recipient_profile_id, created_at desc);

create index if not exists notifications_recipient_unread_idx
on public.notifications(recipient_profile_id)
where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
on public.notifications for select
to authenticated
using (recipient_profile_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
on public.notifications for update
to authenticated
using (recipient_profile_id = auth.uid())
with check (recipient_profile_id = auth.uid());

grant select, update on public.notifications to authenticated;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_034_notification_dismissal.sql
-- ============================================================================

-- Allows users to dismiss their own notifications from the app.
--
-- Run after patch_033. The notification bell uses this permission when the
-- user swipes a notification to the side.

alter table public.notifications enable row level security;

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
on public.notifications for delete
to authenticated
using (recipient_profile_id = auth.uid());

grant delete on public.notifications to authenticated;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_035_account_deletion.sql
-- ============================================================================

-- Soft account deletion while preserving shared legal history.
--
-- Run after patch_034. This intentionally does not physically delete
-- public.profiles because several shared resources still reference it:
-- conversations, cases, appointments and documents. The deleted account is
-- blocked by the app, professional access is removed, and related users keep
-- seeing the historical name with "(delleted account)" in conversation lists.

alter table public.profiles
add column if not exists deleted_at timestamptz;

alter table public.profiles
add column if not exists deleted_display_name text;

alter table public.profiles
add column if not exists deleted_email text;

create index if not exists profiles_deleted_at_idx
on public.profiles(deleted_at);

create or replace function public.profile_display_name(
  full_name_value text,
  deleted_display_name_value text,
  deleted_at_value timestamptz
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when deleted_at_value is not null then
      coalesce(
        nullif(trim(deleted_display_name_value), ''),
        nullif(trim(full_name_value), ''),
        'Usuário'
      ) || ' (delleted account)'
    else
      coalesce(nullif(trim(full_name_value), ''), 'Usuário Jurii')
  end;
$$;

create or replace function public.law_firm_member_role_rank(
  roles_value text[]
)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    when 'owner' = any(coalesce(roles_value, '{}'::text[])) then 1
    when 'admin' = any(coalesce(roles_value, '{}'::text[])) then 2
    when 'lawyer' = any(coalesce(roles_value, '{}'::text[])) then 3
    when 'secretary' = any(coalesce(roles_value, '{}'::text[])) then 4
    when 'intern' = any(coalesce(roles_value, '{}'::text[])) then 5
    else 99
  end;
$$;

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
  );
$$;

create or replace function public.transfer_owned_law_firms_for_deleted_profile(
  profile_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  firm_record record;
  replacement_record record;
  replacement_roles text[];
  replacement_primary_role text;
begin
  for firm_record in
    select distinct lfv.law_firm_id
    from public.law_firm_verifications lfv
    where lfv.owner_profile_id = profile_id_value
      and lfv.law_firm_id is not null
      and lfv.status = 'approved'
  loop
    select
      lfm.id,
      lfm.profile_id,
      coalesce(lfm.roles, array[lfm.member_role::text]::text[]) as roles
    into replacement_record
    from public.law_firm_members lfm
    join public.profiles p
      on p.id = lfm.profile_id
    where lfm.law_firm_id = firm_record.law_firm_id
      and lfm.profile_id is not null
      and lfm.profile_id <> profile_id_value
      and lfm.status = 'active'
      and p.deleted_at is null
    order by
      public.law_firm_member_role_rank(
        coalesce(lfm.roles, array[lfm.member_role::text]::text[])
      ),
      lower(coalesce(nullif(trim(p.full_name), ''), p.email, p.id::text)),
      lfm.profile_id
    limit 1;

    if replacement_record.profile_id is not null then
      replacement_roles := public.normalize_law_firm_member_roles(
        case
          when 'owner' = any(replacement_record.roles) then replacement_record.roles
          else replacement_record.roles || array['owner']::text[]
        end
      );
      replacement_primary_role := public.primary_law_firm_member_role(
        replacement_roles
      );

      update public.law_firm_members
      set
        roles = replacement_roles,
        role = replacement_primary_role,
        member_role = replacement_primary_role::public.law_firm_member_role,
        status = 'active'
      where id = replacement_record.id;

      update public.law_firm_verifications
      set
        owner_profile_id = replacement_record.profile_id,
        updated_at = now()
      where law_firm_id = firm_record.law_firm_id
        and owner_profile_id = profile_id_value
        and status = 'approved';
    end if;
  end loop;
end;
$$;

create or replace function public.delete_current_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_id_value uuid;
  profile_row public.profiles%rowtype;
  deleted_name_value text;
  deleted_email_value text;
begin
  profile_id_value := auth.uid();

  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into profile_row
  from public.profiles
  where id = profile_id_value
  for update;

  if not found then
    return;
  end if;

  if profile_row.deleted_at is not null then
    return;
  end if;

  deleted_name_value := coalesce(
    nullif(trim(profile_row.deleted_display_name), ''),
    nullif(trim(profile_row.full_name), ''),
    'Usuário'
  );
  deleted_email_value := nullif(trim(profile_row.email), '');

  perform public.transfer_owned_law_firms_for_deleted_profile(profile_id_value);

  update public.conversations
  set
    title = deleted_name_value || ' (delleted account)',
    updated_at = now()
  where lawyer_id = profile_id_value
    and law_firm_id is null;

  update public.law_firm_members
  set
    status = 'disabled',
    lawyer_id = null,
    pending_lawyer_id = null,
    lawyer_invite_status = 'disabled'
  where profile_id = profile_id_value
     or lawyer_id = profile_id_value
     or pending_lawyer_id = profile_id_value;

  delete from public.verification_documents
  where user_id = profile_id_value;

  delete from public.lawyer_verifications
  where user_id = profile_id_value;

  delete from public.lawyer_profiles
  where id = profile_id_value;

  delete from public.law_firm_verification_documents lfvd
  where lfvd.owner_profile_id = profile_id_value
    and exists (
      select 1
      from public.law_firm_verifications lfv
      where lfv.id = lfvd.verification_id
        and lfv.owner_profile_id = profile_id_value
        and lfv.status <> 'approved'
    );

  update public.law_firm_verifications
  set
    status = case
      when law_firm_id is null then 'rejected'::public.verification_status
      else status
    end,
    rejection_reason = case
      when law_firm_id is null then 'Conta solicitante excluída.'
      else rejection_reason
    end,
    updated_at = now()
  where owner_profile_id = profile_id_value;

  update public.profiles
  set
    deleted_at = now(),
    deleted_display_name = deleted_name_value,
    deleted_email = deleted_email_value,
    full_name = deleted_name_value,
    email = 'deleted+' || profile_id_value::text || '@deleted.jurii.local',
    cpf = null,
    phone = null,
    avatar_url = null,
    lawyer_status = 'client'
  where id = profile_id_value;
end;
$$;

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
    p.email,
    p.initials,
    p.member_since,
    p.lawyer_status::text
  from public.profiles p
  where p.id = profile_id_value
    and p.deleted_at is null
    and public.can_select_profile(p.id)
  limit 1;
$$;

drop function if exists public.fetch_lawyer_public_profile(uuid);

create or replace function public.fetch_lawyer_public_profile(
  lawyer_profile_id_value uuid
)
returns table (
  id uuid,
  full_name text,
  initials text,
  oab_number text,
  oab_state text,
  primary_area text,
  practice_areas text[],
  bio text,
  rating numeric,
  reviews_count int,
  avatar_type text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    lp.id,
    coalesce(p.full_name, 'Advogado Jurii') as full_name,
    coalesce(p.initials, 'AJ') as initials,
    lp.oab_number,
    lp.oab_state::text as oab_state,
    lp.primary_area,
    case
      when cardinality(lp.practice_areas) > 0 then lp.practice_areas
      else array[lp.primary_area]
    end as practice_areas,
    coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.') as bio,
    4.8::numeric as rating,
    0::int as reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
    and p.deleted_at is null
  limit 1;
$$;

create or replace function public.fetch_conversation_for_current_user(
  conversation_id_value uuid
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.type::text,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      when c.client_id = auth.uid() then
        c.title
      else
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
    end as title,
    case
      when c.client_id = auth.uid() and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when c.client_id = auth.uid() and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      when c.client_id = auth.uid() then
        upper(left(trim(c.title), 2))
      else
        coalesce(client_profile.initials, 'CL')
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from public.conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  where c.id = conversation_id_value
    and (
      c.client_id = auth.uid()
      or c.lawyer_id = auth.uid()
      or exists (
        select 1
        from public.law_firm_members lfm
        where lfm.law_firm_id = c.law_firm_id
          and lfm.profile_id = auth.uid()
          and lfm.status = 'active'
      )
      or (
        c.case_id is not null
        and public.can_access_case(c.case_id)
      )
    )
  limit 1;
$$;

create or replace function public.fetch_conversations_for_current_user(
  scope_value text,
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  with scoped_conversations as (
    select c.*
    from public.conversations c
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages m
        where m.conversation_id = c.id
      )
      and (
        (
          scope_value = 'client'
          and c.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and c.lawyer_id = auth.uid()
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  )
  select
    c.id,
    c.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(c.title), 2))
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from scoped_conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  order by c.last_message_at desc nulls last, c.updated_at desc;
$$;

create or replace function public.fetch_lawyer_cases()
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  area text,
  last_update_label text,
  status text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct
    lc.id,
    lc.title,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_display_name,
      client_profile.deleted_at
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    lc.area,
    coalesce(lc.last_update_label, 'Atualizado hoje') as last_update_label,
    lc.status::text as status,
    lc.updated_at
  from public.legal_cases lc
  left join public.profiles client_profile
    on client_profile.id = lc.client_id
  where lc.assigned_lawyer_id = auth.uid()
     or exists (
      select 1
      from public.case_participants cp
      where cp.case_id = lc.id
        and cp.profile_id = auth.uid()
        and cp.role in ('lawyer', 'firm_member')
     )
  order by lc.updated_at desc;
$$;

drop function if exists public.fetch_law_firm_cases(uuid);

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer_id uuid,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with active_members as (
    select lfm.profile_id, lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id is not null
      and lfm.status = 'active'
  ),
  viewer as (
    select *
    from active_members
    where profile_id = auth.uid()
    limit 1
  ),
  scoped_cases as (
    select distinct lc.*
    from public.legal_cases lc
    where exists (select 1 from viewer)
    and (
      (
        exists (
          select 1
          from viewer
          where roles && array['owner', 'admin', 'secretary']::text[]
        )
        and (
          lc.law_firm_id = law_firm_id_value
          or exists (
            select 1
            from active_members assigned_member
            where assigned_member.profile_id = lc.assigned_lawyer_id
          )
          or exists (
            select 1
            from public.case_participants cp
            join active_members participant_member
              on participant_member.profile_id = cp.profile_id
            where cp.case_id = lc.id
              and cp.role in ('lawyer', 'firm_member')
          )
        )
      )
      or lc.assigned_lawyer_id = auth.uid()
      or exists (
        select 1
        from public.case_participants cp
        where cp.case_id = lc.id
          and cp.profile_id = auth.uid()
      )
    )
  )
  select
    sc.id,
    sc.title,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_display_name,
      client_profile.deleted_at
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    case
      when lawyer_profile.id is null then 'Sem advogado definido'
      else public.profile_display_name(
        lawyer_profile.full_name,
        lawyer_profile.deleted_display_name,
        lawyer_profile.deleted_at
      )
    end as assigned_lawyer,
    sc.area,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    sc.status = 'deadline' as urgent,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$$;

revoke all on function public.profile_display_name(text, text, timestamptz)
from public, anon, authenticated;

revoke all on function public.law_firm_member_role_rank(text[])
from public, anon, authenticated;

revoke all on function public.can_select_profile(uuid)
from public, anon, authenticated;

revoke all on function public.transfer_owned_law_firms_for_deleted_profile(uuid)
from public, anon, authenticated;

revoke all on function public.delete_current_account()
from public, anon, authenticated;

revoke all on function public.fetch_chat_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_public_profile(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversation_for_current_user(uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

revoke all on function public.fetch_lawyer_cases()
from public, anon, authenticated;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

grant execute on function public.delete_current_account()
to authenticated;

grant execute on function public.can_select_profile(uuid)
to authenticated;

grant execute on function public.fetch_chat_profile(uuid)
to authenticated;

grant execute on function public.fetch_lawyer_public_profile(uuid)
to authenticated;

grant execute on function public.fetch_conversation_for_current_user(uuid)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

grant execute on function public.fetch_lawyer_cases()
to authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Source: supabase/patch_036_link_lawyer_conversations_to_firm.sql
-- ============================================================================

-- Links client conversations started from an office lawyer back to the office.
--
-- Run after patch_035. Without this, conversations opened from a lawyer profile
-- can stay only on lawyer_id, so the office inbox and office metrics do not see
-- them.

create index if not exists conversations_law_firm_idx
on public.conversations(law_firm_id);

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
          c.law_firm_id is null
          and c.lawyer_id is not null
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.profile_id = auth.uid()
              and lfm.status = 'active'
              and 'lawyer' = any(lfm.roles)
              and coalesce(lfm.lawyer_id, lfm.profile_id) = c.lawyer_id
              and coalesce(
                lfm.lawyer_invite_status,
                'active'::public.law_firm_member_status
              ) = 'active'
              and c.created_at >= coalesce(lfm.joined_at, lfm.created_at, c.created_at)
          )
        )
        or (
          c.case_id is not null
          and public.can_access_case(c.case_id)
        )
      )
  );
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
    and case_id is null
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

with active_lawyer_members as (
  select distinct on (coalesce(lfm.lawyer_id, lfm.profile_id))
    coalesce(lfm.lawyer_id, lfm.profile_id) as lawyer_profile_id,
    lfm.law_firm_id,
    coalesce(lfm.joined_at, lfm.created_at, now()) as member_since
  from public.law_firm_members lfm
  where coalesce(lfm.lawyer_id, lfm.profile_id) is not null
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(
      lfm.lawyer_invite_status,
      'active'::public.law_firm_member_status
    ) = 'active'
  order by
    coalesce(lfm.lawyer_id, lfm.profile_id),
    coalesce(lfm.joined_at, lfm.created_at, now()) desc
)
update public.conversations c
set
  law_firm_id = active_lawyer_members.law_firm_id,
  updated_at = now()
from active_lawyer_members
where c.lawyer_id = active_lawyer_members.lawyer_profile_id
  and c.law_firm_id is null
  and c.case_id is null
  and c.type = 'client_firm'
  and c.created_at >= active_lawyer_members.member_since;

revoke all on function public.can_access_conversation(uuid)
from public, anon;

revoke all on function public.start_or_get_lawyer_conversation(uuid, text)
from public, anon;

grant execute on function public.can_access_conversation(uuid)
to authenticated;

grant execute on function public.start_or_get_lawyer_conversation(uuid, text)
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_037_remove_law_firm_lawyers_count.sql
-- ============================================================================

-- Removes the deprecated office lawyer-count field from verification records.
--
-- Run after patch_036. The app no longer asks for or sends this value; actual
-- office members are tracked through law_firm_members instead.

alter table if exists public.law_firm_verifications
drop column if exists lawyers_count;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_038_case_assignment_conversation_access.sql
-- ============================================================================

-- Makes office case assignment surface the existing office chat to the lawyer.
--
-- Run after patch_037. When an office assigns a case that came from an office
-- conversation, the assigned lawyer should see that same chat in the lawyer
-- message flow, and the chat should show a system assignment event.

create or replace function public.assign_law_firm_case(
  law_firm_id_value uuid,
  case_id_value uuid,
  lawyer_profile_id_value uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
  old_lawyer_id uuid;
  target_lawyer_id uuid;
  target_lawyer_name text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_case_manager(law_firm_id_value) then
    raise exception 'Only office case managers can assign cases';
  end if;

  select *
  into case_row
  from public.legal_cases
  where id = case_id_value
  for update;

  if not found then
    raise exception 'Case not found';
  end if;

  if not (
    case_row.law_firm_id = law_firm_id_value
    or exists (
      select 1
      from public.law_firm_members lfm
      where lfm.law_firm_id = law_firm_id_value
        and lfm.profile_id = case_row.assigned_lawyer_id
        and lfm.status = 'active'
    )
    or exists (
      select 1
      from public.case_participants cp
      join public.law_firm_members lfm
        on lfm.profile_id = cp.profile_id
      where cp.case_id = case_row.id
        and cp.role in ('lawyer', 'firm_member')
        and lfm.law_firm_id = law_firm_id_value
        and lfm.status = 'active'
    )
  ) then
    raise exception 'Case does not belong to this office';
  end if;

  select
    coalesce(lfm.lawyer_id, lfm.profile_id),
    coalesce(p.full_name, 'Advogado')
  into target_lawyer_id, target_lawyer_name
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  left join public.profiles p
    on p.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  where lfm.law_firm_id = law_firm_id_value
    and lfm.profile_id = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(lfm.lawyer_invite_status, 'active'::public.law_firm_member_status)
      = 'active'
  limit 1;

  if target_lawyer_id is null then
    raise exception 'Target member must be an active lawyer';
  end if;

  old_lawyer_id := case_row.assigned_lawyer_id;

  update public.legal_cases
  set
    law_firm_id = coalesce(law_firm_id, law_firm_id_value),
    assigned_lawyer_id = target_lawyer_id,
    last_update_label = 'Caso atribuído',
    updated_at = now()
  where id = case_id_value;

  if old_lawyer_id is not null and old_lawyer_id <> target_lawyer_id then
    delete from public.case_participants
    where case_id = case_id_value
      and profile_id = old_lawyer_id
      and role = 'lawyer';
  end if;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, target_lawyer_id, 'lawyer')
  on conflict (case_id, profile_id) do update
  set role = 'lawyer';

  update public.conversations
  set
    law_firm_id = coalesce(law_firm_id, law_firm_id_value),
    lawyer_id = target_lawyer_id,
    updated_at = now()
  where case_id = case_id_value
    and type <> 'firm_internal';

  if old_lawyer_id is distinct from target_lawyer_id then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    select
      c.id,
      auth.uid(),
      'system',
      'Caso atribuído a ' || target_lawyer_name || '.',
      jsonb_build_object(
        'type', 'case_assignment',
        'case_id', case_id_value,
        'lawyer_id', target_lawyer_id,
        'law_firm_id', law_firm_id_value
      )
    from public.conversations c
    where c.case_id = case_id_value
      and c.type <> 'firm_internal';
  end if;

  return target_lawyer_id;
end;
$$;

create or replace function public.fetch_conversations_for_current_user(
  scope_value text,
  law_firm_id_value uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  initials text,
  specialty text,
  last_message text,
  last_message_at timestamptz,
  law_firm_id uuid,
  client_id uuid,
  lawyer_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  with scoped_conversations as (
    select c.*
    from public.conversations c
    where auth.uid() is not null
      and exists (
        select 1
        from public.messages m
        where m.conversation_id = c.id
      )
      and (
        (
          scope_value = 'client'
          and c.client_id = auth.uid()
        )
        or (
          scope_value = 'lawyer'
          and c.type <> 'firm_internal'
          and (
            c.lawyer_id = auth.uid()
            or (
              c.case_id is not null
              and public.can_access_case(c.case_id)
            )
          )
        )
        or (
          scope_value = 'firmClient'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type <> 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
        or (
          scope_value = 'firmTeam'
          and law_firm_id_value is not null
          and c.law_firm_id = law_firm_id_value
          and c.type = 'firm_internal'
          and exists (
            select 1
            from public.law_firm_members lfm
            where lfm.law_firm_id = law_firm_id_value
              and lfm.profile_id = auth.uid()
              and lfm.status = 'active'
          )
        )
      )
  )
  select
    c.id,
    c.type::text,
    case
      when scope_value in ('lawyer', 'firmClient') then
        public.profile_display_name(
          client_profile.full_name,
          client_profile.deleted_display_name,
          client_profile.deleted_at
        )
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.name, c.title)
      when scope_value = 'client' and c.lawyer_id is not null then
        public.profile_display_name(
          lawyer_profile.full_name,
          lawyer_profile.deleted_display_name,
          lawyer_profile.deleted_at
        )
      else c.title
    end as title,
    case
      when scope_value in ('lawyer', 'firmClient') then
        coalesce(client_profile.initials, 'CL')
      when scope_value = 'client' and c.law_firm_id is not null then
        coalesce(lf.initials, 'JE')
      when scope_value = 'client' and c.lawyer_id is not null then
        coalesce(lawyer_profile.initials, 'AJ')
      else upper(left(trim(c.title), 2))
    end as initials,
    coalesce(c.specialty, 'Atendimento jurídico') as specialty,
    coalesce(c.last_message, 'Nova conversa') as last_message,
    c.last_message_at,
    c.law_firm_id,
    c.client_id,
    c.lawyer_id
  from scoped_conversations c
  left join public.profiles client_profile
    on client_profile.id = c.client_id
  left join public.law_firms lf
    on lf.id = c.law_firm_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = c.lawyer_id
  order by c.last_message_at desc nulls last, c.updated_at desc;
$$;

revoke all on function public.assign_law_firm_case(uuid, uuid, uuid)
from public, anon, authenticated;

revoke all on function public.fetch_conversations_for_current_user(text, uuid)
from public, anon, authenticated;

grant execute on function public.assign_law_firm_case(uuid, uuid, uuid)
to authenticated;

grant execute on function public.fetch_conversations_for_current_user(text, uuid)
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_039_chat_message_attachments.sql
-- ============================================================================

-- Adds private chat attachments for photos, PDFs and Word documents.
--
-- Run after patch_038. Attachments keep the existing conversation/message model:
-- the app uploads the file to Storage, then this RPC creates a normal message
-- and links exactly one attachment record to it.

insert into storage.buckets (id, name, public)
values ('chat-attachments', 'chat-attachments', false)
on conflict (id) do nothing;

create table if not exists public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete cascade,
  file_name text not null,
  mime_type text not null,
  file_size_bytes bigint not null check (
    file_size_bytes > 0 and file_size_bytes <= 10485760
  ),
  storage_path text not null unique,
  kind text not null check (kind in ('image', 'document')),
  created_at timestamptz not null default now(),
  unique (message_id),
  check (length(trim(file_name)) > 0),
  check (length(trim(storage_path)) > 0)
);

create index if not exists message_attachments_message_idx
on public.message_attachments(message_id);

create index if not exists message_attachments_conversation_idx
on public.message_attachments(conversation_id);

alter table public.message_attachments enable row level security;

drop policy if exists "message_attachments_select_related"
on public.message_attachments;

create policy "message_attachments_select_related"
on public.message_attachments for select
to authenticated
using (public.can_access_conversation(conversation_id));

drop policy if exists "message_attachments_insert_related"
on public.message_attachments;

create policy "message_attachments_insert_related"
on public.message_attachments for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and public.can_access_conversation(conversation_id)
  and storage_path like auth.uid()::text || '/%'
  and exists (
    select 1
    from public.messages m
    where m.id = message_attachments.message_id
      and m.conversation_id = message_attachments.conversation_id
  )
);

grant select, insert on public.message_attachments to authenticated;

drop policy if exists "chat_attachments_storage_read_related"
on storage.objects;

create policy "chat_attachments_storage_read_related"
on storage.objects for select
to authenticated
using (
  bucket_id = 'chat-attachments'
  and exists (
    select 1
    from public.message_attachments ma
    where ma.storage_path = storage.objects.name
      and public.can_access_conversation(ma.conversation_id)
  )
);

drop policy if exists "chat_attachments_storage_own_folder_write"
on storage.objects;

create policy "chat_attachments_storage_own_folder_write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "chat_attachments_storage_own_folder_delete"
on storage.objects;

create policy "chat_attachments_storage_own_folder_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create or replace function public.send_chat_attachment(
  conversation_id_value uuid,
  file_name_value text,
  mime_type_value text,
  file_size_bytes_value bigint,
  storage_path_value text,
  kind_value text,
  sender_type_value text
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_type text,
  body text,
  metadata jsonb,
  read_at timestamptz,
  created_at timestamptz,
  attachment_id uuid,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  storage_path text,
  kind text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_file_name text;
  normalized_mime text;
  normalized_kind text;
  clean_storage_path text;
  message_body text;
  message_id_value uuid;
  attachment_id_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'User cannot access this conversation';
  end if;

  clean_file_name := nullif(trim(coalesce(file_name_value, '')), '');
  normalized_mime := lower(trim(coalesce(mime_type_value, '')));
  normalized_kind := lower(trim(coalesce(kind_value, '')));
  clean_storage_path := nullif(trim(coalesce(storage_path_value, '')), '');

  if clean_file_name is null or clean_storage_path is null then
    raise exception 'Attachment file name and storage path are required';
  end if;

  if clean_storage_path not like auth.uid()::text || '/%' then
    raise exception 'Attachment storage path must be in the current user folder';
  end if;

  if coalesce(sender_type_value, '') not in ('client', 'lawyer') then
    raise exception 'Invalid message sender type';
  end if;

  if normalized_kind not in ('image', 'document') then
    raise exception 'Invalid attachment kind';
  end if;

  if coalesce(file_size_bytes_value, 0) <= 0 then
    raise exception 'Attachment file is empty';
  end if;

  if normalized_kind = 'image' then
    if normalized_mime not in ('image/jpeg', 'image/png', 'image/webp') then
      raise exception 'Unsupported image type';
    end if;
    if file_size_bytes_value > 5242880 then
      raise exception 'Image attachment exceeds 5 MB';
    end if;
    message_body := 'Foto enviada';
  else
    if normalized_mime not in (
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ) then
      raise exception 'Unsupported document type';
    end if;
    if file_size_bytes_value > 10485760 then
      raise exception 'Document attachment exceeds 10 MB';
    end if;
    message_body := 'Documento enviado';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body,
    metadata
  )
  values (
    conversation_id_value,
    auth.uid(),
    sender_type_value::public.message_sender_type,
    message_body,
    jsonb_build_object(
      'type', 'chat_attachment',
      'attachment_kind', normalized_kind,
      'file_name', clean_file_name,
      'mime_type', normalized_mime,
      'file_size_bytes', file_size_bytes_value,
      'storage_path', clean_storage_path
    )
  )
  returning messages.id into message_id_value;

  insert into public.message_attachments (
    message_id,
    conversation_id,
    uploaded_by,
    file_name,
    mime_type,
    file_size_bytes,
    storage_path,
    kind
  )
  values (
    message_id_value,
    conversation_id_value,
    auth.uid(),
    clean_file_name,
    normalized_mime,
    file_size_bytes_value,
    clean_storage_path,
    normalized_kind
  )
  returning message_attachments.id into attachment_id_value;

  update public.messages as msg
  set metadata = msg.metadata || jsonb_build_object('attachment_id', attachment_id_value)
  where msg.id = message_id_value;

  return query
  select
    m.id,
    m.conversation_id,
    m.sender_id,
    m.sender_type::text,
    m.body,
    m.metadata,
    m.read_at,
    m.created_at,
    ma.id,
    ma.file_name,
    ma.mime_type,
    ma.file_size_bytes,
    ma.storage_path,
    ma.kind
  from public.messages m
  join public.message_attachments ma
    on ma.message_id = m.id
  where m.id = message_id_value;
end;
$$;

revoke all on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
from public, anon, authenticated;

grant execute on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_040_fix_chat_attachment_metadata_update.sql
-- ============================================================================

-- Hotfix for patch_039.
--
-- Run after patch_039 if sending an attachment fails with:
-- column reference "metadata" is ambiguous.

create or replace function public.send_chat_attachment(
  conversation_id_value uuid,
  file_name_value text,
  mime_type_value text,
  file_size_bytes_value bigint,
  storage_path_value text,
  kind_value text,
  sender_type_value text
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_type text,
  body text,
  metadata jsonb,
  read_at timestamptz,
  created_at timestamptz,
  attachment_id uuid,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  storage_path text,
  kind text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_file_name text;
  normalized_mime text;
  normalized_kind text;
  clean_storage_path text;
  message_body text;
  message_id_value uuid;
  attachment_id_value uuid;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'User cannot access this conversation';
  end if;

  clean_file_name := nullif(trim(coalesce(file_name_value, '')), '');
  normalized_mime := lower(trim(coalesce(mime_type_value, '')));
  normalized_kind := lower(trim(coalesce(kind_value, '')));
  clean_storage_path := nullif(trim(coalesce(storage_path_value, '')), '');

  if clean_file_name is null or clean_storage_path is null then
    raise exception 'Attachment file name and storage path are required';
  end if;

  if clean_storage_path not like auth.uid()::text || '/%' then
    raise exception 'Attachment storage path must be in the current user folder';
  end if;

  if coalesce(sender_type_value, '') not in ('client', 'lawyer') then
    raise exception 'Invalid message sender type';
  end if;

  if normalized_kind not in ('image', 'document') then
    raise exception 'Invalid attachment kind';
  end if;

  if coalesce(file_size_bytes_value, 0) <= 0 then
    raise exception 'Attachment file is empty';
  end if;

  if normalized_kind = 'image' then
    if normalized_mime not in ('image/jpeg', 'image/png', 'image/webp') then
      raise exception 'Unsupported image type';
    end if;
    if file_size_bytes_value > 5242880 then
      raise exception 'Image attachment exceeds 5 MB';
    end if;
    message_body := 'Foto enviada';
  else
    if normalized_mime not in (
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ) then
      raise exception 'Unsupported document type';
    end if;
    if file_size_bytes_value > 10485760 then
      raise exception 'Document attachment exceeds 10 MB';
    end if;
    message_body := 'Documento enviado';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    sender_type,
    body,
    metadata
  )
  values (
    conversation_id_value,
    auth.uid(),
    sender_type_value::public.message_sender_type,
    message_body,
    jsonb_build_object(
      'type', 'chat_attachment',
      'attachment_kind', normalized_kind,
      'file_name', clean_file_name,
      'mime_type', normalized_mime,
      'file_size_bytes', file_size_bytes_value,
      'storage_path', clean_storage_path
    )
  )
  returning messages.id into message_id_value;

  insert into public.message_attachments (
    message_id,
    conversation_id,
    uploaded_by,
    file_name,
    mime_type,
    file_size_bytes,
    storage_path,
    kind
  )
  values (
    message_id_value,
    conversation_id_value,
    auth.uid(),
    clean_file_name,
    normalized_mime,
    file_size_bytes_value,
    clean_storage_path,
    normalized_kind
  )
  returning message_attachments.id into attachment_id_value;

  update public.messages as msg
  set metadata = msg.metadata || jsonb_build_object('attachment_id', attachment_id_value)
  where msg.id = message_id_value;

  return query
  select
    m.id,
    m.conversation_id,
    m.sender_id,
    m.sender_type::text,
    m.body,
    m.metadata,
    m.read_at,
    m.created_at,
    ma.id,
    ma.file_name,
    ma.mime_type,
    ma.file_size_bytes,
    ma.storage_path,
    ma.kind
  from public.messages m
  join public.message_attachments ma
    on ma.message_id = m.id
  where m.id = message_id_value;
end;
$$;

revoke all on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
from public, anon, authenticated;

grant execute on function public.send_chat_attachment(
  uuid, text, text, bigint, text, text, text
)
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- ============================================================================
-- Source: supabase/patch_041_security_hardening.sql
-- ============================================================================

-- Patch 041 — Hardening de segurança (auditoria jul/2026).
--
-- Corrige os furos de RLS/privilégios encontrados na auditoria:
--   1. Auto-promoção a advogado: qualquer usuário podia dar UPDATE em
--      profiles.lawyer_status='approved' (grant amplo do patch_005) e inserir
--      a própria linha em lawyer_profiles, furando a verificação OAB.
--   2. Vazamento de PII (LGPD): a policy profiles_select_approved_lawyers_public
--      expunha a linha INTEIRA de profiles (cpf, phone, email) de todo advogado
--      aprovado para qualquer usuário autenticado.
--   3. Auto-aprovação de verificações: o WITH CHECK das policies de UPDATE de
--      lawyer_verifications/law_firm_verifications não impedia o próprio autor
--      de setar status='approved'.
--   4. Spoofing de sender_type: cliente podia inserir mensagem como
--      'system'/'lawyer' (engenharia social no chat).
--   5. verification_documents aceitava insert apontando para verificação alheia.
--   6. Bucket chat-attachments sem limite de tamanho/tipo no Storage (o RPC
--      valida, mas upload direto pela Storage API não passava pelo RPC).
--   7. Typo público "(delleted account)" → "(conta excluída)".
--
-- Rodar após o patch_040. Não remove dados; apenas policies/grants/config.
-- Reversível: cada bloco documenta o estado anterior.

-- ---------------------------------------------------------------------------
-- 1. profiles: privilégios por coluna.
--    Antes: grant select,insert,update on profiles to authenticated (patch_005)
--    permitia escrever lawyer_status/member_since diretamente.
--    As funções SECURITY DEFINER (handle_new_auth_user, approve_lawyer_verification,
--    delete_current_account etc.) não são afetadas — rodam como owner.
-- ---------------------------------------------------------------------------

revoke insert, update on public.profiles from authenticated;
revoke select on public.profiles from anon;

grant insert (id, full_name, email, initials, cpf, phone, avatar_url)
on public.profiles to authenticated;

grant update (full_name, email, initials, cpf, phone, avatar_url)
on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. profiles: remove a policy que expunha a linha inteira (cpf/phone/email)
--    de advogados aprovados a qualquer autenticado. Os cards e entrypoints do
--    app usam RPCs SECURITY DEFINER (fetch_recommended_lawyers,
--    fetch_chat_profile, start_or_get_lawyer_conversation), que continuam
--    funcionando e retornam apenas campos não sensíveis.
-- ---------------------------------------------------------------------------

drop policy if exists "profiles_select_approved_lawyers_public"
on public.profiles;

-- ---------------------------------------------------------------------------
-- 3. lawyer_profiles: fim do self-service de perfil profissional.
--    A criação passa a ocorrer somente via fluxo de aprovação/convite
--    (funções SECURITY DEFINER). O advogado poderá editar apenas campos
--    não privilegiados do próprio perfil (bio, áreas, foto, disponibilidade)
--    quando a tela de edição existir.
-- ---------------------------------------------------------------------------

drop policy if exists "lawyer_profiles_insert_own" on public.lawyer_profiles;

revoke insert, update on public.lawyer_profiles from authenticated;

grant update (bio, practice_areas, is_available, professional_photo_url)
on public.lawyer_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 4. lawyer_verifications: o autor pode editar a própria verificação em
--    rascunho/pendente, mas nunca mudar status para aprovado nem preencher
--    campos de revisão. Aprovação continua exclusiva de
--    approve_lawyer_verification (service_role).
-- ---------------------------------------------------------------------------

drop policy if exists "lawyer_verifications_update_own_pending"
on public.lawyer_verifications;

create policy "lawyer_verifications_update_own_pending"
on public.lawyer_verifications for update
to authenticated
using (user_id = auth.uid() and status in ('draft', 'pending'))
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and reviewer_id is null
  and reviewed_at is null
);

-- Mesmo endurecimento para verificações de escritório (patch_004 só checava
-- owner_profile_id no WITH CHECK).

drop policy if exists "law_firm_verifications_update_own_pending"
on public.law_firm_verifications;

create policy "law_firm_verifications_update_own_pending"
on public.law_firm_verifications for update
to authenticated
using (owner_profile_id = auth.uid() and status in ('draft', 'pending'))
with check (
  owner_profile_id = auth.uid()
  and status in ('draft', 'pending')
);

-- ---------------------------------------------------------------------------
-- 5. verification_documents: o insert precisa apontar para uma verificação do
--    próprio usuário (antes bastava user_id = auth.uid(), permitindo poluir a
--    verificação de terceiros). Idem para documentos de escritório.
-- ---------------------------------------------------------------------------

drop policy if exists "verification_documents_insert_own"
on public.verification_documents;

create policy "verification_documents_insert_own"
on public.verification_documents for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.lawyer_verifications lv
    where lv.id = verification_documents.verification_id
      and lv.user_id = auth.uid()
  )
);

drop policy if exists "law_firm_verification_documents_insert_own"
on public.law_firm_verification_documents;

create policy "law_firm_verification_documents_insert_own"
on public.law_firm_verification_documents for insert
to authenticated
with check (
  owner_profile_id = auth.uid()
  and exists (
    select 1
    from public.law_firm_verifications lfv
    where lfv.id = law_firm_verification_documents.verification_id
      and lfv.owner_profile_id = auth.uid()
  )
);

-- ---------------------------------------------------------------------------
-- 6. messages: sender_type precisa corresponder ao papel real do remetente.
--    'client' apenas para o client_id da conversa; 'lawyer' apenas para quem
--    tem acesso e NÃO é o cliente; 'system' nunca via insert direto (somente
--    RPCs SECURITY DEFINER, que não passam por esta policy).
-- ---------------------------------------------------------------------------

drop policy if exists "messages_insert_related" on public.messages;

create policy "messages_insert_related"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_conversation(messages.conversation_id)
  and (
    (
      sender_type = 'client'
      and exists (
        select 1
        from public.conversations c
        where c.id = messages.conversation_id
          and c.client_id = auth.uid()
      )
    )
    or (
      sender_type = 'lawyer'
      and exists (
        select 1
        from public.conversations c
        where c.id = messages.conversation_id
          and c.client_id is distinct from auth.uid()
      )
    )
  )
);

-- ---------------------------------------------------------------------------
-- 7. Storage: aplica no bucket os mesmos limites que o RPC
--    send_chat_attachment valida (upload direto pela Storage API deixava
--    passar qualquer tipo/tamanho).
-- ---------------------------------------------------------------------------

update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
where id = 'chat-attachments';

-- ---------------------------------------------------------------------------
-- 8. Correção do sufixo público de conta excluída (typo + idioma).
--    Recria a função de exibição e corrige títulos já gravados.
-- ---------------------------------------------------------------------------

create or replace function public.profile_display_name(
  full_name_value text,
  deleted_at_value timestamptz,
  deleted_display_name_value text
)
returns text
language sql
immutable
as $$
  select case
    when deleted_at_value is not null then
      coalesce(
        nullif(trim(deleted_display_name_value), ''),
        nullif(trim(full_name_value), ''),
        'Usuário'
      ) || ' (conta excluída)'
    else
      coalesce(nullif(trim(full_name_value), ''), 'Usuário Jurii')
  end;
$$;

update public.conversations
set title = replace(title, ' (delleted account)', ' (conta excluída)')
where title like '% (delleted account)';

-- A função delete_current_account concatena o sufixo em conversations.title;
-- recria apenas o trecho? Não: a função inteira vive no patch_035. Para não
-- duplicar 300 linhas aqui, o texto novo passa a valer para exibição via
-- profile_display_name; o UPDATE acima corrige os títulos persistidos.
-- PENDÊNCIA: ao editar o patch_035 novamente, trocar o literal
-- ' (delleted account)' por ' (conta excluída)' dentro de
-- delete_current_account (linha ~226).

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verificação pós-patch (rodar como usuário de teste autenticado):
--   update public.profiles set lawyer_status='approved' where id = auth.uid();
--     → deve falhar com "permission denied for table profiles".
--   select cpf from public.profiles where id <> auth.uid() limit 1;
--     → deve retornar 0 linhas para advogados não relacionados.
--   update public.lawyer_verifications set status='approved'
--     where user_id = auth.uid();
--     → deve falhar pela policy (WITH CHECK).
--   insert into public.messages (conversation_id, sender_id, sender_type, body)
--     values ('<conversa própria>', auth.uid(), 'system', 'x');
--     → deve falhar pela policy.
-- ---------------------------------------------------------------------------

-- ============================================================================
-- Source: supabase/patch_042_search_word_boundary.sql
-- ============================================================================

-- Patch 042 — Precisão da inferência de área na busca (auditoria jul/2026).
--
-- Alinha a busca do servidor com o mirror local endurecido em
-- lib/data/legal_practice_areas.dart. Rode depois do patch_041.
--
-- Problema: public.legal_search_term_matches (patch_029) casava termo por
-- substring solta:
--     q like '%' || term || '%'   -- "iss" (imposto) casava em "dem*iss*ao"
--     term like '%' || q || '%'
-- Isso gerava falsos positivos de área — ex.: um relato puramente trabalhista
-- inferia Direito Tributário ("iss") e Cível ("nao ... pagaram"), poluindo as
-- recomendações de advogados/escritórios do fetch_recommended_*.
--
-- Correção (espelha _searchIntentTermMatches do Dart):
--   1. Casamento por LIMITE DE PALAVRA (padding com espaços), cobrindo termo de
--      uma palavra ("fgts") e frase inteira ("marido me bateu"), sem casar
--      sigla curta no meio de outra palavra.
--   2. Query de palavra única que é o começo de alguma palavra do termo
--      ("aposenta" -> "aposentadoria").
--   3. Frase cujos tokens significativos (>= 4 letras, antes >= 3) aparecem
--      todos como palavras da query — o piso de 4 evita palavras comuns curtas
--      ("nao", "com", "sem") virarem sinal.
-- Também remove o termo semeado 'das' (guia do MEI), que colidia com a
-- contração "das".
--
-- Só a função de matching muda; infer_legal_search_areas e fetch_recommended_*
-- continuam válidas (mesma assinatura) e mantêm o ranqueamento por weight
-- curado do patch_029 — o mirror local ordena por nº de termos que casaram, mas
-- ambos passam a compartilhar exatamente o mesmo critério de casamento.

create or replace function public.legal_search_term_matches(
  normalized_query text,
  normalized_term text
)
returns boolean
language sql
immutable
as $$
  with cleaned as (
    select
      nullif(trim(coalesce(normalized_query, '')), '') as q,
      nullif(trim(coalesce(normalized_term, '')), '') as term
  ),
  evaluated as (
    select
      -- 1) Termo presente respeitando limites de palavra. O padding com espaços
      --    transforma "contém como palavra/frase inteira" num LIKE simples,
      --    já que a normalização deixa só [a-z0-9] e espaços simples.
      (
        cleaned.q is not null
        and cleaned.term is not null
        and (' ' || cleaned.q || ' ') like ('% ' || cleaned.term || ' %')
      ) as whole_match,
      -- 2) Query de palavra única (sem espaço, >= 4 letras) que prefixa alguma
      --    palavra do termo.
      (
        cleaned.q is not null
        and cleaned.term is not null
        and position(' ' in cleaned.q) = 0
        and length(cleaned.q) >= 4
        and exists (
          select 1
          from regexp_split_to_table(cleaned.term, ' ') as term_token(tok)
          where term_token.tok like cleaned.q || '%'
        )
      ) as prefix_match,
      -- 3) Tokens significativos (>= 4 letras) do termo, todos presentes como
      --    palavras da query (mesmo fora de ordem).
      (
        cleaned.q is not null
        and cleaned.term is not null
        and (
          select count(*)
          from regexp_split_to_table(cleaned.term, ' ') as term_token(tok)
          where length(term_token.tok) >= 4
        ) >= 2
        and not exists (
          select 1
          from regexp_split_to_table(cleaned.term, ' ') as term_token(tok)
          where length(term_token.tok) >= 4
            and term_token.tok not in (
              select query_token.tok
              from regexp_split_to_table(cleaned.q, ' ') as query_token(tok)
            )
        )
      ) as token_subset_match
    from cleaned
  )
  select coalesce(
    whole_match or prefix_match or token_subset_match,
    false
  )
  from evaluated;
$$;

-- Remove o termo 'das' (guia do MEI): colide com a contração "das" ("fotos das
-- agressões") e gera falso positivo de Direito Tributário. Cobertura de MEI
-- segue por 'mei imposto' / 'simples nacional'. Espelha a remoção no mirror
-- local (lib/data/legal_practice_areas.dart).
delete from public.legal_search_intents
where normalized_phrase = 'das'
  and practice_area = 'Direito Tributário';

notify pgrst, 'reload schema';

-- Verificação pós-patch (rode e confira manualmente no SQL Editor):
--
--   -- 1) "demissão" NÃO deve inferir Tributário (era o bug do "iss").
--   select * from public.infer_legal_search_areas(
--     'minha demissao foi sem justa causa e nao recebi as verbas'
--   );
--   -- Esperado: Direito Trabalhista (e nada de Tributário/Cível).
--
--   -- 2) A contração "das" NÃO deve inferir Tributário.
--   select * from public.infer_legal_search_areas('guardei as fotos das conversas');
--   -- Esperado: sem Direito Tributário.
--
--   -- 3) Casos legítimos continuam funcionando.
--   select * from public.infer_legal_search_areas('meu marido me bateu');   -- Criminal
--   select * from public.infer_legal_search_areas('inss negou meu auxilio'); -- Previdenciário
--   select * from public.infer_legal_search_areas('fui demitido sem receber');-- Trabalhista
--
--   -- 4) O termo 'das' saiu da tabela.
--   select count(*) from public.legal_search_intents where normalized_phrase = 'das';
--   -- Esperado: 0.

-- ============================================================================
-- Source: supabase/patch_043_fix_firm_case_scope.sql
-- ============================================================================

-- Patch 043 -- Escopo estrito de casos do escritorio.
--
-- Rode depois do patch_042.
--
-- Problema: as RPCs de escritorio herdadas do patch_030 tratavam como "caso do
-- escritorio" qualquer caso atribuido a um advogado membro ou com participante
-- membro do escritorio. Isso permitia que o escritorio A enxergasse ou
-- reatribuisse um caso pessoal do advogado, ou um caso de outro escritorio, so
-- porque o advogado tambem era membro do escritorio A.
--
-- Correcao: na superficie do escritorio, caso pertence ao escritorio somente
-- quando public.legal_cases.law_firm_id = law_firm_id_value. Membership de
-- advogado continua servindo para permissao/atribuicao dentro desse escritorio,
-- mas nunca para "puxar" caso de fora para dentro.

create or replace function public.fetch_law_firm_cases(
  law_firm_id_value uuid
)
returns table (
  id uuid,
  title text,
  client_name text,
  client_initials text,
  assigned_lawyer_id uuid,
  assigned_lawyer text,
  area text,
  status_label text,
  next_step text,
  urgent boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select lfm.profile_id, lfm.roles
    from public.law_firm_members lfm
    where lfm.law_firm_id = law_firm_id_value
      and lfm.profile_id = auth.uid()
      and lfm.status = 'active'
    limit 1
  ),
  scoped_cases as (
    select lc.*
    from public.legal_cases lc
    where lc.law_firm_id = law_firm_id_value
      and exists (select 1 from viewer)
      and (
        exists (
          select 1
          from viewer
          where roles && array['owner', 'admin', 'secretary']::text[]
        )
        or lc.assigned_lawyer_id = auth.uid()
        or exists (
          select 1
          from public.case_participants cp
          where cp.case_id = lc.id
            and cp.profile_id = auth.uid()
        )
      )
  )
  select
    sc.id,
    sc.title,
    public.profile_display_name(
      client_profile.full_name,
      client_profile.deleted_at,
      client_profile.deleted_display_name
    ) as client_name,
    coalesce(client_profile.initials, 'CL') as client_initials,
    sc.assigned_lawyer_id,
    case
      when lawyer_profile.id is null then 'Sem advogado definido'
      else public.profile_display_name(
        lawyer_profile.full_name,
        lawyer_profile.deleted_at,
        lawyer_profile.deleted_display_name
      )
    end as assigned_lawyer,
    sc.area,
    public.case_status_label(sc.status) as status_label,
    coalesce(sc.last_update_label, 'Atualizado hoje') as next_step,
    sc.status = 'deadline' as urgent,
    sc.updated_at
  from scoped_cases sc
  left join public.profiles client_profile
    on client_profile.id = sc.client_id
  left join public.profiles lawyer_profile
    on lawyer_profile.id = sc.assigned_lawyer_id
  order by sc.updated_at desc;
$$;

create or replace function public.assign_law_firm_case(
  law_firm_id_value uuid,
  case_id_value uuid,
  lawyer_profile_id_value uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  case_row public.legal_cases%rowtype;
  old_lawyer_id uuid;
  target_lawyer_id uuid;
  target_lawyer_name text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  if not public.is_active_law_firm_case_manager(law_firm_id_value) then
    raise exception 'Only office case managers can assign cases';
  end if;

  select *
  into case_row
  from public.legal_cases
  where id = case_id_value
  for update;

  if not found then
    raise exception 'Case not found';
  end if;

  if case_row.law_firm_id is distinct from law_firm_id_value then
    raise exception 'Case does not belong to this office';
  end if;

  select
    coalesce(lfm.lawyer_id, lfm.profile_id),
    coalesce(p.full_name, 'Advogado')
  into target_lawyer_id, target_lawyer_name
  from public.law_firm_members lfm
  join public.lawyer_profiles lp
    on lp.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  left join public.profiles p
    on p.id = coalesce(lfm.lawyer_id, lfm.profile_id)
  where lfm.law_firm_id = law_firm_id_value
    and lfm.profile_id = lawyer_profile_id_value
    and lfm.status = 'active'
    and 'lawyer' = any(lfm.roles)
    and coalesce(lfm.lawyer_invite_status, 'active'::public.law_firm_member_status)
      = 'active'
  limit 1;

  if target_lawyer_id is null then
    raise exception 'Target member must be an active lawyer';
  end if;

  old_lawyer_id := case_row.assigned_lawyer_id;

  update public.legal_cases
  set
    law_firm_id = law_firm_id_value,
    assigned_lawyer_id = target_lawyer_id,
    last_update_label = 'Caso atribuído',
    updated_at = now()
  where id = case_id_value;

  if old_lawyer_id is not null and old_lawyer_id <> target_lawyer_id then
    delete from public.case_participants
    where case_id = case_id_value
      and profile_id = old_lawyer_id
      and role = 'lawyer';
  end if;

  insert into public.case_participants (case_id, profile_id, role)
  values (case_id_value, target_lawyer_id, 'lawyer')
  on conflict (case_id, profile_id) do update
  set role = 'lawyer';

  update public.conversations
  set
    law_firm_id = law_firm_id_value,
    lawyer_id = target_lawyer_id,
    updated_at = now()
  where case_id = case_id_value
    and type <> 'firm_internal'
    and (
      law_firm_id = law_firm_id_value
      or law_firm_id is null
    );

  if old_lawyer_id is distinct from target_lawyer_id then
    insert into public.messages (
      conversation_id,
      sender_id,
      sender_type,
      body,
      metadata
    )
    select
      c.id,
      auth.uid(),
      'system',
      'Caso atribuído a ' || target_lawyer_name || '.',
      jsonb_build_object(
        'type', 'case_assignment',
        'case_id', case_id_value,
        'lawyer_id', target_lawyer_id,
        'law_firm_id', law_firm_id_value
      )
    from public.conversations c
    where c.case_id = case_id_value
      and c.type <> 'firm_internal'
      and c.law_firm_id = law_firm_id_value;
  end if;

  return target_lawyer_id;
end;
$$;

revoke all on function public.fetch_law_firm_cases(uuid)
from public, anon, authenticated;

revoke all on function public.assign_law_firm_case(uuid, uuid, uuid)
from public, anon, authenticated;

grant execute on function public.fetch_law_firm_cases(uuid)
to authenticated;

grant execute on function public.assign_law_firm_case(uuid, uuid, uuid)
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- Verificacao pos-patch (substitua os ids e rode como membro do escritorio):
--
--   -- 1) A lista do escritorio deve conter apenas casos do proprio escritorio.
--   select *
--   from public.fetch_law_firm_cases('<LAW_FIRM_ID>'::uuid);
--
--   -- 2) Atribuir caso pessoal/de outro escritorio deve falhar:
--   select public.assign_law_firm_case(
--     '<LAW_FIRM_ID>'::uuid,
--     '<CASE_ID_COM_LAW_FIRM_ID_DIFERENTE_OU_NULL>'::uuid,
--     '<PROFILE_ID_DO_ADVOGADO_ALVO>'::uuid
--   );
--   -- Esperado: "Case does not belong to this office".
--
--   -- 3) Diagnostico de casos que antes poderiam vazar por membership:
--   select lc.id, lc.title, lc.law_firm_id, lc.assigned_lawyer_id
--   from public.legal_cases lc
--   where lc.law_firm_id is null
--     and exists (
--       select 1
--       from public.law_firm_members lfm
--       where lfm.law_firm_id = '<LAW_FIRM_ID>'::uuid
--         and lfm.status = 'active'
--         and (
--           lfm.profile_id = lc.assigned_lawyer_id
--           or lfm.lawyer_id = lc.assigned_lawyer_id
--         )
--     );
--   -- Esperado para fetch_law_firm_cases: esses casos NAO aparecem.

-- ============================================================================
-- Source: supabase/patch_044_account_deletion_lgpd.sql
-- ============================================================================

-- Patch 044 -- Auditoria da exclusao LGPD via Edge Function.
--
-- Rode depois do patch_043 e faca deploy da Edge Function
-- supabase/functions/delete-account.
--
-- O soft-delete historico continua em public.delete_current_account(), mas a
-- exclusao completa agora deve ser iniciada pela Edge Function `delete-account`,
-- que roda com service_role para:
--   1. apagar Storage sensivel de verificacao/avatar;
--   2. executar o soft-delete transacional existente;
--   3. banir o usuario em auth.users;
--   4. registrar auditoria tecnica nesta tabela.
--
-- Nao apagamos anexos de chat nem documentos de caso aqui: eles podem ser
-- prova/evidencia e precisam de politica de retencao propria.

create table if not exists public.account_deletion_audit (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'started'
    check (status in ('started', 'completed', 'failed')),
  storage_summary jsonb not null default '{}'::jsonb,
  auth_banned_at timestamptz,
  error_message text
);

create index if not exists account_deletion_audit_profile_idx
on public.account_deletion_audit(profile_id, requested_at desc);

alter table public.account_deletion_audit enable row level security;

revoke all on table public.account_deletion_audit
from public, anon, authenticated;

grant select, insert, update on table public.account_deletion_audit
to service_role;

-- Corrige o literal antigo para novas exclusoes. O patch_041 corrigiu a
-- funcao de exibicao, mas delete_current_account ainda gravava o sufixo
-- historico em conversas diretas sem escritorio.
create or replace function public.delete_current_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_id_value uuid;
  profile_row public.profiles%rowtype;
  deleted_name_value text;
  deleted_email_value text;
begin
  profile_id_value := auth.uid();

  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  select *
  into profile_row
  from public.profiles
  where id = profile_id_value
  for update;

  if not found then
    return;
  end if;

  if profile_row.deleted_at is not null then
    return;
  end if;

  deleted_name_value := coalesce(
    nullif(trim(profile_row.deleted_display_name), ''),
    nullif(trim(profile_row.full_name), ''),
    'Usuário'
  );
  deleted_email_value := nullif(trim(profile_row.email), '');

  perform public.transfer_owned_law_firms_for_deleted_profile(profile_id_value);

  update public.conversations
  set
    title = deleted_name_value || ' (conta excluída)',
    updated_at = now()
  where lawyer_id = profile_id_value
    and law_firm_id is null;

  update public.law_firm_members
  set
    status = 'disabled',
    lawyer_id = null,
    pending_lawyer_id = null,
    lawyer_invite_status = 'disabled'
  where profile_id = profile_id_value
     or lawyer_id = profile_id_value
     or pending_lawyer_id = profile_id_value;

  delete from public.verification_documents
  where user_id = profile_id_value;

  delete from public.lawyer_verifications
  where user_id = profile_id_value;

  delete from public.lawyer_profiles
  where id = profile_id_value;

  delete from public.law_firm_verification_documents lfvd
  where lfvd.owner_profile_id = profile_id_value
    and exists (
      select 1
      from public.law_firm_verifications lfv
      where lfv.id = lfvd.verification_id
        and lfv.owner_profile_id = profile_id_value
        and lfv.status <> 'approved'
    );

  update public.law_firm_verifications
  set
    status = case
      when law_firm_id is null then 'rejected'::public.verification_status
      else status
    end,
    rejection_reason = case
      when law_firm_id is null then 'Conta solicitante excluída.'
      else rejection_reason
    end,
    updated_at = now()
  where owner_profile_id = profile_id_value;

  update public.profiles
  set
    deleted_at = now(),
    deleted_display_name = deleted_name_value,
    deleted_email = deleted_email_value,
    full_name = deleted_name_value,
    email = 'deleted+' || profile_id_value::text || '@deleted.jurii.local',
    cpf = null,
    phone = null,
    avatar_url = null,
    lawyer_status = 'client'
  where id = profile_id_value;
end;
$$;

revoke all on function public.delete_current_account()
from public, anon, authenticated;

grant execute on function public.delete_current_account()
to authenticated;

select pg_notify('pgrst', 'reload schema');

-- Verificacao pos-patch:
--
--   select column_name, data_type
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name = 'account_deletion_audit';
--
--   -- Depois de acionar a Edge Function:
--   select profile_id, status, completed_at, auth_banned_at, storage_summary
--   from public.account_deletion_audit
--   order by requested_at desc
--   limit 5;

-- ============================================================================
-- Source: supabase/patch_045_profiles_id_update_grant.sql
-- ============================================================================

-- Patch 045 — Corrige o upsert de profiles bloqueado pelo hardening do patch_041.
--
-- Rode depois do patch_044.
--
-- Problema (confirmado em runtime, 2026-07-06): o patch_041 revogou UPDATE amplo
-- em public.profiles e concedeu UPDATE apenas em
--   (full_name, email, initials, cpf, phone, avatar_url).
-- O app faz `.upsert()` em profiles (lib/repositories/profile_repository.dart)
-- enviando `id`. Um upsert do PostgREST vira
--   INSERT ... ON CONFLICT (id) DO UPDATE SET ... , id = EXCLUDED.id
-- e o ramo DO UPDATE toca a coluna `id`, que tem grant de INSERT mas NÃO de
-- UPDATE. Resultado reproduzido com usuário de teste autenticado:
--   POST /rest/v1/profiles (Prefer: resolution=merge-duplicates)
--   -> HTTP 403, 42501 "permission denied for table profiles".
--
-- Impacto real hoje é BAIXO (o cadastro grava full_name/email/initials/cpf pela
-- trigger handle_new_auth_user, SECURITY DEFINER, que não passa por grants), mas
-- o caminho de upsert do app fica morto: qualquer edição futura de perfil
-- (telefone, avatar, nome) via esse upsert falharia em silêncio (o app engole o
-- erro em try/catch). Este patch destrava esse caminho.
--
-- Segurança: a policy profiles_update_own já é
--   using (id = auth.uid()) with check (id = auth.uid())
-- (supabase/schema.sql), então conceder UPDATE em `id` NÃO permite repontar a
-- linha para outro usuário — o WITH CHECK exige que o id resultante continue
-- sendo o do próprio usuário. Na prática o SET id = EXCLUDED.id é um no-op.

grant update (id) on public.profiles to authenticated;

notify pgrst, 'reload schema';

-- Verificação pós-patch (como usuário de teste autenticado, via REST):
--   POST /rest/v1/profiles
--     apikey: <publishable>  Authorization: Bearer <jwt do usuário>
--     Prefer: resolution=merge-duplicates,return=representation
--     body: {"id":"<auth.uid()>","full_name":"X","email":"...","initials":"X",
--            "cpf":"52998224725","phone":"11999998888"}
--   -> deve retornar 200/201 e a linha com cpf/phone atualizados
--      (antes deste patch retornava 403 / 42501).
