import 'package:flutter/foundation.dart';

import '../data/legal_practice_areas.dart';
import '../models/firm_operation_metrics.dart';
import '../models/firm_role.dart';
import '../models/firm_team_member.dart';
import '../models/firm_workspace.dart';
import '../models/law_firm.dart';
import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_status.dart';
import '../services/supabase_config.dart';

class FirmWorkspaceRepository {
  const FirmWorkspaceRepository();

  Future<FirmOperationMetrics> fetchLawFirmOperationMetrics(
    String lawFirmId,
  ) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      return const FirmOperationMetrics.empty();
    }

    final rows = await SupabaseConfig.client.rpc(
      'fetch_law_firm_operation_metrics',
      params: {'law_firm_id_value': lawFirmId},
    );

    final data = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    if (data.isEmpty) return const FirmOperationMetrics.empty();

    final row = data.first;
    return FirmOperationMetrics(
      clientMessages: row['client_messages'] as int? ?? 0,
      teamMessages: row['team_messages'] as int? ?? 0,
      activeCases: row['active_cases'] as int? ?? 0,
      teamMembers: row['team_members'] as int? ?? 0,
    );
  }

  Future<FirmWorkspace?> fetchCurrentWorkspace({
    LawFirmVerification? verification,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    final membershipWorkspace = await _fetchWorkspaceFromMembership(user.id);
    if (membershipWorkspace != null) return membershipWorkspace;

    // Em ambiente real, uma verificacao aprovada prova apenas que o escritorio
    // foi validado; autoridade vem exclusivamente de membership ativo. Isso
    // impede que um ex-dono continue entrando pela verificacao historica.
    if (SupabaseConfig.isReady) return null;

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
          currentUserRoles: const [FirmRole.owner],
          teamMembers: _teamWithCurrentOwner(user.id, verification),
          fromSupabase: true,
        );
      }
    }

    return _workspaceFromApprovedVerification(user.id, verification!);
  }

  Future<FirmWorkspace?> _fetchWorkspaceFromMembership(String profileId) async {
    final rows = await _fetchActiveMembershipRows(profileId);

    if (rows.isEmpty) return null;

    final membership = rows.first;
    final firmRow = membership['law_firms'];
    if (firmRow is! Map<String, dynamic>) return null;

    final firm = _firmFromRow(firmRow);
    final roles = _rolesFromRow(
      membership['roles'],
      membership['member_role'] as String? ?? membership['role'] as String?,
    );
    final role = FirmRole.primaryFrom(roles);

    return FirmWorkspace(
      firm: firm,
      currentUserRole: role,
      currentUserRoles: roles,
      teamMembers: await _fetchTeamMembers(firm.id, profileId, roles),
      fromSupabase: true,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchActiveMembershipRows(
    String profileId,
  ) async {
    try {
      final rows = await SupabaseConfig.client
          .from('law_firm_members')
          .select(
            'law_firm_id, profile_id, roles, member_role, role, status, law_firms(*)',
          )
          .eq('profile_id', profileId)
          .eq('status', 'active')
          // Ordenação estável: membro de 2+ escritórios sempre entra no mais
          // antigo (até existir um seletor de escritório).
          .order('joined_at', ascending: true)
          .limit(1);

      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      final rows = await SupabaseConfig.client
          .from('law_firm_members')
          .select(
            'law_firm_id, profile_id, member_role, role, status, law_firms(*)',
          )
          .eq('profile_id', profileId)
          .eq('status', 'active')
          .order('joined_at', ascending: true)
          .limit(1);

      return rows.cast<Map<String, dynamic>>();
    }
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
    List<FirmRole> currentUserRoles,
  ) async {
    try {
      final rows = await _fetchTeamMemberRows(lawFirmId);

      if (rows.isEmpty) return const [];

      return rows.map<FirmTeamMember>((row) {
        final profileId = row['profile_id'] as String? ?? '';
        final lawyerId = row['lawyer_id'] as String?;
        final status = row['status'] as String? ?? 'active';
        final profileRow = row['profiles'];
        final rowRoles = _rolesFromRow(
          row['roles'],
          row['member_role'] as String? ?? row['role'] as String?,
        );
        final isCurrentUser = profileId == currentProfileId;
        final effectiveRoles = isCurrentUser ? currentUserRoles : rowRoles;
        final role = FirmRole.primaryFrom(effectiveRoles);
        final profileName = profileRow is Map<String, dynamic>
            ? profileRow['full_name'] as String?
            : null;
        final profileInitials = profileRow is Map<String, dynamic>
            ? profileRow['initials'] as String?
            : null;
        final profileAvatarUrl = profileRow is Map<String, dynamic>
            ? _optionalText(profileRow['avatar_url'])
            : null;

        return FirmTeamMember(
          id: profileId.isEmpty ? 'member_${rows.indexOf(row)}' : profileId,
          name: isCurrentUser ? 'Você' : profileName ?? _roleName(role),
          initials: isCurrentUser
              ? 'VC'
              : profileInitials ?? _roleInitials(role),
          avatarUrl: profileAvatarUrl,
          role: role,
          roles: effectiveRoles,
          specialty: status == 'invited'
              ? 'Convite pendente'
              : _rolesSpecialty(effectiveRoles, isAlsoLawyer: lawyerId != null),
          // Métricas por membro ainda não existem no banco; zero = a UI
          // esconde o badge em vez de exibir número inventado.
          activeCases: 0,
          responseHours: 0,
          rating: 0,
          available: status == 'active',
        );
      }).toList();
    } catch (error) {
      // Falha real não pode virar equipe fake — lista vazia e log.
      debugPrint('Supabase firm team members fetch failed: $error');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTeamMemberRows(
    String lawFirmId,
  ) async {
    try {
      final rows = await SupabaseConfig.client
          .from('law_firm_members')
          .select(
            'profile_id, lawyer_id, roles, member_role, role, status, profiles(full_name, initials, avatar_url)',
          )
          .eq('law_firm_id', lawFirmId)
          .neq('status', 'disabled');

      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      final rows = await SupabaseConfig.client
          .from('law_firm_members')
          .select(
            'profile_id, lawyer_id, member_role, role, status, profiles(full_name, initials, avatar_url)',
          )
          .eq('law_firm_id', lawFirmId)
          .neq('status', 'disabled');

      return rows.cast<Map<String, dynamic>>();
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
      specialty: primaryPracticeArea(verification.practiceAreas),
      practiceAreas: verification.practiceAreas,
      reviews: 0,
      avatarType: 'purple',
    );

    return FirmWorkspace(
      firm: firm,
      currentUserRole: FirmRole.owner,
      currentUserRoles: const [FirmRole.owner],
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
        roles: const [FirmRole.owner],
        specialty: 'Líder',
        activeCases: 0,
        responseHours: 0,
        rating: 0,
        available: true,
      ),
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
      practiceAreas: _practiceAreasFromRow(
        row['practice_areas'],
        fallback: [row['specialty'] as String? ?? ''],
      ),
      reviews: row['reviews_count'] as int? ?? 0,
      avatarType: row['avatar_type'] as String? ?? 'purple',
    );
  }

  List<String> _practiceAreasFromRow(Object? value, {List<String>? fallback}) {
    final areas = value is List
        ? value.whereType<String>().toList()
        : const <String>[];
    final cleanAreas = areas
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
    if (cleanAreas.isNotEmpty) return cleanAreas;

    return (fallback ?? const <String>[])
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();
  }

  Future<void> updateMemberRoles({
    required String lawFirmId,
    required String memberProfileId,
    required List<FirmRole> roles,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexao com o Supabase nao esta ativa.');
    }

    await SupabaseConfig.client.rpc(
      'update_law_firm_member_roles',
      params: {
        'law_firm_id_value': lawFirmId,
        'member_profile_id_value': memberProfileId,
        'roles_value': FirmRole.normalize(roles).values,
      },
    );
  }

  List<FirmRole> _rolesFromRow(Object? value, String? fallbackRole) {
    final rowRoles = value is List
        ? value
              .whereType<String>()
              .map(FirmRole.fromValue)
              .toList(growable: false)
        : const <FirmRole>[];

    if (rowRoles.isNotEmpty) return FirmRole.normalize(rowRoles);
    return FirmRole.normalize([_roleFromRow(fallbackRole)]);
  }

  FirmRole _roleFromRow(String? value) {
    return switch (value) {
      'owner' => FirmRole.owner,
      'admin' => FirmRole.admin,
      'secretary' => FirmRole.secretary,
      'lawyer' => FirmRole.lawyer,
      'intern' => FirmRole.intern,
      _ => FirmRole.lawyer,
    };
  }

  String _roleName(FirmRole role) {
    return switch (role) {
      FirmRole.owner => 'Líder do escritório',
      FirmRole.admin => 'Administrador',
      FirmRole.secretary => 'Secretaria',
      FirmRole.lawyer => 'Advogado associado',
      FirmRole.intern => 'Estagiário',
    };
  }

  String _roleInitials(FirmRole role) {
    return switch (role) {
      FirmRole.owner => 'DO',
      FirmRole.admin => 'AD',
      FirmRole.secretary => 'SE',
      FirmRole.lawyer => 'AA',
      FirmRole.intern => 'EA',
    };
  }

  String _rolesSpecialty(List<FirmRole> roles, {bool isAlsoLawyer = false}) {
    final normalizedRoles = FirmRole.normalize(roles);
    if (normalizedRoles.length > 1) return normalizedRoles.labels;

    return _roleSpecialty(normalizedRoles.first, isAlsoLawyer: isAlsoLawyer);
  }

  String _roleSpecialty(FirmRole role, {bool isAlsoLawyer = false}) {
    return switch (role) {
      FirmRole.intern => 'Apoio limitado',
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

  String? _optionalText(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }
}
