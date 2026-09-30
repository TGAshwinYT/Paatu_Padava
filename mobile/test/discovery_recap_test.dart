import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/radio_engine.dart';
import 'package:paatu_padava_mobile/services/recap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_recap_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(HistoryManager.boxName);
    await Hive.openBox(HistoryManager.pendingBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('RadioEngine & Smart Queue Tests', () {
    test('shapeRadioQueue maintains seedSong at index 0 and excludes duplicates', () {
      final seedSong = Song(
        id: 'seed_1',
        title: 'Hukum',
        artist: 'Anirudh Ravichander',
        album: 'Jailer',
        duration: 210,
        coverUrl: 'https://example.com/hukum.jpg',
        source: 'saavn',
      );

      final candidatePool = [
        // Duplicate seed song
        Song(id: 'seed_1', title: 'Hukum', artist: 'Anirudh Ravichander', album: 'Jailer', duration: 210, coverUrl: '', source: 'saavn'),
        // Other tracks
        Song(id: 'song_2', title: 'Kaavaalaa', artist: 'Anirudh Ravichander, Shilpa Rao', album: 'Jailer', duration: 190, coverUrl: '', source: 'saavn'),
        Song(id: 'song_3', title: 'Naa Ready', artist: 'Anirudh Ravichander, Vijay', album: 'Leo', duration: 240, coverUrl: '', source: 'saavn'),
        Song(id: 'song_4', title: 'Arabic Kuthu', artist: 'Anirudh Ravichander, Jonita Gandhi', album: 'Beast', duration: 270, coverUrl: '', source: 'saavn'),
        Song(id: 'song_5', title: 'Enjoy Enjaami', artist: 'Dhee, Arivu, Santhosh Narayanan', album: 'Single', duration: 250, coverUrl: '', source: 'saavn'),
        Song(id: 'song_6', title: 'Rowdy Baby', artist: 'Yuvan Shankar Raja, Dhanush', album: 'Maari 2', duration: 280, coverUrl: '', source: 'saavn'),
        Song(id: 'song_7', title: 'Aalaporan Thamizhan', artist: 'A.R. Rahman, Kailash Kher', album: 'Mersal', duration: 340, coverUrl: '', source: 'saavn'),
      ];

      final queue = RadioEngine.shapeRadioQueue(
        seedSong: seedSong,
        candidatePool: candidatePool,
        limit: 10,
      );

      expect(queue.isNotEmpty, isTrue);
      expect(queue.first.id, equals('seed_1'));
      // No duplicate seed_1 in queue
      expect(queue.where((s) => s.id == 'seed_1').length, equals(1));
    });

    test('shapeRadioQueue enforces sliding window artist diversity', () {
      final seedSong = Song(
        id: 's_0',
        title: 'Track 0',
        artist: 'Artist A',
        album: 'A',
        duration: 200,
        coverUrl: '',
        source: 'saavn',
      );

      // Consecutive songs by multiple artists
      final candidates = [
        Song(id: 's_1', title: 'Track 1', artist: 'Artist A', album: 'A', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_2', title: 'Track 2', artist: 'Artist A', album: 'A', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_3', title: 'Track 3', artist: 'Artist A', album: 'A', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_4', title: 'Track 4', artist: 'Artist B', album: 'B', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_5', title: 'Track 5', artist: 'Artist B', album: 'B', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_6', title: 'Track 6', artist: 'Artist B', album: 'B', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_7', title: 'Track 7', artist: 'Artist C', album: 'C', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_8', title: 'Track 8', artist: 'Artist C', album: 'C', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_9', title: 'Track 9', artist: 'Artist D', album: 'D', duration: 200, coverUrl: '', source: 'saavn'),
        Song(id: 's_10', title: 'Track 10', artist: 'Artist D', album: 'D', duration: 200, coverUrl: '', source: 'saavn'),
      ];

      final queue = RadioEngine.shapeRadioQueue(
        seedSong: seedSong,
        candidatePool: candidates,
        limit: 8,
      );

      // In the first 6 tracks of queue (including seedSong), Artist A should not have more than 2 tracks
      final initialWindow = queue.length >= 6 ? queue.sublist(0, 6) : queue;
      final artistACount = initialWindow.where((s) => s.primaryArtist.toLowerCase() == 'artist a').length;
      expect(artistACount, lessThanOrEqualTo(2));
      // Non-Artist A songs should have been promoted earlier in the queue
      expect(queue.any((s) => s.primaryArtist.toLowerCase() == 'artist b'), isTrue);
      expect(queue.any((s) => s.primaryArtist.toLowerCase() == 'artist c'), isTrue);
    });
  });

  group('ListeningRecapService Analytics & Persona Tests', () {
    test('Empty raw entries returns fallback Curious Listener recap', () {
      final recap = ListeningRecapService.generateRecapFromData([]);

      expect(recap.totalPlays, equals(0));
      expect(recap.totalMinutes, equals(0));
      expect(recap.uniqueTracksCount, equals(0));
      expect(recap.uniqueArtistsCount, equals(0));
      expect(recap.topSongs, isEmpty);
      expect(recap.topArtists, isEmpty);
      expect(recap.listenerPersona, equals('Curious Listener'));
    });

    test('Calculates total minutes with duration and fallback', () {
      final testData = [
        {
          'id': 'track_1',
          'title': 'Song 1',
          'artist': 'Artist 1',
          'duration': 180, // 3 minutes
          'play_count': 2, // 6 minutes total
        },
        {
          'id': 'track_2',
          'title': 'Song 2',
          'artist': 'Artist 2',
          'duration': 0, // Fallback 210s = 3.5 minutes
          'play_count': 1, // 3.5 minutes
        },
      ];

      final recap = ListeningRecapService.generateRecapFromData(testData);

      expect(recap.totalPlays, equals(3));
      // (180*2 + 210*1) = 360 + 210 = 570s = 9.5 minutes -> rounds to 10
      expect(recap.totalMinutes, equals(10));
      expect(recap.uniqueTracksCount, equals(2));
      expect(recap.uniqueArtistsCount, equals(2));
    });

    test('Accurately ranks top songs and aggregates primary artists', () {
      final testData = [
        {
          'id': 's1',
          'title': 'Vathi Coming',
          'artist': 'Anirudh Ravichander, Gana Balachandar',
          'duration': 210,
          'play_count': 15,
        },
        {
          'id': 's2',
          'title': 'Arabic Kuthu',
          'artist': 'Anirudh Ravichander, Jonita Gandhi',
          'duration': 260,
          'play_count': 8,
        },
        {
          'id': 's3',
          'title': 'Urshvasi Urvasi',
          'artist': 'A.R. Rahman, Suresh Peters',
          'duration': 300,
          'play_count': 5,
        },
      ];

      final recap = ListeningRecapService.generateRecapFromData(testData);

      expect(recap.topSongs.first.song.id, equals('s1'));
      expect(recap.topSongs.first.playCount, equals(15));
      expect(recap.topSongs[1].song.id, equals('s2'));
      expect(recap.topSongs[1].playCount, equals(8));

      // Artist aggregation: Anirudh has 15 + 8 = 23 plays
      expect(recap.topArtists.first.artistName, equals('Anirudh Ravichander'));
      expect(recap.topArtists.first.playCount, equals(23));
      expect(recap.topArtists[1].artistName, equals('A.R. Rahman'));
      expect(recap.topArtists[1].playCount, equals(5));
    });

    test('Assigns Devoted Stan persona when top artist exceeds 40% of plays', () {
      final testData = [
        {
          'id': 's1',
          'title': 'Track A',
          'artist': 'Yuvan Shankar Raja',
          'duration': 200,
          'play_count': 30, // 30 out of 40 plays = 75%
        },
        {
          'id': 's2',
          'title': 'Track B',
          'artist': 'Harris Jayaraj',
          'duration': 200,
          'play_count': 10,
        },
      ];

      final recap = ListeningRecapService.generateRecapFromData(testData);
      expect(recap.listenerPersona, equals('Devoted Stan'));
    });

    test('Assigns Midnight Voyager persona for late night listening concentration', () {
      // 2:30 AM local time timestamp
      final midnightDt = DateTime(2026, 9, 30, 2, 30);
      final testData = [
        {
          'id': 's1',
          'title': 'Late Night Lo-fi',
          'artist': 'Acoustic Waves',
          'duration': 180,
          'play_count': 10,
          'timestamps': [midnightDt.millisecondsSinceEpoch],
        },
        {
          'id': 's2',
          'title': 'Starlight Beats',
          'artist': 'Cosmic Chill',
          'duration': 200,
          'play_count': 10,
          'timestamps': [midnightDt.millisecondsSinceEpoch],
        },
        {
          'id': 's3',
          'title': 'Moonlight Walk',
          'artist': 'Lunar Vibes',
          'duration': 220,
          'play_count': 10,
          'timestamps': [midnightDt.millisecondsSinceEpoch],
        },
      ];

      final recap = ListeningRecapService.generateRecapFromData(testData);
      expect(recap.listenerPersona, equals('Midnight Voyager'));
      expect(recap.peakHour, equals(2));
      expect(recap.peakHourFormatted, equals('2:00 AM'));
    });

    test('HistoryManager records play count and stores timestamps', () async {
      final song = Song(
        id: 'h_test_1',
        title: 'Illuminati',
        artist: 'Sushin Shyam',
        album: 'Aavesham',
        duration: 180,
        coverUrl: 'https://example.com/cover.jpg',
        source: 'saavn',
      );

      // Play once
      await HistoryManager.recordPlay(song);
      var raw = HistoryManager.getRawHistoryEntries();
      expect(raw.length, equals(1));
      expect(raw.first['play_count'], equals(1));

      // Play second time
      await HistoryManager.recordPlay(song);
      raw = HistoryManager.getRawHistoryEntries();
      expect(raw.length, equals(1)); // Deduplicated in box
      expect(raw.first['play_count'], equals(2));
      expect((raw.first['timestamps'] as List).length, equals(2));
    });
  });
}
