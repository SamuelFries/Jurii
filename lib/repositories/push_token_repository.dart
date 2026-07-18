import '../services/supabase_config.dart';

enum PushPlatform {
  ios('ios'),
  android('android'),
  web('web');

  const PushPlatform(this.value);
  final String value;
}

/// Registro/remocao do token FCM deste dispositivo, via RPCs SECURITY DEFINER.
/// A tabela push_tokens nao aceita escrita direta (tudo por RPC). No-op fora do
/// Supabase (modo demo/teste).
class PushTokenRepository {
  const PushTokenRepository();

  Future<void> register({
    required String token,
    required PushPlatform platform,
  }) async {
    if (!_ready) return;
    await SupabaseConfig.client.rpc(
      'register_push_token',
      params: {'token_value': token, 'platform_value': platform.value},
    );
  }

  Future<void> unregister(String token) async {
    if (!_ready) return;
    await SupabaseConfig.client.rpc(
      'unregister_push_token',
      params: {'token_value': token},
    );
  }

  bool get _ready =>
      SupabaseConfig.isReady &&
      SupabaseConfig.client.auth.currentUser != null;
}
