import 'firm_role.dart';

class LawFirmMembership {
  final String firmId;
  final String profileId;
  final FirmRole role;
  final List<FirmRole> roles;
  final bool active;

  const LawFirmMembership({
    required this.firmId,
    required this.profileId,
    required this.role,
    this.roles = const [],
    this.active = true,
  });

  List<FirmRole> get effectiveRoles {
    return roles.isEmpty ? [role] : FirmRole.normalize(roles);
  }
}
