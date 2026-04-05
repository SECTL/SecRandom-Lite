Uri getCurrentBrowserUri() => Uri.base;

String resolveCurrentWebAppUrl() {
  final uri = Uri.base;
  return uri
      .replace(queryParameters: <String, String>{}, fragment: '')
      .toString();
}

void clearBrowserOAuthParams() {}

Future<void> navigateBrowserTo(String url) async {
  throw UnsupportedError('Browser navigation is only available on web.');
}
