import 'package:universal_html/html.dart' as html;

Uri getCurrentBrowserUri() => Uri.base;

String resolveCurrentWebAppUrl() {
  final uri = Uri.base;
  return uri
      .replace(queryParameters: <String, String>{}, fragment: '')
      .toString();
}

void clearBrowserOAuthParams() {
  final uri = Uri.base.replace(
    queryParameters: <String, String>{},
    fragment: '',
  );
  html.window.history.replaceState(null, html.document.title, uri.toString());
}

Future<void> navigateBrowserTo(String url) async {
  html.window.location.assign(url);
}
