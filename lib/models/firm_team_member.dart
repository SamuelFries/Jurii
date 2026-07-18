import 'firm_role.dart';

class FirmTeamMember {
  final String id;
  final String name;
  final String initials;
  final String? avatarUrl;
  final FirmRole role;
  final List<FirmRole> roles;
  final String specialty;
  final int activeCases;
  final double responseHours;
  final double rating;
  final bool available;

  const FirmTeamMember({
    required this.id,
    required this.name,
    required this.initials,
    this.avatarUrl,
    required this.role,
    this.roles = const [],
    required this.specialty,
    required this.activeCases,
    required this.responseHours,
    required this.rating,
    required this.available,
  });

  List<FirmRole> get effectiveRoles {
    return roles.isEmpty ? [role] : FirmRole.normalize(roles);
  }

  String get roleLabel => effectiveRoles.labels;

  bool get canReceiveCaseAssignment => available && effectiveRoles.hasLawyer;
}
