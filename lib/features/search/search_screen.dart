import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/storage/search_providers.dart';
import '../../core/api/deezer_api_client.dart';
import '../../core/api/lastfm_providers.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/storage/recently_played.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/content_cards.dart';
import '../../widgets/inline_error.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/snap_horizontal_list.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && _isFocused != _focus.hasFocus) {
        setState(() => _isFocused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String value) {
    final t = value.trim();
    if (t.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).push(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.isNotEmpty;
    return ColoredBox(
      color: theme.background,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: hasQuery
                  ? const _Results()
                  : _Browse(
                      onTapRecent: (q) {
                        _ctrl.text = q;
                        ref.read(searchQueryProvider.notifier).setText(q);
                      },
                    ),
            ),
            // Backdrop blur appears when focused but no query yet.
            if (_isFocused && !hasQuery)
              Positioned.fill(
                top: 80,
                child: IgnorePointer(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: theme.background.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: WaveSearchBar(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).setText(v),
                onSubmitted: _commit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse (idle state) -----------------------------------------------------

class _Browse extends ConsumerWidget {
  const _Browse({required this.onTapRecent});

  final ValueChanged<String> onTapRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        if (recents.isNotEmpty) ...<Widget>[
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Recent'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final q in recents)
                    RecentSearchChip(
                      label: q,
                      onTap: () => onTapRecent(q),
                      onRemove: () => ref
                          .read(recentSearchesProvider.notifier)
                          .remove(q),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Results (active query) --------------------------------------------------

class _Results extends ConsumerStatefulWidget {
  const _Results();

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final async = ref.watch(searchResultsProvider);
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: <Widget>[
          for (var i = 0; i < 5; i++) ...<Widget>[
            const ShimmerBox(
              width: double.infinity,
              height: 56,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      error: (e, _) => InlineError(
        message: 'Search failed. Tap retry.',
        onRetry: () => ref.invalidate(searchResultsProvider),
      ),
      data: (r) {
        if (r.isEmpty) {
          return _EmptyState(theme: theme);
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            if (r.tracks.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: SectionHeader(title: 'Tracks')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final track = r.tracks[i];
                    return TrackRow(
                      track: track,
                      queue: r.tracks,
                      indexInQueue: i,
                      onTapOverride: () async => _playSearchTrack(
                        context,
                        ref,
                        track,
                        r.tracks,
                        i,
                        addRelated: true,
                      ),
                    );
                  },
                  childCount: r.tracks.length > 5 ? 5 : r.tracks.length,
                ),
              ),
            ],
            if (r.artists.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Artists'),
              ),
              SliverToBoxAdapter(
                child: SnapHorizontalList(
                  itemCount: r.artists.length,
                  itemExtent: 110,
                  height: 158,
                  itemBuilder: (_, i) => ArtistCircle(artist: r.artists[i]),
                ),
              ),
            ],
            if (r.albums.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Albums'),
              ),
              SliverToBoxAdapter(
                child: SnapHorizontalList(
                  itemCount: r.albums.length,
                  itemExtent: 150,
                  height: 198,
                  itemBuilder: (_, i) => AlbumCard(album: r.albums[i]),
                ),
              ),
            ],
            if (r.playlists.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Playlists'),
              ),
              SliverToBoxAdapter(
                child: SnapHorizontalList(
                  itemCount: r.playlists.length,
                  itemExtent: 150,
                  height: 198,
                  itemBuilder: (_, i) =>
                      PlaylistCard(playlist: r.playlists[i]),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  Future<void> _playSearchTrack(
    BuildContext context,
    WidgetRef ref,
    DeezerTrack track,
    List<DeezerTrack> queue,
    int index, {
    required bool addRelated,
  }) async {
    final controls = ref.read(playerControlsProvider);
    await controls.playTracks(queue, startIndex: index);

    if (context.mounted) {
      ref.read(recentlyPlayedProvider.notifier).push(
            RecentEntry(
              kind: 'track',
              id: track.id,
              title: track.title,
              subtitle: track.artist?.name,
              imageUrl: track.album?.coverMedium ?? track.album?.cover,
              atMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }

    if (!addRelated || _isYoutubeListing(track)) return;

    final artistName = track.artist?.name;
    if (artistName == null || artistName.isEmpty) return;

    final lastfmApi = ref.read(lastfmApiClientProvider);
    try {
      final similar = await lastfmApi.getSimilarTracks(track.title, artistName);
      if (similar.isEmpty) return;

      final deezerApi = ref.read(deezerApiClientProvider);
      int added = 0;
      for (final t in similar) {
        final tName = t['name'] ?? '';
        final tArtist = t['artist'] ?? '';
        if (tName.isEmpty || tArtist.isEmpty) continue;

        try {
          final searchRes = await deezerApi.searchTracks(
            'artist:"$tArtist" track:"$tName"',
          );
          if (searchRes.isNotEmpty) {
            await controls.addToQueueLast(searchRes.first);
            added++;
            if (added >= 15) break; // Limit related tracks
          }
        } catch (_) {}
      }
    } catch (_) {
      // ignore errors silently
    }
  }

  bool _isYoutubeListing(DeezerTrack track) =>
      track.link?.startsWith('wave://youtube') == true || track.id < 0;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    final t = theme as AppTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: t.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: t.accent.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              PhosphorIconsRegular.waveform,
              color: t.accent,
              size: 36,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No matches',
            style: TextStyle(
              color: t.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different artist, album or song.',
            style: TextStyle(color: t.onSurfaceMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
