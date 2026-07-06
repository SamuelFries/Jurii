import 'package:flutter/material.dart';

import '../models/social_auth_provider.dart';
import '../theme/app_theme.dart';
import '../types/auth_callbacks.dart';
import 'legal_agreement_notice.dart';

/// Botões sociais do cadastro. No Supabase, OAuth de cadastro e de login são
/// o mesmo fluxo — recebe o mesmo callback usado na tela de login.
class RegisterSocialButtons extends StatefulWidget {
  const RegisterSocialButtons({super.key, this.onSocialLogin});

  final SocialLoginSubmit? onSocialLogin;

  @override
  State<RegisterSocialButtons> createState() => _RegisterSocialButtonsState();
}

class _RegisterSocialButtonsState extends State<RegisterSocialButtons> {
  SocialAuthProvider? _loadingProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Container(height: 1, color: AppTheme.divider)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'ou cadastre-se com',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            Expanded(child: Container(height: 1, color: AppTheme.divider)),
          ],
        ),

        const SizedBox(height: 24),

        _googleButton(context),

        const SizedBox(height: 12),

        _socialButton(
          icon: Icons.apple,
          text: 'Continuar com Apple',
          loading: _loadingProvider == SocialAuthProvider.apple,
          onPressed: () => _submitSocial(SocialAuthProvider.apple),
        ),

        const SizedBox(height: 32),

        const Text(
          'Já possui uma conta?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Entrar',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        const LegalAgreementNotice(
          prefix: 'Ao criar sua conta você concorda com nossos',
        ),
      ],
    );
  }

  Widget _googleButton(BuildContext context) {
    final loading = _loadingProvider == SocialAuthProvider.google;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton(
        onPressed: _loadingProvider != null
            ? null
            : () => _submitSocial(SocialAuthProvider.google),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.softBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              )
            else
              Image.asset(
                'assets/images/google_logo.png',
                width: 20,
                height: 20,
              ),
            const SizedBox(width: 12),
            const Text(
              'Continuar com Google',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required String text,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton.icon(
        onPressed: _loadingProvider != null ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              )
            : Icon(icon, color: AppTheme.textPrimary),
        label: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.softBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Future<void> _submitSocial(SocialAuthProvider provider) async {
    final onSocialLogin = widget.onSocialLogin;
    if (onSocialLogin == null) {
      _showSocialUnavailable(context);
      return;
    }

    setState(() => _loadingProvider = provider);
    try {
      await onSocialLogin(provider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Conclua o cadastro com ${provider.label} para continuar.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Social sign-up failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível iniciar o cadastro social. Tente novamente.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingProvider = null);
      }
    }
  }

  void _showSocialUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cadastro social será conectado em uma próxima etapa.'),
      ),
    );
  }
}
