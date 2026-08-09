import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api/android_auto_browse.dart';
import 'api/audiobook_player_service.dart';
import 'api/audio_handler.dart';
import 'api/local_server_service.dart';
import 'api/music_player_service.dart';
import 'api/torrent_stream_service.dart';
import 'platform_flags.dart';
import 'screens/audiobook_screen.dart';
import 'services/playtorrio_cloud_sync_service.dart';
import 'services/android_background_policy_service.dart';
import 'utils/app_theme.dart';

/// Set when [AudioService.init] fails in [main]; shown once on the home screen.
String? audiobookAudioInitWarning;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AudiobookPlayerService().ensurePlayerListeners();
  unawaited(AudiobookPlayerService().ensurePlaybackRateLoaded());

  unawaited(_configureAudioSession());

  try {
    final audioHandler = await AudioService.init(
      builder: () => PlayTorrioAudioHandler(MusicPlayerService().player),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.playtorrio.stories.channel.audio',
        androidNotificationChannelName: 'Stories playback',
        androidNotificationChannelDescription:
            'Playback controls and now playing for Stories',
        androidNotificationIcon: 'drawable/ic_stat_stories',
        androidNotificationClickStartsActivity: true,
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        androidResumeOnClick: true,
        androidShowNotificationBadge: false,
        notificationColor: AppTheme.bgCard,
        preloadArtwork: true,
        fastForwardInterval: const Duration(seconds: 30),
        rewindInterval: const Duration(seconds: 15),
        androidBrowsableRootExtras: const {
          AndroidContentStyle.supportedKey: true,
          AndroidContentStyle.browsableHintKey:
              AndroidContentStyle.listItemHintValue,
          AndroidContentStyle.playableHintKey:
              AndroidContentStyle.listItemHintValue,
        },
      ),
    ).timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        throw TimeoutException('AudioService.init timed out');
      },
    );
    MusicPlayerService().setHandler(audioHandler);
    AudiobookPlayerService().attachHandler(audioHandler);
    unawaited(AndroidAutoBrowse.warmCache());
    debugPrint('[Stories] AudioService ready');
  } catch (e, st) {
    debugPrint('[Stories] AudioService failed: $e\n$st');
    audiobookAudioInitWarning =
        'Lock-screen notification unavailable ($e). Rebuild after running tool/patch_android.sh and tool/patch_audio_service.sh.';
  }

  runApp(const StoriesApp());

  if (platformIsAndroid) {
    unawaited(_requestAndroidStartupPermissions());
  }
  unawaited(_warmBackgroundEngines());
}

class StoriesApp extends StatelessWidget {
  const StoriesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stories',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.materialTheme,
      home: AudiobookScreen(initWarning: audiobookAudioInitWarning),
    );
  }
}

Future<void> _warmBackgroundEngines() async {
  try {
    await LocalServerService().start();
  } catch (e) {
    debugPrint('[Stories] LocalServer failed: $e');
  }

  unawaited(
    TorrentStreamService()
        .start()
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            debugPrint('[Stories] Torrent engine timed out');
            return false;
          },
        )
        .catchError((Object e, StackTrace st) {
          debugPrint('[Stories] Torrent engine failed: $e\n$st');
          return false;
        }),
  );
  unawaited(
    PlaytorrioCloudSyncService.instance.pullOnStartup().catchError((Object e) {
      debugPrint('[Stories] Cloud pull failed: $e');
    }),
  );
}

Future<void> _requestAndroidStartupPermissions() async {
  try {
    final notificationStatus = await Permission.notification.request();
    if (!notificationStatus.isGranted) {
      audiobookAudioInitWarning =
          'Enable notifications for Stories to show playback controls in the shade.';
    }
  } catch (e) {
    debugPrint('[Stories] Notification permission: $e');
  }

  try {
    final battery = AndroidBackgroundPolicyService.instance;
    if (!await battery.isBatteryUnrestricted()) {
      await battery.requestBatteryUnrestricted();
    }
  } catch (e) {
    debugPrint('[Stories] Battery optimization prompt: $e');
  }
}

Future<void> _configureAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    await session.setActive(true);
  } catch (e) {
    debugPrint('[Stories] AudioSession: $e');
  }
}
