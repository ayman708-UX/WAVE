import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final res = await http.get(
    Uri.parse('https://audiobookbay.lu/?s=novel'),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    },
  );

  final blocks = res.body.split('<div class="post">');
  print('Found ${blocks.length} blocks');
  
  for (int i = 1; i < blocks.length && i < 4; i++) {
    final block = blocks[i];
    
    final RegExp titleExp = RegExp(
        r'<div class="postTitle">\s*<h2>\s*<a href="([^"]+)"[^>]*>([^<]+)</a>',
        caseSensitive: false);
    final titleMatch = titleExp.firstMatch(block);
    
    final RegExp imgExp = RegExp(r'<img[^>]*src="([^"]+)"', caseSensitive: false);
    final imgMatch = imgExp.firstMatch(block);
    
    print('Title: ${titleMatch?.group(2)}');
    print('URL: ${titleMatch?.group(1)}');
    print('Image: ${imgMatch?.group(1)}');
    print('---');
  }
}
