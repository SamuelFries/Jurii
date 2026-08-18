import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A apresentação de primeira abertura.
///
/// As três garantias que valem o teste: quem nunca viu, vê UMA vez; quem já
/// viu vai direto ao login; e "Pular" está sempre à mão, porque intro que
/// prende é pedágio, e pedágio na primeira abertura é onde se perde gente.
void main() {
  testWidgets('primeira abertura mostra a apresentação, e Pular leva ao login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const JuriiApp());
    await tester.pumpAndSettle();

    expect(find.text('O advogado certo,\nsem adivinhar'), findsOneWidget);
    expect(find.text('Pular'), findsOneWidget);

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    // O login é a tela seguinte, e a intro não volta mais.
    expect(find.text('Entrar'), findsWidgets);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('jurii.onboarding_visto'), isTrue);
  });

  testWidgets('quem já viu vai direto ao login, sem flash de intro', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'jurii.onboarding_visto': true});

    await tester.pumpWidget(const JuriiApp());
    await tester.pumpAndSettle();

    expect(find.text('O advogado certo,\nsem adivinhar'), findsNothing);
    expect(find.text('Entrar'), findsWidgets);
  });

  testWidgets('as três páginas se percorrem e Começar encerra', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const JuriiApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Avançar'));
    await tester.pumpAndSettle();
    expect(find.text('Seu caso,\nacompanhado de perto'), findsOneWidget);

    await tester.tap(find.text('Avançar'));
    await tester.pumpAndSettle();
    expect(find.text('Advoga?\nTrabalhe por aqui'), findsOneWidget);

    // Na última página o botão muda de nome: é o fim anunciado, não um
    // "Avançar" que de repente fecha a tela.
    expect(find.text('Avançar'), findsNothing);
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsWidgets);
  });
}
