import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/case_request.dart';
import 'package:jurii/models/cases.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/models/firm_case_overview.dart';
import 'package:jurii/models/lawyer_case.dart';
import 'package:jurii/utils/inbox_filters.dart';
import 'package:jurii/utils/list_search.dart';

Conversation _conversa({
  required String nome,
  String especialidade = 'Direito Trabalhista',
  String ultima = 'mensagem qualquer',
  int naoLidas = 0,
}) => Conversation(
  id: nome,
  initials: 'XX',
  officeName: nome,
  specialty: especialidade,
  lastMessage: ultima,
  time: '10:00',
  unreadCount: naoLidas,
);

LawyerCase _casoDoAdvogado({
  required String cliente,
  String titulo = 'Reclamatória',
  String area = 'Direito Trabalhista',
  LawyerCaseStatus status = LawyerCaseStatus.updated,
  String? cnj,
}) => LawyerCase(
  id: cliente,
  title: titulo,
  clientName: cliente,
  clientInitials: 'CL',
  area: area,
  lastUpdate: 'hoje',
  status: status,
  cnjNumber: cnj,
);

FirmCaseOverview _casoDoEscritorio({
  required String cliente,
  String? advogadoId,
  String advogado = 'Sem advogado definido',
  bool urgente = false,
  bool encerrado = false,
}) => FirmCaseOverview(
  id: cliente,
  title: 'Caso de $cliente',
  clientName: cliente,
  clientInitials: 'CL',
  assignedLawyerId: advogadoId,
  assignedLawyer: advogado,
  area: 'Direito Cível',
  statusLabel: 'Em andamento',
  nextStep: 'Aguardando',
  urgent: urgente,
  isClosed: encerrado,
);

void main() {
  group('casamento de texto', () {
    test('acha sem acento e sem diferenciar maiúscula', () {
      // Quem digita "jose" tem que achar "José": a pessoa não vai lembrar de
      // acentuar o nome de quem ela procura.
      expect(searchTextMatches('jose', ['José da Silva']), isTrue);
      expect(searchTextMatches('AÇÃO', ['ação trabalhista']), isTrue);
      expect(searchTextMatches('trabalhista', ['Direito Trabalhista']), isTrue);
    });

    test('termo vazio casa com tudo, e lista sem campo não casa', () {
      expect(searchTextMatches('', ['qualquer coisa']), isTrue);
      expect(searchTextMatches('   ', ['qualquer coisa']), isTrue);
      expect(searchTextMatches('ana', []), isFalse);
    });

    test('campo nulo é ignorado, não tratado como vazio que casa', () {
      // Se nulo virasse string vazia dentro do palheiro, um caso sem número
      // de processo passaria a casar com qualquer busca.
      expect(searchTextMatches('ana', [null, 'Bruno']), isFalse);
      expect(searchTextMatches('bruno', [null, 'Bruno']), isTrue);
    });

    test('palavras do termo podem vir de campos diferentes', () {
      // "ana trabalhista": o nome está num campo e a área no outro.
      expect(
        searchTextMatches('ana trabalhista', [
          'Ana Souza',
          'Direito Trabalhista',
        ]),
        isTrue,
      );
      expect(
        searchTextMatches('ana previdenciario', [
          'Ana Souza',
          'Direito Trabalhista',
        ]),
        isFalse,
      );
    });
  });

  group('número de processo', () {
    // O banco guarda 20 dígitos sem máscara; o tribunal entrega com ponto e
    // traço. Sem comparar por dígitos, colar o número copiado do PJe não acha
    // nada, que é justamente como o advogado procura.
    const cnj = '08012345620268260100';

    test('colado com máscara acha o caso', () {
      expect(cnjMatches('0801234-56.2026.8.26.0100', cnj), isTrue);
    });

    test('pedaço do número acha', () {
      expect(cnjMatches('0801234', cnj), isTrue);
      expect(cnjMatches('8260100', cnj), isTrue);
    });

    test('número de outro processo não acha', () {
      expect(cnjMatches('99999999', cnj), isFalse);
    });

    test('busca por nome não consulta o CNJ', () {
      // Sem esta guarda, qualquer termo sem dígito viraria "dígitos vazios",
      // que estão contidos em todo número: buscar "ana" devolveria todos os
      // processos do mundo.
      expect(cnjMatches('ana', cnj), isFalse);
      expect(cnjMatches('', cnj), isFalse);
    });

    test('caso sem número nunca casa', () {
      expect(cnjMatches('0801234', null), isFalse);
    });
  });

  group('chip só existe quando separa algo', () {
    test('chip que alcança tudo não filtra nada', () {
      expect(filterChipIsUseful(matches: 5, total: 5), isFalse);
    });

    test('chip que não alcança nada só esvazia a tela', () {
      expect(filterChipIsUseful(matches: 0, total: 5), isFalse);
    });

    test('chip que separa parte da lista serve', () {
      expect(filterChipIsUseful(matches: 2, total: 5), isTrue);
    });
  });

  group('conversas', () {
    final lista = [
      _conversa(nome: 'Escritório Sangiogo', naoLidas: 2),
      _conversa(nome: 'Ana Souza', especialidade: 'Direito de Família'),
      _conversa(nome: 'Bruno Lima', naoLidas: 1),
    ];

    test('busca por nome de quem está do outro lado', () {
      expect(
        filterConversations(lista, query: 'ana').map((c) => c.officeName),
        ['Ana Souza'],
      );
    });

    test('busca pela área também', () {
      expect(
        filterConversations(lista, query: 'família').map((c) => c.officeName),
        ['Ana Souza'],
      );
    });

    test('não lidas separa quem tem mensagem esperando', () {
      expect(
        filterConversations(lista, onlyUnread: true).map((c) => c.officeName),
        ['Escritório Sangiogo', 'Bruno Lima'],
      );
    });

    test('busca e chip se somam, não se substituem', () {
      expect(
        filterConversations(lista, query: 'bruno', onlyUnread: true).length,
        1,
      );
      expect(
        filterConversations(lista, query: 'ana', onlyUnread: true),
        isEmpty,
      );
    });

    test('o conteúdo da última mensagem NÃO entra na busca', () {
      // A lista carrega só a última mensagem de cada conversa. Buscar dentro
      // dela responderia "nenhum resultado" para uma palavra que existe no
      // meio do histórico: filtro que enxerga um pedaço falando como se
      // enxergasse tudo. É recusa deliberada, não esquecimento.
      final comTexto = [
        _conversa(nome: 'Ana Souza', ultima: 'combinado audiência quinta'),
      ];
      expect(filterConversations(comTexto, query: 'audiência'), isEmpty);
    });

    test('a ordem que veio do servidor é preservada', () {
      // A RPC ordena por last_message_at desc. Filtrar não pode reordenar.
      expect(filterConversations(lista, query: '').map((c) => c.officeName), [
        'Escritório Sangiogo',
        'Ana Souza',
        'Bruno Lima',
      ]);
    });
  });

  group('casos do cliente', () {
    final lista = [
      const LegalCase(
        id: '1',
        title: 'Rescisão indireta',
        area: 'Direito Trabalhista',
        status: 'Em andamento',
        cnjNumber: '08012345620268260100',
      ),
      const LegalCase(
        id: '2',
        title: 'Inventário do pai',
        area: 'Direito das Sucessões',
        status: 'Encerrado',
        isClosed: true,
      ),
    ];

    test('busca por título e por área', () {
      expect(filterClientCases(lista, query: 'rescisão').single.id, '1');
      expect(filterClientCases(lista, query: 'sucessões').single.id, '2');
    });

    test('busca por número de processo colado do tribunal', () {
      expect(
        filterClientCases(lista, query: '0801234-56.2026.8.26.0100').single.id,
        '1',
      );
    });

    test('em andamento esconde o encerrado', () {
      expect(filterClientCases(lista, onlyOpen: true).single.id, '1');
    });

    test('solicitações pendentes obedecem à mesma busca', () {
      // Sem isto, filtrar esconderia os casos e deixaria a seção de
      // solicitações intacta, como se ela ignorasse o que foi digitado.
      final pedidos = [
        const CaseRequest(
          id: 'p1',
          conversationId: 'c1',
          title: 'Ação trabalhista',
          area: 'Direito Trabalhista',
          summary: '',
          requestedBy: 'Ana Souza',
          requesterInitials: 'AS',
          createdAtLabel: 'hoje',
        ),
      ];
      expect(filterCaseRequests(pedidos, query: 'ana').length, 1);
      expect(filterCaseRequests(pedidos, query: 'bruno'), isEmpty);
    });
  });

  group('casos do advogado', () {
    final lista = [
      _casoDoAdvogado(cliente: 'Ana Souza', cnj: '08012345620268260100'),
      _casoDoAdvogado(
        cliente: 'Bruno Lima',
        status: LawyerCaseStatus.newMessage,
      ),
      _casoDoAdvogado(cliente: 'Carla Dias', status: LawyerCaseStatus.closed),
    ];

    test('busca pelo nome do cliente, que é o pedido', () {
      expect(filterLawyerCases(lista, query: 'bruno').single.clientName, 'Bruno Lima');
    });

    test('busca por processo', () {
      expect(filterLawyerCases(lista, query: '0801234').single.clientName, 'Ana Souza');
    });

    test('nova mensagem e em andamento separam grupos diferentes', () {
      expect(
        filterLawyerCases(lista, onlyNewMessage: true).single.clientName,
        'Bruno Lima',
      );
      expect(
        filterLawyerCases(lista, onlyOpen: true).map((c) => c.clientName),
        ['Ana Souza', 'Bruno Lima'],
      );
    });
  });

  group('casos do escritório', () {
    final lista = [
      _casoDoEscritorio(
        cliente: 'Ana Souza',
        advogadoId: 'adv1',
        advogado: 'Dra. Marina Reis',
      ),
      _casoDoEscritorio(cliente: 'Bruno Lima', urgente: true),
      _casoDoEscritorio(
        cliente: 'Carla Dias',
        advogadoId: 'adv2',
        advogado: 'Dr. Paulo Nunes',
        encerrado: true,
      ),
    ];

    test('busca pelo advogado responsável', () {
      expect(filterFirmCases(lista, query: 'marina').single.clientName, 'Ana Souza');
    });

    test('"Sem advogado definido" é rótulo, não gente', () {
      // O servidor manda esse texto quando não há responsável. Se ele
      // entrasse na busca, digitar "sem" devolveria casos como se existisse
      // um advogado com esse nome.
      expect(filterFirmCases(lista, query: 'sem advogado'), isEmpty);
      expect(filterFirmCases(lista, query: 'definido'), isEmpty);
    });

    test('sem responsável acha o caso órfão', () {
      expect(
        filterFirmCases(lista, onlyUnassigned: true).single.clientName,
        'Bruno Lima',
      );
    });

    test('urgentes e em andamento', () {
      expect(filterFirmCases(lista, onlyUrgent: true).single.clientName, 'Bruno Lima');
      expect(
        filterFirmCases(lista, onlyOpen: true).map((c) => c.clientName),
        ['Ana Souza', 'Bruno Lima'],
      );
    });

    test('filtros se acumulam', () {
      expect(
        filterFirmCases(lista, onlyOpen: true, onlyUrgent: true)
            .single
            .clientName,
        'Bruno Lima',
      );
    });
  });
}
