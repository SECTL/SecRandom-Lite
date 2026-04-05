import 'dart:convert';
import 'dart:io';

typedef LoopbackRequestHandler = Future<void> Function(Uri uri);

class AuthLoopbackServer {
  HttpServer? _server;

  Future<void> start({
    required String host,
    required int port,
    required String path,
    required LoopbackRequestHandler onRequest,
  }) async {
    _server = await HttpServer.bind(host, port, shared: true);
    _server!.listen((request) async {
      try {
        if (request.uri.path != path) {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        await onRequest(request.uri);
        await _writeHtml(
          request.response,
          title: 'SECTL login complete',
          message: 'You can return to SecRandom Lite now.',
        );
      } catch (_) {
        try {
          await _writeHtml(
            request.response,
            title: 'SECTL login failed',
            message:
                'The callback could not be completed. Return to the app and try again.',
            statusCode: HttpStatus.internalServerError,
          );
        } catch (_) {
          await request.response.close();
        }
      }
    });
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _writeHtml(
    HttpResponse response, {
    required String title,
    required String message,
    int statusCode = HttpStatus.ok,
  }) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.html;
    final escapedTitle = htmlEscape.convert(title);
    final escapedMessage = htmlEscape.convert(message);
    response.write('''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>$escapedTitle</title>
  </head>
  <body style="font-family: Arial, sans-serif; padding: 24px; line-height: 1.6;">
    <h2>$escapedTitle</h2>
    <p>$escapedMessage</p>
  </body>
</html>
''');
    await response.close();
  }
}
