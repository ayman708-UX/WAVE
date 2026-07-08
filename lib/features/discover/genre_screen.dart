import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/deezer_providers.dart';
import '../../core/api/models/deezer_genre.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/detail_track_row.dart';
import '../../widgets/inline_error.dart';
import '../../widgets/shimmer.dart';

class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.genre});
  final DeezerGenre genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final tracksAsync = ref.watch(genreRadioTracksProvider(genre.id));

    return Scaffold(
      backgroundColor: theme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          _SliverHeader(genre: genre, theme: theme),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _PlayButton(
                onTap: () async {
                  final tracks = tracksAsync.maybeWhen(
                    data: (t) => t,
                    orElse: () => <DeezerTrack>[],
                  );
                  if (tracks.isNotEmpty) {
                    ref.read(playerControlsProvider).playTracks(tracks);
                  }
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            sliver: tracksAsync.when(
              data: (tracks) => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DetailTrackRow(
                    track: tracks[i],
                    queue: tracks,
                    indexInQueue: i,
                    position: i + 1,
                  ),
                  childCount: tracks.length,
                ),
              ),
              loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: ShimmerBox(width: double.infinity, height: 50),
                  ),
                  childCount: 10,
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: InlineError(
                  message: 'Could not load genre tracks',
                  onRetry: () =>
                      ref.invalidate(genreRadioTracksProvider(genre.id)),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _SliverHeader extends StatelessWidget {
  const _SliverHeader({required this.genre, required this.theme});
  final DeezerGenre genre;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final pic = genre.pictureBig ?? genre.pictureXl ?? genre.picture;
    return SliverAppBar(
      expandedHeight: 240,
      backgroundColor: theme.background,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            PhosphorIconsRegular.caretLeft,
            color: Colors.white,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          genre.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            shadows: [Shadow(blurRadius: 10, color: Colors.black)],
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (pic != null)
              CachedNetworkImage(
                imageUrl: pic,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(color: theme.surface),
              )
            else
              ColoredBox(color: theme.surface),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsFill.play, color: theme.background, size: 20),
            const SizedBox(width: 10),
            Text(
              'PLAY RADIO',
              style: TextStyle(
                color: theme.background,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
