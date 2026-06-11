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

Enquanto esses defines não forem passados, o app continua abrindo normalmente
com os mocks locais.

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
