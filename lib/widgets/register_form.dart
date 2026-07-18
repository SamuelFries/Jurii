import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../types/auth_callbacks.dart';
import '../utils/cpf_input_formatter.dart';
import '../utils/validators.dart';
import 'jurii_form_motion.dart';
import 'jurii_motion.dart';

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
          JuriiStaggeredItem(
            index: 0,
            child: _shadowedField(
              child: TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                maxLength: kMaxFullNameCharacters,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: const InputDecoration(
                  hintText: 'Nome completo',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: validateFullNameField,
              ),
            ),
          ),

          const SizedBox(height: 14),

          JuriiStaggeredItem(
            index: 1,
            child: _shadowedField(
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'Seu e-mail',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: validateEmailField,
              ),
            ),
          ),

          const SizedBox(height: 14),

          JuriiStaggeredItem(
            index: 2,
            child: _shadowedField(
              child: TextFormField(
                controller: _cpfController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  const CpfInputFormatter(),
                  LengthLimitingTextInputFormatter(14),
                ],
                decoration: const InputDecoration(
                  hintText: 'Seu CPF',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: validateCpfField,
              ),
            ),
          ),

          const SizedBox(height: 14),

          JuriiStaggeredItem(
            index: 3,
            child: _shadowedField(
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
                    child: _PasswordStrengthIndicator(
                      strength: _passwordStrength,
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
          ),

          const SizedBox(height: 20),

          JuriiStaggeredItem(
            index: 5,
            child: JuriiLoadingButton(
              label: 'Criar conta',
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _submit,
            ),
          ),

          JuriiFormErrorBanner(message: _errorMessage),
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
        // Só os 11 dígitos: o trigger copia o valor cru para profiles.cpf,
        // e CPF mascarado quebraria deduplicação/consulta futura.
        cpf: digitsOnly(_cpfController.text),
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

class _PasswordStrengthIndicator extends StatelessWidget {
  const _PasswordStrengthIndicator({required this.strength});

  final int strength;

  Color _color(AppColors colors) => switch (strength) {
    3 => colors.success,
    2 => colors.accent,
    _ => colors.danger,
  };

  String get _label => switch (strength) {
    3 => 'Senha forte',
    2 => 'Senha média',
    _ => 'Senha fraca',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (index) {
              final isActive = index < strength;
              return Expanded(
                child: AnimatedContainer(
                  duration: JuriiMotion.fast,
                  curve: JuriiMotion.ease,
                  height: 6,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _color(colors)
                        : colors.lightBlueBorder.withValues(alpha: 0.45),
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
              color: _color(colors),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
