-- ---------------------------------------------------------------------------
-- Avaliações de advogados e escritórios (notas + comentários dos clientes)
-- ---------------------------------------------------------------------------
-- Ate aqui a nota exibida era FALSA: os RPCs de advogado cravavam 4.8 no
-- hardcode e `lawyer_profiles` nem tinha coluna de rating (law_firms tinha, mas
-- sempre 0). Esta migration cria a infra real:
--   - colunas rating/reviews_count em lawyer_profiles (law_firms ja tem);
--   - tabela professional_reviews (uma por cliente por profissional);
--   - trigger que recalcula a media/contagem do alvo;
--   - RPCs de submissao/remocao/leitura, com gate: so avalia quem teve pelo
--     menos um CASO ACEITO com o profissional (conversa nao basta);
--   - reescrita de fetch_recommended_lawyers / fetch_lawyer_public_profile para
--     devolver a nota real.
-- Migration nova e aditiva; producao ja tem a baseline aplicada.
-- ---------------------------------------------------------------------------

-- 1. Nota agregada no advogado (o escritorio ja tem em law_firms) -----------
alter table public.lawyer_profiles
  add column if not exists rating numeric(2, 1) not null default 0
    check (rating >= 0 and rating <= 5);
alter table public.lawyer_profiles
  add column if not exists reviews_count int not null default 0
    check (reviews_count >= 0);

-- 2. Tabela de avaliacoes ---------------------------------------------------
create table if not exists public.professional_reviews (
  id uuid primary key default gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('lawyer', 'law_firm')),
  lawyer_id uuid references public.lawyer_profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  rating int not null check (rating >= 1 and rating <= 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Exatamente um alvo, coerente com target_type.
  constraint professional_reviews_target_chk check (
    (target_type = 'lawyer' and lawyer_id is not null and law_firm_id is null)
    or
    (target_type = 'law_firm' and law_firm_id is not null and lawyer_id is null)
  )
);

-- Uma avaliacao por cliente por profissional (upsert edita a existente).
create unique index if not exists professional_reviews_lawyer_unique
  on public.professional_reviews (reviewer_id, lawyer_id)
  where lawyer_id is not null;
create unique index if not exists professional_reviews_firm_unique
  on public.professional_reviews (reviewer_id, law_firm_id)
  where law_firm_id is not null;

create index if not exists professional_reviews_lawyer_idx
  on public.professional_reviews (lawyer_id) where lawyer_id is not null;
create index if not exists professional_reviews_firm_idx
  on public.professional_reviews (law_firm_id) where law_firm_id is not null;

-- 3. RLS: leitura publica (a nota e publica); escrita so via RPC ------------
alter table public.professional_reviews enable row level security;

drop policy if exists "professional_reviews_select_all"
  on public.professional_reviews;
create policy "professional_reviews_select_all"
  on public.professional_reviews for select
  to authenticated
  using (true);

-- Sem policy de insert/update/delete: escrita passa so pelos RPCs SECURITY
-- DEFINER abaixo, que aplicam o gate.
grant select on public.professional_reviews to authenticated;

-- 4. Agregacao: recalcula rating/contagem do alvo afetado -------------------
create or replace function public.recompute_professional_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  lawyer_target uuid := coalesce(new.lawyer_id, old.lawyer_id);
  firm_target uuid := coalesce(new.law_firm_id, old.law_firm_id);
begin
  if lawyer_target is not null then
    update public.lawyer_profiles lp
    set
      rating = coalesce((
        select round(avg(r.rating)::numeric, 1)
        from public.professional_reviews r
        where r.lawyer_id = lawyer_target
      ), 0),
      reviews_count = (
        select count(*)
        from public.professional_reviews r
        where r.lawyer_id = lawyer_target
      )
    where lp.id = lawyer_target;
  end if;

  if firm_target is not null then
    update public.law_firms lf
    set
      rating = coalesce((
        select round(avg(r.rating)::numeric, 1)
        from public.professional_reviews r
        where r.law_firm_id = firm_target
      ), 0),
      reviews_count = (
        select count(*)
        from public.professional_reviews r
        where r.law_firm_id = firm_target
      )
    where lf.id = firm_target;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists professional_reviews_recompute
  on public.professional_reviews;
create trigger professional_reviews_recompute
after insert or update or delete on public.professional_reviews
for each row execute function public.recompute_professional_rating();

-- 5. Gate: so avalia quem teve CASO ACEITO com o profissional ---------------
-- Conversa nao basta (seria fabrica de nota). O vinculo real e o caso: quando
-- o cliente aceita a solicitacao (respond_to_case_request), nasce a linha em
-- `legal_cases` com client_id + assigned_lawyer_id + law_firm_id. Checar
-- legal_cases cobre tambem o caso atribuido pelo escritorio
-- (assign_law_firm_case). O OR em case_requests('accepted') e cinto e
-- suspensorio: a FK legal_case_id e `on delete set null`, entao um caso
-- removido nao pode apagar o direito de avaliar de quem ja foi atendido.
create or replace function public.can_review_professional(
  target_type_value text,
  target_id_value uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when target_type_value = 'lawyer' then (
      exists (
        select 1 from public.legal_cases lc
        where lc.client_id = auth.uid()
          and lc.assigned_lawyer_id = target_id_value
      )
      or exists (
        select 1 from public.case_requests cr
        where cr.client_id = auth.uid()
          and cr.lawyer_id = target_id_value
          and cr.status = 'accepted'
      )
    )
    when target_type_value = 'law_firm' then (
      exists (
        select 1 from public.legal_cases lc
        where lc.client_id = auth.uid()
          and lc.law_firm_id = target_id_value
      )
      or exists (
        select 1 from public.case_requests cr
        where cr.client_id = auth.uid()
          and cr.law_firm_id = target_id_value
          and cr.status = 'accepted'
      )
    )
    else false
  end;
$$;

-- 6. Submissao (upsert) -----------------------------------------------------
create or replace function public.submit_professional_review(
  target_type_value text,
  target_id_value uuid,
  rating_value int,
  comment_value text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  reviewer uuid := auth.uid();
  clean_comment text := nullif(trim(coalesce(comment_value, '')), '');
  review_id uuid;
begin
  if reviewer is null then
    raise exception 'É preciso estar autenticado para avaliar.'
      using errcode = '42501';
  end if;
  if rating_value is null or rating_value < 1 or rating_value > 5 then
    raise exception 'A nota deve ser de 1 a 5.' using errcode = '22023';
  end if;
  if not public.can_review_professional(target_type_value, target_id_value) then
    raise exception 'Você só pode avaliar após ter um caso aceito com este profissional.'
      using errcode = '42501';
  end if;

  if target_type_value = 'lawyer' then
    update public.professional_reviews
    set rating = rating_value, comment = clean_comment, updated_at = now()
    where reviewer_id = reviewer and lawyer_id = target_id_value
    returning id into review_id;

    if review_id is null then
      insert into public.professional_reviews
        (reviewer_id, target_type, lawyer_id, rating, comment)
      values (reviewer, 'lawyer', target_id_value, rating_value, clean_comment)
      returning id into review_id;
    end if;
  else
    update public.professional_reviews
    set rating = rating_value, comment = clean_comment, updated_at = now()
    where reviewer_id = reviewer and law_firm_id = target_id_value
    returning id into review_id;

    if review_id is null then
      insert into public.professional_reviews
        (reviewer_id, target_type, law_firm_id, rating, comment)
      values (reviewer, 'law_firm', target_id_value, rating_value, clean_comment)
      returning id into review_id;
    end if;
  end if;

  return review_id;
end;
$$;

revoke all on function public.submit_professional_review(text, uuid, int, text)
  from public, anon;
grant execute on function public.submit_professional_review(text, uuid, int, text)
  to authenticated;

-- 7. Remocao da propria avaliacao ------------------------------------------
create or replace function public.delete_professional_review(
  target_type_value text,
  target_id_value uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if target_type_value = 'lawyer' then
    delete from public.professional_reviews
    where reviewer_id = auth.uid() and lawyer_id = target_id_value;
  elsif target_type_value = 'law_firm' then
    delete from public.professional_reviews
    where reviewer_id = auth.uid() and law_firm_id = target_id_value;
  end if;
end;
$$;

revoke all on function public.delete_professional_review(text, uuid)
  from public, anon;
grant execute on function public.delete_professional_review(text, uuid)
  to authenticated;

-- 8. Leitura das avaliacoes de um profissional ------------------------------
create or replace function public.fetch_professional_reviews(
  target_type_value text,
  target_id_value uuid,
  limit_value int default 20
)
returns table (
  id uuid,
  reviewer_name text,
  reviewer_initials text,
  rating int,
  comment text,
  created_at timestamptz,
  is_mine boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    coalesce(p.full_name, 'Cliente Jurii') as reviewer_name,
    coalesce(p.initials, 'C') as reviewer_initials,
    r.rating,
    r.comment,
    r.created_at,
    r.reviewer_id = auth.uid() as is_mine
  from public.professional_reviews r
  join public.profiles p on p.id = r.reviewer_id
  where (target_type_value = 'lawyer' and r.lawyer_id = target_id_value)
     or (target_type_value = 'law_firm' and r.law_firm_id = target_id_value)
  order by (r.reviewer_id = auth.uid()) desc, r.created_at desc
  limit least(greatest(coalesce(limit_value, 20), 1), 100);
$$;

revoke all on function public.fetch_professional_reviews(text, uuid, int)
  from public, anon;
grant execute on function public.fetch_professional_reviews(text, uuid, int)
  to authenticated;

-- 9. Elegibilidade + minha avaliacao (o app decide se mostra o botao) -------
create or replace function public.fetch_review_eligibility(
  target_type_value text,
  target_id_value uuid
)
returns table (
  can_review boolean,
  my_rating int,
  my_comment text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    public.can_review_professional(target_type_value, target_id_value),
    r.rating,
    r.comment
  from (select 1) dummy
  left join public.professional_reviews r
    on r.reviewer_id = auth.uid()
    and (
      (target_type_value = 'lawyer' and r.lawyer_id = target_id_value)
      or (target_type_value = 'law_firm' and r.law_firm_id = target_id_value)
    );
$$;

revoke all on function public.fetch_review_eligibility(text, uuid)
  from public, anon;
grant execute on function public.fetch_review_eligibility(text, uuid)
  to authenticated;

-- 10. Reescrita: fetch_recommended_lawyers usa a nota REAL do advogado ----
--     (extraida verbatim do baseline; so as linhas de rating mudaram)
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
      lp.rating,
      lp.reviews_count,
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

-- 11. Reescrita: fetch_lawyer_public_profile usa a nota REAL --------------
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
    lp.rating,
    lp.reviews_count,
    'navy'::text as avatar_type
  from public.lawyer_profiles lp
  join public.profiles p on p.id = lp.id
  where lp.id = lawyer_profile_id_value
    and lp.is_available = true
    and p.deleted_at is null
  limit 1;
$$;
