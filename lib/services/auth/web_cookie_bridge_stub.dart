Map<String, String> readBrowserCookies() {
  return const <String, String>{};
}

Future<void> setBrowserCookie({
  required String key,
  required String value,
  required int maxAgeDays,
}) async {}

Future<void> deleteBrowserCookie(String key) async {}
