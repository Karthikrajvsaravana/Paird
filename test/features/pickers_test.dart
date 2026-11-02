import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paird/app/theme/app_theme.dart';
import 'package:paird/shared/widgets/pickers.dart';

Widget host(Widget Function(BuildContext) child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Builder(builder: (context) => Center(child: child(context)))),
    );

void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('searchable picker filters a scrollable list and returns the choice', (tester) async {
    String? result;
    final items = [for (var i = 0; i < 60; i++) 'Country $i', 'India', 'Indonesia'];
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async => result = await showSearchablePicker(context, title: 'Country', items: items),
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Country 0'), findsOneWidget);
    expect(find.text('India'), findsNothing, reason: 'far down the list until scrolled or searched');

    await tester.enterText(find.byType(TextField), 'ind');
    await tester.pumpAndSettle();
    expect(find.text('India'), findsOneWidget);
    expect(find.text('Indonesia'), findsOneWidget);
    expect(find.text('Country 0'), findsNothing);

    await tester.tap(find.text('India'));
    await tester.pumpAndSettle();
    expect(result, 'India');
  });

  testWidgets('birthday wheels scroll through months and enforce the minimum age', (tester) async {
    phoneSize(tester);
    DateTime? result;
    final latest = DateTime(2008, 6, 15);
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async => result = await showBirthDatePicker(
            context,
            initial: DateTime(2000, 1, 10),
            earliest: DateTime(1926, 1, 1),
            latest: latest,
            helpText: 'You must be 18 or older to use PairD.',
          ),
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('10 January 2000'), findsOneWidget);
    expect(find.text('January'), findsOneWidget);

    // Scroll the month wheel down four rows: January -> May.
    await tester.drag(find.text('January'), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.text('10 May 2000'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2000, 5, 10));
  });

  testWidgets('day is clamped when the month is shorter', (tester) async {
    phoneSize(tester);
    DateTime? result;
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async => result = await showBirthDatePicker(
            context,
            initial: DateTime(1999, 1, 31),
            earliest: DateTime(1926, 1, 1),
            latest: DateTime(2008, 1, 1),
          ),
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('January'), const Offset(0, -40)); // -> February
    await tester.pumpAndSettle();
    expect(find.text('28 February 1999'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, DateTime(1999, 2, 28));
  });
}
