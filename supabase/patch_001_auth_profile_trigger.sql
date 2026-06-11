-- Run this if you already executed schema.sql before this patch existed.
-- It creates a profile row automatically when a user signs up.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  full_name_value text;
begin
  full_name_value := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    split_part(new.email, '@', 1),
    'Usuário Jurii'
  );

  insert into public.profiles (id, full_name, email, initials)
  values (
    new.id,
    full_name_value,
    new.email,
    upper(left(full_name_value, 1))
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();
