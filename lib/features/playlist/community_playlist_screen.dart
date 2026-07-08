import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/community_playlist.dart';
import '../../core/audio/player_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/library_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/detail_track_row.dart';
import '../../widgets/play_shuffle_pair.dart';

class CommunityPlaylistScreen extends ConsumerWidget {
  const CommunityPlaylistScreen({super.key, required this.communityPlaylist});

  final CommunityPlaylist communityPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final playlist = communityPlaylist.playlist;
    final tracks = communityPlaylist.tracks;

    // Check if the user already liked it so they can save it locally
    final userPlaylists = ref.watch(userPlaylistsProvider);
    final isLiked = userPlaylists.any((p) => p.title == playlist.title);

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: theme.background,
              elevation: 0,
              pinned: true,
              expandedHeight: 320,
              leading: IconButton(
                icon: Icon(
                  PhosphorIconsRegular.caretLeft,
                  color: theme.onSurface,
                ),
                onPressed: () => context.pop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: playlist.pictureMedium != null
                            ? CachedNetworkImage(
                                imageUrl: playlist.pictureMedium!,
                                fit: BoxFit.cover,
                              )
                            : Icon(
                                PhosphorIconsRegular.musicNotes,
                                size: 60,
                                color: theme.onSurfaceMuted,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (playlist.description != null &&
                        playlist.description!.isNotEmpty) ...[
                      Text(
                        playlist.description!,
                        style: TextStyle(
                          color: theme.onSurfaceMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    GestureDetector(
                      onTap: () {
                        context.push(
                          AppRoutes.userProfilePath(communityPlaylist.userId),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.accent.withValues(alpha: 0.2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              communityPlaylist.creatorName.isNotEmpty
                                  ? communityPlaylist.creatorName[0]
                                        .toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                color: theme.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'By @${communityPlaylist.creatorName}',
                            style: TextStyle(
                              color: theme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: PlayShufflePair(
                            onPlay: () {
                              ref
                                  .read(playerControlsProvider)
                                  .playTracks(tracks);
                            },
                            onShuffle: () {
                              final shuffled = List.of(tracks)..shuffle();
                              ref
                                  .read(playerControlsProvider)
                                  .playTracks(shuffled);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Save button
                        GestureDetector(
                          onTap: () async {
                            final notifier = ref.read(
                              userPlaylistsProvider.notifier,
                            );
                            if (isLiked) {
                              // If they liked it, we might want to delete it by local ID, but we need to find it first.
                              // Actually, the user can manage it in their library. Let's just allow importing.
                            } else {
                              await notifier.importPlaylist(playlist, tracks);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Saved to your library'),
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: isLiked ? theme.accent : theme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              isLiked
                                  ? PhosphorIconsFill.checkCircle
                                  : PhosphorIconsRegular.plus,
                              color: isLiked
                                  ? theme.background
                                  : theme.onSurface,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: DetailTrackRow(
                    track: tracks[index],
                    queue: tracks,
                    indexInQueue: index,
                    position: index + 1,
                  ),
                );
              }, childCount: tracks.length),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}
