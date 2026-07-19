enum LegalDocumentType { privacyPolicy, termsOfUse }

class LegalDocument {
  const LegalDocument({
    required this.type,
    required this.title,
    required this.updatedAt,
    required this.summary,
    required this.sections,
  });

  final LegalDocumentType type;
  final String title;
  final String updatedAt;
  final String summary;
  final List<LegalDocumentSection> sections;
}

class LegalDocumentSection {
  const LegalDocumentSection({required this.title, required this.body});

  final String title;
  final List<String> body;
}

LegalDocument legalDocumentFor(LegalDocumentType type) {
  return switch (type) {
    LegalDocumentType.privacyPolicy => privacyPolicyDocument,
    LegalDocumentType.termsOfUse => termsOfUseDocument,
  };
}

const privacyPolicyDocument = LegalDocument(
  type: LegalDocumentType.privacyPolicy,
  title: 'Política de Privacidade',
  updatedAt: 'Atualizada em 18/07/2026',
  summary:
      'Esta política explica como a Jurii trata dados pessoais no app, '
      'incluindo cadastro, triagem, conversas, documentos e verificações.',
  sections: [
    LegalDocumentSection(
      title: '1. Quem somos',
      body: [
        'A Jurii é uma plataforma digital que aproxima pessoas que precisam de '
            'apoio jurídico de advogados e escritórios. Para operar essa '
            'intermediação, tratamos dados pessoais de clientes, profissionais '
            'e representantes de escritórios.',
        'Esta versão inicial é disponibilizada dentro do app para dar '
            'transparência ao usuário e deve ser revisada periodicamente pelo '
            'responsável jurídico e pelo responsável de privacidade da empresa.',
      ],
    ),
    LegalDocumentSection(
      title: '2. Dados que podemos tratar',
      body: [
        'Dados de cadastro e autenticação, como nome, e-mail, telefone, CPF, '
            'senha criptografada, provedores sociais usados no login e dados '
            'técnicos da sessão.',
        'Dados de perfil profissional, como OAB, áreas de atuação, vínculo com '
            'escritório, fotos escolhidas para perfis pessoais ou de escritório, '
            'documentos de verificação, CNPJ e dados do responsável legal quando '
            'aplicável.',
        'Dados de uso do serviço, como relatos jurídicos, respostas da triagem, '
            'categorias sugeridas, conversas, anexos, documentos enviados, '
            'casos, solicitações, reuniões e notificações.',
        'Dados técnicos e de segurança, como registros de erro, identificadores '
            'de dispositivo, metadados de upload e eventos necessários para '
            'prevenir abuso, fraude ou acesso indevido.',
      ],
    ),
    LegalDocumentSection(
      title: '3. Para que usamos os dados',
      body: [
        'Criar e proteger a conta do usuário, autenticar acessos e manter a '
            'segurança da plataforma.',
        'Permitir a triagem inicial do caso, organizar o relato do usuário, '
            'sugerir áreas jurídicas prováveis e facilitar a busca por '
            'advogados ou escritórios.',
        'Viabilizar conversas, envio de documentos, acompanhamento de casos, '
            'reuniões e notificações entre usuários e profissionais escolhidos.',
        'Analisar verificações de advogados e escritórios, prevenir perfis '
            'falsos e cumprir obrigações legais ou regulatórias aplicáveis.',
        'Melhorar o produto, corrigir falhas, gerar métricas agregadas e manter '
            'registros necessários para exercício regular de direitos.',
      ],
    ),
    LegalDocumentSection(
      title: '4. Bases legais',
      body: [
        'Tratamos dados pessoais conforme as bases legais previstas na LGPD, '
            'incluindo execução de contrato ou procedimentos preliminares, '
            'cumprimento de obrigação legal, exercício regular de direitos, '
            'legítimo interesse, proteção da vida ou da incolumidade física e '
            'consentimento quando ele for exigido.',
        'Quando o relato do caso ou os documentos contiverem dados sensíveis, '
            'adotamos medidas adicionais de segurança e limitamos o acesso aos '
            'profissionais, escritórios, operadores e sistemas necessários para '
            'prestar o serviço.',
      ],
    ),
    LegalDocumentSection(
      title: '5. Compartilhamento',
      body: [
        'Compartilhamos dados com advogados ou escritórios quando isso for '
            'necessário para o atendimento solicitado pelo usuário ou para a '
            'análise de uma solicitação de caso.',
        'Fotos escolhidas como avatar são públicas e podem aparecer em cards, '
            'perfis e conversas. A foto opcional de um escritório só é '
            'associada ao perfil da organização depois da aprovação do cadastro.',
        'Também usamos provedores de tecnologia, autenticação, banco de dados, '
            'armazenamento, notificações e observabilidade. Esses operadores '
            'devem tratar os dados conforme nossas instruções e medidas de '
            'segurança.',
        'Podemos compartilhar informações com autoridades públicas, judiciais, '
            'administrativas ou regulatórias quando houver obrigação legal, '
            'ordem válida ou necessidade de defesa de direitos.',
      ],
    ),
    LegalDocumentSection(
      title: '6. Inteligência artificial e triagem',
      body: [
        'A triagem automatizada ajuda a organizar informações, sugerir áreas '
            'jurídicas e indicar documentos úteis. Ela não substitui a análise '
            'de um advogado e não deve ser interpretada como parecer jurídico.',
        'O usuário deve revisar as informações antes de enviá-las a um '
            'profissional. Em situações de risco imediato, o app pode exibir '
            'orientações de segurança e canais públicos de emergência.',
      ],
    ),
    LegalDocumentSection(
      title: '7. Retenção e exclusão',
      body: [
        'Mantemos dados enquanto a conta estiver ativa e pelo tempo necessário '
            'para prestar o serviço, cumprir obrigações legais, prevenir fraude '
            'e exercer direitos em processos administrativos, judiciais ou '
            'arbitrais.',
        'Quando o usuário solicita exclusão de conta, removemos dados sensíveis '
            'de verificação e o avatar pessoal, fazemos o soft-delete da conta, '
            'banimos o usuário no Auth e registramos auditoria técnica. O avatar '
            'de um escritório já aprovado pode permanecer ligado à organização '
            'quando ela continuar ativa sob outro responsável.',
        'Anexos de chat e documentos de caso podem ser preservados quando '
            'necessários como prova, evidência, histórico do atendimento ou '
            'cumprimento de obrigação legal. Essa retenção deve seguir política '
            'específica de retenção documental.',
      ],
    ),
    LegalDocumentSection(
      title: '8. Seus direitos',
      body: [
        'Você pode solicitar confirmação de tratamento, acesso, correção, '
            'anonimização, bloqueio, eliminação, portabilidade, informação '
            'sobre compartilhamentos, revisão de decisões automatizadas e '
            'revogação de consentimento, conforme a LGPD.',
        'Alguns pedidos podem depender de validação de identidade e podem ser '
            'limitados quando houver obrigação legal, sigilo profissional, '
            'preservação de prova ou exercício regular de direitos.',
      ],
    ),
    LegalDocumentSection(
      title: '9. Segurança',
      body: [
        'Aplicamos autenticação, políticas de acesso, RLS no banco, buckets '
            'privados quando necessário, URLs assinadas para anexos sensíveis e '
            'restrições de privilégio para reduzir exposição indevida.',
        'Nenhum sistema é totalmente imune a incidentes. Caso identifiquemos '
            'risco relevante aos titulares, adotaremos medidas de contenção, '
            'investigação e comunicação compatíveis com a lei aplicável.',
      ],
    ),
    LegalDocumentSection(
      title: '10. Canal de privacidade',
      body: [
        'Pedidos sobre dados pessoais devem ser enviados pelos canais de '
            'suporte da Jurii disponíveis no app. Antes da publicação nas lojas, '
            'a empresa deve indicar o canal oficial do titular e, quando '
            'aplicável, o encarregado pelo tratamento de dados pessoais.',
      ],
    ),
  ],
);

const termsOfUseDocument = LegalDocument(
  type: LegalDocumentType.termsOfUse,
  title: 'Termos de Uso',
  updatedAt: 'Atualizados em 06/07/2026',
  summary:
      'Estes termos definem as regras básicas para usar a Jurii, incluindo '
      'conta, triagem, conversas, documentos, profissionais e limitações.',
  sections: [
    LegalDocumentSection(
      title: '1. Aceitação',
      body: [
        'Ao criar uma conta, acessar ou usar a Jurii, você concorda com estes '
            'Termos de Uso e com a Política de Privacidade.',
        'Se você não concordar com as regras, não utilize o app. Podemos '
            'atualizar estes termos para refletir mudanças do produto, da lei '
            'ou de práticas de segurança.',
      ],
    ),
    LegalDocumentSection(
      title: '2. O que a Jurii faz',
      body: [
        'A Jurii é uma plataforma de tecnologia para organizar relatos, '
            'facilitar triagens e aproximar usuários de advogados ou '
            'escritórios.',
        'A Jurii não substitui atendimento jurídico individualizado, não presta '
            'consultoria jurídica própria e não garante resultado em processos, '
            'negociações ou atendimentos.',
      ],
    ),
    LegalDocumentSection(
      title: '3. Conta e responsabilidades',
      body: [
        'Você deve fornecer informações verdadeiras, manter seus dados '
            'atualizados e proteger suas credenciais de acesso.',
        'Você é responsável pelo conteúdo que envia, incluindo relatos, '
            'documentos, mensagens e informações compartilhadas com '
            'profissionais.',
        'Contas podem ser suspensas, limitadas ou excluídas em caso de fraude, '
            'uso abusivo, violação destes termos, ordem legal ou risco à '
            'segurança da plataforma.',
      ],
    ),
    LegalDocumentSection(
      title: '4. Advogados e escritórios',
      body: [
        'Perfis profissionais e escritórios podem depender de verificação de '
            'dados, documentos, OAB, CNPJ, vínculo e autoridade do responsável.',
        'A aprovação de cadastro profissional não é endosso de resultado, '
            'qualidade, disponibilidade ou estratégia jurídica. O usuário deve '
            'avaliar o profissional escolhido antes de contratar.',
        'Advogados e escritórios são responsáveis por cumprir deveres '
            'profissionais, éticos, legais e de sigilo aplicáveis à sua atuação.',
      ],
    ),
    LegalDocumentSection(
      title: '5. Triagem e inteligência artificial',
      body: [
        'A triagem automatizada pode sugerir áreas jurídicas, perguntas e '
            'documentos, mas serve apenas como apoio organizacional.',
        'As respostas da triagem podem conter imprecisões ou não captar toda a '
            'complexidade do caso. A análise final deve ser feita por '
            'profissional habilitado.',
        'Em situações urgentes, como violência, risco físico ou prisão, procure '
            'imediatamente autoridades públicas, serviços de emergência ou '
            'assistência jurídica adequada.',
      ],
    ),
    LegalDocumentSection(
      title: '6. Contratação e atendimento',
      body: [
        'Qualquer contratação, honorário, prazo, estratégia, documento ou '
            'atendimento combinado entre usuário e profissional é de '
            'responsabilidade das partes envolvidas.',
        'A Jurii pode facilitar comunicação e organização de informações, mas '
            'não se torna parte automática de contrato de honorários ou de '
            'relação advogado-cliente fora do que for expressamente informado.',
      ],
    ),
    LegalDocumentSection(
      title: '7. Uso permitido',
      body: [
        'É proibido usar a Jurii para fraude, spam, assédio, ameaça, violação de '
            'sigilo, envio de malware, falsidade ideológica, tentativa de acesso '
            'indevido ou qualquer finalidade ilícita.',
        'Também é proibido tentar burlar verificações, manipular dados de '
            'perfil, acessar conversas/casos de terceiros ou explorar falhas de '
            'segurança.',
      ],
    ),
    LegalDocumentSection(
      title: '8. Documentos e evidências',
      body: [
        'Você deve enviar apenas documentos que tenha direito de compartilhar e '
            'que sejam pertinentes ao atendimento.',
        'Anexos, conversas e documentos podem ser preservados quando necessários '
            'para histórico, prova, evidência, defesa de direitos ou obrigação '
            'legal, mesmo após pedido de exclusão de conta.',
      ],
    ),
    LegalDocumentSection(
      title: '9. Exclusão de conta',
      body: [
        'Você pode solicitar exclusão de conta pelo app. A rotina remove dados '
            'sensíveis de verificação e o avatar pessoal, desativa dados pessoais '
            'de perfil e bane o usuário no Auth para impedir novo acesso pela '
            'mesma conta. O avatar de escritório já aprovado pode ser preservado '
            'como dado da organização quando ela continuar ativa.',
        'Alguns registros podem ser mantidos quando necessários por lei, '
            'segurança, auditoria, prevenção de fraude, evidência ou exercício '
            'regular de direitos.',
      ],
    ),
    LegalDocumentSection(
      title: '10. Limitação de responsabilidade',
      body: [
        'A Jurii trabalha para manter o app disponível e seguro, mas não garante '
            'operação ininterrupta, ausência total de erros ou compatibilidade '
            'com todos os dispositivos.',
        'Na máxima extensão permitida pela lei, a Jurii não responde por danos '
            'decorrentes de informações falsas fornecidas por usuários, atos de '
            'terceiros, indisponibilidade de redes externas ou decisões tomadas '
            'sem validação profissional adequada.',
      ],
    ),
    LegalDocumentSection(
      title: '11. Contato',
      body: [
        'Dúvidas sobre estes termos devem ser enviadas pelos canais de suporte '
            'disponíveis no app. Antes da publicação nas lojas, a empresa deve '
            'indicar o canal oficial de atendimento e privacidade.',
      ],
    ),
  ],
);
