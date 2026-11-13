import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/budget_pace_screen.dart';
import 'package:sure_mobile/services/budget_pace_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

const money = r'A$1,234.56';
BudgetPaceBreakdown fixture(
        {String title = 'November budget',
        bool early = false,
        bool empty = false,
        bool labeled = false}) =>
    BudgetPaceBreakdown(
      title: title,
      areaNames: const ['Fun', 'Everyday'],
      periodStart: '2026-11-01',
      periodEnd: '2026-11-30',
      fetchedAt: DateTime.utc(2026, 11, 13, 5),
      currency: 'AUD',
      spent: money,
      budget: r'A$2,000.00',
      remaining: r'A$765.44',
      expected: r'A$900.00',
      deviation: r'+A$334.56',
      projected: r'A$2,743.47',
      elapsedFraction: 0.45,
      paceRatio: early ? null : 1.37,
      state: early ? 'unavailable' : 'ahead',
      early: early,
      paceLabel: '37% ahead of even pace',
      categories: empty
          ? const []
          : [
              BudgetPaceCategory(
                  name: 'Everyday and longer category name',
                  spent: r'A$150.00',
                  budget: r'A$100.00',
                  remaining: r'−A$50.00',
                  spentFraction: 1.5,
                  remainingLabel: labeled ? r'A$50.00 over budget' : null)
            ],
      categoryStatus: empty ? 'complete' : 'partial',
      categoryNote: 'Some categories could not be loaded.',
    );

Widget harness(Future<BudgetPaceBreakdown> Function() loader,
        {bool hidden = false,
        double scale = 1,
        VoidCallback? close,
        String budget = 'current',
        bool dark = false}) =>
    ChangeNotifierProvider(
      create: (_) => PrivacyProvider(initialHidden: hidden),
      child: MaterialApp(
        theme: dark ? SureTheme.dark : SureTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: BudgetPaceScreen(
            budget: budget,
            areas: const [],
            onClose: close ?? () {},
            loader: loader),
      ),
    );

void main() {
  testWidgets('shows native breakdown and closes through parent callback',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var closed = false;
    await tester
        .pumpWidget(harness(() async => fixture(), close: () => closed = true));
    await tester.pumpAndSettle();
    expect(find.text('37% ahead of even pace'), findsOneWidget);
    expect(find.text('137% of even pace'), findsOneWidget);
    expect(find.textContaining(money), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('1.37 times even spending pace')),
        findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    expect(closed, isTrue);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back closes embedded destination', (tester) async {
    var closed = false;
    await tester
        .pumpWidget(harness(() async => fixture(), close: () => closed = true));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('privacy masks amounts, ratios, gauge and derived state',
      (tester) async {
    await tester.pumpWidget(harness(() async => fixture(), hidden: true));
    await tester.pumpAndSettle();
    expect(find.text('Financial details hidden'), findsOneWidget);
    expect(find.textContaining(money), findsNothing);
    expect(find.text('37% ahead of even pace'), findsNothing);
    expect(find.text('45%'), findsNothing);
    expect(find.text('137% of even pace'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('1.37 times even spending pace')),
        findsNothing);
    expect(find.text('••••'), findsWidgets);
  });

  testWidgets('small screen large type scrolls without overflow in dark mode',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(harness(() async => fixture(), scale: 2, dark: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('category rows show overspend honestly and privacy removes bars',
      (tester) async {
    await tester.pumpWidget(harness(() async => fixture()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('By category'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Partial breakdown'), findsOneWidget);
    expect(find.text(r'A$150.00 spent of A$100.00'), findsOneWidget);
    expect(find.text(r'−A$50.00 remaining'), findsOneWidget);
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 1);
    expect(find.bySemanticsLabel(RegExp('150 percent of budget used')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        harness(() async => fixture(), hidden: true, budget: 'budget:new'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('By category'), 250);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(r'A$150.00 spent of A$100.00'), findsNothing);
    expect(find.text(r'−A$50.00 remaining'), findsNothing);
  });

  testWidgets('complete empty category snapshot is not a load failure',
      (tester) async {
    await tester.pumpWidget(harness(() async => fixture(empty: true)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('By category'), 250);
    expect(find.text('No spending or allocated amounts in these categories.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester
        .pumpWidget(harness(() async => fixture(empty: true), hidden: true));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('By category'), 250);
    expect(find.text('No spending or allocated amounts in these categories.'),
        findsNothing);
  });

  testWidgets('shows native over budget wording rather than signed remaining',
      (tester) async {
    await tester.pumpWidget(harness(() async => fixture(labeled: true)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('By category'), 250);
    expect(find.text(r'A$50.00 over budget'), findsOneWidget);
    expect(find.text(r'−A$50.00 remaining'), findsNothing);
  });

  testWidgets('early period has no invented gauge', (tester) async {
    await tester.pumpWidget(harness(() async => fixture(early: true)));
    await tester.pumpAndSettle();
    expect(find.text('Building a picture'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('1.37 times even spending pace')),
        findsNothing);
  });

  testWidgets(
      'failure clears previous values, does not expose exception, retries',
      (tester) async {
    var count = 0;
    Future<BudgetPaceBreakdown> load() async {
      count++;
      if (count == 2) throw Exception('private-server-secret');
      return fixture();
    }

    await tester.pumpWidget(harness(load));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining(money), findsNothing);
    expect(find.textContaining('private-server-secret'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.textContaining(money), findsOneWidget);
  });

  testWidgets('old request cannot replace a new selection', (tester) async {
    final old = Completer<BudgetPaceBreakdown>();
    await tester.pumpWidget(harness(() => old.future));
    await tester.pump();
    await tester.pumpWidget(harness(() async => fixture(title: 'New selection'),
        budget: 'budget:other'));
    await tester.pumpAndSettle();
    old.complete(fixture(title: 'Old selection'));
    await tester.pumpAndSettle();
    expect(find.text('New selection'), findsOneWidget);
    expect(find.text('Old selection'), findsNothing);
  });
}
