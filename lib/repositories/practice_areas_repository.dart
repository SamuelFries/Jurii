import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_config.dart';

/// As áreas de atuação do próprio advogado.
///
/// A RPC `update_lawyer_practice_areas` existe desde a 20260805180000, mas
/// nenhuma tela a chamava: o advogado aprovado não tinha como trocar de área
/// depois do cadastro. Com a taxonomia indo de 10 para 39 áreas
/// (20260816120000), isso deixou de ser um detalhe — as áreas novas não
/// serviriam para ninguém que já estivesse cadastrado.
class PracticeAreasRepository {
  const PracticeAreasRepository();

  Future<LawyerPracticeAreas> fetchMine() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (!SupabaseConfig.isReady || user == null) {
      return const LawyerPracticeAreas(primaryArea: null, areas: []);
    }

    final row = await SupabaseConfig.client
        .from('lawyer_profiles')
        .select('primary_area, practice_areas')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      return const LawyerPracticeAreas(primaryArea: null, areas: []);
    }

    final areas = (row['practice_areas'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
    final primary = (row['primary_area'] as String?)?.trim();

    return LawyerPracticeAreas(
      primaryArea: primary == null || primary.isEmpty ? null : primary,
      // A principal SEMPRE faz parte da lista — o servidor garante isso na
      // escrita, mas um cadastro antigo pode ter chegado sem.
      areas: [
        if (primary != null && primary.isNotEmpty && !areas.contains(primary))
          primary,
        ...areas,
      ],
    );
  }

  /// Grava e devolve a lista como o servidor a normalizou (apelido traduzido,
  /// duplicata removida, principal injetada).
  Future<List<String>> save({
    required String primaryArea,
    required List<String> areas,
  }) async {
    final result = await SupabaseConfig.client.rpc(
      'update_lawyer_practice_areas',
      params: {'primary_area_value': primaryArea, 'practice_areas_value': areas},
    );

    return (result as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
  }
}

class LawyerPracticeAreas {
  const LawyerPracticeAreas({required this.primaryArea, required this.areas});

  final String? primaryArea;
  final List<String> areas;
}

/// Mensagem legível para o erro que o servidor devolve.
///
/// O servidor nomeia a área recusada em `Invalid practice area: X`; jogar isso
/// fora e mostrar "área inválida" deixa a pessoa sem saber qual chip tirar.
String friendlyPracticeAreaError(Object error) {
  final texto = error is PostgrestException
      ? '${error.message} ${error.details ?? ''}'
      : error.toString();

  final nome = RegExp(
    r'invalid practice area: ([^,)\n"]+)',
    caseSensitive: false,
  ).firstMatch(texto)?.group(1)?.trim();

  if (nome != null && nome.isNotEmpty) {
    return 'A área "$nome" não está mais disponível. Escolha outra.';
  }
  if (texto.contains('Primary area is required')) {
    return 'Escolha qual é a sua área principal.';
  }
  if (texto.contains('Lawyer profile not found')) {
    return 'Seu cadastro profissional ainda não foi aprovado.';
  }
  return 'Não foi possível salvar. Tente novamente.';
}
