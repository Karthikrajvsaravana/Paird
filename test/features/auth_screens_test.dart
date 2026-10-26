import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paird/app/paird_app.dart';
import 'package:paird/core/api/api_client.dart';
import 'package:paird/core/api/paird_api.dart';
import 'package:paird/core/auth/auth_controller.dart';
import 'package:paird/core/auth/token_store.dart';
import 'package:paird/features/auth/screens/sign_up_screen.dart';

import '../fake_backend.dart';

Future<(FakeBackend, AuthController)> pumpApp(WidgetTester tester) async {
  final backend = FakeBackend();
  final api = PairdApi(ApiClient(tokenStore: MemoryTokenStore(), httpClient: backend.client, baseUrl: 'http://test/api/v1'));
  final auth = AuthController(api: api);
  await auth.restore();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PairdApp(api: api, auth: auth));
  await tester.pump();
  return (backend, auth);
}

void main() {
  testWidgets('sign-up validates fields before calling the server', (tester) async {
    final (backend, _) = await pumpApp(tester);
    await tester.tap(find.textContaining('Create account', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.byType(SignUpScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), '9876543210');
    await tester.enterText(find.byType(TextFormField).at(2), 'short');
    await tester.enterText(find.byType(TextFormField).at(3), 'different');
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(find.text('Please enter your full name'), findsOneWidget);
    expect(find.textContaining('country code'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(backend.requests.where((r) => r.url.path.endsWith('/register/')), isEmpty);
  });

  testWidgets('server errors are shown on the sign-up form', (tester) async {
    final (backend, auth) = await pumpApp(tester);
    backend.users['taken@example.com'] = (password: 'x', name: 'Someone');
    await tester.tap(find.textContaining('Create account', findRichText: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Asha Raman');
    await tester.enterText(find.byType(TextFormField).at(1), 'taken@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'long-enough-1');
    await tester.enterText(find.byType(TextFormField).at(3), 'long-enough-1');
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already exists'), findsWidgets);
    expect(auth.status, AuthStatus.signedOut);
  });

  testWidgets('successful sign-up signs in and leaves the auth screens', (tester) async {
    final (_, auth) = await pumpApp(tester);
    await tester.tap(find.textContaining('Create account', findRichText: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Asha Raman');
    await tester.enterText(find.byType(TextFormField).at(1), 'asha@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'long-enough-1');
    await tester.enterText(find.byType(TextFormField).at(3), 'long-enough-1');
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(auth.status, AuthStatus.signedIn);
    expect(find.byType(SignUpScreen), findsNothing);
  });

  testWidgets('sign-in slide shows server error and snaps back', (tester) async {
    final (backend, auth) = await pumpApp(tester);
    backend.users['asha@example.com'] = (password: 'right-password', name: 'Asha');
    await tester.enterText(find.byType(TextFormField).at(0), 'asha@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');

    final thumb = find.byIcon(Icons.arrow_forward_rounded);
    await tester.drag(thumb, const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email/phone number or password.'), findsOneWidget);
    expect(auth.status, AuthStatus.signedOut);
    expect(find.text('Slide to Sign In'), findsOneWidget);
  });

  testWidgets('sign-in slide with valid credentials signs in', (tester) async {
    final (backend, auth) = await pumpApp(tester);
    backend.users['asha@example.com'] = (password: 'right-password', name: 'Asha');
    await tester.enterText(find.byType(TextFormField).at(0), 'Asha@Example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'right-password');
    await tester.drag(find.byIcon(Icons.arrow_forward_rounded), const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(auth.status, AuthStatus.signedIn);
  });
}
