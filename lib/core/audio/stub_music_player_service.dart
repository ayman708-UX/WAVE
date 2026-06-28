import 'dart:async';
import 'dart:math';

import '../api/models/deezer_track.dart';
import '../api/models/player_state.dart';
import '../api/models/queue_state.dart';
import 'music_player_service.dart';

/// Stub implementation of [MusicPlayerService] used during early development
/// until the real `just_audio`-backed service is wired up.
///
/// All methods mutate in-memory state and broadcast updates over the
/// [playerStateStream] / [queueStateStream] streams so that the UI behaves
/// correctly even without an audio backend.
class StubMusicPlayerService implements MusicPlayerService {
  StubMusicPlayerService();

  final StreamController<PlayerState> _playerCtrl =
      StreamController<PlayerState>.broadcast();
  final StreamController<QueueState> _queueCtrl =
      StreamController<QueueState>.broadcast();

  PlayerState _player = const PlayerState();
  QueueState _queue = const QueueState();

  @override
  Stream<PlayerState> get playerStateStream => _playerCtrl.stream;

  @override
  Stream<QueueState> get queueStateStream => _queueCtrl.stream;

  @override
  PlayerState get playerState => _player;

  @override
  QueueState get queueState => _queue;

  void _emitPlayer(PlayerState next) {
    _player = next;
    _playerCtrl.add(next);
  }

  void _emitQueue(QueueState next) {
    _queue = next;
    _queueCtrl.add(next);
  }

  @override
  Future<void> play() async {
    _emitPlayer(_player.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    _emitPlayer(_player.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> togglePlayPause() async {
    if (_player.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> stop() async {
    _emitPlayer(
      _player.copyWith(
        status: PlaybackStatus.idle,
        position: Duration.zero,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _emitPlayer(_player.copyWith(position: position));
  }

  @override
  Future<void> skipNext() async {
    if (_queue.upcoming.isEmpty) return;
    final next = _queue.upcoming.first;
    final newUpcoming = _queue.upcoming.sublist(1);
    final newHistory = <DeezerTrack>[
      ..._queue.history,
      if (_queue.current != null) _queue.current!,
    ];
    _emitQueue(
      _queue.copyWith(
        history: newHistory,
        current: next,
        upcoming: newUpcoming,
      ),
    );
    _emitPlayer(
      _player.copyWith(
        currentTrack: next,
        position: Duration.zero,
        status: PlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> skipToIndex(int indexInUpcoming) async {
    if (indexInUpcoming < 0 || indexInUpcoming >= _queue.upcoming.length) return;
    final next = _queue.upcoming[indexInUpcoming];
    final newUpcoming = _queue.upcoming.sublist(indexInUpcoming + 1);
    final skippedTracks = _queue.upcoming.sublist(0, indexInUpcoming);
    final newHistory = <DeezerTrack>[
      ..._queue.history,
      if (_queue.current != null) _queue.current!,
      ...skippedTracks,
    ];
    _emitQueue(
      _queue.copyWith(
        history: newHistory,
        current: next,
        upcoming: newUpcoming,
      ),
    );
    _emitPlayer(
      _player.copyWith(
        currentTrack: next,
        position: Duration.zero,
      ),
    );
  }

  @override
  Future<void> skipToHistory(int indexInHistory) async {
    if (indexInHistory < 0 || indexInHistory >= _queue.history.length) return;
    final prev = _queue.history[indexInHistory];
    final newHistory = _queue.history.sublist(0, indexInHistory);
    final skippedHistory = _queue.history.sublist(indexInHistory + 1);
    final newUpcoming = <DeezerTrack>[
      ...skippedHistory,
      if (_queue.current != null) _queue.current!,
      ..._queue.upcoming,
    ];
    _emitQueue(
      _queue.copyWith(
        history: newHistory,
        current: prev,
        upcoming: newUpcoming,
      ),
    );
    _emitPlayer(
      _player.copyWith(
        currentTrack: prev,
        position: Duration.zero,
      ),
    );
  }

  @override
  Future<void> skipPrevious() async {
    if (_queue.history.isEmpty) {
      await seek(Duration.zero);
      return;
    }
    final prev = _queue.history.last;
    final newHistory = _queue.history.sublist(0, _queue.history.length - 1);
    final newUpcoming = <DeezerTrack>[
      if (_queue.current != null) _queue.current!,
      ..._queue.upcoming,
    ];
    _emitQueue(
      _queue.copyWith(
        history: newHistory,
        current: prev,
        upcoming: newUpcoming,
      ),
    );
    _emitPlayer(
      _player.copyWith(
        currentTrack: prev,
        position: Duration.zero,
        status: PlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> setShuffle(bool value) async {
    _emitPlayer(_player.copyWith(shuffle: value));
    _emitQueue(_queue.copyWith(shuffled: value));
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    _emitPlayer(_player.copyWith(repeat: mode));
  }

  @override
  Future<void> setVolume(double volume) async {
    _emitPlayer(_player.copyWith(volume: volume.clamp(0.0, 1.0)));
  }

  @override
  Future<void> setCrossfadeSeconds(int seconds) async {
    _emitPlayer(_player.copyWith(crossfadeSeconds: seconds.clamp(0, 12)));
  }

  @override
  Future<void> playTracks(
    List<DeezerTrack> tracks, {
    int? startIndex,
  }) async {
    if (tracks.isEmpty) return;
    int index = 0;
    if (startIndex != null) {
      index = startIndex.clamp(0, tracks.length - 1);
    } else {
      if (_player.shuffle) {
        index = Random().nextInt(tracks.length);
      }
    }
    final clampedIndex = index;
    final current = tracks[clampedIndex];
    _emitQueue(
      QueueState(
        history: const <DeezerTrack>[],
        current: current,
        upcoming: tracks.sublist(clampedIndex + 1),
      ),
    );
    _emitPlayer(
      _player.copyWith(
        currentTrack: current,
        position: Duration.zero,
        status: PlaybackStatus.playing,
      ),
    );
  }

  @override
  Future<void> addToQueueNext(DeezerTrack track) async {
    _emitQueue(
      _queue.copyWith(upcoming: <DeezerTrack>[track, ..._queue.upcoming]),
    );
  }

  @override
  Future<void> addToQueueLast(DeezerTrack track) async {
    _emitQueue(
      _queue.copyWith(upcoming: <DeezerTrack>[..._queue.upcoming, track]),
    );
  }

  @override
  Future<void> removeFromQueue(int indexInUpcoming) async {
    if (indexInUpcoming < 0 || indexInUpcoming >= _queue.upcoming.length) {
      return;
    }
    final next = <DeezerTrack>[..._queue.upcoming]..removeAt(indexInUpcoming);
    _emitQueue(_queue.copyWith(upcoming: next));
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final list = <DeezerTrack>[..._queue.upcoming];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    final target = newIndex.clamp(0, list.length);
    list.insert(target, item);
    _emitQueue(_queue.copyWith(upcoming: list));
  }

  @override
  Future<void> clearQueue() async {
    _emitQueue(
      _queue.copyWith(
        upcoming: const <DeezerTrack>[],
        history: const <DeezerTrack>[],
      ),
    );
  }

  @override
  bool isDownloaded(int trackId) => false;

  @override
  Future<void> setEqualizer(List<double> bandsDb) async {
    // No-op in the stub backend.
  }

  @override
  Future<void> dispose() async {
    await _playerCtrl.close();
    await _queueCtrl.close();
  }

  @override
  Future<void> toggleRelatedMode() async {
    // Stub implementation
    if (_queue.isRelatedMode) {
      _emitQueue(_queue.copyWith(
        isRelatedMode: false,
        upcoming: _queue.originalUpcoming,
        originalUpcoming: const <DeezerTrack>[],
      ));
    } else {
      _emitQueue(_queue.copyWith(
        isRelatedMode: true,
        originalUpcoming: _queue.upcoming,
        upcoming: const <DeezerTrack>[],
      ));
    }
  }
}
