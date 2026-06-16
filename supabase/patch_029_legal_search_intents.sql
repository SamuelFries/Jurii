-- Adds intent-based legal search on top of practice-area tags.
--
-- Run after patch_028. It lets the client search describe a problem in plain
-- language, such as "Maria da Penha" or "estupro", and still match lawyers
-- and firms tagged as Direito Criminal.

create table if not exists public.legal_search_intents (
  id uuid primary key default gen_random_uuid(),
  phrase text not null,
  normalized_phrase text not null,
  practice_area text not null,
  related_tags text[] not null default '{}'::text[],
  weight int not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (normalized_phrase, practice_area)
);

create index if not exists legal_search_intents_normalized_phrase_idx
on public.legal_search_intents(normalized_phrase);

create index if not exists legal_search_intents_practice_area_idx
on public.legal_search_intents(practice_area);

alter table public.legal_search_intents enable row level security;

drop policy if exists "legal_search_intents_read_active"
on public.legal_search_intents;

create policy "legal_search_intents_read_active"
on public.legal_search_intents for select
to authenticated
using (is_active = true);

create or replace function public.normalize_practice_area_search(value text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(
    regexp_replace(
      translate(
        lower(trim(coalesce(value, ''))),
        'áàâãéêíóôõúüç',
        'aaaaeeiooouuc'
      ),
      '[^a-z0-9]+',
      ' ',
      'g'
    ),
    '[[:space:]]+',
    ' ',
    'g'
  ));
$$;

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
  query_tokens as (
    select query_token.token
    from cleaned,
      regexp_split_to_table(cleaned.q, ' ') as query_token(token)
    where length(query_token.token) >= 3
  ),
  term_tokens as (
    select term_token.token
    from cleaned,
      regexp_split_to_table(cleaned.term, ' ') as term_token(token)
    where length(term_token.token) >= 3
  ),
  term_count as (
    select count(*) as total
    from term_tokens
  )
  select coalesce(
    cleaned.q like '%' || cleaned.term || '%'
    or cleaned.term like '%' || cleaned.q || '%'
    or (
      (select total from term_count) >= 2
      and not exists (
        select 1
        from term_tokens
        where not exists (
          select 1
          from query_tokens
          where query_tokens.token = term_tokens.token
        )
      )
    ),
    false
  )
  from cleaned;
$$;

with seed(practice_areas, weight, terms) as (
  values
    (
      array['Direito Criminal']::text[],
      130,
      array[
        'advogado criminal',
        'advogado criminalista',
        'direito penal',
        'processo criminal',
        'processo penal',
        'acusado',
        'acusação',
        'acusaram',
        'réu',
        'réu primário',
        'vítima de crime',
        'crime',
        'crime grave',
        'denúncia criminal',
        'queixa crime',
        'Maria da Penha',
        'Lei Maria da Penha',
        'violência doméstica',
        'violência contra mulher',
        'violência contra a mulher',
        'violência familiar',
        'mulher agredida',
        'apanhei do marido',
        'marido bateu',
        'marido me bateu',
        'meu marido me bateu',
        'namorado me bateu',
        'ex me bateu',
        'ex me ameaça',
        'ex me ameaçou',
        'meu ex me persegue',
        'perseguição',
        'stalking',
        'medida protetiva',
        'descumpriu medida protetiva',
        'quebrou medida protetiva',
        'estupro',
        'estupro de vulnerável',
        'abuso sexual',
        'assédio sexual',
        'importunação sexual',
        'crime sexual',
        'violência sexual',
        'toque sem consentimento',
        'fui abusada',
        'fui abusado',
        'ameaça',
        'ameaçaram',
        'fui ameaçado',
        'fui ameaçada',
        'ameaça pelo whatsapp',
        'agressão',
        'agressão física',
        'fui agredido',
        'fui agredida',
        'me bateram',
        'lesão corporal',
        'homicídio',
        'tentativa de homicídio',
        'briga',
        'briga de rua',
        'roubo',
        'furto',
        'assalto',
        'fui assaltado',
        'fui assaltada',
        'me roubaram',
        'roubaram meu celular',
        'invadiram minha casa',
        'arrombamento',
        'receptação',
        'estelionato',
        'golpe',
        'caí em golpe',
        'fraude',
        'extorsão',
        'chantagem',
        'sequestro',
        'cárcere privado',
        'prisão',
        'preso',
        'foi preso',
        'prenderam',
        'flagrante',
        'prisão em flagrante',
        'audiência de custódia',
        'habeas corpus',
        'fiança',
        'tornozeleira eletrônica',
        'regime aberto',
        'regime semiaberto',
        'execução penal',
        'delegacia',
        'intimação policial',
        'depoimento na delegacia',
        'inquérito policial',
        'boletim de ocorrência',
        'b o',
        'fazer boletim',
        'trafico de drogas',
        'tráfico de drogas',
        'porte de droga',
        'porte de maconha',
        'drogas',
        'lei seca',
        'embriaguez ao volante',
        'calúnia',
        'injúria',
        'difamação',
        'falsa acusação',
        'nudes vazados',
        'vazaram nudes',
        'pornografia de vingança'
      ]::text[]
    ),
    (
      array['Direito de Família']::text[],
      125,
      array[
        'advogado de família',
        'direito de família',
        'divórcio',
        'divorciar',
        'quero divorciar',
        'quero me separar',
        'separação',
        'separação amigável',
        'separação litigiosa',
        'divórcio amigável',
        'divórcio litigioso',
        'fim do casamento',
        'casamento acabou',
        'pensão alimentícia',
        'pensão',
        'pensão atrasada',
        'não paga pensão',
        'não pagou pensão',
        'pai não paga pensão',
        'mãe não paga pensão',
        'aumentar pensão',
        'diminuir pensão',
        'revisão de pensão',
        'execução de alimentos',
        'alimentos',
        'alimentos gravídicos',
        'guarda',
        'guarda compartilhada',
        'guarda unilateral',
        'guarda dos filhos',
        'pegar guarda',
        'perder guarda',
        'visitas',
        'direito de visita',
        'regulamentação de visitas',
        'mãe não deixa ver filho',
        'pai não deixa ver filho',
        'não consigo ver meu filho',
        'união estável',
        'dissolução de união estável',
        'contrato de união estável',
        'alienação parental',
        'partilha',
        'partilha de bens',
        'dividir bens',
        'bens do casal',
        'regime de bens',
        'pacto antenupcial',
        'paternidade',
        'reconhecimento de paternidade',
        'exame de dna',
        'dna',
        'nome do pai',
        'adoção',
        'adotar',
        'tutela',
        'curatela',
        'interdição familiar',
        'inventário familiar',
        'herança de família',
        'briga de herança',
        'testamento da família'
      ]::text[]
    ),
    (
      array['Direito Trabalhista']::text[],
      120,
      array[
        'advogado trabalhista',
        'direito trabalhista',
        'trabalho',
        'emprego',
        'patrão',
        'empresa não pagou',
        'patrão não pagou',
        'chefe',
        'demissão',
        'fui demitido',
        'fui demitida',
        'me mandaram embora',
        'mandaram embora',
        'demitido sem receber',
        'demitida sem receber',
        'não recebi acerto',
        'acerto trabalhista',
        'acordo trabalhista',
        'rescisão',
        'rescisão trabalhista',
        'fgts',
        'fgts atrasado',
        'fgts não depositado',
        'não depositaram fgts',
        'horas extras',
        'hora extra',
        'banco de horas',
        'jornada de trabalho',
        'intervalo',
        'não tenho intervalo',
        'trabalho demais',
        'assédio moral',
        'humilhação no trabalho',
        'chefe humilha',
        'chefe grita',
        'perseguição no trabalho',
        'assédio sexual no trabalho',
        'chefe me assedia',
        'salário atrasado',
        'salário não pago',
        'pagamento atrasado',
        'décimo terceiro',
        '13 atrasado',
        'férias',
        'férias vencidas',
        'férias não pagas',
        'verbas rescisórias',
        'justa causa',
        'demissão por justa causa',
        'reverter justa causa',
        'carteira assinada',
        'trabalho sem carteira',
        'não assinaram carteira',
        'vínculo empregatício',
        'pejotização',
        'mei obrigado',
        'sou mei mas sou empregado',
        'autônomo mas empregado',
        'desvio de função',
        'acúmulo de função',
        'equiparação salarial',
        'adicional noturno',
        'periculosidade',
        'insalubridade',
        'acidente de trabalho',
        'doença ocupacional',
        'estabilidade gestante',
        'licença maternidade',
        'cipa',
        'sindicato',
        'doméstica',
        'empregada doméstica',
        'diarista',
        'motorista de aplicativo',
        'entregador de aplicativo',
        'processo trabalhista',
        'reclamação trabalhista'
      ]::text[]
    ),
    (
      array['Direito do Consumidor']::text[],
      115,
      array[
        'advogado consumidor',
        'direito do consumidor',
        'procon',
        'juizado consumidor',
        'pequenas causas consumidor',
        'produto defeituoso',
        'produto com defeito',
        'produto quebrado',
        'comprei e não chegou',
        'compra não chegou',
        'pedido não chegou',
        'loja não entregou',
        'atraso na entrega',
        'loja não troca',
        'troca negada',
        'garantia',
        'garantia negada',
        'cobrança indevida',
        'cobraram errado',
        'boleto indevido',
        'fatura errada',
        'cobrança abusiva',
        'juros abusivos',
        'nome sujo',
        'negativação',
        'negativação indevida',
        'serasa',
        'spc',
        'protesto indevido',
        'cartão de crédito',
        'cartão clonado',
        'plano de saúde',
        'convênio médico',
        'plano negou cirurgia',
        'plano negou tratamento',
        'plano negou exame',
        'cirurgia negada',
        'tratamento negado',
        'banco',
        'banco bloqueou conta',
        'conta bloqueada',
        'empréstimo não contratado',
        'empréstimo consignado',
        'desconto indevido',
        'financiamento',
        'consórcio',
        'seguro',
        'seguradora não paga',
        'viagem cancelada',
        'passagem cancelada',
        'voo cancelado',
        'voo atrasado',
        'bagagem extraviada',
        'overbooking',
        'hotel cancelado',
        'mensalidade',
        'faculdade',
        'escola',
        'curso online',
        'assinatura',
        'cancelar assinatura',
        'cobrança de assinatura',
        'telefone',
        'internet',
        'operadora',
        'energia elétrica',
        'conta de luz',
        'água',
        'conta de água',
        'marketplace',
        'app de entrega',
        'compra online',
        'propaganda enganosa',
        'fraude bancária',
        'pix errado',
        'golpe do pix'
      ]::text[]
    ),
    (
      array['Direito Previdenciário']::text[],
      115,
      array[
        'advogado previdenciário',
        'direito previdenciário',
        'previdência',
        'inss',
        'meu inss',
        'aposentadoria',
        'aposentadoria negada',
        'aposentar',
        'aposentadoria por idade',
        'aposentadoria por tempo',
        'aposentadoria especial',
        'tempo de contribuição',
        'revisão da aposentadoria',
        'revisão da vida toda',
        'auxílio doença',
        'auxílio por incapacidade',
        'benefício por incapacidade',
        'bpc',
        'loas',
        'benefício negado',
        'benefício cortado',
        'meu benefício foi cortado',
        'pente fino',
        'perícia',
        'perícia negada',
        'perícia médica',
        'laudo médico',
        'incapacidade',
        'auxílio acidente',
        'pensão por morte',
        'salário maternidade',
        'salario maternidade',
        'recurso inss',
        'indeferido inss',
        'pedido indeferido',
        'cnis',
        'contribuição não aparece',
        'tempo rural',
        'trabalhador rural',
        'segurado especial',
        'ppp',
        'insalubridade inss',
        'aposentadoria rural',
        'deficiente',
        'idoso bpc',
        'aposentadoria pessoa com deficiência'
      ]::text[]
    ),
    (
      array['Direito Imobiliário']::text[],
      110,
      array[
        'advogado imobiliário',
        'direito imobiliário',
        'imóvel',
        'casa',
        'apartamento',
        'terreno',
        'lote',
        'aluguel',
        'aluguel atrasado',
        'contrato de aluguel',
        'despejo',
        'ordem de despejo',
        'ação de despejo',
        'inquilino não paga',
        'inquilino não sai',
        'proprietário',
        'locador',
        'locatário',
        'condomínio',
        'taxa de condomínio',
        'síndico',
        'locação',
        'compra de imóvel',
        'venda de imóvel',
        'escritura',
        'registro de imóvel',
        'matrícula do imóvel',
        'regularizar imóvel',
        'habite-se',
        'usucapião',
        'posse',
        'posse de terreno',
        'invasão de terreno',
        'invasão de imóvel',
        'construtora',
        'obra atrasada',
        'atraso na obra',
        'imóvel na planta',
        'distrato imobiliário',
        'financiamento imobiliário',
        'financiamento caixa',
        'corretor',
        'comissão de corretagem',
        'caução',
        'fiador',
        'vistoria',
        'infiltração',
        'vício construtivo',
        'reforma',
        'vizinho barulhento',
        'barulho de vizinho'
      ]::text[]
    ),
    (
      array['Acidente de Trânsito']::text[],
      110,
      array[
        'advogado de trânsito',
        'direito de trânsito',
        'acidente de trânsito',
        'batida',
        'bati o carro',
        'bateram no meu carro',
        'bateram na minha moto',
        'colisão',
        'engavetamento',
        'acidente de carro',
        'acidente de moto',
        'acidente de ônibus',
        'acidente com uber',
        'acidente aplicativo',
        'atropelamento',
        'fui atropelado',
        'fui atropelada',
        'trânsito',
        'seguradora',
        'seguro do carro',
        'seguro não pagou',
        'indenização acidente',
        'danos no carro',
        'conserto do carro',
        'perda total',
        'dpvat',
        'boletim de acidente',
        'culpa no acidente',
        'motorista bêbado',
        'multa de trânsito',
        'multa de transito',
        'cnh suspensa',
        'cnh cassada',
        'pontos na carteira',
        'bafômetro',
        'recusei bafômetro',
        'lei seca',
        'carro apreendido',
        'guincho',
        'licenciamento',
        'recurso de multa'
      ]::text[]
    ),
    (
      array['Direito Empresarial']::text[],
      105,
      array[
        'advogado empresarial',
        'direito empresarial',
        'empresa',
        'abrir empresa',
        'fechar empresa',
        'cnpj',
        'contrato social',
        'alteração contrato social',
        'alterar contrato social',
        'sócio',
        'sócios',
        'briga de sócios',
        'briga com sócio',
        'tirar sócio',
        'retirada de sócio',
        'entrada de sócio',
        'sociedade',
        'dissolução de sociedade',
        'acordo de sócios',
        'quotas',
        'ltda',
        'mei',
        'microempresa',
        'holding',
        'startup',
        'franquia',
        'contrato empresarial',
        'fornecedor',
        'cliente não pagou empresa',
        'cobrança empresarial',
        'recuperação judicial',
        'falência',
        'marca',
        'registro de marca',
        'pro labore',
        'compliance',
        'licitação',
        'contrato de prestação de serviço',
        'contrato com fornecedor',
        'contrato de parceria',
        'distribuição',
        'representação comercial'
      ]::text[]
    ),
    (
      array['Direito Tributário']::text[],
      105,
      array[
        'advogado tributário',
        'direito tributário',
        'imposto',
        'impostos',
        'tributo',
        'tributos',
        'dívida ativa',
        'execução fiscal',
        'cobrança da prefeitura',
        'cobrança do estado',
        'cobrança da receita',
        'iptu',
        'ipva',
        'icms',
        'iss',
        'irpf',
        'irpj',
        'imposto de renda',
        'receita federal',
        'malha fina',
        'simples nacional',
        'mei imposto',
        'pis',
        'cofins',
        'darf',
        'das',
        'parcelamento fiscal',
        'multa fiscal',
        'autuação fiscal',
        'fiscalização',
        'nota fiscal',
        'sonegação',
        'cnd',
        'certidão negativa',
        'recuperar imposto',
        'restituição',
        'taxa',
        'itcmd',
        'itbi',
        'protesto da prefeitura',
        'regularizar imposto'
      ]::text[]
    ),
    (
      array['Direito Cível']::text[],
      105,
      array[
        'advogado cível',
        'direito civil',
        'processo civil',
        'juizado especial',
        'pequenas causas',
        'indenização',
        'danos morais',
        'dano moral',
        'danos materiais',
        'dano material',
        'cobrança',
        'cobrar dívida',
        'alguém me deve',
        'me devem dinheiro',
        'calote',
        'levei calote',
        'emprestei dinheiro',
        'não me pagaram',
        'contrato',
        'quebra de contrato',
        'descumprimento de contrato',
        'rescisão de contrato',
        'responsabilidade civil',
        'erro médico',
        'erro odontológico',
        'acidente em loja',
        'queda em estabelecimento',
        'queda no mercado',
        'herança',
        'inventário',
        'testamento',
        'partilha de herança',
        'briga de herança',
        'registro civil',
        'alterar nome',
        'alteração de nome',
        'retificar documento',
        'retificação de registro',
        'interdição',
        'curatela',
        'vizinho',
        'briga com vizinho',
        'barulho de vizinho',
        'direito de imagem',
        'uso indevido de imagem',
        'calúnia',
        'injúria',
        'difamação',
        'cobrança judicial',
        'notificação extrajudicial',
        'contrato de compra e venda',
        'contrato de prestação de serviço'
      ]::text[]
    ),
    (
      array['Direito Digital']::text[],
      115,
      array[
        'advogado digital',
        'direito digital',
        'crime virtual',
        'crime na internet',
        'internet',
        'rede social',
        'lgpd',
        'vazamento de dados',
        'dados vazados',
        'privacidade',
        'proteção de dados',
        'perfil hackeado',
        'conta hackeada',
        'instagram hackeado',
        'facebook hackeado',
        'whatsapp clonado',
        'clonaram whatsapp',
        'conta invadida',
        'golpe do pix',
        'pix',
        'pix errado',
        'fraude online',
        'golpe online',
        'loja falsa',
        'site falso',
        'cyberbullying',
        'nudes vazados',
        'vazaram nudes',
        'fotos vazadas',
        'vídeo vazado',
        'pornografia de vingança',
        'difamação na internet',
        'post ofensivo',
        'comentário ofensivo',
        'fake news',
        'deepfake',
        'remover conteúdo',
        'tirar conteúdo do ar',
        'remover foto',
        'remover vídeo',
        'uso indevido de imagem',
        'direito autoral',
        'plágio',
        'software',
        'contrato de software',
        'aplicativo',
        'termos de uso',
        'e-commerce'
      ]::text[]
    )
),
expanded_terms as (
  select
    areas.practice_area,
    terms.phrase,
    public.normalize_practice_area_search(terms.phrase) as normalized_phrase,
    seed.weight
  from seed
  cross join unnest(seed.practice_areas) as areas(practice_area)
  cross join unnest(seed.terms) as terms(phrase)
  where nullif(trim(terms.phrase), '') is not null
),
deduplicated_terms as (
  select
    expanded_terms.practice_area,
    expanded_terms.normalized_phrase,
    min(expanded_terms.phrase) as phrase,
    max(expanded_terms.weight) as weight
  from expanded_terms
  where expanded_terms.normalized_phrase <> ''
  group by
    expanded_terms.practice_area,
    expanded_terms.normalized_phrase
)
insert into public.legal_search_intents (
  phrase,
  normalized_phrase,
  practice_area,
  related_tags,
  weight
)
select
  deduplicated_terms.phrase,
  deduplicated_terms.normalized_phrase,
  deduplicated_terms.practice_area,
  '{}'::text[],
  deduplicated_terms.weight
from deduplicated_terms
on conflict (normalized_phrase, practice_area) do update
set
  phrase = excluded.phrase,
  related_tags = excluded.related_tags,
  weight = greatest(public.legal_search_intents.weight, excluded.weight),
  is_active = true;

create or replace function public.infer_legal_search_areas(search_value text)
returns table (
  practice_area text,
  weight int
)
language sql
stable
security definer
set search_path = public
as $$
  with search as (
    select nullif(public.normalize_practice_area_search(search_value), '') as q
  ),
  matches as (
    select
      lsi.practice_area,
      max(lsi.weight) as weight
    from public.legal_search_intents lsi
    cross join search
    where lsi.is_active = true
      and search.q is not null
      and length(search.q) >= 3
      and (
        public.legal_search_term_matches(search.q, lsi.normalized_phrase)
        or exists (
          select 1
          from unnest(lsi.related_tags) as tags(tag_value)
          where public.legal_search_term_matches(
            search.q,
            public.normalize_practice_area_search(tags.tag_value)
          )
        )
      )
    group by lsi.practice_area
  )
  select matches.practice_area, matches.weight
  from matches
  order by matches.weight desc, matches.practice_area;
$$;

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
      4.8::numeric as rating,
      0::int as reviews_count,
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

create or replace function public.fetch_recommended_law_firms(
  limit_value int default 10,
  search_value text default null
)
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
  address text
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
      lf.id,
      lf.name,
      lf.initials,
      lf.rating,
      lf.distance_label,
      lf.specialty,
      case
        when cardinality(lf.practice_areas) > 0 then lf.practice_areas
        else array[lf.specialty]
      end as practice_areas,
      lf.reviews_count,
      lf.avatar_type,
      lf.description,
      lf.phone,
      lf.email,
      lf.website_url,
      lf.address,
      lf.created_at
    from public.law_firms lf
    where lf.is_active = true
  ),
  ranked as (
    select
      base.*,
      coalesce(
        public.normalize_practice_area_search(base.name)
          like '%' || search.q || '%'
        or public.normalize_practice_area_search(base.specialty)
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
        where public.normalize_practice_area_search(base.specialty) =
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
    ranked.name,
    ranked.initials,
    ranked.rating,
    ranked.distance_label,
    ranked.specialty,
    ranked.practice_areas,
    ranked.reviews_count,
    ranked.avatar_type,
    ranked.description,
    ranked.phone,
    ranked.email,
    ranked.website_url,
    ranked.address
  from ranked
  cross join search
  where search.q is null
    or ranked.direct_match
    or ranked.intent_weight > 0
  order by
    ranked.intent_weight desc,
    ranked.direct_match desc,
    ranked.rating desc,
    ranked.created_at desc
  limit least(greatest(coalesce(limit_value, 10), 1), 30);
$$;

revoke all on function public.normalize_practice_area_search(text)
from public, anon, authenticated;

revoke all on function public.legal_search_term_matches(text, text)
from public, anon, authenticated;

revoke all on function public.infer_legal_search_areas(text)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_lawyers(int, text)
from public, anon, authenticated;

revoke all on function public.fetch_recommended_law_firms(int, text)
from public, anon, authenticated;

grant select on public.legal_search_intents to authenticated;

grant execute on function public.infer_legal_search_areas(text)
to authenticated;

grant execute on function public.fetch_recommended_lawyers(int, text)
to authenticated;

grant execute on function public.fetch_recommended_law_firms(int, text)
to authenticated;

notify pgrst, 'reload schema';
