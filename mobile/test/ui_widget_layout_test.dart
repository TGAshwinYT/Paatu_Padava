// Regression tests for the overflow bugs fixed in the "debug pass".
// Widgets (not full screens) that are easy to pump in isolation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/sleep_timer_service.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/sleep_timer_sheet.dart';

import 'helpers/layout_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SleepTimerService.instance.cancel());
  tearDown(() => SleepTimerService.instance.cancel());

  for (final device in kDevices) {
    for (final scale in kTextScales) {
      testWidgets('SleepTimerSheet (idle) $device x$scale: no overflow', (tester) async {
        final r = await pumpAndCollectLayoutErrors(
          tester,
          const Scaffold(body: SingleChildScrollView(child: SleepTimerSheet())),
          device: device,
          textScale: scale,
        );
        expect(r.layoutErrors, isEmpty, reason: r.layoutErrors.toSet().join('\n'));
      });

      testWidgets('SleepTimerSheet (timer running) $device x$scale: no overflow', (tester) async {
        SleepTimerService.instance.setTimer(const Duration(minutes: 25));
        try {
          final r = await pumpAndCollectLayoutErrors(
            tester,
            const Scaffold(body: SingleChildScrollView(child: SleepTimerSheet())),
            device: device,
            textScale: scale,
          );
          expect(r.layoutErrors, isEmpty, reason: r.layoutErrors.toSet().join('\n'));
        } finally {
          SleepTimerService.instance.cancel();
        }
      });
    }
  }
}
