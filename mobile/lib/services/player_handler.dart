import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'api_client.dart';
import 'download_manager.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';

late PaatuAudioHandler audioHandler;

class PaatuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  // Reactive State Notifiers for UI binding
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier<Song?>(null);
  final ValueNotifier<List<Song>> playlistNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<bool> isSmartShuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentLyricsNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<Duration?> sleepTimerRemainingNotifier = ValueNotifier<Duration?>(null);

  List<Song> _playlist = [];
  List<Song> _originalPlaylist = [];
  int _currentIndex = -1;
  Timer? _sleepTimer;
  Timer? _countdownTicker;

  AudioPlayer get player => _player;
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_currentIndex >= 0 && _currentIndex < _playlist.length) ? _playlist[_currentIndex] : null;

  PaatuAudioHandler() {
    _initStreams();
  }

  bool _hasRecordedListen = false;

  void _broadcastState() {
    final playing = _player.playing;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState] ?? AudioProcessingState.idle;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    ));
  }

  void _initStreams() {
    _player.playbackEventStream.listen((event) => _broadcastState());

    _player.playerStateStream.listen((state) {
      _broadcastState();
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });

    // 15-second listen tracker: trains backend item-item collaborative filtering ML graph!
    _player.positionStream.listen((pos) {
      if (!_hasRecordedListen && pos.inSeconds >= 15 && currentSong != null) {
        _hasRecordedListen = true;
        ApiClient.addListenHistory(currentSong!);
      }
    });
  }

  void _syncQueueState() {
    playlistNotifier.value = List.from(_playlist);
    currentIndexNotifier.value = _currentIndex;
    final song = currentSong;
    currentSongNotifier.value = song;
  }

  Future<void> playSong(Song song, {List<Song>? queue}) async {
    if (queue != null && queue.isNotEmpty) {
      _playlist = List.from(queue);
      _originalPlaylist = List.from(queue);
      _currentIndex = _playlist.indexWhere((s) => s.id == song.id);
      if (_currentIndex == -1) {
        _playlist.insert(0, song);
        _currentIndex = 0;
      }
    } else {
      _playlist = [song];
      _originalPlaylist = [song];
      _currentIndex = 0;
    }

    _syncQueueState();
    await _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(Song song) async {
    try {
      _hasRecordedListen = false;
      currentSongNotifier.value = song;
      currentLyricsNotifier.value = (song.lyrics != null && song.lyrics!.isNotEmpty) ? song.lyrics : null;

      // 1. Fetch multi-source lyrics asynchronously in background
      ApiClient.fetchLyrics(song).then((lyrics) {
        if (currentSong?.id == song.id && lyrics != null && lyrics.isNotEmpty) {
          currentLyricsNotifier.value = lyrics;
        }
      });

      // 2. Play from local storage if downloaded
      if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
        await _player.setAudioSource(AudioSource.file(song.localFilePath!));
      } else if (DownloadManager.isDownloaded(song.id)) {
        final downloadedSongs = DownloadManager.getDownloadedSongs();
        final match = downloadedSongs.firstWhere((s) => s.id == song.id, orElse: () => song);
        if (match.localFilePath != null && File(match.localFilePath!).existsSync()) {
          await _player.setAudioSource(AudioSource.file(match.localFilePath!));
        } else {
          await _resolveRemoteAndPlay(song);
        }
      } else {
        await _resolveRemoteAndPlay(song);
      }

      // 3. Update Android lock-screen and notification controls
      mediaItem.add(MediaItem(
        id: song.id,
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: Duration(seconds: song.duration),
        artUri: Uri.tryParse(song.coverUrl),
      ));

      await _player.play();
      _broadcastState();
    } catch (e) {
      // If primary playback fails, attempt YouTube fallback before giving up
      try {
        final ytResults = await YouTubeClient.search('${song.title} ${song.artist}', limit: 1);
        if (ytResults.isNotEmpty) {
          final streamUrl = await YouTubeClient.getAudioStreamUrl(ytResults.first.id);
          if (streamUrl != null) {
            await _player.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
            await _player.play();
            _broadcastState();
            return;
          }
        }
      } catch (_) {}
      
      // If both fail, advance to next track
      skipToNext();
    }
  }

  Future<void> _resolveRemoteAndPlay(Song song) async {
    String? streamUrl = song.streamUrl;

    // If stream URL is missing, resolve it
    if (streamUrl == null || streamUrl.isEmpty) {
      if (song.source == 'youtube') {
        streamUrl = await YouTubeClient.getAudioStreamUrl(song.id);
      } else {
        final matches = await SaavnClient.search('${song.title} ${song.artist}', limit: 1);
        if (matches.isNotEmpty && matches.first.streamUrl != null) {
          streamUrl = matches.first.streamUrl;
        }
      }
    }

    if (streamUrl != null && streamUrl.isNotEmpty) {
      // Set audio source with standard headers
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(streamUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko)',
          },
        ),
      );
    } else {
      throw Exception("Could not resolve valid audio stream URL");
    }
  }

  // ================= Queue Management ================= //

  void insertNext(Song song) {
    if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
      _playlist.insert(_currentIndex + 1, song);
    } else {
      _playlist.add(song);
    }
    _syncQueueState();
  }

  void addToQueue(Song song) {
    _playlist.add(song);
    _syncQueueState();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _playlist.length) return;
    if (index == _currentIndex) {
      // If removing current song, skip to next then remove
      skipToNext();
    }
    _playlist.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    }
    _syncQueueState();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, item);

    // Track active playing index
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    _syncQueueState();
  }

  Future<void> jumpToIndex(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      _syncQueueState();
      await _loadAndPlay(_playlist[_currentIndex]);
    }
  }

  void clearQueue() {
    if (currentSong != null) {
      _playlist = [currentSong!];
      _currentIndex = 0;
    } else {
      _playlist.clear();
      _currentIndex = -1;
    }
    _syncQueueState();
  }

  // ================= Smart Shuffle & Recommendations ================= //

  Future<void> toggleSmartShuffle() async {
    final nextState = !isSmartShuffleNotifier.value;
    isSmartShuffleNotifier.value = nextState;

    if (nextState) {
      // Intelligent shuffle via recommendation graph
      if (_playlist.length > 2 && currentSong != null) {
        final orderedIds = await ApiClient.fetchSmartShuffle(_playlist, currentSong);

        final Map<String, Song> map = {for (final s in _playlist) s.id: s};
        final List<Song> reordered = [];
        for (final id in orderedIds) {
          if (map.containsKey(id)) {
            reordered.add(map[id]!);
          }
        }
        for (final s in _playlist) {
          if (!reordered.any((r) => r.id == s.id)) {
            reordered.add(s);
          }
        }

        _playlist = reordered;
        _currentIndex = _playlist.indexWhere((s) => s.id == currentSong!.id);
        _syncQueueState();
      }
    } else {
      // Restore standard playlist
      if (_originalPlaylist.isNotEmpty && currentSong != null) {
        _playlist = List.from(_originalPlaylist);
        _currentIndex = _playlist.indexWhere((s) => s.id == currentSong!.id);
        if (_currentIndex == -1) _currentIndex = 0;
        _syncQueueState();
      }
    }
  }

  Future<int> addRadioMix() async {
    if (currentSong == null) return 0;
    final recommendations = await ApiClient.fetchRecommendations(
      currentSong!.id,
      artist: currentSong!.artist,
    );

    if (recommendations.isNotEmpty) {
      // Filter out songs already in the queue
      final existingIds = _playlist.map((s) => s.id).toSet();
      final fresh = recommendations.where((s) => !existingIds.contains(s.id)).toList();
      _playlist.addAll(fresh);
      _syncQueueState();
      return fresh.length;
    }
    return 0;
  }

  // ================= Sleep Timer ================= //

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    DateTime endTime = DateTime.now().add(duration);
    sleepTimerRemainingNotifier.value = duration;

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = endTime.difference(DateTime.now());
      if (remaining.isNegative) {
        cancelSleepTimer();
        pause();
      } else {
        sleepTimerRemainingNotifier.value = remaining;
      }
    });

    _sleepTimer = Timer(duration, () {
      pause();
      cancelSleepTimer();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _countdownTicker?.cancel();
    _sleepTimer = null;
    _countdownTicker = null;
    sleepTimerRemainingNotifier.value = null;
  }

  // ================= Standard Controls ================= //

  @override
  Future<void> play() async {
    await _player.play();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    currentSongNotifier.value = null;
    await _player.stop();
    _broadcastState();
    await super.stop();
  }

  Future<void> toggleLoopMode() async {
    final current = _player.loopMode;
    if (current == LoopMode.off) {
      await _player.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      await _player.setLoopMode(LoopMode.one);
    } else {
      await _player.setLoopMode(LoopMode.off);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex + 1 < _playlist.length) {
      _currentIndex++;
      _syncQueueState();
      await _loadAndPlay(_playlist[_currentIndex]);
    } else {
      // End of playlist: automatically try to load more radio recommendations!
      final added = await addRadioMix();
      if (added > 0 && _currentIndex + 1 < _playlist.length) {
        _currentIndex++;
        _syncQueueState();
        await _loadAndPlay(_playlist[_currentIndex]);
      } else {
        await _player.stop();
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      _syncQueueState();
      await _loadAndPlay(_playlist[_currentIndex]);
    } else {
      await _player.seek(Duration.zero);
    }
  }
}
