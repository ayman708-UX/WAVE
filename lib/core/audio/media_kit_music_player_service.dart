import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../../main.dart' show scaffoldMessengerKey;
import '../../features/audiobooks/services/torrent_stream_service.dart';
import '../api/debrid_api.dart';
import '../api/deezer_api_client.dart';
import '../api/lastfm_api_client.dart';
import '../api/models/deezer_track.dart';
import '../api/models/player_state.dart';
import '../api/models/queue_state.dart';
import '../auth/supabase_audiobook_sync.dart';
import '../storage/hive_boxes.dart';
import '../models/audiobook.dart';
import '../downloads/local_download_matcher.dart';
import '../utils/app_logger.dart';
import '../utils/youtube_stream_http.dart';
import 'local_proxy.dart';
import 'music_player_service.dart';
import '../api/octave_music_service.dart';
import '../storage/settings_providers.dart';
import 'youtube_stream_resolver.dart';
import 'youtube_rate_limit_guard.dart';

/// Real audio backend powered by `media_kit` (libmpv).
/// Uses a dual-player architecture to support true overlapping crossfades.
class MediaKitMusicPlayerService extends BaseAudioHandler
    with SeekHandler
    implements MusicPlayerService {
  MediaKitMusicPlayerService({YoutubeStreamResolver? resolver})
    : _resolver = resolver ?? YoutubeStreamResolver() {
    _initPlayer(_playerA);
    _initPlayer(_playerB);
    _loadInitialSettings();
  }

  final mk.Player _playerA = mk.Player();
  final mk.Player _playerB = mk.Player();
  late mk.Player _activePlayer = _playerA;
  late mk.Player _inactivePlayer = _playerB;

  final YoutubeStreamResolver _resolver;

  final StreamController<PlayerState> _playerCtrl =
      StreamController<PlayerState>.broadcast();
  final StreamController<QueueState> _queueCtrl =
      StreamController<QueueState>.broadcast();

  PlayerState _state = const PlayerState();
  QueueState _queue = const QueueState();
  bool _loading = false;
  int _playbackOp = 0;

  Timer? _crossfadeTimer;
  Timer? _loadingWatchdog;
  Object? _crossfadeTag;
  bool _isCrossfading = false;
  bool _autoCrossfadeTriggered = false;
  bool _audioResetting = false;
  int? _lastAutoRecoveryTrackId;
  List<double> _equalizerBandsDb = const <double>[0, 0, 0, 0, 0];
  int _lastAudiobookSaveTime = 0;

  int _nextPlaybackOp() => ++_playbackOp;

  bool _isStalePlaybackOp(int op) => op != _playbackOp;

  void _cancelTransitions() {
    _crossfadeTimer?.cancel();
    _crossfadeTag = Object();
    _isCrossfading = false;
    _autoCrossfadeTriggered = false;
  }

  void _cancelLoadingWatchdog() {
    _loadingWatchdog?.cancel();
    _loadingWatchdog = null;
  }

  void _setLoadingForOp(int op, bool value) {
    if (!_isStalePlaybackOp(op)) {
      _loading = value;
      if (!value) _cancelLoadingWatchdog();
    }
  }

  void _startLoadingWatchdog(int op, DeezerTrack track) {
    _cancelLoadingWatchdog();
    _loadingWatchdog = Timer(const Duration(seconds: 45), () {
      if (_isStalePlaybackOp(op) || !_loading) return;
      appLogger.e('Playback watchdog fired for ${track.title}');
      unawaited(
        _recoverAudioPipeline(
          track,
          reason: 'playback watchdog timed out',
          retryCurrentTrack: true,
        ),
      );
    });
  }

  Future<void> _safeStopPlayer(mk.Player player) async {
    try {
      await player.stop().timeout(const Duration(seconds: 4));
    } catch (e) {
      appLogger.w('Player stop timeout/error during reset: $e');
    }
  }

  Future<void> _resetAudioPipeline({required String reason}) async {
    if (_audioResetting) return;
    _audioResetting = true;
    appLogger.w('Resetting audio pipeline: $reason');
    _cancelTransitions();
    _cancelLoadingWatchdog();
    _loading = false;
    await _safeStopPlayer(_playerA);
    await _safeStopPlayer(_playerB);
    try {
      await LocalProxy.restart();
    } catch (e) {
      appLogger.w('LocalProxy restart failed during audio reset: $e');
    } finally {
      _audioResetting = false;
    }
  }

  Future<void> _recoverAudioPipeline(
    DeezerTrack? track, {
    required String reason,
    bool retryCurrentTrack = false,
  }) async {
    final retryTrack = track ?? _queue.current;
    final canRetry =
        retryCurrentTrack &&
        retryTrack != null &&
        _queue.current?.id == retryTrack.id &&
        _lastAutoRecoveryTrackId != retryTrack.id;

    _nextPlaybackOp();
    await _resetAudioPipeline(reason: reason);

    if (canRetry) {
      _lastAutoRecoveryTrackId = retryTrack.id;
      final retryOp = _nextPlaybackOp();
      await _loadAndPlay(retryTrack, _activePlayer, retryOp);
      return;
    }

    _emitPlayer(
      _state.copyWith(
        status: PlaybackStatus.idle,
        position: Duration.zero,
        errorMessage: 'Audio engine reset. Press play again.',
      ),
    );
  }

  void _initPlayer(mk.Player player) {
    player.stream.playing.listen((v) => _onPlayingChanged(player, v));
    player.stream.buffering.listen((v) => _onBufferingChanged(player, v));
    player.stream.completed.listen((v) => _onCompleted(player, v));
    player.stream.position.listen((v) => _onPositionChanged(player, v));
    player.stream.duration.listen((v) => _onDurationChanged(player, v));
    player.stream.buffer.listen((v) => _onBufferChanged(player, v));
    player.stream.error.listen((v) => _onError(player, v));
  }

  void _loadInitialSettings() {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.settings);
      final raw = box.get('app_settings');
      if (raw is String && raw.isNotEmpty) {
        final json = jsonDecode(raw);
        if (json is Map) {
          final secs = (json['crossfadeSeconds'] as num?)?.toInt() ?? 0;
          _state = _state.copyWith(crossfadeSeconds: secs);
          final bandsRaw = json['equalizerBandsDb'];
          if (bandsRaw is List) {
            final List<double> bands = bandsRaw
                .whereType<num>()
                .map((n) => n.toDouble())
                .toList();
            if (bands.length == 5) {
              _equalizerBandsDb = bands;
            }
          }
        }
      } else if (raw is Map) {
        final secs = (raw['crossfadeSeconds'] as num?)?.toInt() ?? 0;
        _state = _state.copyWith(crossfadeSeconds: secs);
        final bandsRaw = raw['equalizerBandsDb'];
        if (bandsRaw is List) {
          final List<double> bands = bandsRaw
              .whereType<num>()
              .map((n) => n.toDouble())
              .toList();
          if (bands.length == 5) {
            _equalizerBandsDb = bands;
          }
        }
      }
      // Apply loaded equalizer settings
      _applyEqualizerToPlayer(_playerA);
      _applyEqualizerToPlayer(_playerB);
    } catch (e) {
      appLogger.w('Failed to load initial settings: $e');
    }
  }

  Future<void> _applyEqualizerToPlayer(mk.Player player) async {
    final isFlat = _equalizerBandsDb.every((db) => db == 0.0);
    final filter = isFlat
        ? ''
        : 'lavfi=[equalizer=f=60:t=q:w=1:g=${_equalizerBandsDb[0]},'
              'equalizer=f=230:t=q:w=1:g=${_equalizerBandsDb[1]},'
              'equalizer=f=910:t=q:w=1:g=${_equalizerBandsDb[2]},'
              'equalizer=f=4000:t=q:w=1:g=${_equalizerBandsDb[3]},'
              'equalizer=f=14000:t=q:w=1:g=${_equalizerBandsDb[4]}]';
    try {
      if (player.platform is mk.NativePlayer) {
        await (player.platform as mk.NativePlayer).setProperty('af', filter);
      }
    } catch (e) {
      appLogger.e('Failed to apply equalizer filter to player: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Streams ------------------------------------------------------------------

  @override
  Stream<PlayerState> get playerStateStream => _playerCtrl.stream;

  @override
  Stream<QueueState> get queueStateStream => _queueCtrl.stream;

  @override
  PlayerState get playerState => _state;

  @override
  QueueState get queueState => _queue;

  void _emitPlayer(PlayerState next) {
    _state = next;
    _playerCtrl.add(next);
    _syncAudioService();
  }

  void _syncAudioService() {
    final isPlaying = _state.status == PlaybackStatus.playing;
    final isBuffering =
        _state.status == PlaybackStatus.buffering ||
        _state.status == PlaybackStatus.loading;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : (_state.status == PlaybackStatus.idle
                  ? AudioProcessingState.idle
                  : AudioProcessingState.ready),
        playing: isPlaying,
        updatePosition: _state.position,
        bufferedPosition: _state.buffered,
        speed: 1.0,
      ),
    );

    if (_state.currentTrack != null) {
      final t = _state.currentTrack!;
      final oldMediaItem = mediaItem.value;
      if (oldMediaItem?.id != t.id.toString()) {
        mediaItem.add(
          MediaItem(
            id: t.id.toString(),
            title: t.title,
            artist: t.artist?.name,
            album: t.album?.title,
            duration: t.duration != null
                ? Duration(seconds: t.duration!)
                : _state.duration,
            artUri: t.album?.coverMedium != null
                ? Uri.parse(t.album!.coverMedium!)
                : null,
          ),
        );
      }
    }
  }

  void _emitQueue(QueueState next) {
    _queue = next;
    _queueCtrl.add(next);
  }

  // ---------------------------------------------------------------------------
  // media_kit -> PlayerState bridges -----------------------------------------

  void _onPlayingChanged(mk.Player p, bool playing) {
    if (p != _activePlayer || _loading) return;
    _emitPlayer(
      _state.copyWith(
        status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      ),
    );
  }

  void _onBufferingChanged(mk.Player p, bool buffering) {
    if (p != _activePlayer || _loading) return;
    if (buffering) {
      _emitPlayer(_state.copyWith(status: PlaybackStatus.buffering));
    } else if (p.state.playing) {
      _emitPlayer(_state.copyWith(status: PlaybackStatus.playing));
    }
  }

  void _onCompleted(mk.Player p, bool completed) {
    if (p != _activePlayer) return;
    if (completed && !_isCrossfading && !_autoCrossfadeTriggered) {
      if (_queue.isRelatedMode && _queue.upcoming.length <= 1) {
        _fetchMoreRelatedTracks();
      }
      unawaited(skipNext());
    }
  }

  Future<void> _fetchMoreRelatedTracks() async {
    if (_queue.upcoming.isEmpty && _queue.current != null) {
      // Current track is ending, fetch related for it
      final track = _queue.current!;
      final artistName = track.artist?.name ?? '';
      final trackName = track.title;
      if (artistName.isEmpty) return;

      try {
        final similar = await LastfmApiClient().getSimilarTracks(
          trackName,
          artistName,
        );
        if (similar.isNotEmpty) {
          final deezerApi = DeezerApiClient();
          final newTracks = <DeezerTrack>[];
          for (final t in similar) {
            final tName = t['name'] ?? '';
            final tArtist = t['artist'] ?? '';
            if (tName.isEmpty || tArtist.isEmpty) continue;
            try {
              final res = await deezerApi.searchTracks(
                'artist:"$tArtist" track:"$tName"',
              );
              if (res.isNotEmpty) {
                // Avoid adding tracks already in history or upcoming
                final exists = [
                  ..._queue.history,
                  ..._queue.upcoming,
                  _queue.current,
                ].any((e) => e?.id == res.first.id);
                if (!exists) {
                  newTracks.add(res.first);
                }
              }
            } catch (_) {}
            if (newTracks.length >= 10) break;
          }
          if (newTracks.isNotEmpty) {
            _emitQueue(
              _queue.copyWith(upcoming: [..._queue.upcoming, ...newTracks]),
            );
          }
        }
      } catch (e) {
        appLogger.e('Failed to fetch more related tracks: $e');
      }
    }
  }

  void _onPositionChanged(mk.Player p, Duration pos) {
    if (p != _activePlayer) return;
    if (pos == _state.position) return;
    _emitPlayer(_state.copyWith(position: pos));

    final currentTrack = _queue.current;
    if (currentTrack != null && currentTrack.link == 'wave://audiobook') {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAudiobookSaveTime > 5000 && currentTrack.preview != null) {
        _lastAudiobookSaveTime = now;
        try {
          final payload = jsonDecode(currentTrack.preview!);
          final book = Audiobook.fromJson(payload['audiobook']);
          final chapterIndex = payload['chapterIndex'] as int;
          
          final box = Hive.box<dynamic>(HiveBoxes.audiobookProgress);
          final progress = AudiobookProgress(
            audiobook: book,
            chapterIndex: chapterIndex,
            positionSeconds: pos.inSeconds,
            updatedAt: now,
          );
          box.put(
            book.uuid,
            jsonDecode(jsonEncode(progress.toJson())),
          );
          SupabaseAudiobookSync().syncProgress(progress);
        } catch (_) {}
      }
    }

    // Check for automatic crossfade
    if (!_isCrossfading &&
        !_autoCrossfadeTriggered &&
        _state.duration > Duration.zero &&
        _state.crossfadeSeconds > 0) {
      final remaining = _state.duration - pos;
      if (remaining <= Duration(seconds: _state.crossfadeSeconds)) {
        if (_queue.upcoming.isNotEmpty) {
          _autoCrossfadeTriggered = true;
          _triggerAutoCrossfade();
        }
      }
    }
  }

  void _triggerAutoCrossfade() async {
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
    await _startPlayback(next, autoCrossfade: true);
  }

  void _onDurationChanged(mk.Player p, Duration d) {
    if (p != _activePlayer) return;
    if (d == Duration.zero) return;
    _emitPlayer(_state.copyWith(duration: d));
  }

  void _onBufferChanged(mk.Player p, Duration b) {
    if (p != _activePlayer) return;
    _emitPlayer(_state.copyWith(buffered: b));
  }

  void _onError(mk.Player p, String e) {
    if (p != _activePlayer) return;
    if (_loading || _isCrossfading) return;
    appLogger.e('media_kit error: $e');
    _emitPlayer(_state.copyWith(status: PlaybackStatus.error, errorMessage: e));
  }

  // ---------------------------------------------------------------------------
  // Source loading & Crossfade -----------------------------------------------

  /// Force-stop everything and play directly with no crossfade at all.
  Future<void> _directPlay(DeezerTrack track, {Duration? startPosition}) async {
    final op = _nextPlaybackOp();
    _cancelTransitions();
    _cancelLoadingWatchdog();
    _loading = false;
    await _safeStopPlayer(_activePlayer);
    await _safeStopPlayer(_inactivePlayer);
    if (_isStalePlaybackOp(op)) return;
    await _loadAndPlay(track, _activePlayer, op, startPosition: startPosition);
  }

  /// Start playback with optional crossfade.
  /// Only called from auto-crossfade and skip next/prev (manual short fade).
  Future<void> _startPlayback(
    DeezerTrack track, {
    required bool autoCrossfade,
  }) async {
    final op = _nextPlaybackOp();
    _autoCrossfadeTriggered = false;

    final int fadeSecs = _state.crossfadeSeconds;
    final crossfadeDuration = autoCrossfade
        ? Duration(seconds: fadeSecs)
        : const Duration(milliseconds: 500);

    final bool canCrossfade =
        _activePlayer.state.playing && crossfadeDuration > Duration.zero;

    if (!canCrossfade) {
      _cancelTransitions();
      await _safeStopPlayer(_activePlayer);
      await _safeStopPlayer(_inactivePlayer);
      if (_isStalePlaybackOp(op)) return;

      await _loadAndPlay(track, _activePlayer, op);
      return;
    }

    // Cancel any in-progress crossfade cleanly
    _crossfadeTimer?.cancel();
    if (_isCrossfading) {
      // Stop the player that was fading out from the previous crossfade
      await _safeStopPlayer(_inactivePlayer);
    }
    _isCrossfading = true;

    final fadingOutPlayer = _activePlayer;
    final fadingInPlayer = _inactivePlayer;

    // Switch active player NOW so UI updates to new track
    _activePlayer = fadingInPlayer;
    _inactivePlayer = fadingOutPlayer;

    // Start new track at volume 0
    await fadingInPlayer.setVolume(0.0);

    // Begin loading
    _setLoadingForOp(op, true);
    _emitPlayer(
      _state.copyWith(
        currentTrack: track,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        buffered: Duration.zero,
        errorMessage: null,
        transitionDuration: crossfadeDuration,
      ),
    );

    try {
      _startLoadingWatchdog(op, track);

      String? url;
      String? userAgent;
      Map<String, String>? customHeaders;

      if (track.link == 'wave://audiobook' && track.preview != null) {
        final payload = (jsonDecode(track.preview!) as Map).cast<String, dynamic>();
        url = await _resolveAudiobookTrackUrl(track, payload);
        final headersMap = payload['httpHeaders'];
        if (headersMap is Map) {
          customHeaders = Map<String, String>.from(headersMap);
        }
      } else {
        final localPath = LocalDownloadMatcher.localAudioPathForTrack(track);
        if (localPath == null) {
          await LocalProxy.ensureRunning();
          appLogger.i(
            'Resolving playback stream for ${track.artist?.name ?? ''} - ${track.title}',
          );
          final res = await _resolver
              .resolveUrl(track)
              .timeout(
                const Duration(seconds: 22),
                onTimeout: () {
                  appLogger.w('Stream resolution timed out for ${track.title}');
                  return null;
                },
              );
          url = res?.url;
          userAgent = res?.userAgent;
        } else {
          url = 'file://$localPath'; // Wrap local path in file:// URI
        }
      }
      if (url == null) throw Exception('No audio source found');
      if (_isStalePlaybackOp(op)) return;

      // Route YouTube urls through our local proxy
      if (YoutubeStreamHttp.isYoutubeCdnUrl(url) && LocalProxy.isRunning) {
        final encodedUrl = Uri.encodeComponent(url);
        final encodedUa = Uri.encodeComponent(userAgent ?? '');
        url =
            'http://127.0.0.1:${LocalProxy.port}/proxy?url=$encodedUrl&ua=$encodedUa';
      }

      final Map<String, String> mergedHeaders = {};
      if (userAgent != null) mergedHeaders['User-Agent'] = userAgent;
      if (customHeaders != null) mergedHeaders.addAll(customHeaders);

      await fadingInPlayer
          .open(mk.Media(url, httpHeaders: mergedHeaders.isNotEmpty ? mergedHeaders : null), play: true)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException('Player open timed out'),
          );
      await fadingInPlayer.play().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      if (_isStalePlaybackOp(op)) {
        await fadingInPlayer.stop();
        return;
      }
      await _applyEqualizerToPlayer(fadingInPlayer);

      _setLoadingForOp(op, false);
      _lastAutoRecoveryTrackId = null;
      _emitPlayer(_state.copyWith(status: PlaybackStatus.playing));
      _preloadNext();
    } on YoutubeRateLimitException catch (e) {
      _setLoadingForOp(op, false);
      _isCrossfading = false;
      if (_isStalePlaybackOp(op)) return;
      appLogger.e('YouTube rate limit blocked playback: $e');
      await _resetAudioPipeline(reason: 'YouTube rate limit');
      _emitPlayer(
        _state.copyWith(status: PlaybackStatus.error, errorMessage: e.message),
      );
      return;
    } catch (e, st) {
      _setLoadingForOp(op, false);
      _isCrossfading = false;
      if (_isStalePlaybackOp(op)) return;

      // Revert the active player swap so the currently playing song isn't interrupted
      _activePlayer = fadingOutPlayer;
      _inactivePlayer = fadingInPlayer;

      appLogger.e('media_kit load failed', error: e, stackTrace: st);
      await _resetAudioPipeline(reason: 'crossfade load failed');

      // Attempt to auto-skip to the next song instead of just failing silently and stopping the queue
      unawaited(skipNext());
      return;
    }

    // Now start volume fade
    // Capture a reference so we can detect if a new crossfade replaced us
    final thisTimer = Object();
    _crossfadeTag = thisTimer;

    final steps = 20;
    final stepDuration = crossfadeDuration ~/ steps;
    final targetVolume = _state.volume * 100;

    int currentStep = 0;
    _crossfadeTimer = Timer.periodic(stepDuration, (timer) async {
      // If a newer crossfade or direct play has started, bail out
      if (_crossfadeTag != thisTimer || _isStalePlaybackOp(op)) {
        timer.cancel();
        return;
      }

      currentStep++;
      final progress = currentStep / steps;

      try {
        await fadingOutPlayer.setVolume(targetVolume * (1 - progress));
        await fadingInPlayer.setVolume(targetVolume * progress);
      } catch (_) {
        // Player may have been stopped/disposed
        timer.cancel();
        _isCrossfading = false;
        return;
      }

      if (currentStep >= steps) {
        timer.cancel();
        try {
          await fadingOutPlayer.stop();
        } catch (_) {}
        _isCrossfading = false;
      }
    });
  }

  void _showErrorUiToast(String message) {
    try {
      final clean = message.replaceAll('Exception: ', '').trim();
      scaffoldMessengerKey.currentState?.clearSnackBars();
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  clean,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFC93B3B),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (_) {}
  }

  Future<String?> _resolveAudiobookTrackUrl(DeezerTrack track, Map<String, dynamic> payload) async {
    final rawUrl = payload['url'] as String;
    final isTorrent = payload['isTorrent'] == true;
    if (!isTorrent) return rawUrl;

    final bookData = payload['audiobook'] as Map?;
    final source = (bookData?['source'] as String? ?? '').toLowerCase();
    final fileIndex = payload['torrentFileIndex'] as int?;

    final isAudiobookBay = source.contains('audiobookbay') ||
        source.contains('audiobook_bay') ||
        source.contains('audiobook bay') ||
        source == 'abb' ||
        rawUrl.startsWith('magnet:');

    final activeDebrid = await DebridApi().getActiveDebridService();
    if (activeDebrid != null && activeDebrid.isNotEmpty && isAudiobookBay) {
      appLogger.i('[Debrid] Resolving Audiobook magnet via active Debrid service ($activeDebrid)...');
      try {
        final files = await DebridApi().resolveByService(
          activeDebrid,
          rawUrl,
          fileIndex: fileIndex,
          filename: track.title,
        );
        if (files.isNotEmpty && files.first.downloadUrl.isNotEmpty) {
          final debridUrl = files.first.downloadUrl;
          appLogger.i('[Debrid] Successfully resolved stream URL via $activeDebrid: $debridUrl');
          return debridUrl;
        }
        throw Exception('Audiobook is not cached on $activeDebrid yet.');
      } catch (e) {
        appLogger.e('[Debrid] Debrid resolution failed on $activeDebrid: $e');
        final rawStr = e.toString().replaceAll('Exception: ', '').trim();
        if (rawStr.contains('returned no files') || rawStr.contains('never returned') || rawStr.contains('not cached')) {
          throw Exception('Audiobook is not cached on $activeDebrid yet. Please wait for it to cache.');
        } else if (rawStr.contains('timed out')) {
          throw Exception('$activeDebrid caching timed out. Audiobook is still downloading on $activeDebrid.');
        } else {
          throw Exception('Debrid ($activeDebrid): $rawStr');
        }
      }
    }

    // Only if Debrid is OFF (no active Debrid service configured), use local P2P engine.
    appLogger.i('[TorrentStream] Debrid is OFF. Streaming via local libtorrent engine: ${track.title}');
    return await TorrentStreamService.instance.getStreamUrl(rawUrl, fileIndex ?? 0);
  }

  Future<void> _loadAndPlay(DeezerTrack track, mk.Player player, int op, {Duration? startPosition}) async {
    await player.pause();
    await player.setVolume(_state.volume * 100);
    if (track.link == 'wave://audiobook') {
      await player.setRate(_state.speed);
    } else {
      await player.setRate(1.0);
    }

    _setLoadingForOp(op, true);
    _emitPlayer(
      _state.copyWith(
        currentTrack: track,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        buffered: Duration.zero,
        errorMessage: null,
        transitionDuration: Duration.zero,
      ),
    );
    try {
      _startLoadingWatchdog(op, track);

      String? url;
      String? userAgent;
      Map<String, String>? customHeaders;

      if (track.link == 'wave://audiobook' && track.preview != null) {
        final payload = (jsonDecode(track.preview!) as Map).cast<String, dynamic>();
        url = await _resolveAudiobookTrackUrl(track, payload);
        final headersMap = payload['httpHeaders'];
        if (headersMap is Map) {
          customHeaders = Map<String, String>.from(headersMap);
        }
      } else {
        final localPath = LocalDownloadMatcher.localAudioPathForTrack(track);
        if (localPath == null) {
          final settingsRaw = Hive.isBoxOpen(HiveBoxes.settings)
              ? Hive.box<dynamic>(HiveBoxes.settings).get('app_settings')
              : null;
          AppSettings settings = const AppSettings();
          if (settingsRaw is String && settingsRaw.isNotEmpty) {
            try {
              settings = AppSettings.fromJson(jsonDecode(settingsRaw));
            } catch (_) {}
          }

          if (settings.audioQuality == AudioQuality.lossless) {
            final octaveRes = await OctaveMusicService.instance.resolveLosslessUrl(track);
            if (octaveRes != null) {
              url = octaveRes.url;
              customHeaders = octaveRes.headers;
            }
          }

          if (url == null) {
            await LocalProxy.ensureRunning();
            final res = await _resolver
                .resolveUrl(track)
                .timeout(
                  const Duration(seconds: 22),
                  onTimeout: () {
                    appLogger.w('Stream resolution timed out for ${track.title}');
                    return null;
                  },
                );
            url = res?.url;
            userAgent = res?.userAgent;
          }
        } else {
          url = 'file://$localPath';
        }
      }
      if (_isStalePlaybackOp(op)) return;

      if (url == null) {
        _setLoadingForOp(op, false);
        const errMsg = 'No audio source found';
        _showErrorUiToast(errMsg);
        _emitPlayer(
          _state.copyWith(
            status: PlaybackStatus.error,
            errorMessage: errMsg,
          ),
        );
        return;
      }

      // Route YouTube urls through our local proxy
      if (YoutubeStreamHttp.isYoutubeCdnUrl(url) && LocalProxy.isRunning) {
        final encodedUrl = Uri.encodeComponent(url);
        final encodedUa = Uri.encodeComponent(userAgent ?? '');
        url =
            'http://127.0.0.1:${LocalProxy.port}/proxy?url=$encodedUrl&ua=$encodedUa';
      }

      final Map<String, String> mergedHeaders = {};
      if (userAgent != null) mergedHeaders['User-Agent'] = userAgent;
      if (customHeaders != null) mergedHeaders.addAll(customHeaders);

      await player
          .open(mk.Media(url, httpHeaders: mergedHeaders.isNotEmpty ? mergedHeaders : null), play: true)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException('Player open timed out'),
          );
      await player.play().timeout(const Duration(seconds: 5), onTimeout: () {});
      if (startPosition != null && startPosition > Duration.zero) {
        await player.seek(startPosition);
      }
      
      if (_isStalePlaybackOp(op)) {
        await player.stop();
        return;
      }
      await _applyEqualizerToPlayer(player);
      _setLoadingForOp(op, false);
      _lastAutoRecoveryTrackId = null;
      _emitPlayer(_state.copyWith(status: PlaybackStatus.playing));
      _preloadNext();
    } on YoutubeRateLimitException catch (e) {
      _setLoadingForOp(op, false);
      if (_isStalePlaybackOp(op)) return;
      appLogger.e('YouTube rate limit blocked playback: $e');
      await _resetAudioPipeline(reason: 'YouTube rate limit');
      _showErrorUiToast(e.message);
      _emitPlayer(
        _state.copyWith(status: PlaybackStatus.error, errorMessage: e.message),
      );
      return;
    } catch (e, st) {
      _setLoadingForOp(op, false);
      if (_isStalePlaybackOp(op)) return;
      appLogger.e('media_kit load failed', error: e, stackTrace: st);
      await _resetAudioPipeline(reason: 'track load failed');
      final cleanMessage = e.toString().replaceAll('Exception: ', '').trim();
      _showErrorUiToast(cleanMessage);
      _emitPlayer(
        _state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: cleanMessage,
        ),
      );
    }
  }

  void _preloadNext() async {
    // v21 stability fix: do not resolve the next YouTube stream in the
    // background on Android/mobile. The same resolver/network stack is used by
    // the track the user actually tapped, and background preloading can make the
    // whole player feel stuck when YouTube/CDN calls hang. Play the current track
    // first; resolve the next one only when it is actually selected.
    return;
  }

  // ---------------------------------------------------------------------------
  // AudioService / Playback control ------------------------------------------

  @override
  Future<void> play() async {
    if (_loading || _state.status == PlaybackStatus.loading) {
      await _recoverAudioPipeline(
        _queue.current,
        reason: 'user pressed play while player was stuck loading',
        retryCurrentTrack: true,
      );
      return;
    }
    if (_state.status == PlaybackStatus.idle && _queue.current != null) {
      await _directPlay(_queue.current!);
      return;
    }
    try {
      await LocalProxy.ensureRunning();
    } catch (e) {
      appLogger.w('LocalProxy ensureRunning failed before resume: $e');
    }
    await _activePlayer.play().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  @override
  Future<void> pause() async {
    if (_loading || _state.status == PlaybackStatus.loading) {
      await stop();
      return;
    }
    await _activePlayer.pause();
    await _inactivePlayer.pause();
    _emitPlayer(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    _nextPlaybackOp();
    _cancelTransitions();
    _cancelLoadingWatchdog();
    _loading = false;
    await _safeStopPlayer(_activePlayer);
    await _safeStopPlayer(_inactivePlayer);
    _emitPlayer(
      _state.copyWith(status: PlaybackStatus.idle, position: Duration.zero),
    );
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _activePlayer.seek(position);

  @override
  Future<void> skipToNext() async => skipNext();

  @override
  Future<void> skipToPrevious() async => skipPrevious();

  @override
  Future<void> togglePlayPause() async {
    if (_loading ||
        _state.status == PlaybackStatus.loading ||
        _state.status == PlaybackStatus.buffering) {
      await _recoverAudioPipeline(
        _queue.current,
        reason: 'user pressed play/pause while player was stuck',
        retryCurrentTrack: true,
      );
      return;
    }
    if (_activePlayer.state.playing ||
        _state.status == PlaybackStatus.playing) {
      await pause();
      return;
    }
    await play();
  }

  @override
  Future<void> skipNext() async {
    if (_queue.upcoming.isEmpty) {
      await stop();
      return;
    }
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
    await _startPlayback(next, autoCrossfade: false);
  }

  @override
  Future<void> skipToIndex(int indexInUpcoming) async {
    if (indexInUpcoming < 0 || indexInUpcoming >= _queue.upcoming.length) {
      return;
    }
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
    await _startPlayback(next, autoCrossfade: false);
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
    await _startPlayback(prev, autoCrossfade: false);
  }

  @override
  Future<void> skipPrevious() async {
    if (_activePlayer.state.position > const Duration(seconds: 3) ||
        _queue.history.isEmpty) {
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
    await _startPlayback(prev, autoCrossfade: false);
  }

  @override
  Future<void> setShuffle(bool value) async {
    _emitPlayer(_state.copyWith(shuffle: value));
    if (value && _queue.upcoming.isNotEmpty) {
      final list = List<DeezerTrack>.from(_queue.upcoming)..shuffle(Random());
      _emitQueue(_queue.copyWith(shuffled: value, upcoming: list));
    } else {
      _emitQueue(_queue.copyWith(shuffled: value));
    }
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    _emitPlayer(_state.copyWith(repeat: mode));
    final mkMode = switch (mode) {
      RepeatMode.off => mk.PlaylistMode.none,
      RepeatMode.all => mk.PlaylistMode.loop,
      RepeatMode.one => mk.PlaylistMode.single,
    };
    await _playerA.setPlaylistMode(mkMode);
    await _playerB.setPlaylistMode(mkMode);
  }

  @override
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _emitPlayer(_state.copyWith(volume: v));
    if (!_isCrossfading) {
      await _activePlayer.setVolume(v * 100);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    final s = speed.clamp(0.25, 4.0);
    _emitPlayer(_state.copyWith(speed: s));
    if (_state.currentTrack?.link == 'wave://audiobook') {
      await _activePlayer.setRate(s);
    }
  }

  @override
  Future<void> setCrossfadeSeconds(int seconds) async {
    _emitPlayer(_state.copyWith(crossfadeSeconds: seconds.clamp(0, 12)));
  }

  // ---------------------------------------------------------------------------
  // Queue management ---------------------------------------------------------

  @override
  Future<void> playTracks(List<DeezerTrack> tracks, {int? startIndex, Duration? startPosition}) async {
    if (tracks.isEmpty) return;

    int i;
    if (startIndex != null) {
      i = startIndex.clamp(0, tracks.length - 1);
    } else {
      if (_state.shuffle) {
        i = Random().nextInt(tracks.length);
      } else {
        i = 0;
      }
    }

    final current = tracks[i];

    var upcoming = List<DeezerTrack>.from(tracks);
    upcoming.removeAt(i);

    if (_state.shuffle && upcoming.isNotEmpty) {
      upcoming.shuffle(Random());
    } else if (!_state.shuffle) {
      upcoming = List<DeezerTrack>.from(tracks.sublist(i + 1));
    }

    _emitQueue(
      QueueState(
        history: const <DeezerTrack>[],
        current: current,
        upcoming: upcoming,
        shuffled: _state.shuffle,
      ),
    );
    await _directPlay(current, startPosition: startPosition);
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
  Future<void> toggleRelatedMode() async {
    if (_queue.isRelatedMode) {
      // Disable related mode
      _emitQueue(
        _queue.copyWith(
          isRelatedMode: false,
          upcoming: _queue.originalUpcoming,
          originalUpcoming: const <DeezerTrack>[],
        ),
      );
    } else {
      // Enable related mode
      _emitQueue(
        _queue.copyWith(
          isRelatedMode: true,
          originalUpcoming: _queue.upcoming,
          upcoming: const <DeezerTrack>[], // clear upcoming while loading
        ),
      );

      if (_queue.current != null) {
        final track = _queue.current!;
        final artistName = track.artist?.name ?? '';
        final trackName = track.title;
        if (artistName.isNotEmpty) {
          try {
            final similar = await LastfmApiClient().getSimilarTracks(
              trackName,
              artistName,
            );
            final deezerApi = DeezerApiClient();
            final newTracks = <DeezerTrack>[];
            for (final t in similar) {
              final tName = t['name'] ?? '';
              final tArtist = t['artist'] ?? '';
              if (tName.isEmpty || tArtist.isEmpty) continue;
              try {
                final res = await deezerApi.searchTracks(
                  'artist:"$tArtist" track:"$tName"',
                );
                if (res.isNotEmpty) {
                  final exists = [
                    ..._queue.history,
                    _queue.current,
                  ].any((e) => e?.id == res.first.id);
                  if (!exists) {
                    newTracks.add(res.first);
                  }
                }
              } catch (_) {}
              if (newTracks.length >= 10) break;
            }
            // Only update upcoming if we are still in related mode
            if (_queue.isRelatedMode) {
              _emitQueue(_queue.copyWith(upcoming: newTracks));
            }
          } catch (e) {
            appLogger.e('Failed to toggle related mode: $e');
            // If failed, just leave it empty and it will fall back to charting tracks if skipNext is called or we can just leave it
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Misc ---------------------------------------------------------------------

  @override
  bool isDownloaded(int trackId) {
    return LocalDownloadMatcher.isDownloadedById(trackId);
  }

  @override
  Future<void> setEqualizer(List<double> bandsDb) async {
    _equalizerBandsDb = bandsDb;
    await _applyEqualizerToPlayer(_playerA);
    await _applyEqualizerToPlayer(_playerB);
  }

  @override
  Future<void> dispose() async {
    _crossfadeTimer?.cancel();
    _cancelLoadingWatchdog();
    await _playerA.dispose();
    await _playerB.dispose();
    _resolver.dispose();
    await _playerCtrl.close();
    await _queueCtrl.close();
  }
}
