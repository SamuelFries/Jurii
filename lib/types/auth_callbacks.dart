typedef LoginSubmit = Future<void> Function(String email, String password);

enum RegisterResult { signedIn, needsEmailConfirmation }

typedef RegisterSubmit =
    Future<RegisterResult> Function({
      required String fullName,
      required String email,
      required String cpf,
      required String password,
    });
