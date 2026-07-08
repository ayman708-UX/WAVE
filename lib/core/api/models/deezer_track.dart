import 'package:freezed_annotation/freezed_annotation.dart';

import 'deezer_album.dart';
import 'deezer_artist.dart';
import 'bool_converter.dart';

part 'deezer_track.freezed.dart';
part 'deezer_track.g.dart';

/// A single playable track returned by the Deezer API.
@freezed
abstract class DeezerTrack with _$DeezerTrack {
  const factory DeezerTrack({
    required int id,
    required String title,
    @JsonKey(name: 'title_short') String? titleShort,
    @JsonKey(name: 'title_version') String? titleVersion,
    String? link,
    int? duration,
    int? rank,
    @JsonKey(
      name: 'explicit_lyrics',
      fromJson: boolFromJson,
      toJson: boolToJson,
    )
    bool? explicitLyrics,
    String? preview,
    DeezerArtist? artist,
    DeezerAlbum? album,
  }) = _DeezerTrack;

  factory DeezerTrack.fromJson(Map<String, dynamic> json) =>
      _$DeezerTrackFromJson(json);
}
