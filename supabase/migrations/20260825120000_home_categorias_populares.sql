-- Home do cliente: categorias na lingua do cliente, e os termos que elas
-- pescam.
--
-- Defeitos medidos em 2026-08-09, todos da mesma familia (fontes de verdade
-- discordando sobre onde um termo mora):
--
--   1. Tocar "Plano de Saude" filtrava Direito Medico e da Saude (1 advogado);
--      digitar "plano de saude" pescava Direito do Consumidor (4). O atalho
--      entregava MENOS que o teclado. Idem "Dividas e Banco".
--   2. "violencia domestica" pescava Direito Trabalhista, porque o termo
--      solto 'domestica' (de empregada domestica) morava la: 55 perfis
--      trabalhistas afogavam os 12 criminais na busca mais sensivel do app.
--   3. Buscas reais devolviam zero: "meu marido me bate" (so havia o passado
--      "me bateu"), "fui despedido" (so "demitido"), "fui roubado" (so "me
--      roubaram"), "estou sendo ameacado", "problema com loja",
--      "estou endividado".
--   4. O toque na categoria jogava a PALAVRA DO JURISTA na caixa de busca
--      ("Direito Civel" no lugar do titulo). Corrigido no app: o toque manda
--      o titulo; o banco precisa pescar cada titulo.
--
-- PARTE 1 ressemeia as cinco areas retocadas em legal_search_intents:
-- desativa todos os termos delas e reinsere a lista completa. Espelho exato
-- de legalSearchIntentRules (lib/data/legal_practice_areas.dart);
-- test/practice_areas_sync_test.dart compara os dois lados por area, com o
-- arquivo mais novo vencendo.
--
-- PARTE 2 troca as categorias da home: rotulo na lingua de quem tem o
-- problema (o toque manda o titulo para a busca), Plano de Saude sai (1
-- advogado e 2 escritorios, prateleira mais rala do app) e entra Crime ou
-- Agressao (Direito Criminal: 12 de oferta e porta nenhuma). Espelho de
-- lib/data/mock/mock_categories.dart; a barreira de que todo titulo pesca a
-- propria practice_area e test/categorias_populares_test.dart.

-- ---------------------------------------------------------------------------
-- 1. Termos de busca
-- ---------------------------------------------------------------------------

update public.legal_search_intents
set is_active = false
where practice_area in (
  'Direito Trabalhista',
  'Direito Criminal',
  'Direito do Consumidor',
  'Direito Bancário',
  'Direito Médico e da Saúde'
);

with seed (practice_areas, weight, terms) as (
  values
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
        'fui despedido',
        'fui despedida',
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
        'sou doméstica',
        'trabalho doméstico',
        'empregada doméstica',
        'diarista',
        'motorista de aplicativo',
        'entregador de aplicativo',
        'processo trabalhista',
        'reclamação trabalhista',
        'direito do trabalho',
        'advogado do trabalho',
        'direito processual do trabalho',
        'justiça do trabalho'
      ]::text[]
    ),
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
        'marido me bate',
        'me bate',
        'estou sendo ameaçado',
        'estou sendo ameaçada',
        'fui roubado',
        'fui roubada',
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
        'pornografia de vingança',
        'advogado penalista',
        'direito processual penal'
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
        'problema com loja',
        'problema com a loja',
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
        'golpe do pix',
        'direito consumerista'
      ]::text[]
    ),
    (
      array['Direito Bancário']::text[],
      110,
      array[
        'advogado bancário',
        'direito bancário',
        'contra o banco',
        'problema com banco',
        'dívida com o banco',
        'renegociar dívida',
        'empréstimo',
        'empréstimo consignado',
        'consignado indevido',
        'empréstimo que não fiz',
        'desconto no benefício',
        'desconto na aposentadoria',
        'juros abusivos',
        'ação revisional',
        'revisional de juros',
        'revisão de contrato bancário',
        'financiamento de veículo',
        'financiamento de carro',
        'busca e apreensão do carro',
        'alienação fiduciária',
        'cheque especial',
        'rotativo do cartão',
        'superendividamento',
        'endividado',
        'endividada',
        'estou endividado',
        'estou endividada',
        'tarifa bancária',
        'tarifas indevidas',
        'venda casada do banco',
        'seguro embutido no empréstimo',
        'consórcio não contemplado',
        'carta de crédito',
        'penhora na conta',
        'bloqueio judicial da conta',
        'banco negou empréstimo',
        'contrato bancário',
        'banco',
        'dívida',
        'dívidas'
      ]::text[]
    ),
    (
      array['Direito Médico e da Saúde']::text[],
      110,
      array[
        'advogado médico',
        'direito médico',
        'direito da saúde',
        'direito à saúde',
        'erro médico',
        'erro cirúrgico',
        'erro de diagnóstico',
        'negligência médica',
        'imperícia médica',
        'imprudência médica',
        'cirurgia deu errado',
        'sequela de cirurgia',
        'infecção hospitalar',
        'morte no hospital',
        'hospital',
        'médico',
        'crm',
        'conselho de medicina',
        'processo no crm',
        'plano de saúde',
        'convênio médico',
        'plano negou cirurgia',
        'plano negou tratamento',
        'plano negou exame',
        'cirurgia negada',
        'tratamento negado',
        'plano de saúde negou',
        'negativa de cobertura',
        'medicamento negado',
        'remédio de alto custo',
        'sus negou',
        'fila do sus',
        'liminar para cirurgia',
        'liminar para remédio',
        'internação negada',
        'uti negada',
        'home care',
        'tratamento fora de domicílio',
        'exame negado',
        'reajuste do plano de saúde',
        'plano de saúde cancelado',
        'carência do plano',
        'prontuário médico',
        'consentimento informado',
        'erro odontológico',
        'cirurgia plástica deu errado',
        'tratamento negado pelo plano'
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
  weight = excluded.weight,
  is_active = true;

-- ---------------------------------------------------------------------------
-- 2. Categorias da home
--
-- Ids antigos ficam onde so o rotulo muda (a FK de law_firm_categories e
-- on delete restrict). Id novo so para o cartao novo.
-- ---------------------------------------------------------------------------

insert into public.legal_categories
  (id, title, icon_name, practice_area, is_highlighted, sort_order)
values
  ('trabalhista', 'Trabalhista', 'work_outline',
   'Direito Trabalhista', false, 10),
  ('previdenciario', 'INSS e Aposentadoria', 'elderly_outlined',
   'Direito Previdenciário', false, 20),
  ('divorcio-familia', 'Divórcio e Pensão', 'family_restroom',
   'Direito de Família', false, 30),
  ('acidente-transito', 'Acidente e Indenização', 'directions_car_outlined',
   'Direito Cível', false, 40),
  ('consumidor', 'Consumidor', 'shopping_bag_outlined',
   'Direito do Consumidor', false, 50),
  ('dividas-e-banco', 'Dívidas e Banco', 'account_balance_outlined',
   'Direito Bancário', false, 60),
  ('imobiliario', 'Aluguel e Imóvel', 'home_outlined',
   'Direito Imobiliário', false, 70),
  ('inventario-heranca', 'Inventário e Herança', 'balance_outlined',
   'Direito das Sucessões', false, 80),
  ('crime-agressao', 'Crime ou Agressão', 'shield_outlined',
   'Direito Criminal', false, 90)
on conflict (id) do update set
  title = excluded.title,
  icon_name = excluded.icon_name,
  practice_area = excluded.practice_area,
  sort_order = excluded.sort_order;

-- Plano de Saude sai: prateleira mais rala do app (1 advogado, 2
-- escritorios) e o titulo digitado ja alcanca mais que o cartao alcancava.
-- A grade e 3x3: uma decima linha viraria cartao orfao numa quarta fileira.
delete from public.law_firm_categories where category_id = 'plano-de-saude';
delete from public.legal_categories where id = 'plano-de-saude';

notify pgrst, 'reload schema';
