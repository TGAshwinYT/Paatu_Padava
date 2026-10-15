import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/sleep_timer_service.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/sleep_timer_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SleepTimerService.instance.cancel();
  });

  tearDown(() {
    SleepTimerService.instance.cancel();
  });

  testWidgets('SleepTimerSheet renders configuration view with presets and custom slider', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SleepTimerSheet(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Header
    expect(find.text('Sleep Timer'), findsOneWidget);
    expect(find.text('Fade out and stop when you sleep'), findsOneWidget);

    // Verify Popular Presets Grid
    expect(find.text('15 Min'), findsOneWidget);
    expect(find.text('30 Min'), findsOneWidget);
    expect(find.text('45 Min'), findsOneWidget);
    expect(find.text('1 Hour'), findsOneWidget);
    expect(find.text('1.5 Hours'), findsOneWidget);
    expect(find.text('End of Track'), findsWidgets);

    // Verify Custom Slider & Steppers
    expect(find.text('Custom Duration'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    // Verify Primary Action Button
    expect(find.textContaining('Start Sleep Timer'), findsOneWidget);
  });

  testWidgets('Tapping End of Track updates selection and button label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SleepTimerSheet(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Tap 'End of Track' card in grid
    final endOfTrackGridItem = find.text('Finish current song');
    expect(endOfTrackGridItem, findsOneWidget);
    await tester.tap(endOfTrackGridItem);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Start Timer (End of Track)'), findsOneWidget);
  });

  testWidgets('SleepTimerSheet transitions to active view with countdown and controls when timer is running', (tester) async {
    // Arm timer
    SleepTimerService.instance.setTimer(const Duration(minutes: 25));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SleepTimerSheet(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Active View Header Subtitle
    expect(find.text('Music will fade out smoothly'), findsOneWidget);

    // Verify Countdown is shown
    expect(find.text(SleepTimerService.instance.formattedRemaining), findsOneWidget);
    expect(find.text('REMAINING'), findsOneWidget);

    // Verify Quick Extension Pills
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);

    // Verify Turn Off Action
    expect(find.text('Turn Off Sleep Timer'), findsOneWidget);

    // Tap +5 min pill
    await tester.tap(find.text('5 min'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(SleepTimerService.instance.remainingTime.inMinutes, greaterThanOrEqualTo(29));

    // Tap Turn Off Sleep Timer
    await tester.tap(find.text('Turn Off Sleep Timer'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(SleepTimerService.instance.isActive, isFalse);
  });
}
