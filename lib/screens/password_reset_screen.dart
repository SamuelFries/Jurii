import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../types/auth_callbacks.dart';
import '../utils/validators.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/login_logo.dart';

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
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                const JuriiStaggeredItem(
                  index: 1,
                  child: Text(
                    'Defina sua nova senha',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const JuriiStaggeredItem(
                  index: 2,
                  child: Text(
                    'Escolha uma senha segura para voltar a acessar sua conta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
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
                          child: _PasswordHint(strength: _passwordStrength),
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
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.20),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.card,
                              ),
                            )
                          : const Text(
                              'Confirmar nova senha',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _isLoading ? null : widget.onCancel,
                  child: const Text(
                    'Voltar ao login',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  int get _passwordStrength {
    var strength = 0;
    if (_password.length >= 8) strength++;
    if (RegExp(r'[a-z]').hasMatch(_password) &&
        RegExp(r'[A-Z]').hasMatch(_password)) {
      strength++;
    }
    if (RegExp(r'\d').hasMatch(_password) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(_password)) {
      strength++;
    }
    return strength;
  }
}

class _PasswordHint extends StatelessWidget {
  final int strength;

  const _PasswordHint({required this.strength});

  @override
  Widget build(BuildContext context) {
    final label = switch (strength) {
      0 || 1 => 'Senha fraca',
      2 => 'Senha média',
      _ => 'Senha forte',
    };
    final color = switch (strength) {
      0 || 1 => AppTheme.danger,
      2 => AppTheme.warning,
      _ => AppTheme.success,
    };

    return Row(
      children: [
        Expanded(
          child: _bar(active: strength >= 1, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _bar(active: strength >= 2, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _bar(active: strength >= 3, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _bar({required bool active, required Color color}) {
    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      height: 5,
      decoration: BoxDecoration(
        color: active ? color : AppTheme.divider,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
