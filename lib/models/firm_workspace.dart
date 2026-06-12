import 'firm_role.dart';
import 'firm_team_member.dart';
import 'law_firm.dart';

class FirmWorkspace {
  final LawFirm firm;
  final FirmRole currentUserRole;
  final List<FirmTeamMember> teamMembers;
  final bool fromSupabase;

  const FirmWorkspace({
    required this.firm,
    required this.currentUserRole,
    required this.teamMembers,
    required this.fromSupabase,
  });
}
