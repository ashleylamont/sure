import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/screens/more_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

void main() {
  testWidgets('pace entry wraps at narrow large text without paint assertions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: SureTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 900), textScaler: TextScaler.linear(2)),
        child: MoreScreen(onOpenSpendingPace: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Spending pace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
