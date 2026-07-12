import 'package:flutter/material.dart';

import 'register_screen.dart';
import '../models/social_auth_provider.dart';
import '../theme/app_colors.dart';
import '../types/auth_callbacks.dart';
import '../utils/validators.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/legal_agreement_notice.dart';
import '../widgets/login_logo.dart';

class LoginScreen extends StatefulWidget {
  final LoginSubmit onLogin;
  final SocialLoginSubmit onSocialLogin;
  final PasswordResetRequest onPasswordResetRequested;
  final RegisterSubmit onRegister;

  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onSocialLogin,
    required this.onPasswordResetRequested,
    required this.onRegister,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool showPassword = false;
  bool isLoading = false;
  SocialAuthProvider? socialLoadingProvider;
  String? errorMessage;

  bool get _isAnyAuthLoading => isLoading || socialLoadingProvider != null;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 24),

              const JuriiStaggeredItem(index: 0, child: LoginLogo()),

              const SizedBox(height: 32),

              // Email
              JuriiStaggeredItem(
                index: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colors.softShadow,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Seu e-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                      filled: true,
                      fillColor: colors.card,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Senha
              JuriiStaggeredItem(
                index: 2,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colors.softShadow,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: passwordController,
                    obscureText: !showPassword,
                    decoration: InputDecoration(
                      hintText: 'Sua senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: colors.card,
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => showPassword = !showPassword),
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              JuriiStaggeredItem(
                index: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isAnyAuthLoading ? null : _openPasswordReset,
                    child: Text(
                      'Esqueceu sua senha?',
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Botão entrar
              JuriiStaggeredItem(
                index: 4,
                child: JuriiLoadingButton(
                  label: 'Entrar',
                  isLoading: isLoading,
                  onPressed: _isAnyAuthLoading ? null : _submit,
                ),
              ),

              JuriiFormErrorBanner(message: errorMessage),

              const SizedBox(height: 22),

              JuriiStaggeredItem(
                index: 5,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(height: 1, color: colors.divider),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'ou continue com',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(height: 1, color: colors.divider),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Google
              JuriiStaggeredItem(
                index: 6,
                child: Container(
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
                    onPressed: _isAnyAuthLoading
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
                          child:
                              socialLoadingProvider == SocialAuthProvider.google
                              ? SizedBox(
                                  key: ValueKey('google_loading'),
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.primary,
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/google_logo.png',
                                  key: const ValueKey('google_logo'),
                                  width: 20,
                                  height: 20,
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
                ),
              ),

              const SizedBox(height: 12),

              // Apple
              JuriiStaggeredItem(
                index: 7,
                child: Container(
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
                    onPressed: _isAnyAuthLoading
                        ? null
                        : () => _submitSocial(SocialAuthProvider.apple),
                    icon: AnimatedSwitcher(
                      duration: JuriiMotion.fast,
                      child: socialLoadingProvider == SocialAuthProvider.apple
                          ? SizedBox(
                              key: ValueKey('apple_loading'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary,
                              ),
                            )
                          : Icon(
                              Icons.apple,
                              key: ValueKey('apple_icon'),
                              color: colors.textPrimary,
                            ),
                    ),
                    label: Text(
                      'Continuar com Apple',
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
                ),
              ),

              const SizedBox(height: 24),

              JuriiStaggeredItem(
                index: 8,
                child: Text(
                  'Ainda não possui conta?',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),

              const SizedBox(height: 12),

              JuriiStaggeredItem(
                index: 9,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _openRegister,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.accent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Criar conta',
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const LegalAgreementNotice(
                prefix: 'Ao continuar você concorda com nossos',
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Informe seu e-mail e sua senha.');
      return;
    }
    if (!isValidEmail(email)) {
      setState(() => errorMessage = 'Informe um e-mail válido.');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await widget.onLogin(email, password);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _submitSocial(SocialAuthProvider provider) async {
    setState(() {
      socialLoadingProvider = provider;
      errorMessage = null;
    });

    try {
      await widget.onSocialLogin(provider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Conclua o login com ${provider.label} para continuar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = _friendlySocialError(error);
      });
    } finally {
      if (mounted) {
        setState(() => socialLoadingProvider = null);
      }
    }
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: JuriiMotion.standard,
        reverseTransitionDuration: JuriiMotion.fast,
        pageBuilder: (_, _, _) => RegisterScreen(
          onRegister: widget.onRegister,
          onSocialLogin: widget.onSocialLogin,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: JuriiMotion.ease,
            reverseCurve: JuriiMotion.exitEase,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.035),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPasswordReset() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _PasswordResetRequestSheet(
          initialEmail: emailController.text.trim(),
          onSubmit: widget.onPasswordResetRequested,
        );
      },
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'E-mail ou senha inválidos.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (message.contains('conta excluída') ||
        message.contains('conta excluida') ||
        message.contains('deleted account')) {
      return 'Esta conta foi excluída e não pode mais acessar a Jurii.';
    }
    return 'Não foi possível entrar. Tente novamente.';
  }

  String _friendlySocialError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('cancel')) {
      return 'Login social cancelado.';
    }
    if (message.contains('not configured') ||
        message.contains('could not launch')) {
      return 'Login social indisponível no momento. Tente novamente.';
    }
    return 'Não foi possível iniciar o login social. Tente novamente.';
  }
}

class _PasswordResetRequestSheet extends StatefulWidget {
  final String initialEmail;
  final PasswordResetRequest onSubmit;

  const _PasswordResetRequestSheet({
    required this.initialEmail,
    required this.onSubmit,
  });

  @override
  State<_PasswordResetRequestSheet> createState() =>
      _PasswordResetRequestSheetState();
}

class _PasswordResetRequestSheetState
    extends State<_PasswordResetRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiModalSheetScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recuperar senha',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Informe o e-mail cadastrado para receber o link de redefinição.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colors.softShadow,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  hintText: 'Seu e-mail',
                  prefixIcon: Icon(Icons.mail_outline),
                  filled: true,
                  fillColor: colors.card,
                ),
                validator: validateEmailField,
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 18),
            JuriiLoadingButton(
              label: 'Enviar link',
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _submit,
              height: 52,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            JuriiFormErrorBanner(message: _errorMessage),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onSubmit(_emailController.text.trim());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enviamos um link de recuperação para seu e-mail.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Aguarde alguns minutos antes de solicitar outro link.';
    }
    if (message.contains('email')) {
      return 'Não foi possível enviar o link para este e-mail.';
    }
    return 'Não foi possível enviar o link. Tente novamente.';
  }
}
