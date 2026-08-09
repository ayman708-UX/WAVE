import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

/// Minimal local proxy: Tokybook audio only (used alongside Audiobook Bay torrents).
class LocalServerService {
  static final LocalServerService _instance = LocalServerService._internal();
  factory LocalServerService() => _instance;
  LocalServerService._internal();

  HttpServer? _server;
  final Router _router = Router();
  int _port = 0;

  int get port => _port;
  String get baseUrl => 'http://127.0.0.1:$_port';

  Future<void> start() async {
    if (_server != null) return;

    _router.get('/toky-proxy', _handleTokyProxy);

    try {
      _server = await io.serve(_router.call, InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      debugPrint('[LocalServer] Started on $baseUrl');
    } catch (e) {
      debugPrint('[LocalServer] Error starting server: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  Future<Response> _handleTokyProxy(Request request) async {
    final params = request.url.queryParameters;
    final targetUrl = params['url'];
    final audiobookId = params['id'];
    final token = params['token'];
    final trackSrc = params['src'];

    if (targetUrl == null) return Response.notFound('Missing url');

    final baseUri = Uri.parse(targetUrl);
    final decodedPath = Uri.decodeComponent(baseUri.path);
    final finalUrl = Uri.https('tokybook.com', decodedPath).toString();

    final String finalTrackSrc;
    if (trackSrc != null) {
      finalTrackSrc = Uri.https('tokybook.com', Uri.decodeComponent(trackSrc)).path;
    } else {
      finalTrackSrc = '';
    }

    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
      'Referer': 'https://tokybook.com/',
      'Origin': 'https://tokybook.com',
      'Accept': '*/*',
      ...?audiobookId != null ? {'x-audiobook-id': audiobookId} : null,
      ...?token != null ? {'x-stream-token': token} : null,
      'x-track-src': finalTrackSrc,
    };

    try {
      final res = await http.get(Uri.parse(finalUrl), headers: headers);
      if (res.statusCode != 200) {
        return Response(res.statusCode, body: res.body);
      }

      if (targetUrl.endsWith('.m3u8')) {
        final baseDir = targetUrl.substring(0, targetUrl.lastIndexOf('/') + 1);
        final baseSrcDir =
            trackSrc?.substring(0, trackSrc.lastIndexOf('/') + 1) ?? '';

        final rewrittenLines = res.body.split('\n').map((line) {
          if (line.isEmpty || line.startsWith('#')) return line;
          final segmentUrl = line.startsWith('http') ? line : '$baseDir$line';
          final segmentSrc = line.startsWith('http') ? line : '$baseSrcDir$line';
          return getTokyProxyUrl(
            segmentUrl,
            audiobookId ?? '',
            token ?? '',
            segmentSrc,
          );
        }).toList();

        return Response.ok(
          rewrittenLines.join('\n'),
          headers: {'Content-Type': 'application/x-mpegURL'},
        );
      }

      return Response.ok(res.bodyBytes, headers: {
        'Content-Type': res.headers['content-type'] ?? 'video/mp2t',
        'Access-Control-Allow-Origin': '*',
      });
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  String getTokyProxyUrl(String url, String id, String token, String src) {
    return '$baseUrl/toky-proxy?url=${Uri.encodeComponent(url)}&id=$id&token=${Uri.encodeComponent(token)}&src=${Uri.encodeComponent(src)}';
  }
}
