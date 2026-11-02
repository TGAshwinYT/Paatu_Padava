import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/core/dsa/minhash.dart';
import 'package:paatu_padava_mobile/services/semantic_search_service.dart';
import 'package:paatu_padava_mobile/ui/widgets/common/cascading_cover_image.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MinHash & Jaccard Fingerprinting Tests', () {
    test('Identical texts produce identical MinHash signatures with 1.0 similarity', () {
      final minhash = MinHash();
      final sigA = minhash.computeFromText('Arabic Kuthu Halamithi Habibo');
      final sigB = minhash.computeFromText('Arabic Kuthu Halamithi Habibo');

      expect(sigA.similarity(sigB), equals(1.0));
      expect(sigA.isDuplicate(sigB, threshold: 0.90), isTrue);
    });

    test('Near-duplicate titles with extra metadata produce high MinHash similarity', () {
      final minhash = MinHash();
      // JioSaavn format vs YouTube music video title format
      final sigA = minhash.computeFromText('Arabic Kuthu Halamithi Habibo Beast Anirudh');
      final sigB = minhash.computeFromText('Arabic Kuthu Video Song Beast Thalapathy Vijay Anirudh');

      final sim = sigA.similarity(sigB);
      // MinHash should estimate substantial overlap (> 0.40) between the shared shingles
      expect(sim, greaterThan(0.40));
    });

    test('Completely dissimilar titles yield near-zero MinHash similarity', () {
      final minhash = MinHash();
      final sigA = minhash.computeFromText('Arabic Kuthu Beast Anirudh');
      final sigB = minhash.computeFromText('Chinna Chinna Aasai Roja AR Rahman');

      final sim = sigA.similarity(sigB);
      expect(sim, lessThan(0.15));
      expect(sigA.isDuplicate(sigB, threshold: 0.50), isFalse);
    });

    test('SongRepository.deduplicateByMinHash filters near-identical tracks across providers', () {
      final songs = [
        const Song(
          id: 'saavn_1',
          title: 'Arabic Kuthu',
          artist: 'Anirudh Ravichander, Jonita Gandhi',
          album: 'Beast',
          coverUrl: 'https://c.saavncdn.com/123/500x500.jpg',
          source: 'saavn',
        ),
        const Song(
          id: 'yt_1',
          title: 'Arabic Kuthu',
          artist: 'Anirudh Ravichander, Jonita Gandhi',
          album: 'Beast',
          coverUrl: 'https://img.youtube.com/vi/abc/hqdefault.jpg',
          source: 'youtube',
        ),
        const Song(
          id: 'saavn_2',
          title: 'Hukum - Thalaivar Alappara',
          artist: 'Anirudh Ravichander',
          album: 'Jailer',
          coverUrl: 'https://c.saavncdn.com/456/500x500.jpg',
          source: 'saavn',
        ),
      ];

      final deduped = SongRepository.deduplicateByMinHash(songs, threshold: 0.80);
      expect(deduped.length, equals(2));
      expect(deduped[0].id, equals('saavn_1'));
      expect(deduped[1].id, equals('saavn_2'));
    });
  });

  group('Vector Embeddings & Semantic Search Tests', () {
    test('projectQuery identifies mood intent keywords into normalized unit vectors', () {
      final vec = SemanticSearchService.instance.projectQuery('late night sad drive');
      expect(vec, isNotNull);
      expect(vec!.isZero, isFalse);

      // Dimension 1 (Melancholy) and 3 (Chill/Night) should have significant magnitude
      expect(vec.values[1], greaterThan(0.0));
      expect(vec.values[3], greaterThan(0.0));
      expect(vec.magnitude, closeTo(1.0, 0.001));
    });

    test('Neutral entity query (movie or artist name) returns null for semantic projection', () {
      final vec = SemanticSearchService.instance.projectQuery('Leo Vijay Lokesh');
      expect(vec, isNull);
    });

    test('Cosine similarity scores matching mood tracks higher', () {
      final sadQueryVec = SemanticSearchService.instance.projectQuery('heartbreak sad crying')!;

      const sadSong = Song(
        id: 's_1',
        title: 'Po Nee Po (The Pain of Love)',
        artist: 'Anirudh Ravichander, Mohit Chauhan',
        album: '3',
        coverUrl: '',
      );

      const partySong = Song(
        id: 's_2',
        title: 'Aaluma Doluma Party Dance Beat',
        artist: 'Anirudh Ravichander, Badshah',
        album: 'Vedalam',
        coverUrl: '',
      );

      final sadScore = SemanticSearchService.instance.scoreSong(sadSong, sadQueryVec);
      final partyScore = SemanticSearchService.instance.scoreSong(partySong, sadQueryVec);

      expect(sadScore, greaterThan(partyScore));
    });

    test('rankBySemanticIntent re-ranks songs when query specifies vibe', () {
      final songs = [
        const Song(
          id: 's_1',
          title: 'Aaluma Doluma Party Dance Beat',
          artist: 'Anirudh Ravichander',
          album: 'Vedalam',
          coverUrl: '',
        ),
        const Song(
          id: 's_2',
          title: 'Po Nee Po (The Pain of Love)',
          artist: 'Anirudh Ravichander',
          album: '3',
          coverUrl: '',
        ),
      ];

      final ranked = SemanticSearchService.instance.rankBySemanticIntent(songs, 'sad crying heartbreak');
      // The sad song should be boosted to the top
      expect(ranked.first.id, equals('s_2'));
    });
  });

  group('Cascading Thumbnail Resolution Tests', () {
    test('deriveLowResUrl extracts 150x150 for JioSaavn 500x500 covers', () {
      const saavnHighRes = 'https://c.saavncdn.com/123/Beast-Tamil-500x500.jpg';
      final lowRes = CascadingCoverImage.deriveLowResUrl(saavnHighRes);
      expect(lowRes, equals('https://c.saavncdn.com/123/Beast-Tamil-150x150.jpg'));
    });

    test('deriveLowResUrl extracts default.jpg for YouTube covers', () {
      const ytHq = 'https://img.youtube.com/vi/abc123xyz/hqdefault.jpg';
      final lowRes = CascadingCoverImage.deriveLowResUrl(ytHq);
      expect(lowRes, equals('https://img.youtube.com/vi/abc123xyz/default.jpg'));
    });
  });
}
