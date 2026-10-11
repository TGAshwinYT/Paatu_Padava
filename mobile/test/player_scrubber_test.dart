import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/player_scrubber.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSong = Song(
    id: 'scrub_01',
    title: 'Aalaporaan Thamizhan',
    artist: 'A.R. Rahman',
    album: 'Mersal',
    duration: 200,
    coverUrl: 'https://example.com/cover.jpg',
  );

  setUp(() {
    audioHandler = PaatuAudioHandler();
  });

  group('PlayerScrubber Widget & Scrubbing Isolation Tests', () {
    testWidgets('Renders isolated scrubber with correct duration format', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerScrubber(song: testSong),
          ),
        ),
      );

      await tester.pump();

      // Total duration for 200s is 03:20
      expect(find.text('03:20'), findsOneWidget);
      // Initial position is 00:00
      expect(find.text('00:00'), findsOneWidget);
      // Slider is present
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('Scrubbing slider smoothly updates without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerScrubber(song: testSong),
          ),
        ),
      );

      await tester.pump();

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      // Drag slider forward
      await tester.drag(sliderFinder, const Offset(50.0, 0.0));
      await tester.pump();

      expect(sliderFinder, findsOneWidget);
    });
  });
}
