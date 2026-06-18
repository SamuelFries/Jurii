import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const _projectUrl = 'https://rlgtgipxltucrtkyrmag.supabase.co';
  static const _projectPublishableKey =
      'sb_publishable_3gA6AW1vF0Lg33dwobEULg_jpLkh8Fx';

  static const _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const _envPublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _envOAuthRedirectUrl = String.fromEnvironment(
    'SUPABASE_OAUTH_REDIRECT_URL',
  );
  static bool _initialized = false;

  static String get url => _envUrl.isNotEmpty ? _envUrl : _projectUrl;

  static String get key => _envPublishableKey.isNotEmpty
      ? _envPublishableKey
      : _legacyAnonKey.isNotEmpty
      ? _legacyAnonKey
      : _projectPublishableKey;

  static String get oauthRedirectUrl => _envOAuthRedirectUrl.isNotEmpty
      ? _envOAuthRedirectUrl
      : 'jurii://login-callback';

  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;
  static bool get isReady {
    if (!isConfigured) return false;
    if (_initialized) return true;
    return _hasInitializedClient();
  }

  static Future<void> initialize() async {
    if (!isConfigured) return;
    if (_initialized) return;

    await Supabase.initialize(url: url, publishableKey: key);
    _initialized = true;
  }

  static SupabaseClient get client {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Run with '
        '--dart-define=SUPABASE_URL=... '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
      );
    }
    if (!_initialized && !_hasInitializedClient()) {
      throw StateError('Supabase has not been initialized yet.');
    }

    return Supabase.instance.client;
  }

  static bool _hasInitializedClient() {
    try {
      Supabase.instance.client;
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }
}
