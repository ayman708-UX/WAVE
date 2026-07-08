import 'package:freezed_annotation/freezed_annotation.dart';
import 'deezer_playlist.dart';
import 'deezer_track.dart';

part 'community_playlist.freezed.dart';

@freezed
abstract class CommunityPlaylist with _$CommunityPlaylist {
  const factory CommunityPlaylist({
    required String id,
    required String userId,
    required String creatorName,
    required DeezerPlaylist playlist,
    required List<DeezerTrack> tracks,
    required DateTime createdAt,
  }) = _CommunityPlaylist;
}
