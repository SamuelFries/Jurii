import '../../models/cases.dart';
import '../../models/lawyer_case.dart';

const List<LegalCase> mockClientCases = [];

const List<LawyerCase> mockLawyerCases = [
  LawyerCase(
    id: 'caso_01',
    title: 'Rescisão trabalhista',
    clientName: 'João Silva',
    clientInitials: 'JS',
    area: 'Trabalhista',
    lastUpdate: 'Nova mensagem há 12 min',
    status: LawyerCaseStatus.newMessage,
  ),
  LawyerCase(
    id: 'caso_02',
    title: 'Inventário familiar',
    clientName: 'Marina Costa',
    clientInitials: 'MC',
    area: 'Família',
    lastUpdate: 'Prazo em 2 dias',
    status: LawyerCaseStatus.deadline,
  ),
  LawyerCase(
    id: 'caso_03',
    title: 'Revisão contratual',
    clientName: 'Tech Nova',
    clientInitials: 'TN',
    area: 'Empresarial',
    lastUpdate: 'Atualizado hoje',
    status: LawyerCaseStatus.updated,
  ),
];
