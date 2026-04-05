class WebAuthPopupSession {
  Future<Uri> waitForCallback() {
    throw UnsupportedError('Web auth popup is only available on web.');
  }

  Future<void> close() async {}
}

Future<WebAuthPopupSession?> openWebAuthPopup(String url) async {
  return null;
}
