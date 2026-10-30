import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/player_scrubber.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final song = Song(id: 'b1', title: 'T', artist: 'A', album: 'B', duration: 200, coverUrl: '');

  setUp(() {
    audioHandler = PaatuAudioHandler();
  });

  test('formatDuration handles hour-long tracks', () {
    expect(PlayerScrubber.formatDuration(const Duration(seconds: 200)), '03:20');
    expect(PlayerScrubber.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  testWidgets('slider exposes a buffered (secondary) track and keeps the old labels', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlayerScrubber(song: song))));
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.secondaryTrackValue, isNotNull);
    expect(slider.secondaryTrackValue!, greaterThanOrEqualTo(slider.value));
    expect(slider.secondaryTrackValue!, lessThanOrEqualTo(slider.max));
    expect(find.text('03:20'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    // Nothing downloaded yet -> no percentage label
    expect(find.byKey(const Key('scrubber_loaded_percent')), findsNothing);
  });
}
