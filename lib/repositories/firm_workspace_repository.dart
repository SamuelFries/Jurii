import '../data/mock/mock_firm_workspace.dart';
import '../models/firm_role.dart';
import '../models/firm_team_member.dart';
import '../models/firm_workspace.dart';
import '../models/law_firm.dart';
import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_status.dart';
import '../services/supabase_config.dart';

class FirmWorkspaceRepository {
  const FirmWorkspaceRepository();

  Future<FirmWorkspace?> fetchCurrentWorkspace({
    LawFirmVerification? verification,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    final membershipWorkspace = await _fetchWorkspaceFromMembership(user.id);
    if (membershipWorkspace != null) return membershipWorkspace;

    if (verification?.status != LawFirmVerificationStatus.approved) {
      return null;
    }

    final lawFirmId = verification?.lawFirmId;
    if (lawFirmId != null && lawFirmId.isNotEmpty) {
      final firm = await _fetchFirmById(lawFirmId);
      if (firm != null) {
        return FirmWorkspace(
          firm: firm,
          currentUserRole: FirmRole.owner,
          teamMembers: _teamWithCurrentOwner(user.id, verification),
          fromSupabase: true,
        );
      }
    }

    return _workspaceFromApprovedVerification(user.id, verification!);
  }

  Future<FirmWorkspace?> _fetchWorkspaceFromMembership(String profileId) async {
    final rows = await SupabaseConfig.client
        .from('law_firm_members')
        .select(
          'law_firm_id, profile_id, member_role, role, status, law_firms(*)',
        )
        .eq('profile_id', profileId)
        .eq('status', 'active')
        .limit(1);

    if (rows.isEmpty) return null;

    final membership = rows.first;
    final firmRow = membership['law_firms'];
    if (firmRow is! Map<String, dynamic>) return null;

    final firm = _firmFromRow(firmRow);
    final role = _roleFromRow(
      membership['member_role'] as String? ?? membership['role'] as String?,
    );

    return FirmWorkspace(
      firm: firm,
      currentUserRole: role,
      teamMembers: await _fetchTeamMembers(firm.id, profileId, role),
      fromSupabase: true,
    );
  }

  Future<LawFirm?> _fetchFirmById(String lawFirmId) async {
    final row = await SupabaseConfig.client
        .from('law_firms')
        .select()
        .eq('id', lawFirmId)
        .maybeSingle();

    if (row == null) return null;
    return _firmFromRow(row);
  }

  Future<List<FirmTeamMember>> _fetchTeamMembers(
    String lawFirmId,
    String currentProfileId,
    FirmRole currentUserRole,
  ) async {
    try {
      final rows = await SupabaseConfig.client
          .from('law_firm_members')
          .select(
            'profile_id, lawyer_id, member_role, role, status, profiles(full_name, initials)',
          )
          .eq('law_firm_id', lawFirmId)
          .neq('status', 'disabled');

      if (rows.isEmpty) return mockFirmTeamMembers;

      return rows.map<FirmTeamMember>((row) {
        final profileId = row['profile_id'] as String? ?? '';
        final lawyerId = row['lawyer_id'] as String?;
        final status = row['status'] as String? ?? 'active';
        final profileRow = row['profiles'];
        final role = _roleFromRow(
          row['member_role'] as String? ?? row['role'] as String?,
        );
        final isCurrentUser = profileId == currentProfileId;
        final profileName = profileRow is Map<String, dynamic>
            ? profileRow['full_name'] as String?
            : null;
        final profileInitials = profileRow is Map<String, dynamic>
            ? profileRow['initials'] as String?
            : null;

        return FirmTeamMember(
          id: profileId.isEmpty ? 'member_${rows.indexOf(row)}' : profileId,
          name: isCurrentUser ? 'Você' : profileName ?? _roleName(role),
          initials: isCurrentUser
              ? 'VC'
              : profileInitials ?? _roleInitials(role),
          role: isCurrentUser ? currentUserRole : role,
          specialty: status == 'invited'
              ? 'Convite pendente'
              : _roleSpecialty(role, isAlsoLawyer: lawyerId != null),
          activeCases: role == FirmRole.lawyer ? 3 : 0,
          responseHours: role == FirmRole.secretary ? 0.8 : 1.6,
          rating: role == FirmRole.lawyer ? 4.8 : 4.7,
          available: status == 'active',
        );
      }).toList();
    } catch (_) {
      return mockFirmTeamMembers;
    }
  }

  FirmWorkspace _workspaceFromApprovedVerification(
    String ownerProfileId,
    LawFirmVerification verification,
  ) {
    final firm = LawFirm(
      id: verification.lawFirmId ?? verification.id ?? 'approved_firm',
      name: verification.firmName,
      initials: _initialsFor(verification.firmName),
      rating: 0,
      distance: '',
      specialty: 'Escritório jurídico',
      reviews: 0,
      avatarType: 'purple',
    );

    return FirmWorkspace(
      firm: firm,
      currentUserRole: FirmRole.owner,
      teamMembers: _teamWithCurrentOwner(ownerProfileId, verification),
      fromSupabase: false,
    );
  }

  List<FirmTeamMember> _teamWithCurrentOwner(
    String ownerProfileId,
    LawFirmVerification? verification,
  ) {
    return [
      FirmTeamMember(
        id: ownerProfileId,
        name: 'Você',
        initials: 'VC',
        role: FirmRole.owner,
        specialty: 'Líder',
        activeCases: 0,
        responseHours: 0,
        rating: 0,
        available: true,
      ),
      ...mockFirmTeamMembers,
    ];
  }

  LawFirm _firmFromRow(Map<String, dynamic> row) {
    return LawFirm(
      id: row['id'] as String,
      name: row['name'] as String? ?? 'Escritório',
      initials:
          row['initials'] as String? ??
          _initialsFor(row['name'] as String? ?? ''),
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      distance: row['distance_label'] as String? ?? '',
      specialty: row['specialty'] as String? ?? 'Escritório jurídico',
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'purple',
    );
  }

  FirmRole _roleFromRow(String? value) {
    return switch (value) {
      'admin' => FirmRole.admin,
      'secretary' => FirmRole.secretary,
      'lawyer' => FirmRole.lawyer,
      _ => FirmRole.owner,
    };
  }

  String _roleName(FirmRole role) {
    return switch (role) {
      FirmRole.owner => 'Líder do escritório',
      FirmRole.admin => 'Administrador',
      FirmRole.secretary => 'Secretaria',
      FirmRole.lawyer => 'Advogado associado',
    };
  }

  String _roleInitials(FirmRole role) {
    return switch (role) {
      FirmRole.owner => 'DO',
      FirmRole.admin => 'AD',
      FirmRole.secretary => 'SE',
      FirmRole.lawyer => 'AA',
    };
  }

  String _roleSpecialty(FirmRole role, {bool isAlsoLawyer = false}) {
    return switch (role) {
      FirmRole.owner => isAlsoLawyer ? 'Líder · Advogado' : 'Líder',
      FirmRole.admin => isAlsoLawyer ? 'Admin · Advogado' : 'Operações',
      FirmRole.secretary => 'Atendimento',
      FirmRole.lawyer => 'Jurídico',
    };
  }

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'JE';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
