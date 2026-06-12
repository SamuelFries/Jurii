# Jurii Supabase Setup

## 1. Criar as tabelas

Abra o Supabase Dashboard, vá em **SQL Editor**, cole todo o conteúdo de
`supabase/schema.sql` e execute.

Esse script cria:

- enums
- tabelas
- índices
- triggers de `updated_at`
- buckets de Storage
- policies RLS
- seeds iniciais de categorias e escritórios

## 2. Configurar o app Flutter

No Supabase Dashboard, copie:

- Project URL
- Publishable key

Rode o app com:

```bash
flutter run \
  --dart-define=SUPABASE_URL=SUA_PROJECT_URL \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_PUBLISHABLE_KEY
```

Esses valores também estão configurados como padrão em `SupabaseConfig`, então
os `dart-define` são opcionais neste projeto. Use `dart-define` se quiser
apontar para outro ambiente.

## 2.1. Patch para perfis automáticos

Se você já rodou o `schema.sql` antes da criação do arquivo
`patch_001_auth_profile_trigger.sql`, rode também esse patch no SQL Editor.
Ele cria automaticamente uma linha em `profiles` quando um usuário se cadastra
pelo Supabase Auth.

## 2.2. Patch para recursão de RLS

Se aparecer no terminal:

```text
infinite recursion detected in policy for relation "legal_cases"
```

rode também `patch_002_fix_rls_recursion.sql` no SQL Editor.
Ele substitui policies recursivas por funções `security definer`.

## 2.3. Patch para CPF no cadastro

Se você já rodou o `schema.sql` antes do cadastro enviar CPF nos metadados do
Auth, rode `patch_003_auth_profile_cpf.sql` no SQL Editor. Ele atualiza o
trigger de criação de perfil para salvar o CPF recebido durante o cadastro.

## 2.4. Patch para verificação de escritório

Rode `patch_004_law_firm_verification.sql` antes de integrar a área do
escritório. Esse patch cria as tabelas de verificação de escritório e ajusta
`law_firm_members` para aceitar donos, admins e secretárias sem exigir OAB.

## 2.5. Patch para permissões das roles do Supabase

Se o app mostrar erros como:

```text
permission denied for table profiles
Grant SELECT ON public.profiles TO authenticated
```

rode `patch_005_public_grants.sql` no SQL Editor. As policies RLS controlam as
linhas acessíveis, mas o Postgres também precisa de permissões de tabela para
as roles `anon` e `authenticated`.

## 2.6. Patch para aprovar escritório

Rode `patch_006_approve_law_firm_verification.sql` depois dos patches 004 e
005. Ele cria uma função administrativa para aprovar a verificação de
escritório do jeito que o app espera: preenchendo `law_firm_id`, criando ou
atualizando o registro em `law_firms` e vinculando o dono em
`law_firm_members`.

Depois de enviar uma solicitação pelo app, aprove pelo SQL Editor com:

```sql
select public.approve_law_firm_verification('ID_DA_VERIFICACAO');
```

Evite aprovar apenas mudando `status` manualmente para `approved`, porque o app
precisa do vínculo com o escritório para abrir a área administrativa com dados
reais.

## 3. Próxima etapa de integração

A camada inicial de repositories já existe em `lib/repositories/`.
O próximo passo é trocar as telas, uma por vez, dos mocks para esses
repositories:

1. Auth + Profile
2. Home cliente: categorias e escritórios
3. Verificação profissional
4. Verificação de escritório
5. Casos
6. Mensagens
7. Agenda
