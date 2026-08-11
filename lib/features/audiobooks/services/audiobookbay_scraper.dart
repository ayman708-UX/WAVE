import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/api/debrid_api.dart';
import '../../../core/models/audiobook.dart';
import 'torrent_stream_service.dart';

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

      // Extract files from HTML page
      final RegExp fileExp = RegExp(
          r"(?:<td>|<li>|<code>|<pre>|class=\x22torrent_files\x22|class=\x22file_list\x22|>|\n|^)\s*([a-zA-Z0-9_\-\.\s\(\)\[\]\,']+\.(?:mp3|m4b|m4a|aac|flac|ogg|opus|wav|wma))",
          caseSensitive: false);

      final chapters = <AudiobookChapter>[];
      final seenFiles = <String>{};
      int fileIndex = 0;

      for (final m in fileExp.allMatches(res.body)) {
        final filename = m.group(1)!.trim();
        if (filename.isEmpty || !seenFiles.add(filename.toLowerCase())) continue;

        chapters.add(AudiobookChapter(
          title: filename,
          url: magnetString,
          isTorrent: true,
          torrentFileIndex: fileIndex,
        ));
        fileIndex++;
      }

      // If HTML scraping couldn't find multi-file chapters, auto-expand via Debrid or local Torrent engine
      if (chapters.length <= 1) {
        try {
          final activeDebrid = await DebridApi().getActiveDebridService();
          if (activeDebrid != null && activeDebrid.isNotEmpty) {
            final debridFiles = await DebridApi().resolveByService(activeDebrid, magnetString);
            if (debridFiles.isNotEmpty && debridFiles.length > 1) {
              chapters.clear();
              for (int i = 0; i < debridFiles.length; i++) {
                chapters.add(AudiobookChapter(
                  title: debridFiles[i].filename,
                  url: magnetString,
                  isTorrent: true,
                  torrentFileIndex: i,
                ));
              }
            }
          } else {
            // Debrid is OFF -> try local torrent engine metadata to extract all audio files
            final torrentFiles = await TorrentStreamService.instance.getTorrentAudioFiles(magnetString);
            if (torrentFiles.isNotEmpty && torrentFiles.length > 1) {
              chapters.clear();
              for (int i = 0; i < torrentFiles.length; i++) {
                final fileInfo = torrentFiles[i];
                final name = fileInfo.path.split('/').last.split('\\').last;
                chapters.add(AudiobookChapter(
                  title: name,
                  url: magnetString,
                  isTorrent: true,
                  torrentFileIndex: fileInfo.index,
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('AudiobookBay chapter auto-expansion error: $e');
        }
      }

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
