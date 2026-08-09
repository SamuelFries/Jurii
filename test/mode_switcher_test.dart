import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/app_mode.dart';
import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/repositories/notification_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/models/law_firm_verification.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/law_firm_verification_status.dart';
import 'package:jurii/models/user_profile.dart';
import 'package:jurii/main.dart';
import 'package:jurii/models/profile_avatar_file.dart';
import 'package:jurii/screens/profile_screen.dart';
import 'package:jurii/widgets/mode_switcher_sheet.dart';

class _FakeNotifications extends NotificationRepository {
  const _FakeNotifications(this.counts);

  final Map<NotificationScope, int> counts;

  @override
  Future<Map<NotificationScope, int>> fetchUnreadCountsByScope({
    String? lawFirmId,
  }) async => counts;
}

void main() {
  group('quais áreas entram na lista', () {
    test('só cliente não vale seletor', () {
      // Um botão que abre uma lista de um item só não é navegação, é ruído.
      final opcoes = buildModeOptions(hasLawyerMode: false, hasFirmMode: false);
      expect(opcoes, hasLength(1));
      expect(shouldShowModeSwitcher(opcoes), isFalse);
    });

    test('cliente entra sempre, mesmo sendo o modo atual', () {
      final opcoes = buildModeOptions(
        onLawyer: () {},
        hasLawyerMode: true,
        hasFirmMode: false,
      );
      expect(opcoes.map((o) => o.mode), [AppMode.client, AppMode.lawyer]);
      expect(shouldShowModeSwitcher(opcoes), isTrue);
    });

    test('os três aparecem para quem tem os três', () {
      final opcoes = buildModeOptions(
        onLawyer: () {},
        onFirm: () {},
        hasLawyerMode: true,
        hasFirmMode: true,
      );
      expect(opcoes, hasLength(3));
    });
  });

  group('o fluxo do advogado não oferece escritório que não existe', () {
    // O DEFEITO QUE ISTO TRAVA: no fluxo do advogado, ProfileScreen decide
    // hasFirmMode por `onOpenLawFirmArea != null`, e o main.dart passava esse
    // callback SEM checar nada. Resultado: todo advogado aprovado via
    // "Escritório" no seletor, mesmo sem escritório nenhum. Pior, o toque
    // caía num `return` mudo dentro de _switchToFirm: a opção aparecia,
    // aceitava o toque e não fazia nada.

    const advogado = UserProfile(
      id: 'u1',
      name: 'Dra. Ana',
      email: 'ana@x.com',
      initials: 'A',
      memberSince: '2026-01-01',
      lawyerStatus: LawyerStatus.approved,
    );

    Future<void> abrirPerfilDoAdvogado(
      WidgetTester tester, {
      required VoidCallback? onOpenLawFirmArea,
    }) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ProfileScreen(
              user: advogado,
              // Estar no fluxo do advogado é o que onSwitchToClient sinaliza.
              onSwitchToClient: () {},
              onOpenLawFirmArea: onOpenLawFirmArea,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Trocar de área'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trocar de área'));
      await tester.pumpAndSettle();
    }

    testWidgets('advogado SEM escritório não vê a área do escritório', (
      tester,
    ) async {
      await abrirPerfilDoAdvogado(tester, onOpenLawFirmArea: null);

      expect(find.text(AppMode.client.label), findsOneWidget);
      expect(find.text(AppMode.lawyer.label), findsOneWidget);
      expect(find.text(AppMode.firm.label), findsNothing);
    });

    testWidgets('advogado COM escritório vê, e a opção leva a algum lugar', (
      tester,
    ) async {
      var abriu = 0;
      await abrirPerfilDoAdvogado(tester, onOpenLawFirmArea: () => abriu++);

      expect(find.text(AppMode.firm.label), findsOneWidget);

      await tester.tap(find.text(AppMode.firm.label));
      await tester.pumpAndSettle();
      expect(abriu, 1);
    });

    testWidgets('LawyerNavigation repassa o nulo até o seletor', (
      tester,
    ) async {
      // O teste acima injeta ProfileScreen direto e prova só que ELA se
      // comporta. Este cobre o trecho onde o defeito morava: a fiação entre
      // a navegação do advogado e o perfil. Sem ele, alguém volta a passar
      // um callback incondicional e nada fica vermelho.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LawyerNavigation(
            user: advogado,
            workspace: null,
            onRefreshFirmWorkspace: () async {},
            onSwitchToFirm: null,
            onSwitchToClient: () {},
            onLogout: () {},
            onDeleteAccount: () async {},
            onEditProfile:
                ({
                  required String fullName,
                  required String phone,
                  ProfileAvatarFile? avatar,
                  required bool removeAvatar,
                }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Trocar de área'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trocar de área'));
      await tester.pumpAndSettle();

      expect(find.text(AppMode.firm.label), findsNothing);
    });
  });

  group('folha do seletor', () {
    Future<void> abrir(
      WidgetTester tester, {
      required AppMode atual,
      required List<ModeOption> opcoes,
      Map<NotificationScope, int> pendentes = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModeSwitcher(
                    context,
                    current: atual,
                    options: opcoes,
                    repository: _FakeNotifications(pendentes),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('marca onde a pessoa está e não navega dali', (tester) async {
      var trocou = 0;
      await abrir(
        tester,
        atual: AppMode.client,
        opcoes: buildModeOptions(
          onLawyer: () => trocou++,
          hasLawyerMode: true,
          hasFirmMode: false,
        ),
      );

      expect(find.text('Você está aqui'), findsOneWidget);

      await tester.tap(find.text('Cliente'));
      await tester.pumpAndSettle();
      expect(trocou, 0, reason: 'tocar no modo atual não é navegação');
    });

    testWidgets('o modo atual não diz "não liberado"', (tester) async {
      // No modo atual não existe callback de troca (não se navega para onde
      // já se está) — sem ressalva, a linha da pessoa diria que a área dela
      // não está liberada.
      await abrir(
        tester,
        atual: AppMode.client,
        opcoes: buildModeOptions(
          onLawyer: () {},
          hasLawyerMode: true,
          hasFirmMode: false,
        ),
      );

      expect(find.text('Ainda não liberado para sua conta'), findsNothing);
      expect(find.text(AppMode.client.description), findsOneWidget);
    });

    testWidgets('trocar chama o callback do modo escolhido', (tester) async {
      AppMode? escolhido;
      await abrir(
        tester,
        atual: AppMode.client,
        opcoes: buildModeOptions(
          onLawyer: () => escolhido = AppMode.lawyer,
          onFirm: () => escolhido = AppMode.firm,
          hasLawyerMode: true,
          hasFirmMode: true,
        ),
      );

      await tester.tap(find.text('Escritório'));
      await tester.pumpAndSettle();

      expect(escolhido, AppMode.firm);
      expect(
        find.text('Trocar de área'),
        findsNothing,
        reason: 'a folha fecha',
      );
    });

    testWidgets('mostra o que está esperando nos OUTROS fluxos', (
      tester,
    ) async {
      // O ponto do seletor inteiro. O sino conta só o escopo do modo aberto,
      // então uma solicitação de caso que chega no fluxo profissional é
      // invisível para quem está no fluxo cliente — e vira lead perdido.
      await abrir(
        tester,
        atual: AppMode.client,
        opcoes: buildModeOptions(
          onLawyer: () {},
          onFirm: () {},
          hasLawyerMode: true,
          hasFirmMode: true,
        ),
        pendentes: const {
          NotificationScope.client: 0,
          NotificationScope.lawyer: 3,
          NotificationScope.firm: 0,
        },
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('contagem alta não estoura o rótulo', (tester) async {
      await abrir(
        tester,
        atual: AppMode.client,
        opcoes: buildModeOptions(
          onLawyer: () {},
          hasLawyerMode: true,
          hasFirmMode: false,
        ),
        pendentes: const {NotificationScope.lawyer: 42},
      );

      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('área existente mas não liberada aparece explicada', (
      tester,
    ) async {
      // Sumir com a linha faria a pessoa procurar por algo que ela lembra de
      // ter pedido.
      await abrir(
        tester,
        atual: AppMode.client,
        opcoes: [
          const ModeOption(mode: AppMode.client, onSelect: null),
          const ModeOption(mode: AppMode.lawyer, onSelect: null),
        ],
      );

      expect(find.text('Ainda não liberado para sua conta'), findsOneWidget);
    });
  });

  group('seletor e convite nao competem pelo mesmo espaco', () {
    testWidgets('cliente com escritorio ve o seletor, nao dois caminhos', (
      tester,
    ) async {
      // Era o defeito visto em uso: a tela mostrava "Trocar de área" E
      // "Área do Escritório", um debaixo do outro, levando ao mesmo lugar.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ProfileScreen(
              user: const UserProfile(
                id: 'u1',
                name: 'Leonardo',
                email: 'l@x.com',
                initials: 'L',
                memberSince: '2026-07-25',
                lawyerStatus: LawyerStatus.client,
              ),
              lawFirmVerification: const LawFirmVerification(
                ownerProfileId: 'u1',
                firmName: 'Firma',
                cnpj: '12.345.678/0001-90',
                phone: '11999999999',
                email: 'c@x.com',
                address: 'Rua',
                practiceAreas: ['Direito Cível'],
                documents: [],
                status: LawFirmVerificationStatus.approved,
              ),
              onVerificationSubmitted: (_) {},
              onOpenLawFirmArea: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trocar de área'), findsOneWidget);
      expect(find.text('Área do Escritório'), findsNothing);
    });
  });
}
