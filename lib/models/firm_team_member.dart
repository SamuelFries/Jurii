import 'firm_role.dart';

class FirmTeamMember {
  final String id;
  final String name;
  final String initials;
  final FirmRole role;
  final String specialty;
  final int activeCases;
  final double responseHours;
  final double rating;
  final bool available;

  const FirmTeamMember({
    required this.id,
    required this.name,
    required this.initials,
    required this.role,
    required this.specialty,
    required this.activeCases,
    required this.responseHours,
    required this.rating,
    required this.available,
  });
}
