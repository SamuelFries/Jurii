import '../services/supabase_config.dart';

class FirmInvitationRepository {
  const FirmInvitationRepository();

  Future<void> inviteVerifiedLawyer({
    required String lawFirmId,
    required String oabState,
    required String oabNumber,
  }) async {
    if (!SupabaseConfig.isReady ||
        SupabaseConfig.client.auth.currentUser == null) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }

    await SupabaseConfig.client.rpc(
      'invite_verified_lawyer_to_law_firm',
      params: {
        'law_firm_id_value': lawFirmId,
        'oab_state_value': oabState,
        'oab_number_value': oabNumber,
      },
    );
  }
}
