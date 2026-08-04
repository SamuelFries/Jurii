import '../services/supabase_config.dart';

/// Apresentação pública do profissional: a bio do advogado e a descrição do
/// escritório. Leitura direta (a coluna é pública, é o que o cliente vê);
/// escrita só por RPC, que valida tamanho e transforma vazio em NULL para o
/// texto padrão voltar quando o profissional limpa o campo.
class ProfessionalBioRepository {
  const ProfessionalBioRepository();

  /// Espelha o teto do servidor (`update_lawyer_bio` / `update_law_firm_description`).
  static const int maxLength = 800;

  bool get isAvailable =>
      SupabaseConfig.isReady && SupabaseConfig.client.auth.currentUser != null;

  /// Bio do próprio advogado, crua — nula quando nunca escreveu. Não usa o
  /// perfil público de propósito: lá o nulo já vem trocado pelo texto padrão,
  /// e o editor abriria pré-preenchido com uma frase que não é dele.
  Future<String?> fetchMyBio() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    final row = await SupabaseConfig.client
        .from('lawyer_profiles')
        .select('bio')
        .eq('id', user.id)
        .maybeSingle();

    return row?['bio'] as String?;
  }

  Future<String?> saveMyBio(String? bio) async {
    final result = await SupabaseConfig.client.rpc(
      'update_lawyer_bio',
      params: {'bio_value': bio},
    );
    return result as String?;
  }

  Future<String?> saveLawFirmDescription({
    required String lawFirmId,
    required String? description,
  }) async {
    final result = await SupabaseConfig.client.rpc(
      'update_law_firm_description',
      params: {
        'law_firm_id_value': lawFirmId,
        'description_value': description,
      },
    );
    return result as String?;
  }
}
