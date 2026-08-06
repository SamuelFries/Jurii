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

  Future<void> sendPasswordResetEmail(String email) {
    return SupabaseConfig.client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirectUrl,
    );
  }

  Future<void> updatePassword(String password) {
    return SupabaseConfig.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  /// `true` quando a conta tem senha própria (cadastro por e-mail).
  ///
  /// Quem entrou só por Google ou Apple nunca teve senha: pedir a senha atual
  /// para essa pessoa seria um beco sem saída.
  bool get hasEmailPassword {
    final identities = SupabaseConfig.client.auth.currentUser?.identities;
    if (identities == null || identities.isEmpty) return true;
    return identities.any((identity) => identity.provider == 'email');
  }

  /// Troca a senha de quem já está logado.
  ///
  /// A senha atual é conferida com um login de verdade porque o Supabase não
  /// expõe "valide esta senha": `updateUser` sozinho trocaria a senha sem
  /// perguntar nada, e aí qualquer um com o celular destravado tranca o dono
  /// para fora da conta. Login errado NÃO derruba a sessão atual — o pior caso
  /// é a mensagem de senha incorreta.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) throw StateError('User must be authenticated.');

    if (hasEmailPassword) {
      final email = user.email;
      if (email == null || email.isEmpty) {
        throw StateError('Account has no e-mail to verify against.');
      }
      await signIn(email: email, password: currentPassword);
    }

    await updatePassword(newPassword);
  }

  Future<void> signOut() => SupabaseConfig.client.auth.signOut();
}
