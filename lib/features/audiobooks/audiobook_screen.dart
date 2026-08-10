import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/api/models/deezer_album.dart';
import '../../../core/api/models/deezer_artist.dart';
import '../../../core/api/models/deezer_track.dart';
import '../../../core/audio/player_providers.dart';
import '../../../core/models/audiobook.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/detail_track_row.dart';
import '../../../widgets/play_shuffle_pair.dart';
import '../../../widgets/shimmer.dart';
import '../../../widgets/player/more_options_sheet.dart';
import '../player/now_playing_screen.dart';
import 'services/audiobook_scraper_service.dart';
import 'services/audiobook_providers.dart';

class AudiobookScreen extends ConsumerStatefulWidget {
  const AudiobookScreen({
    super.key,
    required this.audiobook,
    this.autoPlay = false,
  });
  final Audiobook audiobook;
  final bool autoPlay;

  @override
  ConsumerState<AudiobookScreen> createState() => _AudiobookScreenState();
}

class _AudiobookScreenState extends ConsumerState<AudiobookScreen> {
  List<AudiobookChapter>? _chapters;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchChapters();
  }

  Future<void> _fetchChapters() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final chapters = await AudiobookScraperService.instance.getChapters(widget.audiobook);
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _loading = false;
        });

        if (widget.autoPlay) {
          final tracks = _buildMockTracks();
          if (tracks.isNotEmpty) {
            final progress = ref
                .read(audiobookProgressProvider.notifier)
                .getProgress(widget.audiobook.uuid);
            final controls = ref.read(playerControlsProvider);
            if (progress != null) {
              controls.playTracks(
                tracks,
                startIndex: progress.chapterIndex,
                startPosition: Duration(seconds: progress.positionSeconds),
              );
            } else {
              controls.playTracks(tracks);
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  List<DeezerTrack> _buildMockTracks() {
    if (_chapters == null) return [];
    
    // Hash the audiobook URL to generate stable IDs for the tracks
    final baseId = widget.audiobook.pageUrl.hashCode.abs();

    return _chapters!.asMap().entries.map((entry) {
      final idx = entry.key;
      final ch = entry.value;

      final payload = {
        'url': ch.url,
        'isTorrent': ch.isTorrent,
        'torrentFileIndex': ch.torrentFileIndex,
        'httpHeaders': ch.httpHeaders,
        'chapterIndex': idx,
        'audiobook': widget.audiobook.toJson(),
      };

      final img = widget.audiobook.coverImage.isEmpty ? null : widget.audiobook.coverImage;
      return DeezerTrack(
        id: -baseId - idx - 1, // Negative ID so it doesn't conflict with real Deezer IDs
        title: ch.title,
        link: 'wave://audiobook',
        preview: jsonEncode(payload),
        duration: 0,
        artist: DeezerArtist(id: 0, name: widget.audiobook.title),
        album: DeezerAlbum(
          id: 0,
          title: widget.audiobook.title,
          cover: img,
          coverSmall: img,
          coverMedium: img,
          coverBig: img,
          coverXl: img,
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final cover = widget.audiobook.coverImage.isNotEmpty ? widget.audiobook.coverImage : null;
    final tracks = _buildMockTracks();

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(child: _Header(theme: theme)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: <Widget>[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.65,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                theme.cardRadius == 0 ? 0 : 12,
                              ),
                              child: cover != null
                                  ? CachedNetworkImage(
                                      imageUrl: cover,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) =>
                                          ColoredBox(color: theme.surface),
                                      errorWidget: (_, _, _) =>
                                          ColoredBox(color: theme.surface),
                                    )
                                  : ColoredBox(color: theme.surface),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.audiobook.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Source: ${widget.audiobook.source}',
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!_loading && tracks.isNotEmpty)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: PlayShufflePair(
                              onPlay: () {
                                final progress = ref.read(audiobookProgressProvider.notifier).getProgress(widget.audiobook.uuid);
                                if (progress != null) {
                                  final controls = ref.read(playerControlsProvider);
                                  controls.playTracks(tracks, startIndex: progress.chapterIndex, startPosition: Duration(seconds: progress.positionSeconds));
                                } else {
                                  ref.read(playerControlsProvider).playTracks(tracks);
                                }
                              },
                              onShuffle: () async {
                                final controls = ref.read(playerControlsProvider);
                                await controls.setShuffle(true);
                                await controls.playTracks(tracks);
                              },
                            ),
                          ),
                          Consumer(
                            builder: (context, ref, _) {
                              final player = ref.watch(playerSnapshotProvider);
                              final speed = player.speed;
                              return Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: InkWell(
                                  onTap: () => showWaveSheet<void>(
                                    context: context,
                                    builder: (_) => const AudioSpeedDial(),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: speed != 1.0
                                          ? theme.accent
                                          : theme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: theme.onSurface.withValues(alpha: 0.1)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          PhosphorIconsRegular.gauge,
                                          size: 18,
                                          color: speed != 1.0 ? theme.background : theme.onSurface,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${speed == speed.truncateToDouble() ? speed.toInt() : speed}x',
                                          style: TextStyle(
                                            color: speed != 1.0 ? theme.background : theme.onSurface,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, _) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: ShimmerBox(
                      width: MediaQuery.of(context).size.width - 32,
                      height: 40,
                    ),
                  ),
                  childCount: 6,
                ),
              )
            else if (_error)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: TextButton(
                      onPressed: _fetchChapters,
                      child: const Text('Failed to load chapters. Tap to retry.'),
                    ),
                  ),
                ),
              )
            else if (tracks.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('No chapters found.')),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DetailTrackRow(
                    track: tracks[i],
                    queue: tracks,
                    indexInQueue: i,
                    position: i + 1,
                    showArtist: false,
                  ),
                  childCount: tracks.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});
  final AppTheme theme;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                PhosphorIconsRegular.caretLeft,
                color: theme.onSurface,
                size: 22,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'AUDIOBOOK',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 46),
        ],
      ),
    );
  }
}
