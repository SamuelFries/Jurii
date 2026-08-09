import '../models/firm_workspace.dart';
import '../models/law_firm_verification_status.dart';

/// A pessoa tem área de escritório para entrar?
///
/// Função pura, e não um `if` dentro do `build`, porque esta regra decide
/// duas coisas que precisam concordar: se a área aparece no seletor de fluxo,
/// e se a troca de fato acontece. Quando as duas moravam em lugares
/// diferentes, elas divergiram: o fluxo do advogado oferecia "Escritório"
/// para todo advogado aprovado, e o toque caía num `return` mudo. Opção que
/// aparece, aceita o toque e não faz nada é pior que opção ausente, porque a
/// pessoa toca de novo achando que errou a mira.
bool hasFirmArea({
  required FirmWorkspace? workspace,
  required LawFirmVerificationStatus? verificationStatus,
  required bool supabaseReady,
}) {
  // Vínculo ativo sincronizado é a resposta em produção. `fromSupabase`
  // falso significa workspace montado localmente, que não dá acesso.
  if (workspace?.fromSupabase == true) return true;

  // Modo demo (sem Supabase): a verificação aprovada é o que existe para
  // provar que há escritório. Em produção ela NÃO basta, de propósito:
  // autoridade vem de vínculo ativo, senão um ex-sócio entraria pela
  // verificação histórica.
  return !supabaseReady &&
      verificationStatus == LawFirmVerificationStatus.approved;
}
