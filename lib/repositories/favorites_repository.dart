import '../models/law_firm.dart';
import '../models/lawyer_profile_summary.dart';
import '../services/supabase_config.dart';
import 'law_firm_repository.dart';
import 'lawyer_profile_repository.dart';

enum FavoriteTargetType {
  lawyer('lawyer'),
  lawFirm('law_firm');

  const FavoriteTargetType(this.value);
  final String value;
}

/// Favoritos do cliente (advogados e escritórios). Tudo por RPC — a tabela
/// é trancada no banco. Favorito é PRIVADO: nenhuma superfície do app expõe
/// contagem ou identidade de quem favoritou ao profissional.
class FavoritesRepository {
  const FavoritesRepository();

  /// O modo demo/deslogado não tem favoritos: telas escondem o coração e a
  /// lista fica vazia. Testável: fakes sobrescrevem para true.
  bool get isAvailable =>
      SupabaseConfig.isReady && SupabaseConfig.client.auth.currentUser != null;

  /// Liga/desliga e devolve o estado novo (true = favoritado).
  Future<bool> toggleFavorite({
    required FavoriteTargetType type,
    required String id,
  }) async {
    final result = await SupabaseConfig.client.rpc(
      'toggle_favorite',
      params: {'target_type_value': type.value, 'target_id_value': id},
    );
    return result as bool;
  }

  /// Pares favoritados do usuário, como chaves `tipo:id` (estado dos
  /// corações — um Set só, para uma consulta cobrir as duas listas).
  Future<Set<String>> fetchFavoriteKeys() async {
    if (!isAvailable) return const {};

    final rows = await SupabaseConfig.client.rpc('fetch_favorite_ids');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => favoriteKey(
            row['target_type'] as String,
            row['target_id'].toString(),
          ),
        )
        .toSet();
  }

  Future<List<LawyerProfileSummary>> fetchFavoriteLawyers() async {
    if (!isAvailable) return const [];

    final rows = await SupabaseConfig.client.rpc('fetch_favorite_lawyers');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LawyerProfileSummary>(LawyerProfileRepository.summaryFromRow)
        .toList();
  }

  Future<List<LawFirm>> fetchFavoriteLawFirms() async {
    if (!isAvailable) return const [];

    final rows = await SupabaseConfig.client.rpc('fetch_favorite_law_firms');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LawFirm>(LawFirmRepository.firmFromRow)
        .toList();
  }
}

String favoriteKey(String targetType, String id) => '$targetType:$id';
