import '../../models/conversation.dart';
import '../../models/lawyer_contact.dart';

const List<Conversation> mockClientConversations = [
  Conversation(
    initials: 'FA',
    officeName: 'Fries Advogados',
    specialty: 'Direito Trabalhista',
    lastMessage: 'Contrato e contracheques ja sao suficientes para comecar.',
    time: '09:10',
    unreadCount: 1,
  ),
  Conversation(
    initials: 'SA',
    officeName: 'Silva & Associados',
    specialty: 'Direito de Familia',
    lastMessage: 'Sua reuniao foi confirmada para amanha as 10h.',
    time: 'Ontem',
    unreadCount: 0,
  ),
  Conversation(
    initials: 'MJ',
    officeName: 'Dra. Marina Jardim',
    specialty: 'Direito de Familia',
    lastMessage: 'Recebi os documentos e ja deixei a minuta encaminhada.',
    time: '11:24',
    unreadCount: 3,
    type: 'client_lawyer',
    lawyerId: 'lawyer_marina',
  ),
  Conversation(
    initials: 'MA',
    officeName: 'Moura Advogados',
    specialty: 'Direito do Consumidor',
    lastMessage: 'Podemos pedir restituicao em dobro nesse caso.',
    time: 'Seg',
    unreadCount: 0,
  ),
  Conversation(
    initials: 'LC',
    officeName: 'LexCorp Digital',
    specialty: 'Direito Digital',
    lastMessage: 'A notificacao extrajudicial ficou pronta para sua revisao.',
    time: 'Sex',
    unreadCount: 0,
  ),
];

const List<Conversation> mockLawyerConversations = [
  Conversation(
    initials: 'AP',
    officeName: 'Ana Pereira',
    specialty: 'Direito de Familia',
    lastMessage: 'Enviei os documentos para analise.',
    time: '09:12',
    unreadCount: 2,
  ),
  Conversation(
    initials: 'CO',
    officeName: 'Carlos Oliveira',
    specialty: 'Previdenciario',
    lastMessage: 'Podemos agendar uma conversa hoje?',
    time: '08:40',
    unreadCount: 1,
  ),
  Conversation(
    initials: 'BR',
    officeName: 'Beatriz Ramos',
    specialty: 'Direito do Consumidor',
    lastMessage: 'Enviei o comprovante da cobranca duplicada.',
    time: '10:48',
    unreadCount: 1,
  ),
  Conversation(
    initials: 'FL',
    officeName: 'Fernanda Lima',
    specialty: 'Direito Imobiliario',
    lastMessage: 'O proprietario aceitou revisar a multa.',
    time: 'Ontem',
    unreadCount: 0,
  ),
  Conversation(
    initials: 'TN',
    officeName: 'Tech Nova',
    specialty: 'Direito Empresarial',
    lastMessage: 'Precisamos fechar o acordo ate sexta.',
    time: '2d',
    unreadCount: 0,
  ),
];

const List<LawyerContact> mockLawyerContacts = [
  LawyerContact(
    id: 'contato_01',
    name: 'Ana Pereira',
    initials: 'AP',
    description: 'Solicitou atendimento em Direito de Familia',
  ),
  LawyerContact(
    id: 'contato_02',
    name: 'Carlos Oliveira',
    initials: 'CO',
    description: 'Precisa de orientacao previdenciaria',
  ),
  LawyerContact(
    id: 'contato_03',
    name: 'Fernanda Lima',
    initials: 'FL',
    description: 'Busca revisao de contrato de locacao',
  ),
  LawyerContact(
    id: 'contato_04',
    name: 'Beatriz Ramos',
    initials: 'BR',
    description: 'Cobranca indevida com urgencia em reembolso',
  ),
  LawyerContact(
    id: 'contato_05',
    name: 'Studio Bento',
    initials: 'SB',
    description: 'Precisa organizar contrato societario',
  ),
];
