import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_logger.dart';

class Convertytmp3Client {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Origin': 'https://convertytmp3.org',
    'Referer': 'https://convertytmp3.org/',
  };

  static Future<String?> getStreamUrl(String videoId) async {
    try {
      appLogger.i('Convertytmp3: Starting flow for $videoId');

      // 1. Auth
      final authUrl = Uri.parse(
        'https://epsilon.epsiloncloud.org/api/v1/auth?_=${DateTime.now().millisecondsSinceEpoch}',
      );
      final authRes = await http.get(authUrl, headers: _headers);
      if (authRes.statusCode != 200) { appLogger.e('Ctmp3 auth fail: ${authRes.statusCode}'); return null; }

      final authJson = jsonDecode(authRes.body);
      final key = authJson['key'] as String?;
      if (key == null) { appLogger.e('Ctmp3 no key'); return null; }

      final authHeaders = Map<String, String>.from(_headers);
      authHeaders['Authorization'] = 'Bearer $key';

      // 2. Init
      final initUrl = Uri.parse(
        'https://epsilon.epsiloncloud.org/api/v1/init?_=${DateTime.now().millisecondsSinceEpoch}',
      );
      final initRes = await http.get(initUrl, headers: authHeaders);
      if (initRes.statusCode != 200) { appLogger.e('Ctmp3 init fail: ${initRes.statusCode}'); return null; }

      final initJson = jsonDecode(initRes.body);
      final convertURLStr = initJson['convertURL'] as String?;
      if (convertURLStr == null) { appLogger.e('Ctmp3 no convertURL'); return null; }

      // 3. Convert (with redirect loop)
      String currentConvertUrl =
          '$convertURLStr&v=$videoId&f=mp3&_=${DateTime.now().millisecondsSinceEpoch}';
      Map<String, dynamic>? convertJson;

      while (true) {
        final res = await http.get(
          Uri.parse(currentConvertUrl),
          headers: authHeaders,
        );
        if (res.statusCode != 200) { appLogger.e('Ctmp3 conv fail: ${res.statusCode}'); return null; }

        try {
          convertJson = jsonDecode(res.body);
        } catch (_) {
          appLogger.e('Ctmp3 conv JSON parse fail');
          return null; // Not JSON, usually HTML error page
        }

        if (convertJson != null &&
            convertJson['redirect'] == 1 &&
            convertJson['redirectURL'] != null &&
            (convertJson['redirectURL'] as String).isNotEmpty) {
          currentConvertUrl = convertJson['redirectURL'] as String;
          // Loop and fetch redirect
        } else {
          break;
        }
      }

      if (convertJson == null) { appLogger.e('Ctmp3 null convertJson'); return null; }

      String? dlUrl = convertJson['downloadURL'] as String?;
      final progressUrl = convertJson['progressURL'] as String?;

      if ((dlUrl == null || dlUrl.isEmpty) &&
          progressUrl != null &&
          progressUrl.isNotEmpty) {
        // Needs polling
        int status = 0;
        int polls = 0;
        while (status != 3) {
          polls++;
          if (polls > 15) { appLogger.e('Ctmp3 poll timeout'); return null; }
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          final progRes = await http.get(
            Uri.parse(progressUrl),
            headers: authHeaders,
          );
          if (progRes.statusCode != 200) { appLogger.e('Ctmp3 prog fail: ${progRes.statusCode}'); return null; }

          Map<String, dynamic>? progJson;
          try {
            progJson = jsonDecode(progRes.body);
          } catch (_) {
            appLogger.e('Ctmp3 prog JSON parse fail');
            return null;
          }

          if (progJson != null &&
              progJson['downloadURL'] != null &&
              (progJson['downloadURL'] as String).isNotEmpty) {
            dlUrl = progJson['downloadURL'] as String;
            break;
          } else if (progJson != null &&
              progJson['error'] != null &&
              progJson['error'] is int &&
              (progJson['error'] as int) > 0) {
            appLogger.e(
              'Convertytmp3: Error in progress polling: ${progJson['error']}',
            );
            return null;
          } else if (progJson != null && progJson['progress'] != null) {
            status = progJson['progress'] as int;
          }
        }
      }

      if (dlUrl != null && dlUrl.isNotEmpty) {
        // 4. Final Download URL
        final finalUrl = '$dlUrl&v=$videoId&f=mp3&r=convertytmp3.org';
        return finalUrl;
      } else {
        appLogger.e('Ctmp3 dlUrl empty: $convertJson');
      }
    } catch (e) {
      appLogger.w('Convertytmp3 stream extraction failed: $e');
    }
    return null;
  }
}
