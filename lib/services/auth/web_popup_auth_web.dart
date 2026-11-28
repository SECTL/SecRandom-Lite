import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'auth_config.dart';
import 'auth_web_security.dart';

/// 直接使用 `dart:js_interop` 操作原生 window，而不是 `dart:html` /
/// `package:universal_html` 的 `WindowBase`。
///
/// 原因：`dart:html` 在访问「其它窗口」时会包装成 `_DOMWindowCrossFrame`。
/// 该包装类每次访问都会新建实例（SDK 里明确写着 "TODO(vsm): Cache or
/// implement equality"），因此：
///   * `event.source` 与 `window.open()` 的返回值永远不 `identical`，
///     合法的登录回调消息会被当成伪造消息丢弃；
///   * `closed` / `location` 在 `WindowBase` 上是 external 成员，静态类型
///     调用会被编译成裸属性读取，落到包装类上只会得到 `undefined`，
///     于是「弹窗是否已关闭」永远判断为 false，界面卡在等待状态。
@JS('window')
external _MainWindow get _mainWindow;

extension type _MainWindow(JSObject _) implements JSObject {
  external num get screenLeft;
  external num get screenTop;
  external num get outerWidth;
  external num get outerHeight;
  external _PopupWindow? open(String url, String target, String features);
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _PopupWindow(JSObject _) implements JSObject {
  external bool get closed;
  external _WindowLocation get location;
  external void close();
}

extension type _WindowLocation(JSObject _) implements JSObject {
  external String get href;
}

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
  external String get origin;
  external JSObject? get source;
}

class WebAuthPopupSession {
  WebAuthPopupSession._(this._popupWindow) {
    _messageListener = _handleWindowMessage.toJS;
    _mainWindow.addEventListener('message', _messageListener!);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_isClosed || _callbackCompleter.isCompleted) return;
      _startClosedTimer();
    });
  }

  final _PopupWindow _popupWindow;
  final Completer<Uri> _callbackCompleter = Completer<Uri>();
  JSFunction? _messageListener;
  Timer? _closedTimer;
  bool _isClosed = false;

  Future<Uri> waitForCallback() => _callbackCompleter.future;

  void _handleWindowMessage(JSObject rawEvent) {
    final event = _MessageEvent(rawEvent);
    final payload = _normalizeMessagePayload(_readEventData(event));
    final callbackUri = _extractTrustedCallbackUri(event, payload);
    if (callbackUri == null) {
      return;
    }

    if (!_callbackCompleter.isCompleted) {
      _callbackCompleter.complete(callbackUri);
    }
    unawaited(close());
  }

  Map<String, dynamic>? _normalizeMessagePayload(JSAny? data) {
    if (data == null) {
      return null;
    }

    final Object? decodedData;
    try {
      decodedData = data.dartify();
    } catch (_) {
      return null;
    }

    if (decodedData is String) {
      try {
        final decoded = jsonDecode(decodedData);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }

    if (decodedData is Map) {
      return decodedData.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  Uri? _extractTrustedCallbackUri(
    _MessageEvent event,
    Map<String, dynamic>? payload,
  ) {
    if (payload == null || !_isTrustedPopupMessage(event, payload)) {
      return null;
    }

    final href = payload['href'] as String;
    return parseTrustedWebAppCallbackUri(href);
  }

  bool _isTrustedPopupMessage(
    _MessageEvent event,
    Map<String, dynamic> payload,
  ) {
    final origin = _readEventOrigin(event);
    if (origin == null) {
      return false;
    }

    return isTrustedWebPopupCallbackMessage(
      messageType: payload['type'],
      href: payload['href'],
      eventOrigin: origin,
      isFromExpectedPopupWindow: _isExpectedPopupSource(
        _readEventSource(event),
      ),
      callbackBridgeUrl: AuthConfig.webOauthRedirectUri,
    );
  }

  JSAny? _readEventData(_MessageEvent event) {
    try {
      return event.data;
    } catch (_) {
      return null;
    }
  }

  String? _readEventOrigin(_MessageEvent event) {
    try {
      return event.origin;
    } catch (_) {
      return null;
    }
  }

  JSObject? _readEventSource(_MessageEvent event) {
    try {
      return event.source;
    } catch (_) {
      return null;
    }
  }

  /// 这里是真正的 JS 对象身份比较（编译为 `===`）。
  ///
  /// 只有在「明确是别的窗口」时才拒绝；若浏览器没有暴露 `event.source`，
  /// 则退回由 origin 校验 + 下游 pending session 的 state 校验把关，
  /// 避免再次因为拿不到窗口句柄而把合法回调整条吞掉。
  bool _isExpectedPopupSource(JSObject? source) {
    if (source == null) {
      return true;
    }

    try {
      return identical(source, _popupWindow);
    } catch (_) {
      return true;
    }
  }

  void _startClosedTimer() {
    _closedTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_isClosed || _callbackCompleter.isCompleted) {
        _closedTimer?.cancel();
        _closedTimer = null;
        return;
      }

      final callbackUri = _tryReadPopupCallbackUri();
      if (callbackUri != null) {
        if (!_callbackCompleter.isCompleted) {
          _callbackCompleter.complete(callbackUri);
        }
        unawaited(close());
        return;
      }

      if (_isPopupClosed() && !_callbackCompleter.isCompleted) {
        _callbackCompleter.completeError(
          StateError('The SECTL login popup was closed before finishing.'),
        );
        unawaited(close());
      }
    });
  }

  bool _isPopupClosed() {
    try {
      return _popupWindow.closed;
    } catch (_) {
      return false;
    }
  }

  Uri? _tryReadPopupCallbackUri() {
    try {
      final hrefString = _popupWindow.location.href;
      if (hrefString.isEmpty) {
        return null;
      }

      final uri = Uri.tryParse(hrefString);
      if (uri == null) {
        return null;
      }

      if (uri.queryParameters.containsKey('code') ||
          uri.queryParameters.containsKey('error') ||
          uri.queryParameters[AuthConfig.webCookieAuthSignalKey] ==
              AuthConfig.webCookieAuthSignalValue) {
        return uri;
      }
    } catch (_) {
      // 弹窗还在其它源上时读取 location 会抛异常，等它回到本站再看。
    }
    return null;
  }

  Future<void> close() async {
    _isClosed = true;
    _closedTimer?.cancel();
    _closedTimer = null;

    final listener = _messageListener;
    if (listener != null) {
      _messageListener = null;
      try {
        _mainWindow.removeEventListener('message', listener);
      } catch (_) {
        // Ignore browser interop failures.
      }
    }

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

  num screenLeft = 0;
  num screenTop = 0;
  num outerWidth = width;
  num outerHeight = height;
  try {
    screenLeft = _mainWindow.screenLeft;
    screenTop = _mainWindow.screenTop;
    outerWidth = _mainWindow.outerWidth;
    outerHeight = _mainWindow.outerHeight;
  } catch (_) {
    // 取不到窗口尺寸时按默认值居中。
  }

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

  final _PopupWindow? popup;
  try {
    popup = _mainWindow.open(url, 'sectl_auth_popup', features);
  } catch (_) {
    return null;
  }

  if (popup == null) {
    // 被浏览器拦截时返回 null，由调用方退化为整页跳转。
    return null;
  }

  try {
    if (popup.closed) {
      return null;
    }
  } catch (_) {
    // Ignore browser interop failures and continue with popup session.
  }

  return WebAuthPopupSession._(popup);
}
