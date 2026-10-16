import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/domain/models/home_feed_models.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/logic/home_feed_provider.dart';
import 'package:paatu_padava_mobile/ui/screens/home_settings_screen.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/feeling_chips_bar.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/top_hits_hero_card.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/numbered_chart_view.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/quick_picks_grid_carousel.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/mood_station_card.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tempDir = Directory.systemTemp.createTempSync('home_feed_test_hive_');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(SettingsManager.boxName)) {
      await Hive.openBox(SettingsManager.boxName);
    }
    await SettingsManager.init();
  });

  tearDownAll(() async {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final testSong1 = Song(
    id: 'test_song_1',
    title: 'Hukum - Thalaivar Alappara',
    artist: 'Anirudh Ravichander',
    album: 'Jailer',
    coverUrl: '',
    duration: 205,
    source: 'saavn',
    language: 'Tamil',
  );

  final testSong2 = Song(
    id: 'test_song_2',
    title: 'Naa Ready',
    artist: 'Anirudh Ravichander, Thalapathy Vijay',
    album: 'Leo',
    coverUrl: '',
    duration: 248,
    source: 'saavn',
    language: 'Tamil',
  );

  group('Next-Gen Home Feed Domain Models', () {
    test('HeroShowcase serialization and deserialization', () {
      final showcase = HeroShowcase(
        title: "Today's Top Tamil Hits",
        subtitle: 'The hottest tracks dominating the Tamil music industry',
        description: 'Updated daily • Curated strictly with pure lossless audio',
        coverUrl: 'https://c.saavncdn.com/cover.jpg',
        gradientColors: const [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
        tracks: [testSong1, testSong2],
      );

      final map = showcase.toMap();
      final reconstructed = HeroShowcase.fromMap(map);

      expect(reconstructed.title, "Today's Top Tamil Hits");
      expect(reconstructed.subtitle, 'The hottest tracks dominating the Tamil music industry');
      expect(reconstructed.tracks.length, 2);
      expect(reconstructed.tracks.first.id, 'test_song_1');
      expect(reconstructed.gradientColors.length, 2);
    });

    test('RankedChartSong rank tracking and serialization', () {
      final item = RankedChartSong(
        rank: 1,
        song: testSong1,
        rankChange: 2,
        isNew: false,
      );

      final map = item.toMap();
      final reconstructed = RankedChartSong.fromMap(map);

      expect(reconstructed.rank, 1);
      expect(reconstructed.song.title, 'Hukum - Thalaivar Alappara');
      expect(reconstructed.rankChange, 2);
      expect(reconstructed.isNew, false);

      final newItem = RankedChartSong(
        rank: 8,
        song: testSong2,
        rankChange: 0,
        isNew: true,
      );
      final newMap = newItem.toMap();
      final newReconstructed = RankedChartSong.fromMap(newMap);
      expect(newReconstructed.rank, 8);
      expect(newReconstructed.isNew, true);
    });

    test('FeelingMix mood bundle serialization', () {
      final mix = FeelingMix(
        feelingId: 'chill',
        title: '🌙 Chill & Soul',
        subtitle: 'Relaxing acoustic & serene melodies',
        icon: '🌙',
        gradient: const [Color(0xFF1E1B4B), Color(0xFF4338CA)],
        songs: [testSong1],
      );

      final map = mix.toMap();
      final reconstructed = FeelingMix.fromMap(map);

      expect(reconstructed.feelingId, 'chill');
      expect(reconstructed.title, '🌙 Chill & Soul');
      expect(reconstructed.icon, '🌙');
      expect(reconstructed.songs.length, 1);
    });
  });

  group('Home Feed Settings & Customization Preferences', () {
    test('SettingsManager updates home Hero banner mode', () async {
      await SettingsManager.setHomeHeroBannerMode('flagship');
      expect(SettingsManager.homeHeroBannerMode, 'flagship');

      await SettingsManager.setHomeHeroBannerMode('smart');
      expect(SettingsManager.homeHeroBannerMode, 'smart');
    });

    test('SettingsManager updates top 10 chart layout mode', () async {
      await SettingsManager.setHomeTop10ChartLayout('horizontal');
      expect(SettingsManager.homeTop10ChartLayout, 'horizontal');

      await SettingsManager.setHomeTop10ChartLayout('vertical');
      expect(SettingsManager.homeTop10ChartLayout, 'vertical');
    });

    test('SettingsManager privacy toggle for remembering feeling', () async {
      await SettingsManager.setHomeRememberFeeling(true);
      expect(SettingsManager.isHomeRememberFeelingEnabled, true);

      await SettingsManager.setHomeRememberFeeling(false);
      expect(SettingsManager.isHomeRememberFeelingEnabled, false);
    });

    test('SettingsManager quick picks toggle', () async {
      await SettingsManager.setHomeShowQuickPicks(false);
      expect(SettingsManager.isHomeShowQuickPicksEnabled, false);

      await SettingsManager.setHomeShowQuickPicks(true);
      expect(SettingsManager.isHomeShowQuickPicksEnabled, true);
    });
  });

  group('HomeFeedProvider State & Mood Switching', () {
    test('setActiveFeeling updates active feeling and notifies listeners', () {
      final provider = HomeFeedProvider.instance;
      expect(provider.state.activeFeeling, 'all');

      provider.setActiveFeeling('chill');
      expect(provider.state.activeFeeling, 'chill');

      provider.setActiveFeeling('kuthu');
      expect(provider.state.activeFeeling, 'kuthu');

      provider.setActiveFeeling('all');
      expect(provider.state.activeFeeling, 'all');
    });

    test('HomeFeedState isEmpty correctly considers heroShowcase', () {
      const emptyState = HomeFeedState();
      expect(emptyState.isEmpty, true);

      final stateWithHero = HomeFeedState(
        heroShowcase: HeroShowcase(
          title: 'Hits',
          subtitle: 'Sub',
          description: 'Desc',
          coverUrl: '',
          gradientColors: const [],
          tracks: [testSong1],
        ),
      );
      expect(stateWithHero.isEmpty, false);
    });
  });

  group('Next-Gen UI Widgets Rendering Tests', () {
    testWidgets('FeelingChipsBar renders all feeling chips and handles selection', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FeelingChipsBar(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Chill & Soul'), findsOneWidget);
      expect(find.text('Romance'), findsOneWidget);
      expect(find.text('High Energy'), findsOneWidget);

      await tester.tap(find.text('Chill & Soul'));
      await tester.pumpAndSettle();
      expect(HomeFeedProvider.instance.state.activeFeeling, 'chill');

      // Reset
      HomeFeedProvider.instance.setActiveFeeling('all');
    });

    testWidgets('TopHitsHeroCard renders editorial banner with title and badge', (tester) async {
      final showcase = HeroShowcase(
        title: "Today's Top Tamil Hits",
        subtitle: 'The hottest tracks dominating the Tamil music industry',
        description: 'Editorial Chart',
        coverUrl: '',
        gradientColors: const [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
        tracks: [testSong1, testSong2],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopHitsHeroCard(showcase: showcase),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("Today's Top Tamil Hits"), findsOneWidget);
      expect(find.text('SPOTIFY EDITORIAL • TOP 50'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('NumberedChartView renders ranked badges in vertical mode', (tester) async {
      SettingsManager.homeTop10ChartLayoutNotifier.value = 'vertical';

      final chartList = [
        RankedChartSong(rank: 1, song: testSong1, rankChange: 0, isNew: false),
        RankedChartSong(rank: 2, song: testSong2, rankChange: 1, isNew: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberedChartView(charts: chartList),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Top 10 Official Charts'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('Hukum - Thalaivar Alappara'), findsOneWidget);
      expect(find.text('Naa Ready'), findsOneWidget);
    });

    testWidgets('QuickPicksGridCarousel renders YouTube Music column rows', (tester) async {
      final songs = [testSong1, testSong2, testSong1, testSong2];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickPicksGridCarousel(songs: songs),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Quick Picks'), findsOneWidget);
      expect(find.text('Start radio or jump in'), findsOneWidget);
    });

    testWidgets('MoodStationCard renders panoramic card with emoji', (tester) async {
      final mix = FeelingMix(
        feelingId: 'night',
        title: '🌃 Late Night Drive',
        subtitle: 'Atmospheric synths',
        icon: '🌃',
        gradient: const [Color(0xFF0F172A), Color(0xFF581C87)],
        songs: [testSong1],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoodStationCard(mix: mix),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('🌃 Late Night Drive'), findsOneWidget);
      expect(find.text('Atmospheric synths'), findsOneWidget);
    });

    testWidgets('HomeSettingsScreen renders all customization switches and privacy card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeSettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Home Feed & Experience'), findsOneWidget);
      expect(find.text('Smart Adaptive (Recommended)'), findsOneWidget);
      expect(find.text('Spotify Top 50 Chart'), findsOneWidget);
      expect(find.text('Time-of-Day Vibe'), findsOneWidget);
      expect(find.text('Ranked List'), findsOneWidget);
      expect(find.text('3D Card Slider'), findsOneWidget);
      expect(find.text('Remember Last Mood / Feeling Filter'), findsOneWidget);
      expect(find.text('Zero-Permission Storage Architecture'), findsOneWidget);
    });
  });
}
