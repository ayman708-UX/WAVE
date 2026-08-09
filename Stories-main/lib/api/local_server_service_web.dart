import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Web: no local Shelf server. Proxy helpers return the target URL; some
/// features that relied on localhost proxies may hit browser CORS limits.
class LocalServerService {
  static final LocalServerService _instance = LocalServerService._internal();
  factory LocalServerService() => _instance;
  LocalServerService._internal();

  int get port => 0;
  String get baseUrl => '';

  Future<void> start() async {
    debugPrint('[LocalServer] Web: local proxy server disabled');
  }

  String getTokyProxyUrl(String url, String id, String token, String src) {
    return url;
  }

  String getComicProxyUrl(String url) => url;

  String getJellyfinProxyUrl(String targetUrl, String authHeaderValue) {
    // No local proxy on web; caller should use direct URLs where CORS allows.
    return targetUrl;
  }

  String getHlsProxyUrl(String targetUrl, Map<String, String> headers) {
    return targetUrl;
  }

  Future<void> stop() async {}
}
