import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final urls = [
    'https://fulllengthaudiobooks.com/?s=novel',
    'https://hotaudiobooks.com/?s=novel',
    'https://bookaudiobooks.com/?s=novel',
    'https://audiozaic.com/?s=novel',
    'https://audiobooks4soul.com/?s=novel',
    'https://goldenaudiobooks.com/?s=novel',
  ];

  for (final url in urls) {
    print('Testing $url');
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'});
      if (res.statusCode != 200) {
        print(' Failed ${res.statusCode}');
        continue;
      }
      
      final html = res.body;
      
      // We will look for <article or <div class="post"
      // Then inside we extract img src and a href.
      final matches = RegExp(r'(<article[\s\S]*?</article>|<div[^>]*class="[^"]*post[^"]*"[^>]*>[\s\S]*?</div>|<li[^>]*>[\s\S]*?</li>)', caseSensitive: false).allMatches(html);
      
      if (matches.isNotEmpty) {
        for (var i = 0; i < 2 && i < matches.length; i++) {
           final content = matches.elementAt(i).group(0)!;
           final imgExp = RegExp(r'<img[^>]*src="([^"]+)"');
           final imgSrc = imgExp.firstMatch(content)?.group(1);
           final aExp = RegExp(r'<a[^>]*href="([^"]+)"[^>]*>([^<]*)</a>');
           final aMatch = aExp.firstMatch(content);
           print(' Found item:');
           print('   Img src: $imgSrc');
           print('   Link: ${aMatch?.group(1)}');
        }
      } else {
        print(' No article/post/li found.');
      }
    } catch (e) {
      print(' Error: $e');
    }
  }
}
