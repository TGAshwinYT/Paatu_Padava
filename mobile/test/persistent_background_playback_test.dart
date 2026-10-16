import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paatu_padava_mobile/domain/models/track_entity.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/services/history_manager.dart';
import 'package:paatu_padava_mobile/services/player_handler.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';

class _MockPlayer extends Fake implements AudioPlayer {
  bool _playing = false;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(seconds: 180);
  AudioSource? _audioSource;
  int _sourceIndex = 0;
  double _volume = 1.0;
  bool stopCalled = false;

  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _currentIndexController = StreamController<int?>.broadcast();
  final _sequenceStateController = StreamController<SequenceState?>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _playbackEventController = StreamController<PlaybackEvent>.broadcast();
  final _sessionIdController = StreamController<int?>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  _MockPlayer() {
    _playerStateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  @override Stream<int?> get currentIndexStream => _currentIndexController.stream;
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
    stopCalled = true;
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

dynamic _createSong(String id, String title) {
  return TrackEntity(
    id: id,
    title: title,
    artist: 'Artist $id',
    album: 'Album $id',
    streamUrl: 'https://example.com/audio_$id.mp3',
    coverUrl: 'https://example.com/cover_$id.jpg',
    duration: 180,
    source: 'saavn',
  ).toSong();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('persistent_playback_test_hive_');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen(SettingsManager.boxName)) {
      await Hive.openBox(SettingsManager.boxName);
    }
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
    await SettingsManager.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Persistent Background Playback Setting & Resilience Tests', () {
    test('1. Setting defaults to OFF (false)', () {
      // Must be disabled by default per user requirement
      expect(SettingsManager.isPersistentBackgroundPlaybackEnabled, isFalse);
      expect(SettingsManager.persistentBackgroundPlaybackNotifier.value, isFalse);
    });

    test('2. Toggling setting updates notifier and persists in Hive', () async {
      await SettingsManager.setPersistentBackgroundPlayback(true);
      expect(SettingsManager.isPersistentBackgroundPlaybackEnabled, isTrue);
      expect(SettingsManager.persistentBackgroundPlaybackNotifier.value, isTrue);

      // Re-read directly from Hive box
      final box = Hive.box(SettingsManager.boxName);
      expect(box.get('persistent_background_playback'), isTrue);

      // Toggle back to false
      await SettingsManager.setPersistentBackgroundPlayback(false);
      expect(SettingsManager.isPersistentBackgroundPlaybackEnabled, isFalse);
      expect(box.get('persistent_background_playback'), isFalse);
    });

    test('3. onTaskRemoved() stops playback immediately when setting is OFF', () async {
      await SettingsManager.setPersistentBackgroundPlayback(false);

      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      final s1 = _createSong('s1', 'Song One');
      await handler.queueHandler.loadQueue([s1], initialIndex: 0, autoPlay: false);
      mockPlayer.stopCalled = false;
      await mockPlayer.play();
      expect(mockPlayer.playing, isTrue);

      // Simulate Android OS calling onTaskRemoved (swiped away from RAM/Recents)
      await handler.onTaskRemoved();

      // Since setting is OFF, handler must call stop() immediately
      expect(mockPlayer.stopCalled, isTrue);
      expect(mockPlayer.playing, isFalse);
      expect(handler.isAppTaskRemoved, isTrue);
    });

    test('4. onTaskRemoved() keeps playing when setting is ON and song is playing', () async {
      await SettingsManager.setPersistentBackgroundPlayback(true);

      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      final s1 = _createSong('s1', 'Song One');
      final s2 = _createSong('s2', 'Song Two');
      await handler.queueHandler.loadQueue([s1, s2], initialIndex: 0, autoPlay: false);
      mockPlayer.stopCalled = false;
      await mockPlayer.play();
      expect(mockPlayer.playing, isTrue);

      // Simulate Android OS calling onTaskRemoved (swiped away from RAM/Recents)
      await handler.onTaskRemoved();

      // Setting is ON: player must NOT be stopped! Playback continues uninterrupted
      expect(mockPlayer.stopCalled, isFalse);
      expect(mockPlayer.playing, isTrue);
      expect(handler.isAppTaskRemoved, isTrue);

      // Queue advancement test: when current track skips to next in background
      await handler.queueHandler.skipToNext();
      expect(handler.currentSong?.id, equals('s2'));
    });

    test('5. onTaskRemoved() stops player if user was paused when clearing app even if setting is ON', () async {
      await SettingsManager.setPersistentBackgroundPlayback(true);

      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      final s1 = _createSong('s1', 'Song One');
      await handler.queueHandler.loadQueue([s1], initialIndex: 0, autoPlay: false);
      mockPlayer.stopCalled = false;
      await mockPlayer.pause();
      expect(mockPlayer.playing, isFalse);

      // Swiped away from recents while already paused
      await handler.onTaskRemoved();

      // Since nothing was actively playing, service stops completely
      expect(mockPlayer.stopCalled, isTrue);
    });

    test('6. Tapping Pause after app was cleared terminates service completely', () async {
      await SettingsManager.setPersistentBackgroundPlayback(true);

      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      final s1 = _createSong('s1', 'Song One');
      await handler.queueHandler.loadQueue([s1], initialIndex: 0, autoPlay: false);
      mockPlayer.stopCalled = false;
      await mockPlayer.play();
      expect(mockPlayer.playing, isTrue);

      // App cleared from recents
      await handler.onTaskRemoved();
      expect(handler.isAppTaskRemoved, isTrue);
      expect(mockPlayer.stopCalled, isFalse);

      // User pauses playback from Notification / Lockscreen / Bluetooth
      await handler.pause();

      // Should terminate service completely (stop called)
      expect(mockPlayer.stopCalled, isTrue);
    });

    test('7. Resuming app lifecycle resets isAppTaskRemoved flag', () async {
      await SettingsManager.setPersistentBackgroundPlayback(true);

      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      await handler.onTaskRemoved();
      expect(handler.isAppTaskRemoved, isTrue);

      // User reopens the app from launcher
      handler.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(handler.isAppTaskRemoved, isFalse);

      // Normal in-app pause does not kill the whole service
      mockPlayer.stopCalled = false;
      await mockPlayer.play();
      await handler.pause();
      expect(mockPlayer.stopCalled, isFalse);
      expect(mockPlayer.playing, isFalse);
    });

    test('8. onNotificationDeleted() terminates playback cleanly', () async {
      final mockPlayer = _MockPlayer();
      final handler = PaatuAudioHandler(player: mockPlayer);
      audioHandler = handler;

      await handler.onNotificationDeleted();
      expect(mockPlayer.stopCalled, isTrue);
    });
  });
}
