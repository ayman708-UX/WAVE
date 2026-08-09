import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../api/audiobook_service.dart';
import '../api/audiobook_player_service.dart';
import '../api/audiobook_download_service.dart';
import '../api/torrent_stream_service.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';

bool _isTorrentEngineLoopbackUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('127.0.0.1') ||
      lower.contains('localhost') ||
      lower.contains('::1');
}

class AudiobookPlayerScreen extends StatefulWidget {
  final Audiobook audiobook;
  final List<AudiobookChapter> chapters;
  final int initialChapterIndex;
  final Duration? initialPosition;

  const AudiobookPlayerScreen({
    super.key,
    required this.audiobook,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.initialPosition,
  });

  @override
  State<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

class _AudiobookPlayerScreenState extends State<AudiobookPlayerScreen> {
  final _service = AudiobookPlayerService();
  final _downloadService = AudiobookDownloadService();
  double _playbackSpeed = 1.0;
  bool _isDownloaded = false;
  bool _bookmarked = false;

  List<AudiobookChapter>? _playableChapters;
  bool _magnetResolving = false;
  Uint8List? _magnetCoverBytes;

  List<AudiobookChapter> get _chaptersForUi =>
      _playableChapters ?? widget.chapters;

  String get _remoteThumbUrl {
    final t = widget.audiobook.thumbUrl.trim();
    if (t.isNotEmpty) return t;
    return widget.audiobook.coverImage.trim();
  }

  Widget _backgroundCover() {
    final bytes = _magnetCoverBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        color: Colors.black.withValues(alpha: 0.6),
        colorBlendMode: BlendMode.darken,
        errorBuilder: (_, __, ___) =>
            Container(color: Colors.black.withValues(alpha: 0.88)),
      );
    }
    if (_remoteThumbUrl.isEmpty) {
      return Container(color: Colors.black.withValues(alpha: 0.88));
    }
    if (_isTorrentEngineLoopbackUrl(_remoteThumbUrl)) {
      return Image.network(
        _remoteThumbUrl,
        fit: BoxFit.cover,
        color: Colors.black.withValues(alpha: 0.6),
        colorBlendMode: BlendMode.darken,
        errorBuilder: (_, __, ___) =>
            Container(color: Colors.black.withValues(alpha: 0.88)),
      );
    }
    return CachedNetworkImage(
      imageUrl: _remoteThumbUrl,
      fit: BoxFit.cover,
      color: Colors.black.withValues(alpha: 0.6),
      colorBlendMode: BlendMode.darken,
      errorWidget: (context, url, error) => CachedNetworkImage(
        imageUrl: widget.audiobook.coverImage,
        fit: BoxFit.cover,
        color: Colors.black.withValues(alpha: 0.6),
        colorBlendMode: BlendMode.darken,
      ),
    );
  }

  Widget _foregroundCover() {
    final bytes = _magnetCoverBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CachedNetworkImage(
          imageUrl: widget.audiobook.coverImage,
          fit: BoxFit.cover,
        ),
      );
    }
    if (_remoteThumbUrl.isEmpty) {
      return Container(
        color: Colors.white.withValues(alpha: 0.08),
        child: const Center(
          child: Icon(Icons.menu_book_rounded,
              size: 120, color: Colors.white24),
        ),
      );
    }
    if (_isTorrentEngineLoopbackUrl(_remoteThumbUrl)) {
      return Image.network(
        _remoteThumbUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CachedNetworkImage(
          imageUrl: widget.audiobook.coverImage,
          fit: BoxFit.cover,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: _remoteThumbUrl,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => CachedNetworkImage(
          imageUrl: widget.audiobook.coverImage, fit: BoxFit.cover),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlaybackSpeed());
    unawaited(_refreshBookmarkFlag());
    _bootstrapPlayback();
  }

  Future<void> _loadPlaybackSpeed() async {
    await _service.ensurePlaybackRateLoaded();
    if (!mounted) return;
    setState(() => _playbackSpeed = _service.playbackRate.value);
  }

  Future<void> _refreshBookmarkFlag() async {
    final b = await _service.isBookmarked(widget.audiobook.audioBookId);
    if (mounted) setState(() => _bookmarked = b);
  }

  Future<void> _bootstrapPlayback() async {
    await _service.ensurePlaybackRateLoaded();
    final book = widget.audiobook;
    final magnet = book.magnetLink;
    final needsMagnet = (book.source == 'magnet' || book.source == 'audiobookbay') &&
        magnet != null &&
        magnet.isNotEmpty &&
        widget.chapters.any((c) => c.torrentFileIndex != null);

    _playableChapters = widget.chapters;

    final ch = _playableChapters;
    if (ch == null || ch.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable chapters')),
        );
        Navigator.pop(context);
      });
      return;
    }

    setState(() {
      _magnetResolving = needsMagnet;
    });

    try {
      await Future.wait([
        _refreshDownloadState(ch.length),
        _service.loadBook(
          book,
          ch,
          initialChapter: widget.initialChapterIndex,
          resumePosition: widget.initialPosition,
        ),
      ]);
      if (mounted) {
        setState(() => _playbackSpeed = _service.playbackRate.value);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playback failed: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
      Navigator.pop(context);
      return;
    } finally {
      if (mounted) {
        setState(() => _magnetResolving = false);
      }
    }

    unawaited(_fetchMagnetCoverInBackground(book));
    unawaited(_refreshBookmarkFlag());
  }

  /// Cover art from the torrent — loaded after audio starts so it does not block playback.
  Future<void> _fetchMagnetCoverInBackground(Audiobook book) async {
    final magnet = book.magnetLink?.trim();
    final coverIdx = book.magnetCoverFileIndex;
    if (magnet == null || magnet.isEmpty || coverIdx == null) return;
    try {
      final torrent = TorrentStreamService();
      final coverUrl = await torrent.streamAudiobookFile(
        magnet,
        coverIdx,
        allowNonStreamable: true,
        stopSiblingStreams: false,
        fileNameHint: book.magnetCoverFileName,
      );
      if (coverUrl == null || coverUrl.isEmpty) return;
      final res = await http.get(
        Uri.parse(coverUrl),
        headers: AudiobookPlayerService.magnetStreamHttpHeaders,
      );
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        if (mounted) setState(() => _magnetCoverBytes = res.bodyBytes);
        unawaited(_service.setNotificationCoverBytes(res.bodyBytes));
      }
    } catch (_) {}
  }

  Future<void> _refreshDownloadState(int chapterCount) async {
    final downloaded =
        await _downloadService.isBookDownloaded(widget.audiobook.audioBookId);
    if (mounted) setState(() => _isDownloaded = downloaded);
    _downloadService.checkDownloadedChapters(
      widget.audiobook.audioBookId,
      chapterCount,
    );
  }

  @override
  void dispose() {
    unawaited(_service.saveManualProgress());
    super.dispose();
  }

  void _changeChapter(int index) async {
    await _service.changeChapter(index);
  }

  void _startDownload() {
    final ch = _playableChapters;
    if (ch == null || ch.isEmpty) return;
    _downloadService.downloadBook(widget.audiobook, ch);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Download started...'), duration: Duration(seconds: 2)),
    );
  }

  void _handleExit() async {
    await _service.saveManualProgress();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExit();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Stack(
          children: [
            Positioned.fill(
              child: _backgroundCover(),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        AppTheme.bgDark.withValues(alpha: 0.92),
                        AppTheme.bgDark,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          _buildCoverArt(),
                          const SizedBox(height: 40),
                          _buildTitleInfo(),
                          const SizedBox(height: 48),
                          _buildPlayerControls(),
                          const SizedBox(height: 32),
                          _buildChapterList(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_magnetResolving)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primaryColor),
                      SizedBox(height: 16),
                      Text(
                        'Starting playback…',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
            onPressed: _handleExit,
          ),
          const Text(
            'NOW PLAYING',
            style: TextStyle(
              color: AppTheme.textSecondary,
              letterSpacing: 1.6,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () async {
                    await _service.saveManualProgress();
                    await Future.delayed(const Duration(milliseconds: 160));
                    final wasBookmarked = _bookmarked;
                    final snap = await _service.captureBookmarkSnapshot();
                    final book = _service.currentBook.value ?? widget.audiobook;
                    await _service.upsertBookmarkWithProgress(
                      book,
                      chapterIndex: snap.chapterIndex,
                      positionMs: snap.positionMs,
                    );
                    if (!mounted) return;
                    setState(() => _bookmarked = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          wasBookmarked
                              ? 'Bookmark updated'
                              : 'Saved to bookmarks',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  onLongPress: _bookmarked
                      ? () async {
                          await _service.removeBookmark(
                              widget.audiobook.audioBookId);
                          if (!mounted) return;
                          setState(() => _bookmarked = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bookmark removed'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: _bookmarked ? Colors.amberAccent : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
              _buildDownloadButton(),
              const SizedBox(width: 4),
              _buildSpeedMenu(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    return ValueListenableBuilder<Map<String, AudiobookDownloadProgress>>(
      valueListenable: _downloadService.activeDownloads,
      builder: (context, downloads, _) {
        final progress = downloads[widget.audiobook.audioBookId];

        if (progress != null && progress.status == 'downloading') {
          return TvGestureTap(
            onTap: () {
              _downloadService.cancelDownload(widget.audiobook.audioBookId);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress.progress,
                      strokeWidth: 2.5,
                      color: AppTheme.primaryColor,
                      backgroundColor: Colors.white12,
                    ),
                    Icon(Icons.close, color: Colors.white, size: 12),
                  ],
                ),
              ),
            ),
          );
        }

        if (_isDownloaded || (progress != null && progress.status == 'completed')) {
          return IconButton(
            icon: const Icon(Icons.download_done, color: Colors.greenAccent, size: 24),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Already downloaded'), duration: Duration(seconds: 1)),
              );
            },
            tooltip: 'Downloaded',
          );
        }

        return IconButton(
          icon: const Icon(Icons.download_rounded, color: Colors.white, size: 24),
          onPressed: _startDownload,
          tooltip: 'Download all chapters',
        );
      },
    );
  }

  Widget _buildSpeedMenu() {
    return PopupMenuButton<double>(
      initialValue: _playbackSpeed,
      onSelected: (double speed) {
        setState(() => _playbackSpeed = speed);
        unawaited(_service.setRate(speed));
      },
      itemBuilder: (context) => [0.5, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0].map((s) => PopupMenuItem(value: s, child: Text('${s}x Speed'))).toList(),
      color: const Color(0xFF1A0B2E),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCoverArt() {
    return Center(
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 5)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _foregroundCover(),
        ),
      ),
    );
  }

  Widget _buildTitleInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ValueListenableBuilder<int>(
        valueListenable: _service.currentChapterIndex,
        builder: (context, chapterIndex, _) {
          return Column(
            children: [
              Text(
                widget.audiobook.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 24,
                child: chapterIndex < _chaptersForUi.length
                    ? MarqueeText(
                  text: 'Chapter ${chapterIndex + 1}: ${_chaptersForUi[chapterIndex].title}',
                  style: const TextStyle(color: AppTheme.primaryColor, fontSize: 16, fontWeight: FontWeight.w500),
                )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlayerControls() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ValueListenableBuilder<Duration>(
            valueListenable: _service.position,
            builder: (context, pos, _) {
              return ValueListenableBuilder<Duration>(
                valueListenable: _service.duration,
                builder: (context, dur, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _service.isPreparingPlayback,
                    builder: (context, preparing, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _service.isBuffering,
                        builder: (context, buffering, _) {
                          final hasDuration = dur > Duration.zero;
                          final showLoading =
                              preparing || (buffering && !hasDuration);
                      final displayPos =
                          (showLoading && pos <= Duration.zero)
                              ? Duration.zero
                              : pos;
                      final dValue =
                          hasDuration ? dur.inMilliseconds.toDouble() : 1.0;
                      final pValue = displayPos.inMilliseconds.toDouble();
                      final safePValue = hasDuration
                          ? pValue.clamp(0.0, dValue)
                          : 0.0;

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white10,
                              thumbColor: Colors.white,
                              trackHeight: 4,
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                            ),
                            child: Slider(
                              value: safePValue,
                              max: dValue,
                              onChanged: (showLoading || !hasDuration)
                                  ? null
                                  : (v) => unawaited(
                                      _service.seekTo(
                                        Duration(milliseconds: v.toInt()),
                                      ),
                                    ),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(displayPos),
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                                Text(
                                  hasDuration
                                      ? _formatDuration(dur)
                                      : (showLoading ? 'Buffering…' : '--:--'),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        ValueListenableBuilder<bool>(
          valueListenable: _service.autoplay,
          builder: (context, auto, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('AUTOPLAY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: auto, 
                      onChanged: (v) => _service.autoplay.value = v,
                      activeTrackColor: AppTheme.primaryColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _service.currentChapterIndex,
              builder: (context, index, _) => IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 48),
                onPressed: index > 0 ? () => _changeChapter(index - 1) : null,
              ),
            ),
            const SizedBox(width: 32),
            ValueListenableBuilder<bool>(
              valueListenable: _service.isPreparingPlayback,
              builder: (context, preparing, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _service.isBuffering,
                  builder: (context, buffering, _) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable: _service.duration,
                      builder: (context, dur, _) {
                        final showLoading =
                            preparing || (buffering && dur <= Duration.zero);
                        if (showLoading) {
                          return const SizedBox(
                            width: 80,
                            height: 80,
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                  color: Colors.white),
                            ),
                          );
                        }
                        return ValueListenableBuilder<bool>(
                          valueListenable: _service.isPlaying,
                          builder: (context, playing, _) {
                            return TvGestureTap(
                              onTap: () => _service.playOrPause(),
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle),
                                child: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 54,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(width: 32),
            ValueListenableBuilder<int>(
              valueListenable: _service.currentChapterIndex,
              builder: (context, index, _) => IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 48),
                onPressed: index < _chaptersForUi.length - 1 ? () => _changeChapter(index + 1) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChapterList() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CHAPTERS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 16),
          ValueListenableBuilder<int>(
            valueListenable: _service.currentChapterIndex,
            builder: (context, currentIdx, _) {
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _chaptersForUi.length,
                itemBuilder: (context, index) {
                  final isCurrent = currentIdx == index;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () => _changeChapter(index),
                      leading: Text('${index + 1}', style: TextStyle(color: isCurrent ? AppTheme.primaryColor : Colors.white24, fontWeight: FontWeight.bold)),
                      title: Text(
                        _chaptersForUi[index].title,
                        style: TextStyle(color: isCurrent ? Colors.white : Colors.white70, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrent)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.graphic_eq, color: AppTheme.primaryColor, size: 20),
                            ),
                          _buildChapterDownloadIcon(index),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChapterDownloadIcon(int index) {
    final key = '${widget.audiobook.audioBookId}_$index';
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _downloadService.downloadingChapters,
      builder: (context, downloading, _) {
        if (downloading.contains(key)) {
          return const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
          );
        }
        return ValueListenableBuilder<Set<String>>(
          valueListenable: _downloadService.downloadedChapterKeys,
          builder: (context, downloaded, _) {
            if (downloaded.contains(key)) {
              return const Icon(Icons.download_done, color: Colors.greenAccent, size: 20);
            }
            return TvGestureTap(
              onTap: () {
                _downloadService.downloadSingleChapter(
                  widget.audiobook,
                  _chaptersForUi[index],
                  index,
                );
              },
              child: const Icon(Icons.download_outlined, color: Colors.white38, size: 20),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const MarqueeText({super.key, required this.text, required this.style});
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  void _startScrolling() async {
    if (!_scrollController.hasClients) return;
    await Future.delayed(const Duration(seconds: 2));
    while (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) break;
      await _scrollController.animateTo(maxScroll, duration: Duration(milliseconds: (maxScroll * 30).toInt()), curve: Curves.linear);
      await Future.delayed(const Duration(seconds: 1));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Text(widget.text, style: widget.style, maxLines: 1),
    );
  }
}
