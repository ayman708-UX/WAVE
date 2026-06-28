import 'package:http/http.dart' as http;

class YoutubeStreamHttp {
  YoutubeStreamHttp._();

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  static const String androidUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

  static const String androidVrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.60.19 '
      '(Linux; U; Android 14; en_US; Quest 3; Build/UQ1A.240105.004) gzip';

  static const String iosUserAgent =
      'com.google.ios.youtube/20.10.4 '
      '(iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';

  static const String mobileWebUserAgent =
      'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36';

  static const String tvUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  static const String tvEmbeddedUserAgent =
      'Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  static bool isYoutubeCdnUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase();
    if (host == null) return false;
    return host == 'googlevideo.com' ||
        host.endsWith('.googlevideo.com') ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com');
  }

  static String userAgentForUrl(String url, {String? preferredUserAgent}) {
    if (preferredUserAgent != null && preferredUserAgent.isNotEmpty) {
      return preferredUserAgent;
    }

    final uri = Uri.tryParse(url);
    final client = uri?.queryParameters['c']?.toUpperCase();
    return switch (client) {
      'ANDROID_VR' => androidVrUserAgent,
      'ANDROID' || 'ANDROID_MUSIC' => androidUserAgent,
      'IOS' => iosUserAgent,
      'MWEB' => mobileWebUserAgent,
      'TVHTML5_SIMPLY_EMBEDDED_PLAYER' => tvEmbeddedUserAgent,
      'TVHTML5' => tvUserAgent,
      _ => desktopUserAgent,
    };
  }

  static Map<String, String> streamHeaders(
    String url, {
    String? userAgent,
    String? range,
  }) {
    final resolvedUserAgent = userAgentForUrl(
      url,
      preferredUserAgent: userAgent,
    );
    final uri = Uri.tryParse(url);
    final client = uri?.queryParameters['c']?.toUpperCase();

    final headers = <String, String>{
      'User-Agent': resolvedUserAgent,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (range != null) {
      headers['Range'] = range;
    }

    // Mobile and TV stream URLs are commonly rejected when browser-only
    // Origin/Referer headers are attached.
    if (client == 'WEB') {
      headers['Origin'] = 'https://www.youtube.com';
      headers['Referer'] = 'https://www.youtube.com/';
    }

    return headers;
  }

  static Future<bool> probe(
    String url, {
    String? userAgent,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..headers.addAll(
          streamHeaders(url, userAgent: userAgent, range: 'bytes=0-0'),
        );
      final response = await client.send(request).timeout(timeout);
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
