import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/deezer_track.dart';
import '../../core/audio/lyrics_service.dart';
import '../../core/audio/player_providers.dart';
import '../../core/theme/app_theme.dart';

/// Auto-scrolling lyrics view. Synced LRC: highlights the active line and
/// allows tap-to-seek. Plain text: scroll-only.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key, required this.track});
  final DeezerTrack track;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scroll = ScrollController();
  int _activeIndex = -1;
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final asyncLyrics = ref.watch(lyricsForTrackProvider(widget.track));
    final position = ref.watch(playerSnapshotProvider).position;
    return asyncLyrics.when(
      loading: () => Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: _BeatingDot(color: theme.accent),
        ),
      ),
      error: (e, _) => _Empty(message: 'Lyrics unavailable', theme: theme),
      data: (lyrics) {
        if (lyrics.isEmpty) {
          return _Empty(message: 'No lyrics for this track', theme: theme);
        }
        // Responsive sizing config
        final screenWidth = MediaQuery.of(context).size.width;
        final isWide = screenWidth > 600;
        final baseFontSize = isWide ? 24.0 : 20.0;
        final activeFontSize = isWide ? 36.0 : 28.0;
        final paddingHz = isWide ? screenWidth * 0.15 : 32.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewHeight = constraints.maxHeight;
            final halfHeight = viewHeight / 2.0;

            if (lyrics.synced) {
              int active = -1;
              for (var i = 0; i < lyrics.lines.length; i++) {
                if (lyrics.lines[i].timestamp <= position) {
                  active = i;
                } else {
                  break;
                }
              }
              if (active != _activeIndex) {
                _activeIndex = active;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_scroll.hasClients || active < 0) return;
                  final key = _lineKeys[active];
                  if (key != null && key.currentContext != null) {
                    Scrollable.ensureVisible(
                      key.currentContext!,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                    );
                  }
                });
              }
            }

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: paddingHz),
                      child: Column(
                        children: [
                          SizedBox(height: halfHeight),
                          for (var i = 0; i < lyrics.lines.length; i++)
                            Builder(
                              builder: (context) {
                                _lineKeys[i] ??= GlobalKey();
                                final line = lyrics.lines[i];
                                final isActive = lyrics.synced && i == _activeIndex;
                                return Container(
                                  key: _lineKeys[i],
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: lyrics.synced
                                        ? () => ref
                                            .read(playerControlsProvider)
                                            .seek(line.timestamp)
                                        : null,
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isActive
                                            ? theme.onSurface
                                            : theme.onSurface.withValues(alpha: 0.55),
                                        fontSize: isActive ? activeFontSize : baseFontSize,
                                        fontWeight:
                                            isActive ? FontWeight.w800 : FontWeight.w600,
                                        height: 1.5,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        child: Center(
                                          child: Text(
                                            line.text.isEmpty ? '• • •' : line.text,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          SizedBox(height: halfHeight),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Lyrics provided by LRCLIB',
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, required this.theme});
  final String message;
  final AppTheme theme;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            PhosphorIconsRegular.musicNote,
            color: theme.onSurfaceMuted,
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BeatingDot extends StatefulWidget {
  const _BeatingDot({required this.color});
  final Color color;
  @override
  State<_BeatingDot> createState() => _BeatingDotState();
}

class _BeatingDotState extends State<_BeatingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Transform.scale(
        scale: 0.6 + 0.4 * _c.value,
        child: Container(
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
