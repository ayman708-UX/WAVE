import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../core/auth/supabase_auth_service.dart';
import '../../core/auth/supabase_playlist_sync.dart';
import '../../core/auth/supabase_library_sync.dart';
import '../../core/auth/supabase_profile_service.dart';
import '../../core/storage/library_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/storage/hive_boxes.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    if (!_isLogin && username.isEmpty) {
      _showError('Please choose a username');
      return;
    }
    if (!_isLogin && displayName.isEmpty) {
      _showError('Please enter your display name');
      return;
    }

    setState(() => _isLoading = true);
    final authService = ref.read(supabaseAuthProvider);

    try {
      if (_isLogin) {
        await authService.signInWithEmail(email: email, password: password);
      } else {
        await authService.signUpWithEmail(
          email: email,
          password: password,
          username: username,
          displayName: displayName,
        );
      }
      if (mounted) {
        // Helper to convert objects to safe Hive JSON
        Map<String, dynamic> deepJson(Map<String, dynamic> json) =>
            jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

        // 1. Download existing remote library to local (Merge)
        final tracksBox = Hive.box<dynamic>(HiveBoxes.likedTracks);
        final albumsBox = Hive.box<dynamic>(HiveBoxes.likedAlbums);
        final artistsBox = Hive.box<dynamic>(HiveBoxes.followedArtists);

        await ref
            .read(supabaseLibrarySyncProvider)
            .downloadLibrary(
              onTrackFound: (track) async {
                if (!tracksBox.containsKey(track.id)) {
                  await tracksBox.put(track.id, deepJson(track.toJson()));
                }
              },
              onAlbumFound: (album) async {
                if (!albumsBox.containsKey(album.id)) {
                  await albumsBox.put(album.id, deepJson(album.toJson()));
                }
              },
              onArtistFound: (artist) async {
                if (!artistsBox.containsKey(artist.id)) {
                  await artistsBox.put(artist.id, deepJson(artist.toJson()));
                }
              },
              onPlaylistFound: (playlist) async {
                final likedPlaylistsBox = Hive.box<dynamic>(
                  HiveBoxes.likedPlaylists,
                );
                if (!likedPlaylistsBox.containsKey(playlist.id.toString())) {
                  await likedPlaylistsBox.put(
                    playlist.id.toString(),
                    deepJson(playlist.toJson()),
                  );
                }
              },
            );

        // 2. Download existing remote playlists to local (Merge)
        final playlistsBox = Hive.box<dynamic>(HiveBoxes.playlists);
        final playlistTracksBox = Hive.box<dynamic>(HiveBoxes.playlistTracks);

        await ref
            .read(supabasePlaylistSyncProvider)
            .downloadPlaylists(
              onPlaylistFound: (playlist, tracks) async {
                final existingTitles = playlistsBox.values
                    .whereType<Map>()
                    .map((m) => m['title']?.toString() ?? '')
                    .toSet();
                if (!existingTitles.contains(playlist.title)) {
                  await playlistsBox.put(
                    playlist.id.toString(),
                    deepJson(playlist.toJson()),
                  );
                  await playlistTracksBox.put(
                    playlist.id.toString(),
                    tracks.map((t) => deepJson(t.toJson())).toList(),
                  );
                }
              },
            );

        // 3. Sync local playlists upward (Bulk Upsert)
        final playlists = ref.read(userPlaylistsProvider);
        final trackMap = ref.read(localPlaylistTracksProvider);
        await ref
            .read(supabasePlaylistSyncProvider)
            .syncAllPlaylists(playlists: playlists, trackMap: trackMap);

        // 4. Sync local library upward (Bulk Upsert)
        final likedTracks = ref.read(likedTracksProvider);
        final likedAlbums = ref.read(likedAlbumsProvider);
        final following = ref.read(followedArtistsProvider);
        final likedPlaylists = ref.read(likedPlaylistsProvider);
        await ref
            .read(supabaseLibrarySyncProvider)
            .syncAll(
              tracks: likedTracks,
              albums: likedAlbums,
              artists: following,
              playlists: likedPlaylists,
            );

        // Invalidate to reload UI with merged data, wait a bit to avoid build phase conflicts
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        ref.invalidate(likedTracksProvider);
        ref.invalidate(likedAlbumsProvider);
        ref.invalidate(followedArtistsProvider);
        ref.invalidate(likedPlaylistsProvider);
        ref.invalidate(userPlaylistsProvider);
        ref.invalidate(localPlaylistTracksProvider);
        ref.invalidate(currentProfileProvider);

        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString().toLowerCase();
        String message;
        if (raw.contains('email_not_confirmed') ||
            raw.contains('email not confirmed')) {
          message =
              'Please confirm your email before signing in. Check your inbox.';
        } else if (raw.contains('invalid_credentials') ||
            raw.contains('invalid login')) {
          message = 'Incorrect email or password. Try again.';
        } else if (raw.contains('user_already_exists') ||
            raw.contains('already registered')) {
          message = 'An account with this email already exists.';
        } else if (raw.contains('username_taken')) {
          message = 'This username is already taken. Please choose another.';
        } else if (raw.contains('weak_password') || raw.contains('password')) {
          message = 'Password is too weak. Use at least 6 characters.';
        } else if (raw.contains('invalid_email') ||
            raw.contains('valid email')) {
          message = 'Please enter a valid email address.';
        } else {
          // Fallback: strip the ugly exception wrapper
          message = e
              .toString()
              .replaceAll(
                RegExp(
                  r'AuthApiException\(message: |AuthException\(message: |, statusCode: \d+.*?\)',
                ),
                '',
              )
              .trim();
          if (message.isEmpty) message = 'Something went wrong. Try again.';
        }
        _showError(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    final theme = AppThemeScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: theme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _continueAsGuest() {
    context.go(AppRoutes.home);
  }

  InputDecoration _inputDecoration(
    AppTheme theme,
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.onSurfaceMuted),
      prefixIcon: Icon(icon, color: theme.onSurfaceMuted, size: 20),
      filled: true,
      fillColor: theme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo / brand area
                Icon(PhosphorIconsFill.waveform, size: 56, color: theme.accent),
                const SizedBox(height: 16),
                Text(
                  'WAVE',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: theme.onSurface,
                    letterSpacing: 4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _isLogin
                      ? 'Sign in to sync your library'
                      : 'Join the WAVE community',
                  style: TextStyle(color: theme.onSurfaceMuted, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),

                // Registration-only fields
                if (!_isLogin) ...[
                  TextField(
                    controller: _displayNameController,
                    style: TextStyle(color: theme.onSurface),
                    decoration: _inputDecoration(
                      theme,
                      'Display Name',
                      PhosphorIconsRegular.user,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _usernameController,
                    style: TextStyle(color: theme.onSurface),
                    decoration: _inputDecoration(
                      theme,
                      'Username',
                      PhosphorIconsRegular.at,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                ],

                // Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: theme.onSurface),
                  decoration: _inputDecoration(
                    theme,
                    'Email',
                    PhosphorIconsRegular.envelope,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // Password
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: TextStyle(color: theme.onSurface),
                  decoration:
                      _inputDecoration(
                        theme,
                        'Password',
                        PhosphorIconsRegular.lock,
                      ).copyWith(
                        suffixIcon: GestureDetector(
                          onTap: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          child: Icon(
                            _obscurePassword
                                ? PhosphorIconsRegular.eye
                                : PhosphorIconsRegular.eyeSlash,
                            color: theme.onSurfaceMuted,
                            size: 20,
                          ),
                        ),
                      ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 28),

                // Submit button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: theme.background,
                      disabledBackgroundColor: theme.accent.withValues(
                        alpha: 0.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.background,
                            ),
                          )
                        : Text(
                            _isLogin ? 'Sign In' : 'Create Account',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Toggle login/signup
                TextButton(
                  onPressed: () {
                    setState(() => _isLogin = !_isLogin);
                  },
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 14,
                      ),
                      children: [
                        TextSpan(
                          text: _isLogin
                              ? "Don't have an account? "
                              : 'Already have an account? ',
                        ),
                        TextSpan(
                          text: _isLogin ? 'Sign Up' : 'Sign In',
                          style: TextStyle(
                            color: theme.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: theme.onSurfaceMuted.withValues(alpha: 0.2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: theme.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: theme.onSurfaceMuted.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Continue as Guest
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _continueAsGuest,
                    icon: Icon(
                      PhosphorIconsRegular.userCircle,
                      size: 20,
                      color: theme.onSurfaceMuted,
                    ),
                    label: Text(
                      'Continue as Guest',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: theme.onSurfaceMuted.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Guest users cannot share playlists or be found by others',
                  style: TextStyle(
                    color: theme.onSurfaceMuted.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
