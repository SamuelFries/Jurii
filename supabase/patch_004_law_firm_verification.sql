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
  lawyers_count int not null default 1 check (lawyers_count >= 0),
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
