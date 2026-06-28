import 'package:freezed_annotation/freezed_annotation.dart';

import 'deezer_track.dart';

part 'queue_state.freezed.dart';

/// Snapshot of the play queue: the history, the current track index and the
/// upcoming items. The UI never mutates this directly — all changes go
/// through `MusicPlayerService`.
@freezed
abstract class QueueState with _$QueueState {
  const factory QueueState({
    @Default(<DeezerTrack>[]) List<DeezerTrack> history,
    @Default(<DeezerTrack>[]) List<DeezerTrack> upcoming,
    DeezerTrack? current,
    @Default(false) bool shuffled,
    @Default(false) bool isRelatedMode,
    @Default(<DeezerTrack>[]) List<DeezerTrack> originalUpcoming,
  }) = _QueueState;
}
