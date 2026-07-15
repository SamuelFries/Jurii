-- CPF validado no servidor (completar cadastro do login social)
--
-- Google e Apple autenticam sem CPF — e a Apple, muitas vezes, sem nome. O app
-- passa a cobrar esses dados numa etapa extra antes de liberar o acesso, mas a
-- regra nao pode viver so no cliente: um app adulterado gravaria "00000000000"
-- num campo que a plataforma usa para identificar a parte em contrato/processo.
--
-- Aqui:
--   1. is_valid_cpf: digitos verificadores (espelha o validador do app).
--   2. upsert_current_profile: recusa CPF invalido e CPF ja usado.
--   3. handle_new_auth_user: ignora CPF invalido/repetido em vez de derrubar o
--      cadastro (o signUp grava CPF pelo gatilho, nao pela RPC).
--   4. indice unico: 1 CPF = 1 conta.
--
-- O NOME completo (dois nomes) fica validado apenas no app, de proposito:
-- monônimo legitimo existe, e travar isso no banco criaria um bloqueio sem
-- saida para o usuario. O CPF, esse sim, e objetivamente conferivel.
--
-- Os 5 perfis de teste que compartilhavam um CPF em producao foram apagados
-- (autorizado pelo Samuel em 14/07) — sem isso o indice unico nao nasceria.

-- ---------------------------------------------------------------------------
-- 1. Validador de CPF
-- ---------------------------------------------------------------------------

create or replace function public.is_valid_cpf(cpf_value text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  digits text;
  first_check int;
  second_check int;
  sum_value int;
  i int;
begin
  digits := regexp_replace(coalesce(cpf_value, ''), '[^0-9]', '', 'g');

  if length(digits) <> 11 then
    return false;
  end if;

  -- 000.000.000-00, 111.111.111-11 etc. passam na conta, mas nao sao CPFs.
  if digits ~ '^(.)\1{10}$' then
    return false;
  end if;

  sum_value := 0;
  for i in 1..9 loop
    sum_value := sum_value + substr(digits, i, 1)::int * (11 - i);
  end loop;
  first_check := (sum_value * 10) % 11;
  if first_check = 10 then
    first_check := 0;
  end if;

  if first_check <> substr(digits, 10, 1)::int then
    return false;
  end if;

  sum_value := 0;
  for i in 1..10 loop
    sum_value := sum_value + substr(digits, i, 1)::int * (12 - i);
  end loop;
  second_check := (sum_value * 10) % 11;
  if second_check = 10 then
    second_check := 0;
  end if;

  return second_check = substr(digits, 11, 1)::int;
end;
$$;

revoke all on function public.is_valid_cpf(text) from public, anon;
grant execute on function public.is_valid_cpf(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. upsert_current_profile recusa CPF invalido
-- ---------------------------------------------------------------------------

create or replace function public.upsert_current_profile(
  full_name_value text,
  cpf_value text default null,
  phone_value text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id_value uuid := auth.uid();
  auth_email_value text;
  clean_cpf_value text;
  normalized_name_value text;
  normalized_initials_value text;
  name_parts text[];
begin
  if profile_id_value is null then
    raise exception 'User must be authenticated';
  end if;

  normalized_name_value := nullif(
    btrim(
      regexp_replace(
        coalesce(full_name_value, ''),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ),
    ''
  );

  if normalized_name_value is null then
    raise exception 'Full name is required';
  end if;

  -- CPF e a ancora de identidade da plataforma: guarda so os 11 digitos e
  -- recusa numero invalido. A checagem existe no app, mas a regra tem que
  -- valer mesmo para um cliente adulterado.
  clean_cpf_value := nullif(
    regexp_replace(coalesce(cpf_value, ''), '[^0-9]', '', 'g'),
    ''
  );

  if clean_cpf_value is not null and not public.is_valid_cpf(clean_cpf_value) then
    raise exception 'Invalid CPF';
  end if;

  -- 1 CPF = 1 conta. O indice unico no fim do arquivo e a garantia real (a
  -- prova de corrida); esta checagem existe para o app conseguir EXPLICAR o que
  -- houve, em vez de mostrar uma violacao de constraint crua. Conta excluida
  -- tem o CPF anulado pela rotina de LGPD, entao nao prende o CPF de ninguem.
  if clean_cpf_value is not null and exists (
    select 1
    from public.profiles other_profile
    where other_profile.cpf = clean_cpf_value
      and other_profile.id <> profile_id_value
  ) then
    raise exception 'CPF already registered';
  end if;

  select nullif(trim(auth_user.email), '')
  into auth_email_value
  from auth.users auth_user
  where auth_user.id = profile_id_value;

  if not found or auth_email_value is null then
    raise exception 'Authenticated user was not found';
  end if;

  name_parts := regexp_split_to_array(normalized_name_value, '[[:space:]]+');
  normalized_initials_value := upper(
    left(name_parts[1], 1)
    || case
      when array_length(name_parts, 1) > 1
        then left(name_parts[array_upper(name_parts, 1)], 1)
      else ''
    end
  );

  insert into public.profiles (
    id,
    full_name,
    email,
    initials,
    cpf,
    phone
  )
  values (
    profile_id_value,
    normalized_name_value,
    auth_email_value,
    normalized_initials_value,
    clean_cpf_value,
    nullif(trim(phone_value), '')
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    initials = excluded.initials,
    cpf = coalesce(excluded.cpf, public.profiles.cpf),
    phone = coalesce(excluded.phone, public.profiles.phone)
  where public.profiles.deleted_at is null;

  if not found then
    raise exception 'Deleted profile cannot be restored';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Cadastro por e-mail nao pode quebrar por causa do CPF
--
-- O signUp grava o CPF pelo GATILHO (raw_user_meta_data), nao pela RPC. Com o
-- indice unico abaixo, um CPF repetido faria o insert do gatilho falhar e o
-- signUp voltar um "Database error" opaco. Aqui o gatilho passa a ignorar CPF
-- invalido/repetido: a conta nasce sem CPF e cai na tela de completar cadastro,
-- que sabe explicar o motivo.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  full_name_value text;
  cpf_value text;
begin
  full_name_value := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    split_part(new.email, '@', 1),
    'Usuário Jurii'
  );

  cpf_value := nullif(
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'cpf', ''),
      '[^0-9]',
      '',
      'g'
    ),
    ''
  );

  -- CPF invalido ou ja usado por outra conta NAO derruba o cadastro: a conta
  -- nasce sem CPF e o app cobra na tela de completar cadastro, onde da para
  -- explicar o motivo. Sem isso, o indice unico abaixo faria o signUp falhar
  -- com um "Database error" opaco.
  if cpf_value is not null and (
    not public.is_valid_cpf(cpf_value)
    or exists (select 1 from public.profiles p where p.cpf = cpf_value)
  ) then
    cpf_value := null;
  end if;

  insert into public.profiles (id, full_name, email, initials, cpf)
  values (
    new.id,
    full_name_value,
    new.email,
    upper(left(full_name_value, 1)),
    cpf_value
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    initials = excluded.initials,
    cpf = coalesce(excluded.cpf, public.profiles.cpf);

  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- 4. 1 CPF = 1 conta
--
-- Parcial em `cpf is not null`: quem entrou por Google/Apple ainda nao tem CPF,
-- e conta excluida tem o CPF anulado pela LGPD — nenhum dos dois colide.
-- ---------------------------------------------------------------------------

create unique index if not exists profiles_cpf_unique
on public.profiles (cpf)
where cpf is not null;

notify pgrst, 'reload schema';
