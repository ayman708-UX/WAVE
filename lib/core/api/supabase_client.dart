import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class SupabaseApiClient {
  static String? supabaseUrl;
  static String? supabaseAnonKey;

  static Future<void> loadEnvAndInit() async {
    try {
      final content = await rootBundle.loadString('.env');
      final lines = content.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty || line.startsWith('#')) continue;
        final parts = line.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          if (key == 'SUPABASE_URL') supabaseUrl = value;
          if (key == 'SUPABASE_ANON_KEY') supabaseAnonKey = value;
        }
      }

      if (supabaseUrl == null || supabaseAnonKey == null) {
        appLogger.e('Supabase credentials missing from .env');
        return;
      }

      await Supabase.initialize(
        url: supabaseUrl!,
        publishableKey: supabaseAnonKey!,
      );
      
      appLogger.i('Supabase initialized successfully');
    } catch (e) {
      appLogger.e('Could not initialize Supabase: $e');
    }
  }
}
