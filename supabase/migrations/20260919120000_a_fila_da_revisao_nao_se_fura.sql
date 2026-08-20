-- A fila da revisão não se fura.
--
-- lawyer_verifications tinha insert e update de TABELA INTEIRA concedidos a
-- authenticated. As policies seguravam o que mais importa (o candidato não se
-- aprova: o WITH CHECK prende status em draft/pending e exige reviewer_id e
-- reviewed_at nulos), mas deixavam passar a escrita das colunas de tempo. Na
-- prática o candidato reescrevia o próprio submitted_at e se colocava na
-- frente na fila que a equipe Jurii revisa em ordem de envio, além de poder
-- mentir em created_at e updated_at.
--
-- A escrita legítima nunca passou por aqui: o app envia por
-- submit_lawyer_verification, e a equipe decide por approve_lawyer_verification
-- e reject_lawyer_verification. As três são SECURITY DEFINER e não usam o
-- grant de quem chama. O app e o webapp só LEEM a tabela.
--
-- Mesmo desenho da 20260918 para legal_cases: o grant de escrita sai inteiro,
-- as policies ficam como segunda camada.

revoke insert, update on public.lawyer_verifications from authenticated;
