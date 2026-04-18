import 'package:flutter_test/flutter_test.dart';
import 'package:secrandom_lite/models/pending_auth_session.dart';

void main() {
  test('PendingAuthSession serializes and deserializes correctly', () {
    final session = PendingAuthSession(
      state: 'state-token',
      codeVerifier: 'verifier-token',
      targetPlatform: PendingAuthTargetPlatform.windows,
      redirectUri:
          'https://secrandom-lite.sectl.top/auth_callback_windows.html',
      loopbackPort: 8788,
      createdAt: DateTime.parse('2026-04-05T10:00:00.000Z'),
    );

    final decoded = PendingAuthSession.fromJsonString(session.toJsonString());

    expect(decoded.state, session.state);
    expect(decoded.codeVerifier, session.codeVerifier);
    expect(decoded.targetPlatform, session.targetPlatform);
    expect(decoded.redirectUri, session.redirectUri);
    expect(decoded.loopbackPort, session.loopbackPort);
    expect(decoded.createdAt, session.createdAt);
  });
}
