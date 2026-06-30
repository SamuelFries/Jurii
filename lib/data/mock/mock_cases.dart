import '../../models/case_request.dart';
import '../../models/case_update.dart';
import '../../models/cases.dart';
import '../../models/lawyer_case.dart';

const List<LegalCase> mockClientCases = [
  LegalCase(
    id: 'client_case_01',
    title: 'Rescisao trabalhista',
    area: 'Direito Trabalhista',
    status: 'Em andamento',
    lastUpdate: 'Nova atualizacao hoje',
  ),
  LegalCase(
    id: 'client_case_02',
    title: 'Divorcio consensual',
    area: 'Direito de Familia',
    status: 'Aguardando documentos',
    lastUpdate: 'Reuniao amanha',
  ),
  LegalCase(
    id: 'client_case_03',
    title: 'Cobranca indevida',
    area: 'Direito do Consumidor',
    status: 'Analise inicial',
    lastUpdate: 'Orcamento recebido',
  ),
  LegalCase(
    id: 'client_case_04',
    title: 'Contrato de locacao',
    area: 'Direito Imobiliario',
    status: 'Minuta em revisao',
    lastUpdate: 'Atualizado ha 2h',
  ),
];

const List<LawyerCase> mockLawyerCases = [
  LawyerCase(
    id: 'caso_01',
    title: 'Rescisao trabalhista',
    clientName: 'Joao Silva',
    clientInitials: 'JS',
    area: 'Trabalhista',
    lastUpdate: 'Nova mensagem ha 12 min',
    status: LawyerCaseStatus.newMessage,
  ),
  LawyerCase(
    id: 'caso_02',
    title: 'Inventario familiar',
    clientName: 'Marina Costa',
    clientInitials: 'MC',
    area: 'Familia',
    lastUpdate: 'Prazo em 2 dias',
    status: LawyerCaseStatus.deadline,
  ),
  LawyerCase(
    id: 'caso_03',
    title: 'Revisao contratual',
    clientName: 'Tech Nova',
    clientInitials: 'TN',
    area: 'Empresarial',
    lastUpdate: 'Atualizado hoje',
    status: LawyerCaseStatus.updated,
  ),
  LawyerCase(
    id: 'caso_04',
    title: 'Cobranca indevida',
    clientName: 'Beatriz Ramos',
    clientInitials: 'BR',
    area: 'Consumidor',
    lastUpdate: 'Cliente enviou comprovantes',
    status: LawyerCaseStatus.newMessage,
  ),
  LawyerCase(
    id: 'caso_05',
    title: 'Contrato de aluguel',
    clientName: 'Fernanda Lima',
    clientInitials: 'FL',
    area: 'Imobiliario',
    lastUpdate: 'Aguardando contraproposta',
    status: LawyerCaseStatus.updated,
  ),
  LawyerCase(
    id: 'caso_06',
    title: 'Planejamento societario',
    clientName: 'Studio Bento',
    clientInitials: 'SB',
    area: 'Empresarial',
    lastUpdate: 'Assinatura ate sexta',
    status: LawyerCaseStatus.deadline,
  ),
];

const List<CaseRequest> mockClientCaseRequests = [
  CaseRequest(
    id: 'request_demo_01',
    conversationId: 'mock_conversation_fries',
    title: 'Analise de verbas rescisorias',
    area: 'Direito Trabalhista',
    summary:
        'O escritorio analisou a conversa inicial e pediu aceite para abrir o caso.',
    requestedBy: 'Fries Advogados',
    requesterInitials: 'FA',
    createdAtLabel: 'Hoje',
  ),
  CaseRequest(
    id: 'request_demo_02',
    conversationId: 'mock_conversation_silva',
    title: 'Acordo de guarda e alimentos',
    area: 'Direito de Familia',
    summary:
        'A equipe preparou uma proposta de atendimento para organizar documentos e prazos.',
    requestedBy: 'Silva & Associados',
    requesterInitials: 'SA',
    createdAtLabel: 'Ontem',
  ),
];

const List<CaseUpdate> mockCaseUpdates = [
  CaseUpdate(
    id: 'update_demo_01',
    caseId: 'client_case_01',
    title: 'Triagem concluida',
    body:
        'Documentos principais recebidos. Proxima etapa e calcular verbas e preparar notificacao.',
    authorName: 'Dra. Marina Jardim',
    authorInitials: 'MJ',
    createdAtLabel: 'Hoje',
  ),
  CaseUpdate(
    id: 'update_demo_02',
    caseId: 'client_case_01',
    title: 'Audiencia sinalizada',
    body:
        'Incluimos uma tarefa interna para separar comprovantes antes da audiencia de conciliacao.',
    authorName: 'Dr. Rafael Lima',
    authorInitials: 'RL',
    createdAtLabel: 'Ontem',
  ),
  CaseUpdate(
    id: 'update_demo_03',
    caseId: 'caso_02',
    title: 'Prazo mapeado',
    body:
        'O inventario foi marcado como prioritario porque depende de certidao atualizada.',
    authorName: 'Joao Silva',
    authorInitials: 'JS',
    createdAtLabel: '2d',
  ),
];
