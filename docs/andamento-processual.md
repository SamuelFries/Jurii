# Andamento processual automático (DataJud/CNJ)

O advogado ou escritório informa o número CNJ do processo em um caso; um job
de hora em hora consulta a API pública do DataJud e grava os movimentos. O
app mostra uma timeline traduzida para linguagem simples e o cliente recebe
notificação (sino + push) quando o processo anda. Sem Jusbrasil, sem
scraping: só a API oficial e gratuita do CNJ.

## Decisões de produto (29/07/2026)

- **Número CNJ é opcional, para sempre.** Muitos casos nunca viram processo
  judicial (consultoria, acordo extrajudicial); a ausência do número é estado
  normal, nunca erro.
- **Só advogado/escritório preenche**: o advogado do caso
  (`can_manage_case_updates`, o mesmo predicado do "Atualizar") ou um gestor
  ativo do escritório do caso (dono/admin/secretaria, via
  `is_active_law_firm_case_manager` — na prática é a secretaria quem cadastra
  número de processo). O cliente vê, não edita.
- **Indicativo "Sem nº do processo"** nos cards profissionais só quando o
  caso tem `deadline_at` e não tem número (sinal real de processo rodando).
  Tom neutro, estilo do badge "Novo". Obs.: `deadline_at` ainda não é
  preenchido por nenhum fluxo do app, então o indicativo nasce dormente e
  passa a funcionar quando prazos entrarem em uso.
- **Timeline mostra só o que interessa ao leigo**: movimentos com tradução
  curada em `case_movement_translations`. Ruído processual (juntada,
  certidão, publicação) fica gravado mas não aparece.
- **Segredo de justiça**: o índice público do DataJud só tem processos com
  `nivelSigilo=0`; processo sigiloso simplesmente não retorna. Timeline
  vazia é tratada como estado normal na UI.

## Arquitetura

```
pg_cron ('7 * * * *')
  └─ dispatch_case_movement_sync()            [Vault: case_sync_hook_url/secret; NO-OP sem eles]
       └─ Edge Function sync-case-movements    [auth: CASE_SYNC_HOOK_SECRET]
            ├─ RPC fetch_cases_for_movement_sync(4)   [service_role only; fila por synced_at, 1x/20h]
            ├─ DataJud: 1-2 índices por caso (origem + superior do ramo, via J.TR do número)
            └─ RPC ingest_case_movements(case, cnj, jsonb) [dedup, tradução, notificação, label]
```

- Notificação reusa o tipo **`case_update`** (declarado com escopo `client`
  e com ícone no sino desde a baseline, nunca usado até aqui). Push e
  realtime vêm de graça do trigger `notifications_push_dispatch` e da
  publication existente. Uma notificação por passada, agregando os
  movimentos novos.
- O mesmo processo tem um documento por instância no DataJud (e o índice do
  STJ carrega o histórico de origem): a unique
  `(case_id, movement_code, occurred_at)` absorve a sobreposição.
- Latência do DataJud é alta (4-47s por consulta, medida em 29/07): lote de
  4 casos por passada, consultas sequenciais, timeout de 45s. Com o índice
  atualizando a cada ~3-4 dias, re-sincronizar cada caso 1x/20h sobra.
- `cnj_number` não tem grant de coluna: escrita **só** pela RPC
  `set_case_cnj_number` (valida papel + dígito verificador mod 97, espelhado
  em `isValidCnj` no Dart). Trocar o número zera movimentos e fila.
- Estado de sincronização vive em `case_movement_sync_state` (tabela
  própria) de propósito: em `legal_cases` o trigger de `updated_at`
  reordenaria as listas de casos a cada passada do job.
- **Blindagens da revisão adversarial (29/07)**: a primeira passada de um
  número é backfill de histórico e NÃO notifica nem mexe no label (só
  passadas incrementais); o ingest recebe o número que o job de fato
  consultou e vira NO-OP se o advogado trocou o número durante a janela da
  consulta; `dataHora` malformado é descartado item a item (`pg_input_is_valid`
  + `Date.parse`), nunca aborta o lote; falha na consulta ao índice de ORIGEM
  não marca o caso como sincronizado (volta à fila); o handler tem orçamento
  de 100s por invocação — o que não couber fica para a próxima hora.

## Ampliar a curadoria de movimentos

`case_movement_translations` é a fonte única (timeline e notificação):

```sql
insert into case_movement_translations (movement_code, title, body, notify)
values (123, 'Título curto', 'Frase para o cliente leigo.', true)
on conflict (movement_code) do update
  set title = excluded.title, body = excluded.body, notify = excluded.notify;
```

Sem release do app. Códigos atuais verificados contra dados reais do DataJud
em 29/07/2026 (TJRS/TRT4/TRF4/STJ/TST); tabela de referência oficial: TPU do
CNJ (movimentos).

## Deploy (produção)

1. `supabase db push --linked` (migration `20260729150000`).
2. `supabase functions deploy sync-case-movements --project-ref rlgtgipxltucrtkyrmag --use-api`
3. Gerar um segredo forte e configurar:
   - `supabase secrets set CASE_SYNC_HOOK_SECRET="<SEGREDO>"`
   - SQL Editor:
     `select vault.create_secret('https://rlgtgipxltucrtkyrmag.supabase.co/functions/v1/sync-case-movements', 'case_sync_hook_url');`
     `select vault.create_secret('<SEGREDO>', 'case_sync_hook_secret');`
4. Conferir: `select jobname, schedule from cron.job where jobname = 'case-movement-sync';`
   e, após a primeira hora, `select * from case_movement_sync_state;`.

Sem os passos 2-3 nada quebra: o dispatch é NO-OP (mesmo padrão do push).
A chave do DataJud é pública (hardcoded na função; sobrescrevível com o
secret `DATAJUD_API_KEY` se o CNJ rotacionar).

## Limitações conhecidas (v1)

- Ramos fora da v1: STF, eleitoral e militar (função marca como sincronizado
  e segue; adicionar aliases quando houver demanda).
- O DataJud reflete a carga dos tribunais com ~3-4 dias de atraso; a UI avisa
  ("pode levar alguns dias").
- Movimento 970 (Audiência) não distingue designada/realizada/cancelada no
  título (o complemento existe no dado cru, fica para v2).
- Tap na notificação ainda não abre o caso (não há roteamento de tap no
  push/sino hoje; feature separada).
- Caso cujo índice de origem falhe cronicamente ocupa 1 das 4 vagas do lote
  a cada hora (retry sem backoff). Aceitável no volume atual; se incomodar,
  registrar tentativa falha em `case_movement_sync_state` com horizonte
  curto (backoff) é o upgrade natural.
