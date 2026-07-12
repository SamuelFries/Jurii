# Legacy SQL Patches

Este diretório guarda os patches históricos `patch_001` a `patch_045` e o
`schema.sql` anterior ao baseline de migrations.

Eles foram consolidados em:

```text
supabase/migrations/20260711190000_squashed_legacy_baseline.sql
```

Use estes arquivos para auditoria, investigação e comparação. Para ambientes
novos, aplique a baseline via Supabase CLI. Para mudanças futuras, crie uma nova
migration timestampada em `supabase/migrations/` em vez de adicionar outro patch
legado.
