import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  final search = await yt.search.search('Everlong Foo Fighters');
  print('Video ID: ${search.first.id.value}');
  yt.close();
}
