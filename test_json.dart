import 'dart:convert';
import 'package:wave/core/api/models/deezer_album.dart';

void main() {
  final jsonStr =
      '{"id":1002561451,"title":"you seem pretty sad for a girl so in love","link":"https://www.deezer.com/album/1002561451","cover":"https://api.deezer.com/album/1002561451/image","cover_small":"https://cdn-images.dzcdn.net/images/cover/07d6896c8afea3a87dcf9381c3d0e6c7/56x56-000000-80-0-0.jpg","cover_medium":"https://cdn-images.dzcdn.net/images/cover/07d6896c8afea3a87dcf9381c3d0e6c7/250x250-000000-80-0-0.jpg","cover_big":"https://cdn-images.dzcdn.net/images/cover/07d6896c8afea3a87dcf9381c3d0e6c7/500x500-000000-80-0-0.jpg","cover_xl":"https://cdn-images.dzcdn.net/images/cover/07d6896c8afea3a87dcf9381c3d0e6c7/1000x1000-000000-80-0-0.jpg","md5_image":"07d6896c8afea3a87dcf9381c3d0e6c7","record_type":"album","tracklist":"https://api.deezer.com/album/1002561451/tracks","explicit_lyrics":true,"position":1,"artist":{"id":11152580,"name":"Olivia Rodrigo","link":"https://www.deezer.com/artist/11152580","picture":"https://api.deezer.com/artist/11152580/image","picture_small":"https://cdn-images.dzcdn.net/images/artist/2c9e480317183c037eaebcd7ba96daf4/56x56-000000-80-0-0.jpg","picture_medium":"https://cdn-images.dzcdn.net/images/artist/2c9e480317183c037eaebcd7ba96daf4/250x250-000000-80-0-0.jpg","picture_big":"https://cdn-images.dzcdn.net/images/artist/2c9e480317183c037eaebcd7ba96daf4/500x500-000000-80-0-0.jpg","picture_xl":"https://cdn-images.dzcdn.net/images/artist/2c9e480317183c037eaebcd7ba96daf4/1000x1000-000000-80-0-0.jpg","radio":true,"tracklist":"https://api.deezer.com/artist/11152580/top?limit=50","type":"artist"},"type":"album"}';

  try {
    final map = jsonDecode(jsonStr);
    final album = DeezerAlbum.fromJson(map);
    print('Success: ${album.title}');
  } catch (e, stack) {
    print('Error: $e\n$stack');
  }
}
