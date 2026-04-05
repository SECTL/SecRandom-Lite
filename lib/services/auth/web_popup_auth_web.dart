import 'dart:async';

import 'package:universal_html/html.dart' as html;

class WebAuthPopupSession {
  WebAuthPopupSession._(this._popupWindow) {
    _messageSubscription = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is! Map) return;

      final type = data['type'];
      final href = data['href'];
      if (type != 'sectl-auth-callback' || href is! String) {
        return;
      }

      final expectedOrigin = html.window.location.origin;
      if (event.origin.isNotEmpty &&
          expectedOrigin.isNotEmpty &&
          event.origin != expectedOrigin) {
        return;
      }

      if (!_callbackCompleter.isCompleted) {
        _callbackCompleter.complete(Uri.parse(href));
      }
      unawaited(close());
    });

    _closedTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final callbackUri = _tryReadPopupCallbackUri();
      if (callbackUri != null && !_callbackCompleter.isCompleted) {
        _callbackCompleter.complete(callbackUri);
        unawaited(close());
        return;
      }

      if (_popupWindow.closed == true && !_callbackCompleter.isCompleted) {
        _callbackCompleter.completeError(
          StateError('The SECTL login popup was closed before finishing.'),
        );
        unawaited(close());
      }
    });
  }

  final html.WindowBase _popupWindow;
  final Completer<Uri> _callbackCompleter = Completer<Uri>();
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  Timer? _closedTimer;

  Future<Uri> waitForCallback() => _callbackCompleter.future;

  Uri? _tryReadPopupCallbackUri() {
    try {
      final href = _popupWindow.location.href;
      if (href == null || href.isEmpty) {
        return null;
      }

      final uri = Uri.parse(href);
      if (uri.queryParameters.containsKey('code') ||
          uri.queryParameters.containsKey('error')) {
        return uri;
      }
    } catch (_) {
      // Ignore cross-origin access errors until the popup returns to our origin.
    }
    return null;
  }

  Future<void> close() async {
    _closedTimer?.cancel();
    _closedTimer = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    try {
      _popupWindow.close();
    } catch (_) {
      // Ignore browser close failures.
    }
  }
}

Future<WebAuthPopupSession?> openWebAuthPopup(String url) async {
  const width = 540;
  const height = 760;
  final screenLeft = html.window.screenLeft ?? 0;
  final screenTop = html.window.screenTop ?? 0;
  final outerWidth = html.window.outerWidth;
  final outerHeight = html.window.outerHeight;
  final left = screenLeft + ((outerWidth - width) / 2).round();
  final top = screenTop + ((outerHeight - height) / 2).round();

  final features = [
    'popup=yes',
    'toolbar=no',
    'location=yes',
    'status=no',
    'menubar=no',
    'scrollbars=yes',
    'resizable=yes',
    'width=$width',
    'height=$height',
    'left=$left',
    'top=$top',
  ].join(',');

  final popup = html.window.open(url, 'sectl_auth_popup', features);
  return WebAuthPopupSession._(popup);
}
