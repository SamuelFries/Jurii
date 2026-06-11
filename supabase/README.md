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

## 3. Próxima etapa de integração

A camada inicial de repositories já existe em `lib/repositories/`.
O próximo passo é trocar as telas, uma por vez, dos mocks para esses
repositories:

1. Auth + Profile
2. Home cliente: categorias e escritórios
3. Verificação profissional
4. Casos
5. Mensagens
6. Agenda
