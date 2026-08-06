import 'package:flutter/material.dart';

import '../repositories/auth_repository.dart';
import '../theme/app_colors.dart';
import '../utils/password_change.dart';
import '../utils/validators.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/password_strength_hint.dart';

/// Troca de senha de quem JÁ está dentro do app (menu Segurança).
///
/// Diferente da recuperação por e-mail, aqui a pessoa não provou identidade por
/// link nenhum — ela só está com o aparelho na mão. Por isso a senha atual é
/// exigida: sem ela, qualquer um com o celular destravado troca a senha e
/// tranca o dono para fora da própria conta. Num app que guarda documento de
/// processo, isso não é detalhe.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    this.repository = const AuthRepository(),
  });

  final AuthRepository repository;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String _newPassword = '';
  String? _errorMessage;

  /// Quem entrou só por Google ou Apple nunca teve senha: pedir a atual seria
  /// um beco sem saída.
  late final bool _requiresCurrent = widget.repository.hasEmailPassword;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final validation = validatePasswordChange(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
      confirmation: _confirmController.text,
      requiresCurrentPassword: _requiresCurrent,
    );
    if (!validation.isValid) {
      setState(() => _errorMessage = validation.error);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    // O ScaffoldMessenger é capturado ANTES do await: depois do pop, o context
    // desta tela já não serve para mostrar nada.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await widget.repository.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Senha alterada.')));
    } catch (error) {
      debugPrint('Password change failed: $error');
      if (!mounted) return;
      setState(() => _errorMessage = friendlyPasswordChangeError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: const Text('Alterar senha'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _requiresCurrent
                      ? 'Confirme sua senha atual e escolha a nova.'
                      : 'Sua conta entra pelo Google ou pela Apple. Criar uma '
                            'senha aqui não substitui esse acesso: passa a '
                            'valer também o login por e-mail e senha.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),

                if (_requiresCurrent) ...[
                  JuriiStaggeredItem(
                    index: 0,
                    child: TextFormField(
                      controller: _currentController,
                      obscureText: _obscureCurrent,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Senha atual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscureCurrent = !_obscureCurrent,
                          ),
                          icon: Icon(
                            _obscureCurrent
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscureCurrent
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Informe sua senha atual'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                JuriiStaggeredItem(
                  index: 1,
                  child: TextFormField(
                    controller: _newController,
                    obscureText: _obscureNew,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Nova senha',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureNew
                            ? 'Mostrar senha'
                            : 'Ocultar senha',
                      ),
                    ),
                    onChanged: (value) => setState(() => _newPassword = value),
                    validator: validatePasswordField,
                  ),
                ),

                AnimatedSize(
                  duration: JuriiMotion.fast,
                  curve: JuriiMotion.ease,
                  alignment: Alignment.topCenter,
                  child: _newPassword.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: PasswordStrengthHint(
                            strength: passwordStrength(_newPassword),
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                JuriiStaggeredItem(
                  index: 2,
                  child: TextFormField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Confirmar nova senha',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureConfirm
                            ? 'Mostrar senha'
                            : 'Ocultar senha',
                      ),
                    ),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) => value != _newController.text
                        ? 'As senhas precisam ser iguais'
                        : null,
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.dangerSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.dangerBorder),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: colors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar nova senha'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
