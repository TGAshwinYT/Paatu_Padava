import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/volume_hud_overlay.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/player_gesture_detector.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VolumeHudOverlay Widget Tests', () {
    testWidgets('Renders volume percentage and icon correctly at 75%', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VolumeHudOverlay(
              volume: 0.75,
              isVisible: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('75%'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('Renders volume_off icon at 0% volume', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VolumeHudOverlay(
              volume: 0.0,
              isVisible: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('0%'), findsOneWidget);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('Renders volume_down icon at 50% volume', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VolumeHudOverlay(
              volume: 0.50,
              isVisible: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
    });
  });

  group('PlayerGestureDetector Widget Tests', () {
    testWidgets('Renders wrapped child container within Stack', (tester) async {
      SettingsManager.playerGesturesEnabledNotifier.value = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlayerGestureDetector(
              child: SizedBox(
                key: Key('artwork_test_box'),
                width: 200,
                height: 200,
                child: Text('Cover Artwork'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cover Artwork'), findsOneWidget);
      expect(find.byKey(const Key('artwork_test_box')), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('Renders direct child without gesture interceptor when disabled', (tester) async {
      SettingsManager.playerGesturesEnabledNotifier.value = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlayerGestureDetector(
              child: SizedBox(
                key: Key('artwork_disabled_box'),
                width: 200,
                height: 200,
                child: Text('Disabled Gestures Artwork'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Disabled Gestures Artwork'), findsOneWidget);
      expect(find.byType(PlayerGestureDetector), findsOneWidget);
      // When disabled, no gesture interceptor or HUD stack is built
      expect(find.byType(VolumeHudOverlay), findsNothing);

      // Restore setting
      SettingsManager.playerGesturesEnabledNotifier.value = true;
    });
  });
}
