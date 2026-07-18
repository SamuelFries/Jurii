import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_avatar_file.dart';
import '../services/supabase_config.dart';

class StoredProfileAvatar {
  const StoredProfileAvatar({required this.path});

  final String path;
}

class ProfileAvatarStorage {
  const ProfileAvatarStorage();

  static const String bucket = 'profile-avatars';

  Future<StoredProfileAvatar> upload({
    required String userId,
    required ProfileAvatarFile file,
  }) async {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '$userId/avatar-$timestamp-${_safeFileName(file.fileName)}';

    await SupabaseConfig.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );

    return StoredProfileAvatar(path: path);
  }

  Future<void> removePath(String path) async {
    await SupabaseConfig.client.storage.from(bucket).remove([path]);
  }

  String? ownedPathFromPublicUrl(String? value, {required String userId}) {
    if (value == null || value.trim().isEmpty) return null;
    const marker = '/storage/v1/object/public/$bucket/';
    final markerIndex = value.indexOf(marker);
    if (markerIndex < 0) return null;

    final encodedPath = value
        .substring(markerIndex + marker.length)
        .split(RegExp(r'[?#]'))
        .first;
    String path;
    try {
      path = Uri.decodeComponent(encodedPath);
    } catch (_) {
      return null;
    }
    return path.startsWith('$userId/') ? path : null;
  }

  String _safeFileName(String fileName) {
    final parts = fileName
        .split(RegExp(r'[\\/]'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    final name = parts.isEmpty ? 'avatar' : parts.last;
    final sanitized = name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (sanitized.isEmpty) return 'avatar';
    if (sanitized.length <= 160) return sanitized;

    final dot = sanitized.lastIndexOf('.');
    final extension = dot > 0 && sanitized.length - dot <= 12
        ? sanitized.substring(dot)
        : '';
    return '${sanitized.substring(0, 160 - extension.length)}$extension';
  }
}
