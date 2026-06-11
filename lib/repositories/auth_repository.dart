import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_config.dart';
import 'profile_repository.dart';

class AuthRepository {
  const AuthRepository({this.profileRepository = const ProfileRepository()});

  final ProfileRepository profileRepository;

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
      data: {'full_name': fullName},
    );

    final user = response.user;
    if (user != null) {
      await profileRepository.upsertProfile(
        id: user.id,
        fullName: fullName,
        email: email,
        cpf: cpf,
      );
    }

    return response;
  }

  Future<void> signOut() => SupabaseConfig.client.auth.signOut();
}
