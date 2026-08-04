-- Encarece a fraude de avaliacao com conta-fantoche.
--
-- O EXPLOIT (reproduzido no banco local): um advogado aprovado abre uma conta
-- de CLIENTE fantoche, conversa consigo mesmo, propoe o caso pela conta de
-- advogado, aceita pela conta de cliente e se avalia 5 estrelas. A guarda
-- anti-autoavaliacao compara auth.uid() e nao pega, porque sao DUAS contas.
-- Custo por estrela falsa: um CPF valido e unico — algoritmo publico.
--
-- Nao existe barreira definitiva: quem controla os dois lados sempre consegue
-- forjar. O objetivo e ENCARECER e tornar o padrao detectavel, sem atrapalhar
-- o cliente real. Tres exigencias novas, todas naturais em atendimento
-- verdadeiro e caras de fabricar em escala:
--
--   1. CASO ENCERRADO, nao so aceito. Alinha com o produto: o convite de
--      avaliacao ('case_closed') ja e disparado no encerramento — o gate
--      passa a coincidir com o momento em que o app convida.
--   2. IDADE MINIMA de 24h do caso. Caso aberto e encerrado em minutos nao e
--      atendimento. Tira a fraude do instantaneo: cada estrela falsa passa a
--      custar um dia de espera.
--   3. CONVERSA COM OS DOIS LADOS. Pelo menos uma mensagem do cliente e uma
--      do profissional. Atendimento real sempre tem; fantoche precisa
--      encenar os dois papeis.
--
-- Deliberadamente NAO exigimos numero de processo nem duracao minima de
-- atendimento: consulta pontual resolvida numa conversa e caso legitimo.

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
  with reviewer as (select auth.uid() as id),
  -- Caso encerrado, com pelo menos 24h de vida, entre este cliente e o alvo.
  qualifying_case as (
    select lc.id
    from public.legal_cases lc, reviewer
    where lc.client_id = reviewer.id
      and lc.status = 'closed'
      and lc.created_at <= now() - interval '24 hours'
      and (
        (target_type_value = 'lawyer' and lc.assigned_lawyer_id = target_id_value)
        or (target_type_value = 'law_firm' and lc.law_firm_id = target_id_value)
      )
  ),
  -- Conversa com troca real: uma mensagem de cada lado.
  real_exchange as (
    select 1
    from public.conversations conv, reviewer
    where conv.client_id = reviewer.id
      and (
        (target_type_value = 'lawyer' and conv.lawyer_id = target_id_value)
        or (target_type_value = 'law_firm' and conv.law_firm_id = target_id_value)
      )
      and exists (
        select 1 from public.messages m
        where m.conversation_id = conv.id and m.sender_type = 'client'
      )
      and exists (
        select 1 from public.messages m
        where m.conversation_id = conv.id and m.sender_type = 'lawyer'
      )
  )
  select case
    when target_type_value not in ('lawyer', 'law_firm') then false
    -- Autoavaliacao direta (mesma conta) segue barrada, como antes.
    when target_type_value = 'lawyer'
      and target_id_value is not distinct from auth.uid() then false
    when target_type_value = 'law_firm' and exists (
      select 1 from public.law_firm_members lfm, reviewer
      where lfm.law_firm_id = target_id_value
        and lfm.profile_id = reviewer.id
        and lfm.status = 'active'
    ) then false
    else exists (select 1 from qualifying_case)
      and exists (select 1 from real_exchange)
  end;
$$;


-- A mensagem de recusa precisa contar a regra NOVA: quem lia "após ter um
-- caso aceito" ficava sem entender por que o botão não aparecia com um caso
-- aceito na mão. Corpo extraído verbatim; só a frase muda.

create or replace function public.submit_professional_review(target_type_value text, target_id_value uuid, rating_value integer, comment_value text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'Você pode avaliar depois que o caso for encerrado pelo profissional.'
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
$function$;

revoke all on function public.can_review_professional(text, uuid) from public, anon;
grant execute on function public.can_review_professional(text, uuid) to authenticated;

notify pgrst, 'reload schema';
