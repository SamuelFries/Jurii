# Jurii Supabase

Este diretório agora usa o fluxo de migrations do Supabase CLI como fonte
principal para novos ambientes.

## Estrutura

- `migrations/20260711190000_squashed_legacy_baseline.sql`: baseline atual do
  banco, gerada a partir de `schema.sql` + patches 001 a 045.
- `legacy_patches/`: histórico dos patches antigos. Use para auditoria ou para
  entender a origem de uma regra, não como fluxo normal de setup.
- `functions/delete-account/`: Edge Function de exclusão LGPD.
- `proposals/`: propostas SQL ainda não aplicadas como migration oficial.

## Ambiente novo

Para um projeto Supabase vazio:

```bash
supabase link --project-ref SEU_PROJECT_REF
supabase db push
```

Isso aplica a baseline em `supabase/migrations/`. Depois configure o app com:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Os `dart-define` são opcionais para o projeto padrão da Jurii, mas devem ser
usados quando você quiser apontar para outro ambiente.

## Projeto remoto atual

O projeto remoto da Jurii já recebeu manualmente o conteúdo que foi consolidado
na baseline. Portanto, **não rode `supabase db push` nele antes de marcar a
baseline como aplicada**, ou a CLI tentará executar novamente uma migration que
representa estado já existente.

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
supabase db push
```

Regras práticas:

- migrations são **forward-only**;
- evite editar migration já aplicada em remoto;
- prefira funções/RPCs idempotentes (`create or replace function`) quando fizer
  sentido;
- documente no topo da migration o problema, a decisão e a verificação;
- rode smoke tests de RLS/RPC quando a mudança tocar permissões, Storage,
  conversas, casos ou LGPD.

## Edge Function LGPD

Depois de aplicar a baseline em um ambiente novo, publique a Function:

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

Evite aprovar verificações apenas mudando `status` manualmente: o app depende
dos vínculos criados por essas funções.

## Histórico legado

Os arquivos em `legacy_patches/` foram mantidos de propósito. Eles explicam a
história do banco até julho/2026, incluindo hardening de segurança, busca
jurídica, escopo de casos, anexos e LGPD. Em setup novo, use a baseline em
`migrations/`; consulte os patches somente para investigação.
