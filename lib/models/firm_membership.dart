import 'firm_role.dart';

/// UM VÍNCULO da pessoa com um escritório.
///
/// O cargo pertence ao vínculo, não à pessoa: quem é sócio numa banca pode ser
/// estagiário em outra, e as duas coisas são verdade ao mesmo tempo. Por isso
/// [roles] vem aqui dentro, e não num campo global do usuário.
///
/// É o mínimo para montar o seletor: nome, cargo e o id para abrir. O
/// [FirmWorkspace] completo (equipe, métricas) só é carregado do escritório
/// que está aberto, porque carregar os três de uma vez custaria três consultas
/// para mostrar duas linhas de menu.
class FirmMembership {
  final String firmId;
  final String firmName;
  final String initials;
  final String? avatarUrl;
  final String? oabState;
  final List<FirmRole> roles;

  const FirmMembership({
    required this.firmId,
    required this.firmName,
    required this.initials,
    this.avatarUrl,
    this.oabState,
    required this.roles,
  });

  FirmRole get primaryRole => FirmRole.primaryFrom(roles);

  static FirmMembership fromRow(Map<String, dynamic> row) {
    // A RPC já devolve os papéis normalizados pelo banco
    // (normalize_law_firm_member_roles), então aqui é só converter. O
    // `primary_role` entra como rede quando o array vier vazio, que o banco
    // não permite mas um ambiente antigo poderia.
    final rawRoles = row['roles'];
    final parsed = <FirmRole>[];
    if (rawRoles is List) {
      for (final item in rawRoles) {
        parsed.add(FirmRole.fromValue(item?.toString()));
      }
    }
    if (parsed.isEmpty) {
      parsed.add(FirmRole.fromValue(row['primary_role']?.toString()));
    }

    return FirmMembership(
      firmId: row['law_firm_id'].toString(),
      firmName: row['law_firm_name']?.toString() ?? 'Escritório',
      initials: row['law_firm_initials']?.toString() ?? 'ES',
      avatarUrl: row['avatar_url']?.toString(),
      oabState: row['oab_state']?.toString(),
      roles: FirmRole.normalize(parsed),
    );
  }
}
