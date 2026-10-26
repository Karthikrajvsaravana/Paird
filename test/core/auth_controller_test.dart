import 'package:flutter_test/flutter_test.dart';
import 'package:paird/core/api/api_client.dart';
import 'package:paird/core/api/api_exception.dart';
import 'package:paird/core/api/paird_api.dart';
import 'package:paird/core/auth/auth_controller.dart';
import 'package:paird/core/auth/token_store.dart';

import '../fake_backend.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore store;

  AuthController controller() => AuthController(
        api: PairdApi(ApiClient(tokenStore: store, httpClient: backend.client, baseUrl: 'http://test/api/v1')),
      );

  setUp(() {
    backend = FakeBackend();
    store = MemoryTokenStore();
  });

  test('sign up starts a session and stores only the refresh token', () async {
    final auth = controller();
    await auth.signUp(fullName: 'Asha Raman', identifier: 'asha@example.com', password: 'long-enough-1');
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.account!.fullName, 'Asha Raman');
    expect(store.token, startsWith('refresh-'));
    expect(store.token, isNot(contains('long-enough-1')));
  });

  test('invalid credentials surface the server message', () async {
    final auth = controller();
    await auth.signUp(fullName: 'A', identifier: 'a@b.co', password: 'long-enough-1');
    await auth.signOut();
    expect(
      () => auth.signIn('a@b.co', 'wrong'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Incorrect'))),
    );
  });

  test('session is restored after an app restart', () async {
    await controller().signUp(fullName: 'A', identifier: 'a@b.co', password: 'long-enough-1');
    final restarted = controller(); // new controller, same secure storage
    await restarted.restore();
    expect(restarted.status, AuthStatus.signedIn);
    expect(restarted.account!.email, 'a@b.co');
  });

  test('restore without a stored session signs out', () async {
    final auth = controller();
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
  });

  test('expired/revoked session on restore signs out and clears storage', () async {
    store.token = 'revoked-refresh';
    final auth = controller();
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
    expect(store.token, isNull);
  });

  test('offline restore keeps the stored session for retry', () async {
    await controller().signUp(fullName: 'A', identifier: 'a@b.co', password: 'long-enough-1');
    backend.offline = true;
    final auth = controller();
    await auth.restore();
    expect(auth.status, AuthStatus.unknown);
    expect(auth.restoreError, isNotNull);
    expect(store.token, isNotNull);
  });

  test('sign out revokes the refresh token on the server and clears storage', () async {
    final auth = controller();
    await auth.signUp(fullName: 'A', identifier: 'a@b.co', password: 'long-enough-1');
    final refresh = store.token!;
    await auth.signOut();
    expect(auth.status, AuthStatus.signedOut);
    expect(store.token, isNull);
    expect(backend.validRefresh.contains(refresh), isFalse);
  });
}
