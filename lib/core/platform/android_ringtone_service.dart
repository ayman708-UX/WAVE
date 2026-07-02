// Removed in WAVE v22I.
// Android ringtone setting was unreliable across devices because it depends on
// protected system settings and ringtone media-store behaviour.
// Keep this file only as a harmless stub in case older imports remain.

class AndroidRingtoneResult {
  const AndroidRingtoneResult({
    required this.status,
    required this.message,
    this.uri,
  });

  final String status;
  final String message;
  final String? uri;

  bool get success => false;
  bool get needsPermission => false;
}

class AndroidRingtoneService {
  AndroidRingtoneService._();

  static bool get isSupported => false;

  static Future<AndroidRingtoneResult> makeRingtone({
    required String filePath,
    required String title,
    String? artist,
  }) async {
    return const AndroidRingtoneResult(
      status: 'removed',
      message: 'Make ringtone was removed.',
    );
  }
}
