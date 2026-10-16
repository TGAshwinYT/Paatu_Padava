import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_history_manager.dart';
import 'package:paatu_padava_mobile/ui/screens/search_screen.dart';

Song createTestSong({
  required String id,
  required String title,
  required String artist,
  String album = 'Test Album',
  String coverUrl = '',
  int duration = 240,
  String source = 'saavn',
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    duration: duration,
    source: source,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_search_test_');
    Hive.init(tempDir.path);
    await SearchHistoryManager.init();
    await SearchHistoryManager.clearAll();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SearchHistoryManager Tests', () {
    test('Stores and deduplicates search queries with a 12-item cap', () async {
      await SearchHistoryManager.addQuery('Anirudh');
      await SearchHistoryManager.addQuery('ARR');
      await SearchHistoryManager.addQuery('anirudh'); // Case-insensitive duplicate

      expect(SearchHistoryManager.historyNotifier.value, equals(['anirudh', 'ARR']));

      for (int i = 0; i < 15; i++) {
        await SearchHistoryManager.addQuery('Query $i');
      }

      expect(SearchHistoryManager.historyNotifier.value.length, equals(12));
      expect(SearchHistoryManager.historyNotifier.value.first, equals('Query 14'));
    });

    test('Stores and deduplicates clicked songs with move-to-top and 20-item cap', () async {
      final s1 = createTestSong(id: 'song_1', title: 'Song One', artist: 'Artist A');
      final s2 = createTestSong(id: 'song_2', title: 'Song Two', artist: 'Artist B');

      await SearchHistoryManager.addSong(s1);
      await SearchHistoryManager.addSong(s2);
      expect(SearchHistoryManager.recentSongsNotifier.value.map((s) => s.id).toList(), equals(['song_2', 'song_1']));

      // Re-adding song_1 moves it to the top
      await SearchHistoryManager.addSong(s1);
      expect(SearchHistoryManager.recentSongsNotifier.value.map((s) => s.id).toList(), equals(['song_1', 'song_2']));

      // Enforces 20-song cap
      for (int i = 4; i <= 30; i++) {
        await SearchHistoryManager.addSong(createTestSong(id: 'song_$i', title: 'Song $i', artist: 'Artist'));
      }

      expect(SearchHistoryManager.recentSongsNotifier.value.length, equals(20));
      expect(SearchHistoryManager.recentSongsNotifier.value.first.id, equals('song_30'));
    });

    test('Removes individual song, individual query, and clears recent songs', () async {
      final s1 = createTestSong(id: 's_1', title: 'Title 1', artist: 'Artist 1');
      final s2 = createTestSong(id: 's_2', title: 'Title 2', artist: 'Artist 2');

      await SearchHistoryManager.addSong(s1);
      await SearchHistoryManager.addSong(s2);
      await SearchHistoryManager.addQuery('Query 1');
      await SearchHistoryManager.addQuery('Query 2');

      expect(SearchHistoryManager.recentSongsNotifier.value.length, equals(2));
      expect(SearchHistoryManager.historyNotifier.value.length, equals(2));

      await SearchHistoryManager.removeSong('s_1');
      expect(SearchHistoryManager.recentSongsNotifier.value.map((s) => s.id).toList(), equals(['s_2']));

      await SearchHistoryManager.removeQuery('Query 1');
      expect(SearchHistoryManager.historyNotifier.value, equals(['Query 2']));

      await SearchHistoryManager.clearSongs();
      expect(SearchHistoryManager.recentSongsNotifier.value, isEmpty);
      expect(SearchHistoryManager.historyNotifier.value, equals(['Query 2']));

      await SearchHistoryManager.clearAll();
      expect(SearchHistoryManager.recentSongsNotifier.value, isEmpty);
      expect(SearchHistoryManager.historyNotifier.value, isEmpty);
    });

    test('Persists clicked songs and queries across re-initialization', () async {
      final s1 = createTestSong(id: 'persist_1', title: 'Arabic Kuthu', artist: 'Anirudh');
      await SearchHistoryManager.addSong(s1);
      await SearchHistoryManager.addQuery('Arabic Kuthu');

      // Simulate app restart by calling init again
      await SearchHistoryManager.init();

      expect(SearchHistoryManager.recentSongsNotifier.value.first.title, equals('Arabic Kuthu'));
      expect(SearchHistoryManager.historyNotifier.value.first, equals('Arabic Kuthu'));
    });
  });

  group('SearchResultsState Model Tests', () {
    test('Correctly identifies empty state and non-empty state', () {
      const emptyState = SearchResultsState();
      expect(emptyState.isEmpty, isTrue);
      expect(emptyState.hasError, isFalse);

      final stateWithSongs = SearchResultsState(
        songs: [createTestSong(id: '1', title: 'Song 1', artist: 'Artist 1')],
      );
      expect(stateWithSongs.isEmpty, isFalse);
    });
  });
}
