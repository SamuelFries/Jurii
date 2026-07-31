# ⚖️ Jurii

Jurii é uma plataforma digital desenvolvida para conectar clientes, advogados e escritórios de advocacia em um único ecossistema moderno, seguro e intuitivo.

Nosso objetivo é simplificar o acesso a serviços jurídicos, tornando a contratação, comunicação e gestão de atendimentos mais acessíveis, transparentes e eficientes.

---

## 🚀 Funcionalidades

### 👤 Para Clientes

- Cadastro e autenticação (e-mail/senha, Google, Apple)
- Busca por linguagem do dia a dia ("fui demitido"), não por termo jurídico
- Ordenação da descoberta por relevância, avaliação ou distância
- Conversa direta com advogado ou escritório, com anexos
- Triagem assistida antes de falar com o profissional
- **Andamento do processo automático**: linha do tempo traduzida do DataJud
  (CNJ) e aviso no celular quando o processo anda
- Avaliação do profissional, liberada só depois de um caso aceito
- Perfil com foto e exclusão de conta (LGPD)

### ⚖️ Para Advogados

- Verificação de OAB com envio de documentos e ciclo de recusa
- Perfil profissional validado, com foto e áreas de atuação
- Casos: proposta ao cliente, aceite, atualizações
- Agenda com compromissos, lembretes e assinatura em calendário externo
  (feed `.ics` para Google/Apple/Outlook)
- Destaque pago na descoberta, sempre sinalizado ao cliente
- Notificações push

### 🏢 Para Escritórios

- Perfil institucional verificado por CNPJ e endereço
- Equipe com papéis (dono, admin, advogado, secretaria, estagiário)
- Recepção digital: o escritório indica o advogado certo dentro da conversa
- Painel com as conversas e casos da organização
- Distância até o escritório calculada **no aparelho do cliente** — a
  localização dele nunca sai do dispositivo

---

## 🏗️ Arquitetura do Projeto

```text
lib/
├── data/           # dados estáticos reais (+ data/mock para modo demo)
├── models/         # entidades imutáveis
├── repositories/   # acesso a Supabase (tabelas + RPCs)
├── screens/        # telas
├── services/       # infraestrutura (SupabaseConfig, push, roteador de notificação)
├── theme/          # AppTheme, AppColors (dark mode), ThemeController
├── utils/          # helpers puros (validators, formatadores)
└── widgets/        # componentes reutilizáveis

supabase/
├── migrations/     # fonte da verdade do banco (baseline + incrementais)
├── functions/      # Edge Functions (Deno, sem dependências externas)
├── tests/          # pgTAP: RLS, permissões, invariantes
└── legacy_patches/ # patches 001-045 arquivados (só auditoria)
```

Detalhes em [docs/architecture.md](docs/architecture.md).

### Documentação

| Documento | Sobre |
|---|---|
| [architecture.md](docs/architecture.md) | camadas, navegação, tema, busca |
| [security.md](docs/security.md) | LGPD, hardening, postura anti-SQL-injection |
| [andamento-processual.md](docs/andamento-processual.md) | integração com o DataJud (CNJ) |
| [notificacoes.md](docs/notificacoes.md) | sino, push, destino do toque, retenção |
| [ai-intake.md](docs/ai-intake.md) | triagem assistida |
| [design-motion.md](docs/design-motion.md) | design system e animação |
| [supabase-local.md](docs/supabase-local.md) | subir o banco local com Docker |

---

## 📱 Tecnologias Utilizadas

- Flutter / Dart
- Supabase (PostgreSQL, Auth, Storage, Realtime, RPCs, Edge Functions)
- Firebase Cloud Messaging (push)
- RLS (Row Level Security) em **todas** as tabelas
- `pg_cron` + `pg_net` para as rotinas do servidor
- API pública do DataJud (CNJ) para o andamento processual

---

## ▶️ Como rodar

```bash
flutter pub get
flutter run
```

O app aponta para o projeto Supabase da Jurii por padrão. Para outro ambiente:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

### Testes

```bash
flutter test                       # app
supabase db reset                  # banco local (Docker) com todas as migrations
psql "$LOCAL_DB" -f supabase/tests/<arquivo>_test.sql   # pgTAP
```

O banco tem suíte própria em `supabase/tests/`, que cobre RLS, permissões e
**invariantes** — coisas que deveriam continuar verdadeiras para sempre
(nenhuma policy sem `search_path`, nenhuma tabela sem RLS, nenhum filtro do
PostgREST montado por string). Ver [docs/supabase-local.md](docs/supabase-local.md).

### Configurar o Supabase do zero

1. Crie um projeto no Supabase.
2. Rode `supabase link --project-ref SEU_PROJECT_REF`.
3. Confira o estado do ambiente com `supabase migration list --linked`.
4. Aplique a baseline consolidada e as migrations incrementais com
   `supabase db push`.
5. Publique as Edge Functions:

   ```bash
   supabase functions deploy delete-account        # exclusão de conta (LGPD)
   supabase functions deploy calendar-feed         # feed .ics da agenda
   supabase functions deploy send-push             # entrega de push (FCM)
   supabase functions deploy sync-case-movements   # andamento processual (DataJud)
   ```

6. Configure os segredos que as rotinas usam (sem eles nada quebra: os
   disparos viram no-op). Ver as instruções em
   [docs/notificacoes.md](docs/notificacoes.md) e
   [docs/andamento-processual.md](docs/andamento-processual.md).

Os antigos `patch_001...045` foram arquivados em
`supabase/legacy_patches/`. Para setup novo, use o conjunto versionado em
`supabase/migrations/`; detalhes em `supabase/README.md`.

A `service_role key` **nunca** entra no app ou no repositório.

### Rotinas do servidor (`pg_cron`)

| Job | Quando | O quê |
|---|---|---|
| `appointment-reminders` | a cada 10 min | avisa o advogado ~1h antes do compromisso |
| `case-movement-sync` | de hora em hora | busca o andamento no DataJud |
| `purge-old-notifications` | diário | apaga notificação **já lida** há mais de 90 dias |

---

## 🎨 Design

A identidade visual da Jurii foi construída com foco em:

- Credibilidade
- Profissionalismo
- Simplicidade
- Acessibilidade
- Experiência do usuário

### Princípios

- Interface limpa e intuitiva
- Navegação simplificada
- Fluxos guiados para usuários leigos
- Experiência otimizada para dispositivos móveis

---

## 🔒 Verificação Profissional

Para garantir a autenticidade dos profissionais cadastrados, a Jurii realiza um processo de validação documental.

### Informações solicitadas

- Número da OAB
- Estado da inscrição
- Área de atuação

### Documentos solicitados

- Documento de identificação
- Carteira da OAB
- Foto profissional (vira o avatar do perfil)

### Escritórios

Fluxo próprio: nome, CNPJ, endereço com CEP, áreas atendidas, foto de perfil e
documentos. O CEP é obrigatório porque dele saem as coordenadas do escritório
— é o que permite ao cliente ver a distância **sem** enviar a localização dele
para o servidor.

Após o envio, a documentação é analisada antes da liberação. Hoje a aprovação e
a recusa são feitas pelo painel do Supabase (back-office); a tela de revisão
fica para o futuro webapp.

---

## 📌 Status do Projeto

🚧 Em desenvolvimento

### Implementado

- Autenticação (e-mail/senha, Google/Apple OAuth, reset de senha) e portão de
  completar cadastro quando o login social não traz nome ou CPF
- Banco Supabase completo com RLS em todas as tabelas
- Busca por linguagem leiga → área do direito, com ordenação por relevância,
  avaliação ou distância
- Mensagens em tempo real com anexos (bucket privado, URL assinada)
- Casos: proposta pelo advogado, aceite pelo cliente, atualizações
- **Andamento processual automático** via DataJud/CNJ: número do processo,
  linha do tempo traduzida (inclusive audiência marcada, remarcada e
  cancelada) e notificação quando o processo anda
  ([docs/andamento-processual.md](docs/andamento-processual.md))
- Notificações: sino em tempo real, push (FCM), toque abre o destino,
  retenção automática ([docs/notificacoes.md](docs/notificacoes.md))
- Agenda do advogado: CRUD, lembretes e feed `.ics` assinável
- Verificação de advogado (OAB) e de escritório, com upload real e recusa
- Escritório: equipe, convites, papéis, indicação de advogado, painel
- Localização: distância até o escritório calculada no aparelho
- Avaliações reais, só após caso aceito, sem autoavaliação
- Destaque pago na descoberta, sempre sinalizado
- IA de triagem rule-based local + arquitetura para LLM
  ([docs/ai-intake.md](docs/ai-intake.md))
- Tema escuro com preferência persistida; identidade visual aplicada
- Exclusão de conta (LGPD) via Edge Function
- Testes: `flutter test` e suíte pgTAP do banco

### Em desenvolvimento / pendente

- **Publicação nas lojas**: o app ainda usa assinatura de depuração e não tem
  CI de build. É o que bloqueia o lançamento.
- Aprovação de OAB/escritório é manual pelo painel do Supabase; tela de
  revisão fica para o futuro webapp
- Revisão jurídica final dos Termos de Uso e da Política de Privacidade
- Push no iOS depende de conta Apple Developer paga (APNs); Android funciona
- Adoção do andamento processual: hoje o advogado só encontra o campo do
  número se abrir o caso e reparar
- Pendências de segurança/LGPD em [docs/security.md](docs/security.md)

### Planejado

- Integração com OAB (CNA)
- IA de triagem com LLM via Edge Function
- Cobrança do destaque pago (gateway, preço, tela de contratação)
- Videoconferência, assinatura digital
- Dashboards do escritório

---

## 🎯 Visão

A Jurii nasce com a missão de modernizar a relação entre clientes e profissionais do Direito, utilizando tecnologia para tornar o acesso à justiça mais simples, eficiente e transparente.

Buscamos construir a principal plataforma jurídica digital do Brasil, conectando pessoas e profissionais por meio de uma experiência moderna e confiável.

---

## 👥 Equipe

Fundada por estudantes e empreendedores com foco em inovação, tecnologia e transformação digital do setor jurídico.

---

## 📄 Licença

Copyright © 2026 Jurii.

Software proprietário e confidencial.

Todos os direitos reservados.

Nenhuma parte deste software pode ser reproduzida, distribuída, modificada ou utilizada sem autorização prévia dos proprietários do projeto.

---

## 🌐 Website

[jurii.com.br](https://jurii.com.br) — site institucional no ar, com lista de
espera. Código no repositório `jurii-site` (estático, sem build).

---

## 📧 Contato

Em breve.
