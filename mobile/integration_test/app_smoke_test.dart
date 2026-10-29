// END-TO-END SMOKE TEST (runs the REAL app on an emulator/device)
//
//   cd mobile
//   flutter test integration_test/app_smoke_test.dart -d <emulator-id>
//
// Checks: cold start reaches the main navigation, every bottom tab opens, and
// no layout/framework error is thrown along the way.
//
// NOTE: on a fresh install the app may show onboarding first. Either complete
// onboarding once on the emulator before running, or extend this test to tap
// through onboarding. If the bottom bar never appears the test fails with a
// clear message instead of hanging.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paatu_padava_mobile/main.dart' as app;

Future<bool> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold start -> Home/Search/Library tabs -> no layout errors', (tester) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exceptionAsString().split('\n').first);
      previous?.call(details);
    };

    app.main();

    final navBar = find.byType(BottomNavigationBar);
    final found = await _pumpUntil(tester, navBar);
    expect(found, isTrue,
        reason: 'Bottom navigation never appeared within 30s. '
            'Is onboarding/auth blocking the app on this emulator?');

    for (final label in ['Search', 'Library', 'Home']) {
      final tab = find.descendant(of: navBar, matching: find.text(label));
      expect(tab, findsOneWidget, reason: 'Bottom tab "$label" missing');
      await tester.tap(tab);
      await tester.pump(const Duration(milliseconds: 800));
      await binding.takeScreenshot('tab_${label.toLowerCase()}');
    }

    final layoutErrors = errors.where((e) =>
        e.contains('overflowed') ||
        e.contains('RenderFlex') ||
        e.contains('unbounded') ||
        e.contains('not laid out'));
    expect(layoutErrors, isEmpty,
        reason: 'Layout errors during smoke run:\n${layoutErrors.join('\n')}');

    FlutterError.onError = previous;
  });
}
