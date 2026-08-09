/// A filtragem das listas de conversas e casos, fora das telas.
///
/// POR QUE PURO. Teste de tela injeta repositório falso e recebe a lista já
/// pronta, então nunca exercita a regra de filtragem de verdade. Aqui a regra
/// é exercitada direto, e cada função devolve UMA lista na mesma ordem que
/// entrou (a ordem certa já vem do servidor: conversas por last_message_at,
/// casos por updated_at).
///
/// O QUE NÃO ENTRA NA BUSCA, de propósito:
///
/// `Conversation.lastMessage`. A lista carrega só a ÚLTIMA mensagem de cada
/// conversa. Procurar "audiência" e ouvir "nenhum resultado" enquanto a
/// palavra existe no meio do histórico é filtro que enxerga um pedaço e fala
/// como se enxergasse tudo. Busca de conteúdo de mensagem é outra obra, com
/// índice no servidor.
///
/// `FirmCaseOverview.assignedLawyer` quando `assignedLawyerId` é nulo. Nesse
/// caso o servidor manda o rótulo "Sem advogado definido", que é texto de
/// interface e não gente: sem a checagem, digitar "sem" devolveria casos como
/// se existisse um advogado com esse nome.
library;

import '../models/case_request.dart';
import '../models/cases.dart';
import '../models/conversation.dart';
import '../models/firm_case_overview.dart';
import '../models/lawyer_case.dart';
import 'list_search.dart';

List<Conversation> filterConversations(
  List<Conversation> conversations, {
  String query = '',
  bool onlyUnread = false,
}) {
  return conversations.where((conversation) {
    if (onlyUnread && conversation.unreadCount == 0) return false;
    return searchTextMatches(query, [
      conversation.officeName,
      conversation.specialty,
    ]);
  }).toList(growable: false);
}

List<LegalCase> filterClientCases(
  List<LegalCase> cases, {
  String query = '',
  bool onlyOpen = false,
}) {
  return cases.where((legalCase) {
    if (onlyOpen && legalCase.isClosed) return false;
    return searchTextMatches(query, [
          legalCase.title,
          legalCase.area,
          legalCase.status,
        ]) ||
        cnjMatches(query, legalCase.cnjNumber);
  }).toList(growable: false);
}

/// As solicitações pendentes moram na mesma tela dos casos do cliente, então
/// obedecem à mesma busca. Sem isto, filtrar esconderia os casos e deixaria a
/// seção de solicitações intacta, como se ela ignorasse o que foi digitado.
List<CaseRequest> filterCaseRequests(
  List<CaseRequest> requests, {
  String query = '',
}) {
  return requests
      .where(
        (request) => searchTextMatches(query, [
          request.title,
          request.area,
          request.requestedBy,
        ]),
      )
      .toList(growable: false);
}

List<LawyerCase> filterLawyerCases(
  List<LawyerCase> cases, {
  String query = '',
  bool onlyOpen = false,
  bool onlyNewMessage = false,
}) {
  return cases.where((lawyerCase) {
    if (onlyOpen && lawyerCase.status == LawyerCaseStatus.closed) return false;
    if (onlyNewMessage && lawyerCase.status != LawyerCaseStatus.newMessage) {
      return false;
    }
    return searchTextMatches(query, [
          lawyerCase.clientName,
          lawyerCase.title,
          lawyerCase.area,
        ]) ||
        cnjMatches(query, lawyerCase.cnjNumber);
  }).toList(growable: false);
}

List<FirmCaseOverview> filterFirmCases(
  List<FirmCaseOverview> cases, {
  String query = '',
  bool onlyOpen = false,
  bool onlyUnassigned = false,
  bool onlyUrgent = false,
}) {
  return cases.where((overview) {
    if (onlyOpen && overview.isClosed) return false;
    if (onlyUnassigned && overview.assignedLawyerId != null) return false;
    if (onlyUrgent && !overview.urgent) return false;
    return searchTextMatches(query, [
          overview.clientName,
          overview.title,
          overview.area,
          // Só o nome de gente de verdade; ver a nota no topo do arquivo.
          if (overview.assignedLawyerId != null) overview.assignedLawyer,
        ]) ||
        cnjMatches(query, overview.cnjNumber);
  }).toList(growable: false);
}
