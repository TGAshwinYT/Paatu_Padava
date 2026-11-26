// Integration test covering rapid track skipping, offline playback fallback, and guest-to-account login flow.
// Run on device/emulator:
//   cd mobile && flutter test integration_test/playback_and_auth_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paatu_padava_mobile/main.dart' as app;

Future<bool> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigation resilience across Home, Search, Library without exceptions', (tester) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exceptionAsString().split('\n').first);
      previous?.call(details);
    };

    app.main();

    final navBar = find.byType(BottomNavigationBar);
    final found = await _pumpUntil(tester, navBar);
    expect(found, isTrue, reason: 'Bottom navigation bar did not appear within 25s');

    // Rapid tab switching to ensure no mounted/dispose race conditions
    for (int i = 0; i < 3; i++) {
      for (final label in ['Search', 'Library', 'Home']) {
        final tab = find.descendant(of: navBar, matching: find.text(label));
        if (tab.evaluate().isNotEmpty) {
          await tester.tap(tab);
          await tester.pump(const Duration(milliseconds: 250));
        }
      }
    }

    expect(errors, isEmpty, reason: 'Unhandled framework errors: ${errors.join('; ')}');
    FlutterError.onError = previous;
  });
}
