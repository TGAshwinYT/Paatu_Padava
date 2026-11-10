import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/lyrics_state.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';
import 'package:paatu_padava_mobile/ui/screens/lyrics_screen.dart';
import 'package:paatu_padava_mobile/ui/widgets/lyrics/karaoke_vocal_slider.dart';
import 'package:paatu_padava_mobile/ui/widgets/lyrics/studio_karaoke_pill.dart';
import 'package:paatu_padava_mobile/ui/widgets/lyrics/lyrics_top_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSong = Song(
    id: 'test_song_1',
    title: 'Test Song Title Long Name',
    artist: 'Test Artist Featuring Guest Star',
    coverUrl: 'https://example.com/cover.jpg',
    duration: 180,
  );

  setUp(() {
    audioHandler = PaatuAudioHandler();
    audioHandler.isKaraokeModeNotifier.value = false;
    audioHandler.studioKaraokeTrackNotifier.value = null;
  });

  testWidgets('LyricsScreen builds and renders with lyrics', (tester) async {
    const lrc = '''
[00:10.00] First lyric line
[00:20.00] Second lyric line
''';
    audioHandler.currentSongNotifier.value = testSong;
    audioHandler.currentLyricsNotifier.value = lrc;
    audioHandler.lyricsStateNotifier.value = const LyricsState.loaded(lrc);

    await tester.pumpWidget(
      MaterialApp(
        home: LyricsScreen(initialSong: testSong),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LyricsTopBar), findsOneWidget);
    expect(find.text('First lyric line'), findsOneWidget);
    expect(find.byType(KaraokeVocalSlider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LyricsScreen renders in Karaoke Mode with Studio Karaoke Pill and Slider', (tester) async {
    const lrc = '''
[00:10.00] First lyric line
[00:20.00] Second lyric line
''';
    audioHandler.currentSongNotifier.value = testSong;
    audioHandler.currentLyricsNotifier.value = lrc;
    audioHandler.lyricsStateNotifier.value = const LyricsState.loaded(lrc);
    audioHandler.isKaraokeModeNotifier.value = true;
    audioHandler.studioKaraokeTrackNotifier.value = testSong;

    await tester.pumpWidget(
      MaterialApp(
        home: LyricsScreen(initialSong: testSong),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(KaraokeVocalSlider), findsOneWidget);
    expect(find.byType(StudioKaraokePill), findsOneWidget);
    expect(find.byType(LyricsTopBar), findsOneWidget);
    expect(find.text('First lyric line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LyricsScreen renders empty/null lyrics without crash', (tester) async {
    audioHandler.currentSongNotifier.value = testSong;
    audioHandler.currentLyricsNotifier.value = null;
    audioHandler.lyricsStateNotifier.value = const LyricsState.idle();

    await tester.pumpWidget(
      MaterialApp(
        home: LyricsScreen(initialSong: testSong),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LyricsTopBar), findsOneWidget);
    expect(find.byType(KaraokeVocalSlider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LyricsScreen survives small-phone 360x640 at 1.5x font scale without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    const lrc = '''
[00:05.00] Active line on small phone
[00:15.00] Next line on small phone
''';
    audioHandler.currentSongNotifier.value = testSong;
    audioHandler.currentLyricsNotifier.value = lrc;
    audioHandler.lyricsStateNotifier.value = const LyricsState.loaded(lrc);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.5),
            padding: EdgeInsets.only(top: 24, bottom: 16),
          ),
          child: LyricsScreen(initialSong: testSong),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LyricsTopBar), findsOneWidget);
    expect(find.text('Active line on small phone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
