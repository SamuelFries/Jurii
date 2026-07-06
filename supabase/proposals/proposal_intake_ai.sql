-- PROPOSTA (não aplicar ainda) — Tabelas para a IA de triagem (intake).
--
-- Suporta o fluxo de lib/services/intake_ai_service.dart quando ele migrar
-- do modo local (rule-based) para persistência + IA real via Edge Function.
-- Só aplicar quando o produto decidir persistir sessões de triagem.
--
-- LGPD: os relatos do cliente são dados sensíveis (art. 5º, II). Este desenho:
--   * RLS estrita: só o titular lê as próprias sessões;
--   * o advogado só lê o RESUMO depois que o cliente consente em enviar
--     (consented_at) e a sessão é vinculada a uma conversa/caso;
--   * exclusão em cascata quando o profile é removido;
--   * retention_expires_at para expurgo programado de sessões abandonadas.

create table if not exists public.intake_sessions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'collecting'
    check (status in ('collecting', 'ready', 'delivered', 'abandoned')),
  inferred_practice_areas text[] not null default '{}'::text[],
  conversation_id uuid references public.conversations(id) on delete set null,
  consented_at timestamptz,
  retention_expires_at timestamptz not null default now() + interval '90 days',
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.intake_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.intake_sessions(id) on delete cascade,
  sender text not null check (sender in ('assistant', 'client')),
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.intake_summaries (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.intake_sessions(id) on delete cascade,
  case_summary text not null,
  urgency text not null check (urgency in ('low', 'medium', 'high', 'critical')),
  urgency_reason text,
  key_points text[] not null default '{}'::text[],
  pending_questions text[] not null default '{}'::text[],
  generated_at timestamptz not null default now(),
  unique (session_id)
);

create table if not exists public.intake_category_suggestions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.intake_sessions(id) on delete cascade,
  practice_area text not null,
  confidence numeric(3, 2) not null check (confidence >= 0 and confidence <= 1),
  unique (session_id, practice_area)
);

create table if not exists public.intake_recommended_documents (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.intake_sessions(id) on delete cascade,
  title text not null,
  reason text
);

create index if not exists intake_sessions_client_idx
  on public.intake_sessions(client_id);
create index if not exists intake_messages_session_idx
  on public.intake_messages(session_id, created_at);
create index if not exists intake_sessions_retention_idx
  on public.intake_sessions(retention_expires_at);

alter table public.intake_sessions enable row level security;
alter table public.intake_messages enable row level security;
alter table public.intake_summaries enable row level security;
alter table public.intake_category_suggestions enable row level security;
alter table public.intake_recommended_documents enable row level security;

-- Titular: acesso total às próprias sessões.
create policy "intake_sessions_own"
on public.intake_sessions for all
to authenticated
using (client_id = auth.uid())
with check (client_id = auth.uid());

create policy "intake_messages_own"
on public.intake_messages for all
to authenticated
using (
  exists (
    select 1 from public.intake_sessions s
    where s.id = intake_messages.session_id and s.client_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.intake_sessions s
    where s.id = intake_messages.session_id and s.client_id = auth.uid()
  )
);

-- Advogado: lê apenas o RESUMO (nunca a conversa bruta) e só após consentimento
-- e entrega via conversa que ele pode acessar.
create policy "intake_summaries_read"
on public.intake_summaries for select
to authenticated
using (
  exists (
    select 1 from public.intake_sessions s
    where s.id = intake_summaries.session_id
      and (
        s.client_id = auth.uid()
        or (
          s.status = 'delivered'
          and s.consented_at is not null
          and s.conversation_id is not null
          and public.can_access_conversation(s.conversation_id)
        )
      )
  )
);

-- (Policies análogas à de summaries para category_suggestions e
-- recommended_documents; escrita dessas três tabelas apenas via função
-- SECURITY DEFINER/Edge Function que gera o resumo.)

-- Integração futura com IA real (a chave NUNCA vai no app Flutter):
--   Edge Function `intake-chat` (Deno) com ANTHROPIC_API_KEY em secret;
--   o app chama supabase.functions.invoke('intake-chat', body: {...});
--   a função valida o JWT, roda o prompt e persiste nas tabelas acima.
-- Ver docs/ai-intake.md.
