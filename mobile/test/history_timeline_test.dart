import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/domain/models/history_entry.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';

class _MockPlayer extends Fake implements AudioPlayer {
  final StreamController<int?> _currentIndexController = StreamController<int?>.broadcast();
  final StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast();
  final StreamController<SequenceState?> _sequenceStateController = StreamController<SequenceState?>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<PlaybackEvent> _playbackEventController = StreamController<PlaybackEvent>.broadcast();
  final StreamController<int?> _sessionIdController = StreamController<int?>.broadcast();
  final StreamController<Duration?> _durationController = StreamController<Duration?>.broadcast();

  double _volume = 1.0;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 3);
  AudioSource? _audioSource;
  int? _sourceIndex;

  @override Stream<int?> get currentIndexStream => _currentIndexController.stream;
  @override Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  @override Stream<SequenceState?> get sequenceStateStream => _sequenceStateController.stream;
  @override Stream<Duration> get positionStream => _positionController.stream;
  @override Stream<PlaybackEvent> get playbackEventStream => _playbackEventController.stream;
  @override Stream<int?> get androidAudioSessionIdStream => _sessionIdController.stream;
  @override Stream<Duration?> get durationStream => _durationController.stream;
  @override double get volume => _volume;
  @override bool get playing => _playing;
  @override Duration get position => _position;
  @override Duration? get duration => _duration;
  @override AudioSource? get audioSource => _audioSource;
  @override ProcessingState get processingState => ProcessingState.ready;
  @override double get speed => 1.0;
  @override Duration get bufferedPosition => Duration.zero;

  void setTestDuration(Duration d) {
    _duration = d;
  }

  void emitPosition(Duration pos) {
    _position = pos;
    _positionController.add(pos);
  }

  @override
  Future<void> setVolume(double value) async {
    _volume = value;
  }

  @override
  Future<void> play() async {
    _playing = true;
    _playerStateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _audioSource = source;
    _sourceIndex = initialIndex ?? 0;
    _currentIndexController.add(_sourceIndex);
    return _duration;
  }

  @override
  Future<void> seek(Duration? pos, {int? index}) async {
    if (pos != null) {
      _position = pos;
      _positionController.add(pos);
    }
    if (index != null) {
      _sourceIndex = index;
      _currentIndexController.add(index);
    }
  }

  @override
  Future<void> dispose() async {
    await _currentIndexController.close();
    await _playerStateController.close();
    await _sequenceStateController.close();
    await _positionController.close();
    await _playbackEventController.close();
    await _sessionIdController.close();
    await _durationController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('history_timeline_test_hive_');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(FavoritesManager.boxName)) {
      await Hive.openBox(FavoritesManager.boxName);
    }
    if (!Hive.isBoxOpen(HistoryManager.boxName)) {
      await Hive.openBox(HistoryManager.boxName);
    }
    if (!Hive.isBoxOpen(HistoryManager.pendingBoxName)) {
      await Hive.openBox(HistoryManager.pendingBoxName);
    }
    await FavoritesManager.init();
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

  TrackEntity createSampleTrack(String id, String title, {int duration = 180}) {
    return TrackEntity(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      coverUrl: 'https://example.com/cover_$id.jpg',
      duration: duration,
      source: 'saavn',
    );
  }

  group('History Subsystem Architecture Tests', () {
    test('1. Tracks skipped before 30 seconds do not write to history', () async {
      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      final track1 = createSampleTrack('track_skip_1', 'Skipped Track', duration: 200).toSong();
      final track2 = createSampleTrack('track_play_2', 'Full Played Track', duration: 200).toSong();

      await handler.queueHandler.loadQueue([track1, track2], initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(handler.currentSong?.id, equals('track_skip_1'));
      expect(HistoryManager.getHistoryEntries().isEmpty, isTrue);

      // Playback advances to only 15 seconds (< 30s threshold)
      mockPlayer.emitPosition(const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Must NOT be in history yet
      expect(handler.hasRecordedHistory, isFalse);
      expect(HistoryManager.getHistoryEntries().isEmpty, isTrue);

      // User skips to next track before reaching 30s
      await handler.queueHandler.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(handler.currentSong?.id, equals('track_play_2'));
      // Skipped track must never have been written
      expect(HistoryManager.getHistoryEntries().any((e) => e.track.id == 'track_skip_1'), isFalse);
      expect(HistoryManager.getHistoryEntries().isEmpty, isTrue);

      // Now track 2 advances past the 30-second scrobble threshold
      mockPlayer.emitPosition(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Must be committed to history!
      expect(handler.hasRecordedHistory, isTrue);
      final history = HistoryManager.getHistoryEntries();
      expect(history.length, equals(1));
      expect(history.first.track.id, equals('track_play_2'));
      expect(history.first.track.title, equals('Full Played Track'));

      await handler.disposeAudioHandler();
      await mockPlayer.dispose();
    });

    test('2. Playing the same song twice hoists it to the top without duplicate rows', () async {
      final trackA = createSampleTrack('song_a', 'Song A');
      final trackB = createSampleTrack('song_b', 'Song B');
      final trackC = createSampleTrack('song_c', 'Song C');

      // 1. Play Song A
      await HistoryManager.addToHistory(trackA);
      expect(HistoryManager.getHistoryEntries().length, equals(1));
      expect(HistoryManager.getHistoryEntries().first.track.id, equals('song_a'));

      // 2. Play Song B
      await HistoryManager.addToHistory(trackB);
      expect(HistoryManager.getHistoryEntries().length, equals(2));
      expect(HistoryManager.getHistoryEntries()[0].track.id, equals('song_b'));
      expect(HistoryManager.getHistoryEntries()[1].track.id, equals('song_a'));

      // 3. Play Song C
      await HistoryManager.addToHistory(trackC);
      expect(HistoryManager.getHistoryEntries().length, equals(3));
      expect(HistoryManager.getHistoryEntries().map((e) => e.track.id).toList(), equals(['song_c', 'song_b', 'song_a']));

      // 4. Play Song A again within 24 hours: MUST hoist Song A to index 0 without duplicates!
      await HistoryManager.addToHistory(trackA);
      final entriesAfterHoist = HistoryManager.getHistoryEntries();

      expect(entriesAfterHoist.length, equals(3));
      expect(entriesAfterHoist[0].track.id, equals('song_a'));
      expect(entriesAfterHoist[1].track.id, equals('song_c'));
      expect(entriesAfterHoist[2].track.id, equals('song_b'));
      // No duplicate rows for song_a
      expect(entriesAfterHoist.where((e) => e.track.id == 'song_a').length, equals(1));
    });

    test('3. HistoryEntry correctly maps to date sections ("Today", "Yesterday")', () {
      final now = DateTime(2026, 10, 12, 14, 30); // Current fixed test baseline
      final todayTime = DateTime(2026, 10, 12, 10, 15);
      final yesterdayTime = DateTime(2026, 10, 11, 22, 45);
      final olderTime = DateTime(2026, 10, 10, 9, 0); // Saturday, 10 October 2026

      final track = createSampleTrack('track_date_1', 'Date Track');

      final todayEntry = HistoryEntry(track: track, playedAt: todayTime);
      final yesterdayEntry = HistoryEntry(track: track, playedAt: yesterdayTime);
      final olderEntry = HistoryEntry(track: track, playedAt: olderTime);

      expect(HistoryEntry.formatDateSection(todayEntry.playedAt, now), equals('Today'));
      expect(HistoryEntry.formatDateSection(yesterdayEntry.playedAt, now), equals('Yesterday'));
      expect(HistoryEntry.formatDateSection(olderEntry.playedAt, now), equals('Saturday, 10 October'));

      // HistoryEntry equality: same track id & calendar date evaluates to true
      final sameDayEntry = HistoryEntry(
        track: track,
        playedAt: DateTime(2026, 10, 12, 18, 0), // Different time, same day
      );
      expect(todayEntry == sameDayEntry, isTrue);
      expect(todayEntry == yesterdayEntry, isFalse);

      // JSON serialization round-trip
      final json = todayEntry.toJson();
      final revived = HistoryEntry.fromJson(json);
      expect(revived.track.id, equals(todayEntry.track.id));
      expect(revived.playedAt.year, equals(todayEntry.playedAt.year));
      expect(revived.playedAt.month, equals(todayEntry.playedAt.month));
      expect(revived.playedAt.day, equals(todayEntry.playedAt.day));
    });

    test('4. Tracks under 60 seconds scrobble at >= 50% duration threshold', () async {
      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      // 40-second track: threshold is 20 seconds (50%)
      final shortTrack = createSampleTrack('short_track_1', 'Short Track', duration: 40).toSong();
      mockPlayer.setTestDuration(const Duration(seconds: 40));

      await handler.queueHandler.loadQueue([shortTrack], initialIndex: 0, autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // At 18 seconds (< 50% of 40s = 20s): not yet scrobbled
      mockPlayer.emitPosition(const Duration(seconds: 18));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler.hasRecordedHistory, isFalse);
      expect(HistoryManager.getHistoryEntries().isEmpty, isTrue);

      // At 20 seconds (>= 50%): committed to history!
      mockPlayer.emitPosition(const Duration(seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler.hasRecordedHistory, isTrue);
      expect(HistoryManager.getHistoryEntries().length, equals(1));
      expect(HistoryManager.getHistoryEntries().first.track.id, equals('short_track_1'));

      await handler.disposeAudioHandler();
      await mockPlayer.dispose();
    });
  });
}
