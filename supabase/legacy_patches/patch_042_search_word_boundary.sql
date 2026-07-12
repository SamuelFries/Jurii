-- Patch 042 — Precisão da inferência de área na busca (auditoria jul/2026).
--
-- Alinha a busca do servidor com o mirror local endurecido em
-- lib/data/legal_practice_areas.dart. Rode depois do patch_041.
--
-- Problema: public.legal_search_term_matches (patch_029) casava termo por
-- substring solta:
--     q like '%' || term || '%'   -- "iss" (imposto) casava em "dem*iss*ao"
--     term like '%' || q || '%'
-- Isso gerava falsos positivos de área — ex.: um relato puramente trabalhista
-- inferia Direito Tributário ("iss") e Cível ("nao ... pagaram"), poluindo as
-- recomendações de advogados/escritórios do fetch_recommended_*.
--
-- Correção (espelha _searchIntentTermMatches do Dart):
--   1. Casamento por LIMITE DE PALAVRA (padding com espaços), cobrindo termo de
--      uma palavra ("fgts") e frase inteira ("marido me bateu"), sem casar
--      sigla curta no meio de outra palavra.
--   2. Query de palavra única que é o começo de alguma palavra do termo
--      ("aposenta" -> "aposentadoria").
--   3. Frase cujos tokens significativos (>= 4 letras, antes >= 3) aparecem
--      todos como palavras da query — o piso de 4 evita palavras comuns curtas
--      ("nao", "com", "sem") virarem sinal.
-- Também remove o termo semeado 'das' (guia do MEI), que colidia com a
-- contração "das".
--
-- Só a função de matching muda; infer_legal_search_areas e fetch_recommended_*
-- continuam válidas (mesma assinatura) e mantêm o ranqueamento por weight
-- curado do patch_029 — o mirror local ordena por nº de termos que casaram, mas
-- ambos passam a compartilhar exatamente o mesmo critério de casamento.

create or replace function public.legal_search_term_matches(
  normalized_query text,
  normalized_term text
)
returns boolean
language sql
immutable
as $$
  with cleaned as (
    select
      nullif(trim(coalesce(normalized_query, '')), '') as q,
      nullif(trim(coalesce(normalized_term, '')), '') as term
  ),
  evaluated as (
    select
      -- 1) Termo presente respeitando limites de palavra. O padding com espaços
      --    transforma "contém como palavra/frase inteira" num LIKE simples,
      --    já que a normalização deixa só [a-z0-9] e espaços simples.
      (
        cleaned.q is not null
        and cleaned.term is not null
        and (' ' || cleaned.q || ' ') like ('% ' || cleaned.term || ' %')
      ) as whole_match,
      -- 2) Query de palavra única (sem espaço, >= 4 letras) que prefixa alguma
      --    palavra do termo.
      (
        cleaned.q is not null
        and cleaned.term is not null
        and position(' ' in cleaned.q) = 0
        and length(cleaned.q) >= 4
        and exists (
          select 1
          from regexp_split_to_table(cleaned.term, ' ') as term_token(tok)
          where term_token.tok like cleaned.q || '%'
        )
      ) as prefix_match,
      -- 3) Tokens significativos (>= 4 letras) do termo, todos presentes como
      --    palavras da query (mesmo fora de ordem).
      (
        cleaned.q is not null
        and cleaned.term is not null
        and (
          select count(*)
          from regexp_split_to_table(cleaned.term, ' ') as term_token(tok)
          where length(term_token.tok) >= 4
        ) >= 2
        and not exists (
          select 1
          from regexp_split_to_table(cleaned.term, ' ') as term_token(tok)
          where length(term_token.tok) >= 4
            and term_token.tok not in (
              select query_token.tok
              from regexp_split_to_table(cleaned.q, ' ') as query_token(tok)
            )
        )
      ) as token_subset_match
    from cleaned
  )
  select coalesce(
    whole_match or prefix_match or token_subset_match,
    false
  )
  from evaluated;
$$;

-- Remove o termo 'das' (guia do MEI): colide com a contração "das" ("fotos das
-- agressões") e gera falso positivo de Direito Tributário. Cobertura de MEI
-- segue por 'mei imposto' / 'simples nacional'. Espelha a remoção no mirror
-- local (lib/data/legal_practice_areas.dart).
delete from public.legal_search_intents
where normalized_phrase = 'das'
  and practice_area = 'Direito Tributário';

notify pgrst, 'reload schema';

-- Verificação pós-patch (rode e confira manualmente no SQL Editor):
--
--   -- 1) "demissão" NÃO deve inferir Tributário (era o bug do "iss").
--   select * from public.infer_legal_search_areas(
--     'minha demissao foi sem justa causa e nao recebi as verbas'
--   );
--   -- Esperado: Direito Trabalhista (e nada de Tributário/Cível).
--
--   -- 2) A contração "das" NÃO deve inferir Tributário.
--   select * from public.infer_legal_search_areas('guardei as fotos das conversas');
--   -- Esperado: sem Direito Tributário.
--
--   -- 3) Casos legítimos continuam funcionando.
--   select * from public.infer_legal_search_areas('meu marido me bateu');   -- Criminal
--   select * from public.infer_legal_search_areas('inss negou meu auxilio'); -- Previdenciário
--   select * from public.infer_legal_search_areas('fui demitido sem receber');-- Trabalhista
--
--   -- 4) O termo 'das' saiu da tabela.
--   select count(*) from public.legal_search_intents where normalized_phrase = 'das';
--   -- Esperado: 0.
