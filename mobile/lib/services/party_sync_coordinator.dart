import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../logic/party_sync_engine.dart';
import '../models/song.dart';
import 'player_handler.dart';
import 'settings_manager.dart';
import 'supabase_service.dart';
import 'app_logger.dart';

enum PartyRole { none, host, joiner }

/// Coordinates multi-phone synchronized playback ("Party Mode").
///
/// Implements:
/// - NTP-style 4-timestamp handshake to measure clock skew and RTT.
/// - Scheduled epoch start times (now + 500ms) for simultaneous playback.
/// Coordinates multi-phone synchronized playback ("Party Mode").
///
/// Implements:
/// - NTP-style 4-timestamp handshake to measure clock skew and RTT.
/// - Scheduled epoch start times (now + 500ms) for simultaneous playback.
/// - Continuous background drift monitoring with soft pitch-preserved speed adjustments (0.98x / 1.02x)
///   to eliminate audible glitches, falling back to hard-seeks for large desync (>200ms).
/// - Manual hardware Bluetooth DAC delay adjustment (-500ms to +500ms).
/// - Real-time peer device presence, device naming, ping metrics, and automatic song loading on joiners.
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

class PartySyncCoordinator {
  static final Random _random = Random.secure();
  static const Uuid _uuid = Uuid();

  static final ValueNotifier<PartyRole> roleNotifier = ValueNotifier<PartyRole>(PartyRole.none);
  static final ValueNotifier<String?> partyCodeNotifier = ValueNotifier<String?>(null);
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
  static int get clockOffsetMs => clockOffsetMsNotifier.value;
  static bool get isHost => role == PartyRole.host;
  static bool get isJoiner => role == PartyRole.joiner;
  static bool get isActive => role != PartyRole.none;

  static RealtimeChannel? _partyChannel;
  static Timer? _hostHeartbeatTimer;
  static Timer? _ntpHandshakeTimer;
  static final String _clientId = _uuid.v4();
  static final List<NtpSample> _ntpSamples = [];

  /// User-friendly name for this local phone device
  static String get localDeviceName {
    final shortId = _clientId.length >= 4 ? _clientId.substring(0, 4).toUpperCase() : 'DEV';
    if (kIsWeb) return 'Web Browser ($shortId)';
    final os = defaultTargetPlatform.name;
    final prefix = os.isNotEmpty ? '${os[0].toUpperCase()}${os.substring(1)}' : 'Mobile';
    return '$prefix Device ($shortId)';
  }

  /// Generates a readable 6-character party join code
  static String generatePartyCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final randStr = String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
    return 'SYNC-$randStr';
  }

  /// Host: Starts a new Party playback session
  static Future<String?> startParty() async {
    final client = SupabaseService.client;
    if (client == null) {
      syncStatusDescription.value = 'Cloud offline';
      return null;
    }

    await leaveParty();

    final code = generatePartyCode();
    partyCodeNotifier.value = code;
    roleNotifier.value = PartyRole.host;
    clockOffsetMsNotifier.value = 0;
    currentDriftMsNotifier.value = 0;

    final selfPeer = PeerDeviceInfo(
      id: _clientId,
      deviceName: '$localDeviceName (Host)',
      role: 'Host',
      rttMs: 0,
      lastSeen: DateTime.now(),
      isSelf: true,
    );
    _knownPeers.clear();
    _knownPeers[_clientId] = selfPeer;
    connectedPeersNotifier.value = [selfPeer];
    peerCountNotifier.value = 1;
    syncStatusDescription.value = 'Hosting Party ($code)';

    final channel = client.channel('party:$code');

    // Host listens for NTP pings and peer heartbeats
    channel.onBroadcast(
      event: 'ntp_ping',
      callback: (payload) {
        final t1 = DateTime.now().millisecondsSinceEpoch;
        final t0 = payload['t0'] as int?;
        final senderId = payload['senderId']?.toString();
        if (t0 != null && senderId != null) {
          final t2 = DateTime.now().millisecondsSinceEpoch;
          channel.sendBroadcastMessage(
            event: 'ntp_pong',
            payload: {
              't0': t0,
              't1': t1,
              't2': t2,
              'recipientId': senderId,
            },
          );
        }
      },
    );

    channel.onBroadcast(
      event: 'peer_join',
      callback: (payload) {
        final peerId = payload['peerId']?.toString();
        final devName = payload['deviceName']?.toString() ?? 'Guest Phone';
        if (peerId != null) {
          _knownPeers[peerId] = PeerDeviceInfo(
            id: peerId,
            deviceName: devName,
            role: 'Speaker',
            rttMs: 0,
            lastSeen: DateTime.now(),
          );
          connectedPeersNotifier.value = _knownPeers.values.toList();
          peerCountNotifier.value = _knownPeers.length;
        }
        // Send immediate current playback state & peer list to new joiner
        _broadcastCurrentState();
      },
    );

    channel.onBroadcast(
      event: 'peer_presence',
      callback: (payload) {
        final peerId = payload['id']?.toString();
        final devName = payload['deviceName']?.toString() ?? 'Guest Phone';
        final rtt = (payload['rttMs'] as num?)?.toInt() ?? 0;
        if (peerId != null && peerId != _clientId) {
          _knownPeers[peerId] = PeerDeviceInfo(
            id: peerId,
            deviceName: devName,
            role: 'Speaker',
            rttMs: rtt,
            lastSeen: DateTime.now(),
          );
          connectedPeersNotifier.value = _knownPeers.values.toList();
          peerCountNotifier.value = _knownPeers.length;
        }
      },
    );

    channel.onBroadcast(
      event: 'peer_leave',
      callback: (payload) {
        final peerId = payload['id']?.toString();
        if (peerId != null) {
          _knownPeers.remove(peerId);
          connectedPeersNotifier.value = _knownPeers.values.toList();
          peerCountNotifier.value = _knownPeers.length;
          _broadcastCurrentState();
        }
      },
    );

    channel.subscribe((status, [error]) {
      debugPrint('[PartySyncCoordinator] Host channel status: $status');
    });

    _partyChannel = channel;

    // Start periodic 2-second heartbeat broadcast
    _hostHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _broadcastCurrentState();
    });

    return code;
  }

  /// Joiner: Joins an active party using code and performs clock handshake
  static Future<bool> joinParty(String rawCode) async {
    final cleanCode = rawCode.trim().toUpperCase();
    if (cleanCode.isEmpty) return false;

    final client = SupabaseService.client;
    if (client == null) {
      syncStatusDescription.value = 'Cloud offline';
      return false;
    }

    await leaveParty();

    partyCodeNotifier.value = cleanCode;
    roleNotifier.value = PartyRole.joiner;
    syncStatusDescription.value = 'Synchronizing clocks...';

    final selfPeer = PeerDeviceInfo(
      id: _clientId,
      deviceName: '$localDeviceName (This Phone)',
      role: 'Speaker',
      rttMs: 0,
      lastSeen: DateTime.now(),
      isSelf: true,
    );
    _knownPeers.clear();
    _knownPeers[_clientId] = selfPeer;
    connectedPeersNotifier.value = [selfPeer];
    peerCountNotifier.value = 1;

    final channel = client.channel('party:$cleanCode');

    channel.onBroadcast(
      event: 'ntp_pong',
      callback: (payload) {
        final recipientId = payload['recipientId']?.toString();
        if (recipientId == _clientId) {
          final t3 = DateTime.now().millisecondsSinceEpoch;
          final t0 = payload['t0'] as int?;
          final t1 = payload['t1'] as int?;
          final t2 = payload['t2'] as int?;
          if (t0 != null && t1 != null && t2 != null) {
            final sample = NtpSample(t0: t0, t1: t1, t2: t2, t3: t3);
            _ntpSamples.add(sample);
            measuredRttMsNotifier.value = sample.rtt;
            final offset = NtpCalculator.calculateOffset(_ntpSamples);
            clockOffsetMsNotifier.value = offset;
            syncStatusDescription.value = 'In Sync (RTT: ${sample.rtt}ms, Offset: ${offset}ms)';

            // Update self peer RTT in local state and notify channel
            _knownPeers[_clientId] = selfPeer.copyWith(rttMs: sample.rtt);
            connectedPeersNotifier.value = _knownPeers.values.toList();
            channel.sendBroadcastMessage(
              event: 'peer_presence',
              payload: {
                'id': _clientId,
                'deviceName': localDeviceName,
                'role': 'Speaker',
                'rttMs': sample.rtt,
              },
            );
          }
        }
      },
    );

    channel.onBroadcast(
      event: 'sync_play',
      callback: (payload) async {
        await _handleRemotePlay(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_pause',
      callback: (payload) {
        audioHandler.pause();
        syncStatusDescription.value = 'Host Paused';
      },
    );

    channel.onBroadcast(
      event: 'sync_seek',
      callback: (payload) async {
        final posMs = payload['positionMs'] as int? ?? 0;
        final startAtEpochMs = payload['startAtEpochMs'] as int?;
        if (startAtEpochMs != null) {
          final delayMs = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
            startAtEpochMs: startAtEpochMs,
            currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
            clockOffsetMs: clockOffsetMs,
          );
          if (delayMs > 0) {
            await audioHandler.pause();
            await audioHandler.seek(Duration(milliseconds: posMs));
            await Future.delayed(Duration(milliseconds: delayMs));
            await audioHandler.play();
          } else {
            await audioHandler.seek(Duration(milliseconds: posMs));
          }
        } else {
          await audioHandler.seek(Duration(milliseconds: posMs));
        }
      },
    );

    channel.onBroadcast(
      event: 'sync_heartbeat',
      callback: (payload) {
        _handleHeartbeatReconciliation(payload);
      },
    );

    channel.onBroadcast(
      event: 'party_ended',
      callback: (_) {
        leaveParty();
        syncStatusDescription.value = 'Host ended party session';
      },
    );

    channel.subscribe((status, [error]) {
      debugPrint('[PartySyncCoordinator] Joiner channel status: $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Announce join to host with device details
        channel.sendBroadcastMessage(
          event: 'peer_join',
          payload: {
            'peerId': _clientId,
            'deviceName': localDeviceName,
          },
        );
        // Start 8-packet NTP handshake
        _executeNtpHandshake();
      }
    });

    _partyChannel = channel;
    return true;
  }

  /// Runs 8 consecutive NTP pings spaced by 150ms
  static void _executeNtpHandshake() {
    _ntpSamples.clear();
    int pingsSent = 0;

    _ntpHandshakeTimer?.cancel();
    _ntpHandshakeTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (_partyChannel == null || role != PartyRole.joiner) {
        timer.cancel();
        return;
      }

      final t0 = DateTime.now().millisecondsSinceEpoch;
      _partyChannel?.sendBroadcastMessage(
        event: 'ntp_ping',
        payload: {
          't0': t0,
          'senderId': _clientId,
        },
      );

      pingsSent++;
      if (pingsSent >= 8) {
        timer.cancel();
      }
    });
  }

  /// Host: Broadcasts current playing track, reference epoch, position, and peer devices
  static void _broadcastCurrentState() {
    final mediaItem = audioHandler.mediaItem.value;
    final playbackState = audioHandler.playbackState.value;
    final currentPosMs = playbackState.position.inMilliseconds;
    final isPlaying = playbackState.playing;
    final curSong = audioHandler.currentSong;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_heartbeat',
      payload: {
        'songId': mediaItem?.id ?? curSong?.id,
        'title': mediaItem?.title ?? curSong?.title,
        'artist': mediaItem?.artist ?? curSong?.artist,
        'artworkUrl': mediaItem?.artUri?.toString() ?? curSong?.coverUrl,
        'song': curSong?.toMap(),
        'referenceHostEpochMs': DateTime.now().millisecondsSinceEpoch,
        'referencePositionMs': currentPosMs,
        'isPlaying': isPlaying,
        'peerCount': _knownPeers.length,
        'peers': _knownPeers.values.map((p) => p.toMap()).toList(),
      },
    );
  }

  /// Host: Notifies connected speakers when a new track starts playing
  static Future<void> notifyHostPlay(Song song, {int positionMs = 0}) async {
    if (!isHost) return;
    const leadTimeMs = 400;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: {
        'song': song.toMap(),
        'songId': song.id,
        'positionMs': positionMs,
        'startAtEpochMs': startAtEpochMs,
      },
    );
  }

  /// Host: Notifies connected speakers when playback pauses
  static Future<void> notifyHostPause() async {
    if (!isHost) return;
    final pos = audioHandler.playbackState.value.position.inMilliseconds;
    _partyChannel?.sendBroadcastMessage(
      event: 'sync_pause',
      payload: {'positionMs': pos},
    );
  }

  /// Host: Notifies connected speakers when user seeks
  static Future<void> notifyHostSeek(Duration position) async {
    if (!isHost) return;
    const leadTimeMs = 250;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_seek',
      payload: {
        'positionMs': position.inMilliseconds,
        'startAtEpochMs': startAtEpochMs,
      },
    );
  }

  /// Host: Notifies connected speakers when playback resumes
  static Future<void> notifyHostResume() async {
    if (!isHost) return;
    final pos = audioHandler.playbackState.value.position.inMilliseconds;
    const leadTimeMs = 300;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;
    final curSong = audioHandler.currentSong;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: {
        'song': curSong?.toMap(),
        'songId': curSong?.id,
        'positionMs': pos,
        'startAtEpochMs': startAtEpochMs,
      },
    );
  }

  /// Host: Scheduled Play trigger (broadcasting start at now + 2000ms future epoch)
  static Future<void> hostPlaySong(Song song, {int positionMs = 0}) async {
    if (!isHost) {
      await audioHandler.playSong(song);
      return;
    }

    const leadTimeMs = 2000;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: {
        'song': song.toMap(),
        'songId': song.id,
        'positionMs': positionMs,
        'startAtEpochMs': startAtEpochMs,
      },
    );

    // Host prepares song and starts at exact scheduled epoch
    await audioHandler.playSong(song);
    if (positionMs > 0) {
      await audioHandler.seek(Duration(milliseconds: positionMs));
    }
  }

  /// Host: Scheduled Seek trigger
  static Future<void> hostSeek(Duration position) async {
    if (!isHost) {
      await audioHandler.seek(position);
      return;
    }

    const leadTimeMs = 300;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_seek',
      payload: {
        'positionMs': position.inMilliseconds,
        'startAtEpochMs': startAtEpochMs,
      },
    );

    await audioHandler.seek(position);
  }

  /// Host: Pause trigger
  static Future<void> hostPause() async {
    if (isHost) {
      final pos = audioHandler.playbackState.value.position.inMilliseconds;
      _partyChannel?.sendBroadcastMessage(
        event: 'sync_pause',
        payload: {'positionMs': pos},
      );
    }
    await audioHandler.pause();
  }

  /// Joiner: Handles remote scheduled play from host
  static Future<void> _handleRemotePlay(Map<String, dynamic> payload) async {
    try {
      final songData = payload['song'] as Map<dynamic, dynamic>?;
      if (songData == null) return;

      final song = Song.fromMap(songData);
      final positionMs = payload['positionMs'] as int? ?? 0;
      final startAtEpochMs = payload['startAtEpochMs'] as int? ?? 0;

      syncStatusDescription.value = 'Syncing "${song.title}"...';

      // Load media and position
      await audioHandler.playSong(song, queue: [song]);
      if (positionMs > 0) {
        await audioHandler.seek(Duration(milliseconds: positionMs));
      } else {
        await audioHandler.seek(Duration.zero);
      }

      final delayMs = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: startAtEpochMs,
        currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
        clockOffsetMs: clockOffsetMs,
      );

      if (delayMs > 0 && delayMs < 5000) {
        await audioHandler.pause();
        await Future.delayed(Duration(milliseconds: delayMs));
        await audioHandler.play();
      }
    } catch (e) {
      debugPrint('[PartySyncCoordinator] handleRemotePlay error: $e');
    }
  }

  /// Joiner: Analyzes drift on heartbeat and performs micro-rate adjustments or hard-seek
  static void _handleHeartbeatReconciliation(Map<String, dynamic> payload) async {
    if (role != PartyRole.joiner) return;

    // 1. Sync peer devices list from host broadcast
    final rawPeers = payload['peers'] as List<dynamic>?;
    if (rawPeers != null) {
      for (final p in rawPeers) {
        if (p is Map) {
          final pMap = Map<String, dynamic>.from(p);
          final id = pMap['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            final isSelf = id == _clientId;
            _knownPeers[id] = PeerDeviceInfo.fromMap(pMap, isSelf: isSelf);
          }
        }
      }
      connectedPeersNotifier.value = _knownPeers.values.toList();
      peerCountNotifier.value = _knownPeers.length;
    } else {
      final hostPeerCount = payload['peerCount'] as int?;
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
            final song = Song.fromMap(hostSongData);
            await audioHandler.playSong(song, queue: [song]);
            final refHostEpoch = payload['referenceHostEpochMs'] as int?;
            final refHostPos = payload['referencePositionMs'] as int?;
            if (refHostEpoch != null && refHostPos != null) {
              final expectedPos = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
                referenceHostEpochMs: refHostEpoch,
                referenceTrackPositionMs: refHostPos,
                currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
                clockOffsetMs: clockOffsetMs,
                bluetoothDelayMs: SettingsManager.bluetoothDelayMs,
                hardwareLatencyMs: SettingsManager.hardwareAudioLatencyMs,
                isPlaying: isHostPlaying,
              );
              if (expectedPos > 0) {
                await audioHandler.seek(Duration(milliseconds: expectedPos));
              }
            }
            if (!isHostPlaying) {
              await audioHandler.pause();
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

    if (_isSyncLoading) return;

    final playbackState = audioHandler.playbackState.value;

    if (!isHostPlaying) {
      if (playbackState.playing) {
        audioHandler.pause();
      }
      syncStatusDescription.value = 'Host Paused';
      return;
    } else if (!playbackState.playing && currentSong != null && currentSong.id == hostSongId) {
      // Host is playing and track is loaded, resume joiner audio
      audioHandler.play();
    }

    final refHostEpoch = payload['referenceHostEpochMs'] as int?;
    final refHostPos = payload['referencePositionMs'] as int?;
    if (refHostEpoch == null || refHostPos == null) return;

    final expectedPos = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
      referenceHostEpochMs: refHostEpoch,
      referenceTrackPositionMs: refHostPos,
      currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
      clockOffsetMs: clockOffsetMs,
      bluetoothDelayMs: SettingsManager.bluetoothDelayMs,
      hardwareLatencyMs: SettingsManager.hardwareAudioLatencyMs,
      isPlaying: isHostPlaying,
    );

    final currentPos = playbackState.position.inMilliseconds;
    final drift = currentPos - expectedPos;
    currentDriftMsNotifier.value = drift;

    final action = DriftReconciler.reconcileDrift(
      currentPositionMs: currentPos,
      expectedPositionMs: expectedPos,
    );

    if (action.isHardSeek && action.seekTargetMs != null) {
      debugPrint('[PartySyncCoordinator] Macro-drift hard seek of ${drift}ms to ${action.seekTargetMs}ms');
      final priorVolume = audioHandler.player.volume;
      // Macro-drift (>= 250ms): Mute audio output, execute hard seek, un-mute, and resume
      audioHandler.player.setVolume(0.0).then((_) async {
        try {
          await audioHandler.seek(Duration(milliseconds: action.seekTargetMs!));
          audioHandler.setSpeed(1.0);
          syncStatusDescription.value = 'Resyncing (muted hard-seek)';
        } finally {
          await audioHandler.player.setVolume(priorVolume);
        }
      });
    } else if (action.isMicroAdjusting) {
      audioHandler.setSpeed(action.playbackSpeed);
      syncStatusDescription.value = action.playbackSpeed > 1.0 ? 'Catching up (+2%)' : 'Slowing down (-2%)';
    } else {
      audioHandler.setSpeed(1.0);
      syncStatusDescription.value = 'In Sync (|drift| < 10ms)';
    }
  }

  /// Leaves or terminates the party session
  static Future<void> leaveParty() async {
    _hostHeartbeatTimer?.cancel();
    _hostHeartbeatTimer = null;
    _ntpHandshakeTimer?.cancel();
    _ntpHandshakeTimer = null;

    if (_partyChannel != null) {
      try {
        if (isHost) {
          _partyChannel?.sendBroadcastMessage(
            event: 'party_ended',
            payload: {'hostId': _clientId},
          );
        } else {
          _partyChannel?.sendBroadcastMessage(
            event: 'peer_leave',
            payload: {'id': _clientId},
          );
        }
        SupabaseService.client?.removeChannel(_partyChannel!);
      } catch (e) {
        AppLogger.log('PartySyncCoordinator', 'Remove channel notice: $e');
      }
      _partyChannel = null;
    }

    // Reset playback speed to normal
    audioHandler.setSpeed(1.0);

    roleNotifier.value = PartyRole.none;
    partyCodeNotifier.value = null;
    clockOffsetMsNotifier.value = 0;
    measuredRttMsNotifier.value = 0;
    currentDriftMsNotifier.value = 0;
    peerCountNotifier.value = 0;
    _knownPeers.clear();
    connectedPeersNotifier.value = [];
    syncStatusDescription.value = 'Idle';
    _ntpSamples.clear();
  }
}
