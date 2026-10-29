@Tags(<String>['golden'])
library;

// PIXEL SNAPSHOTS ("golden" tests)
//
// First time / after an intentional design change, regenerate baselines:
//     cd mobile
//     flutter test --update-goldens --tags golden
// then REVIEW the PNGs in test/goldens/files/ and commit them.
//
// Normal runs (`flutter test`) skip these unless baselines are committed and
// you run `flutter test --tags golden`. Flutter's test font is a fixed block
// font, so snapshots are stable across Windows/macOS/Linux; they detect layout
// and spacing changes, not font-rendering differences.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/sleep_timer_service.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/sleep_timer_sheet.dart';

import '../helpers/layout_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SleepTimerService.instance.cancel());
  tearDown(() => SleepTimerService.instance.cancel());

  for (final device in [kDevices[0], kDevices[1]]) {
    final goldenFile = File('test/goldens/files/sleep_timer_sheet_${device.name}.png');
    testWidgets(
      'SleepTimerSheet golden on ${device.name}',
      (tester) async {
        await pumpAndCollectLayoutErrors(
          tester,
          const Scaffold(body: SleepTimerSheet()),
          device: device,
        );
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('files/sleep_timer_sheet_${device.name}.png'),
        );
      },
      tags: ['golden'],
      skip: !goldenFile.existsSync(),
    );
  }

  // TODO(ui): add goldens for MiniPlayer, PlayerControls, QueueSheet and
  // HomeSongCard once they can be pumped with a fake audio handler.
}
