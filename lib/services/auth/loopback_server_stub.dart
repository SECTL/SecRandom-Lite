typedef LoopbackRequestHandler = Future<void> Function(Uri uri);

class AuthLoopbackServer {
  Future<void> start({
    required String host,
    required int port,
    required String path,
    required LoopbackRequestHandler onRequest,
  }) {
    throw UnsupportedError('Loopback callback server is not available here.');
  }

  Future<void> close() async {}
}
