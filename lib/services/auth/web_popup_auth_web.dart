import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:universal_html/html.dart' as html;

extension on JSObject {
  external JSAny? operator [](String key);
}

class WebAuthPopupSession {
  WebAuthPopupSession._(this._popupWindow) {
    _messageSubscription = html.window.onMessage.listen((event) {
      final payload = _normalizeMessagePayload(event.data);
      if (payload == null) {
        return;
      }

      final type = payload['type'];
      final href = payload['href'];

      if (type != 'sectl-auth-callback' || href is! String) {
        return;
      }

      if (href.isEmpty) {
        return;
      }

      if (!_callbackCompleter.isCompleted) {
        _callbackCompleter.complete(Uri.parse(href));
      }
      unawaited(close());
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (_callbackCompleter.isCompleted) return;
      _startClosedTimer();
    });
  }

  final html.WindowBase _popupWindow;
  final Completer<Uri> _callbackCompleter = Completer<Uri>();
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  Timer? _closedTimer;

  Future<Uri> waitForCallback() => _callbackCompleter.future;

  Map<String, dynamic>? _normalizeMessagePayload(dynamic data) {
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {
        return null;
      }
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    try {
      final object = data as JSObject;
      final type = object['type'];
      final href = object['href'];
      if (type == null || href == null) {
        return null;
      }
      return {
        'type': (type as JSString).toDart,
        'href': (href as JSString).toDart,
      };
    } catch (_) {
      return null;
    }
  }

  void _startClosedTimer() {
    _closedTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_callbackCompleter.isCompleted) {
        _closedTimer?.cancel();
        return;
      }

      final callbackUri = _tryReadPopupCallbackUri();
      if (callbackUri != null && !_callbackCompleter.isCompleted) {
        _callbackCompleter.complete(callbackUri);
        unawaited(close());
        return;
      }

      final isClosed = _isPopupClosed();
      if (isClosed && !_callbackCompleter.isCompleted) {
        _callbackCompleter.completeError(
          StateError('The SECTL login popup was closed before finishing.'),
        );
        unawaited(close());
      }
    });
  }

  bool _isPopupClosed() {
    try {
      final popupJs = _popupWindow as JSObject;
      final closed = popupJs['closed'];
      return (closed as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  Uri? _tryReadPopupCallbackUri() {
    try {
      final location = _popupWindow.location as JSObject;
      final href = location['href'];
      if (href == null) {
        return null;
      }

      final hrefString = (href as JSString).toDart;
      if (hrefString.isEmpty) {
        return null;
      }

      final uri = Uri.parse(hrefString);
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
  if (popup == null) {
    return null;
  }
  return WebAuthPopupSession._(popup);
}
