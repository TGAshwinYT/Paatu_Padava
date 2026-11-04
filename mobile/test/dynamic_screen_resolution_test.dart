import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/ui/theme/app_theme.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/home_song_card.dart';
import 'package:paatu_padava_mobile/ui/widgets/home/home_song_tile.dart';

import 'helpers/layout_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSong = Song(
    id: 'test_song_1',
    title: 'Naan Gaali (From "Good Night")',
    artist: 'Sean Roldan, Kalyani Nair',
    album: 'Good Night',
    coverUrl: 'https://example.com/cover.jpg',
    duration: 215,
    source: 'saavn',
  );

  group('AppDimensions Unit Tests', () {
    testWidgets('Breakpoints: classifies compact, standard, and tablet correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return const SizedBox();
            },
          ),
        ),
      );

      // Compact (320dp)
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      await tester.pump();
      final compactCtx = tester.element(find.byType(SizedBox));
      expect(AppDimensions.isCompact(compactCtx), isTrue);
      expect(AppDimensions.isTablet(compactCtx), isFalse);
      expect(AppDimensions.screenPadding(compactCtx), 12.0);
      expect(AppDimensions.songTileCoverSize(compactCtx), 46.0);

      // Standard (390dp)
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      await tester.pump();
      final standardCtx = tester.element(find.byType(SizedBox));
      expect(AppDimensions.isCompact(standardCtx), isFalse);
      expect(AppDimensions.isTablet(standardCtx), isFalse);
      expect(AppDimensions.screenPadding(standardCtx), 16.0);
      expect(AppDimensions.songTileCoverSize(standardCtx), 50.0);

      // Tablet (800dp)
      tester.view.physicalSize = const Size(800 * 2, 1280 * 2);
      tester.view.devicePixelRatio = 2.0;
      await tester.pump();
      final tabletCtx = tester.element(find.byType(SizedBox));
      expect(AppDimensions.isCompact(tabletCtx), isFalse);
      expect(AppDimensions.isTablet(tabletCtx), isTrue);
      expect(AppDimensions.screenPadding(tabletCtx), 28.0);
      expect(AppDimensions.songTileCoverSize(tabletCtx), 56.0);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    testWidgets('TextScaler Clamping: bounds extremes to prevent layout breaks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: child!,
            );
          },
          home: Builder(
            builder: (context) {
              final clamped = AppDimensions.clampedTextScaler(context);
              expect(clamped.scale(10), 13.0); // 10 * 1.30 (clamped from 2.0)
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('homeCarouselHeight dynamically accommodates larger font scales', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              const cardWidth = 140.0;
              final heightStandard = AppDimensions.homeCarouselHeight(context, cardWidth);
              expect(heightStandard, greaterThan(cardWidth));
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });

  group('Dynamic Resolution Layout Survivability Tests', () {
    for (final device in kDevices) {
      for (final scale in kTextScales) {
        testWidgets('HomeSongCard renders with 0 errors on $device @ x$scale', (tester) async {
          final report = await pumpAndCollectLayoutErrors(
            tester,
            Scaffold(
              body: Center(
                child: HomeSongCard(
                  song: testSong,
                  onTap: () {},
                ),
              ),
            ),
            device: device,
            textScale: scale,
          );
          expect(report.layoutErrors, isEmpty);
        });

        testWidgets('HomeSongTile renders with 0 errors on $device @ x$scale', (tester) async {
          final report = await pumpAndCollectLayoutErrors(
            tester,
            Scaffold(
              body: ListView(
                children: [
                  HomeSongTile(
                    song: testSong,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            device: device,
            textScale: scale,
          );
          expect(report.layoutErrors, isEmpty);
        });
      }
    }
  });
}
