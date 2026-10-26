import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paird/app/paird_app.dart';
import 'package:paird/core/api/api_client.dart';
import 'package:paird/core/api/paird_api.dart';
import 'package:paird/core/auth/auth_controller.dart';
import 'package:paird/core/auth/token_store.dart';
import 'package:paird/features/auth/screens/sign_in_screen.dart';
import 'package:paird/features/discover/screens/member_profile_screen.dart';
import 'package:paird/features/home/screens/home_shell.dart';
import 'package:paird/features/onboarding/screens/onboarding_screen.dart';

import '../fake_backend.dart';

/// Signs in through the real AuthController against the fake API, then shows the app.
Future<(FakeBackend, AuthController, MemoryTokenStore)> signedInApp(
  WidgetTester tester, {
  bool complete = true,
  List<Map<String, dynamic>> discover = const [],
}) async {
  final backend = FakeBackend();
  if (complete) addHomeRoutes(backend, discover: discover);
  backend.users['asha@example.com'] = (password: 'long-enough-1', name: 'Asha Raman');
  final store = MemoryTokenStore();
  final api = PairdApi(ApiClient(tokenStore: store, httpClient: backend.client, baseUrl: 'http://test/api/v1'));
  final auth = AuthController(api: api);
  await auth.signIn('asha@example.com', 'long-enough-1');
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PairdApp(api: api, auth: auth));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return (backend, auth, store);
}

Map<String, dynamic> member(int id, String name) => {
      'user_id': id,
      'display_name': name,
      'age': 31,
      'city': 'Pune',
      'country': 'India',
      'occupation': 'Engineer',
      'photo_url': null,
      'photos_hidden': false,
      'is_verified': false,
      'vibe': {'score': 75, 'breakdown': []},
      'connection': {'status': 'none', 'can_send_interest': true},
    };

void main() {
  testWidgets('incomplete profile goes to onboarding, not the home screen', (tester) async {
    await signedInApp(tester, complete: false);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('home shows real dashboard counts and tabs show empty states', (tester) async {
    await signedInApp(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Hello, Asha'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // interests received from the API
    expect(find.textContaining('No recommendations yet'), findsOneWidget);

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.text('No profiles right now'), findsOneWidget);

    await tester.tap(find.text('Matches').last);
    await tester.pumpAndSettle();
    expect(find.text('No matches yet'), findsOneWidget);

    await tester.tap(find.text('Messages').last);
    await tester.pumpAndSettle();
    expect(find.text('No conversations yet'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Asha Raman'), findsOneWidget);
  });

  testWidgets('discover lists members and sending an interest calls the API', (tester) async {
    final (backend, _, _) = await signedInApp(tester, discover: [member(7, 'Arjun M.')]);
    final sent = <Map<String, dynamic>>[];
    var status = 'none';
    backend.routes['GET /members/7/'] = (_) => {
          ...member(7, 'Arjun M.'),
          'photos': [],
          'photo_count': 0,
          'income': null,
          'income_hidden': true,
          'lifestyle': null,
          'lifestyle_hidden': true,
          'connection': {'status': status, 'can_send_interest': status == 'none', 'interest_id': 3},
        };
    backend.routes['POST /interests/'] = (body) {
      sent.add(body);
      status = 'interest_sent';
      return {'interest': {'id': 3, 'status': 'pending'}, 'match': null};
    };

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.text('1 profile for you'), findsOneWidget);
    expect(find.text('Vibe 75%'), findsOneWidget);

    await tester.tap(find.text('Arjun M.'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberProfileScreen), findsOneWidget);

    await tester.tap(find.text('Send interest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(sent.single['receiver_id'], 7);
    expect(find.text('Withdraw interest'), findsOneWidget);
  });

  testWidgets('sign out clears the session and returns to sign in', (tester) async {
    final (_, auth, store) = await signedInApp(tester);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.status, AuthStatus.signedOut);
    expect(store.token, isNull);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('expired session returns to sign in with an explanation', (tester) async {
    final (backend, auth, _) = await signedInApp(tester);
    backend.validAccess = 'rotated-elsewhere';
    backend.validRefresh.clear(); // server revoked the session
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(auth.status, AuthStatus.signedOut);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.textContaining('session has expired'), findsOneWidget);
  });
}
