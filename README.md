# ⚖️ Jurii

Jurii é uma plataforma digital desenvolvida para conectar clientes, advogados e escritórios de advocacia em um único ecossistema moderno, seguro e intuitivo.

Nosso objetivo é simplificar o acesso a serviços jurídicos, tornando a contratação, comunicação e gestão de atendimentos mais acessíveis, transparentes e eficientes.

---

## 🚀 Funcionalidades

### 👤 Para Clientes

- Cadastro e autenticação de usuários
- Busca de advogados e escritórios
- Acompanhamento de casos
- Sistema de mensagens
- Agendamento de reuniões
- Gerenciamento de documentos
- Perfil personalizado

### ⚖️ Para Advogados

- Solicitação de ativação profissional
- Verificação documental
- Perfil profissional validado
- Gerenciamento de clientes
- Controle de atendimentos
- Comunicação direta com clientes
- Área exclusiva para profissionais

### 🏢 Para Escritórios

- Gestão de equipes jurídicas
- Administração de profissionais vinculados
- Organização de atendimentos
- Controle de processos internos
- Gestão centralizada de clientes

---

## 🏗️ Arquitetura do Projeto

```text
lib/
├── data/           # dados estáticos reais (+ data/mock para modo demo)
├── models/         # entidades imutáveis
├── repositories/   # acesso a Supabase (tabelas + RPCs)
├── screens/        # telas
├── services/       # infraestrutura (SupabaseConfig, IntakeAIService)
├── theme/          # AppTheme, AppColors (dark mode), ThemeController
├── utils/          # helpers puros (validators)
└── widgets/        # componentes reutilizáveis
```

Detalhes em [docs/architecture.md](docs/architecture.md).

---

## 📱 Tecnologias Utilizadas

- Flutter / Dart
- Supabase (PostgreSQL, Auth, Storage, Realtime, RPCs)
- RLS (Row Level Security) em todas as tabelas

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

### Configurar o Supabase do zero

1. Crie um projeto no Supabase.
2. Rode `supabase link --project-ref SEU_PROJECT_REF`.
3. Confira o estado do ambiente com `supabase migration list --linked`.
4. Aplique a baseline consolidada e as migrations incrementais com
   `supabase db push`.
5. Publique a Edge Function LGPD com
   `supabase functions deploy delete-account`.

Os antigos `patch_001...045` foram arquivados em
`supabase/legacy_patches/`. Para setup novo, use o conjunto versionado em
`supabase/migrations/`; detalhes em `supabase/README.md`.

A `service_role key` **nunca** entra no app ou no repositório.

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
- Foto profissional

Após o envio, a documentação é analisada pela equipe da Jurii antes da liberação do modo profissional.

---

## 📌 Status do Projeto

🚧 Em desenvolvimento

### Implementado

- Autenticação (e-mail/senha, Google/Apple OAuth, reset de senha)
- Banco Supabase completo com RLS (baseline consolidada + migrations incrementais)
- Busca inteligente: termo leigo → área do direito (servidor + fallback local)
- Mensagens em tempo real com anexos (bucket privado, URL assinada)
- Casos: solicitação pelo advogado, aceite pelo cliente, atualizações
- Fluxo de verificação de advogado (OAB) e de escritório
- Workspace de escritório: equipe, convites com aceite, papéis, delegação
- Notificações com realtime
- IA de triagem (intake) rule-based local + arquitetura para LLM
  ([docs/ai-intake.md](docs/ai-intake.md))
- Tema escuro ativo, com preferência persistida
- Upload real de documentos de verificação, validação e ciclo de recusa
- Avaliações reais, liberadas somente após caso aceito
- Recomendações de advogados por escritórios
- Testes (`flutter test`)

### Em desenvolvimento / pendente

- Aprovação de OAB/escritório manual pelo Supabase durante a fase apenas-app;
  página revisora será construída no futuro webapp
- Revisão jurídica final dos Termos de Uso e da Política de Privacidade
- Consentimento, canal do titular/DPO e política de retenção documental
- Pendências de segurança/LGPD listadas em [docs/security.md](docs/security.md)

### Planejado

- Integração com OAB (CNA)
- IA de triagem com LLM via Edge Function
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

Em breve.

---

## 📧 Contato

Em breve.
