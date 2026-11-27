import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../logic/party_sync_engine.dart';
import '../logic/stream_resolver.dart';
import '../models/song.dart';
import '../platform/sync_platform.dart';
import 'download_manager.dart';
import 'player_handler.dart';
import 'settings_manager.dart';
import 'supabase_service.dart';
import 'app_logger.dart';

part 'party/party_remote_handlers.dart';
part 'party/party_ntp_sync.dart';
part 'party/party_host_controls.dart';
part 'party/party_host_flow.dart';
part 'party/party_joiner_flow.dart';
part 'party/party_drift_controller.dart';

enum PartyRole { none, host, joiner }

/// Peer device metadata and live telemetry in Party Mode
class PeerDeviceInfo {
  final String id;
  final String deviceName;
  final String role; // 'Host' or 'Speaker'
  final int rttMs;
  final DateTime lastSeen;
  final bool isSelf;

  const PeerDeviceInfo({
    required this.id,
    required this.deviceName,
    required this.role,
    this.rttMs = 0,
    required this.lastSeen,
    this.isSelf = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'deviceName': deviceName,
    'role': role,
    'rttMs': rttMs,
  };

  factory PeerDeviceInfo.fromMap(Map<String, dynamic> map, {bool isSelf = false}) => PeerDeviceInfo(
    id: map['id']?.toString() ?? '',
    deviceName: map['deviceName']?.toString() ?? 'Mobile Device',
    role: map['role']?.toString() ?? 'Speaker',
    rttMs: (map['rttMs'] as num?)?.toInt() ?? 0,
    lastSeen: DateTime.now(),
    isSelf: isSelf,
  );

  PeerDeviceInfo copyWith({
    String? id,
    String? deviceName,
    String? role,
    int? rttMs,
    DateTime? lastSeen,
    bool? isSelf,
  }) => PeerDeviceInfo(
    id: id ?? this.id,
    deviceName: deviceName ?? this.deviceName,
    role: role ?? this.role,
    rttMs: rttMs ?? this.rttMs,
    lastSeen: lastSeen ?? this.lastSeen,
    isSelf: isSelf ?? this.isSelf,
  );
}

/// Coordinates multi-phone synchronized playback ("Party Mode").
///
/// Features:
/// 1. Authoritative Reference Clock: Host announces {referenceHostEpochMs, referencePositionMs, isPlaying}.
/// 2. Hold-Before-Start on Host: Scheduled starts hold the host player until startAtEpochMs.
/// 3. Monotonic Event Sequencing: Sequence numbers and generation tokens prevent out-of-order race conditions.
/// 4. Cancellable Operations: Pending delayed play and seek timers are cleanly cancelled when state changes.
/// 5. Dual-Transport Architecture: High-frequency UDP unicast on local Wi-Fi with Supabase Realtime fallback.
/// 6. Multi-Tier Gentle Drift Correction: Inaudible ±0.5% micro-adjustments with hysteresis deadbands.
/// 7. Automatic Ghost Pruning: Inactive peers (>8s) are pruned from active presence lists.
class PartySyncCoordinator {
  static final Random _random = Random.secure();
  static const Uuid _uuid = Uuid();

  static final ValueNotifier<PartyRole> roleNotifier = ValueNotifier<PartyRole>(PartyRole.none);
  static final ValueNotifier<String?> partyCodeNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> partyPinNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<int> clockOffsetMsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> measuredRttMsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> currentDriftMsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<String> syncStatusDescription = ValueNotifier<String>('Idle');
  static final ValueNotifier<int> peerCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<List<PeerDeviceInfo>> connectedPeersNotifier =
      ValueNotifier<List<PeerDeviceInfo>>([]);

  static final Map<String, PeerDeviceInfo> _knownPeers = {};
  static bool _isSyncLoading = false;

  static PartyRole get role => roleNotifier.value;
  static String? get partyCode => partyCodeNotifier.value;
  static String? get partyPin => partyPinNotifier.value;
  static int get clockOffsetMs => clockOffsetMsNotifier.value;
  static bool get isHost => role == PartyRole.host;
  static bool get isJoiner => role == PartyRole.joiner;
  static bool get isActive => role != PartyRole.none;
  static ValueNotifier<bool> get isLanActiveNotifier => PartyLanAccelerator.isLanActiveNotifier;

  static RealtimeChannel? _partyChannel;
  static Timer? _hostHeartbeatTimer;
  static Timer? _ntpHandshakeTimer;
  static Timer? _rollingNtpTimer;
  static Timer? _pendingScheduledPlayTimer;
  static Timer? _pendingSeekTimer;

  static final String _clientId = _uuid.v4();
  static String _sessionSecret = '';
  static int _currentHostSeq = 0;
  static int _lastProcessedSeq = 0;
  static final List<NtpSample> _ntpSamples = [];
  static final Set<String> _processedEventKeys = {};
  static final Set<String> _processedCmdIds = {};
  static Completer<void>? _peerReadyCompleter;
  static String? _pendingPrepareCmdId;
  static String? get pendingPrepareCmdId => _pendingPrepareCmdId;
  static List<String> _localIps = [];
  static String? _lastAnnouncedSongId;
  static int _lastAnnouncedTimeMs = 0;
  static int _lastHardSeekEpochMs = 0;
  static Function(Song song)? onJoinerManualPlayAttempted;

  static int get _effectiveBluetoothDelayMs {
    final manual = SettingsManager.bluetoothDelayMs;
    if (manual != 0) return manual;
    // Zero-Touch auto-calibration: automatically compensate standard Bluetooth A2DP DAC lag
    if (DeviceConnectCoordinator.instance.isBluetoothActive) {
      return -140;
    }
    return 0;
  }

  /// Downshifts high-bitrate 320k streams to 96k/160k on cellular connections or high network latency.
  /// 70% smaller file size enables instant sub-second audio buffering on weak 1-2 bar cellular.
  static String _optimizeStreamUrlForNetwork(String url) =>
      _optimizeStreamUrlForNetworkImpl(url);

  static void _handlePeerReady(Map<String, dynamic> payload) =>
      _handlePeerReadyImpl(payload);

  /// User-friendly name for this local phone device
  static String get localDeviceName {
    final shortId = _clientId.length >= 4 ? _clientId.substring(0, 4).toUpperCase() : 'DEV';
    if (kIsWeb) return 'Web Browser ($shortId)';
    final os = defaultTargetPlatform.name;
    final prefix = os.isNotEmpty ? '${os[0].toUpperCase()}${os.substring(1)}' : 'Mobile';
    return '$prefix Device ($shortId)';
  }

  /// Generates a readable 6-character party join code (30 bits of entropy)
  static String generatePartyCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final randStr = String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
    return 'SYNC-$randStr';
  }

  /// Derives a deterministic 64-character SHA-256 room token from partyCode + PIN.
  static String deriveRoomToken(String code, String pin) {
    final normalized = '${code.trim().toUpperCase()}:${pin.trim()}';
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  static bool _isValidSessionPayload(Map<String, dynamic> payload) {
    if (_sessionSecret.isEmpty) return false;
    return PartyLanAccelerator.constantTimeEquals(payload['token']?.toString(), _sessionSecret);
  }

  /// Host: Starts a new Party playback session
  static Future<String?> startParty({String? pin}) => _startPartyImpl(pin: pin);

  static bool _shouldProcessEvent(String event, Map<String, dynamic> payload) =>
      _shouldProcessEventImpl(event, payload);

  static void _cancelPendingScheduledOperations() {
    _pendingScheduledPlayTimer?.cancel();
    _pendingScheduledPlayTimer = null;
    _pendingSeekTimer?.cancel();
    _pendingSeekTimer = null;
    if (_peerReadyCompleter != null && !_peerReadyCompleter!.isCompleted) {
      _peerReadyCompleter!.complete();
    }
  }

  static void _handleNtpPong(Map<String, dynamic> payload, RealtimeChannel? channel, PeerDeviceInfo selfPeer) =>
      _handleNtpPongImpl(payload, channel, selfPeer);

  /// Joiner: Joins an active party using code and room PIN, then performs clock handshake.
  static Future<bool> joinParty(String rawCode, {String? pin}) =>
      _joinPartyImpl(rawCode, pin: pin);

  static void _startNtpHandshake(RealtimeChannel channel) => _startNtpHandshakeImpl(channel);

  /// Host: Broadcasts current playing track, reference epoch, position, and peer devices
  static void _broadcastCurrentState() => _broadcastCurrentStateImpl();

  /// Host: Notifies connected speakers when a new track starts playing via Prepare -> Ack -> Go barrier
  static Future<void> notifyHostPlay(
    Song song, {
    int positionMs = 0,
    List<Song>? queue,
    int? currentIndex,
  }) =>
      _notifyHostPlayImpl(song, positionMs: positionMs, queue: queue, currentIndex: currentIndex);

  static Future<void> notifyHostLookaheadPrepare(
    Song song, {
    List<Song>? queue,
    int? currentIndex,
  }) =>
      _notifyHostLookaheadPrepareImpl(song, queue: queue, currentIndex: currentIndex);

  static Future<void> _handleRemotePrepareNext(Map<String, dynamic> payload) =>
      _handleRemotePrepareNextImpl(payload);

  /// Host: Notifies connected speakers when active track transitions automatically or via skip
  static Future<void> notifyHostTrackTransition(
    Song song, {
    List<Song>? queue,
    int? currentIndex,
  }) async {
    if (!isHost) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastAnnouncedSongId == song.id && (now - _lastAnnouncedTimeMs) < 1500) {
      return; // Deduplicate: already announced by notifyHostPlay or rapid transition
    }
    await notifyHostPlay(song, positionMs: 0, queue: queue, currentIndex: currentIndex);
  }

  /// Host: Coordinated skip/next transition across all party speakers with adaptive presentation barrier.
  static Future<void> hostTransitionToNext(
    Song nextSong, {
    List<Song>? queue,
    int? currentIndex,
  }) =>
      _hostTransitionToNextImpl(nextSong, queue: queue, currentIndex: currentIndex);

  /// Host: Notifies connected speakers when playback queue is updated or modified
  static void notifyHostQueueUpdated(List<Song> queue, int currentIndex) =>
      _notifyHostQueueUpdatedImpl(queue, currentIndex);

  /// Host: Notifies connected speakers when playback pauses
  static Future<void> notifyHostPause() => _notifyHostPauseImpl();

  /// Host: Notifies connected speakers when user seeks
  static Future<void> notifyHostSeek(Duration position) => _notifyHostSeekImpl(position);

  /// Host: Notifies connected speakers when playback resumes
  static Future<void> notifyHostResume() => _notifyHostResumeImpl();

  /// Host: Scheduled Play trigger with synchronized barrier start across all devices
  static Future<void> hostPlaySong(Song song, {int positionMs = 0}) async {
    if (!isHost) {
      await audioHandler.playSong(song);
      return;
    }
    await audioHandler.playSong(
      song,
      preserveUserQueue: false,
      autoPlay: false,
      isPartySyncInternal: true,
    );
    await notifyHostPlay(song, positionMs: positionMs);
  }

  /// Host: Seek trigger
  static Future<void> hostSeek(Duration position) async {
    await notifyHostSeek(position);
    await audioHandler.seek(position, isPartyDriven: true);
  }

  /// Host: Pause trigger
  static Future<void> hostPause() async {
    await notifyHostPause();
    await audioHandler.pause(isPartyDriven: true);
  }

  /// Joiner: Handles remote track preparation from host (pre-buffers audio stream before Go)
  /// Checks if the peer already has a verified downloaded copy of [song] on disk
  /// (by exact ID or canonicalBaseKey) so PartySync can play offline without re-downloading.
  static Song? resolveLocalDownloadedCopy(
    Song song, {
    String? Function(String songId)? pathLookup,
    String? Function(String songId)? coverLookup,
    List<Song> Function()? downloadedListLookup,
  }) {
    final getPath = pathLookup ?? DownloadManager.getLocalFilePath;
    final getCover = coverLookup ?? DownloadManager.getLocalCoverPath;
    final getAll = downloadedListLookup ?? DownloadManager.getDownloadedSongs;

    final directPath = getPath(song.id);
    if (directPath != null && File(directPath).existsSync()) {
      return song.copyWith(
        localFilePath: directPath,
        localCoverPath: getCover(song.id) ?? song.localCoverPath,
        isDownloaded: true,
        source: 'offline',
      );
    }

    final targetKey = song.canonicalBaseKey;
    if (targetKey.isNotEmpty) {
      for (final downloaded in getAll()) {
        if (downloaded.canonicalBaseKey == targetKey) {
          final matchedPath = downloaded.localFilePath ?? getPath(downloaded.id);
          if (matchedPath != null && File(matchedPath).existsSync()) {
            return song.copyWith(
              localFilePath: matchedPath,
              localCoverPath: getCover(downloaded.id) ?? downloaded.localCoverPath ?? song.localCoverPath,
              isDownloaded: true,
              source: 'offline',
            );
          }
        }
      }
    }
    return null;
  }

  static Future<void> _handleRemotePrepare(Map<String, dynamic> payload) =>
      _handleRemotePrepareImpl(payload);

  static Future<void> _handleRemotePlay(Map<String, dynamic> payload) =>
      _handleRemotePlayImpl(payload);

  static void _handleRemotePause(Map<String, dynamic> payload) =>
      _handleRemotePauseImpl(payload);

  static Future<void> _handleRemoteSeek(Map<String, dynamic> payload) =>
      _handleRemoteSeekImpl(payload);

  /// Joiner: Mirrors host queue in local AudioQueueHandler for gapless consecutive song transitions
  static Future<void> _handleRemoteQueue(Map<String, dynamic> payload) async {
    if (role != PartyRole.joiner) return;
    try {
      final rawQueue = payload['queue'] as List<dynamic>?;
      if (rawQueue == null || rawQueue.isEmpty) return;

      final hostIndex = (payload['currentIndex'] as num?)?.toInt() ?? 0;
      final isPlaying = payload['isPlaying'] == true;

      final songs = rawQueue.map((item) => Song.fromMap(Map<String, dynamic>.from(item as Map))).toList();

      final currentQueue = audioHandler.playlist;
      bool isMatch = currentQueue.length == songs.length;
      if (isMatch) {
        for (int i = 0; i < songs.length; i++) {
          if (currentQueue[i].id != songs[i].id) {
            isMatch = false;
            break;
          }
        }
      }

      if (!isMatch) {
        AppLogger.log('PartySyncCoordinator', 'Mirroring host queue (${songs.length} songs, active index: $hostIndex)');
        final currentSong = audioHandler.currentSong;
        final targetIndex = hostIndex.clamp(0, songs.length - 1);
        final targetSong = songs[targetIndex];

        if (currentSong?.id == targetSong.id) {
          await audioHandler.queueHandler.updateContextQueuePreservingCurrent(
            songs,
            currentIndex: targetIndex,
          );
        } else if (isPlaying) {
          await audioHandler.playSong(
            targetSong,
            queue: songs,
            preserveUserQueue: false,
            autoPlay: false,
            isPartySyncInternal: true,
          );
        }
        _prewarmUpcomingTracks(rawQueue, currentIndex: targetIndex);
      }
    } catch (e) {
      debugPrint('[PartySyncCoordinator] handleRemoteQueue error: $e');
    }
  }

  /// Pre-resolves audio stream URLs for upcoming tracks to eliminate track skip latency
  static void _prewarmUpcomingTracks(List<dynamic>? rawQueue, {int currentIndex = 0}) {
    if (rawQueue == null || rawQueue.isEmpty) return;
    try {
      final upcoming = rawQueue
          .skip(currentIndex + 1)
          .take(3)
          .whereType<Map>()
          .map((m) => Song.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      if (upcoming.isNotEmpty) {
        DefaultStreamResolver.prewarmSongs(upcoming);
      }
    } catch (e) {
      AppLogger.debug('PartySyncCoordinator', 'Handled exception: $e');
    }
  }

  /// Joiner: Analyzes drift on heartbeat and performs micro-rate adjustments or hard-seek
  static void _handleHeartbeatReconciliation(Map<String, dynamic> payload) async {
    if (role != PartyRole.joiner) return;

    // Direct LAN host address registration if advertised
    final hostLanIps = (payload['lanIps'] as List<dynamic>?)?.map((e) => e.toString()).toList();
    final hostPort = (payload['lanPort'] as num?)?.toInt() ?? PartyLanAccelerator.defaultPort;
    if (hostLanIps != null && hostLanIps.isNotEmpty) {
      for (final ip in hostLanIps) {
        PartyLanAccelerator.registerHostAddress(ip, hostPort);
      }
    }

    // 1. Sync peer devices list from host broadcast & prune ghosts
    final rawPeers = payload['peers'] as List<dynamic>?;
    if (rawPeers != null) {
      final validIds = <String>{};
      for (final p in rawPeers) {
        if (p is Map) {
          final pMap = Map<String, dynamic>.from(p);
          final id = pMap['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            final isSelf = id == _clientId;
            _knownPeers[id] = PeerDeviceInfo.fromMap(pMap, isSelf: isSelf);
            validIds.add(id);
          }
        }
      }
      _knownPeers.removeWhere((id, _) => !validIds.contains(id) && id != _clientId);
      connectedPeersNotifier.value = _knownPeers.values.toList();
      peerCountNotifier.value = _knownPeers.length;
    } else {
      final hostPeerCount = (payload['peerCount'] as num?)?.toInt();
      if (hostPeerCount != null && hostPeerCount > 0) {
        peerCountNotifier.value = hostPeerCount;
      }
    }

    final isHostPlaying = payload['isPlaying'] == true;
    final hostSongId = payload['songId']?.toString();
    final hostSongData = payload['song'] as Map<dynamic, dynamic>?;
    final currentSong = audioHandler.currentSong;

    // 2. CHECK IF JOINER NEEDS TO LOAD THE HOST'S SONG!
    if (hostSongId != null && hostSongId.isNotEmpty) {
      if (currentSong == null || currentSong.id != hostSongId) {
        if (!_isSyncLoading && hostSongData != null) {
          _isSyncLoading = true;
          final title = payload['title']?.toString() ?? 'host track';
          syncStatusDescription.value = 'Syncing track: $title';
          try {
            var song = Song.fromMap(Map<String, dynamic>.from(hostSongData));
            final localCopy = resolveLocalDownloadedCopy(song);
            if (localCopy != null) {
              song = localCopy;
            } else {
              final rawStreamUrl = payload['streamUrl']?.toString() ??
                  hostSongData['streamUrl']?.toString();
              final directStreamUrl = rawStreamUrl != null ? _optimizeStreamUrlForNetwork(rawStreamUrl) : null;
              if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
                song.streamUrl = directStreamUrl;
                DefaultStreamResolver.cacheStream(song.id, directStreamUrl);
              }
            }
            final rawQueue = payload['queue'] as List<dynamic>?;
            List<Song>? queue;
            if (rawQueue != null && rawQueue.isNotEmpty) {
              queue = rawQueue.map((item) => Song.fromMap(Map<String, dynamic>.from(item as Map))).toList();
            }
            await audioHandler.playSong(
              song,
              queue: queue ?? [song],
              preserveUserQueue: false,
              isPartySyncInternal: true,
              autoPlay: false,
            );
            final refHostEpoch = (payload['referenceHostEpochMs'] as num?)?.toInt();
            final refHostPos = (payload['referencePositionMs'] as num?)?.toInt();
            if (refHostEpoch != null && refHostPos != null) {
              final expectedPos = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
                referenceHostEpochMs: refHostEpoch,
                referenceTrackPositionMs: refHostPos,
                currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
                clockOffsetMs: clockOffsetMs,
                bluetoothDelayMs: _effectiveBluetoothDelayMs,
                hardwareLatencyMs: SettingsManager.hardwareAudioLatencyMs,
                isPlaying: isHostPlaying,
              );
              if (expectedPos > 0) {
                await audioHandler.seek(Duration(milliseconds: expectedPos), isPartyDriven: true);
              }
            }
            if (!isHostPlaying) {
              await audioHandler.pause(isPartyDriven: true);
            } else {
              audioHandler.play().catchError((_) => null);
            }
          } catch (e) {
            AppLogger.log('PartySyncCoordinator', 'Heartbeat auto-load track notice: $e');
          } finally {
            _isSyncLoading = false;
          }
        }
        return; // Skip drift reconciliation until track is ready
      }
    }

    if (_isSyncLoading || _pendingScheduledPlayTimer != null) return;

    final isPlaying = audioHandler.playbackState.value.playing;

    if (!isHostPlaying) {
      if (isPlaying) {
        audioHandler.pause(isPartyDriven: true);
      }
      syncStatusDescription.value = 'Host Paused';
      return;
    } else if (!isPlaying && currentSong != null && currentSong.id == hostSongId) {
      audioHandler.play().catchError((_) => null);
    }

    final refHostEpoch = (payload['referenceHostEpochMs'] as num?)?.toInt();
    final refHostPos = (payload['referencePositionMs'] as num?)?.toInt();
    if (refHostEpoch == null || refHostPos == null) return;

    final expectedPos = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
      referenceHostEpochMs: refHostEpoch,
      referenceTrackPositionMs: refHostPos,
      currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
      clockOffsetMs: clockOffsetMs,
      bluetoothDelayMs: _effectiveBluetoothDelayMs,
      hardwareLatencyMs: SettingsManager.hardwareAudioLatencyMs,
      isPlaying: isHostPlaying,
    );

    // Read real player output position directly from audio engine
    final currentPos = audioHandler.player.position.inMilliseconds;
    final drift = currentPos - expectedPos;
    currentDriftMsNotifier.value = drift;

    final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
    final rtt = measuredRttMsNotifier.value;
    final deadband = DriftReconciler.calculateAdaptiveDeadband(rttMs: rtt, isLan: isLan);
    final microMax = DriftReconciler.calculateAdaptiveMicroAdjustMax(rttMs: rtt, isLan: isLan);

    final action = DriftReconciler.reconcileDrift(
      currentPositionMs: currentPos,
      expectedPositionMs: expectedPos,
      deadbandMs: deadband,
      microAdjustMaxMs: microMax,
      wasInSync: syncStatusDescription.value.startsWith('In Sync'),
    );

    if (action.isHardSeek && action.seekTargetMs != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastHardSeekEpochMs < 8000) {
        // Anti-thrashing cooldown: do not hard seek repeatedly within 8 seconds!
        final speed = action.driftMs > 0 ? 0.96 : 1.04;
        audioHandler.setSpeed(speed);
        syncStatusDescription.value = 'Stabilizing buffer (${speed}x)';
        return;
      }
      _lastHardSeekEpochMs = nowMs;

      debugPrint('[PartySyncCoordinator] Macro-drift hard seek of ${drift}ms to ${action.seekTargetMs}ms');
      final priorVolume = audioHandler.player.volume;
      // Macro-drift: Mute audio output, execute hard seek, un-mute, and resume
      audioHandler.player.setVolume(0.0).then((_) async {
        try {
          await audioHandler.seek(Duration(milliseconds: action.seekTargetMs!), isPartyDriven: true);
          audioHandler.setSpeed(1.0);
          syncStatusDescription.value = 'In Sync';
        } finally {
          await audioHandler.player.setVolume(priorVolume);
        }
      });
    } else if (action.isMicroAdjusting) {
      audioHandler.setSpeed(action.playbackSpeed);
      final pct = ((action.playbackSpeed - 1.0) * 100).toStringAsFixed(1);
      syncStatusDescription.value = action.playbackSpeed > 1.0 ? 'Catching up (+$pct%)' : 'Slowing down ($pct%)';
    } else {
      audioHandler.setSpeed(1.0);
      syncStatusDescription.value = 'In Sync (|drift| < ${deadband}ms)';
    }
  }

  /// Leaves or terminates the party session
  static Future<void> leaveParty() => _leavePartyImpl();
}
