import '../models/business_hours.dart';
import '../services/supabase_config.dart';

/// Horários de atendimento do escritório.
///
/// Leitura direta da tabela (a política de RLS libera para todo autenticado —
/// é informação que existe para o CLIENTE ver antes de escrever). Escrita só
/// por RPC, que valida o portão de gestor e troca o conjunto inteiro numa
/// transação.
class BusinessHoursRepository {
  const BusinessHoursRepository();

  Future<BusinessHours> fetch(String lawFirmId) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return BusinessHours.empty;
    }

    final rows = await SupabaseConfig.client
        .from('law_firm_business_hours')
        .select('weekday, opens_at, closes_at')
        .eq('law_firm_id', lawFirmId)
        .order('weekday')
        .order('opens_at');

    return BusinessHours(
      rows
          .cast<Map<String, dynamic>>()
          .map(BusinessHourInterval.fromRow)
          .toList(growable: false),
    );
  }

  /// Grava o conjunto inteiro e devolve o que ficou.
  ///
  /// Substituir tudo, e não editar linha a linha, é o que evita o cliente ver
  /// um estado intermediário — sexta-feira sumida por um instante porque a
  /// tela ainda estava gravando.
  Future<BusinessHours> save({
    required String lawFirmId,
    required List<BusinessHourInterval> intervals,
  }) async {
    final rows = await SupabaseConfig.client.rpc(
      'set_law_firm_business_hours',
      params: {
        'law_firm_id_value': lawFirmId,
        'hours_value': intervals.map((i) => i.toJson()).toList(),
      },
    );

    return BusinessHours(
      (rows as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BusinessHourInterval.fromRow)
          .toList(growable: false),
    );
  }
}
