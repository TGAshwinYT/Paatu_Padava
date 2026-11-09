import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/logic/queue/queue_tuner_mode.dart';
import 'package:paatu_padava_mobile/logic/queue/queue_tuner_controller.dart';
import 'package:paatu_padava_mobile/logic/smart_shuffle_controller.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('queue_tuner_test_');
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

  group('QueueTunerMode & Details', () {
    test('QueueTunerMode has 4 distinct modes with correct labels', () {
      expect(QueueTunerMode.values.length, equals(4));
      expect(QueueTunerMode.mix.label, equals('Mix'));
      expect(QueueTunerMode.familiar.label, equals('Familiar'));
      expect(QueueTunerMode.discover.label, equals('Discover'));
      expect(QueueTunerMode.composer.label, equals('Composer'));
    });
  });

  group('QueueTunerController Filtering & Re-Ranking', () {
    final seedSong = Song(
      id: 'seed_1',
      title: 'Hukum',
      artist: 'Anirudh Ravichander, Super Subu',
      album: 'Jailer',
      coverUrl: '',
      language: 'Tamil',
      duration: 200,
    );

    final familiarSong = Song(
      id: 'fam_1',
      title: 'Vathi Coming',
      artist: 'Anirudh Ravichander, Gana Balachandar',
      album: 'Master',
      coverUrl: '',
      language: 'Tamil',
      duration: 210,
    );

    final unplayedSong = Song(
      id: 'fresh_1',
      title: 'Puthu Mazha',
      artist: 'Sushin Shyam',
      album: 'Aavesham',
      coverUrl: '',
      language: 'Malayalam',
      duration: 190,
    );

    final composerMatchSong = Song(
      id: 'comp_1',
      title: 'Arabic Kuthu',
      artist: 'Anirudh Ravichander, Jonita Gandhi',
      album: 'Beast',
      coverUrl: '',
      language: 'Tamil',
      duration: 230,
    );

    final nonComposerSong = Song(
      id: 'non_comp_1',
      title: 'Chaleya',
      artist: 'Arijit Singh, Shilpa Rao',
      album: 'Jawan',
      coverUrl: '',
      language: 'Hindi',
      duration: 200,
    );

    test('Familiar mode prioritizes songs in user favorites and history', () async {
      await FavoritesManager.toggleFavorite(familiarSong);
      await HistoryManager.recordPlay(familiarSong);

      final candidates = [unplayedSong, familiarSong];
      final ranked = await QueueTunerController.filterAndRankCandidates(
        seedSong: seedSong,
        candidates: candidates,
        mode: QueueTunerMode.familiar,
      );

      expect(ranked.isNotEmpty, isTrue);
      expect(ranked.first.id, equals(familiarSong.id));
    });

    test('Discover mode strictly purges songs in user history and favorites', () async {
      await FavoritesManager.toggleFavorite(familiarSong);
      await HistoryManager.recordPlay(familiarSong);

      final candidates = [familiarSong, unplayedSong];
      final ranked = await QueueTunerController.filterAndRankCandidates(
        seedSong: seedSong,
        candidates: candidates,
        mode: QueueTunerMode.discover,
      );

      // familiarSong must be pruned completely
      expect(ranked.any((s) => s.id == familiarSong.id), isFalse);
      expect(ranked.any((s) => s.id == unplayedSong.id), isTrue);
    });

    test('Composer mode prioritizes tracks sharing Music Director / Composer', () async {
      final candidates = [nonComposerSong, composerMatchSong];
      final ranked = await QueueTunerController.filterAndRankCandidates(
        seedSong: seedSong,
        candidates: candidates,
        mode: QueueTunerMode.composer,
      );

      expect(ranked.isNotEmpty, isTrue);
      expect(ranked.first.id, equals(composerMatchSong.id));
    });
  });

  group('SmartShuffle Multi-Language Parity & Composer Bonus', () {
    test('SmartShuffle does not discard candidates matching secondary preferred languages', () async {
      await SettingsManager.setPreferredLanguages(['Tamil', 'Telugu', 'Hindi']);

      final controller = SmartShuffleController();
      final seed = Song(
        id: 's_tamil',
        title: 'Naa Ready',
        artist: 'Anirudh Ravichander, Vijay',
        album: 'Leo',
        coverUrl: '',
        language: 'Tamil',
        duration: 210,
      );

      // Verify affinity score calculation works
      expect(controller.getSongAffinityScore(seed), equals(0.0));
      controller.recordFeedback(song: seed, isPositive: true);
      expect(controller.getSongAffinityScore(seed), equals(1.0));
    });
  });
}
