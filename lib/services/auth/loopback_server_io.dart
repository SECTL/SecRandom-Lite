import 'dart:async';
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

        // 先把结果页写回浏览器，再异步处理换 token。
        // 否则 completeLogin 里的 cleanup 会 force-close，浏览器侧像连接被拒绝。
        unawaited(() async {
          try {
            await onRequest(request.uri);
          } catch (_) {
            // 登录 Completer 已收到错误；这里吞掉以避免未处理异常。
          }
        }());
        await _writeHtml(
          request.response,
          title: 'SECTL login complete',
          message: '授权已完成，现在可以关闭本页面并返回 SecRandom Lite。',
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
    // 不用 force：等在写的结果页先落盘，避免浏览器看到连接被重置。
    await _server?.close(force: false);
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
