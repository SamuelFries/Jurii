-- Apresentação do profissional: torna gravável o que o cliente lê para
-- escolher.
--
-- O BURACO: `lawyer_profiles.bio` e `law_firms.description` eram LIDOS na
-- descoberta e nos perfis públicos, mas NENHUM caminho do app os escrevia —
-- não estavam no formulário de verificação nem na edição de perfil. Como as
-- RPCs fazem `coalesce(lp.bio, 'Perfil profissional verificado pela Jurii.')`,
-- todo advogado exibia o MESMO texto de apresentação, e todo escritório o
-- mesmo parágrafo genérico. Produção: 0 advogados com bio, 0 escritórios com
-- descrição — não por desinteresse, por impossibilidade.
--
-- Escrita por RPC (padrão da casa desde o hardening): valida tamanho, apara
-- espaço e transforma vazio em NULL, para o fallback genérico voltar quando o
-- profissional limpa o texto em vez de gravar string vazia.
--
-- lawyer_profiles.bio JÁ tinha grant de UPDATE para authenticated (policy
-- lawyer_profiles_update_own). Revogado abaixo: com a RPC existindo, escrita
-- direta seria um segundo caminho sem validação. law_firms nunca teve grant
-- de UPDATE — a RPC é a única via desde sempre.

-- Teto generoso mas finito: apresentação, não petição. O app espelha.
create or replace function public.update_lawyer_bio(bio_value text)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_bio text := nullif(btrim(coalesce(bio_value, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if length(clean_bio) > 800 then
    raise exception 'Bio is too long';
  end if;

  update public.lawyer_profiles
  set bio = clean_bio
  where id = auth.uid();

  if not found then
    raise exception 'Lawyer profile not found';
  end if;

  return clean_bio;
end;
$$;

-- Gate = owner/admin ativo (is_active_law_firm_manager). Secretária NÃO:
-- a apresentação é a peça comercial do escritório, mesmo público que já
-- decide sobre a organização.
create or replace function public.update_law_firm_description(
  law_firm_id_value uuid,
  description_value text
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  clean_description text := nullif(btrim(coalesce(description_value, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_active_law_firm_manager(law_firm_id_value) then
    raise exception 'Only firm owners and admins can edit the description';
  end if;

  if length(clean_description) > 800 then
    raise exception 'Description is too long';
  end if;

  update public.law_firms
  set description = clean_description
  where id = law_firm_id_value;

  if not found then
    raise exception 'Law firm not found';
  end if;

  return clean_description;
end;
$$;

-- A RPC passa a ser o único caminho de escrita da bio.
revoke update (bio) on public.lawyer_profiles from authenticated;

revoke all on function public.update_lawyer_bio(text) from public, anon;
grant execute on function public.update_lawyer_bio(text) to authenticated;

revoke all on function public.update_law_firm_description(uuid, text)
from public, anon;
grant execute on function public.update_law_firm_description(uuid, text)
to authenticated;

notify pgrst, 'reload schema';
