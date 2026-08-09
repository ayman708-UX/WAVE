import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/models/audiobook.dart';

class AudiobookBayScraper {
  static const String _baseUrl = 'https://audiobookbay.lu';

  static Future<List<Audiobook>> search(String query) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/?s=${Uri.encodeComponent(query)}&cat=undefined%2Cundefined'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
      );

      final blocks = res.body.split('<div class="post">');
      final books = <Audiobook>[];
      
      for (int i = 1; i < blocks.length; i++) {
        final block = blocks[i];
        
        final RegExp titleExp = RegExp(
            r'<div class="postTitle">\s*<h2>\s*<a href="([^"]+)"[^>]*>([^<]+)</a>',
            caseSensitive: false);
        final titleMatch = titleExp.firstMatch(block);
        if (titleMatch == null) continue;
        
        var url = titleMatch.group(1)!;
        if (url.startsWith('/')) url = '$_baseUrl$url';

        final RegExp imgExp = RegExp(r'<img[^>]*src="([^"]+)"', caseSensitive: false);
        final imgMatch = imgExp.firstMatch(block);
        final coverImage = imgMatch?.group(1) ?? '';

        books.add(Audiobook(
          uuid: 'abb_${url.hashCode}',
          audioBookId: url,
          dynamicSlugId: url,
          title: titleMatch.group(2)!.trim(),
          coverImage: coverImage,
          source: 'audiobookbay',
          pageUrl: url,
        ));
      }
      return books;
    } catch (e) {
      debugPrint('AudiobookBay search error: $e');
      return [];
    }
  }

  static Future<List<AudiobookChapter>> getChapters(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
      );

      final RegExp hashExp = RegExp(
          r'Info Hash:</td>\s*<td[^>]*>\s*([a-fA-F0-9]{40})\s*</td>',
          caseSensitive: false);
      final hashMatch = hashExp.firstMatch(res.body);
      if (hashMatch == null) return [];

      final infoHash = hashMatch.group(1)!;

      final RegExp trackerExp = RegExp(
          r'(?:Announce URL|Tracker):</td>\s*<td[^>]*>\s*([^<]+?)\s*</td>',
          caseSensitive: false);
      
      final trackers = <String>[];
      for (final m in trackerExp.allMatches(res.body)) {
        trackers.add(m.group(1)!.trim());
      }

      // Generate base magnet URI
      final magnetUri = StringBuffer('magnet:?xt=urn:btih:$infoHash');
      for (final tr in trackers) {
        magnetUri.write('&tr=${Uri.encodeComponent(tr)}');
      }
      
      final magnetString = magnetUri.toString();

      // Extract files from the HTML table to build the chapters list
      // Audiobookbay lists files in a table usually like:
      // <tr><td>1. 01.mp3</td><td>10.5 MB</td></tr>
      // We'll use a regex to find audio files. We need their index in the torrent.
      
      final RegExp fileExp = RegExp(
          r'<tr>\s*<td>\s*(?:<img[^>]*>\s*)?([^<]+\.(?:mp3|m4b|m4a|aac|flac|ogg|opus|wav|wma))\s*</td>',
          caseSensitive: false);

      final chapters = <AudiobookChapter>[];
      int fileIndex = 0;
      for (final m in fileExp.allMatches(res.body)) {
        final filename = m.group(1)!.trim();
        chapters.add(AudiobookChapter(
          title: filename,
          url: magnetString, // The URL is the magnet link itself!
          isTorrent: true,
          torrentFileIndex: fileIndex,
        ));
        fileIndex++;
      }

      // If we couldn't parse the files from the HTML, just return one "Full Torrent" chapter
      if (chapters.isEmpty) {
        chapters.add(AudiobookChapter(
          title: 'Full Audiobook Torrent',
          url: magnetString,
          isTorrent: true,
          torrentFileIndex: 0,
        ));
      }

      return chapters;
    } catch (e) {
      debugPrint('AudiobookBay getChapters error: $e');
      return [];
    }
  }
}
