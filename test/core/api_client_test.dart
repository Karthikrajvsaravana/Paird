import 'package:flutter_test/flutter_test.dart';
import 'package:paird/core/api/api_client.dart';
import 'package:paird/core/api/api_exception.dart';
import 'package:paird/core/auth/token_store.dart';

import '../fake_backend.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore store;
  late ApiClient client;

  setUp(() {
    backend = FakeBackend();
    store = MemoryTokenStore();
    client = ApiClient(tokenStore: store, httpClient: backend.client, baseUrl: 'http://test/api/v1');
  });

  test('parses the server error envelope', () async {
    expect(
      () => client.postPublic('/auth/login/', {'identifier': 'x@y.co', 'password': 'nope'}),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 400)
          .having((e) => e.message, 'message', 'Incorrect email/phone number or password.')),
    );
  });

  test('refreshes an expired access token once and retries', () async {
    final tokens = await client.postPublic('/auth/register/', {
      'full_name': 'A',
      'identifier': 'a@b.co',
      'password': 'long-enough-1',
    });
    await client.setSession(access: 'stale-access', refresh: tokens['tokens']['refresh'] as String);

    final me = await client.get('/auth/me/');
    expect(me['email'], 'a@b.co');
    expect(backend.refreshCalls, 1);
    expect(store.token, isNot(tokens['tokens']['refresh']), reason: 'rotated refresh token is persisted');
  });

  test('concurrent 401s share a single refresh', () async {
    final tokens = await client.postPublic('/auth/register/', {
      'full_name': 'A',
      'identifier': 'a@b.co',
      'password': 'long-enough-1',
    });
    await client.setSession(access: 'stale-access', refresh: tokens['tokens']['refresh'] as String);
    await Future.wait([client.get('/auth/me/'), client.get('/auth/me/'), client.get('/auth/me/')]);
    expect(backend.refreshCalls, 1);
  });

  test('invalid refresh token ends the session and notifies', () async {
    var expired = false;
    client.onSessionExpired = () => expired = true;
    await client.setSession(access: 'stale', refresh: 'revoked');
    await expectLater(client.get('/auth/me/'), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
    expect(store.token, isNull);
  });

  test('network failures become friendly ApiExceptions', () async {
    backend.offline = true;
    await expectLater(
      client.postPublic('/auth/login/', {}),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
    );
  });
}
