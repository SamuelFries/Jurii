-- As duas sobrecargas de profile_display_name devem dizer a MESMA coisa.
-- O typo "(delleted account)" viveu numa delas por semanas justamente porque
-- nada comparava as duas.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(5);

select is(
  public.profile_display_name('Maria'::text, null::text, now()),
  'Maria (conta excluída)',
  'sobrecarga (nome, rotulo, data) usa o texto em portugues');

select is(
  public.profile_display_name('Maria'::text, now(), null::text),
  'Maria (conta excluída)',
  'sobrecarga (nome, data, rotulo) diz o mesmo');

select isnt(
  public.profile_display_name('Maria'::text, null::text, now()),
  'Maria (delleted account)',
  'REGRESSAO: o typo em ingles nao volta');

select is(
  public.profile_display_name('Maria'::text, null::text, null::timestamptz),
  'Maria',
  'conta ativa continua sem sufixo');

-- O rotulo de exclusao, quando existe, tem precedencia sobre o nome real.
select is(
  public.profile_display_name('Maria'::text, 'Cliente Jurii'::text, now()),
  'Cliente Jurii (conta excluída)',
  'rotulo de exclusao substitui o nome real');

select * from finish();
rollback;
