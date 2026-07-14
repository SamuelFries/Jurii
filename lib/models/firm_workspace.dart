import 'firm_role.dart';
import 'firm_team_member.dart';
import 'law_firm.dart';

class FirmWorkspace {
  final LawFirm firm;
  final FirmRole currentUserRole;
  final List<FirmRole> currentUserRoles;
  final List<FirmTeamMember> teamMembers;
  final bool fromSupabase;

  const FirmWorkspace({
    required this.firm,
    required this.currentUserRole,
    this.currentUserRoles = const [],
    required this.teamMembers,
    required this.fromSupabase,
  });

  List<FirmRole> get effectiveCurrentUserRoles {
    return currentUserRoles.isEmpty
        ? [currentUserRole]
        : FirmRole.normalize(currentUserRoles);
  }

  bool get isOwner => effectiveCurrentUserRoles.hasOwner;
  bool get canManageMembers => effectiveCurrentUserRoles.canManageFirmMembers;
  bool get canAssignCases => effectiveCurrentUserRoles.canAssignFirmCases;
  bool get canRecommendLawyers =>
      effectiveCurrentUserRoles.canRecommendFirmLawyers;
  bool get canAttendAssignedCases =>
      effectiveCurrentUserRoles.canAttendAssignedFirmCases;
}
