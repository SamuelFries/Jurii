import 'package:flutter/material.dart';

import '../models/social_auth_provider.dart';
import '../theme/app_colors.dart';
import '../types/auth_callbacks.dart';
import 'jurii_motion.dart';
import 'legal_agreement_notice.dart';
import 'social_provider_logo.dart';

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
    final colors = context.jColors;
    return Column(
      children: [
        JuriiStaggeredItem(
          index: 0,
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: colors.divider)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ou cadastre-se com',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
              Expanded(child: Container(height: 1, color: colors.divider)),
            ],
          ),
        ),

        const SizedBox(height: 24),

        JuriiStaggeredItem(index: 1, child: _googleButton(context)),

        const SizedBox(height: 12),

        JuriiStaggeredItem(
          index: 2,
          child: _socialButton(
            context: context,
            provider: SocialAuthProvider.apple,
            text: 'Continuar com Apple',
            loading: _loadingProvider == SocialAuthProvider.apple,
            onPressed: () => _submitSocial(SocialAuthProvider.apple),
          ),
        ),

        const SizedBox(height: 32),

        JuriiStaggeredItem(
          index: 3,
          child: Text(
            'Já possui uma conta?',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),

        const SizedBox(height: 12),

        JuriiStaggeredItem(
          index: 4,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Entrar',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
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
    final colors = context.jColors;
    final loading = _loadingProvider == SocialAuthProvider.google;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
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
          side: BorderSide(color: colors.softBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: JuriiMotion.fast,
              child: loading
                  ? SizedBox(
                      key: ValueKey('google_loading'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    )
                  : SocialProviderLogo(
                      key: const ValueKey('google_logo'),
                      provider: SocialAuthProvider.google,
                    ),
            ),
            const SizedBox(width: 12),
            Text(
              'Continuar com Google',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialButton({
    required BuildContext context,
    required SocialAuthProvider provider,
    required String text,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    final colors = context.jColors;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton.icon(
        onPressed: _loadingProvider != null ? null : onPressed,
        icon: AnimatedSwitcher(
          duration: JuriiMotion.fast,
          child: loading
              ? SizedBox(
                  key: ValueKey('social_loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              : SocialProviderLogo(
                  key: ValueKey('social_icon_$text'),
                  provider: provider,
                ),
        ),
        label: Text(
          text,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.softBorder),
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
