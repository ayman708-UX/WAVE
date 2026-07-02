import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../core/api/models/deezer_playlist.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/utils/playlist_exchange.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/library_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/utils/app_breakpoints.dart';
import '../../main.dart' show scaffoldMessengerKey;
import '../../widgets/content_cards.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/player/add_to_playlist_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sub_tabs.dart';
import '../../widgets/swipe_action_row.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0;

  static const List<String> _labels = <String>[
    'Liked',
    'Albums',
    'Playlists',
    'Following',
    'Downloads',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return ColoredBox(
      color: theme.background,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text(
              'Your library',
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          WaveSubTabs(
            labels: _labels,
            active: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: theme.normalDuration,
              switchInCurve: theme.defaultCurve,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: switch (_tab) {
                0 => const KeyedSubtree(
                    key: ValueKey<String>('liked'),
                    child: _LikedTracksTab(),
                  ),
                1 => const KeyedSubtree(
                    key: ValueKey<String>('albums'),
                    child: _LikedAlbumsTab(),
                  ),
                2 => const KeyedSubtree(
                    key: ValueKey<String>('playlists'),
                    child: _PlaylistsTab(),
                  ),
                3 => const KeyedSubtree(
                    key: ValueKey<String>('following'),
                    child: _FollowingTab(),
                  ),
                _ => const KeyedSubtree(
                    key: ValueKey<String>('downloads'),
                    child: _DownloadsTab(),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liked tracks ------------------------------------------------------------

class _LikedTracksTab extends ConsumerWidget {
  const _LikedTracksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(likedTracksSortedProvider);
    final sort = ref.watch(likedSortProvider);
    final theme = AppThemeScope.of(context);

    if (tracks.isEmpty) {
      return _EmptyHint(
        icon: PhosphorIconsRegular.heart,
        title: 'Nothing liked yet',
        subtitle: 'Tap the heart on any song to save it here.',
      );
    }

    final totalSecs = tracks.fold<int>(0, (s, t) => s + (t.duration ?? 0));

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${tracks.length} songs · ${_durationText(totalSecs)}',
                        style: TextStyle(
                          color: theme.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _PillButton(
                  label: 'Shuffle',
                  icon: PhosphorIconsRegular.shuffle,
                  onTap: () async {
                    final controls = ref.read(playerControlsProvider);
                    await controls.setShuffle(true);
                    await controls.playTracks(tracks);
                  },
                ),
                const SizedBox(width: 8),
                _PillButton(
                  label: 'Play',
                  icon: PhosphorIconsFill.play,
                  filled: true,
                  onTap: () async {
                    final controls = ref.read(playerControlsProvider);
                    await controls.playTracks(tracks);
                  },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openSortSheet(context, ref, sort),
              child: Row(
                children: <Widget>[
                  Icon(
                    PhosphorIconsRegular.funnel,
                    size: 14,
                    color: theme.onSurfaceMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _sortLabel(sort),
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final t = tracks[i];
              return SwipeActionRow(
                trailingIcon: PhosphorIconsRegular.heartBreak,
                trailingColor: theme.error,
                trailingLabel: 'Unlike',
                onTrailing: () =>
                    ref.read(likedTracksProvider.notifier).remove(t.id),
                leadingIcon: PhosphorIconsRegular.queue,
                leadingColor: theme.accent,
                leadingLabel: 'Queue',
                onLeading: () async {
                  await ref.read(playerControlsProvider).addToQueueLast(t);
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPressStart: (d) => _openTrackMenu(
                    context,
                    ref,
                    t,
                    d.globalPosition,
                  ),
                  child: TrackRow(
                    track: t,
                    queue: tracks,
                    indexInQueue: i,
                  ),
                ),
              );
            },
            childCount: tracks.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  void _openTrackMenu(
    BuildContext context,
    WidgetRef ref,
    DeezerTrack t,
    Offset origin,
  ) {
    showWaveContextMenu(
      context: context,
      origin: origin,
      items: <ContextMenuItem>[
        ContextMenuItem(
          icon: PhosphorIconsRegular.queue,
          label: 'Add to queue',
          onTap: () => ref.read(playerControlsProvider).addToQueueLast(t),
        ),
        ContextMenuItem(
          icon: PhosphorIconsRegular.playlist,
          label: 'Add to playlist',
          onTap: () {
            showAddToPlaylistSheet(context, t);
          },
        ),
        if (t.album != null)
          ContextMenuItem(
            icon: PhosphorIconsRegular.vinylRecord,
            label: 'Go to album',
            onTap: () => context.push(AppRoutes.albumPath(t.album!.id)),
          ),
        if (t.artist != null)
          ContextMenuItem(
            icon: PhosphorIconsRegular.user,
            label: 'Go to artist',
            onTap: () => context.push(AppRoutes.artistPath(t.artist!.id)),
          ),
        ContextMenuItem(
          icon: PhosphorIconsRegular.shareNetwork,
          label: 'Share',
          onTap: () {},
        ),
        ContextMenuItem(
          icon: PhosphorIconsRegular.heartBreak,
          label: 'Remove from liked',
          destructive: true,
          onTap: () => ref.read(likedTracksProvider.notifier).remove(t.id),
        ),
      ],
    );
  }

  Future<void> _openSortSheet(
    BuildContext context,
    WidgetRef ref,
    LikedSort current,
  ) async {
    final theme = AppThemeScope.of(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'sort',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: theme.normalDuration,
      pageBuilder: (_, _, _) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(
                  theme.cardRadius == 0 ? 0 : 18,
                ),
                border: Border.all(
                  color: theme.onSurface.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: theme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Sort by',
                    style: TextStyle(
                      color: theme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final s in LikedSort.values)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ref.read(likedSortProvider.notifier).set(s);
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              s == current
                                  ? PhosphorIconsFill.checkCircle
                                  : PhosphorIconsRegular.circle,
                              color: s == current
                                  ? theme.accent
                                  : theme.onSurfaceMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _sortLabel(s),
                              style: TextStyle(
                                color: theme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          ),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }
}

String _sortLabel(LikedSort s) {
  switch (s) {
    case LikedSort.recent:
      return 'Recently liked';
    case LikedSort.alphabetical:
      return 'Title (A–Z)';
    case LikedSort.artist:
      return 'Artist';
    case LikedSort.duration:
      return 'Duration';
  }
}

String _durationText(int totalSecs) {
  final h = totalSecs ~/ 3600;
  final m = (totalSecs % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

// ---------------------------------------------------------------------------
// Liked albums ------------------------------------------------------------

class _LikedAlbumsTab extends ConsumerWidget {
  const _LikedAlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(likedAlbumsProvider);
    if (albums.isEmpty) {
      return _EmptyHint(
        icon: PhosphorIconsRegular.vinylRecord,
        title: 'No saved albums',
        subtitle: 'Albums you save will appear here.',
      );
    }
    final cols = AppBreakpoints.isDesktop(context)
        ? 4
        : AppBreakpoints.isTablet(context)
            ? 3
            : 2;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) =>
          AlbumCard(album: albums[i], size: double.infinity),
    );
  }
}

// ---------------------------------------------------------------------------
// User playlists ----------------------------------------------------------

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localLists = ref.watch(userPlaylistsProvider);
    final likedLists = ref.watch(likedPlaylistsProvider);
    final theme = AppThemeScope.of(context);

    final buttonsRow = Row(
      children: <Widget>[
        Expanded(child: _buildCreateButton(context, theme, ref)),
        const SizedBox(width: 12),
        Expanded(child: _buildImportButton(context, theme, ref)),
      ],
    );

    if (localLists.isEmpty && likedLists.isEmpty) {
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: buttonsRow,
          ),
          Expanded(
            child: _EmptyHint(
              icon: PhosphorIconsRegular.playlist,
              title: 'No playlists yet',
              subtitle: 'Tap "Create playlist" or like a playlist to save it here.',
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: <Widget>[
        buttonsRow,
        const SizedBox(height: 12),
        if (localLists.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'My Playlists'),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: localLists.length,
            itemBuilder: (context, i) {
              final p = localLists[i];
              return SwipeActionRow(
                key: ValueKey<int>(p.id),
                trailingIcon: PhosphorIconsRegular.trash,
                trailingColor: theme.error,
                trailingLabel: 'Delete',
                onTrailing: () => ref.read(userPlaylistsProvider.notifier).delete(p.id),
                child: _buildPlaylistRow(context, theme, p, isLocal: true, index: i),
              );
            },
            onReorder: (a, b) => ref.read(userPlaylistsProvider.notifier).reorder(a, b),
          ),
        ],
        if (likedLists.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Liked Playlists'),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: likedLists.length,
            itemBuilder: (context, i) {
              final p = likedLists[i];
              return SwipeActionRow(
                key: ValueKey<String>('liked_${p.id}'),
                trailingIcon: PhosphorIconsRegular.heartBreak,
                trailingColor: theme.error,
                trailingLabel: 'Unlike',
                onTrailing: () => ref.read(likedPlaylistsProvider.notifier).toggle(p),
                child: _buildPlaylistRow(context, theme, p, isLocal: false),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCreateButton(BuildContext context, AppTheme theme, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCreate(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(
            theme.cardRadius == 0 ? 0 : 12,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              PhosphorIconsRegular.plus,
              color: theme.background,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              'Create playlist',
              style: TextStyle(
                color: theme.background,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistRow(
    BuildContext context,
    AppTheme theme,
    DeezerPlaylist p, {
    required bool isLocal,
    int? index,
  }) {
    final hasCover = (p.pictureMedium ?? p.picture) != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(AppRoutes.playlistPath(p.id)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(
            theme.cardRadius == 0 ? 0 : 10,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: hasCover
                  ? CachedNetworkImage(
                      imageUrl: p.pictureMedium ?? p.picture!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => ColoredBox(color: theme.surface),
                      errorWidget: (_, _, _) => Icon(
                        PhosphorIconsRegular.musicNotes,
                        color: theme.onSurfaceMuted,
                      ),
                    )
                  : Icon(
                      PhosphorIconsRegular.musicNotes,
                      color: theme.onSurfaceMuted,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLocal
                        ? '${p.nbTracks ?? 0} tracks'
                        : 'Playlist · by ${p.creator?.name ?? 'Deezer'}',
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isLocal && index != null)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Icon(
                    PhosphorIconsRegular.dotsSixVertical,
                    color: theme.onSurfaceMuted,
                    size: 18,
                  ),
                ),
              )
            else if (isLocal)
              Icon(
                PhosphorIconsRegular.dotsSixVertical,
                color: theme.onSurfaceMuted,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final theme = AppThemeScope.of(context);
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'create',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: theme.normalDuration,
      pageBuilder: (_, _, _) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setLocal) => Container(
                margin: const EdgeInsets.fromLTRB(12, 80, 12, 24),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(
                    theme.cardRadius == 0 ? 0 : 18,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: theme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'New playlist',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _UnderlineField(
                      controller: nameCtrl,
                      hint: 'Playlist name',
                    ),
                    const SizedBox(height: 14),
                    _UnderlineField(
                      controller: descCtrl,
                      hint: 'Description (optional)',
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pop(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: theme.onSurfaceMuted,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (nameCtrl.text.trim().isEmpty) return;
                            await ref
                                .read(userPlaylistsProvider.notifier)
                                .create(
                                  title: nameCtrl.text.trim(),
                                  description: descCtrl.text.trim().isEmpty
                                      ? null
                                      : descCtrl.text.trim(),
                                  public: true,
                                );
                            if (context.mounted) {
                              Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pop();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'CREATE',
                              style: TextStyle(
                                color: theme.background,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildImportButton(BuildContext context, AppTheme theme, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openImport(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.onSurface.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(
            theme.cardRadius == 0 ? 0 : 12,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              PhosphorIconsRegular.downloadSimple,
              color: theme.onSurface,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              'Import playlist',
              style: TextStyle(
                color: theme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openImport(BuildContext context, WidgetRef ref) async {
    // Safe snackbar helper — swallows any Flutter internal assertion.
    void snack(String msg) {
      try {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } catch (_) {}
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    String? successTitle;
    String? errorMsg;
    try {
      final jsonStr = await File(path).readAsString();
      final pl = await PlaylistExchange.importFromJson(
        jsonStr,
        ref.read(userPlaylistsProvider.notifier),
        ref.read(localPlaylistTracksProvider.notifier),
      );
      successTitle = pl.title;
    } catch (e) {
      errorMsg = e.toString();
    }

    if (successTitle != null) {
      snack('Successfully imported "$successTitle"');
    } else {
      snack('Import failed: $errorMsg');
    }
  }
}

// ---------------------------------------------------------------------------
// Following ---------------------------------------------------------------

class _FollowingTab extends ConsumerWidget {
  const _FollowingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(followedArtistsProvider);
    if (artists.isEmpty) {
      return _EmptyHint(
        icon: PhosphorIconsRegular.user,
        title: 'No artists followed',
        subtitle: 'Follow an artist to see them here.',
      );
    }
    final cols = AppBreakpoints.isDesktop(context)
        ? 5
        : AppBreakpoints.isTablet(context)
            ? 4
            : 3;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.70,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) =>
          ArtistCircle(artist: artists[i], size: double.infinity),
    );
  }
}

// ---------------------------------------------------------------------------
// Downloads ---------------------------------------------------------------

enum _DownloadFilter { all, notInPlaylist, inPlaylist }

class _DownloadsTab extends ConsumerStatefulWidget {
  const _DownloadsTab();

  @override
  ConsumerState<_DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends ConsumerState<_DownloadsTab> {
  late final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _DownloadFilter _filter = _DownloadFilter.all;
  final Set<int> _selectedIds = <int>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _setFilter(_DownloadFilter filter) {
    setState(() {
      _filter = filter;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(int trackId) {
    setState(() {
      if (_selectedIds.contains(trackId)) {
        _selectedIds.remove(trackId);
      } else {
        _selectedIds.add(trackId);
      }
    });
  }

  void _enterSelection(int trackId) {
    setState(() {
      _selectedIds.add(trackId);
    });
  }

  void _selectAllVisible(List<DeezerTrack> visible) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(visible.map((track) => track.id));
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  void _openBulkAddSheet(List<DeezerTrack> downloaded) {
    final selectedTracks = downloaded
        .where((track) => _selectedIds.contains(track.id))
        .toList(growable: false);

    if (selectedTracks.isEmpty) return;

    showAddTracksToPlaylistSheet(context, selectedTracks);
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = ref.watch(downloadedTracksProvider);
    final queue = ref.watch(downloadQueueProvider);
    final tracksByPlaylist = ref.watch(localPlaylistTracksProvider);
    final playlistTrackIds = _downloadPlaylistTrackIds(tracksByPlaylist);
    final notInPlaylist = downloaded
        .where((track) => !playlistTrackIds.contains(track.id))
        .toList(growable: false);
    final inPlaylist = downloaded
        .where((track) => playlistTrackIds.contains(track.id))
        .toList(growable: false);

    final base = switch (_filter) {
      _DownloadFilter.all => downloaded,
      _DownloadFilter.notInPlaylist => notInPlaylist,
      _DownloadFilter.inPlaylist => inPlaylist,
    };
    final filtered = _filterDownloadedTracks(base, _query);

    final validIds = downloaded.map((track) => track.id).toSet();
    _selectedIds.removeWhere((id) => !validIds.contains(id));

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _DownloadQueueCard(queue: queue),
        const _DownloadLocationCard(),
        if (downloaded.isEmpty && !queue.hasItems)
          _EmptyHint(
            icon: PhosphorIconsRegular.cloudArrowDown,
            title: 'No downloads',
            subtitle: 'Downloaded tracks for offline play will appear here.',
          )
        else if (downloaded.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Download manager',
              style: TextStyle(
                color: AppThemeScope.of(context).onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _DownloadKpiStrip(
            downloadedCount: downloaded.length,
            notInPlaylistCount: notInPlaylist.length,
            inPlaylistCount: inPlaylist.length,
            playlistCount: ref.watch(userPlaylistsProvider).length,
            activeFilter: _filter,
            onTap: _setFilter,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: _DownloadsSearchField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              onClear: _query.isEmpty
                  ? null
                  : () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
            ),
          ),
          if (_selectionMode)
            _BulkSelectionBar(
              selectedCount: _selectedIds.length,
              visibleCount: filtered.length,
              onAddToPlaylist: () => _openBulkAddSheet(downloaded),
              onSelectAll: () => _selectAllVisible(filtered),
              onClear: _clearSelection,
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Long press any downloaded song or use the checkboxes to select multiple songs.',
                style: TextStyle(
                  color: AppThemeScope.of(context).onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (filtered.isEmpty)
            _EmptyHint(
              icon: PhosphorIconsRegular.magnifyingGlass,
              title: 'No downloaded songs found',
              subtitle: _filter == _DownloadFilter.notInPlaylist
                  ? 'Everything downloaded is already inside a playlist.'
                  : 'Try title, artist, album, or a close spelling.',
            )
          else
            ...List<Widget>.generate(filtered.length, (i) {
              final t = filtered[i];
              return _DownloadedTrackTile(
                track: t,
                queue: filtered,
                indexInQueue: i,
                selected: _selectedIds.contains(t.id),
                selectionMode: _selectionMode,
                onToggleSelected: () => _toggleSelected(t.id),
                onEnterSelection: () => _enterSelection(t.id),
              );
            }),
        ],
      ],
    );
  }
}

Set<int> _downloadPlaylistTrackIds(
  Map<int, List<DeezerTrack>> tracksByPlaylist,
) {
  final ids = <int>{};
  for (final tracks in tracksByPlaylist.values) {
    for (final track in tracks) {
      ids.add(track.id);
    }
  }
  return ids;
}

List<DeezerTrack> _filterDownloadedTracks(
  List<DeezerTrack> tracks,
  String rawQuery,
) {
  final query = _normaliseSearch(rawQuery);
  if (query.isEmpty) return tracks;

  final queryParts = query.split(' ').where((p) => p.isNotEmpty).toList();
  final scored = <({DeezerTrack track, int score})>[];

  for (final track in tracks) {
    final haystack = _normaliseSearch(
      '${track.title} ${track.artist?.name ?? ''} ${track.album?.title ?? ''}',
    );

    var score = 0;
    if (haystack.contains(query)) score += 1000;

    for (final part in queryParts) {
      if (haystack.contains(part)) {
        score += 120;
      } else {
        final words = haystack.split(' ').where((w) => w.isNotEmpty);
        var best = 999;
        for (final word in words) {
          final d = _levenshteinDistance(word, part);
          if (d < best) best = d;
        }
        if (part.length >= 4 && best <= 1) {
          score += 70;
        } else if (part.length >= 5 && best <= 2) {
          score += 45;
        }
      }
    }

    if (score > 0) scored.add((track: track, score: score));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.map((item) => item.track).toList(growable: false);
}

String _normaliseSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final previous = List<int>.generate(b.length + 1, (i) => i);
  final current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      current[j + 1] = <int>[
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    for (var j = 0; j < previous.length; j++) {
      previous[j] = current[j];
    }
  }

  return previous[b.length];
}

class _DownloadKpiStrip extends StatelessWidget {
  const _DownloadKpiStrip({
    required this.downloadedCount,
    required this.notInPlaylistCount,
    required this.inPlaylistCount,
    required this.playlistCount,
    required this.activeFilter,
    required this.onTap,
  });

  final int downloadedCount;
  final int notInPlaylistCount;
  final int inPlaylistCount;
  final int playlistCount;
  final _DownloadFilter activeFilter;
  final ValueChanged<_DownloadFilter> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          _DownloadKpiCard(
            label: 'Downloaded',
            value: downloadedCount,
            icon: PhosphorIconsFill.cloudCheck,
            active: activeFilter == _DownloadFilter.all,
            onTap: () => onTap(_DownloadFilter.all),
          ),
          _DownloadKpiCard(
            label: 'Not in playlist',
            value: notInPlaylistCount,
            icon: PhosphorIconsRegular.warningCircle,
            active: activeFilter == _DownloadFilter.notInPlaylist,
            onTap: () => onTap(_DownloadFilter.notInPlaylist),
          ),
          _DownloadKpiCard(
            label: 'In playlists',
            value: inPlaylistCount,
            icon: PhosphorIconsRegular.playlist,
            active: activeFilter == _DownloadFilter.inPlaylist,
            onTap: () => onTap(_DownloadFilter.inPlaylist),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(
                theme.cardRadius == 0 ? 0 : 16,
              ),
              border: Border.all(
                color: theme.onSurface.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  PhosphorIconsRegular.listBullets,
                  color: theme.onSurfaceMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  '$playlistCount playlists',
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadKpiCard extends StatelessWidget {
  const _DownloadKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final border = active ? theme.accent : theme.onSurface.withValues(alpha: 0.10);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: theme.fastDuration,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? theme.accent.withValues(alpha: 0.12)
              : theme.surface,
          borderRadius: BorderRadius.circular(
            theme.cardRadius == 0 ? 0 : 16,
          ),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              color: active ? theme.accent : theme.onSurfaceMuted,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              '$value',
              style: TextStyle(
                color: active ? theme.accent : theme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? theme.onSurface : theme.onSurfaceMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkSelectionBar extends StatelessWidget {
  const _BulkSelectionBar({
    required this.selectedCount,
    required this.visibleCount,
    required this.onAddToPlaylist,
    required this.onSelectAll,
    required this.onClear,
  });

  final int selectedCount;
  final int visibleCount;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 16),
        border: Border.all(color: theme.accent.withValues(alpha: 0.55)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              '$selectedCount selected',
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _SmallActionButton(
            label: 'Add to playlist',
            icon: PhosphorIconsRegular.playlist,
            onTap: onAddToPlaylist,
            filled: true,
          ),
          _SmallActionButton(
            label: 'Select visible ($visibleCount)',
            icon: PhosphorIconsRegular.checks,
            onTap: onSelectAll,
          ),
          _SmallActionButton(
            label: 'Clear',
            icon: PhosphorIconsRegular.x,
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}

class _DownloadsSearchField extends StatelessWidget {
  const _DownloadsSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: theme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: 'Search downloaded songs...',
        hintStyle: TextStyle(
          color: theme.onSurfaceMuted,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(
          PhosphorIconsRegular.magnifyingGlass,
          color: theme.onSurfaceMuted,
        ),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                icon: Icon(
                  PhosphorIconsRegular.x,
                  color: theme.onSurfaceMuted,
                ),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: theme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 16),
          borderSide: BorderSide(
            color: theme.onSurface.withValues(alpha: 0.10),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 16),
          borderSide: BorderSide(
            color: theme.onSurface.withValues(alpha: 0.10),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 16),
          borderSide: BorderSide(
            color: theme.accent.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _DownloadedTrackTile extends ConsumerWidget {
  const _DownloadedTrackTile({
    required this.track,
    required this.queue,
    required this.indexInQueue,
    required this.selected,
    required this.selectionMode,
    required this.onToggleSelected,
    required this.onEnterSelection,
  });

  final DeezerTrack track;
  final List<DeezerTrack> queue;
  final int indexInQueue;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onToggleSelected;
  final VoidCallback onEnterSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final playlists = ref.watch(playlistsForTrackProvider(track.id));
    final inPlaylist = playlists.isNotEmpty;
    final cover = track.album?.coverMedium ??
        track.album?.cover ??
        track.album?.coverSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selectionMode
              ? onToggleSelected
              : () => ref
                  .read(playerControlsProvider)
                  .playTracks(queue, startIndex: indexInQueue),
          onLongPress: onEnterSelection,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? theme.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(
                theme.cardRadius == 0 ? 0 : 14,
              ),
              border: Border.all(
                color: selected
                    ? theme.accent.withValues(alpha: 0.65)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelected(),
                  visualDensity: VisualDensity.compact,
                ),
                ClipRRect(
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
                                ColoredBox(color: theme.surface),
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: theme.surface),
                          )
                        : ColoredBox(
                            color: theme.surface,
                            child: Icon(
                              PhosphorIconsRegular.musicNotes,
                              color: theme.onSurfaceMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist?.name ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.onSurfaceMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!selectionMode)
                  Icon(
                    PhosphorIconsFill.cloudCheck,
                    color: theme.accent,
                    size: 16,
                  )
                else
                  Icon(
                    selected
                        ? PhosphorIconsFill.checkCircle
                        : PhosphorIconsRegular.circle,
                    color: selected ? theme.accent : theme.onSurfaceMuted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
        if (inPlaylist)
          Padding(
            padding: const EdgeInsets.fromLTRB(88, 0, 16, 6),
            child: Text(
              'In playlist: ${_playlistPreview(playlists)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(88, 0, 16, 6),
            child: Text(
              'Not in any playlist',
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (!selectionMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(88, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: _SmallActionButton(
                label: inPlaylist ? 'Manage playlists' : 'Add to playlist',
                icon: PhosphorIconsRegular.playlist,
                onTap: () => showAddToPlaylistSheet(context, track),
                filled: true,
              ),
            ),
          ),
      ],
    );
  }
}

String _playlistPreview(List<DeezerPlaylist> playlists) {
  if (playlists.length <= 2) {
    return playlists.map((p) => p.title).join(', ');
  }
  return '${playlists.take(2).map((p) => p.title).join(', ')} +${playlists.length - 2}';
}

class _DownloadQueueCard extends ConsumerWidget {
  const _DownloadQueueCard({required this.queue});

  final DownloadQueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!queue.hasItems) return const SizedBox.shrink();

    final theme = AppThemeScope.of(context);
    final current = queue.current;
    final progress = queue.overallProgress;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 18),
        border: Border.all(color: theme.onSurface.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                queue.running
                    ? PhosphorIconsRegular.downloadSimple
                    : PhosphorIconsFill.cloudCheck,
                color: theme.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  queue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: theme.onSurface.withValues(alpha: 0.08),
              color: theme.accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Downloaded: ${queue.downloaded} / ${queue.total}   '
            'Failed: ${queue.failed}   '
            'Skipped: ${queue.skipped}   '
            'Waiting: ${queue.waiting}',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (current != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Current: ${current.title} - ${current.status.label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: current.status == DownloadItemStatus.resolving
                    ? null
                    : current.progress.clamp(0.0, 1.0),
                backgroundColor: theme.onSurface.withValues(alpha: 0.08),
                color: theme.accent.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _currentDownloadDetail(current),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (queue.failed > 0) ...<Widget>[
            const SizedBox(height: 10),
            ...queue.items
                .where((item) => item.status == DownloadItemStatus.failed)
                .take(3)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          PhosphorIconsRegular.warningCircle,
                          color: theme.onSurfaceMuted,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${item.title}: ${item.error ?? 'Failed'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.onSurfaceMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (queue.running)
                _SmallActionButton(
                  label: 'Cancel',
                  icon: PhosphorIconsRegular.x,
                  onTap: () => ref.read(downloadManagerProvider).cancelQueue(),
                ),
              if (!queue.running && (queue.failed > 0 || queue.cancelled > 0))
                _SmallActionButton(
                  label: 'Retry failed',
                  icon: PhosphorIconsRegular.clockCounterClockwise,
                  onTap: () => ref.read(downloadManagerProvider).retryFailed(),
                  filled: true,
                ),
              if (!queue.running)
                _SmallActionButton(
                  label: 'Clear finished',
                  icon: PhosphorIconsRegular.trash,
                  onTap: () =>
                      ref.read(downloadManagerProvider).clearFinishedQueue(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadLocationCard extends ConsumerStatefulWidget {
  const _DownloadLocationCard();

  @override
  ConsumerState<_DownloadLocationCard> createState() =>
      _DownloadLocationCardState();
}

class _DownloadLocationCardState extends ConsumerState<_DownloadLocationCard> {
  bool _exporting = false;

  Future<void> _exportBackup() async {
    if (_exporting) return;

    setState(() => _exporting = true);

    try {
      final result = await ref
          .read(downloadManagerProvider)
          .exportDownloadsBackup();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloads exported: ${result.filesCopied} files · '
            '${_formatBytes(result.bytesCopied)} → '
            'Internal storage/Download/WAVE/wave_downloads',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not export to Internal storage/Download/WAVE/wave_downloads. '
            'Android may have blocked public Download folder access on this device. $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    if (!Platform.isAndroid) {
      final locationAsync = ref.watch(downloadLocationProvider);

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 14),
          border: Border.all(color: theme.onSurface.withValues(alpha: 0.10)),
        ),
        child: locationAsync.when(
          loading: () => Text(
            'Finding download folder...',
            style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
          ),
          error: (_, _) => Text(
            'Could not show download folder',
            style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
          ),
          data: (path) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Download folder',
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                path,
                style: TextStyle(color: theme.onSurfaceMuted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              _SmallActionButton(
                label: 'Open folder',
                icon: PhosphorIconsRegular.folderOpen,
                onTap: () async {
                  try {
                    await ref.read(downloadManagerProvider).openDownloadsFolder();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 14),
        border: Border.all(color: theme.onSurface.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Downloads backup',
            style: TextStyle(
              color: theme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'WAVE keeps songs in private app storage so offline playback works.',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Export backup copies them to:',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Internal storage/Download/WAVE/wave_downloads',
            style: TextStyle(
              color: theme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          _SmallActionButton(
            label: _exporting ? 'Exporting...' : 'Export backup',
            icon: PhosphorIconsRegular.export,
            onTap: _exporting ? () {} : _exportBackup,
            filled: true,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This is a copy/backup. WAVE will still play from its private folder.',
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _currentDownloadDetail(DownloadQueueItem item) {
  final percent = (item.progress.clamp(0.0, 1.0) * 100).floor();

  if (item.status == DownloadItemStatus.resolving) {
    return 'Finding playable YouTube audio';
  }

  if (item.status == DownloadItemStatus.downloading) {
    final bytes = _formatBytes(item.receivedBytes);
    final speed = _formatSpeed(item.bytesPerSecond);
    if (item.totalBytes > 0) {
      final total = _formatBytes(item.totalBytes);
      final eta = _etaText(item);
      return '$percent% · $bytes / $total · $speed$eta';
    }
    return '$percent% · $bytes downloaded · $speed';
  }

  if (item.status == DownloadItemStatus.failed && item.error != null) {
    return item.error!;
  }

  return '${item.status.label} · $percent%';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';

  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 100 ? 1 : 0)} KB';
  }

  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb < 100 ? 1 : 0)} MB';
  }

  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

String _formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return 'starting...';
  final kb = bytesPerSecond / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 100 ? 1 : 0)} KB/s';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB/s';
}

String _etaText(DownloadQueueItem item) {
  if (item.totalBytes <= 0 ||
      item.receivedBytes <= 0 ||
      item.bytesPerSecond <= 0 ||
      item.receivedBytes >= item.totalBytes) {
    return '';
  }

  final seconds = ((item.totalBytes - item.receivedBytes) / item.bytesPerSecond)
      .ceil();
  if (seconds <= 0) return '';

  if (seconds < 60) {
    return ' · ${seconds}s left';
  }

  final minutes = (seconds / 60).ceil();
  return ' · ${minutes}m left';
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final fg = filled ? theme.background : theme.onSurface;
    final bg = filled ? theme.accent : theme.surface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: filled
                ? theme.accent
                : theme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers -----------------------------------------------------------------

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: theme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.accent.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: Icon(icon, color: theme.accent, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: theme.onSurfaceMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final fg = filled ? theme.background : theme.onSurface;
    final bg = filled ? theme.accent : theme.surface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: filled
                ? theme.accent
                : theme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.onSurface.withValues(alpha: 0.2),
            width: 1.4,
          ),
        ),
      ),
      child: TextField(
        controller: controller,
        cursorColor: theme.accent,
        cursorWidth: 1.5,
        style: TextStyle(
          color: theme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(
            color: theme.onSurfaceMuted,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
