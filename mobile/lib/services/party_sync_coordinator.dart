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
import 'party_lan_accelerator.dart';

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

  /// Host: Starts a new Party playback session
  static Future<String?> startParty() async {
    final client = SupabaseService.client;
    if (client == null) {
      syncStatusDescription.value = 'Cloud offline';
      return null;
    }

    await leaveParty();

    final code = generatePartyCode();
    _sessionSecret = _uuid.v4();
    _currentHostSeq = 0;
    _lastProcessedSeq = 0;

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

    // Host listens for NTP pings and peer presence
    channel.onBroadcast(
      event: 'ntp_ping',
      callback: (payload) {
        final t1 = DateTime.now().millisecondsSinceEpoch;
        final t0 = (payload['t0'] as num?)?.toInt();
        final senderId = payload['senderId']?.toString();
        final isRolling = payload['isRolling'] == true;
        if (t0 != null && senderId != null) {
          final t2 = DateTime.now().millisecondsSinceEpoch;
          channel.sendBroadcastMessage(
            event: 'ntp_pong',
            payload: {
              't0': t0,
              't1': t1,
              't2': t2,
              'recipientId': senderId,
              'isRolling': isRolling,
              'token': _sessionSecret,
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

    // Joiner requests state immediately upon connecting
    channel.onBroadcast(
      event: 'request_state',
      callback: (_) {
        _broadcastCurrentState();
      },
    );

    channel.subscribe((status, [error]) {
      debugPrint('[PartySyncCoordinator] Host channel status: $status');
      if (status == RealtimeSubscribeStatus.closed || status == RealtimeSubscribeStatus.timedOut) {
        if (isAudioHandlerInitialized) {
          try {
            audioHandler.setSpeed(1.0);
          } catch (e) {
            AppLogger.debug('PartySyncCoordinator', 'Could not reset playback speed: $e');
          }
        }
      }
    });

    _partyChannel = channel;

    // Start direct Local Wi-Fi (LAN) UDP acceleration on host
    PartyLanAccelerator.startHost(code, clientId: _clientId);

    // Start periodic 2-second heartbeat broadcast and ghost peer pruning
    _hostHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      // Prune ghost peers inactive for > 8s
      final initialCount = _knownPeers.length;
      _knownPeers.removeWhere((id, peer) => id != _clientId && now.difference(peer.lastSeen).inSeconds > 8);
      if (_knownPeers.length != initialCount) {
        connectedPeersNotifier.value = _knownPeers.values.toList();
        peerCountNotifier.value = _knownPeers.length;
      }

      _broadcastCurrentState();
    });

    return code;
  }

  static bool _shouldProcessEvent(String event, Map<String, dynamic> payload) {
    final seq = (payload['seq'] as num?)?.toInt();
    if (seq != null) {
      if (seq <= _lastProcessedSeq) {
        return false; // Stale or duplicate out-of-order event
      }
      _lastProcessedSeq = seq;
    }

    final key = '${event}_${payload['seq']}_${payload['startAtEpochMs']}_${payload['positionMs']}_${payload['songId']}';
    if (_processedEventKeys.contains(key)) return false;
    _processedEventKeys.add(key);
    if (_processedEventKeys.length > 50) {
      _processedEventKeys.remove(_processedEventKeys.first);
    }
    return true;
  }

  static void _cancelPendingScheduledOperations() {
    _pendingScheduledPlayTimer?.cancel();
    _pendingScheduledPlayTimer = null;
    _pendingSeekTimer?.cancel();
    _pendingSeekTimer = null;
  }

  static void _handleNtpPong(Map<String, dynamic> payload, RealtimeChannel? channel, PeerDeviceInfo selfPeer) {
    final recipientId = payload['recipientId']?.toString();
    if (recipientId == _clientId) {
      final t3 = DateTime.now().millisecondsSinceEpoch;
      final t0 = (payload['t0'] as num?)?.toInt();
      final t1 = (payload['t1'] as num?)?.toInt();
      final t2 = (payload['t2'] as num?)?.toInt();
      final isRolling = payload['isRolling'] == true;
      final isLan = payload['isLan'] == true || PartyLanAccelerator.isLanActiveNotifier.value;

      if (t0 != null && t1 != null && t2 != null) {
        final sample = NtpSample(t0: t0, t1: t1, t2: t2, t3: t3, isLan: isLan);

        // Maintain sliding window of the last 16 samples
        _ntpSamples.add(sample);
        while (_ntpSamples.length > 16) {
          _ntpSamples.removeAt(0);
        }

        // Outlier rejection: filters samples where RTT > 1.5x of min RTT and prioritizes LAN samples
        final offset = NtpCalculator.calculateOffset(_ntpSamples);
        clockOffsetMsNotifier.value = offset;
        measuredRttMsNotifier.value = sample.rtt;

        if (!isRolling) {
          syncStatusDescription.value = 'In Sync (RTT: ${sample.rtt}ms, Offset: ${offset}ms)';
        }

        // Update self peer RTT in local state and notify channel
        _knownPeers[_clientId] = selfPeer.copyWith(rttMs: sample.rtt);
        connectedPeersNotifier.value = _knownPeers.values.toList();
        channel?.sendBroadcastMessage(
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
  }

  /// Joiner: Joins an active party using code and performs clock handshake
  static Future<bool> joinParty(String rawCode) async {
    final client = SupabaseService.client;
    if (client == null) {
      syncStatusDescription.value = 'Cloud offline';
      return false;
    }

    final cleanCode = rawCode.trim().toUpperCase();
    if (cleanCode.isEmpty) return false;

    await leaveParty();

    partyCodeNotifier.value = cleanCode;
    roleNotifier.value = PartyRole.joiner;
    clockOffsetMsNotifier.value = 0;
    measuredRttMsNotifier.value = 0;
    currentDriftMsNotifier.value = 0;
    _lastProcessedSeq = 0;
    syncStatusDescription.value = 'Connecting to $cleanCode...';

    final selfPeer = PeerDeviceInfo(
      id: _clientId,
      deviceName: localDeviceName,
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

    // Hook direct local Wi-Fi UDP acceleration
    PartyLanAccelerator.onNtpPongReceived = (payload) {
      _handleNtpPong(payload, channel, selfPeer);
    };

    PartyLanAccelerator.onSyncEventReceived = (event, payload) async {
      if (!_shouldProcessEvent(event, payload)) return;
      switch (event) {
        case 'sync_play':
          await _handleRemotePlay(payload);
          break;
        case 'sync_pause':
          _handleRemotePause(payload);
          break;
        case 'sync_seek':
          await _handleRemoteSeek(payload);
          break;
        case 'sync_heartbeat':
          _handleHeartbeatReconciliation(payload);
          break;
        case 'sync_queue':
          await _handleRemoteQueue(payload);
          break;
      }
    };

    PartyLanAccelerator.startJoiner(cleanCode, clientId: _clientId);

    channel.onBroadcast(
      event: 'ntp_pong',
      callback: (payload) {
        _handleNtpPong(payload, channel, selfPeer);
      },
    );

    channel.onBroadcast(
      event: 'sync_queue',
      callback: (payload) async {
        if (!_shouldProcessEvent('sync_queue', payload)) return;
        await _handleRemoteQueue(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_play',
      callback: (payload) async {
        if (!_shouldProcessEvent('sync_play', payload)) return;
        await _handleRemotePlay(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_pause',
      callback: (payload) {
        if (!_shouldProcessEvent('sync_pause', payload)) return;
        _handleRemotePause(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_seek',
      callback: (payload) async {
        if (!_shouldProcessEvent('sync_seek', payload)) return;
        await _handleRemoteSeek(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_heartbeat',
      callback: (payload) {
        if (!_shouldProcessEvent('sync_heartbeat', payload)) return;
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
        channel.sendBroadcastMessage(
          event: 'peer_join',
          payload: {
            'peerId': _clientId,
            'deviceName': localDeviceName,
          },
        );
        // Request immediate state so joiner doesn't wait for next periodic heartbeat
        channel.sendBroadcastMessage(
          event: 'request_state',
          payload: {'senderId': _clientId},
        );
        PartyLanAccelerator.sendDirect('request_state', {'senderId': _clientId});

        _startNtpHandshake(channel);
      } else if (status == RealtimeSubscribeStatus.closed || status == RealtimeSubscribeStatus.timedOut) {
        if (isAudioHandlerInitialized) {
          try {
            audioHandler.setSpeed(1.0);
          } catch (e) {
            AppLogger.debug('PartySyncCoordinator', 'Could not reset playback speed: $e');
          }
        }
      }
    });

    _partyChannel = channel;
    return true;
  }

  /// Joiner: Runs initial 8-packet NTP handshake
  static void _startNtpHandshake(RealtimeChannel channel) {
    _ntpSamples.clear();
    int pingsSent = 0;

    _ntpHandshakeTimer?.cancel();
    _ntpHandshakeTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (role != PartyRole.joiner || _partyChannel == null) {
        timer.cancel();
        return;
      }

      final t0 = DateTime.now().millisecondsSinceEpoch;
      channel.sendBroadcastMessage(
        event: 'ntp_ping',
        payload: {
          't0': t0,
          'senderId': _clientId,
          'isRolling': false,
        },
      );
      PartyLanAccelerator.sendLanNtpPing(t0, _clientId);

      pingsSent++;
      if (pingsSent >= 8) {
        timer.cancel();
        _startRollingNtp(channel);
      }
    });
  }

  /// Joiner: Background rolling NTP synchronization (every 3 seconds)
  static void _startRollingNtp(RealtimeChannel channel) {
    _rollingNtpTimer?.cancel();
    int pingsSent = 0;

    _rollingNtpTimer = Timer.periodic(const Duration(milliseconds: 3000), (timer) {
      if (role != PartyRole.joiner || _partyChannel == null) {
        timer.cancel();
        return;
      }

      final t0 = DateTime.now().millisecondsSinceEpoch;
      final bool sendCloud = (pingsSent % 2 == 0) || !PartyLanAccelerator.isLanActiveNotifier.value;
      if (sendCloud) {
        channel.sendBroadcastMessage(
          event: 'ntp_ping',
          payload: {
            't0': t0,
            'senderId': _clientId,
            'isRolling': true,
          },
        );
      }
      PartyLanAccelerator.sendLanNtpPing(t0, _clientId, isRolling: true);
      pingsSent++;
    });
  }

  /// Host: Broadcasts current playing track, reference epoch, position, and peer devices
  static void _broadcastCurrentState() {
    if (!isHost || _partyChannel == null) return;
    final pos = audioHandler.playbackState.value.position.inMilliseconds;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isPlaying = audioHandler.playbackState.value.playing;
    final currentSong = audioHandler.currentSong;

    final seq = ++_currentHostSeq;
    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'isPlaying': isPlaying,
      'songId': currentSong?.id,
      'song': currentSong?.toMap(),
      'referenceHostEpochMs': now,
      'referencePositionMs': pos,
      'peers': _knownPeers.values.map((p) => p.toMap()).toList(),
      'peerCount': _knownPeers.length,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_heartbeat',
      payload: payload,
    );

    // Compact LAN heartbeat (without heavy song metadata or queues)
    PartyLanAccelerator.sendSyncEvent('sync_heartbeat', {
      'seq': seq,
      'token': _sessionSecret,
      'isPlaying': isPlaying,
      'songId': currentSong?.id,
      'referenceHostEpochMs': now,
      'referencePositionMs': pos,
      'peerCount': _knownPeers.length,
    });
  }

  /// Host: Notifies connected speakers when a new track starts playing
  static Future<void> notifyHostPlay(
    Song song, {
    int positionMs = 0,
    List<Song>? queue,
    int? currentIndex,
  }) async {
    if (!isHost || _partyChannel == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final seq = ++_currentHostSeq;

    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'song': song.toMap(),
      'songId': song.id,
      'positionMs': positionMs,
      'referenceHostEpochMs': now,
      'referencePositionMs': positionMs,
      'startAtEpochMs': now,
      'currentIndex': currentIndex ?? 0,
      'isPlaying': true,
      'queue': queue?.take(30).map((s) => s.toMap()).toList(),
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: payload,
    );

    // Compact LAN sync datagram (< 400 bytes, excludes heavy queue list)
    PartyLanAccelerator.sendSyncEvent('sync_play', {
      'seq': seq,
      'token': _sessionSecret,
      'songId': song.id,
      'positionMs': positionMs,
      'referenceHostEpochMs': now,
      'referencePositionMs': positionMs,
      'startAtEpochMs': now,
      'currentIndex': currentIndex ?? 0,
      'isPlaying': true,
    });
  }

  /// Host: Notifies connected speakers when active track transitions automatically or via skip
  static Future<void> notifyHostTrackTransition(
    Song song, {
    List<Song>? queue,
    int? currentIndex,
  }) async {
    if (!isHost || _partyChannel == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final seq = ++_currentHostSeq;

    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'song': song.toMap(),
      'songId': song.id,
      'positionMs': 0,
      'referenceHostEpochMs': now,
      'referencePositionMs': 0,
      'startAtEpochMs': now,
      'currentIndex': currentIndex ?? 0,
      'isPlaying': true,
      'queue': queue?.take(30).map((s) => s.toMap()).toList(),
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: payload,
    );

    PartyLanAccelerator.sendSyncEvent('sync_play', {
      'seq': seq,
      'token': _sessionSecret,
      'songId': song.id,
      'positionMs': 0,
      'referenceHostEpochMs': now,
      'referencePositionMs': 0,
      'startAtEpochMs': now,
      'currentIndex': currentIndex ?? 0,
      'isPlaying': true,
    });
  }

  /// Host: Notifies connected speakers when playback queue is updated or modified
  static void notifyHostQueueUpdated(List<Song> queue, int currentIndex) {
    if (!isHost || _partyChannel == null) return;
    final curSong = audioHandler.currentSong;
    final isPlaying = audioHandler.playbackState.value.playing;
    final seq = ++_currentHostSeq;

    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'queue': queue.take(30).map((s) => s.toMap()).toList(),
      'currentIndex': currentIndex,
      'activeSongId': curSong?.id,
      'isPlaying': isPlaying,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_queue',
      payload: payload,
    );
  }

  /// Host: Notifies connected speakers when playback pauses
  static Future<void> notifyHostPause() async {
    if (!isHost || _partyChannel == null) return;
    final pos = audioHandler.playbackState.value.position.inMilliseconds;
    final seq = ++_currentHostSeq;
    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'positionMs': pos,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_pause',
      payload: payload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_pause', payload);
  }

  /// Host: Notifies connected speakers when user seeks
  static Future<void> notifyHostSeek(Duration position) async {
    if (!isHost || _partyChannel == null) return;
    final seq = ++_currentHostSeq;
    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'positionMs': position.inMilliseconds,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_seek',
      payload: payload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_seek', payload);
  }

  /// Host: Notifies connected speakers when playback resumes
  static Future<void> notifyHostResume() async {
    if (!isHost || _partyChannel == null) return;
    final pos = audioHandler.playbackState.value.position.inMilliseconds;
    final now = DateTime.now().millisecondsSinceEpoch;
    final curSong = audioHandler.currentSong;
    final seq = ++_currentHostSeq;

    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'song': curSong?.toMap(),
      'songId': curSong?.id,
      'positionMs': pos,
      'referenceHostEpochMs': now,
      'referencePositionMs': pos,
      'startAtEpochMs': now,
      'isPlaying': true,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: payload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_play', {
      'seq': seq,
      'token': _sessionSecret,
      'songId': curSong?.id,
      'positionMs': pos,
      'referenceHostEpochMs': now,
      'referencePositionMs': pos,
      'startAtEpochMs': now,
      'isPlaying': true,
    });
  }

  /// Host: Scheduled Play trigger with synchronized barrier start across all devices
  static Future<void> hostPlaySong(Song song, {int positionMs = 0}) async {
    if (!isHost) {
      await audioHandler.playSong(song);
      return;
    }

    const leadTimeMs = 1200;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;
    final seq = ++_currentHostSeq;

    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'song': song.toMap(),
      'songId': song.id,
      'positionMs': positionMs,
      'referenceHostEpochMs': startAtEpochMs,
      'referencePositionMs': positionMs,
      'startAtEpochMs': startAtEpochMs,
      'isPlaying': true,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: payload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_play', {
      'seq': seq,
      'token': _sessionSecret,
      'songId': song.id,
      'positionMs': positionMs,
      'referenceHostEpochMs': startAtEpochMs,
      'referencePositionMs': positionMs,
      'startAtEpochMs': startAtEpochMs,
      'isPlaying': true,
    });

    // The host itself holds playback until startAtEpochMs to guarantee lockstep
    await audioHandler.playSong(song, preserveUserQueue: false);
    await audioHandler.pause();
    if (positionMs > 0) {
      await audioHandler.seek(Duration(milliseconds: positionMs));
    }
    final remainingDelay = startAtEpochMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingDelay > 0) {
      await Future.delayed(Duration(milliseconds: remainingDelay));
    }
    await audioHandler.play();
  }

  /// Host: Seek trigger
  static Future<void> hostSeek(Duration position) async {
    await notifyHostSeek(position);
    await audioHandler.seek(position);
  }

  /// Host: Pause trigger
  static Future<void> hostPause() async {
    await notifyHostPause();
    await audioHandler.pause();
  }

  /// Joiner: Handles remote scheduled play from host
  static Future<void> _handleRemotePlay(Map<String, dynamic> payload) async {
    _cancelPendingScheduledOperations();

    try {
      final songData = payload['song'] as Map<dynamic, dynamic>?;
      final songId = payload['songId']?.toString();
      Song? song;
      if (songData != null) {
        song = Song.fromMap(Map<String, dynamic>.from(songData));
      }

      final positionMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
      final startAtEpochMs = (payload['startAtEpochMs'] as num?)?.toInt() ?? 0;
      final refHostEpoch = (payload['referenceHostEpochMs'] as num?)?.toInt() ?? startAtEpochMs;
      final refHostPos = (payload['referencePositionMs'] as num?)?.toInt() ?? positionMs;
      final isHostPlaying = payload['isPlaying'] != false;

      final currentSong = audioHandler.currentSong;
      final bool isSameSong = (song != null && currentSong?.id == song.id) ||
                              (songId != null && currentSong?.id == songId);

      if (!isSameSong && song != null) {
        final rawQueue = payload['queue'] as List<dynamic>?;
        List<Song>? queue;
        if (rawQueue != null && rawQueue.isNotEmpty) {
          queue = rawQueue.map((item) => Song.fromMap(Map<String, dynamic>.from(item as Map))).toList();
        }
        syncStatusDescription.value = 'Syncing "${song.title}"...';
        await audioHandler.playSong(
          song,
          queue: queue ?? [song],
          preserveUserQueue: false,
        );
      }

      final nowLocal = DateTime.now().millisecondsSinceEpoch;
      final estimatedHostTimeMs = nowLocal + clockOffsetMs;
      final delayMs = startAtEpochMs - estimatedHostTimeMs;

      if (delayMs > 25) {
        // Scheduled barrier is genuinely in the future: pre-position and hold
        if (positionMs > 0) {
          await audioHandler.seek(Duration(milliseconds: positionMs));
        } else {
          await audioHandler.seek(Duration.zero);
        }
        await audioHandler.pause();

        // Cancellable delayed play
        _pendingScheduledPlayTimer = Timer(Duration(milliseconds: delayMs), () async {
          if (role != PartyRole.joiner) return;
          await audioHandler.play();
          syncStatusDescription.value = 'In Sync';
        });
      } else {
        // Immediate start anchored to referenceHostEpochMs and referencePositionMs:
        final targetPosMs = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
          referenceHostEpochMs: refHostEpoch,
          referenceTrackPositionMs: refHostPos,
          currentLocalEpochMs: nowLocal,
          clockOffsetMs: clockOffsetMs,
          bluetoothDelayMs: SettingsManager.bluetoothDelayMs,
          hardwareLatencyMs: SettingsManager.hardwareAudioLatencyMs,
          isPlaying: isHostPlaying,
        );

        if (targetPosMs > 0) {
          await audioHandler.seek(Duration(milliseconds: targetPosMs));
        }
        if (isHostPlaying) {
          await audioHandler.play();
        } else {
          await audioHandler.pause();
        }
        syncStatusDescription.value = 'In Sync';
      }
    } catch (e) {
      debugPrint('[PartySyncCoordinator] handleRemotePlay error: $e');
    }
  }

  /// Joiner: Handles remote pause from host
  static void _handleRemotePause(Map<String, dynamic> payload) {
    _cancelPendingScheduledOperations();
    final posMs = (payload['positionMs'] as num?)?.toInt();
    audioHandler.pause();
    if (posMs != null && posMs > 0) {
      audioHandler.seek(Duration(milliseconds: posMs));
    }
    syncStatusDescription.value = 'Host Paused';
  }

  /// Joiner: Handles remote seek from host
  static Future<void> _handleRemoteSeek(Map<String, dynamic> payload) async {
    _cancelPendingScheduledOperations();
    final posMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
    final startAtEpochMs = (payload['startAtEpochMs'] as num?)?.toInt();
    if (startAtEpochMs != null) {
      final delayMs = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: startAtEpochMs,
        currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
        clockOffsetMs: clockOffsetMs,
      );
      if (delayMs > 25) {
        await audioHandler.pause();
        await audioHandler.seek(Duration(milliseconds: posMs));
        _pendingSeekTimer = Timer(Duration(milliseconds: delayMs), () async {
          if (role != PartyRole.joiner) return;
          await audioHandler.play();
        });
        return;
      }
    }
    await audioHandler.seek(Duration(milliseconds: posMs));
  }

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
          await audioHandler.playSong(
            targetSong,
            queue: songs,
            preserveUserQueue: false,
          );
        } else if (isPlaying) {
          await audioHandler.playSong(
            targetSong,
            queue: songs,
            preserveUserQueue: false,
          );
        }
      }
    } catch (e) {
      debugPrint('[PartySyncCoordinator] handleRemoteQueue error: $e');
    }
  }

  /// Joiner: Analyzes drift on heartbeat and performs micro-rate adjustments or hard-seek
  static void _handleHeartbeatReconciliation(Map<String, dynamic> payload) async {
    if (role != PartyRole.joiner) return;

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
            final song = Song.fromMap(Map<String, dynamic>.from(hostSongData));
            final rawQueue = payload['queue'] as List<dynamic>?;
            List<Song>? queue;
            if (rawQueue != null && rawQueue.isNotEmpty) {
              queue = rawQueue.map((item) => Song.fromMap(Map<String, dynamic>.from(item as Map))).toList();
            }
            await audioHandler.playSong(
              song,
              queue: queue ?? [song],
              preserveUserQueue: false,
            );
            final refHostEpoch = (payload['referenceHostEpochMs'] as num?)?.toInt();
            final refHostPos = (payload['referencePositionMs'] as num?)?.toInt();
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
            } else {
              await audioHandler.play();
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

    final isPlaying = audioHandler.playbackState.value.playing;

    if (!isHostPlaying) {
      if (isPlaying) {
        audioHandler.pause();
      }
      syncStatusDescription.value = 'Host Paused';
      return;
    } else if (!isPlaying && currentSong != null && currentSong.id == hostSongId) {
      audioHandler.play();
    }

    final refHostEpoch = (payload['referenceHostEpochMs'] as num?)?.toInt();
    final refHostPos = (payload['referencePositionMs'] as num?)?.toInt();
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

    // Read real player output position directly from audio engine
    final currentPos = audioHandler.player.position.inMilliseconds;
    final drift = currentPos - expectedPos;
    currentDriftMsNotifier.value = drift;

    final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
    final deadband = isLan ? 30 : 45;
    final microMax = isLan ? 150 : 220;

    final action = DriftReconciler.reconcileDrift(
      currentPositionMs: currentPos,
      expectedPositionMs: expectedPos,
      deadbandMs: deadband,
      microAdjustMaxMs: microMax,
      wasInSync: syncStatusDescription.value.startsWith('In Sync'),
    );

    if (action.isHardSeek && action.seekTargetMs != null) {
      debugPrint('[PartySyncCoordinator] Macro-drift hard seek of ${drift}ms to ${action.seekTargetMs}ms');
      final priorVolume = audioHandler.player.volume;
      // Macro-drift: Mute audio output, execute hard seek, un-mute, and resume
      audioHandler.player.setVolume(0.0).then((_) async {
        try {
          await audioHandler.seek(Duration(milliseconds: action.seekTargetMs!));
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
  static Future<void> leaveParty() async {
    _cancelPendingScheduledOperations();

    // Reset playback speed to 1.0 immediately
    if (isAudioHandlerInitialized) {
      try {
        audioHandler.setSpeed(1.0);
      } catch (e) {
        AppLogger.debug('PartySyncCoordinator', 'Could not reset playback speed: $e');
      }
    }

    _hostHeartbeatTimer?.cancel();
    _hostHeartbeatTimer = null;
    _ntpHandshakeTimer?.cancel();
    _ntpHandshakeTimer = null;
    _rollingNtpTimer?.cancel();
    _rollingNtpTimer = null;
    await PartyLanAccelerator.stop();

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
    if (isAudioHandlerInitialized) {
      try {
        audioHandler.setSpeed(1.0);
      } catch (e) {
        AppLogger.debug('PartySyncCoordinator', 'Could not reset playback speed: $e');
      }
    }

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
    _processedEventKeys.clear();
    _lastProcessedSeq = 0;
    _currentHostSeq = 0;
  }
}
