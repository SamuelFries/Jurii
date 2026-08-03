import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/discovery_page.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';
import 'package:jurii/repositories/lawyer_profile_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/utils/discovery_pagination.dart';
import 'package:jurii/widgets/offices_section.dart';
import 'package:jurii/widgets/recommended_lawyers_section.dart';

LawyerProfileSummary _lawyer(String id, {String name = ''}) {
  return LawyerProfileSummary(
    id: id,
    name: name.isEmpty ? 'Advogado $id' : name,
    initials: 'AJ',
    oabNumber: '123',
    oabState: 'RS',
    primaryArea: 'Direito Cível',
    practiceAreas: const ['Direito Cível'],
    bio: 'bio',
    rating: 4.5,
    reviews: 3,
    avatarType: 'navy',
  );
}

/// Fake com roteiro de páginas por offset. Registra as chamadas para os
/// testes poderem afirmar o offset pedido e a busca propagada.
class _FakeLawyerRepository extends LawyerProfileRepository {
  _FakeLawyerRepository(this.pages);

  final Map<int, DiscoveryPage<LawyerProfileSummary>> pages;
  final List<({int offset, String query})> calls = [];
  Completer<DiscoveryPage<LawyerProfileSummary>>? pending;

  @override
  Future<DiscoveryPage<LawyerProfileSummary>> fetchRecommendedLawyers({
    String searchQuery = '',
    int offset = 0,
    int limit = LawyerProfileRepository.firstPageSize,
  }) {
    calls.add((offset: offset, query: searchQuery));
    final blocked = pending;
    if (blocked != null && offset == 0 && searchQuery == 'lenta') {
      return blocked.future;
    }
    final page = pages[offset];
    if (page == null) throw StateError('sem página para offset $offset');
    return Future.value(page);
  }
}

Widget _host(Widget section) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: section)),
  );
}

void main() {
  group('appendUniqueBy', () {
    test('anexa preservando ordem e descarta chave repetida', () {
      final result = appendUniqueBy(
        [1, 2, 3],
        [3, 4, 5],
        (value) => value,
      );
      expect(result, [1, 2, 3, 4, 5]);
    });

    test('lista atual vazia vira a página nova', () {
      expect(appendUniqueBy(<int>[], [7, 8], (v) => v), [7, 8]);
    });

    test('página duplicada inteira é no-op', () {
      expect(appendUniqueBy([1, 2], [1, 2], (v) => v), [1, 2]);
    });
  });

  group('RecommendedLawyersSection paginada', () {
    // SupabaseConfig nunca inicializa em teste, então o repositório REAL
    // cairia no modo demo; o fake abaixo simula o caminho com backend.
    testWidgets('Ver mais anexa página, dedupa e some no fim', (tester) async {
      final repo = _FakeLawyerRepository({
        0: DiscoveryPage(
          items: [for (var i = 1; i <= 6; i++) _lawyer('l$i')],
          hasMore: true,
        ),
        // 'l6' repetido de propósito: a rotação horária do destaque pode
        // reapresentar um perfil na página seguinte.
        6: DiscoveryPage.last([
          _lawyer('l6'),
          _lawyer('l7'),
          _lawyer('l8'),
        ]),
      });

      await tester.pumpWidget(
        _host(RecommendedLawyersSection(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ver mais advogados'), findsOneWidget);
      expect(find.text('Advogado l6'), findsOneWidget);

      await tester.ensureVisible(find.text('Ver mais advogados'));
      await tester.tap(find.text('Ver mais advogados'));
      await tester.pumpAndSettle();

      // Página 2 pediu offset em coordenadas do servidor.
      expect(repo.calls.last.offset, 6);
      // Dedupe: l6 continua aparecendo UMA vez; l7/l8 entraram.
      expect(find.text('Advogado l6'), findsOneWidget);
      expect(find.text('Advogado l7'), findsOneWidget);
      expect(find.text('Advogado l8'), findsOneWidget);
      // Fim da lista: botão some.
      expect(find.text('Ver mais advogados'), findsNothing);
    });

    testWidgets('trocar a busca descarta resposta atrasada da anterior', (
      tester,
    ) async {
      final repo = _FakeLawyerRepository({
        0: DiscoveryPage.last([_lawyer('novo', name: 'Advogada Nova')]),
      });
      repo.pending = Completer();

      await tester.pumpWidget(
        _host(RecommendedLawyersSection(searchQuery: 'lenta', repository: repo)),
      );
      await tester.pump();

      // Busca muda com o fetch antigo em voo.
      await tester.pumpWidget(
        _host(RecommendedLawyersSection(searchQuery: 'nova', repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Advogada Nova'), findsOneWidget);

      // A resposta ATRASADA da busca antiga chega agora — e não pode
      // sobrescrever a lista da busca atual.
      repo.pending!.complete(
        DiscoveryPage.last([_lawyer('velho', name: 'Advogado Velho')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Advogada Nova'), findsOneWidget);
      expect(find.text('Advogado Velho'), findsNothing);
    });
  });

  group('OfficesSection paginada', () {
    testWidgets('demo (sem Supabase) não mostra Ver mais', (tester) async {
      await tester.pumpWidget(_host(const OfficesSection()));
      await tester.pumpAndSettle();

      // Mocks renderizam; paginação não existe no demo.
      expect(find.text('Ver mais escritórios'), findsNothing);
    });

    // O caminho COM backend da OfficesSection (Ver mais, dedupe, falha de
    // página 2) não é testável aqui: _shouldUseMock curto-circuita para os
    // mocks sempre que o Supabase não inicializou, e SupabaseConfig é
    // estático. O padrão de paginação é o MESMO da seção de advogados
    // (testado acima com fake), e o contrato do servidor é coberto pelo
    // pgTAP discovery_pagination_test.sql.
  });
}
