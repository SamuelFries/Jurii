-- Notificacoes push - fundacao server-side (parte 1: device tokens)
--
-- Guarda os tokens de push (FCM) dos dispositivos de cada usuario. O app
-- registra o token no login/abertura e remove no logout. A Edge Function de
-- envio (send-push) le esses tokens por uma funcao service_role.
--
-- Push depende de um projeto Firebase (credenciais + config nativa) que so o
-- Samuel provê — ver o checklist em docs/notas-socio.md. Esta migration e o
-- codigo do envio ficam prontos esperando isso; nada aqui exige o Firebase.

-- ---------------------------------------------------------------------------
-- 1. Tabela de tokens
--
-- token e UNICO: um mesmo aparelho tem um token FCM. Se o aparelho troca de
-- conta (logout A / login B), o token e reatribuido ao novo dono (ver o upsert
-- em register_push_token) — senao o push de A iria para o aparelho de B.
-- ---------------------------------------------------------------------------

create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('ios', 'android', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_tokens_profile_idx
  on public.push_tokens(profile_id);

-- RLS ligado e SEM policy de escrita/leitura: todo acesso passa por RPC
-- SECURITY DEFINER. Um cliente nao lê nem escreve a tabela direto.
alter table public.push_tokens enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Registrar token (upsert por token)
-- ---------------------------------------------------------------------------

create or replace function public.register_push_token(
  token_value text,
  platform_value text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_token text;
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  clean_token := nullif(trim(coalesce(token_value, '')), '');
  if clean_token is null then
    raise exception 'Token is required';
  end if;

  if platform_value not in ('ios', 'android', 'web') then
    raise exception 'Invalid platform';
  end if;

  insert into public.push_tokens (profile_id, token, platform)
  values (auth.uid(), clean_token, platform_value)
  on conflict (token) do update
  set
    profile_id = auth.uid(),
    platform = excluded.platform,
    updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Remover token (logout) — so o proprio dono
-- ---------------------------------------------------------------------------

create or replace function public.unregister_push_token(token_value text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'User must be authenticated';
  end if;

  delete from public.push_tokens
  where token = token_value
    and profile_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Ler tokens de um destinatario — SO a Edge Function (service_role)
--
-- Fora do alcance de authenticated/anon: um cliente nao deve descobrir os
-- tokens de ninguem, so a funcao de servidor que envia o push.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_push_tokens_for_recipient(
  recipient_id uuid
)
returns table (token text, platform text)
language sql
stable
security definer
set search_path = public
as $$
  select pt.token, pt.platform
  from public.push_tokens pt
  where pt.profile_id = recipient_id;
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------

revoke all on function public.register_push_token(text, text) from public, anon;
revoke all on function public.unregister_push_token(text) from public, anon;
revoke all on function public.fetch_push_tokens_for_recipient(uuid) from public, anon, authenticated;

grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;
grant execute on function public.fetch_push_tokens_for_recipient(uuid) to service_role;

notify pgrst, 'reload schema';
