import 'web_cookie_bridge_stub.dart'
    if (dart.library.html) 'web_cookie_bridge_web.dart'
    as impl;

Map<String, String> readBrowserCookies() {
  return impl.readBrowserCookies();
}

Future<void> setBrowserCookie({
  required String key,
  required String value,
  required int maxAgeDays,
}) {
  return impl.setBrowserCookie(key: key, value: value, maxAgeDays: maxAgeDays);
}

Future<void> deleteBrowserCookie(String key) {
  return impl.deleteBrowserCookie(key);
}
