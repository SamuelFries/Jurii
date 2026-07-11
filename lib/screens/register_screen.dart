import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../types/auth_callbacks.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/login_logo.dart';
import '../widgets/register_form.dart';
import '../widgets/register_social_buttons.dart';

class RegisterScreen extends StatelessWidget {
  final RegisterSubmit onRegister;
  final SocialLoginSubmit? onSocialLogin;

  const RegisterScreen({
    super.key,
    required this.onRegister,
    this.onSocialLogin,
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
              const JuriiStaggeredItem(
                index: 0,
                child: LoginLogo(
                  subtitle:
                      'Crie sua conta e encontre o suporte\njurídico que você precisa.',
                ),
              ),
              const SizedBox(height: 40),
              JuriiStaggeredItem(
                index: 1,
                child: RegisterForm(onRegister: onRegister),
              ),
              const SizedBox(height: 28),
              RegisterSocialButtons(onSocialLogin: onSocialLogin),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
