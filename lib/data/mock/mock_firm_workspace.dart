import '../../models/conversation.dart';
import '../../models/firm_case_overview.dart';
import '../../models/firm_role.dart';
import '../../models/firm_team_member.dart';

const mockFirmWorkspaceName = 'Fries Advogados';

const mockFirmMetrics = (
  clientMessages: 7,
  teamMessages: 4,
  activeCases: 12,
  teamMembers: 6,
);

const mockFirmClientConversations = [
  Conversation(
    initials: 'AP',
    officeName: 'Ana Pereira',
    specialty: 'Cliente - Direito de Família',
    lastMessage: 'Enviei a certidão atualizada para o escritório.',
    time: '09:18',
    unreadCount: 2,
  ),
  Conversation(
    initials: 'CO',
    officeName: 'Carlos Oliveira',
    specialty: 'Cliente - Previdenciário',
    lastMessage: 'Conseguem confirmar minha reunião de hoje?',
    time: '08:40',
    unreadCount: 1,
  ),
  Conversation(
    initials: 'FL',
    officeName: 'Fernanda Lima',
    specialty: 'Cliente - Imobiliário',
    lastMessage: 'Recebi o orçamento. Posso falar com a Dra. Marina?',
    time: 'Ontem',
    unreadCount: 0,
  ),
];

const mockFirmTeamConversations = [
  Conversation(
    initials: 'MJ',
    officeName: 'Dra. Marina Jardim',
    specialty: 'Advogada associada - Família',
    lastMessage: 'O caso da Ana já está pronto para minuta.',
    time: '09:05',
    unreadCount: 1,
  ),
  Conversation(
    initials: 'RL',
    officeName: 'Dr. Rafael Lima',
    specialty: 'Advogado associado - Trabalhista',
    lastMessage: 'Preciso que a secretaria confirme os documentos.',
    time: '08:22',
    unreadCount: 2,
  ),
  Conversation(
    initials: 'CS',
    officeName: 'Carla Souza',
    specialty: 'Secretaria - Atendimento',
    lastMessage: 'As reuniões da tarde foram remarcadas.',
    time: 'Ontem',
    unreadCount: 0,
  ),
];

const mockFirmTeamMembers = [
  FirmTeamMember(
    id: 'member_marina',
    name: 'Dra. Marina Jardim',
    initials: 'MJ',
    role: FirmRole.lawyer,
    roles: [FirmRole.lawyer],
    specialty: 'Família',
    activeCases: 5,
    responseHours: 1.4,
    rating: 4.9,
    available: true,
  ),
  FirmTeamMember(
    id: 'member_rafael',
    name: 'Dr. Rafael Lima',
    initials: 'RL',
    role: FirmRole.lawyer,
    roles: [FirmRole.admin, FirmRole.lawyer],
    specialty: 'Trabalhista',
    activeCases: 4,
    responseHours: 2.1,
    rating: 4.8,
    available: true,
  ),
  FirmTeamMember(
    id: 'member_carla',
    name: 'Carla Souza',
    initials: 'CS',
    role: FirmRole.secretary,
    roles: [FirmRole.secretary],
    specialty: 'Atendimento',
    activeCases: 0,
    responseHours: 0.8,
    rating: 4.7,
    available: true,
  ),
  FirmTeamMember(
    id: 'member_eduardo',
    name: 'Eduardo Martins',
    initials: 'EM',
    role: FirmRole.admin,
    roles: [FirmRole.admin],
    specialty: 'Operações',
    activeCases: 0,
    responseHours: 1.0,
    rating: 4.8,
    available: false,
  ),
  FirmTeamMember(
    id: 'member_luiza',
    name: 'Luiza Campos',
    initials: 'LC',
    role: FirmRole.intern,
    roles: [FirmRole.intern],
    specialty: 'Apoio interno',
    activeCases: 0,
    responseHours: 2.6,
    rating: 4.6,
    available: true,
  ),
];

const mockFirmCases = [
  FirmCaseOverview(
    id: 'firm_case_01',
    title: 'Divórcio consensual',
    clientName: 'Ana Pereira',
    clientInitials: 'AP',
    assignedLawyer: 'Dra. Marina Jardim',
    area: 'Família',
    statusLabel: 'Minuta em revisão',
    nextStep: 'Enviar minuta até hoje',
    urgent: false,
  ),
  FirmCaseOverview(
    id: 'firm_case_02',
    title: 'Rescisão trabalhista',
    clientName: 'João Silva',
    clientInitials: 'JS',
    assignedLawyer: 'Dr. Rafael Lima',
    area: 'Trabalhista',
    statusLabel: 'Prazo crítico',
    nextStep: 'Protocolar em 24h',
    urgent: true,
  ),
  FirmCaseOverview(
    id: 'firm_case_03',
    title: 'Revisão de contrato',
    clientName: 'Fernanda Lima',
    clientInitials: 'FL',
    assignedLawyer: 'Dra. Marina Jardim',
    area: 'Imobiliário',
    statusLabel: 'Aguardando cliente',
    nextStep: 'Confirmar cláusula de reajuste',
    urgent: false,
  ),
];
