import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/deezer_playlist.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/storage/library_providers.dart';
import '../../core/theme/app_theme.dart';

void showAddToPlaylistSheet(BuildContext context, DeezerTrack track) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddToPlaylistSheet(track: track),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.track});

  final DeezerTrack track;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final _controller = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createAndAdd() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;

    final playlist = await ref.read(userPlaylistsProvider.notifier).create(
          title: title,
          coverUrl: widget.track.album?.coverBig ?? widget.track.album?.cover,
        );

    await ref
        .read(localPlaylistTracksProvider.notifier)
        .addTrack(playlist.id, widget.track);

    if (!mounted) return;
    setState(() {
      _creating = false;
      _controller.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to "${playlist.title}"')),
    );
  }

  Future<void> _togglePlaylist(DeezerPlaylist playlist, bool alreadyIn) async {
    final notifier = ref.read(localPlaylistTracksProvider.notifier);
    if (alreadyIn) {
      await notifier.removeTrack(playlist.id, widget.track.id);
    } else {
      await notifier.addTrack(playlist.id, widget.track);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alreadyIn
              ? 'Removed from "${playlist.title}"'
              : 'Added to "${playlist.title}"',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final playlists = ref.watch(userPlaylistsProvider);
    final tracksByPlaylist = ref.watch(localPlaylistTracksProvider);
    final alreadyIn = ref.watch(playlistsForTrackProvider(widget.track.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      maxChildSize: 0.92,
      minChildSize: 0.42,
      builder: (ctx, controller) {
        return Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.onSurfaceMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Manage playlists',
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  alreadyIn.isEmpty
                      ? 'This downloaded song is not in any playlist yet.'
                      : 'Already in: ${_playlistNames(alreadyIn)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_creating)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          style: TextStyle(color: theme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Playlist name',
                            hintStyle: TextStyle(color: theme.onSurfaceMuted),
                            filled: true,
                            fillColor: theme.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                theme.cardRadius == 0 ? 0 : 10,
                              ),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _createAndAdd(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          PhosphorIconsRegular.check,
                          color: theme.accent,
                        ),
                        onPressed: _createAndAdd,
                      ),
                    ],
                  ),
                )
              else
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.background,
                      borderRadius: BorderRadius.circular(
                        theme.cardRadius == 0 ? 0 : 10,
                      ),
                    ),
                    child: Icon(
                      PhosphorIconsRegular.plus,
                      color: theme.accent,
                    ),
                  ),
                  title: Text(
                    'Create new playlist',
                    style: TextStyle(
                      color: theme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    'Creates it and adds this song',
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => setState(() => _creating = true),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: playlists.isEmpty
                    ? Center(
                        child: Text(
                          'No playlists yet. Create one above.',
                          style: TextStyle(
                            color: theme.onSurfaceMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: playlists.length,
                        itemBuilder: (ctx, i) {
                          final playlist = playlists[i];
                          final tracks = tracksByPlaylist[playlist.id] ??
                              const <DeezerTrack>[];
                          final isInPlaylist =
                              tracks.any((t) => t.id == widget.track.id);
                          final cover = playlist.pictureBig ??
                              playlist.pictureMedium ??
                              playlist.picture;

                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                theme.cardRadius == 0 ? 0 : 8,
                              ),
                              child: cover != null
                                  ? CachedNetworkImage(
                                      imageUrl: cover,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 48,
                                      height: 48,
                                      color: theme.background,
                                      child: Icon(
                                        PhosphorIconsRegular.musicNotes,
                                        color: theme.onSurfaceMuted,
                                      ),
                                    ),
                            ),
                            title: Text(
                              playlist.title,
                              style: TextStyle(
                                color: theme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              isInPlaylist
                                  ? 'In this playlist · tap to remove'
                                  : '${playlist.nbTracks ?? tracks.length} tracks · tap to add',
                              style: TextStyle(
                                color: isInPlaylist
                                    ? theme.accent
                                    : theme.onSurfaceMuted,
                                fontSize: 12,
                                fontWeight: isInPlaylist
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            trailing: _PlaylistTogglePill(
                              label: isInPlaylist ? 'Remove' : 'Add',
                              icon: isInPlaylist
                                  ? PhosphorIconsRegular.minusCircle
                                  : PhosphorIconsRegular.plusCircle,
                              accent: isInPlaylist ? theme.error : theme.accent,
                            ),
                            onTap: () => _togglePlaylist(playlist, isInPlaylist),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistTogglePill extends StatelessWidget {
  const _PlaylistTogglePill({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _playlistNames(List<DeezerPlaylist> playlists) {
  if (playlists.length <= 3) {
    return playlists.map((p) => p.title).join(', ');
  }
  final first = playlists.take(3).map((p) => p.title).join(', ');
  return '$first +${playlists.length - 3} more';
}
