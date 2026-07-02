import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/deezer_playlist.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/storage/library_providers.dart';
import '../../core/theme/app_theme.dart';

void showAddToPlaylistSheet(BuildContext context, DeezerTrack track) {
  showAddTracksToPlaylistSheet(context, <DeezerTrack>[track]);
}

void showAddTracksToPlaylistSheet(
  BuildContext context,
  List<DeezerTrack> tracks,
) {
  if (tracks.isEmpty) return;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddToPlaylistSheet(tracks: tracks),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.tracks});

  final List<DeezerTrack> tracks;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final _controller = TextEditingController();
  bool _creating = false;

  bool get _single => widget.tracks.length == 1;
  DeezerTrack get _firstTrack => widget.tracks.first;

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
          coverUrl: _firstTrack.album?.coverBig ?? _firstTrack.album?.cover,
        );

    await ref
        .read(localPlaylistTracksProvider.notifier)
        .addTracks(playlist.id, widget.tracks);

    if (!mounted) return;
    setState(() {
      _creating = false;
      _controller.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_addedMessage(playlist.title, widget.tracks.length))),
    );
  }

  Future<void> _togglePlaylist(
    DeezerPlaylist playlist, {
    required int alreadyCount,
  }) async {
    final notifier = ref.read(localPlaylistTracksProvider.notifier);
    final allInPlaylist = alreadyCount == widget.tracks.length;

    if (allInPlaylist) {
      await notifier.removeTracks(
        playlist.id,
        widget.tracks.map((track) => track.id),
      );
    } else {
      await notifier.addTracks(playlist.id, widget.tracks);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          allInPlaylist
              ? _removedMessage(playlist.title, widget.tracks.length)
              : _addedMessage(playlist.title, widget.tracks.length - alreadyCount),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final playlists = ref.watch(userPlaylistsProvider);
    final tracksByPlaylist = ref.watch(localPlaylistTracksProvider);
    final selectedIds = widget.tracks.map((track) => track.id).toSet();

    final alreadyIn = _single
        ? ref.watch(playlistsForTrackProvider(_firstTrack.id))
        : playlists.where((playlist) {
            final tracks =
                tracksByPlaylist[playlist.id] ?? const <DeezerTrack>[];
            return tracks.any((track) => selectedIds.contains(track.id));
          }).toList(growable: false);

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
                _single ? 'Manage playlists' : 'Add selected to playlist',
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
                  _subtitle(alreadyIn),
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
                    _single
                        ? 'Creates it and adds this song'
                        : 'Creates it and adds ${widget.tracks.length} selected songs',
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
                          final alreadyCount = tracks
                              .where((track) => selectedIds.contains(track.id))
                              .length;
                          final allInPlaylist =
                              alreadyCount == widget.tracks.length;
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
                              _playlistSubtitle(
                                playlist: playlist,
                                playlistTrackCount: tracks.length,
                                alreadyCount: alreadyCount,
                              ),
                              style: TextStyle(
                                color: allInPlaylist
                                    ? theme.accent
                                    : theme.onSurfaceMuted,
                                fontSize: 12,
                                fontWeight: allInPlaylist
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            trailing: _PlaylistTogglePill(
                              label: allInPlaylist ? 'Remove' : 'Add',
                              icon: allInPlaylist
                                  ? PhosphorIconsRegular.minusCircle
                                  : PhosphorIconsRegular.plusCircle,
                              accent: allInPlaylist ? theme.error : theme.accent,
                            ),
                            onTap: () => _togglePlaylist(
                              playlist,
                              alreadyCount: alreadyCount,
                            ),
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

  String _subtitle(List<DeezerPlaylist> alreadyIn) {
    if (_single) {
      if (alreadyIn.isEmpty) {
        return 'This downloaded song is not in any playlist yet.';
      }
      return 'Already in: ${_playlistNames(alreadyIn)}';
    }

    if (alreadyIn.isEmpty) {
      return '${widget.tracks.length} selected downloaded songs are not in any playlist yet.';
    }

    return '${widget.tracks.length} selected songs · already found in ${alreadyIn.length} playlist${alreadyIn.length == 1 ? '' : 's'}.';
  }

  String _playlistSubtitle({
    required DeezerPlaylist playlist,
    required int playlistTrackCount,
    required int alreadyCount,
  }) {
    if (_single) {
      return alreadyCount > 0
          ? 'In this playlist · tap to remove'
          : '${playlist.nbTracks ?? playlistTrackCount} tracks · tap to add';
    }

    if (alreadyCount == widget.tracks.length) {
      return 'All ${widget.tracks.length} selected are in this playlist · tap to remove';
    }

    if (alreadyCount > 0) {
      final missing = widget.tracks.length - alreadyCount;
      return '$alreadyCount already here · tap to add $missing missing';
    }

    return '${playlist.nbTracks ?? playlistTrackCount} tracks · tap to add selected';
  }
}

String _playlistNames(List<DeezerPlaylist> playlists) {
  if (playlists.length <= 2) {
    return playlists.map((p) => p.title).join(', ');
  }
  return '${playlists.take(2).map((p) => p.title).join(', ')} +${playlists.length - 2}';
}

String _addedMessage(String playlistTitle, int count) {
  return count == 1
      ? 'Added to "$playlistTitle"'
      : 'Added $count songs to "$playlistTitle"';
}

String _removedMessage(String playlistTitle, int count) {
  return count == 1
      ? 'Removed from "$playlistTitle"'
      : 'Removed $count songs from "$playlistTitle"';
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
