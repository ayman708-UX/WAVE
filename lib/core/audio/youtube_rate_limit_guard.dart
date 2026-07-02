import 'dart:async';

class YoutubeRateLimitException implements Exception {
  YoutubeRateLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

class YoutubeRateLimitGuard {
  YoutubeRateLimitGuard._();

  // Per-device low-request protection.
  //
  // YouTube search results are not the main problem. The expensive part is
  // stream resolving / manifest fetching. This queue makes sure the app does
  // not fire several resolver requests at the same time from the same device.
  static Future<void> _resolverTail = Future<void>.value();
  static DateTime? _lastResolveAttempt;
  static const Duration minimumResolveGap = Duration(seconds: 3);

  static DateTime? _cooldownUntil;
  static String? _lastReason;

  static bool get isLimited {
    final until = _cooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  static Duration? get remaining {
    final until = _cooldownUntil;
    if (until == null) return null;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  static String get userMessage {
    final wait = remaining;
    final waitText = wait == null || wait == Duration.zero
        ? 'a while'
        : _formatDuration(wait);
    return 'YouTube source is busy on this network. '
        'WAVE will use downloaded music where available and will try online '
        'stream resolving again in $waitText.';
  }

  static String? get lastReason => _lastReason;

  static void throwIfLimited() {
    if (isLimited) {
      throw YoutubeRateLimitException(userMessage);
    }
  }

  static Future<T> runLowRequest<T>(Future<T> Function() action) {
    final previous = _resolverTail;
    final gate = Completer<void>();

    _resolverTail = previous.then<void>(
      (_) => gate.future,
      onError: (_) => gate.future,
    );

    return (() async {
      try {
        try {
          await previous;
        } catch (_) {
          // A previous resolver failure must not poison the queue forever.
        }

        throwIfLimited();

        final last = _lastResolveAttempt;
        if (last != null) {
          final elapsed = DateTime.now().difference(last);
          final wait = minimumResolveGap - elapsed;
          if (!wait.isNegative && wait > Duration.zero) {
            await Future<void>.delayed(wait);
          }
        }

        throwIfLimited();
        _lastResolveAttempt = DateTime.now();

        try {
          return await action();
        } catch (error) {
          if (isRateLimitError(error)) {
            record(error);
          }
          rethrow;
        }
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }
    })();
  }

  static void record(
    Object error, {
    Duration cooldown = const Duration(minutes: 15),
  }) {
    _lastReason = error.toString();
    _cooldownUntil = DateTime.now().add(cooldown);
  }

  static void clear() {
    _cooldownUntil = null;
    _lastReason = null;
  }

  static bool isRateLimitError(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('requestlimitexceededexception') ||
        s.contains('rate limiting') ||
        s.contains('too many requests') ||
        s.contains('google_abuse') ||
        s.contains('google abuse') ||
        s.contains('redirect limit exceeded') ||
        s.contains('http 429') ||
        s.contains('status code: 429');
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 1) return 'about 1 minute';
    if (minutes < 60) return 'about $minutes minutes';
    final hours = duration.inHours;
    final extraMinutes = minutes - (hours * 60);
    if (extraMinutes <= 0) return 'about $hours hour${hours == 1 ? '' : 's'}';
    return 'about $hours hour${hours == 1 ? '' : 's'} $extraMinutes minutes';
  }
}
