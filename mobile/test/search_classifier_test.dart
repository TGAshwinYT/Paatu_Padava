import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/clustered_track_result.dart';
import 'package:paatu_padava_mobile/logic/search_query_planner.dart';
import 'package:paatu_padava_mobile/logic/track_quality_filter.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  group('TrackQualityFilter Content Classification Tests', () {
    test('Correctly identifies non-music video junk (reviews, reactions, trailers, shorts)', () {
      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Leo Movie Public Review | Thalapathy Vijay | Lokesh Kanagaraj',
          durationSec: 320,
          source: 'youtube',
        ),
        equals(ContentClassification.rejectedJunk),
      );

      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Foreigner Reacts to Naa Ready Song | Leo Reaction',
          durationSec: 450,
          source: 'youtube',
        ),
        equals(ContentClassification.rejectedJunk),
      );

      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Vettaiyan Official Teaser | Rajinikanth | Anirudh',
          durationSec: 85,
          source: 'youtube',
        ),
        equals(ContentClassification.rejectedJunk),
      );

      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Anirudh viral dance #shorts',
          durationSec: 30,
          source: 'youtube',
        ),
        equals(ContentClassification.rejectedJunk),
      );
    });

    test('Rejects YouTube videos with invalid duration bounds (< 45s or > 720s)', () {
      // 30s promo/ringtone
      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Arabic Kuthu Ringtone Promo',
          durationSec: 30,
          source: 'youtube',
        ),
        equals(ContentClassification.rejectedJunk),
      );

      // 15-minute commentary / stream
      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Music Director Discussion 2024',
          durationSec: 900,
          source: 'youtube',
        ),
        equals(ContentClassification.rejectedJunk),
      );
    });

    test('Tags fanbase mixes, mashups, slowed+reverb, and BGMs as fanMixOrVersion', () {
      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Arabic Kuthu - Slowed + Reverb | Lofi Chill Beats',
          durationSec: 260,
          source: 'youtube',
        ),
        equals(ContentClassification.fanMixOrVersion),
      );

      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Ordinary Person - Badass BGM Theme (Original Soundtrack)',
          durationSec: 190,
          source: 'youtube',
        ),
        equals(ContentClassification.fanMixOrVersion),
      );

      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Hukum x Badass Epic Mashup | DJ Remix',
          durationSec: 240,
          source: 'youtube',
        ),
        equals(ContentClassification.fanMixOrVersion),
      );
    });

    test('Classifies verified studio tracks as officialTrack', () {
      // JioSaavn studio track
      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Arabic Kuthu',
          durationSec: 280,
          source: 'saavn',
        ),
        equals(ContentClassification.officialTrack),
      );

      // YouTube Music standard audio track
      expect(
        TrackQualityFilter.classifyTrack(
          title: 'Arabic Kuthu (From "Beast")',
          durationSec: 280,
          source: 'youtube',
        ),
        equals(ContentClassification.officialTrack),
      );
    });
  });

  group('SearchQueryPlanner Intent & Relevance Scoring Tests', () {
    test('analyzeQuery identifies query intent types accurately', () {
      final q1 = SearchQueryPlanner.analyzeQuery('Ordinary Person bgm');
      expect(q1.intentType, equals(QueryIntentType.mixOrBgm));
      expect(q1.isExplicitMixRequest, isTrue);

      final q2 = SearchQueryPlanner.analyzeQuery('Leo movie soundtrack');
      expect(q2.intentType, equals(QueryIntentType.collectionOrMovie));

      final q3 = SearchQueryPlanner.analyzeQuery('Anirudh best of hits');
      expect(q3.intentType, equals(QueryIntentType.artist));

      final q4 = SearchQueryPlanner.analyzeQuery('Katchi Sera');
      expect(q4.intentType, equals(QueryIntentType.song));
      expect(q4.isExplicitMixRequest, isFalse);
    });

    test('extractNormalizedCoreTitle clusters variations to identical core title', () {
      final core1 = SearchQueryPlanner.extractNormalizedCoreTitle('Arabic Kuthu - Lofi Flip (Slowed + Reverb)');
      final core2 = SearchQueryPlanner.extractNormalizedCoreTitle('Arabic Kuthu (From "Beast") [Official Video]');
      final core3 = SearchQueryPlanner.extractNormalizedCoreTitle('Arabic Kuthu');

      expect(core1, equals('arabic kuthu'));
      expect(core2, equals('arabic kuthu'));
      expect(core3, equals('arabic kuthu'));
    });

    test('calculateRelevanceScore enforces confidence >= 0.85 for Top Result Crown', () {
      final officialSong = Song(
        id: 's1',
        title: 'Arabic Kuthu',
        artist: 'Anirudh Ravichander, Jonita Gandhi',
        source: 'saavn',
        coverUrl: '',
      );

      final lofiSong = Song(
        id: 's2',
        title: 'Arabic Kuthu Lofi Remix',
        artist: 'Fan Channel',
        source: 'youtube',
        coverUrl: '',
      );

      final scoreOfficial = SearchQueryPlanner.calculateRelevanceScore(
        query: 'Arabic Kuthu',
        song: officialSong,
        classification: ContentClassification.officialTrack,
      );

      final scoreLofi = SearchQueryPlanner.calculateRelevanceScore(
        query: 'Arabic Kuthu',
        song: lofiSong,
        classification: ContentClassification.fanMixOrVersion,
      );

      // Official track should pass the 0.85 threshold
      expect(scoreOfficial, greaterThanOrEqualTo(0.85));
      // Unsolicited fan mix should be penalized under 0.85
      expect(scoreLofi, lessThan(0.85));
    });
  });
}
