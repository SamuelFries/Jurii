import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/invite_link.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/repositories/invite_link_repository.dart';
import 'package:jurii/repositories/license_repository.dart';
import 'package:jurii/screens/firm_join_requests.dart';
import 'package:jurii/screens/firm_team_screen.dart';
import 'package:jurii/screens/invite_link_screen.dart';
import 'package:jurii/services/app_navigator.dart';
import 'package:jurii/services/invite_link_service.dart';
import 'package:jurii/services/notification_router.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/utils/invite_link.dart';

/// O fluxo do convite por link NO APP, ponta a ponta no que dá para provar
/// sem aparelho: o link chega (deep link) e espera o portão; a tela do
/// convidado mostra cada estado do servidor e pede entrada; a Equipe gera
/// o link, lista pedidos e decide; o roteador leva as duas notificações a
/// algum lugar. O que só o aparelho prova (o Android abrir o app pelo
/// https, a folha nativa de compartilhar) fica documentado no PR.
const _token = 'abcdef0123456789abcdef0123456789abcdef0123456789';

class _RepoFalso implements InviteLinkRepository {
  _RepoFalso({
    this.preview = const InviteLinkPreview(
      status: InviteLinkStatus.valido,
      firmName: 'Weber e Silva',
      firmInitials: 'WS',
      memberRole: 'secretary',
    ),
    this.erroAoPedir,
    this.pedidos = const [],
    this.links = const [],
  });

  InviteLinkPreview preview;
  Object? erroAoPedir;
  List<JoinRequest> pedidos;
  List<OpenInviteLink> links;
  final List<String> chamadas = <String>[];
  final List<({String id, bool approve})> decisoes = [];
  int espiadas = 0;

  @override
  Future<InviteLinkPreview> peek(String token) async {
    espiadas++;
    return preview;
  }

  @override
  Future<String> requestEntry(String token) async {
    chamadas.add('pedir:$token');
    if (erroAoPedir != null) throw erroAoPedir!;
    return 'req-1';
  }

  @override
  Future<CreatedInviteLink> create({
    required String lawFirmId,
    required String memberRole,
  }) async {
    chamadas.add('criar:$memberRole');
    return CreatedInviteLink(
      id: 'l1',
      token: _token,
      memberRole: memberRole,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
  }

  @override
  Future<List<OpenInviteLink>> listOpen(String lawFirmId) async => links;

  @override
  Future<void> revoke(String linkId) async {
    chamadas.add('revogar:$linkId');
    links = links.where((l) => l.id != linkId).toList();
  }

  @override
  Future<List<JoinRequest>> listRequests(String lawFirmId) async => pedidos;

  @override
  Future<void> decide({
    required String requestId,
    required bool approve,
  }) async {
    decisoes.add((id: requestId, approve: approve));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// AppLinks falso: o teste decide o que "abriu o app" e o que "chegou
/// depois". `implements` porque só as duas portas importam.
class _AppLinksFalso implements AppLinks {
  _AppLinksFalso({this.inicial});
  final Uri? inicial;
  final StreamController<Uri> _stream = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> getInitialLink() async => inicial;

  @override
  Stream<Uri> get uriLinkStream => _stream.stream;

  void chega(Uri uri) => _stream.add(uri);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

JoinRequest _pedido({String id = 'r1', bool cpf = true}) => JoinRequest(
  id: id,
  requesterName: 'Ana Souza',
  requesterEmail: 'ana@exemplo.com',
  cpfInformado: cpf,
  memberRole: 'secretary',
  createdAt: DateTime(2026, 8, 18),
  expiresAt: DateTime(2026, 8, 25),
);

Widget _app(Widget home) => MaterialApp(theme: AppTheme.lightTheme, home: home);

void main() {
  group('tela do convidado: um estado do servidor, uma frase', () {
    Future<void> monta(WidgetTester tester, _RepoFalso repo) async {
      await tester.pumpWidget(
        _app(InviteLinkScreen(token: _token, repository: repo)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('válido: mostra quem convidou, o papel FIXO e pede entrada', (
      tester,
    ) async {
      final repo = _RepoFalso();
      await monta(tester, repo);

      expect(find.text('Weber e Silva'), findsOneWidget);
      // O papel vem do convite; não há campo para trocar.
      expect(find.byKey(const Key('papel-do-convite')), findsOneWidget);
      expect(find.text('Secretária'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);

      await tester.tap(find.text('Pedir para entrar'));
      await tester.pumpAndSettle();

      expect(repo.chamadas, ['pedir:$_token']);
      expect(find.text('Pedido enviado'), findsOneWidget);
    });

    testWidgets('erro ao pedir: traduz e espia de novo (o estado real)', (
      tester,
    ) async {
      final repo = _RepoFalso(
        erroAoPedir: Exception('Invite link was revoked'),
      );
      await monta(tester, repo);
      // Entre a tela abrir e o toque, o gestor cancelou o link.
      repo.preview = const InviteLinkPreview(
        status: InviteLinkStatus.revogado,
        firmName: 'Weber e Silva',
      );

      await tester.tap(find.text('Pedir para entrar'));
      await tester.pumpAndSettle();

      expect(repo.espiadas, 2);
      // A tela agora diz o estado real e o botão sumiu.
      expect(find.text('Convite cancelado'), findsOneWidget);
      expect(find.text('Pedir para entrar'), findsNothing);
    });

    for (final caso in <(InviteLinkStatus, String)>[
      (InviteLinkStatus.inexistente, 'Convite não encontrado'),
      (InviteLinkStatus.expirado, 'Este convite venceu'),
      (InviteLinkStatus.revogado, 'Convite cancelado'),
      (InviteLinkStatus.usado, 'Convite já utilizado'),
      (InviteLinkStatus.meuPedidoPendente, 'Seu pedido está em análise'),
      (InviteLinkStatus.meuPedidoAprovado, 'Você já faz parte da equipe'),
      (InviteLinkStatus.meuPedidoRecusado, 'Pedido não aprovado'),
      (InviteLinkStatus.meuPedidoExpirado, 'Seu pedido venceu sem resposta'),
      (InviteLinkStatus.desconhecida, 'Convite não encontrado'),
    ]) {
      testWidgets('${caso.$1.name}: "${caso.$2}", sem botão de pedir', (
        tester,
      ) async {
        final repo = _RepoFalso(
          preview: InviteLinkPreview(
            status: caso.$1,
            firmName: 'Weber e Silva',
            memberRole: 'intern',
          ),
        );
        await monta(tester, repo);
        expect(find.text(caso.$2), findsOneWidget);
        expect(find.text('Pedir para entrar'), findsNothing);
      });
    }

    testWidgets('aprovado com destino: "Ir para o escritório" chama a raiz', (
      tester,
    ) async {
      var entrou = 0;
      await tester.pumpWidget(
        _app(
          InviteLinkScreen(
            token: _token,
            repository: _RepoFalso(
              preview: const InviteLinkPreview(
                status: InviteLinkStatus.meuPedidoAprovado,
                firmName: 'Weber e Silva',
              ),
            ),
            onEntrouNaBanca: () => entrou++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ir para o escritório'));
      await tester.pumpAndSettle();
      expect(entrou, 1);
    });
  });

  group('deep link: chega, espera o portão, abre uma vez', () {
    setUp(() {
      appCanRouteNotifications.value = false;
    });
    tearDown(() {
      appCanRouteNotifications.value = false;
    });

    Future<void> montaApp(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: appNavigatorKey,
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Text('casa')),
        ),
      );
    }

    testWidgets(
      'link que ABRIU o app: guarda o token até o app poder navegar',
      (tester) async {
        await montaApp(tester);
        final links = _AppLinksFalso(
          inicial: Uri.parse(buildInviteLink(_token)),
        );
        final servico = InviteLinkService(appLinks: links);
        await servico.start();
        await tester.pump();

        // Deslogado / no portão: nada empilha, o token espera.
        expect(servico.tokenPendente.value, _token);
        expect(find.byType(InviteLinkScreen), findsNothing);

        appCanRouteNotifications.value = true;
        await tester.pumpAndSettle();

        expect(find.byType(InviteLinkScreen), findsOneWidget);
        expect(servico.tokenPendente.value, isNull);
        servico.dispose();
      },
    );

    testWidgets('link com o app vivo e utilizável: abre na hora, e uma vez só', (
      tester,
    ) async {
      await montaApp(tester);
      appCanRouteNotifications.value = true;
      final links = _AppLinksFalso();
      final servico = InviteLinkService(appLinks: links);
      await servico.start();

      links.chega(Uri.parse(buildInviteLink(_token)));
      await tester.pumpAndSettle();
      // O Android costuma entregar o mesmo link duas vezes (initial + stream).
      links.chega(Uri.parse(buildInviteLink(_token)));
      await tester.pumpAndSettle();

      expect(find.byType(InviteLinkScreen), findsOneWidget);
      servico.dispose();
    });

    testWidgets('link que não é convite (login-callback) é ignorado', (
      tester,
    ) async {
      await montaApp(tester);
      appCanRouteNotifications.value = true;
      final links = _AppLinksFalso(
        inicial: Uri.parse('jurii://login-callback?code=x'),
      );
      final servico = InviteLinkService(appLinks: links);
      await servico.start();
      await tester.pumpAndSettle();

      expect(servico.tokenPendente.value, isNull);
      expect(find.byType(InviteLinkScreen), findsNothing);
      servico.dispose();
    });
  });

  group('Equipe do gestor', () {
    testWidgets('pedido pendente: nome, papel, CPF, e Aprovar decide', (
      tester,
    ) async {
      final repo = _RepoFalso(pedidos: [_pedido()]);
      var recarregou = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ListView(
              children: [
                FirmJoinRequestsSection(
                  lawFirmId: 'f1',
                  repository: repo,
                  onMembroEntrou: () => recarregou++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana Souza'), findsOneWidget);
      expect(find.textContaining('Secretária'), findsOneWidget);
      expect(find.text('CPF informado'), findsOneWidget);

      await tester.tap(find.text('Aprovar'));
      await tester.pumpAndSettle();

      expect(repo.decisoes, [(id: 'r1', approve: true)]);
      expect(recarregou, 1);
      expect(find.text('Ana Souza'), findsNothing);
    });

    testWidgets('Recusar decide com approve=false e não recarrega a equipe', (
      tester,
    ) async {
      final repo = _RepoFalso(pedidos: [_pedido(cpf: false)]);
      var recarregou = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ListView(
              children: [
                FirmJoinRequestsSection(
                  lawFirmId: 'f1',
                  repository: repo,
                  onMembroEntrou: () => recarregou++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CPF não informado'), findsOneWidget);

      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();
      expect(repo.decisoes, [(id: 'r1', approve: false)]);
      expect(recarregou, 0);
    });

    testWidgets('inline e sem nada: a seção não ocupa espaço', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ListView(
              children: [
                FirmJoinRequestsSection(
                  lawFirmId: 'f1',
                  repository: _RepoFalso(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pedidos de entrada'), findsNothing);
    });

    testWidgets('link aberto: Cancelar revoga', (tester) async {
      final repo = _RepoFalso(
        links: [
          OpenInviteLink(
            id: 'l9',
            memberRole: 'intern',
            expiresAt: DateTime.now().add(const Duration(days: 3)),
            createdAt: DateTime.now(),
            createdBy: 'u1',
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ListView(
              children: [
                FirmJoinRequestsSection(lawFirmId: 'f1', repository: repo),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Convite para estagiário'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.chamadas, ['revogar:l9']);
      expect(find.text('Convite para estagiário'), findsNothing);
    });

    testWidgets(
      'gerar link: escolhe papel, cria, mostra o link canônico e copia',
      (tester) async {
        final repo = _RepoFalso();
        String? copiado;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiado = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(
          _app(
            Scaffold(
              body: InviteByLinkSheet(lawFirmId: 'f1', repository: repo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Estagiário'));
        await tester.pump();
        await tester.tap(find.text('Gerar link'));
        await tester.pumpAndSettle();

        expect(repo.chamadas, ['criar:intern']);
        final linkWidget = tester.widget<SelectableText>(
          find.byKey(const Key('link-de-convite')),
        );
        expect(linkWidget.data, 'https://app.jurii.com.br/convite/$_token');
        // O link volta a ser lido pelo MESMO parser que o app usa ao recebê-lo.
        expect(inviteTokenFromUri(Uri.parse(linkWidget.data!)), _token);

        await tester.tap(find.text('Copiar'));
        await tester.pumpAndSettle();
        expect(copiado, 'https://app.jurii.com.br/convite/$_token');
        expect(find.text('Copiado'), findsOneWidget);
      },
    );

    testWidgets('a Equipe oferece as DUAS portas: OAB para advogado, link para '
        'secretária/estagiário', (tester) async {
      const firma = LawFirm(
        id: 'f1',
        name: 'Weber e Silva',
        initials: 'WS',
        rating: 4.9,
        distance: '',
        specialty: 'Direito Cível',
        practiceAreas: ['Direito Cível'],
        reviews: 8,
        avatarType: 'blue',
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: FirmTeamScreen(
              workspace: const FirmWorkspace(
                firm: firma,
                currentUserRole: FirmRole.owner,
                currentUserRoles: [FirmRole.owner],
                teamMembers: [],
                fromSupabase: true,
              ),
              teamMembers: const [],
              licenseRepository: _LicencaFalsa(),
              inviteLinkRepository: _RepoFalso(),
              onInviteLawyer:
                  ({required oabState, required oabNumber}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Convidar membro'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('convidar-advogado')), findsOneWidget);
      expect(find.byKey(const Key('convidar-por-link')), findsOneWidget);
      // Nada de link para advogado nesta rodada.
      expect(find.textContaining('Advogado por link'), findsNothing);

      await tester.tap(find.byKey(const Key('convidar-por-link')));
      await tester.pumpAndSettle();
      expect(find.text('Convidar por link'), findsOneWidget);
      // Só os dois papéis sem OAB.
      expect(find.text('Secretária'), findsOneWidget);
      expect(find.text('Estagiário'), findsOneWidget);
      expect(find.text('Advogado'), findsNothing);
    });
  });

  group('roteador: as duas notificações do pedido', () {
    JuriiNotification n({
      required String type,
      required String title,
      String? lawFirmId,
      NotificationScope scope = NotificationScope.firm,
    }) => JuriiNotification(
      id: 'n1',
      title: title,
      body: '',
      type: type,
      scope: scope,
      createdAt: DateTime(2026, 8, 18),
      lawFirmId: lawFirmId,
      metadata: const {'join_request_id': 'r1'},
    );

    tearDown(NotificationRouter.resetForTests);

    test('firm_join_requested abre os pedidos da banca certa', () {
      expect(
        destinationFor(
          n(type: 'firm_join_requested', title: 'Pedido', lawFirmId: 'f1'),
        ),
        NotificationDestinationKind.joinRequests,
      );
      // Sem saber de qual banca, não há Equipe certa para abrir.
      expect(
        destinationFor(n(type: 'firm_join_requested', title: 'Pedido')),
        NotificationDestinationKind.none,
      );
    });

    test(
      'firm_join_decided: aprovado leva para dentro; recusa não abre nada',
      () {
        expect(
          destinationFor(
            n(
              type: 'firm_join_decided',
              title: tituloDeEntradaAprovada,
              lawFirmId: 'f1',
              scope: NotificationScope.client,
            ),
          ),
          NotificationDestinationKind.firmWorkspace,
        );
        expect(
          destinationFor(
            n(
              type: 'firm_join_decided',
              title: 'Pedido não aprovado',
              lawFirmId: 'f1',
              scope: NotificationScope.client,
            ),
          ),
          NotificationDestinationKind.none,
        );
      },
    );

    test('o título de aprovação é o que a migration grava (barreira)', () {
      // O firm_join_decided não tem metadata; o roteador reconhece a
      // aprovação pelo título. Se alguém mudar a frase no banco, este teste
      // cai antes de o toque virar link morto.
      final sql = File(
        'supabase/migrations/20260914120000_o_link_pede_em_vez_de_conceder.sql',
      ).readAsStringSync();
      expect(
        sql,
        contains("'firm_join_decided',\n          '$tituloDeEntradaAprovada'"),
      );
      // E a recusa usa OUTRO título, senão a recusa também "abriria" a banca.
      expect(
        sql,
        contains("'firm_join_decided',\n            'Pedido não aprovado'"),
      );
    });

    testWidgets(
      'abrir os pedidos empilha a tela; entrar na banca chama a raiz',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: appNavigatorKey,
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: Text('casa')),
          ),
        );
        final router = const NotificationRouter();
        final navigator = appNavigatorKey.currentState!;

        final abriu = await router.open(
          navigator,
          n(type: 'firm_join_requested', title: 'Pedido', lawFirmId: 'f1'),
        );
        await tester.pumpAndSettle();
        expect(abriu, isTrue);
        expect(find.byType(JoinRequestsScreen), findsOneWidget);

        String? pedida;
        NotificationRouter.enterFirmWorkspace = (id) async {
          pedida = id;
          return true;
        };
        final entrou = await router.open(
          navigator,
          n(
            type: 'firm_join_decided',
            title: tituloDeEntradaAprovada,
            lawFirmId: 'f2',
            scope: NotificationScope.client,
          ),
        );
        expect(entrou, isTrue);
        expect(pedida, 'f2');
      },
    );
  });

  group('tradução dos erros do banco', () {
    test(
      'cada raise exception tem frase própria; o resto não inventa causa',
      () {
        expect(
          traduzErroDoConvite(Exception('Subscription is not active')),
          contains('assinatura'),
        );
        expect(
          traduzErroDoConvite(
            Exception('Too many invite attempts. Try again later'),
          ),
          contains('Aguarde'),
        );
        expect(
          traduzErroDoConvite(Exception('Join request already decided by Bia')),
          contains('outra pessoa'),
        );
        expect(
          traduzErroDoConvite(Exception('Invite link expired')),
          contains('venceu'),
        );
        expect(
          traduzErroDoConvite(Exception('Already a member of this firm')),
          contains('já faz parte'),
        );
        expect(
          traduzErroDoConvite(Exception('boom')),
          'Não foi possível concluir agora. Tente novamente.',
        );
      },
    );
  });
}

class _LicencaFalsa implements LicenseRepository {
  @override
  Future<bool> bancaPodeCrescer(String lawFirmId) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
