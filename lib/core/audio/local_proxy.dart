import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';
import '../utils/youtube_stream_http.dart';

class LocalProxy {
  static HttpServer? _server;
  static int? _port;
  static bool get isRunning => _server != null;
  static int get port => _port ?? 0;

  static Future<void> start() async {
    if (isRunning) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      appLogger.i('LocalProxy listening on $_port');

      _server!.listen((HttpRequest request) async {
        final targetUrl = request.uri.queryParameters['url'];
        final userAgent = request.uri.queryParameters['ua'];

        if (targetUrl == null) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }

        try {
          final uri = Uri.parse(targetUrl);
          if (uri.scheme != 'http' && uri.scheme != 'https') {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
            return;
          }

          if (request.method == 'HEAD') {
            await _handleHead(request, uri, targetUrl, userAgent);
          } else {
            await _handleGet(request, uri, targetUrl, userAgent);
          }
        } catch (e) {
          appLogger.e('Proxy error: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      });
    } catch (e) {
      appLogger.e('Failed to start LocalProxy: $e');
    }
  }

  static Future<void> _handleGet(
    HttpRequest request,
    Uri uri,
    String targetUrl,
    String? userAgent,
  ) async {
    final client = http.Client();
    try {
      final response = await _send(
        client,
        'GET',
        uri,
        targetUrl,
        userAgent,
        range: request.headers.value('range'),
      );
      _copyResponseHeaders(response, request.response);
      request.response.statusCode = response.statusCode;
      await response.stream.pipe(request.response);
    } finally {
      client.close();
    }
  }

  static Future<void> _handleHead(
    HttpRequest request,
    Uri uri,
    String targetUrl,
    String? userAgent,
  ) async {
    final client = http.Client();
    try {
      // Some googlevideo URLs reject HEAD on Android while accepting a ranged
      // GET. Try HEAD first, then fall back to GET bytes=0-0 and return headers
      // only. This keeps media_kit happy without downloading the full file.
      var response = await _send(
        client,
        'HEAD',
        uri,
        targetUrl,
        userAgent,
        range: request.headers.value('range'),
      );

      if (response.statusCode >= 400) {
        await response.stream.drain<void>();
        response = await _send(
          client,
          'GET',
          uri,
          targetUrl,
          userAgent,
          range: 'bytes=0-0',
        );
      }

      _copyResponseHeaders(response, request.response);
      request.response.statusCode = response.statusCode;
      await response.stream.drain<void>();
      await request.response.close();
    } finally {
      client.close();
    }
  }

  static Future<http.StreamedResponse> _send(
    http.Client client,
    String method,
    Uri uri,
    String targetUrl,
    String? userAgent, {
    String? range,
  }) {
    final proxyRequest = http.Request(method, uri)
      ..followRedirects = true
      ..headers.addAll(
        YoutubeStreamHttp.streamHeaders(
          targetUrl,
          userAgent: userAgent,
          range: range,
        ),
      );
    return client.send(proxyRequest).timeout(const Duration(seconds: 20));
  }

  static void _copyResponseHeaders(
    http.StreamedResponse response,
    HttpResponse out,
  ) {
    response.headers.forEach((key, value) {
      if (const <String>{
        'accept-ranges',
        'cache-control',
        'content-encoding',
        'content-length',
        'content-range',
        'content-type',
        'etag',
        'expires',
        'last-modified',
      }.contains(key.toLowerCase())) {
        out.headers.set(key, value);
      }
    });
  }

  static Future<void> ensureRunning() async {
    if (isRunning && port > 0) return;
    await start();
  }

  static Future<void> restart() async {
    await stopAsync(force: true);
    await start();
  }

  static Future<void> stopAsync({bool force = false}) async {
    final server = _server;
    _server = null;
    _port = null;
    if (server == null) return;
    try {
      await server.close(force: force).timeout(const Duration(seconds: 2));
    } catch (e) {
      appLogger.w('LocalProxy stop timeout/error: $e');
    }
  }

  static void stop() {
    final server = _server;
    _server = null;
    _port = null;
    try {
      server?.close(force: true);
    } catch (_) {}
  }
}
