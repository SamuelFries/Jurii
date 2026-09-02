# IA de Triagem (Intake) — Arquitetura

Objetivo: conversar com o cliente **antes** do advogado, entender a dor,
organizar o relato e entregar o caso "mastigado" ao profissional (categoria
provável, urgência, pontos importantes, documentos recomendados e perguntas
pendentes).

## O que já existe (funcional hoje, 100% local)

| Peça | Arquivo |
| --- | --- |
| Sessão e mensagens | `lib/models/intake_session.dart` |
| Resumo, categoria, urgência, documentos, perguntas | `lib/models/intake_summary.dart` |
| Contrato + implementação rule-based | `lib/services/intake_ai_service.dart` |
| Testes | `test/intake_ai_service_test.dart` |

A implementação `RuleBasedIntakeAIService`:

- infere a área do direito com a **mesma taxonomia da busca**
  (`lib/data/legal_practice_areas.dart`, espelho do patch_029);
- segue um roteiro de perguntas por área + perguntas gerais (máx. 4);
- detecta urgência por palavras-chave em 4 níveis (baixa/média/alta/crítica);
- em urgência crítica (violência, prisão) emite orientação de segurança
  (190/180) — conteúdo padrão de utilidade pública;
- gera `IntakeSummary` e `LawyerOverview` formatado para o advogado.

Isso permite demonstrar e validar o fluxo com usuários **sem chave de IA**.

## Fluxo de produto (decidido em jul/2026, implementado)

**A triagem acontece DEPOIS que o cliente escolheu o advogado/escritório**,
dentro da conversa já iniciada. Decisão de negócio: a triagem não pode
acontecer antes da escolha para não interferir na captação de clientes
(advogados/escritórios pagarão para ser listados no topo). O papel da IA é
ajudar o **profissional** a avaliar se o caso tem fundamento e se vale
aceitar.

Como funciona no app (`lib/screens/chat_screen.dart`):

1. **Conversa nova (sem histórico)**: banner "Comece com uma triagem guiada"
   no topo do chat (somente para o cliente).
2. **Conversa com histórico ou banner ignorado**: a triagem vive no botão
   **"+"** do composer (que substituiu o clipes). O "+" gira ao abrir e sobe
   um menu em slide com "Anexar arquivo" e "Triagem com IA".
3. Se o cliente ignora o banner e envia a primeira mensagem, aparece uma
   dica transitória ("A triagem com a assistente está no botão +") e um
   ponto dourado sutil no "+" até ele abrir o menu.
4. A triagem roda localmente (`IntakeScreen`, rule-based) e, ao final, o
   cliente revisa o resumo e decide **enviá-lo como mensagem na conversa**
   ("Enviar resumo ao advogado/escritório"). O envio é a única saída do
   relato e só ocorre por ação explícita — nada é persistido pela triagem
   em si.
5. O advogado recebe o `LawyerOverview` formatado como mensagem do cliente
   e usa isso para avaliar o caso.

**Limitação conhecida (fast-follow):** o resumo é enviado como mensagem comum
do cliente, identificada só pelo prefixo "Triagem da assistente Jurii" — um
cliente poderia digitar um texto idêntico à mão. Marcação *verificável* exige
inserção server-side (RPC SECURITY DEFINER ou Edge Function gravando
`metadata: {type: intake_summary}`), pois metadata escrito pelo próprio
cliente também seria forjável. Entra junto com a persistência/IA real.

## Integração futura com LLM (sem chave no app)

```
Flutter ──JWT──▶ Supabase Edge Function `intake-chat` ──▶ API de IA
                    │ (ANTHROPIC_API_KEY em secret)
                    └──▶ tabelas intake_* (RLS)
```

- A chave fica **apenas** na Edge Function (`supabase secrets set`).
- A função valida o JWT do usuário, aplica rate-limit e persiste a conversa.
- O contrato `IntakeAIService` não muda: cria-se `RemoteIntakeAIService`
  chamando `supabase.functions.invoke('intake-chat')`, e a UI não percebe.

### Estrutura de prompt sugerida (Edge Function)

- **System**: "Você é a assistente de triagem da Jurii… NÃO dê aconselhamento
  jurídico, não cite artigos de lei, não prometa resultado. Colete fatos,
  datas, documentos e objetivo do cliente. Máximo de N perguntas, uma por vez,
  linguagem simples PT-BR. Em sinais de risco pessoal, oriente 190/180."
- **Saída estruturada**: exigir JSON com `case_summary`,
  `suggested_categories[{practice_area, confidence}]`, `urgency`,
  `key_points[]`, `recommended_documents[]`, `pending_questions[]` —
  exatamente o shape de `IntakeSummary`.
- Validar o JSON no servidor antes de persistir (retry em caso de mismatch).

## Banco (proposto, não aplicado)

`supabase/proposals/proposal_intake_ai.sql` — tabelas `intake_sessions`,
`intake_messages`, `intake_summaries`, `intake_category_suggestions`,
`intake_recommended_documents`, com RLS onde:

- só o titular lê a conversa bruta;
- o advogado lê **apenas o resumo**, e só após `consented_at` + entrega;
- `retention_expires_at` (90 dias) para expurgo de sessões abandonadas.

## Integração real (implementada em 02/09/2026, branch feat/ia-de-triagem)

Decisão de modelo: **Claude Sonnet 5 com prompt caching** (`claude-sonnet-5`).
Custo medido em estimativa: ~US$0,012 por sessão completa (5 chamadas, ~8K
tokens de entrada, cache read a 0,1× do preço); o pior caso adversarial fica
em ~US$0,45/dia por conta, preso pelo taxímetro. Haiku 4.5 custaria o mesmo
na prática (o mínimo cacheável dele, 4.096 tokens, não se atinge aqui) com
perguntas piores; Opus 5 custa 5× e fica como upgrade se a qualidade pedir.

| Peça | Arquivo |
| --- | --- |
| Edge Function (chave, taxímetro, prompt, schema, validação) | `supabase/functions/intake-chat/index.ts` |
| Taxímetro: 12 chamadas/hora e 30/dia por usuário | `supabase/migrations/20260923120000_a_triagem_tem_medidor.sql` |
| Serviço remoto com fallback POR TURNO no rule-based | `lib/services/remote_intake_ai_service.dart` |
| Composição (Supabase pronto → remoto; demo → local) | `lib/services/intake_ai_service_factory.dart` |
| Testes | `supabase/tests/triagem_tem_medidor_test.sql`, `test/remote_intake_ai_service_test.dart` |

O desenho anti-abuso, na ordem em que uma requisição o atravessa, está no
cabeçalho da própria função. O resumo em uma linha: a IA não tem ferramenta
nem vê nada além do texto da própria sessão; a área do direito sai de um
ENUM montado da allowlist do banco; os textos de emergência e encerramento
são fixos do app (a IA só sinaliza booleanos); e qualquer falha cai no
rule-based sem travar a triagem.

A conversa continua EFÊMERA (o proposal de persistência segue não aplicado):
a única tabela nova é o taxímetro, que guarda quem chamou e quando, nunca
conteúdo.

### Para ligar em produção (passos do Samuel)

1. `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...` (chave criada no
   console da Anthropic; recomendo um workspace próprio "jurii-triagem" para
   o limite de gasto ser isolado).
2. `supabase db push` (aplica a migration do taxímetro).
3. `supabase functions deploy intake-chat`.
4. Validar com a chave real: abrir a triagem no app e conferir uma sessão
   inteira. IMPORTANTE: a prova local rodou com chave falsa, que a Anthropic
   recusa ANTES de validar o corpo; o formato das mensagens está fundado na
   regra documentada da API (primeira mensagem é sempre user), mas a
   primeira sessão com chave real é a prova final.
5. Conferir no dashboard da Anthropic que `cache_read_input_tokens` cresce a
   partir da segunda chamada de uma sessão (senão, algum byte do prefixo
   está variando).

## Pendências de decisão humana

- Copy final da assistente e limite de perguntas (revisão advogado/jurídico).
- Checklists de documentos por área devem ser validados por advogado antes de
  produção (hoje são operacionais, não aconselhamento).
- Persistir sessões desde já (rodar o proposal) ou manter efêmero até o MVP+1.
- Marcação verificável do resumo na conversa (inserção server-side), o
  fast-follow já anotado acima.
