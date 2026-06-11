import '../models/lawyer_status.dart';
import '../models/user_profile.dart';
import '../services/supabase_config.dart';

class ProfileRepository {
  const ProfileRepository();

  Future<UserProfile?> fetchCurrentProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    final row = await SupabaseConfig.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return _fromRow(row);
  }

  Future<void> upsertProfile({
    required String id,
    required String fullName,
    required String email,
    String? cpf,
    String? phone,
  }) async {
    await SupabaseConfig.client.from('profiles').upsert({
      'id': id,
      'full_name': fullName,
      'email': email,
      'initials': _initialsFor(fullName),
      'cpf': cpf,
      'phone': phone,
    });
  }

  UserProfile _fromRow(Map<String, dynamic> row) {
    final status = switch (row['lawyer_status'] as String? ?? 'client') {
      'pending' => LawyerStatus.pending,
      'approved' => LawyerStatus.approved,
      _ => LawyerStatus.client,
    };

    return UserProfile(
      id: row['id'] as String,
      name: row['full_name'] as String,
      email: row['email'] as String,
      initials: row['initials'] as String,
      memberSince: 'Cliente desde ${row['member_since'] ?? ''}',
      oabNumber: row['oab_number'] as String?,
      lawyerStatus: status,
    );
  }

  String _initialsFor(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'J';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
