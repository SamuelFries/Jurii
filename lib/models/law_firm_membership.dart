import 'firm_role.dart';

class LawFirmMembership {
  final String firmId;
  final String profileId;
  final FirmRole role;
  final bool active;

  const LawFirmMembership({
    required this.firmId,
    required this.profileId,
    required this.role,
    this.active = true,
  });
}
