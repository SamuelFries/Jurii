-- Coordenada dos escritorios que tinham CEP e nao tinham coordenada.
--
-- CAUSA: a geocodificacao do app usava so a BrasilAPI v2, e o campo
-- `location.coordinates` dela vem VAZIO. Medido em 06/08/2026: 10 de 10 CEPs
-- testados voltaram coordinates:{} (provider "open-cep"). Ou seja, a
-- geocodificacao NUNCA resolvia — e por isso 39 dos 40 escritorios tinham CEP
-- e endereco gravados e nenhuma coordenada, e o cartao deles aparecia sem
-- distancia na descoberta.
--
-- O app foi corrigido com uma cascata de fontes (lib/services/cep_service.dart:
-- BrasilAPI para o endereco, AwesomeAPI por CEP, Nominatim por endereco
-- estruturado). Mas o conserto do codigo so alcanca quem editar o cadastro
-- depois — e pedir a 39 escritorios que reabram o cadastro so para gravar de
-- novo seria empurrar para o usuario um conserto que e nosso.
--
-- Entao os valores vem literais. Foram resolvidos pela MESMA cascata do app,
-- rodada uma vez sobre os CEPs ja gravados: 38 pela awesomeapi, 1 pela brasilapi.
-- 39 de 39 resolveram.
--
-- SO PREENCHE O QUE ESTA VAZIO (`where latitude is null`): se alguem gravar a
-- coordenada antes desta migration rodar, o valor dele vale mais que o daqui.

update public.law_firms firm
set latitude = origem.latitude,
    longitude = origem.longitude,
    updated_at = now()
from (values
  ('05fbe066-c6c9-4456-8953-0dd12231af57'::uuid, -29.947102, -51.092321),  -- 94910000 Antonio Pereira Advocacia & Consultoria
  ('8f502bec-0bb3-448b-955b-f85702fbf0ab'::uuid, -29.165863, -51.180106),  -- 95020190 Borghetti & Von Brock Advogados Associados
  ('1c96707f-f12d-4e28-97b7-0e0ebc4110a0'::uuid, -29.763889, -57.084694),  -- 97502748 Brites Gomes e Leonetti Advogados Associados
  ('3bfbea84-8642-4a08-b4c7-c1a0b1714a73'::uuid, -29.827888, -51.163835),  -- 93210000 Cabral & Zottis Advogados
  ('2c78d28f-7b23-41b6-9766-bd2492a65732'::uuid, -31.767285, -52.339166),  -- 96010000 Cássia Menegaz Advocacia
  ('b7d75212-aeed-482d-abd2-687712960041'::uuid, -29.717256, -52.430144),  -- 96810156 Cleberson Rodrigues Advocacia
  ('d5f831c5-0640-461b-9131-f412dea605d1'::uuid, -32.035587, -52.091067),  -- 96200150 Concli Advogados Associados
  ('5ee79451-13c4-4420-ba61-2d41bd85a573'::uuid, -30.000186, -51.083912),  -- 94810390 Corrêa & Tolksdorf Advocacia
  ('f86d8656-e01d-44b3-8640-9cad4c551626'::uuid, -30.041132, -51.228504),  -- 90020022 Crespo Advogados
  ('a51fe170-3400-4229-b713-9e9b8eb27499'::uuid, -29.171446, -51.182704),  -- 95080190 Dalla Corte e Losso Advogados Associados
  ('560b5abc-1213-45b3-ba3e-5f912cd7e242'::uuid, -30.083002, -51.026219),  -- 94410000 Dettenborn e Juchem Advocacia
  ('61d39792-89d1-4795-887c-6f26a79fd3ef'::uuid, -29.703468, -51.123435),  -- 93415000 DROB Advogados Associados
  ('5e717721-43d0-49af-b56f-f4c671a6f8eb'::uuid, -29.703468, -51.123435),  -- 93415000 Fábio Costa Advocacia
  ('821203ce-1254-4b25-bc5d-d3c6418bc999'::uuid, -29.163770, -51.176035),  -- 95020360 Freitas & Agostini Advogados Associados
  ('358af0f0-ad46-4345-bf67-d7b68f8aa3b3'::uuid, -29.920260, -51.179763),  -- 92010240 Fróes Advocacia
  ('05dc01df-50d2-44dd-8b1b-e1803f02afde'::uuid, -30.041132, -51.228504),  -- 90020022 Henrique Miraflores Sociedade Individual de 
  ('afb1f262-621f-486a-a522-4b4de90f6d8c'::uuid, -29.764890, -51.144306),  -- 93010190 Herzer & Santos Advogados Associados
  ('765d2e85-56d8-494e-a12c-5df3e86c14c5'::uuid, -29.681583, -53.808417),  -- 97010422 Isaia & Gasparetto Advogados
  ('37969565-2292-4574-b575-87dba3301507'::uuid, -29.682592, -51.130688),  -- 93510130 José Luis Hartmann Filho Sociedade Individua
  ('780dcb57-5ea5-47d9-9036-905919b0d21d'::uuid, -29.717256, -52.430144),  -- 96810156 M. Santos Advogados
  ('c82d7788-c108-43f4-a11e-cff45b08a712'::uuid, -29.167871, -51.183096),  -- 95010003 Mambrini & Fabris Sociedade de Advogados
  ('261505e2-53f4-4e28-983a-6e677ac8503d'::uuid, -30.022848, -51.202643),  -- 90570010 Milano Dutra e Bossle Advogados
  ('7d0775e8-9b1a-422a-b184-00053abef8c9'::uuid, -29.925945, -51.037062),  -- 94130000 Mônego & Alves Advogados Associados
  ('e146e130-b9e8-4ec2-88e7-35e44b7ea874'::uuid, -28.253550, -52.400662),  -- 99010220 Morandini & Zinn Advogados Associados
  ('bc9cc183-ddbe-4792-b623-65e9828ef81b'::uuid, -29.846374, -51.171490),  -- 93260030 Nascimento Advocacia
  ('3507894c-6f9d-43a6-bd5d-1593df425cf1'::uuid, -27.636164, -52.278259),  -- 99700062 Ramon Fabro Advocacia
  ('4d100032-75c2-4d41-9952-4a553976ef03'::uuid, -29.165886, -51.517391),  -- 95700010 Reginatto & Delazzari Advocacia
  ('e2a209a1-c4eb-43b4-ba37-cdedb9dfdce3'::uuid, -29.920260, -51.179763),  -- 92010240 RM Advogados Associados
  ('9bb06966-52ce-421f-81c3-a3103c02f0e7'::uuid, -30.019334, -51.190267),  -- 90540140 Sangiogo Advogados Associados
  ('ac4fb78b-657f-4551-9d24-b12181760a10'::uuid, -27.637372, -52.267386),  -- 99700308 Sara Morandi Advocacia e Consultoria Jurídic
  ('f7a65f82-f278-406f-84c4-35f3b03e2916'::uuid, -28.258292, -52.400098),  -- 99010030 Sarturi e Radaelli Advogados Associados
  ('7a6828c1-4488-4918-914d-3e7ae71f3ca9'::uuid, -31.767285, -52.339166),  -- 96010000 Selau Andreazza & Bainy Advocacia
  ('3b398566-bdc1-47bc-8eeb-37549855fc36'::uuid, -29.846374, -51.171490),  -- 93260030 Severo Lima & Conceição Advogados Associados
  ('717c43aa-a608-4ca9-93f3-71295c0197d2'::uuid, -30.041132, -51.228504),  -- 90020022 SNJ Advocacia
  ('50805d1a-4b93-463a-93f7-c939fe3af027'::uuid, -29.984610, -50.132673),  -- 95590000 Sociedade Individual de Advocacia Max Antôni
  ('8183b40b-5fa3-4ccf-8f9e-7b3faf8aa97b'::uuid, -29.165863, -51.180106),  -- 95020190 Toigo & Ferreira Advogados Associados
  ('452f6e6b-06b5-4f65-b4ec-a00b32707a68'::uuid, -29.687379, -53.807960),  -- 97015010 Wagner Advogados Associados
  ('e005ae7f-cb39-46a1-87e0-8ebc3051b35b'::uuid, -29.925945, -51.037062),  -- 94130000 Zagonel & Nôe Advogados Associados
  ('e1fa0956-83ca-4cd1-8bee-9011e6da09b6'::uuid, -29.165863, -51.180106)  -- 95020190 Zuco & Zuco Advogados Associados
) as origem(id, latitude, longitude)
where firm.id = origem.id
  and firm.latitude is null
  and firm.longitude is null;

notify pgrst, 'reload schema';
