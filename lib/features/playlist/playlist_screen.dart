import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/deezer_providers.dart';
import '../../core/api/models/deezer_playlist.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/downloads/download_status.dart';
import '../../core/storage/library_providers.dart';
import '../../core/utils/playlist_exchange.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart' show scaffoldMessengerKey;
import '../../widgets/detail_track_row.dart';
import '../../widgets/inline_error.dart';
import '../../widgets/play_shuffle_pair.dart';
import '../../widgets/shimmer.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final int playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  bool _editing = false;
  bool _showCoverViewer = false;
  bool _selectMode = false;
  final Set<int> _selectedTrackIds = {};
  late final TextEditingController _titleCtrl = TextEditingController();
  late final TextEditingController _descCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _isUserPlaylist => widget.playlistId < 0;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final asyncPl = ref.watch(playlistProvider(widget.playlistId));
    final likedPlaylists = ref.watch(likedPlaylistsProvider);
    final isLiked = likedPlaylists.any((p) => p.id == widget.playlistId);

    List<DeezerTrack>? directTracks;
    AsyncValue<List<DeezerTrack>>? asyncTracks;

    if (_isUserPlaylist) {
      directTracks =
          ref.watch(localPlaylistTracksProvider)[widget.playlistId] ??
          const <DeezerTrack>[];
    } else {
      asyncTracks = ref.watch(playlistTracksProvider(widget.playlistId));
    }

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: asyncPl.when(
              loading: () => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: <Widget>[
                      const ShimmerSquare(size: 200),
                      const SizedBox(height: 16),
                      ShimmerBox(
                        width: MediaQuery.of(context).size.width - 48,
                        height: 24,
                      ),
                    ],
                  ),
                ),
              ),
              error: (e, _) => Center(
                child: InlineError(
                  message: 'Could not load playlist',
                  onRetry: () =>
                      ref.invalidate(playlistProvider(widget.playlistId)),
                ),
              ),
              data: (pl) =>
                  _buildBody(theme, pl, asyncTracks, directTracks, isLiked),
            ),
          ),
          if (_showCoverViewer)
            _CoverViewer(
              imageUrl: asyncPl.maybeWhen(
                data: (p) => p.pictureXl ?? p.pictureBig ?? p.picture,
                orElse: () => null,
              ),
              onClose: () => setState(() => _showCoverViewer = false),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    AppTheme theme,
    DeezerPlaylist pl,
    AsyncValue<List<DeezerTrack>>? asyncTracks,
    List<DeezerTrack>? directTracks,
    bool isLiked,
  ) {
    final liveTrackCount =
        directTracks?.length ??
        asyncTracks?.maybeWhen(
          data: (tracks) => tracks.length,
          orElse: () => pl.nbTracks ?? 0,
        ) ??
        (pl.nbTracks ?? 0);
    final cover =
        pl.pictureBig ?? pl.pictureXl ?? pl.pictureMedium ?? pl.picture;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(child: _topBar(theme, pl, isLiked)),
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
                      child: GestureDetector(
                        onTap: () => setState(() => _showCoverViewer = true),
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
                ),
                const SizedBox(height: 18),
                _editing
                    ? _editableHeader(theme, pl)
                    : _staticHeader(theme, pl, liveTrackCount),
                const SizedBox(height: 14),
                if (_isUserPlaylist) ...<Widget>[
                  _editToggle(theme, pl),
                  const SizedBox(height: 10),
                  _addDownloadsButton(theme),
                ],
                const SizedBox(height: 8),
                PlayShufflePair(
                  onPlay: () {
                    final tracks =
                        directTracks ??
                        asyncTracks?.maybeWhen(
                          data: (t) => t,
                          orElse: () => const <DeezerTrack>[],
                        ) ??
                        const <DeezerTrack>[];
                    if (tracks.isNotEmpty) {
                      ref.read(playerControlsProvider).playTracks(tracks);
                    }
                  },
                  onShuffle: () async {
                    final tracks =
                        directTracks ??
                        asyncTracks?.maybeWhen(
                          data: (t) => t,
                          orElse: () => const <DeezerTrack>[],
                        ) ??
                        const <DeezerTrack>[];
                    if (tracks.isEmpty) return;
                    final controls = ref.read(playerControlsProvider);
                    await controls.setShuffle(true);
                    await controls.playTracks(tracks);
                  },
                ),
                const SizedBox(height: 10),
                _DownloadPlaylistButton(
                  title: pl.title,
                  tracks:
                      directTracks ??
                      asyncTracks?.maybeWhen(
                        data: (t) => t,
                        orElse: () => const <DeezerTrack>[],
                      ) ??
                      const <DeezerTrack>[],
                ),
                if (_isUserPlaylist) ...[
                  const SizedBox(height: 10),
                  if (!_selectMode)
                    GestureDetector(
                      onTap: () => setState(() => _selectMode = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              PhosphorIconsRegular.pencilSimple,
                              color: theme.onSurface,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Edit Tracks',
                              style: TextStyle(
                                color: theme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _selectMode = false;
                              _selectedTrackIds.clear();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: theme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: theme.onSurfaceMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: _selectedTrackIds.isEmpty
                                ? null
                                : () async {
                                    await ref
                                        .read(
                                          localPlaylistTracksProvider.notifier,
                                        )
                                        .removeTracks(
                                          widget.playlistId,
                                          _selectedTrackIds.toList(),
                                        );
                                    ref.invalidate(
                                      playlistProvider(widget.playlistId),
                                    );
                                    final count = _selectedTrackIds.length;
                                    setState(() {
                                      _selectMode = false;
                                      _selectedTrackIds.clear();
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Removed $count track${count == 1 ? '' : 's'}',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTrackIds.isEmpty
                                    ? theme.error.withValues(alpha: 0.3)
                                    : theme.error,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _selectedTrackIds.isEmpty
                                    ? 'Select tracks'
                                    : 'Remove (${_selectedTrackIds.length})',
                                style: TextStyle(
                                  color: _selectedTrackIds.isEmpty
                                      ? theme.error
                                      : theme.background,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (directTracks != null)
          ...(_isUserPlaylist
              ? <Widget>[_userReorderableList(directTracks)]
              : <Widget>[_staticList(directTracks)])
        else
          ...(asyncTracks!.hasValue
              ? (_isUserPlaylist
                    ? <Widget>[_userReorderableList(asyncTracks.value!)]
                    : <Widget>[_staticList(asyncTracks.value!)])
              : asyncTracks.when(
                  loading: () => <Widget>[
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, _) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: ShimmerBox(
                            width: MediaQuery.of(context).size.width - 32,
                            height: 56,
                          ),
                        ),
                        childCount: 8,
                      ),
                    ),
                  ],
                  error: (e, _) => <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: InlineError(
                          message: 'Could not load tracks',
                          onRetry: () => ref.invalidate(
                            playlistTracksProvider(widget.playlistId),
                          ),
                        ),
                      ),
                    ),
                  ],
                  data: (_) => const <Widget>[],
                )),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _topBar(AppTheme theme, DeezerPlaylist pl, bool isLiked) {
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
            'PLAYLIST',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _exportPlaylist(pl),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    PhosphorIconsRegular.export,
                    color: theme.onSurface,
                    size: 22,
                  ),
                ),
              ),
              if (!_isUserPlaylist)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      ref.read(likedPlaylistsProvider.notifier).toggle(pl),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 12,
                      bottom: 12,
                      right: 12,
                    ),
                    child: Icon(
                      isLiked
                          ? PhosphorIconsFill.heart
                          : PhosphorIconsRegular.heart,
                      color: isLiked ? theme.accent : theme.onSurface,
                      size: 22,
                    ),
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _staticHeader(AppTheme theme, DeezerPlaylist pl, int liveTrackCount) {
    final mins = (pl.duration ?? 0) ~/ 60;
    return Column(
      children: <Widget>[
        Text(
          pl.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        if ((pl.description ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            pl.description!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          <String>[
            if ((pl.creator?.name ?? '').isNotEmpty) 'by ${pl.creator!.name}',
            if ((pl.fans ?? 0) > 0) '${pl.fans} followers',
            if (liveTrackCount > 0) '$liveTrackCount tracks',
            if (mins > 0) '${mins}m',
          ].join('  ·  '),
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _editableHeader(AppTheme theme, DeezerPlaylist pl) {
    return Column(
      children: <Widget>[
        _UnderlineField(
          controller: _titleCtrl
            ..text = _titleCtrl.text.isEmpty ? pl.title : _titleCtrl.text,
          hint: 'Title',
          fontSize: 20,
        ),
        const SizedBox(height: 10),
        _UnderlineField(
          controller: _descCtrl
            ..text = _descCtrl.text.isEmpty
                ? (pl.description ?? '')
                : _descCtrl.text,
          hint: 'Description',
          fontSize: 12,
        ),
      ],
    );
  }

  Widget _editToggle(AppTheme theme, DeezerPlaylist pl) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (_editing) ...<Widget>[
          _PillButton(
            label: 'CANCEL',
            background: Colors.transparent,
            border: theme.onSurface.withValues(alpha: 0.2),
            color: theme.onSurface,
            onTap: () => setState(() => _editing = false),
          ),
          const SizedBox(width: 10),
          _PillButton(
            label: 'SAVE',
            background: theme.accent,
            color: theme.background,
            onTap: () async {
              await ref
                  .read(userPlaylistsProvider.notifier)
                  .updatePlaylist(
                    pl.id,
                    title: _titleCtrl.text.trim(),
                    description: _descCtrl.text.trim().isEmpty
                        ? null
                        : _descCtrl.text.trim(),
                  );
              setState(() => _editing = false);
            },
          ),
        ] else ...<Widget>[
          _PillButton(
            label: 'EDIT',
            background: Colors.transparent,
            border: theme.onSurface.withValues(alpha: 0.2),
            color: theme.onSurface,
            onTap: () => setState(() => _editing = true),
          ),
          const SizedBox(width: 10),
          _PillButton(
            label: 'DELETE',
            background: theme.error.withValues(alpha: 0.1),
            border: theme.error,
            color: theme.error,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: theme.surface,
                  title: Text(
                    'Delete Playlist',
                    style: TextStyle(
                      color: theme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Text(
                    'Are you sure you want to delete "${pl.title}"? This cannot be undone.',
                    style: TextStyle(color: theme.onSurfaceMuted),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        'CANCEL',
                        style: TextStyle(color: theme.onSurfaceMuted),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        'DELETE',
                        style: TextStyle(color: theme.error),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                if (!mounted) return;
                final nav = Navigator.of(context);
                await ref.read(userPlaylistsProvider.notifier).delete(pl.id);
                nav.pop();
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _addDownloadsButton(AppTheme theme) {
    final downloadedCount = ref.watch(downloadedTracksProvider).length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: downloadedCount == 0 ? null : _openAddDownloadsSheet,
      child: AnimatedOpacity(
        duration: theme.fastDuration,
        opacity: downloadedCount == 0 ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(
              theme.cardRadius == 0 ? 0 : 999,
            ),
            border: Border.all(color: theme.onSurface.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                PhosphorIconsRegular.cloudCheck,
                color: theme.onSurface,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                downloadedCount == 0
                    ? 'No downloads to add'
                    : 'Add songs from downloads',
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAddDownloadsSheet() async {
    final theme = AppThemeScope.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final downloaded = ref.watch(downloadedTracksProvider);
            final playlistTracks =
                ref.watch(localPlaylistTracksProvider)[widget.playlistId] ??
                const <DeezerTrack>[];
            final existingIds = playlistTracks.map((t) => t.id).toSet();
            final available = downloaded
                .where((track) => !existingIds.contains(track.id))
                .toList(growable: false);

            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.42,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
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
                        'Add downloaded songs',
                        style: TextStyle(
                          color: theme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        available.isEmpty
                            ? 'All downloaded songs are already in this playlist.'
                            : '${available.length} available from Downloads',
                        style: TextStyle(
                          color: theme.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: available.isEmpty
                            ? Center(
                                child: Text(
                                  'Nothing to add.',
                                  style: TextStyle(
                                    color: theme.onSurfaceMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: available.length,
                                itemBuilder: (context, i) {
                                  final track = available[i];
                                  final cover =
                                      track.album?.coverMedium ??
                                      track.album?.cover ??
                                      track.album?.coverSmall;

                                  return ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        theme.cardRadius == 0 ? 0 : 8,
                                      ),
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: cover != null
                                            ? CachedNetworkImage(
                                                imageUrl: cover,
                                                fit: BoxFit.cover,
                                                placeholder: (_, _) =>
                                                    ColoredBox(
                                                      color: theme.background,
                                                    ),
                                                errorWidget: (_, _, _) =>
                                                    ColoredBox(
                                                      color: theme.background,
                                                    ),
                                              )
                                            : ColoredBox(
                                                color: theme.background,
                                                child: Icon(
                                                  PhosphorIconsRegular
                                                      .musicNotes,
                                                  color: theme.onSurfaceMuted,
                                                ),
                                              ),
                                      ),
                                    ),
                                    title: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.onSurface,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      track.artist?.name ?? 'Unknown artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.onSurfaceMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: Icon(
                                      PhosphorIconsRegular.plusCircle,
                                      color: theme.accent,
                                    ),
                                    onTap: () async {
                                      await ref
                                          .read(
                                            localPlaylistTracksProvider
                                                .notifier,
                                          )
                                          .addTrack(widget.playlistId, track);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Added "${track.title}" to playlist',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _staticList(List<DeezerTrack> tracks) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => DetailTrackRow(
          track: tracks[i],
          queue: tracks,
          indexInQueue: i,
          position: i + 1,
        ),
        childCount: tracks.length,
      ),
    );
  }

  Widget _userReorderableList(List<DeezerTrack> tracks) {
    final theme = AppThemeScope.of(context);
    return SliverReorderableList(
      itemBuilder: (context, i) {
        final track = tracks[i];
        return Material(
          key: ValueKey<String>('playlist_${widget.playlistId}_${track.id}'),
          color: theme.background,
          child: Row(
            children: [
              if (_selectMode)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_selectedTrackIds.contains(track.id)) {
                        _selectedTrackIds.remove(track.id);
                      } else {
                        _selectedTrackIds.add(track.id);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Icon(
                      _selectedTrackIds.contains(track.id)
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsRegular.circle,
                      color: _selectedTrackIds.contains(track.id)
                          ? theme.accent
                          : theme.onSurfaceMuted,
                      size: 22,
                    ),
                  ),
                ),
              Expanded(
                child: DetailTrackRow(
                  track: track,
                  queue: tracks,
                  indexInQueue: i,
                  position: i + 1,
                  dragHandle: !_selectMode,
                ),
              ),
            ],
          ),
        );
      },
      itemCount: tracks.length,
      onReorder: _selectMode
          ? (_, __) {}
          : (oldIndex, newIndex) {
              ref
                  .read(localPlaylistTracksProvider.notifier)
                  .reorderTrack(widget.playlistId, oldIndex, newIndex);
            },
    );
  }

  Future<void> _removeTrackFromPlaylist(DeezerTrack track) async {
    await ref
        .read(localPlaylistTracksProvider.notifier)
        .removeTrack(widget.playlistId, track.id);

    ref.invalidate(playlistProvider(widget.playlistId));
    if (mounted) setState(() {});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed "${track.title}" from playlist')),
    );
  }

  Future<void> _exportPlaylist(DeezerPlaylist pl) async {
    // Safe snackbar helper — crash-proof regardless of context lifecycle.
    void snack(String msg) {
      try {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } catch (_) {}
    }

    final tracksAsync = ref.read(playlistTracksProvider(pl.id));
    List<DeezerTrack> tracks = [];
    if (_isUserPlaylist) {
      tracks = ref.read(localPlaylistTracksProvider)[pl.id] ?? [];
    } else {
      tracks = tracksAsync.maybeWhen(
        data: (t) => t,
        orElse: () => const <DeezerTrack>[],
      );
    }

    if (tracks.isEmpty) {
      snack('Cannot export an empty playlist.');
      return;
    }

    final safeTitle = pl.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final suggestedName = 'wave_playlist_$safeTitle.json';
    final jsonStr = PlaylistExchange.serialize(pl, tracks);
    final bytes = utf8.encode(jsonStr);

    // Open native save-file dialog — user picks location, no permissions needed.
    // Pass bytes so FilePicker writes the file itself on all platforms.
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export "${pl.title}"',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (savePath == null) return; // user cancelled or platform handled write

    // On desktop, FilePicker returns the path but doesn't write — do it here.
    try {
      await File(savePath).writeAsBytes(bytes);
      snack('Saved to: $savePath');
    } catch (_) {
      snack('Playlist exported successfully!');
    }
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.background,
    required this.color,
    required this.onTap,
    this.border,
  });
  final String label;
  final Color background;
  final Color color;
  final Color? border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 999),
          border: border != null ? Border.all(color: border!) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
      ),
    );
  }
}

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.controller,
    required this.hint,
    required this.fontSize,
  });
  final TextEditingController controller;
  final String hint;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.onSurface.withValues(alpha: 0.25)),
        ),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          color: theme.onSurface,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
        cursorColor: theme.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: theme.onSurfaceMuted,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class _DownloadPlaylistButton extends ConsumerWidget {
  const _DownloadPlaylistButton({required this.title, required this.tracks});

  final String title;
  final List<DeezerTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final coverage = downloadCoverageForTracks(
      tracks,
      ref.watch(downloadedTracksProvider),
    );
    final enabled = coverage.hasTracks;
    final allOnDevice = coverage.allOnDevice;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !enabled
          ? null
          : () {
              if (allOnDevice) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playlist is already on device: $title'),
                  ),
                );
                return;
              }
              ref
                  .read(downloadManagerProvider)
                  .queueTracks(
                    coverage.missingTracks,
                    title: coverage.partiallyOnDevice
                        ? 'Missing playlist tracks: $title'
                        : 'Playlist: $title',
                    replaceFinishedQueue: false,
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    coverage.partiallyOnDevice
                        ? 'Queued ${coverage.missing} missing playlist tracks: $title'
                        : 'Queued playlist download: $title',
                  ),
                ),
              );
            },
      child: AnimatedOpacity(
        duration: theme.fastDuration,
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(
              theme.cardRadius == 0 ? 0 : 999,
            ),
            border: Border.all(
              color: allOnDevice
                  ? theme.accent.withValues(alpha: 0.55)
                  : theme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                allOnDevice
                    ? PhosphorIconsFill.cloudCheck
                    : PhosphorIconsRegular.cloudArrowDown,
                color: allOnDevice ? theme.accent : theme.onSurface,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                allOnDevice
                    ? 'Playlist on device'
                    : (coverage.partiallyOnDevice
                          ? 'Download missing (${coverage.missing})'
                          : 'Download playlist'),
                style: TextStyle(
                  color: allOnDevice ? theme.accent : theme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverViewer extends StatelessWidget {
  const _CoverViewer({required this.imageUrl, required this.onClose});
  final String? imageUrl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.92),
          child: SafeArea(
            child: Stack(
              children: <Widget>[
                if (imageUrl != null)
                  Center(
                    child: InteractiveViewer(
                      maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        PhosphorIconsRegular.x,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
