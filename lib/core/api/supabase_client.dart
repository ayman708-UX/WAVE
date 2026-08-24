import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../utils/app_logger.dart';

class SupabaseApiClient {
  static String? get supabaseUrl =>
      AppConfig.supabaseUrl.isNotEmpty ? AppConfig.supabaseUrl : null;
  static String? get supabaseAnonKey =>
      AppConfig.supabaseAnonKey.isNotEmpty ? AppConfig.supabaseAnonKey : null;

  static Future<void> loadEnvAndInit() async {
    await AppConfig.init();

    final url = supabaseUrl;
    final anonKey = supabaseAnonKey;

    if (url == null || anonKey == null || url.isEmpty || anonKey.isEmpty) {
      appLogger.w('Supabase credentials missing from environment (SUPABASE_URL / SUPABASE_ANON_KEY)');
      return;
    }

    try {
      await Supabase.initialize(
        url: url,
        publishableKey: anonKey,
      );

      appLogger.i('Supabase initialized successfully');
    } catch (e) {
      appLogger.e('Could not initialize Supabase: $e');
    }
  }
}
