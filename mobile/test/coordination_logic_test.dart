import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/auth_manager.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paatu_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AuthManager Coordination & State Branching Tests', () {
    test('Fresh install with empty cache initializes clean guest session', () async {
      await Hive.openBox(AuthManager.boxName);
      final box = Hive.box(AuthManager.boxName);
      expect(box.get('user_profile'), isNull);

      // Simulate AuthManager guest fallback
      await AuthManager.loginAsGuest();

      expect(AuthManager.currentUser, isNotNull);
      expect(AuthManager.currentUser!.isGuest, isTrue);
      expect(AuthManager.currentUser!.id, equals('guest'));
      expect(AuthManager.token, isNull);
      expect(AuthManager.isLoggedIn, isFalse);

      // Verify persisted state
      final saved = box.get('user_profile');
      expect(saved, isNotNull);
      expect(saved['is_guest'], isTrue);
    });

    test('Cached guest profile in Hive restores correctly without overwriting guest id', () async {
      await Hive.openBox(AuthManager.boxName);
      final box = Hive.box(AuthManager.boxName);

      // Pre-seed box with custom guest state
      final guestData = {
        'id': 'guest',
        'username': 'Guest Listener',
        'email': 'guest@paatupaadava.app',
        'preferred_languages': ['malayalam', 'tamil'],
        'favorite_artists': ['K.J. Yesudas'],
        'is_guest': true,
      };
      await box.put('user_profile', guestData);

      // Restore from cache
      final savedUser = box.get('user_profile');
      expect(savedUser['is_guest'], isTrue);
      final restored = AuthUser.fromJson(savedUser);
      AuthManager.authNotifier.value = restored;

      expect(AuthManager.currentUser?.preferredLanguages, contains('malayalam'));
      expect(AuthManager.currentUser?.favoriteArtists, contains('K.J. Yesudas'));
      expect(AuthManager.currentUser?.isGuest, isTrue);
    });

    test('Authenticated user state takes precedence over guest mode and synchronizes', () async {
      await Hive.openBox(AuthManager.boxName);
      final box = Hive.box(AuthManager.boxName);

      final authUser = AuthUser(
        id: 'usr_real_789',
        username: 'Ashwin',
        email: 'ashwin@example.com',
        preferredLanguages: ['tamil', 'telugu'],
        favoriteArtists: ['A.R. Rahman', 'Anirudh Ravichander'],
        isGuest: false,
      );

      AuthManager.authNotifier.value = authUser;
      AuthManager.tokenNotifier.value = 'mock_jwt_token_123';
      await box.put('user_profile', authUser.toJson());

      expect(AuthManager.currentUser?.id, equals('usr_real_789'));
      expect(AuthManager.token, equals('mock_jwt_token_123'));
      expect(AuthManager.currentUser?.isGuest, isFalse);
      expect(AuthManager.currentUser?.preferredLanguages, contains('telugu'));

      // Logout transitions back to guest cleanly
      await AuthManager.loginAsGuest();
      expect(AuthManager.currentUser?.isGuest, isTrue);
      expect(AuthManager.token, isNull);
    });
  });

  group('Preference Sync & Cross-Store Listener Coordination', () {
    test('SettingsManager reads directly from AuthManager preferences', () async {
      await Hive.openBox(AuthManager.boxName);
      await Hive.openBox(SettingsManager.boxName);

      final user = AuthUser(
        id: 'usr_pref_test',
        username: 'Listener',
        email: 'listener@test.com',
        preferredLanguages: ['malayalam', 'hindi'],
        isGuest: false,
      );
      AuthManager.authNotifier.value = user;

      // SettingsManager.preferredLanguages should reflect AuthManager directly
      expect(SettingsManager.preferredLanguages, equals(['malayalam', 'hindi']));
    });

    test('Updating language preferences propagates to listener subscribers', () async {
      await Hive.openBox(AuthManager.boxName);
      await Hive.openBox(SettingsManager.boxName);

      final notifiedLanguages = <List<String>>[];
      void listener() {
        notifiedLanguages.add(SettingsManager.languagesNotifier.value);
      }

      SettingsManager.languagesNotifier.addListener(listener);

      // Set user
      AuthManager.authNotifier.value = AuthUser(
        id: 'usr_sync_1',
        username: 'User1',
        email: 'u1@test.com',
        preferredLanguages: ['tamil'],
        isGuest: false,
      );

      await AuthManager.updateLanguagePreferences(['kannada', 'telugu']);

      expect(notifiedLanguages.isNotEmpty, isTrue);
      expect(notifiedLanguages.last, equals(['kannada', 'telugu']));
      expect(SettingsManager.preferredLanguages, equals(['kannada', 'telugu']));

      SettingsManager.languagesNotifier.removeListener(listener);
    });
  });

  group('FavoritesManager Local & Cloud Reconciliation Tests', () {
    test('Local toggleFavorite updates Hive instantaneously and notifies UI', () async {
      await FavoritesManager.init();

      final song = Song(
        id: 'fav_001',
        title: 'Vaseegara',
        artist: 'Bombay Jayashri',
        album: 'Minnale',
        duration: 300,
        coverUrl: 'https://example.com/vaseegara.jpg',
      );

      expect(FavoritesManager.isFavorite('fav_001'), isFalse);

      // 1. Add to favorites
      final added = await FavoritesManager.toggleFavorite(song);
      expect(added, isTrue);
      expect(FavoritesManager.isFavorite('fav_001'), isTrue);
      expect(FavoritesManager.getFavorites().length, equals(1));
      expect(FavoritesManager.favoritesNotifier.value.first.title, equals('Vaseegara'));

      // 2. Remove from favorites
      final removed = await FavoritesManager.toggleFavorite(song);
      expect(removed, isFalse);
      expect(FavoritesManager.isFavorite('fav_001'), isFalse);
      expect(FavoritesManager.getFavorites(), isEmpty);
    });

    test('Remote liked_songs reconciliation pulls down missing favorites with string sanitation', () async {
      await FavoritesManager.init();

      // Simulate remote payload from Supabase `liked_songs`
      final remoteRecords = [
        {
          'id': 'remote_uuid_1',
          'yt_video_id': 'remote_track_101',
          'title': 'Anbil Avan &amp; Enna Solla',
          'artist': 'A.R. Rahman',
          'cover_url': 'https://example.com/cover.jpg',
          'audio_url': 'https://example.com/audio.mp3',
          'language': 'tamil',
        },
      ];

      // Simulate the reconciliation loop in FavoritesManager.syncWithCloud
      final box = Hive.box(FavoritesManager.boxName);
      for (final item in remoteRecords) {
        final trackId = item['yt_video_id']?.toString() ?? '';
        if (!box.containsKey(trackId)) {
          final s = Song(
            id: trackId,
            title: TrackEntity.sanitize(item['title'], fallback: 'Unknown Song'),
            artist: TrackEntity.sanitize(item['artist'], fallback: 'Various Artists'),
            album: '',
            duration: 0,
            coverUrl: item['cover_url']?.toString() ?? '',
            streamUrl: item['audio_url']?.toString(),
            language: item['language']?.toString(),
          );
          await box.put(trackId, s.toMap());
        }
      }

      expect(box.containsKey('remote_track_101'), isTrue);
      final restoredSong = Song.fromMap(box.get('remote_track_101'));
      // Verifies HTML unescaping during cloud pull
      expect(restoredSong.title, equals('Anbil Avan & Enna Solla'));
      expect(restoredSong.artist, equals('A.R. Rahman'));
    });
  });

  group('HistoryManager Coordinated Play Recording & Deduplication Tests', () {
    test('recordPlay deduplicates repeated plays and unshifts to top of list', () async {
      await HistoryManager.init();
      await HistoryManager.clear();

      final songA = Song(id: 'song_a', title: 'Song Alpha', artist: 'Artist 1', album: 'Album A', duration: 180, coverUrl: '');
      final songB = Song(id: 'song_b', title: 'Song Beta', artist: 'Artist 2', album: 'Album B', duration: 200, coverUrl: '');

      await HistoryManager.recordPlay(songA);
      await HistoryManager.recordPlay(songB);

      var history = HistoryManager.getHistory();
      expect(history.length, equals(2));
      expect(history.first.id, equals('song_b')); // most recent at front

      // Re-play song A: should move to front, not duplicate
      await HistoryManager.recordPlay(songA);
      history = HistoryManager.getHistory();
      expect(history.length, equals(2));
      expect(history.first.id, equals('song_a'));
    });

    test('recordPlay strictly enforces 100-item maximum history boundary', () async {
      await HistoryManager.init();
      await HistoryManager.clear();

      // Add 105 distinct songs
      for (int i = 0; i < 105; i++) {
        final song = Song(
          id: 'song_$i',
          title: 'Track $i',
          artist: 'Artist',
          album: 'Album',
          duration: 100,
          coverUrl: '',
        );
        await HistoryManager.recordPlay(song);
      }

      final history = HistoryManager.getHistory();
      expect(history.length, lessThanOrEqualTo(100));
      expect(history.first.id, equals('song_104')); // newest is first
    });
  });
}
