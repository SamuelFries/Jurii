import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/repositories/license_repository.dart';
import 'package:jurii/screens/firm_team_screen.dart';
import 'package:jurii/theme/app_theme.dart';

/// O aviso de cobrança na tela de Equipe.
///
/// Ele existe para dizer ANTES em vez de o servidor recusar DEPOIS: com a
/// assinatura parada, convidar e promover são recusados (20260907120000), e
/// sem o aviso a pessoa só descobria isso depois de digitar a OAB e clicar.
class _RepositorioFalso implements LicenseRepository {
  _RepositorioFalso({required this.podeCrescer, this.estoura = false});

  final bool podeCrescer;
  final bool estoura;
  int chamadas = 0;

  @override
  Future<bool> bancaPodeCrescer(String lawFirmId) async {
    chamadas++;
    if (estoura) throw Exception('offline');
    return podeCrescer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _firma = LawFirm(
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

FirmWorkspace _espaco(List<FirmRole> papeis) => FirmWorkspace(
  firm: _firma,
  currentUserRole: papeis.first,
  currentUserRoles: papeis,
  teamMembers: const [],
  fromSupabase: true,
);

Widget _tela(LicenseRepository repositorio, {required List<FirmRole> papeis}) =>
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: FirmTeamScreen(
          workspace: _espaco(papeis),
          teamMembers: const [],
          licenseRepository: repositorio,
          onInviteLawyer: ({required oabState, required oabNumber}) async {},
        ),
      ),
    );

void main() {
  testWidgets('com a assinatura parada, a tela avisa antes de a pessoa tentar', (
    tester,
  ) async {
    await tester.pumpWidget(_tela(
      _RepositorioFalso(podeCrescer: false),
      papeis: const [FirmRole.owner],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Assinatura pendente'), findsOneWidget);
    // A FRASE FALA DE CRESCER, E SÓ: ninguém pode ler "assinatura pendente"
    // como "perdi o escritório".
    expect(
      find.textContaining('continua trabalhando normalmente'),
      findsOneWidget,
    );
  });

  testWidgets('com a assinatura em dia, nao ha aviso nenhum', (tester) async {
    await tester.pumpWidget(_tela(
      _RepositorioFalso(podeCrescer: true),
      papeis: const [FirmRole.owner],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Assinatura pendente'), findsNothing);
  });

  testWidgets('falha de rede NAO vira acusacao de inadimplencia', (
    tester,
  ) async {
    // Quem recusa de verdade é o servidor. Um cartão de cobrança piscando na
    // tela de quem está em dia, por causa de uma queda de rede, seria pior do
    // que aviso nenhum.
    await tester.pumpWidget(_tela(
      _RepositorioFalso(podeCrescer: false, estoura: true),
      papeis: const [FirmRole.owner],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Assinatura pendente'), findsNothing);
  });

  testWidgets('quem nao administra a equipe nem chega a perguntar', (
    tester,
  ) async {
    // A resposta conta se a banca está inadimplente, que é assunto de quem
    // responde pelo escritório. Secretário não vê o cartão nem gasta a
    // chamada.
    final repositorio = _RepositorioFalso(podeCrescer: false);
    await tester.pumpWidget(_tela(
      repositorio,
      papeis: const [FirmRole.secretary],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Assinatura pendente'), findsNothing);
    expect(repositorio.chamadas, 0);
  });
}
