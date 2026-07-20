import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../types/auth_callbacks.dart';
import '../utils/cpf_input_formatter.dart';
import '../utils/validators.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/login_logo.dart';

/// Etapa extra de quem entrou por Google/Apple: esses provedores autenticam,
/// mas não entregam CPF (e a Apple frequentemente não entrega nem o nome).
/// A tela bloqueia o acesso até os dados existirem — sem eles a Jurii não
/// consegue identificar a parte num contrato ou processo.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.profile,
    required this.onSubmit,
    required this.onLogout,
  });

  final UserProfile profile;
  final ProfileCompletionSubmit onSubmit;
  final VoidCallback onLogout;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _cpfController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // O Google costuma mandar o nome real: aproveita e deixa o usuário só
    // conferir. Quando o nome veio do prefixo do e-mail (Apple sem nome), o
    // campo abre vazio — pré-preencher com "pedro.fries68" seria pior que nada.
    _nameController = TextEditingController(
      text: isCompleteName(widget.profile.name) ? widget.profile.name : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onSubmit(
        fullName: _nameController.text.trim(),
        cpf: widget.profile.needsCpfCompletion
            ? digitsOnly(_cpfController.text)
            : null,
      );
    } catch (error) {
      debugPrint('Profile completion failed: $error');
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    // Precisa vir antes do teste genérico: a violação do índice único também
    // menciona "cpf", e mandar "informe um CPF válido" para quem digitou o
    // próprio CPF certo seria enlouquecedor.
    if (message.contains('already registered') ||
        message.contains('profiles_cpf_unique')) {
      return 'Este CPF já está em uso em outra conta da Jurii. '
          'Entre com ela para continuar.';
    }
    if (message.contains('cannot be changed')) {
      return 'O CPF desta conta já foi definido e não pode ser alterado.';
    }
    if (message.contains('cpf')) return 'Informe um CPF válido.';
    return 'Não foi possível salvar seus dados. Tente novamente.';
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
                    'Complete seu cadastro',
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
                    _completionDescription,
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
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
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
                if (widget.profile.needsCpfCompletion) ...[
                  const SizedBox(height: 14),
                  JuriiStaggeredItem(
                    index: 4,
                    child: _shadowedField(
                      child: TextFormField(
                        controller: _cpfController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          const CpfInputFormatter(),
                          LengthLimitingTextInputFormatter(14),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'Seu CPF',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: validateCpfField,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                JuriiStaggeredItem(
                  index: 5,
                  child: JuriiLoadingButton(
                    label: 'Continuar',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _submit,
                  ),
                ),
                JuriiFormErrorBanner(message: _errorMessage),
                const SizedBox(height: 10),
                // Ninguém pode ficar preso numa tela sem saída.
                TextButton(
                  onPressed: _isLoading ? null : widget.onLogout,
                  child: Text(
                    'Sair da conta',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _completionDescription {
    if (widget.profile.needsCpfCompletion &&
        widget.profile.needsNameCompletion) {
      return 'Falta pouco. Precisamos do seu nome completo e CPF: são eles '
          'que identificam você nos contratos e processos conduzidos pela '
          'Jurii.';
    }
    if (widget.profile.needsCpfCompletion) {
      return 'Falta pouco. Precisamos do seu CPF para identificar você nos '
          'contratos e processos conduzidos pela Jurii.';
    }
    return 'Falta pouco. Precisamos confirmar seu nome completo para '
        'identificar você nos contratos e processos conduzidos pela Jurii.';
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
