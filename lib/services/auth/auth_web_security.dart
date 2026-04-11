import 'auth_config.dart';

Uri trustedAuthCallbackOrigin({required String callbackBridgeUrl}) {
  final callbackUri = Uri.parse(callbackBridgeUrl);
  return Uri.parse(callbackUri.origin);
}

bool isTrustedWebPopupCallbackMessage({
  required Object? messageType,
  required Object? href,
  required String eventOrigin,
  required bool isFromExpectedPopupWindow,
  String callbackBridgeUrl = AuthConfig.authCallbackBridgeUrl,
  String webAppUrl = AuthConfig.webAppUrl,
}) {
  if (messageType != 'sectl-auth-callback') {
    return false;
  }

  if (href is! String || href.isEmpty) {
    return false;
  }

  if (!isFromExpectedPopupWindow) {
    return false;
  }

  if (eventOrigin !=
      trustedAuthCallbackOrigin(callbackBridgeUrl: callbackBridgeUrl).origin) {
    return false;
  }

  return parseTrustedWebAppCallbackUri(href, webAppUrl: webAppUrl) != null;
}

Uri? parseTrustedWebAppCallbackUri(
  String href, {
  String webAppUrl = AuthConfig.webAppUrl,
}) {
  if (href.isEmpty) {
    return null;
  }

  final targetUri = Uri.tryParse(href);
  if (targetUri == null || !targetUri.hasScheme) {
    return null;
  }

  final scheme = targetUri.scheme;
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }

  if (targetUri.userInfo.isNotEmpty) {
    return null;
  }

  final expectedBaseUri = Uri.parse(webAppUrl);
  if (targetUri.origin != expectedBaseUri.origin) {
    return null;
  }

  final expectedPath = _normalizeBasePath(expectedBaseUri.path);
  final targetPath = _normalizeTargetPath(targetUri.path);
  if (!targetPath.startsWith(expectedPath)) {
    return null;
  }

  return targetUri.replace(fragment: '');
}

String _normalizeBasePath(String path) {
  if (path.isEmpty || path == '/') {
    return '/';
  }
  return path.endsWith('/') ? path : '$path/';
}

String _normalizeTargetPath(String path) {
  if (path.isEmpty) {
    return '/';
  }
  return path;
}
