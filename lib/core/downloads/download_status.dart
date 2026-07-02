import '../api/models/deezer_track.dart';
import 'local_download_matcher.dart';

class DownloadCoverage {
  const DownloadCoverage({
    required this.total,
    required this.onDevice,
    required this.missingTracks,
  });

  final int total;
  final int onDevice;
  final List<DeezerTrack> missingTracks;

  int get missing => missingTracks.length;
  bool get hasTracks => total > 0;
  bool get allOnDevice => hasTracks && missing == 0;
  bool get noneOnDevice => hasTracks && onDevice == 0;
  bool get partiallyOnDevice => hasTracks && onDevice > 0 && missing > 0;
}

bool isTrackOnDevice(
  DeezerTrack track,
  List<DeezerTrack> downloadedTracks,
) {
  return LocalDownloadMatcher.findDownloadedMatchInList(
        track,
        downloadedTracks,
      ) !=
      null;
}

List<DeezerTrack> tracksMissingFromDevice(
  List<DeezerTrack> tracks,
  List<DeezerTrack> downloadedTracks,
) {
  final missing = <DeezerTrack>[];
  final seen = <int>{};

  for (final track in tracks) {
    if (!seen.add(track.id)) continue;
    if (!isTrackOnDevice(track, downloadedTracks)) {
      missing.add(track);
    }
  }

  return missing;
}

DownloadCoverage downloadCoverageForTracks(
  List<DeezerTrack> tracks,
  List<DeezerTrack> downloadedTracks,
) {
  final unique = <int, DeezerTrack>{};
  for (final track in tracks) {
    unique[track.id] = track;
  }

  if (unique.isEmpty) {
    return const DownloadCoverage(
      total: 0,
      onDevice: 0,
      missingTracks: <DeezerTrack>[],
    );
  }

  final missing = tracksMissingFromDevice(
    unique.values.toList(growable: false),
    downloadedTracks,
  );

  return DownloadCoverage(
    total: unique.length,
    onDevice: unique.length - missing.length,
    missingTracks: missing,
  );
}
