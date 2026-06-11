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
  lawyer_id uuid not null references public.lawyer_profiles(id) on delete cascade,
  role text not null default 'lawyer',
  joined_at timestamptz not null default now(),
  unique (law_firm_id, lawyer_id)
);

create table if not exists public.lawyer_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  oab_number text not null,
  oab_state char(2) not null,
  practice_area text not null,
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

create policy "profiles_select_related_case_or_conversation"
on public.profiles for select
to authenticated
using (
  exists (
    select 1 from public.legal_cases lc
    where (
      lc.client_id = auth.uid()
      and lc.assigned_lawyer_id = profiles.id
    )
    or (
      lc.assigned_lawyer_id = auth.uid()
      and lc.client_id = profiles.id
    )
  )
  or exists (
    select 1 from public.conversations c
    where (
      c.client_id = auth.uid()
      and c.lawyer_id = profiles.id
    )
    or (
      c.lawyer_id = auth.uid()
      and c.client_id = profiles.id
    )
  )
);

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
  lawyer_id = auth.uid()
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
using (
  client_id = auth.uid()
  or assigned_lawyer_id = auth.uid()
  or exists (
    select 1 from public.case_participants cp
    where cp.case_id = legal_cases.id
      and cp.profile_id = auth.uid()
  )
);

create policy "legal_cases_insert_as_client"
on public.legal_cases for insert
to authenticated
with check (client_id = auth.uid());

create policy "legal_cases_update_related"
on public.legal_cases for update
to authenticated
using (
  client_id = auth.uid()
  or assigned_lawyer_id = auth.uid()
  or exists (
    select 1 from public.case_participants cp
    where cp.case_id = legal_cases.id
      and cp.profile_id = auth.uid()
      and cp.role in ('lawyer', 'firm_member')
  )
);

create policy "case_participants_select_related"
on public.case_participants for select
to authenticated
using (
  profile_id = auth.uid()
  or exists (
    select 1 from public.legal_cases lc
    where lc.id = case_participants.case_id
      and (lc.client_id = auth.uid() or lc.assigned_lawyer_id = auth.uid())
  )
);

create policy "case_documents_select_related"
on public.case_documents for select
to authenticated
using (
  uploaded_by = auth.uid()
  or exists (
    select 1 from public.legal_cases lc
    where lc.id = case_documents.case_id
      and (lc.client_id = auth.uid() or lc.assigned_lawyer_id = auth.uid())
  )
);

create policy "case_documents_insert_related"
on public.case_documents for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and exists (
    select 1 from public.legal_cases lc
    where lc.id = case_documents.case_id
      and (lc.client_id = auth.uid() or lc.assigned_lawyer_id = auth.uid())
  )
);

create policy "conversations_select_related"
on public.conversations for select
to authenticated
using (
  client_id = auth.uid()
  or lawyer_id = auth.uid()
  or exists (
    select 1 from public.legal_cases lc
    where lc.id = conversations.case_id
      and (lc.client_id = auth.uid() or lc.assigned_lawyer_id = auth.uid())
  )
);

create policy "conversations_insert_as_client"
on public.conversations for insert
to authenticated
with check (client_id = auth.uid());

create policy "messages_select_related"
on public.messages for select
to authenticated
using (
  exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.client_id = auth.uid() or c.lawyer_id = auth.uid())
  )
);

create policy "messages_insert_related"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.client_id = auth.uid() or c.lawyer_id = auth.uid())
  )
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
    join public.legal_cases lc on lc.id = cd.case_id
    where cd.storage_path = storage.objects.name
      and (lc.client_id = auth.uid() or lc.assigned_lawyer_id = auth.uid())
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

insert into public.law_firms (id, name, initials, specialty, rating, reviews_count, distance_label, avatar_type)
values
  ('11111111-1111-4111-8111-111111111111', 'Fries Advogados', 'FA', 'Direito Trabalhista', 4.9, 128, '1,8 km', 'navy'),
  ('22222222-2222-4222-8222-222222222222', 'Silva & Associados', 'SA', 'Direito de Família', 4.8, 94, '2,4 km', 'blue'),
  ('33333333-3333-4333-8333-333333333333', 'Moura Advogados', 'MA', 'Direito do Consumidor', 4.7, 76, '3,1 km', 'gold')
on conflict (id) do update set
  name = excluded.name,
  initials = excluded.initials,
  specialty = excluded.specialty,
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
