import 'models/deezer_track.dart';
import 'qobuz_music_service.dart';

export 'qobuz_music_service.dart';

/// Legacy alias routing to QobuzMusicService
class OctaveMusicService {
  static final OctaveMusicService instance = OctaveMusicService._internal();
  OctaveMusicService._internal();

  Future<({String url, Map<String, String> headers})?> resolveLosslessUrl(
    DeezerTrack track,
  ) {
    return QobuzMusicService.instance.resolveLosslessUrl(track);
  }
}
