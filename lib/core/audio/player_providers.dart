import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/player_state.dart';
import '../api/models/queue_state.dart';
import 'music_player_service.dart';

/// Streams the live [PlayerState] from the backend service. Seeded with the
/// current snapshot so consumers don't flicker through `loading` first.
final playerStateProvider = StreamProvider<PlayerState>((ref) {
  final svc = ref.watch(musicPlayerServiceProvider);
  return svc.playerStateStream;
});

/// Streams the live [QueueState] from the backend service.
final queueStateProvider = StreamProvider<QueueState>((ref) {
  final svc = ref.watch(musicPlayerServiceProvider);
  return svc.queueStateStream;
});

/// Convenience: synchronous snapshot of the player state, falling back to
/// [PlayerState.initial] when the stream hasn't emitted yet.
final playerSnapshotProvider = Provider<PlayerState>((ref) {
  return ref
      .watch(playerStateProvider)
      .maybeWhen(
        data: (s) => s,
        orElse: () => ref.read(musicPlayerServiceProvider).playerState,
      );
});

/// Convenience: synchronous snapshot of the queue state.
final queueSnapshotProvider = Provider<QueueState>((ref) {
  return ref
      .watch(queueStateProvider)
      .maybeWhen(
        data: (s) => s,
        orElse: () => ref.read(musicPlayerServiceProvider).queueState,
      );
});

/// Whether a track is currently loaded (regardless of play/pause state).
/// Drives mini-player visibility.
final hasActiveTrackProvider = Provider<bool>((ref) {
  final state = ref.watch(playerSnapshotProvider);
  return state.currentTrack != null;
});

/// Convenience accessor that always reads the player without listening — used
/// by buttons / gesture handlers.
final playerControlsProvider = Provider<MusicPlayerService>((ref) {
  return ref.read(musicPlayerServiceProvider);
});

/// Helper to listen to a stream-only [BuildContext] reactively without
/// re-importing flutter_riverpod everywhere.
extension PlayerWidgetRefX on WidgetRef {
  PlayerState get playerSnapshot => watch(playerSnapshotProvider);
  QueueState get queueSnapshot => watch(queueSnapshotProvider);
}
