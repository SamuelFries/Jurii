import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _password = '';

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _shadowedField(
            child: TextFormField(
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
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [_CpfInputFormatter()],
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
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'Crie uma senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _password = value;
                });
              },
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
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'Confirme sua senha',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
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
              onPressed: () {
                _formKey.currentState?.validate();
              },
              child: const Text(
                'Criar conta',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shadowedField({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A1C3B),
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

  Color get _color {
    return switch (strength) {
      3 => const Color(0xFF2E7D32),
      2 => AppTheme.accent,
      _ => const Color(0xFFD32F2F),
    };
  }

  String get _label {
    return switch (strength) {
      3 => 'Senha forte',
      2 => 'Senha média',
      _ => 'Senha fraca',
    };
  }

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
                  margin: EdgeInsets.only(
                    right: index == 2 ? 0 : 6,
                  ),
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
