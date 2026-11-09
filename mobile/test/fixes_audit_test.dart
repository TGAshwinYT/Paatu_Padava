import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';
import 'package:paatu_padava_mobile/logic/queue/queue_tuner_controller.dart';
import 'package:paatu_padava_mobile/logic/queue/queue_tuner_mode.dart';
import 'package:paatu_padava_mobile/logic/track_quality_filter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fixes_audit_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(FavoritesManager.boxName);
    await Hive.openBox(HistoryManager.boxName);
    await Hive.openBox(HistoryManager.pendingBoxName);
    await Hive.openBox(SettingsManager.boxName);
    QueueCooldownManager.clear();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    QueueCooldownManager.clear();
  });

  group('Issue 1: Artist Avatar Resolution & Deduplication', () {
    test('K. J. Yesudas resolves to working high-res avatar regardless of punctuation', () {
      final avatar1 = SongRepository.getVerifiedAvatar('K. J. Yesudas');
      final avatar2 = SongRepository.getVerifiedAvatar('K.J. Yesudas');
      final avatar3 = SongRepository.getVerifiedAvatar('KJ Yesudas');
      final avatar4 = SongRepository.getVerifiedAvatar('Yesudas');

      expect(avatar1, isNotEmpty);
      expect(avatar1, contains('KJ_Yesudas_500x500.webp'));
      expect(avatar2, equals(avatar1));
      expect(avatar3, equals(avatar1));
      expect(avatar4, equals(avatar1));
    });

    test('A. R. Rahman and G. V. Prakash resolve verified avatars across variants', () {
      final rahman1 = SongRepository.getVerifiedAvatar('A. R. Rahman');
      final rahman2 = SongRepository.getVerifiedAvatar('A.R. Rahman');
      final rahman3 = SongRepository.getVerifiedAvatar('AR Rahman');

      expect(rahman1, isNotEmpty);
      expect(rahman2, equals(rahman1));
      expect(rahman3, equals(rahman1));

      final gv1 = SongRepository.getVerifiedAvatar('G. V. Prakash');
      final gv2 = SongRepository.getVerifiedAvatar('G.V. Prakash Kumar');
      expect(gv1, isNotEmpty);
      expect(gv2, isNotEmpty);
    });
  });

  group('Issue 2: Search Duplicate Song Elimination', () {
    test('groupCanonicalSongs groups multiple title/artist variations into one canonical track', () {
      final s1 = Song(
        id: 'saavn_1',
        title: 'Endhayya Saami (From "Ranabaali")',
        artist: 'Ajay-Atul, Ajay Gogavale, Shweta Mohan',
        album: 'Ranabaali',
        coverUrl: 'https://example.com/cover1.jpg',
        duration: 240,
        source: 'saavn',
      );
      final s2 = Song(
        id: 'saavn_2',
        title: 'Endhayya Saami',
        artist: 'Santhosh Narayanan, Ajay-Atul',
        album: 'Ranabaali - Telugu',
        coverUrl: 'https://example.com/cover2.jpg',
        duration: 242,
        source: 'saavn',
      );

      final grouped = SongRepository.groupCanonicalSongs([s1, s2]);
      expect(grouped.length, equals(1));
      expect(grouped.first.title, contains('Endhayya Saami'));
      expect(grouped.first.versions.length, equals(1));
    });
  });

  group('Issue 3: Devotional Quarantine in Queue Familiar Mode', () {
    final mainstreamSeed = Song(
      id: 'seed_pop',
      title: 'Hayati',
      artist: 'Anirudh Ravichander',
      album: 'Vettaiyan',
      coverUrl: '',
      language: 'Tamil',
      duration: 210,
    );

    final devotionalSong1 = Song(
      id: 'devo_1',
      title: 'Srinivasane Varavendum',
      artist: 'Veeramanidasan',
      album: 'Perumale Venkataperumale',
      coverUrl: '',
      language: 'Tamil',
      duration: 280,
    );

    final devotionalSong2 = Song(
      id: 'devo_2',
      title: 'Thirumalaiyil Sri Srinivasa',
      artist: 'Bombay Sisters',
      album: 'Srinivasa Vaibhavam (Tamil Devotional)',
      coverUrl: '',
      language: 'Tamil',
      duration: 310,
    );

    final mainstreamTrack = Song(
      id: 'mainstream_1',
      title: 'Badass',
      artist: 'Anirudh Ravichander',
      album: 'Leo',
      coverUrl: '',
      language: 'Tamil',
      duration: 220,
    );

    test('TrackQualityFilter correctly identifies devotional songs', () {
      expect(TrackQualityFilter.isDevotionalSong(devotionalSong1), isTrue);
      expect(TrackQualityFilter.isDevotionalSong(devotionalSong2), isTrue);
      expect(TrackQualityFilter.isDevotionalSong(mainstreamSeed), isFalse);
      expect(TrackQualityFilter.isDevotionalSong(mainstreamTrack), isFalse);
    });

    test('QueueTunerController._rankForFamiliar strictly drops devotional songs when seed is mainstream', () async {
      final candidates = [devotionalSong1, devotionalSong2, mainstreamTrack];
      final ranked = await QueueTunerController.filterAndRankCandidates(
        seedSong: mainstreamSeed,
        candidates: candidates,
        mode: QueueTunerMode.familiar,
      );

      expect(ranked.any((s) => s.id == devotionalSong1.id), isFalse);
      expect(ranked.any((s) => s.id == devotionalSong2.id), isFalse);
      expect(ranked.any((s) => s.id == mainstreamTrack.id), isTrue);
    });
  });
}
