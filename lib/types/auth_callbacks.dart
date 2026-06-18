import '../models/social_auth_provider.dart';

typedef LoginSubmit = Future<void> Function(String email, String password);

typedef SocialLoginSubmit = Future<void> Function(SocialAuthProvider provider);

enum RegisterResult { signedIn, needsEmailConfirmation }

typedef RegisterSubmit =
    Future<RegisterResult> Function({
      required String fullName,
      required String email,
      required String cpf,
      required String password,
    });
