-- As denúncias chegam ao painel da equipe.
--
-- ONDE ELAS IAM ATÉ AGORA: a lugar nenhum. `user_reports` nasceu com RLS sem
-- policy e revoke de authenticated/anon, e o comentário da migration que a
-- criou dizia "o back-office lê pelo painel (service_role)". Esse painel
-- nunca foi escrito. Ou seja, quem denunciava recebia a tela dizendo que a
-- denúncia foi registrada, e a linha ia para uma tabela que ninguém abria.
--
-- ---------------------------------------------------------------------------
-- A DECISÃO QUE IMPORTA: fotografia, não janela
-- ---------------------------------------------------------------------------
--
-- Denúncia sem conteúdo é inacionável: "conteúdo abusivo" sem o conteúdo é
-- uma acusação, e quem revisa decide no escuro ou não decide. Só que isto é
-- um produto jurídico, e conversa entre cliente e advogado é coberta por
-- sigilo profissional. A pergunta não é "mandar ou não", é QUANTO, QUANDO e
-- POR QUANTO TEMPO.
--
-- Por isso as mensagens são COPIADAS no instante da denúncia e congeladas,
-- em vez de o painel consultar `messages` ao vivo. Três consequências, e as
-- três são o motivo da escolha:
--
--  1. O recorte é limitado e datado. Uma consulta ao vivo daria à equipe uma
--     janela permanente para a conversa inteira, que só cresce depois da
--     denúncia. A fotografia mostra o que existia quando a acusação foi
--     feita, e nada do que veio depois.
--  2. A prova sobrevive ao apagar. Quem ofende e apaga para todos não apaga
--     a denúncia. Ler ao vivo deixaria o denunciado limpar o próprio rastro.
--  3. O que é enviado pode ser DITO a quem denuncia, porque é definido: as
--     15 últimas daquela conversa. Promessa vaga não se cumpre.
--
-- O acesso continua sendo o mesmo da fila de verificações: só quem está em
-- `jurii_staff`, por RPC SECURITY DEFINER, com a tabela fechada a todo
-- cliente.

-- ---------------------------------------------------------------------------
-- 1. A fotografia e a trilha da decisão
-- ---------------------------------------------------------------------------

alter table public.user_reports
  add column if not exists message_snapshot jsonb not null default '[]'::jsonb;

-- A mesma trilha das verificações: quem decidiu, quando e a nota. Sem isto a
-- aba vira caixa de entrada que nunca esvazia, e ninguém sabe quem olhou.
alter table public.user_reports
  add column if not exists reviewer_id uuid references public.profiles (id) on delete set null;
alter table public.user_reports
  add column if not exists reviewed_at timestamptz;
alter table public.user_reports
  add column if not exists review_note text check (char_length(review_note) <= 1000);

-- Toda chave estrangeira tem indice: e invariante da casa, cobrada por
-- perf_invariants_test, e ela pegou esta coluna nova no mesmo dia.
create index if not exists user_reports_reviewer_idx
  on public.user_reports (reviewer_id);

/**
 * As últimas N mensagens de uma conversa, em jsonb, para virar prova.
 *
 * INTERNA: sem grant de execute. Quem chama é `report_conversation`, que é
 * SECURITY DEFINER de dono postgres. Se qualquer pessoa autenticada pudesse
 * chamar, isto seria um leitor de conversa alheia com outro nome.
 *
 * Traz `deleted_for_all_at` em vez de esconder a mensagem apagada: no
 * momento da denúncia ela ainda existia, e é justamente a que costuma
 * interessar. Quem revisa vê que foi apagada, e vê o que dizia.
 */
create or replace function public.snapshot_de_conversa(
  conversation_id_value uuid,
  quantas integer default 15
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ultimas.id,
        'autor_id', ultimas.sender_id,
        'autor_tipo', ultimas.sender_type::text,
        'corpo', ultimas.body,
        'apagada', ultimas.deleted_for_all_at is not null,
        'criada_em', ultimas.created_at
      )
      order by ultimas.created_at asc
    ),
    '[]'::jsonb
  )
  from (
    select m.id, m.sender_id, m.sender_type, m.body, m.deleted_for_all_at, m.created_at
    from public.messages m
    where m.conversation_id = conversation_id_value
    order by m.created_at desc
    limit greatest(1, least(coalesce(quantas, 15), 50))
  ) ultimas;
$$;

revoke all on function public.snapshot_de_conversa(uuid, integer) from public;

-- ---------------------------------------------------------------------------
-- 2. Denunciar passa a levar a fotografia junto
-- ---------------------------------------------------------------------------
--
-- Cópia fiel da 20260801120000: muda SÓ o insert, que ganha a coluna nova.
-- Todas as guardas continuam iguais (razão fechada, acesso à conversa, canal
-- interno recusado, mensagem tem que ser da conversa, trava antiflood com
-- advisory lock, limpeza do texto livre).
create or replace function public.report_conversation(
  conversation_id_value uuid,
  reason_value text,
  details_value text default null,
  message_id_value uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conversation_row public.conversations%rowtype;
  reported_profile uuid;
  reported_firm uuid;
  clean_details text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if reason_value is null or reason_value not in (
    'conteudo_abusivo', 'golpe_ou_fraude', 'falsa_identidade', 'spam', 'outro'
  ) then
    raise exception 'Invalid report reason';
  end if;

  if not public.can_access_conversation(conversation_id_value) then
    raise exception 'Conversation not found';
  end if;

  select * into conversation_row
  from public.conversations
  where id = conversation_id_value;

  -- O canal interno da equipe não tem "contraparte": a denúncia apontaria o
  -- membro errado. Conflito interno se resolve na governança do escritório.
  if conversation_row.type = 'firm_internal' then
    raise exception 'Internal conversation';
  end if;

  -- Contraparte denunciada: para o cliente, o advogado da conversa (ou o
  -- escritório, no balcão); para o profissional, o cliente.
  if conversation_row.client_id = auth.uid() then
    reported_profile := conversation_row.lawyer_id;
    reported_firm := case
      when conversation_row.lawyer_id is null then conversation_row.law_firm_id
    end;
  else
    reported_profile := conversation_row.client_id;
    reported_firm := null;
  end if;

  -- Mensagem denunciada precisa pertencer à própria conversa.
  if message_id_value is not null and not exists (
    select 1
    from public.messages m
    where m.id = message_id_value
      and m.conversation_id = conversation_id_value
  ) then
    raise exception 'Message not in conversation';
  end if;

  -- Serializa o antiflood por usuário: sem o lock, denúncias concorrentes
  -- passariam todas pelo count antes de qualquer insert aparecer.
  perform pg_advisory_xact_lock(
    hashtext('user_reports:' || auth.uid()::text)
  );

  -- Antiflood: 10 denúncias por usuário por dia.
  if (
    select count(*)
    from public.user_reports r
    where r.reporter_profile_id = auth.uid()
      and r.created_at > now() - interval '1 day'
  ) >= 10 then
    raise exception 'Report limit reached';
  end if;

  -- Texto livre: sem caracteres de controle e com teto, mesma blindagem
  -- da migration 20260730150000 (log injection).
  clean_details := nullif(btrim(left(
    regexp_replace(coalesce(details_value, ''), '[[:cntrl:]]+', ' ', 'g'),
    1000
  )), '');

  insert into public.user_reports (
    reporter_profile_id,
    reported_profile_id,
    law_firm_id,
    conversation_id,
    message_id,
    reason,
    details,
    message_snapshot
  ) values (
    auth.uid(),
    reported_profile,
    reported_firm,
    conversation_id_value,
    message_id_value,
    reason_value,
    clean_details,
    -- A FOTOGRAFIA, tirada agora. Depois desta linha o conteúdo da conversa
    -- pode mudar à vontade: esta denúncia continua mostrando o que existia
    -- quando alguém decidiu denunciar.
    public.snapshot_de_conversa(conversation_id_value, 15)
  );
end;
$$;

revoke all on function public.report_conversation(uuid, text, text, uuid)
  from public, anon;
grant execute on function public.report_conversation(uuid, text, text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. A fila da equipe
-- ---------------------------------------------------------------------------
--
-- Mesmo desenho de fetch_pending_verifications: cobra jurii_staff antes de
-- qualquer linha sair, devolve o nome das pessoas (id sozinho não vira
-- decisão) e entrega o conteúdo junto, para a ficha não exigir uma segunda
-- consulta por denúncia.
create or replace function public.fetch_open_reports()
returns table (
  id uuid,
  reason text,
  details text,
  status text,
  created_at timestamptz,
  reporter_profile_id uuid,
  reporter_name text,
  reported_name text,
  reported_is_firm boolean,
  conversation_id uuid,
  reported_message_id uuid,
  messages jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review reports';
  end if;

  return query
  select
    r.id,
    r.reason,
    r.details,
    r.status,
    r.created_at,
    -- O ID de quem denunciou vai junto porque a fotografia guarda o AUTOR de
    -- cada mensagem, e sem ele a tela precisaria adivinhar o lado pelo papel
    -- ('client' ou 'lawyer'). Adivinhar erra: quem denuncia tanto pode ser o
    -- cliente quanto o profissional, e num painel de moderação atribuir a
    -- fala à pessoa errada é o pior defeito possível.
    r.reporter_profile_id,
    coalesce(quem.full_name, 'Sem nome'),
    coalesce(alvo.full_name, firma.name, 'Sem nome'),
    r.law_firm_id is not null,
    r.conversation_id,
    r.message_id,
    r.message_snapshot
  from public.user_reports r
  left join public.profiles quem on quem.id = r.reporter_profile_id
  left join public.profiles alvo on alvo.id = r.reported_profile_id
  left join public.law_firms firma on firma.id = r.law_firm_id
  where r.status = 'open'
  -- A mais antiga primeiro: denúncia parada é a que precisa de decisão.
  order by r.created_at asc;
end;
$$;

revoke all on function public.fetch_open_reports() from public;
grant execute on function public.fetch_open_reports() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Decidir
-- ---------------------------------------------------------------------------
--
-- Duas saídas, as que a coluna `status` já previa desde o primeiro dia:
-- 'reviewed' (a denúncia procedia e foi tratada) e 'dismissed' (não
-- procedia). A NOTA é obrigatória nas duas, e não só na recusa, porque aqui
-- ela não vai para a pessoa denunciada: é a memória da equipe sobre por que
-- decidiu assim, e decisão de moderação sem motivo escrito é decisão que
-- ninguém consegue revisar depois.
create or replace function public.review_user_report(
  report_id_value uuid,
  decision_value text,
  note_value text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_note text;
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review reports';
  end if;

  if decision_value not in ('reviewed', 'dismissed') then
    raise exception 'Invalid report decision';
  end if;

  clean_note := nullif(btrim(left(
    regexp_replace(coalesce(note_value, ''), '[[:cntrl:]]+', ' ', 'g'),
    1000
  )), '');

  if clean_note is null then
    raise exception 'Review note is required';
  end if;

  update public.user_reports
  set
    status = decision_value,
    reviewer_id = (select auth.uid()),
    reviewed_at = now(),
    review_note = clean_note
  where id = report_id_value
    and status = 'open';

  if not found then
    raise exception 'Report not found or already reviewed';
  end if;
end;
$$;

revoke all on function public.review_user_report(uuid, text, text) from public;
grant execute on function public.review_user_report(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. O que já foi decidido
-- ---------------------------------------------------------------------------
--
-- Paginado pelo mesmo motivo do histórico de verificações: a fila esvazia
-- sozinha, o histórico não.
create or replace function public.fetch_reviewed_reports(
  limit_value int default 50,
  offset_value int default 0
)
returns table (
  id uuid,
  reason text,
  details text,
  status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  reviewer_name text,
  review_note text,
  reporter_profile_id uuid,
  reporter_name text,
  reported_name text,
  reported_is_firm boolean,
  conversation_id uuid,
  reported_message_id uuid,
  messages jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review reports';
  end if;

  return query
  select
    r.id,
    r.reason,
    r.details,
    r.status,
    r.created_at,
    r.reviewed_at,
    revisor.full_name,
    r.review_note,
    r.reporter_profile_id,
    coalesce(quem.full_name, 'Sem nome'),
    coalesce(alvo.full_name, firma.name, 'Sem nome'),
    r.law_firm_id is not null,
    r.conversation_id,
    r.message_id,
    r.message_snapshot
  from public.user_reports r
  left join public.profiles quem on quem.id = r.reporter_profile_id
  left join public.profiles alvo on alvo.id = r.reported_profile_id
  left join public.law_firms firma on firma.id = r.law_firm_id
  left join public.profiles revisor on revisor.id = r.reviewer_id
  where r.status in ('reviewed', 'dismissed')
  order by r.reviewed_at desc nulls last, r.created_at desc
  limit greatest(1, least(limit_value, 200))
  offset greatest(0, offset_value);
end;
$$;

revoke all on function public.fetch_reviewed_reports(int, int) from public;
grant execute on function public.fetch_reviewed_reports(int, int) to authenticated;

create or replace function public.count_reviewed_reports()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_jurii_staff() then
    raise exception 'Only Jurii staff can review reports';
  end if;

  return (
    select count(*)::integer
    from public.user_reports
    where status in ('reviewed', 'dismissed')
  );
end;
$$;

revoke all on function public.count_reviewed_reports() from public;
grant execute on function public.count_reviewed_reports() to authenticated;

notify pgrst, 'reload schema';
