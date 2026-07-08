import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:window_manager/window_manager.dart';

import 'core/audio/media_kit_music_player_service.dart';
import 'core/audio/music_player_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/hive_boxes.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_notifier.dart';
import 'core/api/deezer_api_client.dart';
import 'core/api/lastfm_api_client.dart';
import 'core/api/supabase_client.dart';
import 'core/audio/local_proxy.dart';
import 'widgets/theme_morph.dart';

late final MediaKitMusicPlayerService _playerService;

/// Global key for showing snackbars from anywhere without a local context.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load configuration and check API availability
  await SupabaseApiClient.loadEnvAndInit();
  await DeezerApiClient.loadEnv();
  await LastfmApiClient.loadEnv();
  await DeezerApiClient.checkGeoRestriction();
  
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(550, 900), // Larger but reasonable mobile aspect ratio
      minimumSize: Size(400, 650),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  MediaKit.ensureInitialized();
  await HiveBoxes.openAll();
  await LocalProxy.start();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  _playerService = MediaKitMusicPlayerService();
  await AudioService.init(
    builder: () => _playerService,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.aymanasfour.wave.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        // Real audio backend: resolves YouTube audio for each Deezer track
        // (search "title + artist + lyrics") then streams via media_kit (libmpv).
        musicPlayerServiceProvider.overrideWith(
          (ref) => _playerService,
        ),
      ],
      child: const WaveApp(),
    ),
  );
}

class WaveApp extends ConsumerWidget {
  const WaveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return AppThemeScope(
      theme: theme,
      child: MaterialApp.router(
        title: 'WAVE',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: theme.toMaterialTheme(),
        routerConfig: appRouter,
        builder: (context, child) {
          return Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              const Positioned.fill(child: ThemeMorphOverlay()),
            ],
          );
        },
      ),
    );
  }
}
