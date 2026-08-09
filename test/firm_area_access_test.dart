import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/firm_role.dart';
import 'package:jurii/models/firm_workspace.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/law_firm_verification_status.dart';
import 'package:jurii/utils/firm_area_access.dart';

const _firma = LawFirm(
  id: 'f1',
  name: 'Firma',
  initials: 'F',
  rating: 0,
  distance: '',
  specialty: 'Direito Cível',
  practiceAreas: ['Direito Cível'],
  reviews: 0,
  avatarType: 'purple',
);

FirmWorkspace _workspace({required bool fromSupabase}) => FirmWorkspace(
  firm: _firma,
  currentUserRole: FirmRole.owner,
  currentUserRoles: const [FirmRole.owner],
  teamMembers: const [],
  fromSupabase: fromSupabase,
);

void main() {
  // O DEFEITO QUE ISTO TRAVA: no fluxo do advogado, a área do escritório era
  // oferecida no seletor para TODO advogado aprovado, com ou sem escritório,
  // porque o callback ia sem checar nada. O toque caía num `return` mudo: a
  // opção aparecia, aceitava o toque e não fazia nada.
  //
  // A regra existe como função pura porque decide DUAS coisas que precisam
  // concordar: se a área aparece, e se a troca acontece. Quando moravam em
  // lugares diferentes, divergiram.

  test('vínculo ativo sincronizado dá acesso', () {
    expect(
      hasFirmArea(
        workspace: _workspace(fromSupabase: true),
        verificationStatus: null,
        supabaseReady: true,
      ),
      isTrue,
    );
  });

  test('sem workspace nenhum, não dá', () {
    // É o caso do advogado comum: aprovado na OAB, sem escritório.
    expect(
      hasFirmArea(
        workspace: null,
        verificationStatus: null,
        supabaseReady: true,
      ),
      isFalse,
    );
  });

  test('verificação aprovada NÃO basta em produção', () {
    // Autoridade vem de vínculo ativo. Aceitar a verificação histórica
    // deixaria um ex-sócio entrando na área de um escritório que já não é
    // dele.
    expect(
      hasFirmArea(
        workspace: null,
        verificationStatus: LawFirmVerificationStatus.approved,
        supabaseReady: true,
      ),
      isFalse,
    );
  });

  test('workspace local (não sincronizado) não dá acesso em produção', () {
    expect(
      hasFirmArea(
        workspace: _workspace(fromSupabase: false),
        verificationStatus: null,
        supabaseReady: true,
      ),
      isFalse,
    );
  });

  test('no modo demo, a verificação aprovada é o que existe', () {
    // Sem Supabase não há vínculo para consultar; o fluxo precisa ser
    // demonstrável.
    expect(
      hasFirmArea(
        workspace: null,
        verificationStatus: LawFirmVerificationStatus.approved,
        supabaseReady: false,
      ),
      isTrue,
    );
  });

  test('no demo, verificação pendente ou recusada não dá', () {
    for (final status in [
      LawFirmVerificationStatus.pending,
      LawFirmVerificationStatus.rejected,
      null,
    ]) {
      expect(
        hasFirmArea(
          workspace: null,
          verificationStatus: status,
          supabaseReady: false,
        ),
        isFalse,
        reason: 'status $status não deveria abrir a área',
      );
    }
  });
}
