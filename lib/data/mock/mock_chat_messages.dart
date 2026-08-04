import '../../models/chat_message.dart';

const mockChatMessages = [
  ChatMessage(
    id: 'chat_fries_01',
    conversationKey: 'Fries Advogados',
    author: MessageAuthor.other,
    text:
        'Olá, João. Recebemos sua solicitação e podemos ajudar com a análise trabalhista.',
    time: '09:04',
  ),
  ChatMessage(
    id: 'chat_fries_02',
    conversationKey: 'Fries Advogados',
    author: MessageAuthor.me,
    text: 'Perfeito. Quais documentos preciso enviar primeiro?',
    time: '09:07',
  ),
  ChatMessage(
    id: 'chat_fries_03',
    conversationKey: 'Fries Advogados',
    author: MessageAuthor.other,
    text:
        'Contrato, últimos contracheques e a comunicação de desligamento já são suficientes para começar.',
    time: '09:10',
  ),
  ChatMessage(
    id: 'chat_ana_01',
    conversationKey: 'Ana Pereira',
    author: MessageAuthor.other,
    text: 'Bom dia, Dr. João. Enviei os documentos para análise.',
    time: '09:12',
    status: MessageDeliveryStatus.sent,
  ),
  ChatMessage(
    id: 'chat_ana_02',
    conversationKey: 'Ana Pereira',
    author: MessageAuthor.me,
    text:
        'Recebi, Ana. Vou revisar ainda hoje e retorno com os próximos passos.',
    time: '09:16',
  ),
  ChatMessage(
    id: 'chat_ana_03',
    conversationKey: 'Ana Pereira',
    author: MessageAuthor.other,
    text:
        'Obrigada. Também gostaria de confirmar se a reunião das 9h30 está mantida.',
    time: '09:18',
    status: MessageDeliveryStatus.sent,
  ),
  ChatMessage(
    id: 'chat_carlos_01',
    conversationKey: 'Carlos Oliveira',
    author: MessageAuthor.other,
    text: 'Podemos agendar uma conversa hoje?',
    time: '08:40',
    status: MessageDeliveryStatus.sent,
  ),
  ChatMessage(
    id: 'chat_carlos_02',
    conversationKey: 'Carlos Oliveira',
    author: MessageAuthor.me,
    text: 'Sim. Tenho disponibilidade às 16h30.',
    time: '08:46',
  ),
  ChatMessage(
    id: 'chat_silva_01',
    conversationKey: 'Silva & Associados',
    author: MessageAuthor.other,
    text: 'Sua reunião foi confirmada para amanhã às 10h.',
    time: 'Ontem',
  ),
  ChatMessage(
    id: 'chat_silva_02',
    conversationKey: 'Silva & Associados',
    author: MessageAuthor.me,
    text: 'Obrigado. Vou separar os documentos solicitados.',
    time: 'Ontem',
  ),
  ChatMessage(
    id: 'chat_firm_marina_01',
    conversationKey: 'Dra. Marina Jardim',
    author: MessageAuthor.other,
    text: 'O caso da Ana já está pronto para minuta.',
    time: '09:05',
  ),
  ChatMessage(
    id: 'chat_firm_marina_02',
    conversationKey: 'Dra. Marina Jardim',
    author: MessageAuthor.me,
    text: 'Perfeito. Pode enviar para revisão da secretaria antes das 14h.',
    time: '09:08',
  ),
  ChatMessage(
    id: 'chat_firm_rafael_01',
    conversationKey: 'Dr. Rafael Lima',
    author: MessageAuthor.other,
    text: 'Preciso que a secretaria confirme os documentos trabalhistas.',
    time: '08:22',
    status: MessageDeliveryStatus.sent,
  ),
  ChatMessage(
    id: 'chat_firm_carla_01',
    conversationKey: 'Carla Souza',
    author: MessageAuthor.other,
    text: 'As reuniões da tarde foram remarcadas e os clientes avisados.',
    time: 'Ontem',
  ),
  ChatMessage(
    id: 'chat_firm_fernanda_01',
    conversationKey: 'Fernanda Lima',
    author: MessageAuthor.other,
    text: 'Recebi o orçamento. Posso falar com a Dra. Marina?',
    time: 'Ontem',
  ),
];
