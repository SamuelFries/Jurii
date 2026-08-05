import '../models/chat_message.dart';

/// Janela para "apagar para todos", igual à referência do WhatsApp: 2 dias e
/// meio depois do envio.
///
/// O prazo existe porque apagar para todos reescreve o que a outra pessoa já
/// leu. Sem ele, daria para apagar uma promessa de um mês atrás no dia em que
/// ela virasse problema — e aqui a conversa é registro da relação entre
/// cliente e advogado, o que torna isso mais grave que num aplicativo de
/// mensagens comum, não menos.
///
/// Espelha `interval '60 hours'` da migration 20260808120000. Quem decide de
/// verdade é o servidor; isto existe para não oferecer um botão que vai falhar.
const Duration kDeleteForEveryoneWindow = Duration(hours: 60);

/// Mensagem que pode entrar no modo de seleção.
///
/// Cartão de solicitação de caso e sugestão de advogado ficam de fora: são
/// controles com botões próprios, não conversa. Deixá-los selecionáveis
/// misturaria "tocar para aceitar o caso" com "tocar para marcar", que é o
/// tipo de ambiguidade que faz alguém recusar um caso sem querer.
bool canSelectMessage(ChatMessage message) {
  if (message.isCaseRequest) return false;
  if (message.lawyerRecommendation != null) return false;
  return true;
}

/// "Apagar para mim" vale para qualquer mensagem visível: some da minha tela e
/// de mais lugar nenhum.
bool canDeleteForMe(ChatMessage message) => canSelectMessage(message);

/// "Apagar para todos" exige as quatro condições que o servidor também checa.
bool canDeleteForEveryone(ChatMessage message, {required DateTime now}) {
  if (!canSelectMessage(message)) return false;
  // Só o autor apaga para todos.
  if (message.author != MessageAuthor.me) return false;
  // Já apagada não se apaga de novo.
  if (message.deletedForAll) return false;

  final sentAt = message.createdAt;
  // Sem instante conhecido (mensagem local que ainda não voltou do servidor)
  // não dá para afirmar que está na janela — e afirmar de menos é melhor que
  // oferecer um botão que o servidor vai recusar.
  if (sentAt == null) return false;

  return !now.difference(sentAt).isNegative &&
      now.difference(sentAt) <= kDeleteForEveryoneWindow;
}

/// Todas as selecionadas podem ser apagadas para todos? O WhatsApp esconde a
/// opção quando UMA da seleção não pode — meio-apagar seria pior que não
/// oferecer.
bool canDeleteSelectionForEveryone(
  Iterable<ChatMessage> selection, {
  required DateTime now,
}) {
  if (selection.isEmpty) return false;
  return selection.every((message) => canDeleteForEveryone(message, now: now));
}
