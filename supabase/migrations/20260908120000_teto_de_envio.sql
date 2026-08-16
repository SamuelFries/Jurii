-- Enviar mensagem passa a ter teto.
--
-- O QUE JÁ EXISTIA: abrir conversa (20 por dia), pedir caso (30 por dia) e
-- convidar advogado (20 por hora). Todos na porta de ENTRADA de um
-- relacionamento.
--
-- O QUE NÃO EXISTIA: qualquer teto DEPOIS que a porta abriu. A política de
-- INSERT de `messages` confere identidade e acesso à conversa, e só. Ou seja,
-- abrir vinte conversas por dia era limitado, e despejar cem mil mensagens
-- dentro delas não era.
--
-- POR QUE ISSO IMPORTA AQUI mais do que num produto qualquer: o advogado
-- recebe cliente que ele não escolheu, de gente que ele não conhece, e o app
-- entrega a conversa na tela dele. Sem teto, a caixa de entrada de um advogado
-- é um alvo de graça.
--
-- DENUNCIAR JÁ TINHA TETO, e esta migration não mexe nele: `report_conversation`
-- limita a 10 por dia desde a 20260801120000. Vale dizer porque procurar por
-- "Too many" não encontra: aquela fala "Report limit reached", e a única coisa
-- que faltava lá era teste, que este arquivo passa a ter.
--
-- O QUE ESTE TETO NÃO É: moderação. Quem está sendo importunado por uma pessoa
-- de verdade tem o bloqueio (20260801120000), que resolve o caso dela na hora
-- e sem esperar limite nenhum. O teto aqui existe para o que o bloqueio não
-- alcança: script, automação, e a conta criada para incomodar em escala.

-- ---------------------------------------------------------------------------
-- 1. O índice que faz a conta caber no caminho quente
-- ---------------------------------------------------------------------------
--
-- `messages_sender_id_idx` já existia, mas só com sender_id: a contagem por
-- janela de tempo leria todas as mensagens da pessoa desde sempre para
-- descartar quase todas. Com created_at junto, a leitura para no fim da
-- janela.
--
-- DESC porque a consulta sempre olha o passado recente, e é de lá que ela
-- começa.
create index if not exists messages_sender_recentes_idx
  on public.messages (sender_id, created_at desc);

-- E o antigo SAI. Um índice de (sender_id) sozinho não responde nada que o de
-- (sender_id, created_at) não responda melhor: sender_id é o prefixo dele.
-- Manter os dois seria pagar duas escritas de índice por mensagem enviada, na
-- tabela mais quente do produto, para ter a mesma resposta duas vezes.
drop index if exists public.messages_sender_id_idx;

-- ---------------------------------------------------------------------------
-- 2. O teto de envio
-- ---------------------------------------------------------------------------
--
-- DUAS JANELAS, UMA VARREDURA. As duas contagens saem do mesmo índice na
-- mesma passada, com `filter`, porque isto roda a cada mensagem enviada e
-- pagar duas leituras seria pagar duas vezes no lugar mais quente do produto.
--
-- Os números:
--
--   30 por MINUTO. Ninguém digita trinta mensagens em um minuto; um script
--   digita trinta mil. É o teto que separa gente de automação, e ele é o que
--   realmente fecha a porta.
--
--   600 por HORA. Dez por minuto sustentados, muito acima de qualquer
--   conversa real, e é o que impede um script de contornar o primeiro teto
--   andando devagar. Sem ele, 29 por minuto para sempre daria 41 mil
--   mensagens por dia sem esbarrar em nada.
--
-- CONTA A MENSAGEM QUE EXISTE, e não a tentativa. Diferente do convite, que
-- tem tabela própria de tentativas porque lá a tentativa que falha também é
-- barulho. Aqui a mensagem recusada não chega a existir, e uma tabela de
-- tentativas custaria uma escrita a mais por mensagem enviada no produto
-- inteiro. O preço não paga o que ela compraria.
create or replace function public.limita_envio_de_mensagens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  no_minuto int;
  na_hora int;
begin
  -- Sem sessão não é gente enviando: é a nossa própria service_role, uma
  -- migration ou o seed. A política de INSERT já exige sender_id = auth.uid()
  -- para quem está logado, então este ramo não é uma saída para o cliente.
  if (select auth.uid()) is null then
    return new;
  end if;

  select
    count(*) filter (where m.created_at > now() - interval '1 minute'),
    count(*)
  into no_minuto, na_hora
  from public.messages m
  where m.sender_id = new.sender_id
    and m.created_at > now() - interval '1 hour';

  if no_minuto >= 30 or na_hora >= 600 then
    raise exception 'Too many messages. Try again later';
  end if;

  return new;
end;
$$;

drop trigger if exists messages_limita_envio on public.messages;
create trigger messages_limita_envio
  before insert on public.messages
  for each row
  execute function public.limita_envio_de_mensagens();

notify pgrst, 'reload schema';
