import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/widgets/jurii_motion.dart';

class _Counter extends StatefulWidget {
  const _Counter({required this.label});

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${widget.label}: $count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: Text('incrementar ${widget.label}'),
        ),
      ],
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: JuriiLazyIndexedStack(
          index: index,
          children: const [
            _Counter(label: 'A'),
            _Counter(label: 'B'),
          ],
        ),
        bottomNavigationBar: Row(
          children: [
            TextButton(
              onPressed: () => setState(() => index = 0),
              child: const Text('aba A'),
            ),
            TextButton(
              onPressed: () => setState(() => index = 1),
              child: const Text('aba B'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('só a aba ativa é construída na primeira carga', (tester) async {
    await tester.pumpWidget(const _Harness());

    expect(find.text('A: 0'), findsOneWidget);
    // A aba B ainda não foi visitada: não pode ter disparado build (e, no app
    // real, nenhum fetch).
    expect(find.text('B: 0', skipOffstage: false), findsNothing);
  });

  testWidgets('trocar de aba preserva o estado da aba anterior', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());

    await tester.tap(find.text('incrementar A'));
    await tester.pump();
    expect(find.text('A: 1'), findsOneWidget);

    await tester.tap(find.text('aba B'));
    await tester.pumpAndSettle();
    expect(find.text('B: 0'), findsOneWidget);

    await tester.tap(find.text('aba A'));
    await tester.pumpAndSettle();
    // Era o bug do KeyedSubtree: voltar para a aba recriava a tela do zero.
    expect(find.text('A: 1'), findsOneWidget);
  });

  testWidgets('aba visitada continua viva depois de sair dela', (tester) async {
    await tester.pumpWidget(const _Harness());

    await tester.tap(find.text('aba B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('incrementar B'));
    await tester.pump();

    await tester.tap(find.text('aba A'));
    await tester.pumpAndSettle();
    expect(find.text('B: 1', skipOffstage: false), findsOneWidget);
  });
}
