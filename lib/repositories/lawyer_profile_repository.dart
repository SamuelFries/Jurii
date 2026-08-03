import 'dart:developer' as developer;

import '../data/legal_practice_areas.dart';
import '../data/mock/mock_lawyers.dart';
import '../models/discovery_page.dart';
import '../models/lawyer_profile_summary.dart';
import '../services/supabase_config.dart';

class LawyerProfileRepository {
  const LawyerProfileRepository();

  /// Primeira página menor (a home empilha várias seções); "Ver mais" traz
  /// blocos maiores. O teto do servidor é 20 por chamada e o sentinela pede
  /// limit + 1 — qualquer página aqui tem que caber em 19.
  static const int firstPageSize = 6;
  static const int nextPageSize = 10;

  Future<DiscoveryPage<LawyerProfileSummary>> fetchRecommendedLawyers({
    String searchQuery = '',
    int offset = 0,
    int limit = firstPageSize,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      // Demo: uma página só. Offset além dela é fim de lista, não erro.
      if (offset > 0) return const DiscoveryPage.last([]);
      return DiscoveryPage.last(
        _filterLawyers(mockRecommendedLawyers, searchQuery),
      );
    }

    try {
      final rows = await SupabaseConfig.client.rpc(
        'fetch_recommended_lawyers',
        params: {
          // Sentinela: uma linha a mais só para saber se há próxima página.
          'limit_value': limit + 1,
          'search_value': searchQuery,
          'offset_value': offset,
        },
      );

      final parsed = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map<LawyerProfileSummary>(_fromRow)
          .toList();
      final hasMore = parsed.length > limit;
      return DiscoveryPage(
        items: hasMore ? parsed.sublist(0, limit) : parsed,
        hasMore: hasMore,
      );
    } catch (error, stackTrace) {
      // Página 2+ não tem fallback possível (a função antiga não pagina):
      // o erro sobe e o botão "Ver mais" avisa sem derrubar o que já está
      // na tela.
      if (offset > 0) rethrow;

      final fallback = await _fetchRecommendedLawyersLegacy();
      if (fallback.isNotEmpty) {
        return DiscoveryPage.last(_filterLawyers(fallback, searchQuery));
      }

      developer.log(
        'Supabase recommended lawyers fetch failed',
        name: 'LawyerProfileRepository',
        error: error,
        stackTrace: stackTrace,
      );
      // Sem fallback e com backend configurado, o erro sobe: a seção tem
      // estado de erro com retry (a de escritórios já fazia isso; esta
      // devolvia lista vazia e virava "Nenhum advogado recomendado").
      if (SupabaseConfig.isReady) rethrow;
      return const DiscoveryPage.last([]);
    }
  }

  Future<List<LawyerProfileSummary>> _fetchRecommendedLawyersLegacy() async {
    try {
      final rows = await SupabaseConfig.client.rpc(
        'fetch_recommended_lawyers',
        params: {'limit_value': 6},
      );

      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map<LawyerProfileSummary>(_fromRow)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Advogados que o escritório pode sugerir a um cliente: vínculo ativo,
  /// convite aceito e cadastro aprovado. O banco aplica o mesmo filtro e ainda
  /// exige que quem chama fale pelo escritório.
  Future<List<LawyerProfileSummary>> fetchLawFirmLawyers(
    String lawFirmId,
  ) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const [];
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_law_firm_lawyers',
      params: {'law_firm_id_value': lawFirmId},
    );

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map<LawyerProfileSummary>(_fromRow)
        .toList();
  }

  Future<LawyerProfileSummary?> fetchLawyerById(String lawyerId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return null;
    }

    final row = await SupabaseConfig.client
        .rpc(
          'fetch_lawyer_public_profile',
          params: {'lawyer_profile_id_value': lawyerId},
        )
        .maybeSingle();

    if (row == null) return null;
    return _fromRow(row);
  }

  LawyerProfileSummary _fromRow(Map<String, dynamic> row) {
    final name = row['full_name'] as String? ?? 'Advogado Jurii';
    final initials = row['initials'] as String? ?? _initialsFor(name);
    final primaryArea =
        row['primary_area'] as String? ?? 'Atendimento jurídico';

    return LawyerProfileSummary(
      id: row['id'].toString(),
      name: name,
      initials: initials,
      oabNumber: row['oab_number'] as String? ?? '',
      oabState: row['oab_state'] as String? ?? '',
      primaryArea: primaryArea,
      practiceAreas: _practiceAreasFromRow(
        row['practice_areas'],
        fallback: [primaryArea],
      ),
      bio:
          row['bio'] as String? ?? 'Perfil profissional verificado pela Jurii.',
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'navy',
      photoUrl: row['avatar_url'] as String?,
      isFeatured: row['is_featured'] as bool? ?? false,
    );
  }

  List<LawyerProfileSummary> _filterLawyers(
    List<LawyerProfileSummary> lawyers,
    String query,
  ) {
    return lawyers
        .where(
          (lawyer) => matchesPracticeAreaSearch(
            practiceAreas: lawyer.practiceAreas,
            query: query,
            extraFields: [lawyer.name, lawyer.primaryArea],
          ),
        )
        .toList();
  }

  List<String> _practiceAreasFromRow(Object? value, {List<String>? fallback}) {
    final areas = value is List
        ? value.whereType<String>().toList()
        : const <String>[];
    final cleanAreas = areas
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
    if (cleanAreas.isNotEmpty) return cleanAreas;

    return (fallback ?? const <String>[])
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
  }

  String _initialsFor(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'J';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
