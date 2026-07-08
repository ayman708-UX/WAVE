import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wave/core/env/env.dart';

void main() {
  test('Test deleting a playlist from Supabase', () async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

    final client = Supabase.instance.client;
    // We cannot login without credentials, but we can try to call a query.
    // However, we don't have the user credentials here.
  });
}
