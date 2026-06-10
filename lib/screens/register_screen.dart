import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/login_logo.dart';
import '../widgets/register_form.dart';
import '../widgets/register_social_buttons.dart';

class RegisterScreen extends StatelessWidget {
  final VoidCallback onLogin;

  const RegisterScreen({
    super.key,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const LoginLogo(
                subtitle: 'Crie sua conta e encontre o suporte\njurídico que você precisa.',
              ),
              const SizedBox(height: 40),
              RegisterForm(onLogin: onLogin),
              const SizedBox(height: 28),
              RegisterSocialButtons(onLogin: onLogin),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}