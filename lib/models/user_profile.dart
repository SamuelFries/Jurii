import '../utils/validators.dart';
import 'lawyer_status.dart';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String initials;
  final String memberSince;
  final String? oabNumber;
  final LawyerStatus lawyerStatus;
  final String? avatarUrl;

  /// Só vem preenchido no perfil do PRÓPRIO usuário (`fetch_current_profile`).
  /// Perfis de contrapartes não expõem PII, então aqui chega nulo — por isso
  /// [needsProfileCompletion] só faz sentido para o usuário logado.
  final String? cpf;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.initials,
    required this.memberSince,
    required this.lawyerStatus,
    this.oabNumber,
    this.avatarUrl,
    this.cpf,
  });

  /// Google e Apple não entregam CPF, e a Apple frequentemente não entrega nem
  /// o nome — nesse caso o gatilho do banco preenche `full_name` com o prefixo
  /// do e-mail. Sem nome completo e CPF não dá para identificar a parte num
  /// contrato ou processo, então o app cobra esses dados antes de liberar o
  /// acesso.
  ///
  /// O critério é o DADO que falta, não o provedor de login: assim qualquer
  /// perfil incompleto (inclusive os 3 que já entraram por OAuth) se resolve no
  /// próximo login, sem depender de saber como a conta foi criada.
  bool get needsProfileCompletion {
    return !isValidCpf(cpf ?? '') || _nameCameFromLoginProvider;
  }

  /// Nome que o banco derivou sozinho por falta de dado do provedor.
  bool get _nameCameFromLoginProvider {
    final currentName = name.trim().toLowerCase();
    final emailPrefix = email.split('@').first.trim().toLowerCase();

    return currentName.isEmpty ||
        currentName == 'usuário jurii' ||
        (emailPrefix.isNotEmpty && currentName == emailPrefix);
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? initials,
    String? memberSince,
    String? oabNumber,
    LawyerStatus? lawyerStatus,
    String? avatarUrl,
    String? cpf,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      initials: initials ?? this.initials,
      memberSince: memberSince ?? this.memberSince,
      oabNumber: oabNumber ?? this.oabNumber,
      lawyerStatus: lawyerStatus ?? this.lawyerStatus,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      cpf: cpf ?? this.cpf,
    );
  }
}
