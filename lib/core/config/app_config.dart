import 'dart:io' show File;
import '../utils/app_logger.dart';

/// Centralized application configuration.
///
/// Values are injected at compile time via:
/// `--dart-define-from-file=.env` (or `--dart-define=KEY=VALUE`).
///
/// For local development convenience without `--dart-define-from-file`,
/// it will attempt to read a local `.env` file on disk as a fallback.
/// The `.env` file is NOT bundled as an asset into release packages.
class AppConfig {
  AppConfig._();

  static String supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
  static String supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
  static String deezerProxyUrl = const String.fromEnvironment('DEEZER_PROXY_URL');
  static String lastfmApiKey = const String.fromEnvironment('LASTFM_API_KEY');
  static String lastfmSharedSecret = const String.fromEnvironment('LASTFM_SHARED_SECRET');

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Fallback: If not passed via --dart-define-from-file, try reading local .env file on disk during local dev
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty || deezerProxyUrl.isEmpty || lastfmApiKey.isEmpty) {
      try {
        final envFile = File('.env');
        if (await envFile.exists()) {
          final lines = await envFile.readAsLines();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            final parts = trimmed.split('=');
            if (parts.length >= 2) {
              final key = parts[0].trim();
              final value = parts.sublist(1).join('=').trim();
              if (key == 'SUPABASE_URL' && supabaseUrl.isEmpty) supabaseUrl = value;
              if (key == 'SUPABASE_ANON_KEY' && supabaseAnonKey.isEmpty) supabaseAnonKey = value;
              if (key == 'DEEZER_PROXY_URL' && deezerProxyUrl.isEmpty) deezerProxyUrl = value;
              if (key == 'LASTFM_API_KEY' && lastfmApiKey.isEmpty) lastfmApiKey = value;
              if (key == 'LASTFM_SHARED_SECRET' && lastfmSharedSecret.isEmpty) lastfmSharedSecret = value;
            }
          }
          appLogger.i('AppConfig: Loaded fallback environment variables from local .env file');
        }
      } catch (e) {
        appLogger.d('AppConfig: Local .env file read skipped or failed: $e');
      }
    }
  }
}
