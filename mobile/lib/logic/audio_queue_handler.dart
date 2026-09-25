import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../services/download_manager.dart';
import '../services/saavn_client.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';

class AudioQueueHandler {
  final AudioPlayer player;

  // Persistent ConcatenatingAudioSource for Spotify-grade gapless playback
  ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true,
  );

  // Queue state
  final List<Song> _queue = [];
  final List<Song> _originalQueue = [];
  int _currentIndex = -1;

  // Atomic state notifiers for UI and notification sync
  final ValueNotifier<List<Song>> queueNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier<Song?>(null);

  // Callbacks
  final void Function(Song song)? onSongChanged;
  final void Function(int currentIndex, int totalQueue)? onQueueProgress;
  final void Function(bool isPlaying)? onPlayStateChanged;

  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<SequenceState?>? _sequenceStateSub;

  int _sessionToken = 0;
  bool _isLoading = false;

  AudioQueueHandler({
    required this.player,
    this.onSongChanged,
    this.onQueueProgress,
    this.onPlayStateChanged,
  }) {
    _initStreamListeners();
  }

  List<Song> get queue => List.unmodifiable(_queue);
  List<Song> get originalQueue => List.unmodifiable(_originalQueue);
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_currentIndex >= 0 && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;
  bool get hasNext => _currentIndex + 1 < _queue.length;
  bool get hasPrevious => _currentIndex > 0;
  int get upcomingCount => _queue.length - (_currentIndex + 1);
  bool get isLoading => _isLoading;

  void _initStreamListeners() {
    // Synchronous sequenceState listener: guarantees title, artist, and artwork are driven directly
    // and synchronously by player.sequenceStateStream.currentSource.tag so it never flashes previous track
    _sequenceStateSub = player.sequenceStateStream.listen((sequenceState) {
      if (sequenceState == null) return;
      final currentSource = sequenceState.currentSource;
      if (currentSource != null && currentSource.tag != null) {
        final tag = currentSource.tag;
        Song? activeSong;
        if (tag is Song) {
          activeSong = tag;
        } else if (tag is MediaItem) {
          activeSong = Song.fromMediaItem(tag);
        }
        if (activeSong != null && activeSong.id != currentSongNotifier.value?.id) {
          _currentIndex = sequenceState.currentIndex;
          currentSongNotifier.value = activeSong;
          onSongChanged?.call(activeSong);
          onQueueProgress?.call(_currentIndex, _queue.length);
        }
      }
    });

    // Atomic synchronization on track transition: updates UI & notification instantly
    _currentIndexSub = player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _queue.length && index != _currentIndex) {
        _currentIndex = index;
        _syncState();

        final song = _queue[_currentIndex];
        onSongChanged?.call(song);
        onQueueProgress?.call(_currentIndex, _queue.length);

        // Preload upcoming tracks for instantaneous gapless transition
        preloadUpcomingTracks(_currentIndex);
      }
    });

    _playerStateSub = player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);

      if (state.processingState == ProcessingState.completed) {
        if (hasNext) {
          skipToNext();
        }
      }
    });
  }

  void _syncState() {
    currentIndexNotifier.value = _currentIndex;
    queueNotifier.value = List.from(_queue);
    currentSongNotifier.value = currentSong;
  }

  /// Initialize and load a queue with gapless ConcatenatingAudioSource
  Future<void> loadQueue(
    List<Song> songs, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    final token = ++_sessionToken;
    _isLoading = true;

    try {
      await player.stop();
    } catch (_) {}

    if (token != _sessionToken) return;

    _queue.clear();
    _originalQueue.clear();
    _queue.addAll(songs);
    _originalQueue.addAll(songs);
    _currentIndex = (initialIndex >= 0 && initialIndex < songs.length) ? initialIndex : 0;

    _syncState();
    final activeSong = _queue[_currentIndex];
    onSongChanged?.call(activeSong);

    // Build ConcatenatingAudioSource with initial active song & pre-buffered next song
    final List<AudioSource> sources = [];
    final activeSource = await _buildAudioSource(activeSong);
    if (activeSource != null) {
      sources.add(activeSource);
    }

    _playlistSource = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true,
    );

    try {
      await player.setAudioSource(
        _playlistSource,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );

      if (token != _sessionToken) return;

      if (autoPlay) {
        await player.play();
      }

      _isLoading = false;
      onQueueProgress?.call(_currentIndex, _queue.length);

      // Asynchronously buffer upcoming tracks
      preloadUpcomingTracks(_currentIndex);
    } catch (e) {
      _isLoading = false;
      debugPrint('[AudioQueueHandler] Error initializing queue: $e');
    }
  }

  /// Preloads upcoming tracks into ConcatenatingAudioSource ahead of time
  Future<void> preloadUpcomingTracks(int fromIndex) async {
    final token = _sessionToken;

    // Buffer upcoming tracks: fromIndex + 1 and fromIndex + 2
    for (int offset = 1; offset <= 3; offset++) {
      final targetIndex = fromIndex + offset;
      if (targetIndex >= 0 && targetIndex < _queue.length) {
        final song = _queue[targetIndex];

        // Resolve stream URL if missing
        if (song.streamUrl == null || song.streamUrl!.isEmpty) {
          final url = await _resolveStreamUrl(song);
          if (token != _sessionToken) return;
          if (url != null && url.isNotEmpty) {
            song.streamUrl = url;
          }
        }

        // Add to persistent ConcatenatingAudioSource if not already appended
        if (targetIndex >= _playlistSource.length) {
          final source = await _buildAudioSource(song);
          if (source != null && token == _sessionToken) {
            try {
              await _playlistSource.add(source);
            } catch (_) {}
          }
        }
      }
    }
  }

  /// Skip to next track in queue with gapless transition
  Future<void> skipToNext() async {
    if (!hasNext) return;
    await jumpToIndex(_currentIndex + 1);
  }

  /// Skip to previous track in queue
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 4) {
      await player.seek(Duration.zero);
      return;
    }
    if (!hasPrevious) return;
    await jumpToIndex(_currentIndex - 1);
  }

  /// Jump directly to any index in the queue
  Future<void> jumpToIndex(int targetIndex) async {
    if (targetIndex < 0 || targetIndex >= _queue.length) return;
    final token = ++_sessionToken;

    _currentIndex = targetIndex;
    _syncState();
    final targetSong = _queue[targetIndex];
    onSongChanged?.call(targetSong);

    // If targetIndex already exists in _playlistSource, use gapless seek
    if (targetIndex < _playlistSource.length) {
      try {
        await player.seek(Duration.zero, index: targetIndex);
        await player.play();
        preloadUpcomingTracks(targetIndex);
        onQueueProgress?.call(_currentIndex, _queue.length);
        return;
      } catch (_) {}
    }

    // Otherwise, dynamically build and mount from targetIndex
    final targetSource = await _buildAudioSource(targetSong);
    if (token != _sessionToken) return;

    if (targetSource != null) {
      _playlistSource = ConcatenatingAudioSource(
        children: [targetSource],
        useLazyPreparation: true,
      );

      try {
        await player.setAudioSource(_playlistSource);
        if (token != _sessionToken) return;
        await player.play();
        preloadUpcomingTracks(targetIndex);
        onQueueProgress?.call(_currentIndex, _queue.length);
      } catch (e) {
        debugPrint('[AudioQueueHandler] Jump error: $e');
      }
    }
  }

  /// Add track to the end of the queue
  Future<void> addToQueue(Song song) async {
    _queue.add(song);
    _originalQueue.add(song);
    _syncState();

    if (song.streamUrl != null && song.streamUrl!.isNotEmpty) {
      final source = await _buildAudioSource(song);
      if (source != null) {
        try {
          await _playlistSource.add(source);
        } catch (_) {}
      }
    }
    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Insert track to play next (right after current index)
  Future<void> insertNext(Song song) async {
    final insertIdx = (_currentIndex >= 0 && _currentIndex < _queue.length) ? _currentIndex + 1 : _queue.length;
    await insertAt(insertIdx, song);
  }

  /// Insert track at specific index
  Future<void> insertAt(int index, Song song) async {
    final safeIndex = index.clamp(0, _queue.length);
    _queue.insert(safeIndex, song);
    if (!song.isSmartRecommended) {
      _originalQueue.insert(safeIndex.clamp(0, _originalQueue.length), song);
    }
    if (safeIndex <= _currentIndex) {
      _currentIndex++;
    }
    _syncState();

    final source = await _buildAudioSource(song);
    if (source != null) {
      try {
        if (safeIndex < _playlistSource.length) {
          await _playlistSource.insert(safeIndex, source);
        } else {
          await _playlistSource.add(source);
        }
      } catch (_) {}
    }
    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Remove track at index without disrupting playback
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final isRemovingCurrent = index == _currentIndex;

    final removed = _queue.removeAt(index);
    _originalQueue.removeWhere((s) => s.id == removed.id);

    if (index < _playlistSource.length) {
      try {
        await _playlistSource.removeAt(index);
      } catch (_) {}
    }

    if (isRemovingCurrent) {
      if (_currentIndex < _queue.length) {
        await jumpToIndex(_currentIndex);
      } else if (_queue.isNotEmpty) {
        await jumpToIndex(_queue.length - 1);
      } else {
        await clear();
      }
    } else {
      if (index < _currentIndex) {
        _currentIndex--;
      }
      _syncState();
      onQueueProgress?.call(_currentIndex, _queue.length);
    }
  }

  /// Reorder tracks seamlessly
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final song = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, song);

    // Adjust current index tracking
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    _syncState();

    if (oldIndex < _playlistSource.length && newIndex < _playlistSource.length) {
      try {
        await _playlistSource.move(oldIndex, newIndex);
      } catch (_) {}
    }

    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Replace upcoming queue with new list of tracks (used by Smart Shuffle)
  void replaceUpcomingQueue(List<Song> newUpcoming) {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    // Keep history and current playing song intact
    final kept = _queue.sublist(0, _currentIndex + 1);
    _queue.clear();
    _queue.addAll(kept);
    _queue.addAll(newUpcoming);

    _syncState();
    preloadUpcomingTracks(_currentIndex);
    onQueueProgress?.call(_currentIndex, _queue.length);
  }

  /// Clear queue
  Future<void> clear() async {
    _sessionToken++;
    try {
      await player.stop();
    } catch (_) {}

    _queue.clear();
    _originalQueue.clear();
    _currentIndex = -1;
    _syncState();

    try {
      await _playlistSource.clear();
    } catch (_) {}

    currentSongNotifier.value = null;
    onQueueProgress?.call(-1, 0);
  }

  // ================= Private AudioSource Builders ================= //

  Future<AudioSource?> _buildAudioSource(Song song) async {
    // 1. Local downloaded file
    if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
      return AudioSource.file(song.localFilePath!, tag: song.toMediaItem());
    }
    if (DownloadManager.isDownloaded(song.id)) {
      final downloadedSongs = DownloadManager.getDownloadedSongs();
      final match = downloadedSongs.firstWhere((s) => s.id == song.id, orElse: () => song);
      if (match.localFilePath != null && File(match.localFilePath!).existsSync()) {
        return AudioSource.file(match.localFilePath!, tag: song.toMediaItem());
      }
    }

    // 2. Stream URL
    String? streamUrl = song.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) {
      streamUrl = await _resolveStreamUrl(song);
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    // Quality bitrate adjustments for JioSaavn
    if (streamUrl.contains('jiosaavn') || streamUrl.contains('.mp4')) {
      final q = SettingsManager.streamingQuality;
      if (q == '96kbps') {
        streamUrl = streamUrl.replaceAll('_320.mp4', '_96.mp4').replaceAll('_160.mp4', '_96.mp4');
      } else if (q == '160kbps') {
        streamUrl = streamUrl.replaceAll('_320.mp4', '_160.mp4').replaceAll('_96.mp4', '_160.mp4');
      } else {
        streamUrl = streamUrl.replaceAll('_96.mp4', '_320.mp4').replaceAll('_160.mp4', '_320.mp4');
      }
    }
    song.streamUrl = streamUrl;

    // 3. Cache verification
    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final cacheFile = File('${tempDir.path}/audio_$sanitizedId.mp4');
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 100000) {
        return AudioSource.file(cacheFile.path, tag: song.toMediaItem());
      }
      return AudioSource.uri(Uri.parse(streamUrl), tag: song.toMediaItem());
    } catch (_) {
      return AudioSource.uri(Uri.parse(streamUrl), tag: song.toMediaItem());
    }
  }

  Future<String?> _resolveStreamUrl(Song song) async {
    if (song.source == 'youtube' || song.id.length == 11) {
      try {
        final query = YouTubeClient.cleanTitle('${song.title} ${song.artist}');
        final saavnMatches = await SaavnClient.search(query, limit: 1);
        if (saavnMatches.isNotEmpty && saavnMatches.first.streamUrl != null) {
          return saavnMatches.first.streamUrl;
        }
      } catch (_) {}
      try {
        return await YouTubeClient.getAudioStreamUrl(song.id, title: song.title, artist: song.artist);
      } catch (_) {}
    } else {
      try {
        final matches = await SaavnClient.search('${song.title} ${song.artist}', limit: 1);
        if (matches.isNotEmpty && matches.first.streamUrl != null) {
          return matches.first.streamUrl;
        }
      } catch (_) {}
    }
    return null;
  }

  void dispose() {
    _sequenceStateSub?.cancel();
    _currentIndexSub?.cancel();
    _playerStateSub?.cancel();
  }
}
