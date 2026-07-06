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

## Fluxo de produto proposto

1. Cliente toca "Buscar ajuda" → abre chat de triagem com a assistente.
2. Assistente coleta o relato (modelo acima ou LLM no futuro).
3. Ao final, o app mostra o resumo ao cliente e pede **consentimento
   explícito** para enviar ao advogado/escritório escolhido (LGPD).
4. O `LawyerOverview` chega ao advogado como primeira mensagem da conversa
   (sender_type `system`, via RPC) ou como card na solicitação de caso.

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
