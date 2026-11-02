import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paird/app/paird_app.dart';
import 'package:paird/core/api/api_client.dart';
import 'package:paird/core/api/paird_api.dart';
import 'package:paird/core/auth/auth_controller.dart';
import 'package:paird/core/auth/token_store.dart';
import 'package:paird/features/auth/screens/forgot_password_screen.dart';

import '../fake_backend.dart';

Future<FakeBackend> openForgotPassword(WidgetTester tester) async {
  final backend = FakeBackend()..users['asha@example.com'] = (password: 'old-password-1', name: 'Asha');
  final api = PairdApi(ApiClient(tokenStore: MemoryTokenStore(), httpClient: backend.client, baseUrl: 'http://test/api/v1'));
  final auth = AuthController(api: api);
  await auth.restore();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PairdApp(api: api, auth: auth));
  await tester.pump();
  await tester.tap(find.text('Forgot password?'));
  await tester.pumpAndSettle();
  expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  return backend;
}

Future<void> sendCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'asha@example.com');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone numbers are explained, not sent', (tester) async {
    final backend = await openForgotPassword(tester);
    await tester.enterText(find.byType(TextFormField).first, '+919876543210');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Password reset works with the email you signed up with'), findsOneWidget);
    expect(backend.resetRequests, isEmpty);
  });

  testWidgets('send code, then resend only after the countdown', (tester) async {
    final backend = await openForgotPassword(tester);
    await sendCode(tester);
    expect(backend.resetRequests, ['asha@example.com']);
    expect(find.text('6-digit code'), findsOneWidget);
    expect(find.text('Resend code in 60s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend code in 59s'), findsOneWidget);
    await tester.tap(find.text('Resend code in 59s'));
    await tester.pump();
    expect(backend.resetRequests, hasLength(1), reason: 'disabled during countdown');

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text("Didn't get it? Resend code"));
    await tester.pumpAndSettle();
    expect(backend.resetRequests, hasLength(2));
    expect(find.textContaining('a new code is on its way'), findsOneWidget);
    expect(find.text('Resend code in 60s'), findsOneWidget);
  });

  testWidgets('mismatched passwords and wrong codes are reported', (tester) async {
    await openForgotPassword(tester);
    await sendCode(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '999999');
    await tester.enterText(fields.at(2), 'brand-new-pass-1');
    await tester.enterText(fields.at(3), 'something-else-2');
    await tester.ensureVisible(find.text('Set new password'));
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(fields.at(3), 'brand-new-pass-1');
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();
    expect(find.text('That code is invalid or has expired.'), findsOneWidget);
  });

  testWidgets('successful reset returns to sign in with the email filled in', (tester) async {
    final backend = await openForgotPassword(tester);
    await sendCode(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), backend.resetCode);
    await tester.enterText(fields.at(2), 'brand-new-pass-1');
    await tester.enterText(fields.at(3), 'brand-new-pass-1');
    await tester.ensureVisible(find.text('Set new password'));
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.text('Password updated. Sign in with your new password.'), findsOneWidget);
    expect(backend.users['asha@example.com']!.password, 'brand-new-pass-1');
  });

  testWidgets('use a different email returns to step one', (tester) async {
    await openForgotPassword(tester);
    await sendCode(tester);
    await tester.tap(find.text('Use a different email'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('6-digit code'), findsNothing);
  });
}
