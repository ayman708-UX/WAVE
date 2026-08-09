import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wave/core/api/supabase_client.dart';

void main() {
  test('Test deleting a playlist from Supabase', () async {
    if (SupabaseApiClient.supabaseUrl != null && SupabaseApiClient.supabaseAnonKey != null) {
      await Supabase.initialize(
        url: SupabaseApiClient.supabaseUrl!,
        publishableKey: SupabaseApiClient.supabaseAnonKey!,
      );
    }
  });
}
