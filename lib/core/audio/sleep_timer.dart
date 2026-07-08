import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_player_service.dart';

/// Sleep-timer state. `null` means inactive. When active the UI shows the
/// remaining duration as a badge; once it hits zero the player is paused.
class SleepTimerState {
  const SleepTimerState({required this.total, required this.remaining});
  final Duration total;
  final Duration remaining;

  bool get isActive => remaining > Duration.zero;
}

class SleepTimerNotifier extends Notifier<SleepTimerState?> {
  Timer? _ticker;

  @override
  SleepTimerState? build() {
    ref.onDispose(_cancel);
    return null;
  }

  void start(Duration duration) {
    _cancel();
    state = SleepTimerState(total: duration, remaining: duration);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state;
      if (s == null) {
        _cancel();
        return;
      }
      final next = s.remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _cancel();
        state = null;
        // Pause on expiration; volume fade is the player layer's concern.
        ref.read(musicPlayerServiceProvider).pause();
      } else {
        state = SleepTimerState(total: s.total, remaining: next);
      }
    });
  }

  void cancel() {
    _cancel();
    state = null;
  }

  void _cancel() {
    _ticker?.cancel();
    _ticker = null;
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState?>(
      SleepTimerNotifier.new,
    );
