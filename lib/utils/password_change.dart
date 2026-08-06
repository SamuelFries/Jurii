import 'validators.dart';

/// Validação da troca de senha de quem JÁ está dentro do app.
///
/// Diferente do fluxo de recuperação por e-mail, aqui a pessoa não provou
/// identidade por link nenhum: ela só está com o aparelho na mão. Por isso a
/// senha atual é exigida — sem ela, qualquer um com o celular destravado troca
/// a senha e tranca o dono para fora da própria conta.
class PasswordChangeValidation {
  const PasswordChangeValidation._({this.error});

  final String? error;

  bool get isValid => error == null;

  static const PasswordChangeValidation ok = PasswordChangeValidation._();
}

/// [requiresCurrentPassword] é falso para quem entrou por Google ou Apple e
/// nunca teve senha: exigir uma senha que não existe seria um beco sem saída.
PasswordChangeValidation validatePasswordChange({
  required String currentPassword,
  required String newPassword,
  required String confirmation,
  required bool requiresCurrentPassword,
}) {
  if (requiresCurrentPassword && currentPassword.isEmpty) {
    return const PasswordChangeValidation._(error: 'Informe sua senha atual.');
  }

  final erroDeFormato = validatePasswordField(newPassword);
  if (erroDeFormato != null) {
    return PasswordChangeValidation._(error: erroDeFormato);
  }

  if (newPassword != confirmation) {
    return const PasswordChangeValidation._(
      error: 'A confirmação não confere com a nova senha.',
    );
  }

  // Trocar a senha pela mesma senha não é troca: o usuário sairia da tela
  // achando que girou a credencial, e ela continuaria a mesma.
  if (requiresCurrentPassword && newPassword == currentPassword) {
    return const PasswordChangeValidation._(
      error: 'A nova senha precisa ser diferente da atual.',
    );
  }

  return PasswordChangeValidation.ok;
}

/// Mensagem para o erro que vem do servidor na troca de senha.
///
/// A senha atual é conferida com um login: quando ela está errada, o Supabase
/// responde com o mesmo "credenciais inválidas" do login normal, que nesta
/// tela não faz sentido nenhum — a pessoa já está logada.
String friendlyPasswordChangeError(Object error) {
  final texto = error.toString().toLowerCase();

  if (texto.contains('invalid login credentials') ||
      texto.contains('invalid_credentials')) {
    return 'Senha atual incorreta.';
  }
  if (texto.contains('same as the old password') ||
      texto.contains('should be different')) {
    return 'A nova senha precisa ser diferente da atual.';
  }
  if (texto.contains('weak') || texto.contains('password should be at least')) {
    return 'Escolha uma senha mais forte, com pelo menos '
        '$kMinPasswordLength caracteres.';
  }
  // Tentativas seguidas de senha atual errada esbarram no limite do servidor.
  if (texto.contains('rate limit') || texto.contains('too many requests')) {
    return 'Muitas tentativas seguidas. Aguarde alguns minutos.';
  }
  return 'Não foi possível alterar a senha. Tente novamente.';
}

/// Força da senha de 0 a 3, para o indicador visual.
///
/// Não é política de segurança — quem barra senha curta é
/// [validatePasswordField]. Isto é orientação: mostra à pessoa o que falta
/// para a senha ficar melhor, enquanto ela digita.
int passwordStrength(String password) {
  var strength = 0;
  if (password.length >= kMinPasswordLength) strength++;
  if (RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[A-Z]').hasMatch(password)) {
    strength++;
  }
  if (RegExp(r'\d').hasMatch(password) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    strength++;
  }
  return strength;
}
