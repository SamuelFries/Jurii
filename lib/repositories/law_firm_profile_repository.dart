import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/law_firm.dart';
import '../models/profile_avatar_file.dart';
import '../services/supabase_config.dart';
import 'law_firm_repository.dart';

/// Logo do escritório no bucket público `law-firm-avatars`.
///
/// Caminho por FIRMA (`{escritorio}/{arquivo}`), e não pelo cadastro. O caminho
/// antigo carregava o id da verificação e o uid de quem a abriu — o que
/// impedia um admin de trocar o logo e travava tudo assim que a verificação
/// era aprovada.
class LawFirmLogoStorage {
  const LawFirmLogoStorage();

  static const String bucket = 'law-firm-avatars';

  Future<String> upload({
    required String lawFirmId,
    required ProfileAvatarFile file,
  }) async {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '$lawFirmId/logo-$timestamp-${_safeFileName(file.fileName)}';

    await SupabaseConfig.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );

    return path;
  }

  Future<void> removePath(String path) async {
    await SupabaseConfig.client.storage.from(bucket).remove([path]);
  }

  String _safeFileName(String fileName) {
    final parts = fileName
        .split(RegExp(r'[\\/]'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    final name = parts.isEmpty ? 'logo' : parts.last;
    final sanitized = name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (sanitized.isEmpty) return 'logo';
    if (sanitized.length <= 120) return sanitized;

    final dot = sanitized.lastIndexOf('.');
    final extension = dot > 0 && sanitized.length - dot <= 12
        ? sanitized.substring(dot)
        : '';
    return '${sanitized.substring(0, 120 - extension.length)}$extension';
  }
}

class LawFirmProfileRepository {
  const LawFirmProfileRepository({
    this.logoStorage = const LawFirmLogoStorage(),
  });

  final LawFirmLogoStorage logoStorage;

  /// Grava o cadastro. O servidor repete cada validação e é quem decide se
  /// quem chamou fala pelo escritório.
  Future<LawFirm> updateProfile({
    required String lawFirmId,
    required String name,
    String? phone,
    String? email,
    String? websiteUrl,
    String? address,
    String? cep,
    double? latitude,
    double? longitude,
    String? primaryArea,
    List<String> practiceAreas = const [],
    ProfileAvatarFile? logo,
    bool removeLogo = false,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    String? storedPath;
    if (logo != null) {
      storedPath = await logoStorage.upload(lawFirmId: lawFirmId, file: logo);
    }

    final avatarAction = storedPath != null
        ? 'replace'
        : removeLogo
        ? 'remove'
        : 'preserve';

    try {
      final row = await SupabaseConfig.client
          .rpc(
            'update_law_firm_profile',
            params: {
              'law_firm_id_value': lawFirmId,
              'name_value': name,
              'phone_value': phone,
              'email_value': email,
              'website_url_value': websiteUrl,
              'address_value': address,
              'cep_value': cep,
              'latitude_value': latitude,
              'longitude_value': longitude,
              'primary_area_value': primaryArea,
              'practice_areas_value': practiceAreas,
              'avatar_action_value': avatarAction,
              'avatar_storage_path_value': storedPath,
            },
          )
          .single();

      return LawFirmRepository.firmFromRow(row);
    } catch (error) {
      // O arquivo já subiu mas o cadastro não gravou: sem esta limpeza fica um
      // logo órfão no bucket público, pago e sem dono.
      if (storedPath != null) {
        try {
          await logoStorage.removePath(storedPath);
        } catch (cleanupError) {
          debugPrint('Firm logo cleanup failed: $cleanupError');
        }
      }
      rethrow;
    }
  }
}
