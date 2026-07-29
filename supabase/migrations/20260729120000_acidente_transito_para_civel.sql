-- Categoria popular "Acidente de Trânsito" passa a filtrar por Direito Cível
--
-- Ninguém se cadastra como "Acidente de Trânsito": não é uma especializacao
-- real da advocacia, e quem atende esse tipo de caso se autoclassifica como
-- Direito Cível (responsabilidade civil/indenizacao) no cadastro. Resultado:
-- a categoria popular nunca retornava nenhum advogado/escritorio, para
-- ninguem, sempre — nao por falta de profissionais, mas porque a busca
-- procurava um rotulo que nenhum cadastro usa.
--
-- Fix: o rotulo que o cliente ve continua "Acidente de Trânsito" (id/title
-- da categoria inalterados); só a área que o tap aplica como filtro muda
-- para "Direito Cível". "Acidente de Trânsito" também deixa de ser uma opção
-- selecionável no cadastro de advogado/escritorio (lib/data/legal_practice_
-- areas.dart) — confirmado (28/07) que nenhum profissional a tinha marcada,
-- entao nao ha dado a migrar.
--
-- legal_search_intents é o espelho server-side dos termos de busca livre
-- (ex.: cliente digita "bati o carro" na busca) usado por
-- fetch_recommended_lawyers/fetch_recommended_law_firms — sem este update,
-- o mesmo bug reapareceria por essa porta mesmo com a categoria corrigida.

update public.legal_categories
set practice_area = 'Direito Cível'
where id = 'acidente-transito';

update public.legal_search_intents
set practice_area = 'Direito Cível'
where practice_area = 'Acidente de Trânsito';

notify pgrst, 'reload schema';
