import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/domain/models/history_entry.dart';
import 'package:paatu_padava_mobile/domain/models/listening_session.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';

TrackEntity _createTrack(
  String id,
  String title, {
  String artist = 'Various Artists',
  String album = 'Popular Hits',
  int duration = 210,
  String coverUrl = 'https://example.com/cover.jpg',
}) {
  return TrackEntity(
    id: id,
    title: title,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    duration: duration,
    source: 'saavn',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('listening_session_test_hive_');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(HistoryManager.boxName)) {
      await Hive.openBox(HistoryManager.boxName);
    }
    if (!Hive.isBoxOpen(HistoryManager.pendingBoxName)) {
      await Hive.openBox(HistoryManager.pendingBoxName);
    }
    if (!Hive.isBoxOpen(HistoryManager.sessionsBoxName)) {
      await Hive.openBox(HistoryManager.sessionsBoxName);
    }
    if (!Hive.isBoxOpen(PlaylistManager.boxName)) {
      await Hive.openBox(PlaylistManager.boxName);
    }
    if (!Hive.isBoxOpen(FavoritesManager.boxName)) {
      await Hive.openBox(FavoritesManager.boxName);
    }
    await FavoritesManager.init();
    await PlaylistManager.init();
    await HistoryManager.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await HistoryManager.clearHistory();
  });

  group('ListeningSession Model & Continuous Clustering Tests', () {
    test('1. Clusters contiguous playback into a single continuous session', () {
      final now = DateTime(2026, 10, 16, 15, 0); // 3:00 PM
      final entries = [
        HistoryEntry(track: _createTrack('t1', 'Track 1'), playedAt: now),
        HistoryEntry(track: _createTrack('t2', 'Track 2'), playedAt: now.add(const Duration(minutes: 4))),
        HistoryEntry(track: _createTrack('t3', 'Track 3'), playedAt: now.add(const Duration(minutes: 8))),
        HistoryEntry(track: _createTrack('t4', 'Track 4'), playedAt: now.add(const Duration(minutes: 12))),
      ];

      final sessions = HistoryManager.clusterEntriesIntoSessions(entries);
      expect(sessions.length, equals(1));
      final s = sessions.first;
      expect(s.trackCount, equals(4));
      expect(s.tracks.map((t) => t.id).toList(), equals(['t1', 't2', 't3', 't4']));
      expect(s.totalDurationSeconds, equals(210 * 4));
    });

    test('2. Separates sessions when playback gap exceeds 35 minutes', () {
      final now = DateTime(2026, 10, 16, 10, 0); // Morning session
      final entries = [
        // Morning cluster (10:00 AM, 10:05 AM)
        HistoryEntry(track: _createTrack('m1', 'Morning 1'), playedAt: now),
        HistoryEntry(track: _createTrack('m2', 'Morning 2'), playedAt: now.add(const Duration(minutes: 5))),

        // Evening cluster (5:00 PM, 5:04 PM) -> 7 hour gap
        HistoryEntry(track: _createTrack('e1', 'Evening 1'), playedAt: now.add(const Duration(hours: 7))),
        HistoryEntry(track: _createTrack('e2', 'Evening 2'), playedAt: now.add(const Duration(hours: 7, minutes: 4))),
      ];

      final sessions = HistoryManager.clusterEntriesIntoSessions(entries);
      expect(sessions.length, equals(2));

      // Newest session first
      final eveningSession = sessions[0];
      final morningSession = sessions[1];

      expect(eveningSession.trackCount, equals(2));
      expect(eveningSession.tracks.map((t) => t.id).toList(), equals(['e1', 'e2']));

      expect(morningSession.trackCount, equals(2));
      expect(morningSession.tracks.map((t) => t.id).toList(), equals(['m1', 'm2']));
    });

    test('3. Generates smart session title for dominant artist', () {
      final now = DateTime(2026, 10, 16, 14, 0);
      final tracks = [
        _createTrack('a1', 'Badass', artist: 'Anirudh Ravichander'),
        _createTrack('a2', 'Hukum', artist: 'Anirudh Ravichander'),
        _createTrack('a3', 'Arabic Kuthu', artist: 'Anirudh Ravichander'),
        _createTrack('o1', 'Marakkuma Nenjam', artist: 'A.R. Rahman'),
      ];

      final title = ListeningSession.generateTitle(tracks, now);
      expect(title, equals('Anirudh Ravichander & more'));
    });

    test('4. Generates smart session title for dominant album', () {
      final now = DateTime(2026, 10, 16, 14, 0);
      final tracks = [
        _createTrack('a1', 'Song 1', album: 'Leo', artist: 'Various'),
        _createTrack('a2', 'Song 2', album: 'Leo', artist: 'Various'),
        _createTrack('a3', 'Song 3', album: 'Leo', artist: 'Various'),
      ];

      final title = ListeningSession.generateTitle(tracks, now);
      expect(title, equals('Leo Album Session'));
    });

    test('5. Extracts up to 4 distinct album cover URLs for 2x2 collage', () {
      final now = DateTime(2026, 10, 16, 14, 0);
      final tracks = [
        _createTrack('c1', 'T1', coverUrl: 'https://example.com/c1.jpg'),
        _createTrack('c2', 'T2', coverUrl: 'https://example.com/c2.jpg'),
        _createTrack('c3', 'T3', coverUrl: 'https://example.com/c1.jpg'), // Duplicate cover
        _createTrack('c4', 'T4', coverUrl: 'https://example.com/c3.jpg'),
        _createTrack('c5', 'T5', coverUrl: 'https://example.com/c4.jpg'),
        _createTrack('c6', 'T6', coverUrl: 'https://example.com/c5.jpg'),
      ];

      final session = ListeningSession.fromTracks(
        id: 'session_test',
        tracks: tracks,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 20)),
      );

      expect(session.coverUrls.length, equals(4));
      expect(session.coverUrls, equals([
        'https://example.com/c1.jpg',
        'https://example.com/c2.jpg',
        'https://example.com/c3.jpg',
        'https://example.com/c4.jpg',
      ]));
    });

    test('6. Real-time playback adds tracks to continuous session in HistoryManager', () async {
      final t1 = _createTrack('live_1', 'Live Song 1', artist: 'Yuvan Shankar Raja');
      final t2 = _createTrack('live_2', 'Live Song 2', artist: 'Yuvan Shankar Raja');

      await HistoryManager.addToHistory(t1);
      expect(HistoryManager.historySessionsNotifier.value.isNotEmpty, isTrue);
      expect(HistoryManager.historySessionsNotifier.value.first.trackCount, equals(1));

      // Second play within 35 minutes adds to same session
      await HistoryManager.addToHistory(t2);
      expect(HistoryManager.historySessionsNotifier.value.length, equals(1));
      final active = HistoryManager.historySessionsNotifier.value.first;
      expect(active.trackCount, equals(2));
      expect(active.tracks.map((t) => t.id).toList(), containsAll(['live_1', 'live_2']));
    });

    test('7. Saves continuous session as user playlist', () async {
      final now = DateTime(2026, 10, 16, 18, 0);
      final session = ListeningSession.fromTracks(
        id: 'session_playlist_test',
        tracks: [
          _createTrack('p1', 'Playlist Song 1'),
          _createTrack('p2', 'Playlist Song 2'),
        ],
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 10)),
        customTitle: 'My Evening Continuous Mix',
      );

      final playlist = await HistoryManager.saveSessionAsPlaylist(session);
      expect(playlist.title, equals('My Evening Continuous Mix'));
      expect(playlist.tracks.length, equals(2));
      expect(playlist.tracks.map((t) => t.id).toList(), equals(['p1', 'p2']));

      // Verified in PlaylistManager
      final saved = PlaylistManager.getPlaylist(playlist.id);
      expect(saved, isNotNull);
      expect(saved?.tracks.length, equals(2));
    });

    test('8. Removing a song updates both history tracks and continuous sessions', () async {
      final t1 = _createTrack('del_1', 'Delete Track 1');
      final t2 = _createTrack('del_2', 'Delete Track 2');

      await HistoryManager.addToHistory(t1);
      await HistoryManager.addToHistory(t2);

      expect(HistoryManager.getHistory().length, equals(2));
      expect(HistoryManager.getListeningSessions().first.trackCount, equals(2));

      await HistoryManager.removeSong('del_1');

      expect(HistoryManager.getHistory().any((s) => s.id == 'del_1'), isFalse);
      expect(HistoryManager.getListeningSessions().first.trackCount, equals(1));
      expect(HistoryManager.getListeningSessions().first.tracks.first.id, equals('del_2'));
    });

    test('9. clearHistory() purges history and all continuous sessions', () async {
      await HistoryManager.addToHistory(_createTrack('clr_1', 'Clear 1'));
      expect(HistoryManager.getHistory().isNotEmpty, isTrue);
      expect(HistoryManager.getListeningSessions().isNotEmpty, isTrue);

      await HistoryManager.clearHistory();

      expect(HistoryManager.getHistory().isEmpty, isTrue);
      expect(HistoryManager.getListeningSessions().isEmpty, isTrue);
      expect(HistoryManager.historyEntriesNotifier.value.isEmpty, isTrue);
      expect(HistoryManager.historySessionsNotifier.value.isEmpty, isTrue);
    });
  });
}
