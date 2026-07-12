-- Ensures chat messages have metadata required by case requests and chat UI.
--
-- Run after patch_020 if sending a chat message fails with:
-- column messages.metadata does not exist

alter table public.messages
add column if not exists metadata jsonb;

update public.messages
set metadata = '{}'::jsonb
where metadata is null;

alter table public.messages
alter column metadata set default '{}'::jsonb;

alter table public.messages
alter column metadata set not null;

notify pgrst, 'reload schema';
