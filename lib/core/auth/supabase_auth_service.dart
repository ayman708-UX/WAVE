import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

final supabaseAuthProvider = Provider<SupabaseAuthService>((ref) {
  return SupabaseAuthService();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value?.session?.user;
});

/// Whether the user is signed in (not a guest).
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

class SupabaseAuthService {
  final GoTrueClient _auth = Supabase.instance.client.auth;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    try {
      // First, check if the username is already taken
      final existingUser = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (existingUser != null) {
        throw Exception('username_taken');
      }

      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'display_name': displayName,
        },
      );

      // The trigger creates a row with defaults. We need to update it
      // with the real username/displayName. Use a small delay to let
      // the trigger complete and the session establish.
      if (response.user != null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          await Supabase.instance.client.from('profiles').upsert({
            'id': response.user!.id,
            'username': username,
            'display_name': displayName,
          });
          appLogger.i('Profile updated after signup');
        } catch (e) {
          appLogger.w('Profile update after signup failed: $e');
        }
      }

      return response;
    } catch (e) {
      appLogger.e('Sign up error: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      appLogger.e('Sign in error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      appLogger.e('Sign out error: $e');
      rethrow;
    }
  }
}
