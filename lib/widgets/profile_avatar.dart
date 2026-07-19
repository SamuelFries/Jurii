import 'package:flutter/material.dart';

import '../services/supabase_config.dart';

const _publicAvatarMarker = '/storage/v1/object/public/profile-avatars/';
const _publicLawFirmAvatarMarker =
    '/storage/v1/object/public/law-firm-avatars/';
final _profileAvatarPathPattern = RegExp(
  r'^[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,240}$',
);
final _lawFirmAvatarPathPattern = RegExp(
  r'^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,160}$',
);

/// Avatar de perfil com foto remota e fallback consistente para as iniciais.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.initials,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderRadius,
    this.imageUrl,
    this.fontSize,
    this.fontWeight = FontWeight.w900,
  });

  final String? imageUrl;
  final String initials;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;
  final BorderRadius borderRadius;
  final double? fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final url = _trustedAvatarUrl(imageUrl);

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: backgroundColor,
          child: url == null || url.isEmpty
              ? _InitialsFallback(
                  initials: initials,
                  foregroundColor: foregroundColor,
                  fontSize: fontSize ?? size * 0.32,
                  fontWeight: fontWeight,
                )
              : Image.network(
                  url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _InitialsFallback(
                      initials: initials,
                      foregroundColor: foregroundColor,
                      fontSize: fontSize ?? size * 0.32,
                      fontWeight: fontWeight,
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _InitialsFallback(
                      initials: initials,
                      foregroundColor: foregroundColor,
                      fontSize: fontSize ?? size * 0.32,
                      fontWeight: fontWeight,
                    );
                  },
                ),
        ),
      ),
    );
  }

  String? _trustedAvatarUrl(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;

    final isLawFirmAvatar = raw.contains(_publicLawFirmAvatarMarker);
    final marker = isLawFirmAvatar
        ? _publicLawFirmAvatarMarker
        : _publicAvatarMarker;
    final pathPattern = isLawFirmAvatar
        ? _lawFirmAvatarPathPattern
        : _profileAvatarPathPattern;
    final markerIndex = raw.indexOf(marker);
    if (markerIndex < 0) return null;

    final encodedPath = raw
        .substring(markerIndex + marker.length)
        .split(RegExp(r'[?#]'))
        .first;
    String storagePath;
    try {
      storagePath = Uri.decodeComponent(encodedPath);
    } catch (_) {
      return null;
    }
    if (!pathPattern.hasMatch(storagePath)) return null;

    final projectUri = Uri.tryParse(SupabaseConfig.url.trim());
    if (projectUri == null ||
        !projectUri.hasScheme ||
        projectUri.host.isEmpty ||
        (projectUri.scheme != 'https' && projectUri.scheme != 'http')) {
      return null;
    }

    final port = projectUri.hasPort ? ':${projectUri.port}' : '';
    final origin = '${projectUri.scheme}://${projectUri.host}$port';
    return '$origin$marker$storagePath';
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({
    required this.initials,
    required this.foregroundColor,
    required this.fontSize,
    required this.fontWeight,
  });

  final String initials;
  final Color foregroundColor;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final label = initials.trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label.isEmpty ? '?' : label,
            maxLines: 1,
            style: TextStyle(
              color: foregroundColor,
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
          ),
        ),
      ),
    );
  }
}
