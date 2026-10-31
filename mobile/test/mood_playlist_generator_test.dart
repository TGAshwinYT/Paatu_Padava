import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/logic/mood_playlist_generator.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/blacklist_manager.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/download_manager.dart';
import 'package:paatu_padava_mobile/services/queue_cooldown_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mood_playlist_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(BlacklistManager.boxName);
    await Hive.openBox(FavoritesManager.boxName);
    await Hive.openBox(HistoryManager.boxName);
    await Hive.openBox(HistoryManager.pendingBoxName);
    await Hive.openBox(DownloadManager.boxName);
    await BlacklistManager.init();
    QueueCooldownManager.clear();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    QueueCooldownManager.clear();
  });

  group('MoodPlaylistGenerator NLP & Rule Planning Tests', () {
    test('detectLanguageInPrompt correctly extracts explicit Indian languages from freeform descriptions', () {
      expect(MoodPlaylistGenerator.detectLanguageInPrompt('tamil acoustic rain drops'), equals('tamil'));
      expect(MoodPlaylistGenerator.detectLanguageInPrompt('90s romantic hindi hits'), equals('hindi'));
      expect(MoodPlaylistGenerator.detectLanguageInPrompt('high energy telugu gym tracks'), equals('telugu'));
      expect(MoodPlaylistGenerator.detectLanguageInPrompt('chill lofi beats Malayalam'), equals('malayalam'));
      expect(MoodPlaylistGenerator.detectLanguageInPrompt('late night highway drive'), isNull);
    });

    test('detectMoodEmoji maps descriptive keywords to evocative emojis', () {
      expect(MoodPlaylistGenerator.detectMoodEmoji('monsoon evening rain'), equals('🌧️'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('hardcore gym workout energy'), equals('⚡'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('late night lonely highway drive'), equals('🌙'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('deep study lofi chill focus'), equals('🎧'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('evergreen love romance melodies'), equals('❤️'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('retro 90s vintage classics'), equals('📻'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('weekend celebration dance party'), equals('💃'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('sunday morning acoustic coffee'), equals('☕'));
      expect(MoodPlaylistGenerator.detectMoodEmoji('broken heart sad cry'), equals('💔'));
    });

    test('formatTitle matches preset prompts and capitalizes custom prompts cleanly', () {
      expect(
        MoodPlaylistGenerator.formatTitle('rainy evening calm acoustic melodies'),
        equals('Rainy Evening Calm'),
      );
      expect(
        MoodPlaylistGenerator.formatTitle('peaceful sunset piano'),
        equals('Peaceful Sunset Piano Mix'),
      );
      expect(
        MoodPlaylistGenerator.formatTitle('gym motivation playlist'),
        equals('Gym Motivation Playlist'),
      );
    });

    test('generate throws ArgumentError on empty or whitespace prompt', () async {
      expect(
        () => MoodPlaylistGenerator.generate(prompt: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('generate respects BlacklistManager exclusions during playlist synthesis', () async {
      final blockedSong = Song(
        id: 'bad_song_1',
        title: 'Annoying Song',
        artist: 'Blocked Singer',
        coverUrl: '',
        language: 'tamil',
      );
      final goodSong = Song(
        id: 'good_song_1',
        title: 'Calm Melodic Rain',
        artist: 'Peaceful Artist',
        coverUrl: '',
        language: 'tamil',
        duration: 210,
      );

      // Blacklist bad song and add good song to favorites pool
      await BlacklistManager.blacklistSong(blockedSong);
      await FavoritesManager.toggleFavorite(goodSong);

      final result = await MoodPlaylistGenerator.generate(
        prompt: 'calm melodic rain',
        targetCount: 5,
        preferredLanguage: 'tamil',
      );

      expect(result.tracks.any((s) => s.id == 'bad_song_1'), isFalse);
      expect(result.prompt, equals('calm melodic rain'));
      expect(result.moodEmoji, equals('🌧️'));
    });
  });
}
