import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audiobook_service.dart';
import 'android_auto_ids.dart';
import 'android_auto_browse.dart';
import 'audiobook_prefs_keys.dart';
import 'audio_handler.dart';
import 'torrent_stream_service.dart';
import 'notification_cover_cache.dart';
import '../services/playtorrio_cloud_sync_service.dart';
import 'settings_service.dart';

class AudiobookPlayerService {
  static final AudiobookPlayerService _instance = AudiobookPlayerService._internal();
  factory AudiobookPlayerService() => _instance;
  AudiobookPlayerService._internal();

  /// Headers for libtorrent's loopback HTTP stream (mpv is picky without these).
  static const Map<String, String> magnetStreamHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  final Player _player = Player();
  PlayTorrioAudioHandler? _handler;
  
  // State
  final ValueNotifier<Audiobook?> currentBook = ValueNotifier<Audiobook?>(null);
  final ValueNotifier<int> currentChapterIndex = ValueNotifier<int>(0);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier<bool>(false);
  /// True while a chapter is opening/buffering — UI should show loading, not pause.
  final ValueNotifier<bool> isPreparingPlayback = ValueNotifier<bool>(false);
  final ValueNotifier<bool> autoplay = ValueNotifier<bool>(true);
  final ValueNotifier<double> playbackRate = ValueNotifier<double>(1.0);
  
  List<AudiobookChapter> _currentChapters = [];
  final List<StreamSubscription> _subscriptions = [];
  bool _playerListenersAttached = false;
  bool _mpvAudiobookTuned = false;
  bool _playbackRateLoaded = false;
  Future<void>? _playbackRateLoadFuture;
  Timer? _progressTicker;
  bool _isResuming = false;
  Timer? _progressSaveDebounce;
  /// Wall-clock fallback when torrent loopback streams report position 0.
  Duration _wallClockBase = Duration.zero;
  DateTime? _wallClockStartedAt;
  /// Ignore position-driven persistence briefly after resume/chapter opens — mpv often
  /// emits 0 before the clock catches up and would overwrite real progress.
  DateTime? _ignoreProgressPersistenceUntil;
  /// While non-null, ignore player clock readings that snap back to the start.
  Duration? _resumeTargetPosition;
  /// Torrent loopback URLs often never report a trustworthy position.
  bool _streamClockUnreliable = false;
  /// Lowest position we know the user has reached this chapter — never snap UI/audio below it.
  int _positionFloorMs = 0;
  DateTime? _lastCorrectiveSeekAt;
  Uri? _cachedArtUri;

  bool _isLoopbackArtUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('127.0.0.1') ||
        lower.contains('localhost') ||
        lower.contains('::1');
  }

  Uri? _resolveArtUri(Audiobook book) {
    if (_cachedArtUri != null) return _cachedArtUri;
    var art = book.thumbUrl.trim();
    if (art.isEmpty) art = book.coverImage.trim();
    if (art.isEmpty || _isLoopbackArtUrl(art)) return null;
    return Uri.tryParse(art);
  }

  bool _isTorrentBackedBook(Audiobook book) {
    final magnet = book.magnetLink;
    return (book.source == 'magnet' || book.source == 'audiobookbay') &&
        magnet != null &&
        magnet.trim().isNotEmpty;
  }

  void _releaseTorrentForBook(Audiobook book) {
    if (!_isTorrentBackedBook(book)) return;
    TorrentStreamService().releaseAudiobookMagnet(book.magnetLink!);
  }

  Future<void> setNotificationCoverBytes(Uint8List bytes) async {
    final book = currentBook.value;
    if (book == null || bytes.isEmpty) return;
    final uri = await cacheNotificationCover(book.audioBookId, bytes);
    if (uri == null) return;
    _cachedArtUri = uri;
    publishNowPlaying();
  }

  /// Pushes queue, metadata, and playback state to the system media session.
  void publishNowPlaying() {
    _syncChapterQueue();
    _syncMediaItem();
    _updateSystemState();
  }

  void _scheduleNowPlayingRefresh() {
    publishNowPlaying();
    Future<void>.delayed(const Duration(milliseconds: 400), publishNowPlaying);
    Future<void>.delayed(const Duration(seconds: 2), publishNowPlaying);
  }

  MediaItem? _buildCurrentMediaItem() {
    final book = currentBook.value;
    if (book == null) return null;

    final idx = currentChapterIndex.value;
    final chapters = _currentChapters;
    final chapterTitle = (idx >= 0 && idx < chapters.length)
        ? chapters[idx].title
        : '';

    String artist = 'Tokybook';
    if (book.source == 'audiozaic') artist = 'Audiozaic';
    if (book.source == 'goldenaudiobook') artist = 'GoldenAudiobook';
    if (book.source == 'appaudiobooks') artist = 'AppAudiobooks';
    if (book.source == 'magnet') artist = 'Torrent';
    if (book.source == 'audiobookbay') artist = 'Audiobook Bay';

    final title = chapterTitle.isEmpty ? book.title : chapterTitle;
    final dur = duration.value;

    return MediaItem(
      id: AndroidAutoIds.chapter(book.audioBookId, idx),
      album: book.title,
      title: title,
      artist: artist,
      displayTitle: title,
      displaySubtitle: book.title,
      displayDescription: artist,
      duration: dur > Duration.zero ? dur : null,
      artUri: _resolveArtUri(book),
    );
  }

  void _raisePositionFloor(Duration resolved) {
    final ms = resolved.inMilliseconds;
    if (ms > _positionFloorMs) _positionFloorMs = ms;
  }

  void _maybeCorrectiveSeek() {
    if (_positionFloorMs < 5000 || !isPlaying.value) return;
    final now = DateTime.now();
    if (_lastCorrectiveSeekAt != null &&
        now.difference(_lastCorrectiveSeekAt!) < const Duration(seconds: 2)) {
      return;
    }
    final target = Duration(milliseconds: _positionFloorMs);
    final playerPos = _player.state.position;
    if (playerPos >= target - const Duration(seconds: 6)) return;
    _lastCorrectiveSeekAt = now;
    debugPrint(
      'AudiobookPlayerService: corrective seek to ${target.inSeconds}s '
      '(player at ${playerPos.inSeconds}s)',
    );
    unawaited(_player.seek(target));
  }

  bool _acceptPlayerPosition(Duration playerPosition) {
    if (_positionFloorMs > 0 &&
        playerPosition.inMilliseconds > _positionFloorMs + 120_000) {
      return false;
    }

    if (_positionFloorMs > 8000 &&
        playerPosition.inMilliseconds < _positionFloorMs - 5000) {
      _maybeCorrectiveSeek();
      return false;
    }

    final target = _resumeTargetPosition;
    final until = _ignoreProgressPersistenceUntil;
    final inSettleWindow =
        until != null && DateTime.now().isBefore(until);

    if (inSettleWindow &&
        playerPosition < const Duration(seconds: 2) &&
        _wallClockBase > const Duration(seconds: 5)) {
      return false;
    }

    if (target != null && target > const Duration(seconds: 3)) {
      if (playerPosition < const Duration(seconds: 2)) {
        return false;
      }
      final delta = (playerPosition - target).abs();
      if (delta > const Duration(seconds: 8) &&
          playerPosition < target - const Duration(seconds: 8)) {
        return false;
      }
    }
    return true;
  }

  void _applyResolvedPosition(Duration resolved) {
    position.value = resolved;
    _wallClockBase = resolved;
    _raisePositionFloor(resolved);
    if (isPlaying.value) {
      _markWallClock(base: resolved);
    }
  }

  bool get _mayPersistPlaybackProgress {
    if (_isResuming) return false;
    final until = _ignoreProgressPersistenceUntil;
    if (until != null && DateTime.now().isBefore(until)) return false;
    return currentBook.value != null;
  }

  void _scheduleDebouncedProgressSave() {
    if (!_mayPersistPlaybackProgress) return;
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(milliseconds: 900), () {
      _progressSaveDebounce = null;
      if (_mayPersistPlaybackProgress) {
        unawaited(_saveProgress());
      }
    });
  }

  void init(BaseAudioHandler handler) {
    attachHandler(handler);
    ensurePlayerListeners();
  }

  void attachHandler(BaseAudioHandler handler) {
    _handler = handler as PlayTorrioAudioHandler;
  }

  PlayTorrioAudioHandler? get audioHandler => _handler;

  List<AudiobookChapter> get currentChapters =>
      List<AudiobookChapter>.unmodifiable(_currentChapters);

  int get currentChapterCount => _currentChapters.length;

  /// Attaches media_kit listeners. Safe to call even when [AudioService] failed.
  void ensurePlayerListeners() {
    if (_playerListenersAttached) return;
    _playerListenersAttached = true;

    _subscriptions.add(_player.stream.position.listen((p) {
      if (isPreparingPlayback.value) return;
      if (!_acceptPlayerPosition(p)) return;
      if (_streamClockUnreliable && isPlaying.value) {
        if (p > position.value + const Duration(seconds: 1)) {
          position.value = p;
          _wallClockBase = p;
          _raisePositionFloor(p);
          _markWallClock(base: p);
          _updateSystemState();
          _scheduleDebouncedProgressSave();
        }
        return;
      }
      position.value = p;
      _wallClockBase = p;
      _raisePositionFloor(p);
      _updateSystemState();
      _scheduleDebouncedProgressSave();
    }));

    _subscriptions.add(_player.stream.duration.listen((d) {
      if (isPreparingPlayback.value && d <= Duration.zero) return;
      if (d > Duration.zero) {
        duration.value = d;
        _syncMediaItem();
      }
      _updateSystemState();
    }));

    _subscriptions.add(_player.stream.playing.listen((pl) {
      if (isPreparingPlayback.value) return;
      final wasPlaying = isPlaying.value;
      isPlaying.value = pl;
      if (pl) {
        if (_wallClockStartedAt == null) {
          _markWallClock(base: _wallClockBase);
        }
        _startProgressTicker();
      } else {
        _stopProgressTicker();
      }
      _updateSystemState();
      if (pl && !wasPlaying) {
        _scheduleNowPlayingRefresh();
      }
      if (wasPlaying && !pl && !_isResuming && currentBook.value != null) {
        unawaited(_saveProgress(force: true));
      }
    }));

    _subscriptions.add(_player.stream.buffering.listen((b) {
      isBuffering.value = b;
      if (isPlaying.value && _wallClockStartedAt == null) {
        _markWallClock(base: _wallClockBase);
      }
      _updateSystemState();
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (completed && autoplay.value) {
        final nextIdx = currentChapterIndex.value + 1;
        if (nextIdx < _currentChapters.length) {
          unawaited(changeChapter(nextIdx));
        }
      }
    }));

    // Ticker starts when playback begins, not at app launch.
  }

  void _resetPlaybackUiState() {
    position.value = Duration.zero;
    duration.value = Duration.zero;
    isPlaying.value = false;
    isBuffering.value = true;
    isPreparingPlayback.value = true;
    _resetWallClock();
    _stopProgressTicker();
  }

  void _finishPreparingPlayback({Duration? positionHint}) {
    isPreparingPlayback.value = false;
    final st = _player.state;
    if (st.duration > Duration.zero) {
      duration.value = st.duration;
    }
    if (positionHint != null && positionHint > Duration.zero) {
      final playerPos = st.position;
      final resolved = playerPos > Duration.zero &&
              (playerPos - positionHint).abs() < const Duration(seconds: 8)
          ? playerPos
          : positionHint;
      _applyResolvedPosition(resolved);
    } else if (st.position > Duration.zero && _acceptPlayerPosition(st.position)) {
      _applyResolvedPosition(st.position);
    }
    isPlaying.value = st.playing;
    isBuffering.value = st.buffering;
    if (isPlaying.value) {
      if (_wallClockStartedAt == null) {
        _markWallClock(base: _wallClockBase);
      }
      _startProgressTicker();
    }
    _syncMediaItem();
    _updateSystemState();
    _scheduleNowPlayingRefresh();
    unawaited(_applyPlaybackRate(force: true));
  }

  Future<void> _playThroughHandler() async {
    final handler = _handler;
    if (handler != null) {
      await handler.play();
      return;
    }
    await _player.play();
  }
  Future<void> _waitUntilPlaybackReady({
    Audiobook? book,
    AudiobookChapter? chapter,
    Duration timeout = const Duration(seconds: 20),
    bool relaxedBuffer = false,
  }) async {
    final torrent = book != null &&
        chapter != null &&
        _isTorrentChapter(book, chapter);
    final deadline = DateTime.now().add(
      torrent ? timeout : const Duration(seconds: 10),
    );

    while (DateTime.now().isBefore(deadline)) {
      final st = _player.state;
      if (st.duration > Duration.zero) {
        duration.value = st.duration;
      }

      final pos = st.position;
      if (pos > Duration.zero && _acceptPlayerPosition(pos)) {
        position.value = pos;
        _wallClockBase = pos;
        _raisePositionFloor(pos);
        if (!st.buffering) return;
      }

      if (torrent) {
        final minBuffer = relaxedBuffer
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 500);
        if (st.duration > Duration.zero && st.playing && !st.buffering) {
          return;
        }
        if (st.duration > Duration.zero &&
            st.buffer >= minBuffer &&
            !st.buffering) {
          return;
        }
      } else {
        if (st.duration > Duration.zero && !st.buffering) return;
        if (st.playing && !st.buffering && st.duration > Duration.zero) return;
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    debugPrint('AudiobookPlayerService: playback ready wait timed out');
  }

  Future<void> _waitForTorrentDuration({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final st = _player.state;
      if (st.duration > Duration.zero) {
        duration.value = st.duration;
        return;
      }
      if (st.position > Duration.zero) return;
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _quickTorrentSeek(Duration target) async {
    _resumeTargetPosition = target;
    _ignoreProgressPersistenceUntil =
        DateTime.now().add(const Duration(seconds: 12));
    _positionFloorMs = target.inMilliseconds;

    for (var attempt = 0; attempt < 4; attempt++) {
      await _player.seek(target);
      await Future.delayed(Duration(milliseconds: 100 + attempt * 70));
      final p = _player.state.position;
      if (p > Duration.zero &&
          (p - target).abs() < const Duration(seconds: 10)) {
        _applyResolvedPosition(p);
        _resumeTargetPosition = null;
        return;
      }
    }

    _applyResolvedPosition(target);
    _resumeTargetPosition = null;
  }

  /// After play() on a stream, wait until duration/position is available before seeking.
  Future<void> _waitForResumeReady(Audiobook book, AudiobookChapter chapter) async {
    if (_isTorrentChapter(book, chapter)) {
      await _waitForStreamPrime(
        minWait: const Duration(milliseconds: 200),
        timeout: const Duration(seconds: 10),
      );
      return;
    }

    final ready = Completer<void>();
    late StreamSubscription<Duration> durSub;
    durSub = _player.stream.duration.listen((d) {
      if (d > Duration.zero && !ready.isCompleted) {
        ready.complete();
      }
    });
    await ready.future.timeout(const Duration(seconds: 12), onTimeout: () {});
    await durSub.cancel();
  }

  /// Seek repeatedly until mpv settles near [target] (HTTP streams).
  Future<void> _settleResumePosition(Duration target) async {
    _resumeTargetPosition = target;
    _ignoreProgressPersistenceUntil =
        DateTime.now().add(const Duration(seconds: 15));

    for (var attempt = 0; attempt < 6; attempt++) {
      await _player.seek(target);
      await Future.delayed(Duration(milliseconds: 250 + attempt * 100));
      final p = _player.state.position;
      final delta = (p - target).abs();
      if (p > Duration.zero &&
          (delta < const Duration(seconds: 4) ||
              p >= target - const Duration(seconds: 2))) {
        _applyResolvedPosition(p);
        _resumeTargetPosition = null;
        return;
      }
    }

    _applyResolvedPosition(target);
    _resumeTargetPosition = null;
  }

  /// After play() on a torrent stream, wait until the loopback URL is primed.
  Future<void> _waitForStreamPrime({
    Duration minWait = const Duration(milliseconds: 150),
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (minWait > Duration.zero) {
      await Future.delayed(minWait);
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final st = _player.state;
      if (st.position > Duration.zero || st.duration > Duration.zero) return;
      if (st.playing && !st.buffering) return;
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _ensureMpvAudiobookTuning({required bool torrentBacked}) async {
    if (_mpvAudiobookTuned) return;
    if (_player.platform is! NativePlayer) return;
    final p = _player.platform as NativePlayer;
    await p.setProperty('hr-seek', 'yes');
    await p.setProperty('cache', 'yes');
    await p.setProperty('demuxer-max-bytes', '50000000');
    await p.setProperty('demuxer-max-back-bytes', '50000000');
    await p.setProperty('demuxer-readahead-secs', torrentBacked ? '5' : '30');
    if (torrentBacked) {
      await p.setProperty('force-seekable', 'yes');
      try {
        await p.setProperty('demuxer-seekable-cache', 'yes');
        await p.setProperty('cache-secs', '8');
      } catch (_) {}
    }
    _mpvAudiobookTuned = true;
  }

  void _startProgressTicker() {
    _progressTicker ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      _pollPlayerClock();
    });
  }

  void _stopProgressTicker() {
    if (!isPlaying.value) {
      _progressTicker?.cancel();
      _progressTicker = null;
    }
  }

  void _markWallClock({Duration base = Duration.zero}) {
    _wallClockBase = base;
    _wallClockStartedAt = DateTime.now();
  }

  void _resetWallClock({Duration base = Duration.zero}) {
    _wallClockBase = base;
    _wallClockStartedAt = null;
  }

  /// Torrent loopback streams often skip stream events; poll [Player.state] directly.
  void _pollPlayerClock() {
    if (isPreparingPlayback.value) return;
    final st = _player.state;
    final p = st.position;
    final d = st.duration;
    var changed = false;

    if (p > Duration.zero) {
      if (_acceptPlayerPosition(p) && p != position.value) {
        position.value = p;
        _wallClockBase = p;
        changed = true;
      }
    } else if (isPlaying.value && _wallClockStartedAt != null) {
      var wall =
          _wallClockBase + DateTime.now().difference(_wallClockStartedAt!);
      if (d > Duration.zero && wall > d) wall = d;
      if (wall > position.value || _streamClockUnreliable) {
        position.value = wall;
        changed = true;
      }
    }
    if (d > Duration.zero && d != duration.value) {
      duration.value = d;
      changed = true;
      _syncMediaItem();
    }

    if (changed) {
      _updateSystemState();
      _scheduleDebouncedProgressSave();
    }
  }

  void _publishLoadingState() {
    if (_handler == null || currentBook.value == null) return;
    _syncChapterQueue();
    _syncMediaItem();
    _handler!.updateState(PlaybackState(
      controls: const [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.loading,
      playing: false,
      updatePosition: position.value,
      bufferedPosition: Duration.zero,
      speed: 1.0,
      queueIndex: currentChapterIndex.value,
    ));
  }

  void _syncMediaItem() {
    final handler = _handler;
    final item = _buildCurrentMediaItem();
    if (handler == null || item == null) return;
    unawaited(handler.updateMediaItem(item));
  }

  void _updateSystemState() {
    if (_handler == null || currentBook.value == null) return;

    final playing = isPlaying.value;
    final processingState = playing && isBuffering.value
        ? AudioProcessingState.buffering
        : AudioProcessingState.ready;
    
    _handler!.updateState(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        isPlaying.value ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: processingState,
      playing: playing,
      updatePosition: position.value,
      bufferedPosition: _player.state.buffer,
      speed: _player.state.rate,
      queueIndex: currentChapterIndex.value,
    ));
  }

  Future<void> loadBook(Audiobook book, List<AudiobookChapter> chapters, {int initialChapter = 0, Duration? resumePosition}) async {
    final previous = currentBook.value;
    if (previous != null && previous.audioBookId != book.audioBookId) {
      _releaseTorrentForBook(previous);
    }
    _cachedArtUri = null;

    final chapterCount = chapters.length;
    final idx = chapterCount == 0
        ? 0
        : initialChapter.clamp(0, chapterCount - 1);
    if (idx != initialChapter) {
      debugPrint(
        'AudiobookPlayerService: chapter index $initialChapter out of range '
        '($chapterCount chapters) — using $idx',
      );
    }

    _isResuming = initialChapter > 0 ||
        (resumePosition != null && resumePosition > Duration.zero);
    _resumeTargetPosition = null;
    _streamClockUnreliable = false;
    _positionFloorMs = 0;
    _lastCorrectiveSeekAt = null;
    _resetPlaybackUiState();
    _wallClockBase =
        _isResuming && resumePosition != null ? resumePosition : Duration.zero;

    currentBook.value = book;
    _currentChapters = chapters;
    currentChapterIndex.value = idx;
    _resetWallClock(base: _wallClockBase);

    if (!_isResuming) {
      _ignoreProgressPersistenceUntil =
          DateTime.now().add(const Duration(seconds: 2));
    } else if (resumePosition != null && resumePosition > Duration.zero) {
      position.value = resumePosition;
      _positionFloorMs = resumePosition.inMilliseconds;
    }

    _handler?.setPlayerType(AudioPlayerType.audiobook, _player);

    _publishLoadingState();

    final torrentBacked = book.source == 'magnet' || book.source == 'audiobookbay';
    final chapter = chapters[idx];
    final torrentChapter = _isTorrentChapter(book, chapter);
    if (torrentBacked) {
      _streamClockUnreliable = true;
    }

    final needsSeek =
        resumePosition != null && resumePosition > Duration.zero;
    if (needsSeek) {
      _streamClockUnreliable = true;
    }

    final prepResults = await Future.wait([
      _ensureMpvAudiobookTuning(torrentBacked: torrentBacked),
      _mediaForChapter(book, chapter),
    ]);
    final media = prepResults[1] as Media;

    if (needsSeek &&
        resumePosition != null &&
        _player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      try {
        await native.setProperty('start', '${resumePosition.inSeconds}');
      } catch (_) {}
    }

    var resumeAlreadyPlaying = false;
    Duration? preparingPositionHint;

    if (torrentChapter && needsSeek && resumePosition != null) {
      debugPrint(
        'AudiobookPlayerService: Fast torrent resume chapter $idx at $resumePosition',
      );
      await _player.open(media, play: false);
      await _waitForTorrentDuration(
        timeout: const Duration(seconds: 5),
      );
      if (resumePosition > const Duration(seconds: 2)) {
        await _quickTorrentSeek(resumePosition);
      } else {
        position.value = resumePosition;
        _positionFloorMs = resumePosition.inMilliseconds;
      }
      await _player.play();
      resumeAlreadyPlaying = true;
      preparingPositionHint = resumePosition;
    } else if (torrentChapter) {
      await _player.open(media, play: true);
      resumeAlreadyPlaying = true;
    } else {
      await _player.open(media, play: false);
      if (needsSeek && resumePosition != null) {
        debugPrint(
          'AudiobookPlayerService: Resuming chapter $idx at $resumePosition',
        );
        await _player.play();
        resumeAlreadyPlaying = true;
        await _waitForResumeReady(book, chapter);
        await _settleResumePosition(resumePosition);
        preparingPositionHint = position.value > Duration.zero
            ? position.value
            : resumePosition;
      }
    }

    if (!resumeAlreadyPlaying) {
      await _playThroughHandler();
    }

    await _waitUntilPlaybackReady(
      book: book,
      chapter: chapter,
      timeout: torrentChapter
          ? const Duration(seconds: 15)
          : const Duration(seconds: 12),
      relaxedBuffer: torrentChapter,
    );
    _isResuming = false;
    await _applyPlaybackRate(force: true);
    _finishPreparingPlayback(positionHint: preparingPositionHint);
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 600),
        () => _applyPlaybackRate(force: true),
      ),
    );
  }

  Future<Media> _mediaForChapter(
    Audiobook book,
    AudiobookChapter ch,
  ) async {
    final torrentBacked = _isTorrentChapter(book, ch);
    if (!torrentBacked) {
      final headers = ch.headers ?? const <String, String>{};
      return Media(
        ch.url,
        httpHeaders: headers,
      );
    }

    final magnet = book.magnetLink!;
    final torrent = TorrentStreamService();
    final started = await torrent.start();
    if (!started) {
      throw Exception('Torrent engine failed to start');
    }
    final url = await torrent.streamAudiobookFile(
      magnet,
      ch.torrentFileIndex!,
      allowNonStreamable: true,
      stopSiblingStreams: false,
      fileNameHint: ch.title,
    );
    if (url == null || url.isEmpty) {
      throw Exception('Could not stream torrent file: ${ch.title}');
    }
    final merged = Map<String, String>.from(magnetStreamHttpHeaders);
    if (ch.headers != null) {
      merged.addAll(ch.headers!);
    }
    return Media(url, httpHeaders: merged);
  }

  bool _isTorrentChapter(Audiobook book, AudiobookChapter ch) {
    final magnet = book.magnetLink;
    return (book.source == 'magnet' || book.source == 'audiobookbay') &&
        magnet != null &&
        magnet.trim().isNotEmpty &&
        ch.torrentFileIndex != null;
  }

  void playOrPause() {
    if (isPreparingPlayback.value) {
      isPreparingPlayback.value = false;
      final st = _player.state;
      isPlaying.value = st.playing;
      isBuffering.value = st.buffering;
    }
    final handler = _handler;
    if (handler != null) {
      if (_player.state.playing || isPlaying.value) {
        unawaited(handler.pause());
      } else {
        unawaited(handler.play());
      }
      return;
    }
    _player.playOrPause();
  }
  void seek(Duration p) => unawaited(seekTo(p));

  Future<void> ensurePlaybackRateLoaded() async {
    _playbackRateLoadFuture ??= _loadPlaybackRateFromPrefs();
    await _playbackRateLoadFuture;
  }

  Future<void> _loadPlaybackRateFromPrefs() async {
    if (_playbackRateLoaded) return;
    final speed = await SettingsService().getPlaybackSpeed();
    playbackRate.value = speed;
    _playbackRateLoaded = true;
    await _player.setRate(speed);
  }

  Future<void> setRate(double r) async {
    await ensurePlaybackRateLoaded();
    final speed = r.clamp(0.5, 3.0);
    playbackRate.value = speed;
    await _applyPlaybackRate(force: true);
    await SettingsService().setPlaybackSpeed(speed);
    _updateSystemState();
  }

  Future<void> _applyPlaybackRate({bool force = false}) async {
    await ensurePlaybackRateLoaded();
    final speed = playbackRate.value;
    if (!force && (_player.state.rate - speed).abs() <= 0.01) return;
    await _player.setRate(speed);
    if (_player.platform is NativePlayer) {
      try {
        await (_player.platform as NativePlayer)
            .setProperty('speed', speed.toStringAsFixed(2));
      } catch (_) {}
    }
  }

  Future<void> seekTo(Duration target) async {
    var resolved = target;
    if (resolved.isNegative) resolved = Duration.zero;
    final d = duration.value;
    if (d > Duration.zero && resolved > d) resolved = d;

    _positionFloorMs = resolved.inMilliseconds;
    _resumeTargetPosition = null;
    _lastCorrectiveSeekAt = null;
    _wallClockBase = resolved;
    position.value = resolved;
    if (isPlaying.value) {
      _markWallClock(base: resolved);
    } else {
      _resetWallClock(base: resolved);
    }

    await _player.seek(resolved);
    _updateSystemState();
    _scheduleDebouncedProgressSave();
  }

  void skipToNextChapter() {
    final nextIdx = currentChapterIndex.value + 1;
    if (nextIdx < _currentChapters.length) {
      unawaited(changeChapter(nextIdx));
    }
  }

  void skipToPreviousChapter() {
    final prevIdx = currentChapterIndex.value - 1;
    if (prevIdx >= 0) {
      unawaited(changeChapter(prevIdx));
    }
  }

  Future<void> stop() async {
    final book = currentBook.value;
    await _player.stop();
    if (book != null) {
      _releaseTorrentForBook(book);
    }
    isPlaying.value = false;
    isBuffering.value = false;
    isPreparingPlayback.value = false;
    _updateSystemState();
  }

  Future<void> changeChapter(int index) async {
    if (index < 0 || index >= _currentChapters.length) return;
    currentChapterIndex.value = index;
    final book = currentBook.value;
    if (book == null) return;
    _positionFloorMs = 0;
    _resumeTargetPosition = null;
    _lastCorrectiveSeekAt = null;
    _resetPlaybackUiState();
    _syncMediaItem();
    _syncChapterQueue();
    _ignoreProgressPersistenceUntil =
        DateTime.now().add(const Duration(milliseconds: 1200));
    try {
      final media = await _mediaForChapter(book, _currentChapters[index]);
      await _player.open(media, play: false);
      await _playThroughHandler();
      await _waitUntilPlaybackReady(
        book: book,
        chapter: _currentChapters[index],
        timeout: const Duration(seconds: 30),
      );
      await _applyPlaybackRate(force: true);
      _finishPreparingPlayback();
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          () => _applyPlaybackRate(force: true),
        ),
      );
    } catch (e, st) {
      isPreparingPlayback.value = false;
      debugPrint('AudiobookPlayerService.changeChapter: $e\n$st');
    }
  }

  int _playbackPositionMs() {
    if (isPreparingPlayback.value) {
      return _wallClockBase.inMilliseconds;
    }

    var bestMs = position.value.inMilliseconds;
    final fromPlayer = _player.state.position;
    if (fromPlayer > Duration.zero) {
      bestMs = fromPlayer.inMilliseconds > bestMs
          ? fromPlayer.inMilliseconds
          : bestMs;
    }
    if (isPlaying.value && _wallClockStartedAt != null) {
      var wall =
          _wallClockBase + DateTime.now().difference(_wallClockStartedAt!);
      final d = duration.value;
      if (d > Duration.zero && wall > d) wall = d;
      if (wall.inMilliseconds > bestMs) bestMs = wall.inMilliseconds;
    }
    if (bestMs < 0) return 0;
    return bestMs;
  }

  /// Chapter index clamped to the loaded chapter list + live player clock (for bookmarks).
  Future<({int chapterIndex, int positionMs})> captureBookmarkSnapshot() async {
    final n = _currentChapters.length;
    final idx = n == 0 ? 0 : currentChapterIndex.value.clamp(0, n - 1);
    var ms = _playbackPositionMs();
    if (ms < 0) ms = 0;

    final bid = currentBook.value?.audioBookId;
    if (bid != null && ms < 500) {
      final hist = await getHistory();
      for (final h in hist) {
        final b = h['book'];
        if (b is! Map || '${b['audioBookId']}' != bid) continue;
        final pCh = (h['chapterIndex'] as num?)?.toInt() ?? 0;
        final pMs = (h['positionMs'] as num?)?.toInt() ?? 0;
        if (idx == pCh && pMs > 60_000) {
          ms = pMs;
        }
        break;
      }
    }
    return (chapterIndex: idx, positionMs: ms);
  }

  // --- Persistence (History) ---

  Future<void> _saveProgress({bool force = false}) async {
    if (currentBook.value == null) return;
    if (!force) {
      if (_isResuming) return;
      final until = _ignoreProgressPersistenceUntil;
      if (until != null && DateTime.now().isBefore(until)) return;
    }
    final prefs = await SharedPreferences.getInstance();

    List<String> historyStrings =
        prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
    List<Map<String, dynamic>> history = historyStrings
        .map((s) => json.decode(s) as Map<String, dynamic>)
        .toList();

    final bid = currentBook.value!.audioBookId;
    Map<String, dynamic>? prevSame;
    for (final item in history) {
      final b = item['book'];
      if (b is Map && '${b['audioBookId']}' == bid) {
        prevSame = item;
        break;
      }
    }

    int outCh = currentChapterIndex.value;
    int outMs = _playbackPositionMs();
    if (outMs < 0) outMs = 0;

    // Torrent / loopback streams sometimes leave the clock at 0 even while audio
    // is playing — carry forward the last saved offset for the same chapter.
    if (prevSame != null) {
      final pCh = (prevSame['chapterIndex'] as num?)?.toInt() ?? 0;
      final pMs = (prevSame['positionMs'] as num?)?.toInt() ?? 0;
      if (outCh == pCh) {
        if (outMs < 500 && pMs > 1_000) {
          outMs = pMs;
        } else if (outMs + 15_000 < pMs) {
          // Honor bookmark resume / backward scrub below saved history.
          if (_positionFloorMs <= 0 || outMs < _positionFloorMs - 5_000) {
            outMs = pMs;
          }
        }
      }
    }

    final bookData = {
      'book': currentBook.value!.toJson(),
      'chapterIndex': outCh,
      'positionMs': outMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    history.removeWhere((item) {
      final b = item['book'];
      if (b is! Map) return false;
      return '${b['audioBookId']}' == bid;
    });
    history.insert(0, bookData);

    if (history.length > 10) history = history.sublist(0, 10);

    await prefs.setStringList(
      AudiobookPrefsKeys.history,
      history.map((e) => json.encode(e)).toList(),
    );
    PlaytorrioCloudSyncService.instance.scheduleDebouncedSettingsPush();
    SettingsService.notifyAudiobookPrefsChanged();
    AndroidAutoBrowse.invalidateCache();
  }

  Future<void> saveManualProgress() async {
    await _saveProgress(force: true);
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
    return history.map((s) => json.decode(s) as Map<String, dynamic>).toList();
  }

  Future<void> resumeFromAndroidAuto(String audioBookId) async {
    final history = await getHistory();
    for (final progress in history) {
      final rawBook = progress['book'];
      if (rawBook is! Map) continue;
      if ('${rawBook['audioBookId']}' != audioBookId) continue;

      final book = Audiobook.fromJson(Map<String, dynamic>.from(rawBook));
      final ciRaw = progress['chapterIndex'];
      final chapterIndex = ciRaw is int
          ? ciRaw
          : (ciRaw is num ? ciRaw.toInt() : int.tryParse('$ciRaw') ?? 0);
      final pmRaw = progress['positionMs'];
      final positionMs = pmRaw is int
          ? pmRaw
          : (pmRaw is num ? pmRaw.toInt() : int.tryParse('$pmRaw') ?? 0);

      final prepared = await AudiobookService().prepareAudiobookPlayback(
        book,
        warmChapterIndex: chapterIndex,
      );
      await loadBook(
        prepared.book,
        prepared.chapters,
        initialChapter: chapterIndex,
        resumePosition: Duration(milliseconds: positionMs),
      );
      return;
    }
    debugPrint(
      'AudiobookPlayerService: no history entry for Android Auto $audioBookId',
    );
  }

  Future<void> playChapterFromAndroidAuto(String audioBookId, int index) async {
    final book = currentBook.value;
    if (book != null && book.audioBookId == audioBookId) {
      await changeChapter(index);
      return;
    }

    final history = await getHistory();
    for (final progress in history) {
      final rawBook = progress['book'];
      if (rawBook is! Map) continue;
      if ('${rawBook['audioBookId']}' != audioBookId) continue;

      final histBook = Audiobook.fromJson(Map<String, dynamic>.from(rawBook));
      final prepared =
          await AudiobookService().prepareAudiobookPlayback(histBook);
      await loadBook(
        prepared.book,
        prepared.chapters,
        initialChapter: index,
      );
      return;
    }
    debugPrint(
      'AudiobookPlayerService: cannot play chapter for unknown book $audioBookId',
    );
  }

  void _syncChapterQueue() {
    final handler = _handler;
    final book = currentBook.value;
    if (handler == null || book == null || _currentChapters.isEmpty) return;

    final artUri = _resolveArtUri(book);
    final items = List<MediaItem>.generate(_currentChapters.length, (i) {
      final chapter = _currentChapters[i];
      return MediaItem(
        id: AndroidAutoIds.chapter(book.audioBookId, i),
        album: book.title,
        title:
            chapter.title.isEmpty ? 'Chapter ${i + 1}' : chapter.title,
        artist: 'Stories',
        artUri: artUri,
      );
    });
    handler.queue.add(items);
  }

  Future<void> removeFromHistory(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyStrings = prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
    historyStrings.removeWhere((s) {
      final data = json.decode(s);
      return data['book']['audioBookId'] == audioBookId;
    });
    await prefs.setStringList(AudiobookPrefsKeys.history, historyStrings);
    PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
    SettingsService.notifyAudiobookPrefsChanged();
    AndroidAutoBrowse.invalidateCache();
  }

  // --- Liked Books ---

  Future<List<Audiobook>> getLikedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
    return liked.map((s) => Audiobook.fromJson(json.decode(s))).toList();
  }

  Future<bool> isBookLiked(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
    return liked.any((s) => json.decode(s)['audioBookId'] == audioBookId);
  }

  Future<void> toggleLikeBook(Audiobook book) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> likedStrings = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
    
    final index = likedStrings.indexWhere((s) => json.decode(s)['audioBookId'] == book.audioBookId);
    
    if (index >= 0) {
      likedStrings.removeAt(index);
    } else {
      likedStrings.add(json.encode(book.toJson()));
    }
    
    await prefs.setStringList(AudiobookPrefsKeys.liked, likedStrings);
    PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
    SettingsService.notifyAudiobookPrefsChanged();
  }

  // --- Bookmarks (synced via SettingsService → cloud when logged in) ---

  Future<void> _touchBookmarksRevision() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AudiobookPrefsKeys.bookmarksUpdatedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [];
    final out = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        final decoded = json.decode(s);
        if (decoded is Map) {
          out.add(Map<String, dynamic>.from(decoded as Map));
        }
      } catch (_) {}
    }
    return out;
  }

  Future<Set<String>> getBookmarkedAudioBookIds() async {
    final prefs = await SharedPreferences.getInstance();
    final strings = prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [];
    final ids = <String>{};
    for (final s in strings) {
      try {
        final m = json.decode(s) as Map<String, dynamic>;
        final b = m['book'];
        if (b is Map && b['audioBookId'] != null) {
          ids.add('${b['audioBookId']}');
        }
      } catch (_) {}
    }
    return ids;
  }

  Future<bool> isBookmarked(String audioBookId) async {
    final ids = await getBookmarkedAudioBookIds();
    return ids.contains(audioBookId);
  }

  Future<void> removeBookmark(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    var strings = prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [];
    strings.removeWhere((s) {
      try {
        final d = json.decode(s) as Map<String, dynamic>;
        final b = d['book'];
        if (b is Map) return '${b['audioBookId']}' == audioBookId;
      } catch (_) {}
      return false;
    });
    await prefs.setStringList(AudiobookPrefsKeys.bookmarks, strings);
    await _touchBookmarksRevision();
    PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
    SettingsService.notifyAudiobookPrefsChanged();
  }

  /// Replace or insert bookmark for [book] (most recent first).
  Future<void> upsertBookmarkWithProgress(
    Audiobook book, {
    required int chapterIndex,
    required int positionMs,
    bool placeholderOnly = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var strings = prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [];
    strings.removeWhere((s) {
      try {
        final d = json.decode(s) as Map<String, dynamic>;
        final b = d['book'];
        if (b is Map) return '${b['audioBookId']}' == book.audioBookId;
      } catch (_) {}
      return false;
    });
    strings.insert(
      0,
      json.encode({
        'book': book.toJson(),
        'chapterIndex': chapterIndex,
        'positionMs': positionMs < 0 ? 0 : positionMs,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        if (placeholderOnly) 'placeholderBookmark': true,
      }),
    );
    await prefs.setStringList(AudiobookPrefsKeys.bookmarks, strings);
    await _touchBookmarksRevision();
    PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
    SettingsService.notifyAudiobookPrefsChanged();
  }

  /// From grid: add bookmark without a saved position, or remove if already present.
  Future<void> toggleBookmarkGrid(Audiobook book) async {
    if (await isBookmarked(book.audioBookId)) {
      await removeBookmark(book.audioBookId);
    } else {
      await upsertBookmarkWithProgress(
        book,
        chapterIndex: 0,
        positionMs: 0,
        placeholderOnly: true,
      );
    }
  }

  void dispose() {
    _progressSaveDebounce?.cancel();
    for (var s in _subscriptions) { s.cancel(); }
    _player.dispose();
  }
}
