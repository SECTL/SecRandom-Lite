import 'package:universal_html/html.dart' as html;

Map<String, String> readBrowserCookies() {
  final raw = html.document.cookie;
  if (raw == null || raw.trim().isEmpty) {
    return const <String, String>{};
  }

  final result = <String, String>{};
  final parts = raw.split(';');
  for (final part in parts) {
    final separator = part.indexOf('=');
    if (separator <= 0) {
      continue;
    }

    final rawKey = part.substring(0, separator).trim();
    if (rawKey.isEmpty) {
      continue;
    }
    final rawValue = part.substring(separator + 1).trim();
    result[Uri.decodeComponent(rawKey)] = Uri.decodeComponent(rawValue);
  }
  return result;
}

Future<void> setBrowserCookie({
  required String key,
  required String value,
  required int maxAgeDays,
}) async {
  final maxAge = maxAgeDays * 24 * 60 * 60;
  final encodedKey = Uri.encodeComponent(key);
  final encodedValue = Uri.encodeComponent(value);
  final secure = html.window.location.protocol == 'https:' ? '; Secure' : '';
  html.document.cookie =
      '$encodedKey=$encodedValue; Max-Age=$maxAge; Path=/; SameSite=Lax$secure';
}

Future<void> deleteBrowserCookie(String key) async {
  final encodedKey = Uri.encodeComponent(key);
  final secure = html.window.location.protocol == 'https:' ? '; Secure' : '';
  html.document.cookie =
      '$encodedKey=${Uri.encodeComponent('')}; Max-Age=0; Path=/; SameSite=Lax$secure';
}
