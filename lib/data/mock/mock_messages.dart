import '../../models/conversation.dart';
import '../../models/lawyer_contact.dart';

const List<Conversation> mockClientConversations = [
  Conversation(
    initials: 'FA',
    officeName: 'Fries Advogados',
    specialty: 'Direito Trabalhista',
    lastMessage: 'Contrato e contracheques já são suficientes para começar.',
    time: '09:10',
    unreadCount: 1,
  ),
  Conversation(
    initials: 'SA',
    officeName: 'Silva & Associados',
    specialty: 'Direito de Família',
    lastMessage: 'Sua reunião foi confirmada para amanhã às 10h.',
    time: 'Ontem',
    unreadCount: 0,
  ),
];

const List<Conversation> mockLawyerConversations = [
  Conversation(
    initials: 'AP',
    officeName: 'Ana Pereira',
    specialty: 'Direito de Família',
    lastMessage: 'Enviei os documentos para análise.',
    time: '09:12',
    unreadCount: 2,
  ),
  Conversation(
    initials: 'CO',
    officeName: 'Carlos Oliveira',
    specialty: 'Previdenciário',
    lastMessage: 'Podemos agendar uma conversa hoje?',
    time: '08:40',
    unreadCount: 1,
  ),
];

const List<LawyerContact> mockLawyerContacts = [
  LawyerContact(
    id: 'contato_01',
    name: 'Ana Pereira',
    initials: 'AP',
    description: 'Solicitou atendimento em Direito de Família',
  ),
  LawyerContact(
    id: 'contato_02',
    name: 'Carlos Oliveira',
    initials: 'CO',
    description: 'Precisa de orientação previdenciária',
  ),
  LawyerContact(
    id: 'contato_03',
    name: 'Fernanda Lima',
    initials: 'FL',
    description: 'Busca revisão de contrato de locação',
  ),
];
