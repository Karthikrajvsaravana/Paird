import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_navigation_test.dart' show member, signedInApp;

Map<String, dynamic> memberDetail() => {
      ...member(7, 'Arjun M.'),
      'photos': [],
      'photo_count': 0,
      'income': null,
      'income_hidden': true,
      'lifestyle': null,
      'lifestyle_hidden': true,
      'connection': {'status': 'none', 'can_send_interest': true},
    };

Future<void> openArjun(WidgetTester tester, Map<String, dynamic> insightResponse) async {
  final (backend, _, _) = await signedInApp(tester, discover: [member(7, 'Arjun M.')]);
  backend.routes['GET /members/7/'] = (_) => memberDetail();
  backend.routes['GET /members/7/insight/'] = (_) => insightResponse;
  await tester.tap(find.text('Discover'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Arjun M.'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a ready AI insight with strengths and opener', (tester) async {
    await openArjun(tester, {
      'status': 'ready',
      'message': null,
      'insight': {
        'rating': 'strong',
        'rating_label': 'Strong match',
        'score': 88,
        'summary': 'You both want to marry within a year and love travelling.',
        'strengths': ['Same marriage timeline', 'Both vegetarian'],
        'considerations': ['Which city to live in'],
        'conversation_starter': 'Which trek should we plan first?',
        'generated_at': '2026-11-05T10:00:00Z',
      },
    });
    await tester.scrollUntilVisible(find.text('AI match insight'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Strong match'), findsOneWidget);
    expect(find.text('You both want to marry within a year and love travelling.'), findsOneWidget);
    expect(find.text('Same marriage timeline'), findsOneWidget);
    expect(find.text('“Which trek should we plan first?”'), findsOneWidget);
    expect(find.textContaining('It can be wrong'), findsOneWidget);
  });

  testWidgets('hides the card when AI is switched off on the server', (tester) async {
    await openArjun(tester, {
      'status': 'unavailable',
      'insight': null,
      'message': "AI match insights aren't switched on for this server.",
    });
    expect(find.text('AI match insight'), findsNothing);
  });

  testWidgets('explains when a member opted out', (tester) async {
    await openArjun(tester, {
      'status': 'unavailable',
      'insight': null,
      'message': 'This member has chosen not to be included in AI insights.',
    });
    await tester.scrollUntilVisible(find.text('AI match insight'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('This member has chosen not to be included in AI insights.'), findsOneWidget);
  });
}
