import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../types/auth_callbacks.dart';
import '../utils/password_change.dart';
import '../utils/validators.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/login_logo.dart';
import '../widgets/password_strength_hint.dart';

class PasswordResetScreen extends StatefulWidget {
  final PasswordUpdateSubmit onUpdatePassword;
  final VoidCallback onCancel;

  const PasswordResetScreen({
    super.key,
    required this.onUpdatePassword,
    required this.onCancel,
  });

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String _password = '';
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const JuriiStaggeredItem(index: 0, child: LoginLogo()),
                const SizedBox(height: 36),
                JuriiStaggeredItem(
                  index: 1,
                  child: Text(
                    'Defina sua nova senha',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                JuriiStaggeredItem(
                  index: 2,
                  child: Text(
                    'Escolha uma senha segura para voltar a acessar sua conta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                JuriiStaggeredItem(
                  index: 3,
                  child: _shadowedField(
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        hintText: 'Nova senha',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onChanged: (value) => setState(() => _password = value),
                      validator: validatePasswordField,
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: JuriiMotion.fast,
                  curve: JuriiMotion.ease,
                  alignment: Alignment.topCenter,
                  child: _password.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: PasswordStrengthHint(
                            strength: passwordStrength(_password),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 14),
                JuriiStaggeredItem(
                  index: 4,
                  child: _shadowedField(
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        hintText: 'Confirmar nova senha',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'As senhas precisam ser iguais';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                JuriiStaggeredItem(
                  index: 5,
                  child: JuriiLoadingButton(
                    label: 'Confirmar nova senha',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _submit,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _isLoading ? null : widget.onCancel,
                  child: Text(
                    'Voltar ao login',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                JuriiFormErrorBanner(message: _errorMessage),
              ],
            ),
          ),
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
      await widget.onUpdatePassword(_passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha atualizada com sucesso.')),
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
    if (message.contains('session') || message.contains('token')) {
      return 'O link expirou. Solicite uma nova recuperação de senha.';
    }
    if (message.contains('password')) {
      return 'A nova senha não atende aos requisitos.';
    }
    return 'Não foi possível atualizar sua senha. Tente novamente.';
  }

  Widget _shadowedField({required Widget child}) {
    final colors = context.jColors;
    return Container(
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
      child: child,
    );
  }
}
