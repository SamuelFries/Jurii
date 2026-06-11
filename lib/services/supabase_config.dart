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

  static String get url => _envUrl.isNotEmpty ? _envUrl : _projectUrl;

  static String get key => _envPublishableKey.isNotEmpty
      ? _envPublishableKey
      : _legacyAnonKey.isNotEmpty
      ? _legacyAnonKey
      : _projectPublishableKey;

  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;

    await Supabase.initialize(url: url, publishableKey: key);
  }

  static SupabaseClient get client {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Run with '
        '--dart-define=SUPABASE_URL=... '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
      );
    }

    return Supabase.instance.client;
  }
}
