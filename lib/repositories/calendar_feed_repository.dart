import '../services/supabase_config.dart';

/// Gestão do feed .ics assinável da agenda do advogado. O token é uma
/// "capability URL": quem tem o link vê a agenda, por isso é revogável
/// (rotacionar gera outro e derruba o antigo).
class CalendarFeedRepository {
  const CalendarFeedRepository();

  /// Token atual, ou `null` quando o feed está desligado.
  Future<String?> fetchToken() async {
    if (!_ready) return null;
    final token = await SupabaseConfig.client.rpc('get_calendar_feed_token');
    return token as String?;
  }

  Future<String> enable() async {
    _ensureReady();
    final token = await SupabaseConfig.client.rpc('enable_calendar_feed');
    return token as String;
  }

  /// Gera um novo token e invalida o link anterior.
  Future<String> reset() async {
    _ensureReady();
    final token = await SupabaseConfig.client.rpc('reset_calendar_feed');
    return token as String;
  }

  Future<void> disable() async {
    _ensureReady();
    await SupabaseConfig.client.rpc('disable_calendar_feed');
  }

  /// URL https do feed — para colar em "adicionar por URL" no Google/Outlook.
  String feedUrl(String token) =>
      '${SupabaseConfig.url}/functions/v1/calendar-feed?token=$token';

  /// URL webcal:// — abre direto o diálogo de assinatura no Apple/Google.
  String webcalUrl(String token) {
    final https = feedUrl(token);
    return https.replaceFirst(RegExp(r'^https?://'), 'webcal://');
  }

  bool get _ready =>
      SupabaseConfig.isReady && SupabaseConfig.client.auth.currentUser != null;

  void _ensureReady() {
    if (!_ready) {
      throw StateError('A conexão com o Supabase não está ativa.');
    }
  }
}
