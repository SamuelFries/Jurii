import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';
import 'package:jurii/repositories/favorites_repository.dart';
import 'package:jurii/screens/favorites_screen.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/favorite_heart_button.dart';

LawyerProfileSummary _lawyer(String id, String name) {
  return LawyerProfileSummary(
    id: id,
    name: name,
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

LawFirm _firm(String id, String name) {
  return LawFirm(
    id: id,
    name: name,
    initials: 'FP',
    rating: 4.0,
    distance: '',
    specialty: 'Direito Cível',
    practiceAreas: const ['Direito Cível'],
    reviews: 2,
    avatarType: 'blue',
  );
}

class _FakeFavoritesRepository extends FavoritesRepository {
  _FakeFavoritesRepository({
    this.lawyers = const [],
    this.firms = const [],
    Set<String>? keys,
    this.failFetches = false,
    this.failToggle = false,
  }) : keys = keys ?? {};

  List<LawyerProfileSummary> lawyers;
  List<LawFirm> firms;
  final Set<String> keys;
  bool failFetches;
  final bool failToggle;
  int toggleCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> toggleFavorite({
    required FavoriteTargetType type,
    required String id,
  }) async {
    toggleCalls++;
    if (failToggle) throw StateError('offline');
    final key = favoriteKey(type.value, id);
    if (keys.remove(key)) return false;
    keys.add(key);
    return true;
  }

  @override
  Future<Set<String>> fetchFavoriteKeys() async {
    if (failFetches) throw StateError('offline');
    return Set.of(keys);
  }

  @override
  Future<List<LawyerProfileSummary>> fetchFavoriteLawyers() async {
    if (failFetches) throw StateError('offline');
    return lawyers;
  }

  @override
  Future<List<LawFirm>> fetchFavoriteLawFirms() async {
    if (failFetches) throw StateError('offline');
    return firms;
  }
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(appBar: AppBar(actions: [child])),
  );
}

void main() {
  group('FavoriteHeartButton', () {
    testWidgets('carrega estado e alterna com otimismo', (tester) async {
      final repo = _FakeFavoritesRepository(
        keys: {favoriteKey('lawyer', 'l1')},
      );

      await tester.pumpWidget(
        _host(FavoriteHeartButton(
          type: FavoriteTargetType.lawyer,
          targetId: 'l1',
          repository: repo,
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(repo.toggleCalls, 1);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('falha no toggle reverte e avisa', (tester) async {
      final repo = _FakeFavoritesRepository(failToggle: true);

      await tester.pumpWidget(
        _host(FavoriteHeartButton(
          type: FavoriteTargetType.lawFirm,
          targetId: 'f1',
          repository: repo,
        )),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      // Reverteu ao estado real e avisou.
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(
        find.text('Não foi possível atualizar o favorito.'),
        findsOneWidget,
      );
    });

    testWidgets('modo demo (repo indisponível) esconde o coração', (
      tester,
    ) async {
      // Repositório REAL: sem Supabase inicializado, isAvailable == false.
      await tester.pumpWidget(
        _host(const FavoriteHeartButton(
          type: FavoriteTargetType.lawyer,
          targetId: 'l1',
        )),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });
  });

  group('FavoritesScreen', () {
    testWidgets('lista advogados, alterna para escritórios', (tester) async {
      final repo = _FakeFavoritesRepository(
        lawyers: [_lawyer('l1', 'Advogada Um'), _lawyer('l2', 'Advogado Dois')],
        firms: [_firm('f1', 'Firma Única')],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FavoritesScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Advogados (2)'), findsOneWidget);
      expect(find.text('Advogada Um'), findsOneWidget);
      expect(find.text('Firma Única'), findsNothing);

      await tester.tap(find.text('Escritórios (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Firma Única'), findsOneWidget);
      expect(find.text('Advogada Um'), findsNothing);
    });

    testWidgets('vazio orienta a favoritar pelo perfil', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FavoritesScreen(repository: _FakeFavoritesRepository()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhum advogado favorito'), findsOneWidget);
    });

    testWidgets('erro tem retry que recarrega', (tester) async {
      final repo = _FakeFavoritesRepository(failFetches: true);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FavoritesScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar seus favoritos.'),
        findsOneWidget,
      );

      repo
        ..failFetches = false
        ..lawyers = [_lawyer('l1', 'Advogada Um')];
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.text('Advogada Um'), findsOneWidget);
    });
  });
}
