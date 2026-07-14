# Jurii Supabase

Este diretório agora usa o fluxo de migrations do Supabase CLI como fonte
principal para novos ambientes.

## Estrutura

- `migrations/20260711190000_squashed_legacy_baseline.sql`: baseline atual do
  banco, gerada a partir de `schema.sql` + patches 001 a 045.
- `migrations/20260712...` em diante: migrations incrementais de verificação,
  avaliações, recomendações/notificações e hardening de segurança.
- `tests/`: testes pgTAP de autorização e invariantes do banco.
- `legacy_patches/`: histórico dos patches antigos. Use para auditoria ou para
  entender a origem de uma regra, não como fluxo normal de setup.
- `functions/delete-account/`: Edge Function de exclusão LGPD.
- `proposals/`: propostas SQL ainda não aplicadas como migration oficial.

## Ambiente novo

Para um projeto Supabase vazio:

```bash
supabase link --project-ref SEU_PROJECT_REF
supabase migration list --linked
supabase db push
```

Isso aplica a baseline e todas as migrations incrementais de
`supabase/migrations/`. Depois configure o app com:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Os `dart-define` são opcionais para o projeto padrão da Jurii, mas devem ser
usados quando você quiser apontar para outro ambiente.

## Ambiente local com Docker

O projeto tambem tem `supabase/config.toml` para rodar a stack local da CLI:

```bash
supabase start
supabase db reset
supabase status
```

O seed da CLI esta desativado porque a baseline ja inclui os dados/seeds
necessarios. Para detalhes, pre-requisitos e smoke tests SQL, veja
`docs/supabase-local.md`.

## Projeto remoto atual

O projeto remoto da Jurii recebeu manualmente o conteúdo que foi consolidado na
baseline. O reparo histórico abaixo já foi executado no projeto atual; ele só é
necessário ao recuperar outro ambiente legado que tenha o schema, mas não o
histórico da CLI.

Em 14/07/2026, `supabase db push --linked` aplicou a migration
`20260714220000_security_hardening_round2.sql`, e
`supabase migration list --linked` confirmou local e remoto sincronizados. Ela
revoga o contrato antigo de leitura direta de PII em `profiles`; por isso apenas
a versão do app que usa `fetch_current_profile()` e
`upsert_current_profile()` deve permanecer suportada. Builds antigos deixam de
carregar o perfil.

Para registrar apenas o histórico da migration no remoto atual:

```bash
supabase migration repair --linked --status applied 20260711190000
```

Depois disso, `supabase migration list --linked` deve mostrar a baseline como
aplicada local e remotamente.

## Mudanças futuras

Não crie mais `patch_046...` na raiz do diretório. Para qualquer alteração nova:

```bash
supabase migration new nome_curto_da_mudanca
```

Edite o arquivo criado em `supabase/migrations/` e aplique com:

```bash
supabase db reset
supabase test db supabase/tests --local
supabase migration list --linked
supabase db push
```

Regras práticas:

- migrations são **forward-only**;
- evite editar migration já aplicada em remoto;
- coordene app e banco quando a migration mudar ou revogar um contrato usado
  por clientes já publicados;
- prefira funções/RPCs idempotentes (`create or replace function`) quando fizer
  sentido;
- documente no topo da migration o problema, a decisão e a verificação;
- rode testes de RLS/RPC quando a mudança tocar permissões, Storage,
  conversas, casos ou LGPD.

## Edge Function LGPD

Depois de aplicar a baseline e as migrations incrementais em um ambiente novo,
publique a Function:

```bash
supabase functions deploy delete-account
```

Confirme que o ambiente da Function tem acesso a `SUPABASE_URL`,
`SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY`. O app chama a Function
`delete-account`; a chave `service_role` nunca entra no app nem no repositório.

## Operações administrativas úteis

Aprovar advogado criando o perfil profissional:

```sql
select public.approve_lawyer_verification('ID_DA_VERIFICACAO');
```

Aprovar escritório criando/vinculando `law_firms` e dono:

```sql
select public.approve_law_firm_verification('ID_DA_VERIFICACAO');
```

Recusar com motivo:

```sql
select public.reject_lawyer_verification(
  'ID_DA_VERIFICACAO',
  'MOTIVO',
  null
);

select public.reject_law_firm_verification(
  'ID_DA_VERIFICACAO',
  'MOTIVO',
  null
);
```

Enquanto o Jurii for apenas app, essa revisão é manual por um operador
privilegiado no SQL Editor do Dashboard do Supabase. As funções não são
executáveis por `anon` ou `authenticated`; o grant de backend confiável é da
`service_role`. A página revisora, os papéis de funcionário e a auditoria
nominal entram junto com o futuro webapp; `service_role` nunca deve ir para o
navegador.

Evite aprovar verificações apenas mudando `status` manualmente: o app depende
dos vínculos criados por essas funções.

## Histórico legado

Os arquivos em `legacy_patches/` foram mantidos de propósito. Eles explicam a
história do banco até julho/2026, incluindo hardening de segurança, busca
jurídica, escopo de casos, anexos e LGPD. Em setup novo, use a baseline em
`migrations/`; consulte os patches somente para investigação.
