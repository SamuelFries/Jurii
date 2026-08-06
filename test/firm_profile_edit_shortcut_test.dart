import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/lawyer_status.dart';
import 'package:jurii/models/user_profile.dart';
import 'package:jurii/screens/firm_profile_screen.dart';
import 'package:jurii/theme/app_theme.dart';

const _user = UserProfile(
  id: 'u1',
  name: 'Dono',
  email: 'dono@x.com',
  initials: 'D',
  memberSince: '2026-01-01',
  lawyerStatus: LawyerStatus.client,
);

const _firm = LawFirm(
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

FirmWorkspace _workspace(List<FirmRole> roles) => FirmWorkspace(
  firm: _firm,
  currentUserRole: roles.first,
  currentUserRoles: roles,
  teamMembers: const [],
  fromSupabase: true,
);

void main() {
  Widget app(FirmWorkspace? workspace) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: FirmProfileScreen(
        user: _user,
        workspace: workspace,
        onSwitchToClient: () {},
        onLogout: () {},
      ),
    ),
  );

  testWidgets('sócio vê o lápis no cabeçalho, como nos outros dois fluxos', (
    tester,
  ) async {
    await tester.pumpWidget(app(_workspace(const [FirmRole.owner])));
    await tester.pumpAndSettle();

    // Quem edita o próprio perfil no modo cliente ou profissional procura o
    // lápis neste canto por reflexo.
    expect(find.byKey(const Key('firm_profile_edit_button')), findsOneWidget);
  });

  testWidgets('admin também vê', (tester) async {
    await tester.pumpWidget(app(_workspace(const [FirmRole.admin])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firm_profile_edit_button')), findsOneWidget);
  });

  testWidgets('secretária NÃO vê o lápis', (tester) async {
    await tester.pumpWidget(app(_workspace(const [FirmRole.secretary])));
    await tester.pumpAndSettle();

    // Oferecer o atalho a quem o servidor vai recusar é pior que não oferecer:
    // a pessoa preenche o formulário inteiro para ouvir "não permitido".
    expect(find.byKey(const Key('firm_profile_edit_button')), findsNothing);
    expect(find.text('Dados do escritório'), findsNothing);
  });

  testWidgets('sem workspace carregado não há lápis', (tester) async {
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firm_profile_edit_button')), findsNothing);
  });

  testWidgets('o lápis é a ÚNICA porta e abre a tela completa', (
    tester,
  ) async {
    await tester.pumpWidget(app(_workspace(const [FirmRole.owner])));
    await tester.pumpAndSettle();

    // "Dados do escritório" e "Apresentação" eram dois itens de menu para o
    // mesmo gesto — morreram; sobrou o lápis, onde os outros fluxos ensinaram
    // a procurar.
    expect(find.text('Dados do escritório'), findsNothing);
    expect(find.text('Apresentação'), findsNothing);

    await tester.tap(find.byKey(const Key('firm_profile_edit_button')));
    await tester.pumpAndSettle();

    // E a tela atrás dele carrega TUDO: dados, CNPJ travado e apresentação.
    expect(find.text('Dados do escritório'), findsOneWidget);
    expect(find.text('CNPJ'), findsOneWidget);
    expect(find.text('APRESENTAÇÃO'), findsOneWidget);
  });
}
