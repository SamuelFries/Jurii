import 'package:flutter/foundation.dart';

import '../models/lawyer_status.dart';
import '../models/profile_avatar_file.dart';
import '../models/user_profile.dart';
import '../services/supabase_config.dart';
import 'profile_avatar_storage.dart';

class DeletedAccountException implements Exception {
  const DeletedAccountException();

  @override
  String toString() => 'Conta excluída.';
}

class ProfileRepository {
  const ProfileRepository({this.avatarStorage = const ProfileAvatarStorage()});

  final ProfileAvatarStorage avatarStorage;

  Future<UserProfile?> fetchCurrentProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return null;

    // A tabela profiles expoe diretamente apenas colunas publicas. Dados do
    // titular (como email, CPF e telefone) passam por uma RPC que fixa o alvo
    // em auth.uid(), evitando vazar PII para contrapartes de caso/conversa.
    final row = await SupabaseConfig.client
        .rpc('fetch_current_profile')
        .maybeSingle();

    if (row == null) return null;
    if (row['deleted_at'] != null) {
      throw const DeletedAccountException();
    }
    return _fromRow(row);
  }

  Future<UserProfile?> fetchProfileById(String profileId) async {
    final row = await SupabaseConfig.client
        .rpc('fetch_chat_profile', params: {'profile_id_value': profileId})
        .maybeSingle();

    if (row == null) return null;
    return _fromRow(row);
  }

  Future<void> upsertProfile({
    required String fullName,
    String? cpf,
    String? phone,
  }) async {
    if (SupabaseConfig.client.auth.currentUser == null) {
      throw StateError(
        'É necessário estar autenticado para atualizar o perfil.',
      );
    }

    await SupabaseConfig.client.rpc(
      'upsert_current_profile',
      params: {
        'full_name_value': fullName,
        'cpf_value': cpf,
        'phone_value': phone,
      },
    );
  }

  Future<void> deleteCurrentAccount() async {
    try {
      await SupabaseConfig.client.functions.invoke('delete-account');
    } catch (error) {
      debugPrint('Supabase account deletion failed: $error');
      throw StateError(
        'Não foi possível excluir sua conta agora. Tente novamente.',
      );
    }
  }

  Future<UserProfile> updateCustomization({
    required String fullName,
    required String phone,
    required String? previousAvatarUrl,
    ProfileAvatarFile? avatar,
    required bool removeAvatar,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      throw StateError('É necessário estar autenticado para editar o perfil.');
    }

    StoredProfileAvatar? stored;
    if (avatar != null) {
      stored = await avatarStorage.upload(userId: user.id, file: avatar);
    }

    final avatarAction = stored != null
        ? 'replace'
        : removeAvatar
        ? 'remove'
        : 'preserve';

    Map<String, dynamic> row;
    try {
      row = await SupabaseConfig.client
          .rpc(
            'update_current_profile_customization',
            params: {
              'full_name_value': fullName,
              'phone_value': phone,
              'avatar_action_value': avatarAction,
              'avatar_storage_path_value': stored?.path,
            },
          )
          .single();
    } catch (_) {
      if (stored != null) {
        try {
          await avatarStorage.removePath(stored.path);
        } catch (_) {
          // A falha original de persistência é mais útil para o chamador.
        }
      }
      rethrow;
    }

    if (stored != null || removeAvatar) {
      await _removeOldAvatar(previousAvatarUrl, userId: user.id);
    }
    return _fromRow(row);
  }

  Future<void> _removeOldAvatar(
    String? publicUrl, {
    required String userId,
  }) async {
    final path = avatarStorage.ownedPathFromPublicUrl(
      publicUrl,
      userId: userId,
    );
    if (path == null) return;
    try {
      await avatarStorage.removePath(path);
    } catch (error) {
      debugPrint('Old profile avatar cleanup failed: $error');
    }
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
      oabNumber: null,
      lawyerStatus: status,
      avatarUrl: (row['avatar_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : row['avatar_url'] as String,
      // Só fetch_current_profile devolve CPF; no perfil de contraparte
      // (fetch_chat_profile) a coluna nem existe no retorno.
      cpf: row['cpf'] as String?,
      phone: row['phone'] as String?,
    );
  }
}
