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

          final client = http.Client();
          try {
            final range = request.headers.value('range');
            final proxyRequest = http.Request('GET', uri)
              ..followRedirects = true
              ..headers.addAll(
                YoutubeStreamHttp.streamHeaders(
                  targetUrl,
                  userAgent: userAgent,
                  range: range,
                ),
              );

            final response = await client.send(proxyRequest);
            request.response.statusCode = response.statusCode;

            // Copy media headers back to media_kit.
            response.headers.forEach((key, value) {
              if ([
                'accept-ranges',
                'cache-control',
                'content-encoding',
                'content-length',
                'content-range',
                'content-type',
                'etag',
                'expires',
                'last-modified',
              ].contains(key.toLowerCase())) {
                request.response.headers.set(key, value);
              }
            });

            if (request.method == 'HEAD') {
              await request.response.close();
            } else {
              await response.stream.pipe(request.response);
            }
          } finally {
            client.close();
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

  static void stop() {
    _server?.close();
    _server = null;
  }
}
