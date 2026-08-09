import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../api/settings_service.dart';

/// Defaults point at the PlayTorrio project; override with
/// `PLAYTORRIO_SUPABASE_URL` / `PLAYTORRIO_SUPABASE_ANON_KEY` via `--dart-define`.
const String kPlaytorrioSupabaseUrl = String.fromEnvironment(
  'PLAYTORRIO_SUPABASE_URL',
  defaultValue: 'https://lxapazzlduwwecatebti.supabase.co',
);
const String kPlaytorrioSupabaseAnonKey = String.fromEnvironment(
  'PLAYTORRIO_SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx4YXBhenpsZHV3d2VjYXRlYnRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyOTI2NDQsImV4cCI6MjA5Mjg2ODY0NH0.a9e7zUEdWDmf4Qor-rbYZ6G0sMTEYcfKnwTrXjVrBWY',
);

class PlaytorrioCloudSyncService {
  PlaytorrioCloudSyncService._();
  static final PlaytorrioCloudSyncService instance =
      PlaytorrioCloudSyncService._();

  static const _accessKey = 'stories_supabase_access_token';
  static const _refreshKey = 'stories_supabase_refresh_token';
  static const _emailKey = 'stories_supabase_email';

  static const _restSettings = '/rest/v1/user_settings';
  static const _preferUpsert = 'return=minimal,resolution=merge-duplicates';

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  final _settings = SettingsService();

  String? _access;
  String? _refresh;

  String? get _base {
    final u = kPlaytorrioSupabaseUrl.trim();
    if (u.isEmpty) return null;
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  String? get _anon {
    final k = kPlaytorrioSupabaseAnonKey.trim();
    return k.isEmpty ? null : k;
  }

  bool get isConfigured => _base != null && _anon != null;

  bool get isAnonKeyJwtFormat {
    final k = _anon;
    if (k == null || k.isEmpty) return false;
    return k.split('.').length == 3 && k.startsWith('eyJ');
  }

  void _requireConfig() {
    if (!isConfigured) {
      throw const PlaytorrioCloudException(
        'Cloud sync is not configured in this build.',
      );
    }
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secure.read(key: key).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[Stories Cloud] secure read $key: $e');
      return null;
    }
  }

  Future<String?> get _accessToken async {
    if (_access != null && _access!.isNotEmpty) return _access;
    _access = await _readSecure(_accessKey);
    return _access;
  }

  Future<String?> get _refreshToken async {
    if (_refresh != null && _refresh!.isNotEmpty) return _refresh;
    _refresh = await _readSecure(_refreshKey);
    return _refresh;
  }

  Future<void> _saveSession(
    String access,
    String? refresh, {
    String? email,
  }) async {
    _access = access;
    await _secure.write(key: _accessKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      _refresh = refresh;
      await _secure.write(key: _refreshKey, value: refresh);
    }
    if (email != null && email.isNotEmpty) {
      await _secure.write(key: _emailKey, value: email);
    }
  }

  Map<String, String> _headers(String token) => {
        'apikey': _anon!,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  void _logHttpFailure(String op, int code, String body) {
    final snippet = body.length > 500 ? '${body.substring(0, 500)}…' : body;
    debugPrint('[Stories Cloud] $op FAILED: HTTP $code body=$snippet');
  }

  static bool isJwtAccessExpired(String jwt, {int leewaySeconds = 60}) {
    final exp = jwtExpUnixSeconds(jwt);
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp - leewaySeconds;
  }

  static int? jwtExpUnixSeconds(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    var seg = parts[1];
    final m = seg.length % 4;
    if (m > 0) seg += '=' * (4 - m);
    try {
      final map = json.decode(utf8.decode(base64Url.decode(seg)))
          as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is int) return exp;
      if (exp is num) return exp.toInt();
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _clearAccessTokenOnly() async {
    _access = null;
    await _secure.delete(key: _accessKey);
  }

  Future<http.Response> _withAccessRetry(
    Future<http.Response> Function(String accessToken) send,
  ) async {
    await _ensureAccess();
    var token = await _accessToken;
    if (token == null || token.isEmpty) {
      throw const PlaytorrioCloudException('Not signed in');
    }
    var res = await send(token);
    if (res.statusCode != 401) return res;
    await _clearAccessTokenOnly();
    try {
      await _ensureAccess();
    } catch (_) {
      await signOut();
      return res;
    }
    token = await _accessToken;
    if (token == null || token.isEmpty) {
      await signOut();
      return res;
    }
    res = await send(token);
    if (res.statusCode == 401) await signOut();
    return res;
  }

  static String? userIdFromJwt(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    var seg = parts[1];
    final m = seg.length % 4;
    if (m > 0) seg += '=' * (4 - m);
    try {
      final jsonMap = json.decode(utf8.decode(base64Url.decode(seg)))
          as Map<String, dynamic>;
      return jsonMap['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> signedInEmail() => _readSecure(_emailKey);

  Future<void> _ensureAccess() async {
    final existing = await _accessToken;
    if (existing != null &&
        existing.isNotEmpty &&
        !isJwtAccessExpired(existing)) {
      return;
    }
    _access = null;
    final rt = await _refreshToken;
    if (rt == null || rt.isEmpty) {
      throw const PlaytorrioCloudException('Not signed in');
    }
    _requireConfig();
    final res = await http.post(
      Uri.parse('$_base/auth/v1/token?grant_type=refresh_token'),
      headers: {
        'apikey': _anon!,
        'Content-Type': 'application/json',
      },
      body: json.encode({'refresh_token': rt}),
    );
    if (res.statusCode != 200) {
      await signOut();
      throw const PlaytorrioCloudException('Session expired. Sign in again.');
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    await _saveSession(
      data['access_token'] as String,
      data['refresh_token'] as String?,
    );
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _requireConfig();
    final res = await http.post(
      Uri.parse('$_base/auth/v1/token?grant_type=password'),
      headers: {
        'apikey': _anon!,
        'Content-Type': 'application/json',
      },
      body: json.encode({'email': email.trim(), 'password': password}),
    );
    if (res.statusCode != 200) {
      var msg = res.body;
      try {
        final m = json.decode(res.body) as Map<String, dynamic>?;
        msg = m?['error_description']?.toString() ??
            m?['message']?.toString() ??
            msg;
      } catch (_) {}
      throw PlaytorrioCloudException(msg);
    }
    final data = json.decode(res.body) as Map<String, dynamic>;
    await _saveSession(
      data['access_token'] as String,
      data['refresh_token'] as String?,
      email: email.trim(),
    );
  }

  Future<void> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    _requireConfig();
    final res = await http.post(
      Uri.parse('$_base/auth/v1/signup'),
      headers: {
        'apikey': _anon!,
        'Content-Type': 'application/json',
      },
      body: json.encode({'email': email.trim(), 'password': password}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      var msg = res.body;
      try {
        final m = json.decode(res.body) as Map<String, dynamic>?;
        msg = m?['error_description']?.toString() ??
            m?['message']?.toString() ??
            msg;
      } catch (_) {}
      throw PlaytorrioCloudException(msg);
    }
    final data = json.decode(res.body) as Map<String, dynamic>?;
    final at = data?['access_token'] as String?;
    if (at != null && at.isNotEmpty) {
      await _saveSession(
        at,
        data!['refresh_token'] as String?,
        email: email.trim(),
      );
      return;
    }
    await signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    final token = await _accessToken;
    if (token != null && token.isNotEmpty && isConfigured) {
      try {
        unawaited(http.post(
          Uri.parse('$_base/auth/v1/logout'),
          headers: {
            'apikey': _anon!,
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ));
      } catch (_) {}
    }
    _access = null;
    _refresh = null;
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    await _secure.delete(key: _emailKey);
  }

  Future<bool> hasStoredSession() async =>
      (await _accessToken)?.isNotEmpty == true ||
      (await _refreshToken)?.isNotEmpty == true;

  Future<bool> isSettingsSyncEnabled() =>
      _settings.isPlaytorrioCloudSettingsSyncEnabled();

  Future<void> setSettingsSyncEnabled(bool v) =>
      _settings.setPlaytorrioCloudSettingsSyncEnabled(v);

  Future<void> pullUserSettings() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isSettingsSyncEnabled()) return;
    if (!await hasStoredSession()) return;

    final pid = await _settings.getPlaytorrioProfileId();
    final res = await _withAccessRetry(
      (t) {
        final userId = userIdFromJwt(t);
        if (userId == null) {
          return Future.value(
            http.Response('{"message":"no sub in access token"}', 400),
          );
        }
        return http.get(
          Uri.parse(
            '$_base$_restSettings?select=prefs&user_id=eq.$userId&profile_id=eq.$pid',
          ),
          headers: _headers(t),
        );
      },
    );
    if (res.statusCode != 200) {
      debugPrint('[Stories Cloud] pull settings: ${res.statusCode}');
      return;
    }
    final decoded = json.decode(res.body);
    if (decoded is! List || decoded.isEmpty) return;
    final first = decoded.first;
    if (first is! Map) return;
    final p = first['prefs'];
    if (p is! Map) return;
    await _settings.applyCloudPreferenceMap(
      p.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  Future<void> pushUserSettings() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await isSettingsSyncEnabled()) return;
    if (!await hasStoredSession()) return;

    final pid = await _settings.getPlaytorrioProfileId();
    final map = await _settings.exportForCloudSync();

    final res = await _withAccessRetry(
      (t) {
        final uid = userIdFromJwt(t);
        if (uid == null) {
          return Future.value(
            http.Response('{"message":"no sub in access token"}', 400),
          );
        }
        return http.post(
          Uri.parse('$_base$_restSettings?on_conflict=user_id,profile_id'),
          headers: {
            ..._headers(t),
            'Prefer': _preferUpsert,
          },
          body: json.encode({
            'user_id': uid,
            'profile_id': pid,
            'prefs': map,
          }),
        );
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _logHttpFailure('push settings', res.statusCode, res.body);
    }
  }

  void scheduleSettingsPush() {
    if (kIsWeb) return;
    unawaited(() async {
      try {
        await pushUserSettings();
      } catch (e) {
        debugPrint('[Stories Cloud] settings push: $e');
      }
    }());
  }

  Timer? _debouncedSettingsPushTimer;

  void scheduleDebouncedSettingsPush({
    Duration delay = const Duration(seconds: 4),
  }) {
    if (kIsWeb) return;
    _debouncedSettingsPushTimer?.cancel();
    _debouncedSettingsPushTimer = Timer(delay, () {
      _debouncedSettingsPushTimer = null;
      scheduleSettingsPush();
    });
  }

  /// Pull cloud audiobook prefs on startup when signed in.
  Future<void> pullOnStartup() async {
    if (kIsWeb) return;
    if (!isConfigured) return;
    if (!await hasStoredSession()) return;
    if (!isAnonKeyJwtFormat) {
      debugPrint(
        '[Stories Cloud] pullOnStartup skipped: apikey must be legacy anon JWT.',
      );
      return;
    }
    try {
      if (await isSettingsSyncEnabled()) {
        await pullUserSettings();
      }
    } catch (e) {
      debugPrint('[Stories Cloud] startup: $e');
    }
  }

  /// After sign-in: merge remote data, then upload local state.
  Future<void> syncAfterLogin() async {
    await pullOnStartup();
    await pushUserSettings();
  }
}

class PlaytorrioCloudException implements Exception {
  const PlaytorrioCloudException(this.message);
  final String message;
  @override
  String toString() => message;
}
