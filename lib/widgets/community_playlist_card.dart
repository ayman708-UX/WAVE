import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/models/community_playlist.dart';
import '../core/router/app_router.dart';
import 'content_cards.dart';

class CommunityPlaylistCard extends ConsumerWidget {
  const CommunityPlaylistCard({
    super.key,
    required this.communityPlaylist,
    this.size = 150,
  });

  final CommunityPlaylist communityPlaylist;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = communityPlaylist.playlist;
    
    return CoverCard(
      imageUrl: playlist.pictureBig ?? playlist.pictureMedium ?? playlist.picture,
      title: playlist.title,
      subtitle: 'By @${communityPlaylist.creatorName}',
      size: size,
      onTap: () {
        // Navigate to the community playlist screen using extra
        context.push(
          AppRoutes.communityPlaylist,
          extra: communityPlaylist,
        );
      },
    );
  }
}
