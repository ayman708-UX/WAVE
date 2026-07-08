import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../api/models/deezer_playlist.dart';
import '../api/models/deezer_track.dart';
import '../storage/library_providers.dart';

class PlaylistExchange {
  PlaylistExchange._();

  static Future<Directory> getExchangeDirectory() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    }
    return await getApplicationDocumentsDirectory();
  }

  static String serialize(DeezerPlaylist playlist, List<DeezerTrack> tracks) {
    final map = <String, dynamic>{
      'type': 'wave_playlist',
      'version': 1,
      'title': playlist.title,
      'description': playlist.description ?? '',
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static Future<File> exportToFile(
    DeezerPlaylist playlist,
    List<DeezerTrack> tracks,
  ) async {
    final jsonStr = serialize(playlist, tracks);
    final dir = await getExchangeDirectory();

    // Clean filename
    final safeTitle = playlist.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File('${dir.path}/wave_playlist_$safeTitle.json');
    await file.writeAsString(jsonStr);
    return file;
  }

  static Future<void> exportToClipboard(
    DeezerPlaylist playlist,
    List<DeezerTrack> tracks,
  ) async {
    final jsonStr = serialize(playlist, tracks);
    await Clipboard.setData(ClipboardData(text: jsonStr));
  }

  static Future<DeezerPlaylist> importFromJson(
    String jsonStr,
    UserPlaylistsNotifier userPlsNotifier,
    LocalPlaylistTracksNotifier tracksNotifier,
  ) async {
    final map = jsonDecode(jsonStr);
    if (map is! Map || map['type'] != 'wave_playlist') {
      throw const FormatException('Invalid WAVE playlist file.');
    }
    final title = map['title'] as String? ?? 'Imported Playlist';
    final description = map['description'] as String?;
    final rawTracks = map['tracks'] as List?;

    final tracks = <DeezerTrack>[];
    if (rawTracks != null) {
      for (final t in rawTracks) {
        if (t is Map) {
          tracks.add(DeezerTrack.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }

    // Create local playlist
    final pl = await userPlsNotifier.create(
      title: title,
      description: description,
    );

    // Add tracks to it
    for (final t in tracks) {
      await tracksNotifier.addTrack(pl.id, t);
    }

    return pl;
  }
}
