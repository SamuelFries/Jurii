import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/social_auth_provider.dart';
import '../services/supabase_config.dart';

class AuthRepository {
  const AuthRepository();

  Session? get currentSession => SupabaseConfig.client.auth.currentSession;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return SupabaseConfig.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
    String? cpf,
  }) async {
    final response = await SupabaseConfig.client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'cpf': cpf},
    );

    return response;
  }

  Future<bool> signInWithSocialProvider(SocialAuthProvider provider) {
    final oauthProvider = switch (provider) {
      SocialAuthProvider.google => OAuthProvider.google,
      SocialAuthProvider.apple => OAuthProvider.apple,
    };

    return SupabaseConfig.client.auth.signInWithOAuth(
      oauthProvider,
      redirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() => SupabaseConfig.client.auth.signOut();
}
