import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paird/app/paird_app.dart';
import 'package:paird/core/api/api_client.dart';
import 'package:paird/core/api/paird_api.dart';
import 'package:paird/core/auth/auth_controller.dart';
import 'package:paird/core/auth/token_store.dart';
import 'package:paird/features/auth/screens/sign_in_screen.dart';

void main() {
  testWidgets('Signed-out app shows the original sign-in screen', (tester) async {
    final client = MockClient((request) async => http.Response(jsonEncode({}), 401));
    final api = PairdApi(ApiClient(tokenStore: MemoryTokenStore(), httpClient: client, baseUrl: 'http://test/api/v1'));
    final auth = AuthController(api: api);
    await auth.restore(); // no stored token -> signed out
    await tester.pumpWidget(PairdApp(api: api, auth: auth));
    await tester.pump();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Slide to Sign In'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
