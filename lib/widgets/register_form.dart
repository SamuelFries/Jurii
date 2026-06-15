import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../types/auth_callbacks.dart';

class RegisterForm extends StatefulWidget {
  final RegisterSubmit onRegister;

  const RegisterForm({super.key, required this.onRegister});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _password = '';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _shadowedField(
            child: TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Nome completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) {
                if (value == null || value.trim().length < 3) {
                  return 'Informe seu nome completo';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 14),

          _shadowedField(
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'Seu e-mail',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!email.contains('@') || !email.contains('.')) {
                  return 'Informe um e-mail válido';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 14),

          _shadowedField(
            child: TextFormField(
              controller: _cpfController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                _CpfInputFormatter(),
                LengthLimitingTextInputFormatter(14),
              ],
              decoration: const InputDecoration(
                hintText: 'Seu CPF',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (value) {
                final cpf = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                if (cpf.length != 11) {
                  return 'Informe um CPF válido';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 14),

          _shadowedField(
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'Crie uma senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onChanged: (value) => setState(() => _password = value),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'Use pelo menos 6 caracteres';
                }
                return null;
              },
            ),
          ),

          if (_password.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PasswordStrengthIndicator(strength: _passwordStrength),
          ],

          const SizedBox(height: 14),

          _shadowedField(
            child: TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'Confirme sua senha',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value != _password) {
                  return 'As senhas precisam ser iguais';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 20),

          Container(
            width: double.infinity,
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
                      'Criar conta',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
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
      final result = await widget.onRegister(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        cpf: _cpfController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;

      if (result == RegisterResult.needsEmailConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Conta criada. Confirme seu e-mail para entrar na Jurii.',
            ),
          ),
        );
        Navigator.of(context).pop();
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'Já existe uma conta com este e-mail.';
    }
    if (message.contains('password')) {
      return 'A senha informada não atende aos requisitos.';
    }
    return 'Não foi possível criar sua conta. Tente novamente.';
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
    if (_password.length >= 8) {
      strength++;
    }
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

class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formattedCpf = _formatCpf(limitedDigits);
    return TextEditingValue(
      text: formattedCpf,
      selection: TextSelection.collapsed(offset: formattedCpf.length),
    );
  }

  String _formatCpf(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index == 3 || index == 6) {
        buffer.write('.');
      } else if (index == 9) {
        buffer.write('-');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

class _PasswordStrengthIndicator extends StatelessWidget {
  const _PasswordStrengthIndicator({required this.strength});

  final int strength;

  Color get _color => switch (strength) {
    3 => AppTheme.success,
    2 => AppTheme.accent,
    _ => AppTheme.danger,
  };

  String get _label => switch (strength) {
    3 => 'Senha forte',
    2 => 'Senha média',
    _ => 'Senha fraca',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (index) {
              final isActive = index < strength;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _color
                        : AppTheme.lightBlueBorder.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _label,
            style: TextStyle(
              color: _color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
