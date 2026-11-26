import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../domain/models/track_entity.dart';
import '../domain/models/app_error.dart';
import '../services/download_manager.dart';
import '../services/settings_manager.dart';
import '../services/youtube_client.dart';
import '../services/error_handler.dart';
import '../services/player_handler.dart';
import '../services/app_logger.dart';
import '../services/catalog_database.dart';
import '../services/battery_optimization_service.dart';
import '../services/queue_cooldown_manager.dart';
import '../services/des_decrypt.dart';
import '../services/connectivity_service.dart';
import '../services/smart_cache_service.dart';
import '../services/sleep_timer_service.dart';
import '../services/party_sync_coordinator.dart';
import 'stream_resolver.dart';
import 'next_track_strategy.dart';
import 'crossfade_engine.dart';
import 'queue/smart_shuffle_permutator.dart';
import 'audio/audio_dsp_calibrator.dart';

part 'audio/playback_error_recovery.dart';
part 'audio/queue_source_builder.dart';
part 'audio/audio_volume_and_idle.dart';
part 'audio/queue_stall_and_diag_ext.dart';
part 'audio/queue_skip_ext.dart';
part 'audio/queue_navigation_ext.dart';
part 'audio/queue_playback_ext.dart';
part 'audio/queue_loader_ext.dart';
part 'audio/queue_mutation_ext.dart';
part 'audio/queue_suggestions_ext.dart';
part 'audio/queue_listeners_ext.dart';

/// AudioQueueHandler: Two-Tier Decoupled Queue Engine matching Spotify and YouTube Music.
/// 
/// Decouples manual user additions from the album/playlist context queue:
/// 1. `_contextQueue` (List<TrackEntity>): Immutable/persistent album or playlist context.
/// 2. `_userQueue` (List<TrackEntity>): High-priority manual user queue ("Play Next" & "Add to Queue").
/// 3. `_contextShuffleIndices` (List<int>): Non-destructive index permutation table applied ONLY to `_contextQueue`.
/// 4. `_playbackHistory` (List<TrackEntity>): Previous track stack for backward navigation.
///
/// Priority Order: [Current Track] -> [_userQueue] -> [Remaining _contextQueue]
class AudioQueueHandler {
  final AudioPlayer player;
  final StreamResolver streamResolver;
  final SmartShufflePermutator _shufflePermutator = SmartShufflePermutator();

  // Persistent ConcatenatingAudioSource for Spotify-grade gapless playback
  ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true,
  );

  // ================= Two-Tier Architecture State ================= //

  // 1. Context Queue: persistent album / playlist context
  final List<TrackEntity> _contextQueue = [];
  final List<int> _contextShuffleIndices = [];
  int _contextIndex = -1;
  bool _isShuffleEnabled = false;

  // 2. User Queue: high-priority explicit user queue (never shuffled, FIFO priority)
  final List<TrackEntity> _userQueue = [];

  // 3. Playback History: tracks played prior to current track
  final List<TrackEntity> _playbackHistory = [];

  // 4. Actually Played in Session (BloomeeTunes model)
  final List<TrackEntity> _actuallyPlayedInSession = [];

  // Anti-double-skip lock and advancement mutex
  String? _lastCompletedTrackId;
  bool _isAdvancing = false;
  bool _isTransitioning = false;

  // Active track state
  TrackEntity? _currentTrack;
  Song? _lastCompletedSeedSong;
  Song? get lastCompletedSeedSong => _lastCompletedSeedSong;
  @visibleForTesting
  set lastCompletedSeedSong(Song? song) => _lastCompletedSeedSong = song;
  bool _currentTrackIsFromUserQueue = false;
  int _playlistBaseIndex = 0;
  int _loadRequestId = 0;
  bool _isPreparing = false;
  bool get isPreparing => _isPreparing;
  int _activeLoadToken = 0;
  Timer? _preloadDebounceTimer;

  void _schedulePreload() {
    _preloadDebounceTimer?.cancel();
    _preloadDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (!_isDisposed && player.playing && !_isPreparing) {
        preloadUpcomingTracks();
      }
    });
  }

  // Streams for two-tier architecture
  final StreamController<TrackEntity?> _currentTrackController = StreamController<TrackEntity?>.broadcast();
  final StreamController<TrackEntity?> _nextTrackController = StreamController<TrackEntity?>.broadcast();
  final StreamController<List<TrackEntity>> _queueStreamController = StreamController<List<TrackEntity>>.broadcast();

  Stream<TrackEntity?> get currentTrackStream => _currentTrackController.stream;
  Stream<TrackEntity?> get nextTrackStream => _nextTrackController.stream;
  Stream<List<TrackEntity>> get queueStream => _queueStreamController.stream;

  // Atomic state notifiers for UI and notification sync
  final ValueNotifier<List<Song>> queueNotifier = ValueNotifier<List<Song>>([]);
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier<Song?>(null);
  final ValueNotifier<AppError?> errorNotifier = ValueNotifier<AppError?>(null);

  // Callbacks
  final void Function(Song song)? onSongChanged;
  final void Function(int currentIndex, int totalQueue)? onQueueProgress;
  final void Function(bool isPlaying)? onPlayStateChanged;
  final VoidCallback? onIdleRelease;
  final void Function(AppError error)? onError;

  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<SequenceState?>? _sequenceStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  Timer? _idleTimeoutTimer;

  int _sessionToken = 0;
  int _activeLoadSessionToken = 0;
  bool _isLoading = false;
  bool _isDisposed = false;
  bool isPartyDrivenLoad = false;
  int _fadeToken = 0;
  int _lastCrossfadeTimeMs = 0;
  late final CrossfadeEngine _crossfadeEngine = CrossfadeEngine(primaryPlayer: player);
  bool _hasRetriedCurrentTrack = false;
  bool _hasDownscaledCurrentTrack = false;
  Timer? _bufferStallTimer;
  Timer? _volumeWatchdogTimer;
  bool _hasEnforcedInitialVolume = false;
  bool _isRecovering = false;
  bool _hasTriggered25PctRecs = false;
  bool _hasTriggered70PctPrecache = false;

  void _resetTrackMilestones() {
    _hasTriggered25PctRecs = false;
    _hasTriggered70PctPrecache = false;
  }
  bool _wasStalledByNetwork = false;
  Duration _networkStallOffset = Duration.zero;
  int _consecutivePlaybackErrors = 0;
  static const int _maxConsecutivePlaybackErrors = 3;
  VoidCallback? _connectivityListener;

  AudioQueueHandler({
    required this.player,
    StreamResolver? streamResolver,
    this.onSongChanged,
    this.onQueueProgress,
    this.onPlayStateChanged,
    this.onIdleRelease,
    this.onError,
  }) : streamResolver = streamResolver ?? DefaultStreamResolver() {
    _initStreamListeners();
    SettingsManager.volumeNormalizationNotifier.addListener(_onNormalizationChanged);
    _connectivityListener = () => _onConnectivityChanged();
    ConnectivityService.isOnlineNotifier.addListener(_connectivityListener!);
  }

  // ================= Public Queue Getters ================= //

  LoopMode get _effectiveLoopMode {
    try {
      return player.loopMode;
    } catch (_) {
      return LoopMode.off;
    }
  }

  TrackEntity? get currentTrack => _currentTrack;

  TrackEntity? get nextTrack {
    // 1. User queue has absolute immediate priority
    if (_userQueue.isNotEmpty) {
      return _userQueue.first;
    }
    // 2. Remaining context tracks
    final remaining = remainingContextTracks;
    if (remaining.isNotEmpty) {
      return remaining.first;
    }
    // 3. RepeatMode.all: loop context queue only
    if (_effectiveLoopMode == LoopMode.all && _contextQueue.isNotEmpty) {
      if (_isShuffleEnabled && _contextShuffleIndices.isNotEmpty) {
        return _contextQueue[_contextShuffleIndices[0]];
      }
      return _contextQueue[0];
    }
    return null;
  }

  List<TrackEntity> get contextQueue => List.unmodifiable(_contextQueue);
  List<TrackEntity> get userQueue => List.unmodifiable(_userQueue);
  List<TrackEntity> get playbackHistory => List.unmodifiable(_playbackHistory);
  List<TrackEntity> get playedTracks => List.unmodifiable(_actuallyPlayedInSession);
  List<int> get contextShuffleIndices => List.unmodifiable(_contextShuffleIndices);
  List<int> get shuffleIndices => _isShuffleEnabled ? contextShuffleIndices : List.generate(_contextQueue.length, (i) => i);
  bool get isShuffleEnabled => _isShuffleEnabled;
  int get contextIndex => _contextIndex;
  bool get currentTrackIsFromUserQueue => _currentTrackIsFromUserQueue;

  /// Remaining context tracks following current position in context sequence
  List<TrackEntity> get remainingContextTracks {
    if (_contextQueue.isEmpty) return const [];
    if (_isShuffleEnabled) {
      if (_contextIndex + 1 < _contextShuffleIndices.length) {
        return _contextShuffleIndices
            .sublist(_contextIndex + 1)
            .map((i) => _contextQueue[i])
            .toList();
      }
      return const [];
    } else {
      if (_contextIndex + 1 < _contextQueue.length) {
        return _contextQueue.sublist(_contextIndex + 1);
      }
      return const [];
    }
  }

  /// Merged effective queue: [Played Context] + [Current Track] + [_userQueue] + [Remaining _contextQueue]
  List<Song> get queue => _buildMergedQueue().map((t) => t.toSong()).toList();
  List<Song> get rawQueue => _contextQueue.map((t) => t.toSong()).toList();
  List<Song> get originalQueue => _contextQueue.map((t) => t.toSong()).toList();

  int get currentIndex {
    final merged = _buildMergedQueue();
    if (_currentTrack == null || merged.isEmpty) return -1;
    final idx = merged.indexWhere((t) => t.id == _currentTrack!.id);
    return idx != -1 ? idx : 0;
  }

  int get playlistBaseIndex => _playlistBaseIndex;
  Song? get currentSong => _currentTrack?.toSong();
  Song? get nextSong => nextTrack?.toSong();
  bool get hasNext => _userQueue.isNotEmpty || remainingContextTracks.isNotEmpty;
  bool get hasPrevious => _playbackHistory.isNotEmpty || _contextIndex > 0;
  int get upcomingCount => _userQueue.length + remainingContextTracks.length;
  bool get isLoading => _isLoading;

  int getPendingUserQueueCount() => _userQueue.length;
  int get userQueueEndIndex => currentIndex + 1 + _userQueue.length;

  // ================= Master Volume & Normalization ================= //

  double _userVolume = 1.0;
  double get userVolume => _userVolume;

  /// Sets master playback volume (0.0 to 1.0) and applies song normalization
  Future<void> setUserVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    final effective = getEffectiveVolumeForSong(currentSong);
    try {
      await player.setVolume(effective);
    } catch (e) {
      AppLogger.debug('AudioQueueHandler', 'Handled exception: $e');
    }
  }

  /// Calculates target normalized volume (0.0 to 1.0)
  static double getNormalizedVolumeForSong(Song? song) =>
      AudioDspCalibrator.getNormalizedVolumeForSong(song);

  /// Calculates effective volume taking both master volume and song calibration into account
  double getEffectiveVolumeForSong(Song? song) =>
      AudioDspCalibrator.getEffectiveVolumeForSong(song, _userVolume);

  // ================= Stream Listeners ================= //

  void _initStreamListeners() => _initStreamListenersImpl();

  /// Monitors active playback for prolonged buffer stalls (>3.5s) on weak networks.
  /// If the current track is on a high bitrate (e.g. 320kbps or 160kbps), dynamically
  /// downscales to the next available bitrate (e.g. 160kbps or 96kbps) in-place at the exact
  /// current playback position. This eliminates prolonged buffering without interrupting audio.
  static Future<String> diagnosePlaybackError(Song song, dynamic error, StackTrace? stack) =>
      _diagnosePlaybackErrorImpl(song, error, stack);

  /// Automatic stream re-attachment engine:
  /// When network reconnects after an outage, automatically invalidates expired/broken stream URLs,
  /// obtains a fresh stream URL, seeks to the cached playback offset, and resumes without user intervention.
  Future<void> _onConnectivityChanged() => _onConnectivityChangedImpl();

  void _syncState() {
    final merged = _buildMergedQueue();
    final curSong = _currentTrack?.toSong();
    final curIdx = currentIndex;

    currentIndexNotifier.value = curIdx;
    queueNotifier.value = merged.map((t) => t.toSong()).toList();
    currentSongNotifier.value = curSong;

    _currentTrackController.add(_currentTrack);
    _nextTrackController.add(nextTrack);
    _queueStreamController.add(merged);
  }

  // ================= Load Queue & Initial Setup ================= //

  /// Plays a standalone track (e.g. from History or Search), clearing context queue
  /// and resetting session playback history while preserving any manual user queue.
  Future<void> playTrack(TrackEntity track, {bool preserveUserQueue = true}) async {
    await loadQueue(
      [track],
      initialIndex: 0,
      autoPlay: true,
      preserveUserQueue: preserveUserQueue,
    );
  }

  Future<void> loadQueue(
    List<dynamic> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
    bool isPartyDriven = false,
    bool preserveUserQueue = false,
  }) =>
      _loadQueueImpl(
        tracks,
        initialIndex: initialIndex,
        autoPlay: autoPlay,
        isPartyDriven: isPartyDriven,
        preserveUserQueue: preserveUserQueue,
      );

  // ================= Deterministic "Play Next" and "Add to Queue" ================= //

  /// Insert track at index 0 of the user queue.
  /// MUST play immediately after the current song, regardless of shuffle state.
  Future<void> playNext(dynamic track) => _playNextImpl(track);

  /// Backward-compatible alias for playNext
  Future<void> insertNext(dynamic track) => playNext(track);

  /// Append track to the end of the user queue.
  /// Plays after all existing user-queued tracks, before returning to the context queue.
  Future<void> addToQueue(dynamic track) => _addToQueueImpl(track);

  /// Append multiple tracks sequentially to the user queue
  Future<void> addAllToQueue(List<dynamic> tracks) => _addAllToQueueImpl(tracks);

  /// Insert track at specific index in merged queue maintaining two-tier separation
  Future<void> insertAt(int index, dynamic track) => _insertAtImpl(index, track);

  // ================= Non-Destructive Shuffle Permutation ================= //

  /// Apply shuffle ONLY to _contextQueue using an index permutation list.
  /// Never shuffles _userQueue (user queue retains strict FIFO priority).
  Future<void> setShuffleEnabled(bool enable) => _setShuffleEnabledImpl(enable);

  Future<void> toggleShuffle() async {
    await setShuffleEnabled(!_isShuffleEnabled);
  }

  // ================= Track Navigation & Consumption ================= //

  /// Skip to next track: consumes _userQueue first, then advances _contextQueue
  Future<void> skipToNext({bool isUserInitiated = true}) =>
      _skipToNextImpl(isUserInitiated: isUserInitiated);

  /// Skip to previous track in playback history or context sequence
  Future<void> skipToPrevious() => _skipToPreviousImpl();

  /// Jump directly to any index in the merged queue with guaranteed index alignment
  Future<void> jumpToIndex(int targetIndex) => _jumpToIndexImpl(targetIndex);

  /// Jumps directly to any track in Up Next, Next in Queue, or Played history in-place
  /// without re-adding or duplicating songs in the context queue.
  Future<void> skipToQueueItem(
    TrackEntity targetTrack, {
    bool fromUserQueue = false,
    bool fromPlayedHistory = false,
  }) =>
      _skipToQueueItemImpl(
        targetTrack,
        fromUserQueue: fromUserQueue,
        fromPlayedHistory: fromPlayedHistory,
      );

  /// Handles gapless advance when just_audio ConcatenatingAudioSource fires index 1
  void _advanceToNextTrackFromPlayerStream([String? expectedId]) =>
      _advanceToNextTrackFromPlayerStreamImpl(expectedId);

  /// Handles seamless looping when RepeatMode.all / LoopMode.all reaches EOF.
  /// Loops ONLY _contextQueue; user-enqueued tracks are transient and never repeat.
  Future<void> handleRepeatAllLoop() => _handleRepeatAllLoopImpl();

  Future<void> _playTrackEntity(TrackEntity entity) => _playTrackEntityImpl(entity);

  // ================= Preloading & Sliding Window ================= //

  // ================= Auto-Suggestions & Recommendations ================= //

  Future<void> addAutoSuggestions(List<dynamic> tracks) =>
      _addAutoSuggestionsImpl(tracks);

  /// Replaces upcoming auto-suggested context tracks while preserving manual user queue
  /// and original album tracks.
  Future<void> replaceAutoSuggestions(List<dynamic> newSuggestions) =>
      _replaceAutoSuggestionsImpl(newSuggestions);

  // ================= Queue Mutation (Remove, Reorder, Clear) ================= //

  Future<void> removeAt(int index) => _removeAtImpl(index);

  Future<void> reorder(int oldIndex, int newIndex) => _reorderImpl(oldIndex, newIndex);

  Future<void> replaceUpcomingQueue(List<dynamic> newUpcoming) =>
      _replaceUpcomingQueueImpl(newUpcoming);

  Future<void> clearUserQueue() => _clearUserQueueImpl();

  Future<void> clear() => _clearImpl();

  // ================= Private AudioSource Builders & Helpers ================= //

  static TrackEntity _toEntity(dynamic track) {
    TrackEntity entity;
    if (track is TrackEntity) {
      entity = track;
    } else if (track is Song) {
      entity = track;
    } else if (track is MediaItem) {
      entity = TrackEntity.fromMediaItem(track);
    } else {
      throw ArgumentError('Track must be TrackEntity, Song, or MediaItem: $track');
    }
    if (DownloadManager.isDownloaded(entity.id)) {
      final localAudio = DownloadManager.getLocalFilePath(entity.id);
      final localCover = DownloadManager.getLocalCoverPath(entity.id);
      if (localAudio != null && File(localAudio).existsSync()) {
        return entity.copyWith(
          isDownloaded: true,
          localFilePath: localAudio,
          localCoverPath: localCover ?? entity.localCoverPath,
          source: 'offline',
        );
      }
    } else {
      final canonicalMatch = DownloadManager.findDownloadedMatch(entity.toSong());
      if (canonicalMatch != null &&
          canonicalMatch.localFilePath != null &&
          File(canonicalMatch.localFilePath!).existsSync()) {
        return entity.copyWith(
          isDownloaded: true,
          localFilePath: canonicalMatch.localFilePath,
          localCoverPath: canonicalMatch.localCoverPath ?? entity.localCoverPath,
          source: 'offline',
        );
      }
    }
    return entity;
  }

  List<TrackEntity> _buildMergedQueue() {
    final result = <TrackEntity>[];
    if (_contextQueue.isEmpty && _userQueue.isEmpty && _currentTrack == null) {
      return result;
    }

    final contextSeq = _isShuffleEnabled
        ? _contextShuffleIndices.map((i) => _contextQueue[i]).toList()
        : _contextQueue;

    if (!_currentTrackIsFromUserQueue) {
      if (_contextIndex > 0 && _contextIndex <= contextSeq.length) {
        result.addAll(contextSeq.sublist(0, _contextIndex));
      }
      if (_currentTrack != null) {
        result.add(_currentTrack!);
      }
      result.addAll(_userQueue);
      if (_contextIndex + 1 < contextSeq.length) {
        result.addAll(contextSeq.sublist(_contextIndex + 1));
      }
    } else {
      if (_contextIndex >= 0 && _contextIndex < contextSeq.length) {
        result.addAll(contextSeq.sublist(0, _contextIndex + 1));
      }
      if (_currentTrack != null) {
        result.add(_currentTrack!);
      }
      result.addAll(_userQueue);
      if (_contextIndex + 1 < contextSeq.length) {
        result.addAll(contextSeq.sublist(_contextIndex + 1));
      }
    }

    return result;
  }

  static bool verifyAudioMatch(Song candidate, Song target) {
    return DefaultStreamResolver.verifyMatch(candidate, target);
  }

  void dispose() {
    _isDisposed = true;
    _fadeToken++;
    if (_connectivityListener != null) {
      ConnectivityService.isOnlineNotifier.removeListener(_connectivityListener!);
      _connectivityListener = null;
    }
    SettingsManager.volumeNormalizationNotifier.removeListener(_onNormalizationChanged);
    _playbackEventSub?.cancel();
    _positionSub?.cancel();
    _volumeWatchdogTimer?.cancel();
    _preloadDebounceTimer?.cancel();
    _crossfadeEngine.dispose();
    cancelIdleTimer();
    _cancelBufferStallWatchdog();
    _sequenceStateSub?.cancel();
    _currentIndexSub?.cancel();
    _playerStateSub?.cancel();
    _currentTrackController.close();
    _nextTrackController.close();
    _queueStreamController.close();
    queueNotifier.dispose();
    currentIndexNotifier.dispose();
    currentSongNotifier.dispose();
    errorNotifier.dispose();
  }
}
