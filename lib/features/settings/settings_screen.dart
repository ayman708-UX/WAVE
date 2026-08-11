import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/debrid_api.dart';
import '../../core/audio/player_providers.dart';
import '../../core/auth/supabase_auth_service.dart';
import '../../core/auth/supabase_profile_service.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/settings_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/themes.dart';
import '../../widgets/snap_horizontal_list.dart';
import '../../widgets/theme_morph.dart';
import '../../services/app_updater_service.dart';
import '../../widgets/update_dialog.dart';
import 'package:hive/hive.dart';
import '../../core/storage/hive_boxes.dart';
import '../../core/storage/library_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 80),
          physics: const BouncingScrollPhysics(),
          children: const <Widget>[
            _Header(),
            SizedBox(height: 24),
            _AccountSection(),
            SizedBox(height: 28),
            _SectionTitle('Audio Quality'),
            SizedBox(height: 12),
            _AudioQualityCard(),
            SizedBox(height: 28),
            _SectionTitle('Debrid Services'),
            SizedBox(height: 12),
            _DebridCard(),
            SizedBox(height: 28),
            _SectionTitle('Themes'),
            SizedBox(height: 12),
            _ThemeCarousel(),
            SizedBox(height: 28),
            _SectionTitle('Crossfade'),
            SizedBox(height: 12),
            _CrossfadeRow(),
            SizedBox(height: 28),
            _SectionTitle('Equalizer'),
            SizedBox(height: 12),
            _EqualizerCard(),
            SizedBox(height: 28),
            _SectionTitle('About'),
            SizedBox(height: 12),
            _AboutBlock(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'SETTINGS',
                style: TextStyle(
                  color: theme.onSurfaceMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Customize WAVE',
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              PhosphorIconsRegular.x,
              color: theme.onSurface,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: theme.onSurfaceMuted,
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: Border.all(color: theme.onSurface.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Account ------------------------------------------------------------------

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final authService = ref.read(supabaseAuthProvider);
    final isSignedIn = ref.watch(isSignedInProvider);
    final profileAsync = ref.watch(currentProfileProvider);

    if (!isSignedIn) {
      return _Card(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(AppRoutes.auth),
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent.withValues(alpha: 0.15),
                  border: Border.all(
                    color: theme.accent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  PhosphorIconsFill.userCircle,
                  color: theme.accent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Guest',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in to sync & share',
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sign In',
                  style: TextStyle(
                    color: theme.background,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Signed-in state
    final profile = profileAsync.value;
    final displayName = profile?['display_name'] ?? 'User';
    final username = profile?['username'] ?? '';
    final isPublicProfile = profile?['is_public'] == true;

    return Column(
      children: [
        _Card(
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent.withValues(alpha: 0.2),
                  border: Border.all(color: theme.accent, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    color: theme.accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await authService.signOut();
                  // Clear local library so the next user starts fresh
                  await Hive.box<dynamic>(HiveBoxes.playlists).clear();
                  await Hive.box<dynamic>(HiveBoxes.playlistTracks).clear();
                  await Hive.box<dynamic>(HiveBoxes.likedTracks).clear();
                  await Hive.box<dynamic>(HiveBoxes.likedAlbums).clear();
                  await Hive.box<dynamic>(HiveBoxes.followedArtists).clear();
                  await Hive.box<dynamic>(HiveBoxes.likedPlaylists).clear();

                  ref.invalidate(currentProfileProvider);
                  ref.invalidate(userPlaylistsProvider);
                  ref.invalidate(localPlaylistTracksProvider);
                  ref.invalidate(likedTracksProvider);
                  ref.invalidate(likedAlbumsProvider);
                  ref.invalidate(followedArtistsProvider);
                  ref.invalidate(likedPlaylistsProvider);
                },
                child: Icon(
                  PhosphorIconsRegular.signOut,
                  color: theme.onSurfaceMuted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Card(
          child: Row(
            children: <Widget>[
              Icon(
                isPublicProfile
                    ? PhosphorIconsRegular.globe
                    : PhosphorIconsRegular.lock,
                color: theme.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Public Profile',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      isPublicProfile
                          ? 'Anyone can see your playlists & library'
                          : 'Your profile is hidden from others',
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isPublicProfile,
                activeColor: theme.accent,
                onChanged: (val) async {
                  final svc = ref.read(supabaseProfileProvider);
                  await svc.updateProfile(isPublic: val);
                  ref.invalidate(currentProfileProvider);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Theme carousel ----------------------------------------------------------

class _ThemeCarousel extends ConsumerWidget {
  const _ThemeCarousel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = AppThemeScope.of(context);
    return SizedBox(
      height: 220,
      child: SnapHorizontalList(
        padding: EdgeInsets.zero,
        itemCount: AppThemes.all.length,
        itemExtent: 170,
        spacing: 14,
        itemBuilder: (context, i) {
          final t = AppThemes.all[i];
          return _ThemePreviewCard(theme: t, active: t.id == active.id);
        },
      ),
    );
  }
}

class _ThemePreviewCard extends ConsumerWidget {
  const _ThemePreviewCard({required this.theme, required this.active});
  final AppTheme theme;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTapDown: (details) {
        ref
            .read(themeMorphControllerProvider.notifier)
            .switchTo(target: theme.id, origin: details.globalPosition);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 170,
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 4 : 14),
          border: Border.all(
            color: active
                ? theme.accent
                : theme.onSurface.withValues(alpha: 0.18),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.45),
                    blurRadius: 24,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: CustomPaint(
          painter: _ThemeMockPainter(theme: theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(
                    theme.cardRadius == 0 ? 0 : 999,
                  ),
                ),
                child: Text(
                  theme.name.toUpperCase(),
                  style: TextStyle(
                    color: theme.background,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeMockPainter extends CustomPainter {
  _ThemeMockPainter({required this.theme});
  final AppTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final r = theme.cardRadius == 0 ? 0.0 : 6.0;
    RRect rrect(Offset o, double w, double h) => RRect.fromRectAndRadius(
      Rect.fromLTWH(o.dx, o.dy, w, h),
      Radius.circular(r),
    );
    // Top bar.
    canvas.drawRRect(
      rrect(const Offset(0, 0), size.width, 16),
      Paint()..color = theme.surface,
    );
    canvas.drawRRect(
      rrect(const Offset(4, 4), 60, 8),
      Paint()..color = theme.onSurface.withValues(alpha: 0.4),
    );
    // Cover grid (2x2).
    const cellPad = 6.0;
    final gridTop = 26.0;
    final cellSize = (size.width - cellPad) / 2;
    for (var i = 0; i < 4; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      final off = Offset(
        col * (cellSize + cellPad),
        gridTop + row * (cellSize * 0.55 + cellPad),
      );
      canvas.drawRRect(
        rrect(off, cellSize, cellSize * 0.5),
        Paint()
          ..color = i.isEven
              ? theme.accent.withValues(alpha: 0.7)
              : theme.onSurface.withValues(alpha: 0.18),
      );
    }
    // Bottom progress bar.
    final barY = gridTop + (cellSize * 0.55 + cellPad) * 2;
    canvas.drawRRect(
      rrect(Offset(0, barY), size.width, 6),
      Paint()..color = theme.onSurface.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      rrect(Offset(0, barY), size.width * 0.55, 6),
      Paint()..color = theme.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _ThemeMockPainter oldDelegate) =>
      oldDelegate.theme != theme;
}

// ---------------------------------------------------------------------------
// Crossfade ----------------------------------------------------------------

class _CrossfadeRow extends ConsumerWidget {
  const _CrossfadeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final value = ref.watch(appSettingsProvider).crossfadeSeconds.toDouble();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Crossfade between tracks',
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                value == 0 ? 'OFF' : '${value.toInt()}s',
                style: TextStyle(
                  color: value == 0 ? theme.onSurfaceMuted : theme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CustomLinearSlider(
            value: value / 12,
            onChanged: (v) {
              final secs = (v * 12).round();
              ref.read(appSettingsProvider.notifier).setCrossfadeSeconds(secs);
              ref.read(playerControlsProvider).setCrossfadeSeconds(secs);
            },
          ),
        ],
      ),
    );
  }
}

class _CustomLinearSlider extends StatelessWidget {
  const _CustomLinearSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        const trackH = 10.0;
        const thumbS = 18.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              onChanged((d.localPosition.dx / w).clamp(0.0, 1.0)),
          onHorizontalDragUpdate: (d) =>
              onChanged((d.localPosition.dx / w).clamp(0.0, 1.0)),
          onTapDown: (d) => onChanged((d.localPosition.dx / w).clamp(0.0, 1.0)),
          child: SizedBox(
            height: thumbS + 4,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                Container(
                  height: trackH,
                  decoration: BoxDecoration(
                    color: theme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(trackH),
                  ),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    height: trackH,
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: BorderRadius.circular(trackH),
                    ),
                  ),
                ),
                Positioned(
                  left: (value.clamp(0.0, 1.0) * w) - thumbS / 2,
                  child: Container(
                    width: thumbS,
                    height: thumbS,
                    decoration: BoxDecoration(
                      color: theme.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.accent, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Equalizer ----------------------------------------------------------------

class _EqualizerCard extends ConsumerWidget {
  const _EqualizerCard();

  static const List<String> _labels = <String>['60', '230', '910', '4K', '14K'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final bands = ref.watch(appSettingsProvider).equalizerBandsDb;
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 160,
            child: Row(
              children: <Widget>[
                for (var i = 0; i < bands.length; i++)
                  Expanded(
                    child: _EqBand(
                      index: i,
                      value: bands[i],
                      label: _labels[i],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '−12 dB  ·  +12 dB',
                style: TextStyle(color: theme.onSurfaceMuted, fontSize: 11),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await ref.read(appSettingsProvider.notifier).resetEqualizer();
                  await ref.read(playerControlsProvider).setEqualizer(
                    const <double>[0, 0, 0, 0, 0],
                  );
                },
                child: Text(
                  'RESET TO DEFAULT',
                  style: TextStyle(
                    color: theme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EqBand extends ConsumerWidget {
  const _EqBand({
    required this.index,
    required this.value,
    required this.label,
  });
  final int index;
  final double value;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight - 28;
        // Map -12..12 onto 0..1.
        final norm = ((value + 12) / 24).clamp(0.0, 1.0);
        return Column(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(d.globalPosition);
                  final normY = (1 - (local.dy / h)).clamp(0.0, 1.0);
                  final db = normY * 24 - 12;
                  ref
                      .read(appSettingsProvider.notifier)
                      .setEqualizerBand(index, db);
                  ref
                      .read(playerControlsProvider)
                      .setEqualizer(
                        ref.read(appSettingsProvider).equalizerBandsDb,
                      );
                },
                child: Center(
                  child: SizedBox(
                    width: 12,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: <Widget>[
                        Container(
                          decoration: BoxDecoration(
                            color: theme.onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          heightFactor: norm,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: <Color>[
                                  theme.accent,
                                  theme.accent.withValues(alpha: 0.5),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: norm * h - 6,
                          child: Container(
                            width: 18,
                            height: 12,
                            decoration: BoxDecoration(
                              color: theme.background,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: theme.accent, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}',
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// About --------------------------------------------------------------------

class _AboutBlock extends StatefulWidget {
  const _AboutBlock();

  @override
  State<_AboutBlock> createState() => _AboutBlockState();
}

class _AboutBlockState extends State<_AboutBlock> {
  bool _isCheckingForUpdates = false;

  Future<void> _checkForUpdates(BuildContext context) async {
    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();

      if (!context.mounted) return;

      if (updateInfo != null) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WAVE is up to date!'),
            backgroundColor: AppThemeScope.of(context).accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (context.mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(
                    theme.cardRadius == 0 ? 0 : 12,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'W',
                  style: TextStyle(
                    color: theme.background,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'WAVE',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'v1.0.8  ·  Build 9',
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isCheckingForUpdates
                  ? null
                  : () => _checkForUpdates(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accent.withValues(alpha: 0.1),
                foregroundColor: theme.accent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    theme.cardRadius == 0 ? 4 : 8,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isCheckingForUpdates
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.accent,
                      ),
                    )
                  : const Text(
                      'Check for Updates',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audio Quality Card --------------------------------------------------------

class _AudioQualityCard extends ConsumerWidget {
  const _AudioQualityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final currentQuality = ref.watch(appSettingsProvider).audioQuality;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                PhosphorIconsRegular.waveform,
                color: theme.accent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Audio Source & Quality',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Select preferred streaming and download quality',
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _QualityOptionTile(
                  title: 'YouTube',
                  subtitle: 'Fast streaming (Default)',
                  icon: PhosphorIconsRegular.youtubeLogo,
                  isSelected: currentQuality == AudioQuality.youtube,
                  onTap: () {
                    ref.read(appSettingsProvider.notifier).setAudioQuality(AudioQuality.youtube);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QualityOptionTile(
                  title: 'Lossless',
                  subtitle: 'FLAC via Octave',
                  icon: PhosphorIconsRegular.sparkle,
                  isSelected: currentQuality == AudioQuality.lossless,
                  onTap: () {
                    ref.read(appSettingsProvider.notifier).setAudioQuality(AudioQuality.lossless);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityOptionTile extends StatelessWidget {
  const _QualityOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? theme.accent.withValues(alpha: 0.15) : theme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.accent : theme.onSurface.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? theme.accent : theme.onSurfaceMuted,
                ),
                const Spacer(),
                if (isSelected)
                  Icon(
                    PhosphorIconsFill.checkCircle,
                    size: 16,
                    color: theme.accent,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebridCard extends StatefulWidget {
  const _DebridCard();

  @override
  State<_DebridCard> createState() => _DebridCardState();
}

class _DebridCardState extends State<_DebridCard> {
  String _selectedService = 'None';
  String? _rdUser;

  final _rdKeyCtrl = TextEditingController();
  final _torboxKeyCtrl = TextEditingController();
  final _alldebridKeyCtrl = TextEditingController();
  final _premiumizeKeyCtrl = TextEditingController();
  final _debridlinkKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllKeys();
  }

  Future<void> _loadAllKeys() async {
    final api = DebridApi();
    final service = await api.getDebridService() ?? 'None';
    final rd = await api.getRDAccessToken() ?? '';
    final tb = await api.getTorBoxKey() ?? '';
    final ad = await api.getAllDebridKey() ?? '';
    final pm = await api.getPremiumizeKey() ?? '';
    final dl = await api.getDebridLinkKey() ?? '';

    _rdKeyCtrl.text = rd;
    _torboxKeyCtrl.text = tb;
    _alldebridKeyCtrl.text = ad;
    _premiumizeKeyCtrl.text = pm;
    _debridlinkKeyCtrl.text = dl;

    if (rd.isNotEmpty) {
      final user = await api.verifyRDApiKey(rd);
      if (user != null) {
        _rdUser = user['username'] as String?;
      }
    }

    if (mounted) {
      setState(() {
        _selectedService = service;
      });
    }
  }

  @override
  void dispose() {
    _rdKeyCtrl.dispose();
    _torboxKeyCtrl.dispose();
    _alldebridKeyCtrl.dispose();
    _premiumizeKeyCtrl.dispose();
    _debridlinkKeyCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final services = ['None', 'Real-Debrid', 'TorBox', 'AllDebrid', 'Premiumize', 'Debrid-Link'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.cloudArrowUp, color: theme.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Active Debrid Provider',
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: services.contains(_selectedService) ? _selectedService : 'None',
            dropdownColor: theme.surface,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.onSurface.withValues(alpha: 0.1)),
              ),
            ),
            style: TextStyle(color: theme.onSurface, fontSize: 14),
            items: services.map((s) {
              return DropdownMenuItem<String>(
                value: s,
                child: Text(s),
              );
            }).toList(),
            onChanged: (val) async {
              if (val != null) {
                setState(() => _selectedService = val);
                await DebridApi().saveDebridService(val);
                if (val != 'None') {
                  final hasKey = await DebridApi().hasKeyForService(val);
                  if (!hasKey) {
                    _showSnack('$val selected, but has no API key saved yet. Please enter and save your API key below.');
                    return;
                  }
                }
                _showSnack('Active Debrid service set to $val');
              }
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Debrid services stream AudiobookBay audiobooks directly via high-speed cloud servers.',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: theme.onSurface.withValues(alpha: 0.08)),
          const SizedBox(height: 12),

          // Real-Debrid Field
          _buildKeyTile(
            title: 'Real-Debrid API Token',
            subtitle: _rdUser != null ? 'Logged in as $_rdUser' : 'Get token from real-debrid.com/apitoken',
            controller: _rdKeyCtrl,
            onSave: () async {
              final key = _rdKeyCtrl.text.trim();
              await DebridApi().saveRDApiKey(key);
              if (key.isNotEmpty) {
                if (_selectedService == 'None') {
                  setState(() => _selectedService = 'Real-Debrid');
                  await DebridApi().saveDebridService('Real-Debrid');
                }
                final user = await DebridApi().verifyRDApiKey(key);
                setState(() => _rdUser = user?['username'] as String?);
                if (user != null) {
                  _showSnack('Real-Debrid verified: Logged in as ${user['username']}');
                } else {
                  _showSnack('Real-Debrid API key saved, but verification failed.');
                }
              } else {
                setState(() => _rdUser = null);
                _showSnack('Real-Debrid API key cleared.');
              }
            },
            theme: theme,
          ),
          const SizedBox(height: 14),

          // TorBox Field
          _buildKeyTile(
            title: 'TorBox API Key',
            subtitle: 'Get key from torbox.app/settings',
            controller: _torboxKeyCtrl,
            onSave: () async {
              final key = _torboxKeyCtrl.text.trim();
              await DebridApi().saveTorBoxKey(key);
              if (key.isNotEmpty && _selectedService == 'None') {
                setState(() => _selectedService = 'TorBox');
                await DebridApi().saveDebridService('TorBox');
              }
              _showSnack(key.isNotEmpty ? 'TorBox API key saved and activated' : 'TorBox API key cleared');
            },
            theme: theme,
          ),
          const SizedBox(height: 14),

          // AllDebrid Field
          _buildKeyTile(
            title: 'AllDebrid API Key',
            subtitle: 'Get key from alldebrid.com/apikeys',
            controller: _alldebridKeyCtrl,
            onSave: () async {
              final key = _alldebridKeyCtrl.text.trim();
              await DebridApi().saveAllDebridKey(key);
              if (key.isNotEmpty && _selectedService == 'None') {
                setState(() => _selectedService = 'AllDebrid');
                await DebridApi().saveDebridService('AllDebrid');
              }
              _showSnack(key.isNotEmpty ? 'AllDebrid API key saved and activated' : 'AllDebrid API key cleared');
            },
            theme: theme,
          ),
          const SizedBox(height: 14),

          // Premiumize Field
          _buildKeyTile(
            title: 'Premiumize API Key',
            subtitle: 'Get key from premiumize.me/account',
            controller: _premiumizeKeyCtrl,
            onSave: () async {
              final key = _premiumizeKeyCtrl.text.trim();
              await DebridApi().savePremiumizeKey(key);
              if (key.isNotEmpty && _selectedService == 'None') {
                setState(() => _selectedService = 'Premiumize');
                await DebridApi().saveDebridService('Premiumize');
              }
              _showSnack(key.isNotEmpty ? 'Premiumize API key saved and activated' : 'Premiumize API key cleared');
            },
            theme: theme,
          ),
          const SizedBox(height: 14),

          // Debrid-Link Field
          _buildKeyTile(
            title: 'Debrid-Link API Key',
            subtitle: 'Get key from debrid-link.com/webapp/apikey',
            controller: _debridlinkKeyCtrl,
            onSave: () async {
              final key = _debridlinkKeyCtrl.text.trim();
              await DebridApi().saveDebridLinkKey(key);
              if (key.isNotEmpty && _selectedService == 'None') {
                setState(() => _selectedService = 'Debrid-Link');
                await DebridApi().saveDebridService('Debrid-Link');
              }
              _showSnack(key.isNotEmpty ? 'Debrid-Link API key saved and activated' : 'Debrid-Link API key cleared');
            },
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildKeyTile({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required VoidCallback onSave,
    required AppTheme theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: theme.onSurfaceMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: true,
                style: TextStyle(color: theme.onSurface, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste API Key / Token',
                  hintStyle: TextStyle(color: theme.onSurfaceMuted.withValues(alpha: 0.5), fontSize: 12),
                  filled: true,
                  fillColor: theme.background,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.onSurface.withValues(alpha: 0.1)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.background,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }
}

