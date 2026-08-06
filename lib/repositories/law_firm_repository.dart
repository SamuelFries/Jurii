import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/legal_practice_areas.dart';
import '../models/discovery_page.dart';
import '../models/law_firm.dart';
import '../services/supabase_config.dart';
import '../utils/discovery_pagination.dart';
import '../utils/office_sorting.dart';
import 'discovery_metrics_repository.dart';

class LawFirmRepository {
  const LawFirmRepository();

  static const _metrics = DiscoveryMetricsRepository();

  /// Página inicial e blocos do "Ver mais". Teto do servidor: 30 por chamada
  /// (o sentinela pede limit + 1 — páginas têm que caber em 29).
  static const int firstPageSize = 10;
  static const int nextPageSize = 10;

  Future<DiscoveryPage<LawFirm>> fetchRecommendedLawFirms({
    String searchQuery = '',
    int offset = 0,
    int limit = firstPageSize,
    OfficeSort sort = OfficeSort.relevance,
    double? userLatitude,
    double? userLongitude,
  }) async {
    try {
      final rows = await SupabaseConfig.client.rpc(
        'fetch_recommended_law_firms',
        params: {
          // Sentinela: uma linha a mais só para saber se há próxima página.
          'limit_value': limit + 1,
          'search_value': searchQuery,
          'offset_value': offset,
          // Ordenar no SERVIDOR é o que faz a ordem valer sobre o conjunto
          // inteiro: client-side, "mais perto" significava "mais perto dos
          // dez primeiros", porque a lista chega paginada.
          //
          // Quais parâmetros viajam (e quando a posição do usuário viaja
          // junto) é decidido em discoverySortParams, que é testado.
          ...discoverySortParams(
            sort,
            userLatitude: userLatitude,
            userLongitude: userLongitude,
          ),
        },
      );

      final parsed = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map<LawFirm>(firmFromRow)
          .toList();
      final page = pageFromSentinel(parsed, limit);

      // Só o que vai para a tela: `parsed` ainda carrega a linha-sentinela da
      // paginação, que ninguém vê e não pode contar como impressão.
      unawaited(
        _metrics.logImpressions(
          target: DiscoveryTarget.lawFirm,
          targetIds: page.items
              .map((firm) => firm.id)
              .whereType<String>()
              .toList(),
          sponsoredIds: page.items
              .where((firm) => firm.isSponsoredSlot)
              .map((firm) => firm.id)
              .whereType<String>()
              .toList(),
        ),
      );

      return page;
    } on PostgrestException catch (error) {
      // Fallback SÓ para "função não existe com esses parâmetros"
      // (PGRST202) — o app novo contra o banco ainda sem a migration de
      // paginação. Erro transitório com banco migrado tem que SUBIR para o
      // estado de erro com retry; o SELECT direto aqui, além de desligar a
      // paginação em silêncio, ignora ranking e slots patrocinados.
      // Página 2+ nunca tem fallback; o botão avisa sem derrubar a lista.
      if (offset > 0 || error.code != 'PGRST202') rethrow;

      final rows = await SupabaseConfig.client
          .from('law_firms')
          .select()
          .eq('is_active', true)
          .order('rating', ascending: false);

      return DiscoveryPage.last(
        _filterLawFirms(rows.map<LawFirm>(firmFromRow).toList(), searchQuery),
      );
    }
  }

  Future<LawFirm?> fetchLawFirmById(String lawFirmId) async {
    final row = await SupabaseConfig.client
        .from('law_firms')
        .select()
        .eq('id', lawFirmId)
        .maybeSingle();

    if (row == null) return null;
    return firmFromRow(row);
  }

  /// Parser público e estático: o repositório de favoritos devolve linhas
  /// com a MESMA forma (por contrato da migration) e reusa este parser.
  static LawFirm firmFromRow(Map<String, dynamic> row) {
    final specialty = row['specialty'] as String? ?? 'Escritório jurídico';

    return LawFirm(
      id: row['id'] as String,
      name: row['name'] as String,
      initials: row['initials'] as String,
      rating: (row['rating'] as num).toDouble(),
      // distance_label era um rótulo FAKE herdado do seed (só os 3 demos têm
      // valor). Distância agora é calculada no aparelho a partir de
      // latitude/longitude; o campo legado não é mais exibido em produção
      // (os mocks do modo demo mantêm o valor via construtor const).
      distance: '',
      specialty: specialty,
      practiceAreas: _practiceAreasFromRow(
        row['practice_areas'],
        fallback: [specialty],
      ),
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'blue',
      avatarUrl: _optionalText(row['avatar_url']),
      description: row['description'] as String?,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      websiteUrl: row['website_url'] as String?,
      address: row['address'] as String?,
      cep: _optionalText(row['cep']),
      // Ausente no fallback de leitura direta da tabela — vira false, sem selo.
      isFeatured: row['is_featured'] as bool? ?? false,
      isSponsoredSlot: row['is_sponsored_slot'] as bool? ?? false,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
    );
  }

  static String? _optionalText(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  List<LawFirm> _filterLawFirms(List<LawFirm> lawFirms, String query) {
    return lawFirms
        .where(
          (lawFirm) => matchesPracticeAreaSearch(
            practiceAreas: lawFirm.practiceAreas,
            query: query,
            extraFields: [lawFirm.name, lawFirm.specialty],
          ),
        )
        .toList();
  }

  static List<String> _practiceAreasFromRow(
    Object? value, {
    List<String>? fallback,
  }) {
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
}
