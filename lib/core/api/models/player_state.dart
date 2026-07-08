import 'package:freezed_annotation/freezed_annotation.dart';

import 'deezer_track.dart';

part 'player_state.freezed.dart';

/// Playback states surfaced by the player layer to the UI.
enum PlaybackStatus { idle, loading, buffering, playing, paused, ended, error }

/// Repeat mode mirrors common music-app semantics.
enum RepeatMode { off, all, one }

/// Snapshot of the current player state. The UI consumes this via Riverpod
/// and never queries the underlying audio backend directly.
@freezed
abstract class PlayerState with _$PlayerState {
  const factory PlayerState({
    @Default(PlaybackStatus.idle) PlaybackStatus status,
    DeezerTrack? currentTrack,
    @Default(Duration.zero) Duration position,
    @Default(Duration.zero) Duration duration,
    @Default(Duration.zero) Duration buffered,
    @Default(false) bool shuffle,
    @Default(RepeatMode.off) RepeatMode repeat,
    @Default(1.0) double volume,
    @Default(0) int crossfadeSeconds,
    @Default(Duration(milliseconds: 500)) Duration transitionDuration,
    String? errorMessage,
  }) = _PlayerState;
}
