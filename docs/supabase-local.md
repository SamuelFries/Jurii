# Supabase local com Docker

Atualizado em: 14/07/2026

Este documento registra o fluxo local recomendado para testar migrations,
funcoes SQL e Edge Functions da Jurii sem tocar no projeto remoto.

## Pre-requisitos

- Docker Desktop aberto e saudavel;
- Supabase CLI instalado e logado;
- alguns GB livres em disco antes do primeiro `supabase start`.

Antes de iniciar, vale conferir:

```bash
df -h / "$HOME"
docker info
docker system df
```

Se o disco estiver quase cheio, o Docker pode falhar durante o pull das imagens
com erro de `input/output error` no banco interno do containerd. Nesse caso,
libere espaco, reinicie o Docker Desktop e rode o fluxo de novo.

## Quando o Docker fica corrompido

Se, mesmo depois de liberar espaco, `docker info` ainda retornar:

```text
Cannot connect to the Docker daemon
```

e os logs do Docker tiverem linhas como:

```text
EXT4-fs ... Remounting filesystem read-only
containerd ... garbage collection failed: input/output error
```

o problema provavelmente nao e mais falta de espaco no macOS. O disco interno
do Docker Desktop (`Docker.raw`) ficou corrompido ou read-only depois da
tentativa anterior.

O caminho mais seguro e resolver pela UI do Docker Desktop:

1. abrir Docker Desktop;
2. ir em Troubleshoot;
3. usar Clean / Purge data ou Reset to factory defaults;
4. reiniciar o Docker Desktop;
5. rodar `docker info`;
6. repetir `supabase start`.

Atencao: Clean / Purge data e Reset to factory defaults removem imagens,
containers e volumes locais do Docker. Nao apagam o codigo do projeto, mas
apagam bancos/volumes locais que existam dentro do Docker.

## Primeiro start local

Na raiz do projeto:

```bash
supabase start
supabase status
```

O arquivo `supabase/config.toml` define `project_id = "jurii"` para manter o
ambiente local estavel entre branches. O seed da CLI esta desativado porque a
baseline atual ja contem os dados/seeds necessarios para um ambiente novo.

## Reset do banco local

Para recriar o banco local a partir das migrations:

```bash
supabase db reset
```

Isso aplica a baseline e todas as migrations incrementais em ordem. Confira o
histórico efetivo com `supabase migration list --local`.

Nao rode `supabase db reset` contra o remoto. Esse comando e para o ambiente
local Docker.

## Testes automatizados do banco

Depois do reset, rode os testes pgTAP versionados:

```bash
supabase test db supabase/tests --local
```

`security_hardening_round2_test.sql` cria fixtures descartáveis dentro de uma
transação e cobre grants, RLS, PII, roster, autoridade de escritório,
conversas/agenda, anexos, convite por OAB, rate limit e recusa. Tudo termina em
`ROLLBACK`.

Se a imagem `pg_prove` ainda não estiver no Docker, a primeira execução pode
demorar enquanto a CLI faz o download. Para diagnóstico direto, o mesmo arquivo
pode ser executado com:

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -v ON_ERROR_STOP=1 \
  -f supabase/tests/security_hardening_round2_test.sql
```

## Smoke tests SQL manuais

Depois do reset, execute consultas simples no banco local:

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

Consultas uteis:

```sql
select to_regprocedure('public.approve_lawyer_verification(uuid,uuid)');
select to_regprocedure('public.approve_law_firm_verification(uuid,uuid)');
select to_regclass('public.account_deletion_audit');
select count(*) > 0 as has_intents from public.legal_search_intents;
select public.legal_search_term_matches('minha demissao foi sem justa causa', 'iss') as iss_false_positive;
select * from public.infer_legal_search_areas('inss negou meu auxilio');
select id, public from storage.buckets order by id;
```

Expectativas principais:

- as funcoes de aprovacao devem existir;
- `account_deletion_audit` deve existir;
- `legal_search_intents` deve ter linhas;
- `iss_false_positive` deve retornar `false`;
- a busca por `inss negou meu auxilio` deve inferir Direito Previdenciario;
- buckets de Storage esperados devem estar presentes.

## App apontando para local

Depois de `supabase status`, use a URL e a anon key locais no Flutter:

```bash
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=COLE_A_ANON_KEY_LOCAL
```

## Mudancas futuras de banco

Para novas alteracoes, nao crie `patch_046...`. Use migrations:

```bash
supabase migration new nome_curto_da_mudanca
supabase db reset
supabase test db supabase/tests --local
supabase migration list --linked
supabase db push
```

Regra pratica: valide localmente com Docker e confira o delta local/remoto antes
de enviar, principalmente quando a mudanca tocar RLS, Storage, Auth, RPCs,
casos, conversas ou LGPD. Se a migration revogar um contrato consumido pelo app,
o `db push` deve fazer parte de uma release coordenada com a versao compativel
do cliente; nao publique apenas o banco.
