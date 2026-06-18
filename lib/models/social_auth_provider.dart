enum SocialAuthProvider {
  google,
  apple;

  String get label {
    return switch (this) {
      SocialAuthProvider.google => 'Google',
      SocialAuthProvider.apple => 'Apple',
    };
  }
}
