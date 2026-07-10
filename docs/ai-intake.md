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

## Pendências de decisão humana

- Copy final da assistente e limite de perguntas (revisão advogado/jurídico).
- Checklists de documentos por área devem ser validados por advogado antes de
  produção (hoje são operacionais, não aconselhamento).
- Persistir sessões desde já (rodar o proposal) ou manter efêmero até o MVP+1.
- Qual modelo/fornecedor de LLM e orçamento por sessão.
