import 'package:flutter/foundation.dart';

import '../services/supabase_config.dart';

/// Alvo de um evento de descoberta.
enum DiscoveryTarget {
  lawyer('lawyer'),
  lawFirm('law_firm');

  const DiscoveryTarget(this.value);

  final String value;
}

/// Registro de alcance na descoberta — o número que sustenta a cobrança do
/// patrocínio.
///
/// Todo método aqui falha em SILÊNCIO. Medição é subproduto: se o registro cair,
/// a pessoa que está procurando advogado não pode ver erro nenhum por causa
/// disso. O custo de perder um evento é um número levemente menor; o custo de
/// mostrar um erro é a busca parecer quebrada.
class DiscoveryMetricsRepository {
  const DiscoveryMetricsRepository();

  /// Registra que estes profissionais APARECERAM numa lista de descoberta.
  ///
  /// [sponsoredIds] são os que ocuparam vaga paga — separado de "tem patrocínio
  /// ativo" de propósito: quem paga também aparece organicamente quando as duas
  /// vagas já estão tomadas, e distinguir os dois é o que responde se a vaga
  /// entrega alguma coisa.
  ///
  /// O servidor deduplica por (dia, alvo, quem viu): chamar de novo na mesma
  /// rolagem não infla nada, então não há por que o app se controlar aqui.
  Future<void> logImpressions({
    required DiscoveryTarget target,
    required List<String> targetIds,
    List<String> sponsoredIds = const [],
  }) {
    return _log(
      eventType: 'impression',
      target: target,
      targetIds: targetIds,
      sponsoredIds: sponsoredIds,
    );
  }

  Future<void> logProfileView({
    required DiscoveryTarget target,
    required String targetId,
  }) {
    return _log(
      eventType: 'profile_view',
      target: target,
      targetIds: [targetId],
    );
  }

  Future<void> _log({
    required String eventType,
    required DiscoveryTarget target,
    required List<String> targetIds,
    List<String> sponsoredIds = const [],
  }) async {
    if (targetIds.isEmpty ||
        !SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return;
    }

    try {
      await SupabaseConfig.client.rpc(
        'log_discovery_events',
        params: {
          'event_type_value': eventType,
          'target_type_value': target.value,
          'target_ids_value': targetIds,
          'sponsored_ids_value': sponsoredIds,
        },
      );
    } catch (error) {
      debugPrint('Discovery metrics failed: $error');
    }
  }
}
