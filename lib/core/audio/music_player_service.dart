import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/deezer_track.dart';
import '../api/models/player_state.dart';
import '../api/models/queue_state.dart';

/// Abstract contract for the audio backend. The UI depends only on this
/// interface — the concrete implementation (just_audio, libmpv, etc.) is
/// wired in `main.dart` via the [musicPlayerServiceProvider].
abstract class MusicPlayerService {
  /// Streams the live [PlayerState] (status, position, duration, etc.).
  Stream<PlayerState> get playerStateStream;

  /// Streams the live [QueueState] (history + upcoming).
  Stream<QueueState> get queueStateStream;

  /// Latest snapshot — useful for synchronous reads.
  PlayerState get playerState;
  QueueState get queueState;

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> skipToIndex(int indexInUpcoming);
  Future<void> skipToHistory(int indexInHistory);
  Future<void> setShuffle(bool value);
  Future<void> setRepeat(RepeatMode mode);
  Future<void> setVolume(double volume);
  Future<void> setCrossfadeSeconds(int seconds);

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  /// Replaces the current queue with [tracks] and starts at [startIndex].
  /// If [startIndex] is null, it defaults to 0, but if shuffle is active, it picks a random start index.
  Future<void> playTracks(List<DeezerTrack> tracks, {int? startIndex});

  Future<void> addToQueueNext(DeezerTrack track);
  Future<void> addToQueueLast(DeezerTrack track);
  Future<void> removeFromQueue(int indexInUpcoming);
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> clearQueue();
  Future<void> toggleRelatedMode();

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

  /// Whether the given track is downloaded for offline playback.
  bool isDownloaded(int trackId);

  /// 5-band equaliser values (–12..12 dB). UI-driven, may no-op on backends
  /// that lack EQ support.
  Future<void> setEqualizer(List<double> bandsDb);

  Future<void> dispose();
}

/// Riverpod hook. Override in `main.dart` once a concrete implementation
/// (e.g. just_audio) is provided.
final musicPlayerServiceProvider = Provider<MusicPlayerService>((ref) {
  throw UnimplementedError(
    'MusicPlayerService has no default implementation. '
    'Override musicPlayerServiceProvider in main.dart.',
  );
});
