-- Favoritos do cliente: salvar advogados e escritórios para achar depois
-- (estilo iFood). Duas decisões de produto travadas aqui:
--   1. favorito é PRIVADO do cliente — nenhuma contagem pública, nenhum
--      sinal ao profissional (contador viraria métrica de vaidade e mais um
--      vetor de manipulação de ranking, que o motor de destaque já bloqueia);
--   2. favorito NÃO altera o ranking da descoberta — vive em tela própria.
--
-- Mesmo lockdown de featured_placements: RLS ligada SEM policy + revoke de
-- tabela (duas camadas); toda leitura/escrita por RPC SECURITY DEFINER.

create table if not exists public.client_favorites (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('lawyer', 'law_firm')),
  lawyer_id uuid references public.lawyer_profiles(id) on delete cascade,
  law_firm_id uuid references public.law_firms(id) on delete cascade,
  created_at timestamptz not null default now(),
  -- Exatamente um alvo, coerente com target_type (padrão de
  -- featured_placements/professional_reviews).
  constraint client_favorites_target_chk check (
    (target_type = 'lawyer' and lawyer_id is not null and law_firm_id is null)
    or (target_type = 'law_firm' and law_firm_id is not null and lawyer_id is null)
  )
);

-- Um favorito por par (parciais porque o alvo é XOR).
create unique index if not exists client_favorites_client_lawyer_key
  on public.client_favorites (client_id, lawyer_id)
  where lawyer_id is not null;

create unique index if not exists client_favorites_client_law_firm_key
  on public.client_favorites (client_id, law_firm_id)
  where law_firm_id is not null;

-- Índices de FK (convenção <tabela>_<coluna>_idx da 20260731120000). Os
-- únicos parciais acima NÃO cobrem lawyer_id/law_firm_id: começam por
-- client_id — o cascade de lawyer_profiles/law_firms varreria a tabela.
create index if not exists client_favorites_client_id_idx
  on public.client_favorites (client_id);

create index if not exists client_favorites_lawyer_id_idx
  on public.client_favorites (lawyer_id);

create index if not exists client_favorites_law_firm_id_idx
  on public.client_favorites (law_firm_id);

alter table public.client_favorites enable row level security;

revoke all on table public.client_favorites from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- toggle_favorite: liga/desliga e devolve o estado novo (true = favoritado).
-- Desligar é sempre permitido; ligar valida que o alvo existe e está visível
-- (advogado não excluído / escritório ativo) — favoritar fantasma não.
-- Autofavorito é permitido de propósito: é privado, não há contagem, não há
-- ganho a inflar.
-- ---------------------------------------------------------------------------
create function public.toggle_favorite(
  target_type_value text,
  target_id_value uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  current_client_id uuid := auth.uid();
  removed int;
begin
  if current_client_id is null then
    raise exception 'Not authenticated';
  end if;

  if target_type_value not in ('lawyer', 'law_firm') then
    raise exception 'Invalid favorite target type';
  end if;

  if target_type_value = 'lawyer' then
    delete from public.client_favorites cf
    where cf.client_id = current_client_id
      and cf.lawyer_id = target_id_value;
    get diagnostics removed = row_count;
    if removed > 0 then
      return false;
    end if;

    if not exists (
      select 1
      from public.lawyer_profiles lp
      join public.profiles p on p.id = lp.id
      where lp.id = target_id_value
        and p.deleted_at is null
    ) then
      raise exception 'Favorite target not found';
    end if;

    insert into public.client_favorites (client_id, target_type, lawyer_id)
    values (current_client_id, 'lawyer', target_id_value)
    on conflict do nothing;
    return true;
  end if;

  delete from public.client_favorites cf
  where cf.client_id = current_client_id
    and cf.law_firm_id = target_id_value;
  get diagnostics removed = row_count;
  if removed > 0 then
    return false;
  end if;

  if not exists (
    select 1 from public.law_firms firm
    where firm.id = target_id_value
      and firm.is_active = true
  ) then
    raise exception 'Favorite target not found';
  end if;

  insert into public.client_favorites (client_id, target_type, law_firm_id)
  values (current_client_id, 'law_firm', target_id_value)
  on conflict do nothing;
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- fetch_favorite_ids: os pares (tipo, id) do usuário — estado dos corações.
-- ---------------------------------------------------------------------------
create function public.fetch_favorite_ids()
returns table (target_type text, target_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select
    cf.target_type,
    coalesce(cf.lawyer_id, cf.law_firm_id) as target_id
  from public.client_favorites cf
  where cf.client_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- fetch_favorite_lawyers: MESMA forma de fetch_recommended_lawyers (o app
-- reaproveita o parser). Ordem: favoritado mais recentemente primeiro.
-- Advogado de conta excluída some (deleted_at); indisponível CONTINUA
-- aparecendo — o usuário salvou, sumir sem explicação seria pior.
-- ---------------------------------------------------------------------------
create function public.fetch_favorite_lawyers()
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
  avatar_type text,
  avatar_url text,
  is_featured boolean
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
    'navy'::text as avatar_type,
    public.safe_profile_avatar_url(p.id, p.avatar_url) as avatar_url,
    exists (
      select 1
      from public.featured_placements fp
      where fp.lawyer_id = lp.id
        and fp.revoked_at is null
        and now() >= fp.starts_at
        and now() < fp.ends_at
    ) as is_featured
  from public.client_favorites cf
  join public.lawyer_profiles lp on lp.id = cf.lawyer_id
  join public.profiles p on p.id = lp.id
  where cf.client_id = auth.uid()
    and cf.target_type = 'lawyer'
    and p.deleted_at is null
  order by cf.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- fetch_favorite_law_firms: MESMA forma de fetch_recommended_law_firms.
-- Escritório desativado some (perfil morto não deve receber toque).
-- ---------------------------------------------------------------------------
create function public.fetch_favorite_law_firms()
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
  address text,
  avatar_url text,
  is_featured boolean,
  latitude double precision,
  longitude double precision
)
language sql
stable
security definer
set search_path = public
as $$
  select
    firm.id,
    firm.name,
    firm.initials,
    firm.rating,
    firm.distance_label,
    firm.specialty,
    case
      when cardinality(firm.practice_areas) > 0 then firm.practice_areas
      else array[firm.specialty]
    end as practice_areas,
    firm.reviews_count,
    firm.avatar_type,
    firm.description,
    firm.phone,
    firm.email,
    firm.website_url,
    firm.address,
    firm.avatar_url,
    exists (
      select 1
      from public.featured_placements fp
      where fp.law_firm_id = firm.id
        and fp.revoked_at is null
        and now() >= fp.starts_at
        and now() < fp.ends_at
    ) as is_featured,
    firm.latitude,
    firm.longitude
  from public.client_favorites cf
  join public.law_firms firm on firm.id = cf.law_firm_id
  where cf.client_id = auth.uid()
    and cf.target_type = 'law_firm'
    and firm.is_active = true
  order by cf.created_at desc;
$$;

revoke all on function public.toggle_favorite(text, uuid) from public, anon;
grant execute on function public.toggle_favorite(text, uuid) to authenticated;

revoke all on function public.fetch_favorite_ids() from public, anon;
grant execute on function public.fetch_favorite_ids() to authenticated;

revoke all on function public.fetch_favorite_lawyers() from public, anon;
grant execute on function public.fetch_favorite_lawyers() to authenticated;

revoke all on function public.fetch_favorite_law_firms() from public, anon;
grant execute on function public.fetch_favorite_law_firms() to authenticated;

notify pgrst, 'reload schema';
