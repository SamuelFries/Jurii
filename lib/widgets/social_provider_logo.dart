import 'package:flutter/material.dart';

import '../models/social_auth_provider.dart';
import '../theme/app_colors.dart';

class SocialProviderLogo extends StatelessWidget {
  const SocialProviderLogo({super.key, required this.provider, this.size = 22});

  final SocialAuthProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      switch (provider) {
        SocialAuthProvider.google =>
          'assets/images/google_logo_transparent.png',
        SocialAuthProvider.apple => 'assets/images/apple_logo_transparent.png',
      },
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
    );

    if (provider == SocialAuthProvider.apple) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          context.jColors.textPrimary,
          BlendMode.srcIn,
        ),
        child: image,
      );
    }

    return image;
  }
}
