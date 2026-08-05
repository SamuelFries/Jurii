import '../models/professional_reach.dart';
import '../services/supabase_config.dart';
import 'discovery_metrics_repository.dart';

class ProfessionalReachRepository {
  const ProfessionalReachRepository();

  /// Busca a série de alcance do profissional.
  ///
  /// Pede o DOBRO de [windowDays] ao servidor de propósito: a metade recente é
  /// o que aparece na tela e a antiga serve só para a comparação ("+12% que no
  /// período anterior"). Uma chamada em vez de duas.
  Future<ReachSummary> fetchReach({
    required DiscoveryTarget target,
    required String targetId,
    int windowDays = 30,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return summarizeReach(const [], windowDays);
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_professional_reach',
      params: {
        'target_type_value': target.value,
        'target_id_value': targetId,
        'days_value': windowDays * 2,
      },
    );

    final dias = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ReachDay.fromRow)
        .toList();

    return summarizeReach(dias, windowDays);
  }
}
