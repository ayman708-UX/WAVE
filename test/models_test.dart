import 'package:flutter_test/flutter_test.dart';
import 'package:wave/core/api/models/deezer_album.dart';
import 'package:wave/core/api/models/deezer_artist.dart';
import 'package:wave/core/api/models/deezer_playlist.dart';
import 'package:wave/core/api/models/deezer_track.dart';

void main() {
  group('DeezerArtist', () {
    test('fromJson maps required + snake_case fields', () {
      final a = DeezerArtist.fromJson(<String, dynamic>{
        'id': 27,
        'name': 'Daft Punk',
        'picture_medium': 'https://example/pm.jpg',
        'nb_fan': 12345,
      });
      expect(a.id, 27);
      expect(a.name, 'Daft Punk');
      expect(a.pictureMedium, 'https://example/pm.jpg');
      expect(a.nbFan, 12345);
    });

    test('fromJson tolerates missing optional fields', () {
      final a = DeezerArtist.fromJson(<String, dynamic>{'id': 1, 'name': 'X'});
      expect(a.pictureBig, isNull);
      expect(a.nbAlbum, isNull);
    });
  });

  group('DeezerAlbum', () {
    test('fromJson decodes nested artist', () {
      final album = DeezerAlbum.fromJson(<String, dynamic>{
        'id': 100,
        'title': 'Discovery',
        'cover_xl': 'https://example/xl.jpg',
        'release_date': '2001-03-12',
        'nb_tracks': 14,
        'artist': <String, dynamic>{'id': 27, 'name': 'Daft Punk'},
      });
      expect(album.id, 100);
      expect(album.title, 'Discovery');
      expect(album.coverXl, 'https://example/xl.jpg');
      expect(album.releaseDate, '2001-03-12');
      expect(album.nbTracks, 14);
      expect(album.artist?.name, 'Daft Punk');
    });
  });

  group('DeezerTrack', () {
    test('fromJson decodes album + artist', () {
      final t = DeezerTrack.fromJson(<String, dynamic>{
        'id': 3135556,
        'title': 'Harder, Better, Faster, Stronger',
        'duration': 224,
        'preview': 'https://example/preview.mp3',
        'explicit_lyrics': false,
        'artist': <String, dynamic>{'id': 27, 'name': 'Daft Punk'},
        'album': <String, dynamic>{'id': 302127, 'title': 'Discovery'},
      });
      expect(t.id, 3135556);
      expect(t.duration, 224);
      expect(t.explicitLyrics, false);
      expect(t.artist?.id, 27);
      expect(t.album?.title, 'Discovery');
    });
  });

  group('DeezerPlaylist', () {
    test('fromJson decodes basic fields', () {
      final p = DeezerPlaylist.fromJson(<String, dynamic>{
        'id': 908622995,
        'title': 'Top Hits',
        'nb_tracks': 50,
        'picture_big': 'https://example/p.jpg',
      });
      expect(p.id, 908622995);
      expect(p.title, 'Top Hits');
      expect(p.nbTracks, 50);
      expect(p.pictureBig, 'https://example/p.jpg');
    });
  });
}
