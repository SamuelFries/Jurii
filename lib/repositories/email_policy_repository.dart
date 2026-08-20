import 'package:flutter/foundation.dart';

import '../services/supabase_config.dart';

/// A política de e-mail do cadastro, perguntada ao servidor.
///
/// A regra mora no banco (gatilho em auth.users, migration
/// `conta_com_email_de_verdade`): a chave anon é pública, então validar só na
/// tela não impede ninguém de cadastrar por fora. Esta consulta existe para a
/// pessoa LER O MOTIVO antes de enviar, em vez de receber um erro de servidor.
///
/// Falha de rede devolve `false` de propósito: sem resposta, quem decide é o
/// banco no momento do cadastro. Errar para o lado de deixar seguir só
/// adianta a recusa para o servidor, que tem a palavra final; errar para o
/// lado de bloquear travaria cadastro legítimo por causa de uma consulta.
class EmailPolicyRepository {
  const EmailPolicyRepository();

  Future<bool> ehDescartavel(String email) async {
    if (!SupabaseConfig.isReady) return false;
    try {
      final resultado = await SupabaseConfig.client.rpc(
        'email_e_descartavel',
        params: {'email_value': email.trim()},
      );
      return resultado == true;
    } catch (error) {
      debugPrint('Disposable email check failed: $error');
      return false;
    }
  }
}
