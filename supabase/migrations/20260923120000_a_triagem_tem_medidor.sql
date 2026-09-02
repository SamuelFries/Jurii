-- A triagem tem medidor.
--
-- A IA de triagem (docs/ai-intake.md) passa a chamar a API da Anthropic por
-- uma Edge Function. Cada chamada custa dinheiro de verdade, e a chave anon é
-- pública: sem um teto POR USUÁRIO, uma conta descartável em loop transforma
-- a triagem num gerador de fatura. O teto vive no banco, no mesmo desenho do
-- teto de envio de mensagens e do orçamento de convites: a Edge Function
-- chama esta RPC ANTES de tocar a API, e a recusa acontece aqui, onde o
-- estado é confiável, não no cliente.
--
-- Dimensionamento: uma sessão de triagem completa faz ~5 chamadas (até 4
-- perguntas + 1 resumo). 12/hora acomoda duas sessões completas com folga;
-- 30/dia acomoda o dia de uso legítimo mais atrapalhado que conseguimos
-- imaginar (seis sessões). Custo por conta por dia, com Sonnet 5: uso
-- legítimo ~30 × US$0,003 ≈ US$0,09; o PIOR caso adversarial (cada chamada
-- com a entrada no teto de 24K chars que a função aceita) ~30 × US$0,015 ≈
-- US$0,45. Nos dois mundos, o abuso não paga o próprio trabalho.
--
-- A tabela não guarda CONTEÚDO nenhum: só quem chamou e quando. A conversa
-- da triagem continua efêmera (decisão pendente em docs/ai-intake.md); isto
-- aqui é taxímetro, não persistência.

create table public.intake_ai_calls (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  called_at timestamptz not null default now()
);

-- O índice serve à contagem por janela e ao cascade do delete de conta
-- (invariante de supabase/tests/perf_invariants_test.sql: toda FK indexada).
create index intake_ai_calls_profile_recentes_idx
  on public.intake_ai_calls (profile_id, called_at);

alter table public.intake_ai_calls enable row level security;
-- Sem policy e sem grant: nem o dono lê o próprio taxímetro. Quem escreve é
-- a função abaixo, definer; quem administra usa o painel.
revoke all on table public.intake_ai_calls from public, anon, authenticated;

create or replace function public.registrar_chamada_de_triagem()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid;
begin
  caller := auth.uid();
  if caller is null then
    raise exception 'User must be authenticated';
  end if;

  -- Trava por usuário ANTES da contagem: N chamadas simultâneas não passam
  -- todas pela conferência antes de qualquer uma gravar (mesmo desenho de
  -- criar_link_de_convite e submit_lawyer_verification).
  perform pg_catalog.pg_advisory_xact_lock(
    17004,
    pg_catalog.hashtext(caller::text)
  );

  -- Faxina de passagem: o taxímetro só precisa de 24h de memória. Apagar o
  -- resto aqui dispensa cron e mantém a tabela do tamanho do dia.
  delete from public.intake_ai_calls c
  where c.profile_id = caller
    and c.called_at < now() - interval '48 hours';

  if (
    select count(*)
    from public.intake_ai_calls c
    where c.profile_id = caller
      and c.called_at >= now() - interval '1 hour'
  ) >= 12 then
    raise exception 'Intake AI hourly limit reached. Try again later';
  end if;

  if (
    select count(*)
    from public.intake_ai_calls c
    where c.profile_id = caller
      and c.called_at >= now() - interval '24 hours'
  ) >= 30 then
    raise exception 'Intake AI daily limit reached. Try again tomorrow';
  end if;

  insert into public.intake_ai_calls (profile_id) values (caller);
end;
$$;

revoke all on function public.registrar_chamada_de_triagem() from public, anon;
grant execute on function public.registrar_chamada_de_triagem() to authenticated;
