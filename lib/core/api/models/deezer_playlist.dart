import 'package:freezed_annotation/freezed_annotation.dart';

import 'deezer_user.dart';
import 'bool_converter.dart';

part 'deezer_playlist.freezed.dart';
part 'deezer_playlist.g.dart';

/// A Deezer playlist.
@freezed
abstract class DeezerPlaylist with _$DeezerPlaylist {
  const factory DeezerPlaylist({
    required int id,
    required String title,
    String? description,
    int? duration,
    @JsonKey(fromJson: boolFromJson, toJson: boolToJson) bool? public,
    @JsonKey(name: 'is_loved_track', fromJson: boolFromJson, toJson: boolToJson)
    bool? isLovedTrack,
    @JsonKey(fromJson: boolFromJson, toJson: boolToJson) bool? collaborative,
    @JsonKey(name: 'nb_tracks') int? nbTracks,
    int? fans,
    String? link,
    String? picture,
    @JsonKey(name: 'picture_small') String? pictureSmall,
    @JsonKey(name: 'picture_medium') String? pictureMedium,
    @JsonKey(name: 'picture_big') String? pictureBig,
    @JsonKey(name: 'picture_xl') String? pictureXl,
    DeezerUser? creator,
  }) = _DeezerPlaylist;

  factory DeezerPlaylist.fromJson(Map<String, dynamic> json) =>
      _$DeezerPlaylistFromJson(json);
}
