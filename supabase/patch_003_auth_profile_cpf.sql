-- Run this if you already executed schema.sql before CPF metadata was added.
-- It keeps sign-up compatible with email confirmation enabled by copying CPF
-- from auth metadata into public.profiles during user creation.

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

  cpf_value := new.raw_user_meta_data ->> 'cpf';

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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();
