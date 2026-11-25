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
  static String _optimizeStreamUrlForNetwork(String url) {
    if (url.isEmpty) return url;
    final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
    final rtt = measuredRttMsNotifier.value;
    if (!isLan && (rtt > 120 || rtt == 0)) {
      if (url.contains('_320.mp4')) {
        return url.replaceAll('_320.mp4', '_96.mp4');
      }
    }
    return url;
  }

  static void _handlePeerReady(Map<String, dynamic> payload) {
    final peerId = payload['peerId']?.toString();
    final cmdId = payload['cmdId']?.toString();
    if (peerId != null && _knownPeers.containsKey(peerId)) {
      _knownPeers[peerId] = _knownPeers[peerId]!.copyWith(lastSeen: DateTime.now());
    }
    if (_pendingPrepareCmdId != null && cmdId == _pendingPrepareCmdId) {
      if (_peerReadyCompleter != null && !_peerReadyCompleter!.isCompleted) {
        _peerReadyCompleter!.complete();
      }
    } else {
      AppLogger.debug('PartySyncCoordinator', 'Ignoring stale or mismatched peer_ready ACK (received: $cmdId, active: $_pendingPrepareCmdId)');
    }
  }

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
  static Future<String?> startParty({String? pin}) async {
    final client = SupabaseService.client;
    await leaveParty();
    await SyncPlatform.acquireWifiLocks();

    final code = generatePartyCode();
    final effectivePin = (pin != null && pin.trim().isNotEmpty)
        ? pin.trim()
        : (1000 + _random.nextInt(9000)).toString();
    _sessionSecret = deriveRoomToken(code, effectivePin);
    _currentHostSeq = 0;
    _lastProcessedSeq = 0;
    _localIps = await PartyLanAccelerator.getLocalIpAddresses();

    partyCodeNotifier.value = code;
    partyPinNotifier.value = effectivePin;
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

    if (client != null) {
      syncStatusDescription.value = 'Hosting Party ($code)';
      final channel = client.channel('party:$code');

      // Host listens for NTP pings and peer presence
      channel.onBroadcast(
        event: 'ntp_ping',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
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
          if (!_isValidSessionPayload(payload)) return;
          final peerId = payload['peerId']?.toString();
          final devName = payload['deviceName']?.toString() ?? 'Guest Phone';
          final peerLanIps = (payload['lanIps'] as List<dynamic>?)?.map((e) => e.toString()).toList();
          final peerPort = (payload['lanPort'] as num?)?.toInt() ?? PartyLanAccelerator.defaultPort;
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

            if (peerLanIps != null && peerLanIps.isNotEmpty) {
              for (final ip in peerLanIps) {
                PartyLanAccelerator.registerPeerAddress(peerId, ip, peerPort);
              }
            }
          }
          _broadcastCurrentState();
        },
      );

      channel.onBroadcast(
        event: 'peer_presence',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
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
          if (!_isValidSessionPayload(payload)) return;
          final peerId = payload['id']?.toString();
          if (peerId != null) {
            _knownPeers.remove(peerId);
            connectedPeersNotifier.value = _knownPeers.values.toList();
            peerCountNotifier.value = _knownPeers.length;
            _broadcastCurrentState();
          }
        },
      );

      channel.onBroadcast(
        event: 'request_state',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
          _broadcastCurrentState();
        },
      );

      channel.onBroadcast(
        event: 'peer_ready',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
          _handlePeerReady(payload);
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
    } else {
      syncStatusDescription.value = 'Hosting Party (Wi-Fi Only - $code)';
    }

    // Start direct Local Wi-Fi (LAN) UDP acceleration on host
    PartyLanAccelerator.onSyncEventReceived = (event, payload) async {
      if (event == 'peer_ready') {
        _handlePeerReady(payload);
      } else if (event == 'request_state') {
        _broadcastCurrentState();
      }
    };
    PartyLanAccelerator.startHost(code, clientId: _clientId, roomToken: _sessionSecret);

    // Start periodic 2-second heartbeat broadcast and ghost peer pruning
    _hostHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      // Prune ghost peers inactive for > 14s (relaxed for cellular/internet peers)
      final initialCount = _knownPeers.length;
      _knownPeers.removeWhere((id, peer) => id != _clientId && now.difference(peer.lastSeen).inSeconds > 14);
      if (_knownPeers.length != initialCount) {
        connectedPeersNotifier.value = _knownPeers.values.toList();
        peerCountNotifier.value = _knownPeers.length;
      }

      _broadcastCurrentState();
    });

    return code;
  }

  static bool _shouldProcessEvent(String event, Map<String, dynamic> payload) {
    final cmdId = payload['cmdId']?.toString();
    if (cmdId != null && cmdId.isNotEmpty) {
      if (_processedCmdIds.contains(cmdId)) return false;
      _processedCmdIds.add(cmdId);
      if (_processedCmdIds.length > 100) {
        _processedCmdIds.remove(_processedCmdIds.first);
      }
      return true;
    }

    final seq = (payload['seq'] as num?)?.toInt();
    final hasPayload = payload['song'] != null || payload['streamUrl'] != null;

    final key = '${event}_${payload['seq']}_${payload['startAtEpochMs']}_${payload['positionMs']}_${payload['songId']}_$hasPayload';
    if (_processedEventKeys.contains(key)) return false;
    _processedEventKeys.add(key);
    if (_processedEventKeys.length > 50) {
      _processedEventKeys.remove(_processedEventKeys.first);
    }

    if (seq != null) {
      if (seq < _lastProcessedSeq) {
        return false; // Stale or duplicate out-of-order event
      }
      if (seq == _lastProcessedSeq && !hasPayload) {
        return false;
      }
      _lastProcessedSeq = seq;
    }

    return true;
  }

  static void _cancelPendingScheduledOperations() {
    _pendingScheduledPlayTimer?.cancel();
    _pendingScheduledPlayTimer = null;
    _pendingSeekTimer?.cancel();
    _pendingSeekTimer = null;
    if (_peerReadyCompleter != null && !_peerReadyCompleter!.isCompleted) {
      _peerReadyCompleter!.complete();
    }
  }

  static void _handleNtpPong(Map<String, dynamic> payload, RealtimeChannel? channel, PeerDeviceInfo selfPeer) {
    final recipientId = payload['recipientId']?.toString();
    if (recipientId == _clientId) {
      final t3 = DateTime.now().millisecondsSinceEpoch;
      final t0 = (payload['t0'] as num?)?.toInt();
      final t1 = (payload['t1'] as num?)?.toInt();
      final t2 = (payload['t2'] as num?)?.toInt();
      final isRolling = payload['isRolling'] == true;
      final isLan = payload['isLan'] == true;

      if (t0 != null && t1 != null && t2 != null) {
        final sample = NtpSample(t0: t0, t1: t1, t2: t2, t3: t3, isLan: isLan);

        if (isLan) {
          // Purge cloud NTP samples as soon as first LAN sample arrives to avoid cloud EMA poisoning
          _ntpSamples.removeWhere((s) => !s.isLan);
        }

        // Maintain sliding window of the last 16 samples
        _ntpSamples.add(sample);
        while (_ntpSamples.length > 16) {
          _ntpSamples.removeAt(0);
        }

        // Outlier rejection: filters samples where RTT > 1.4x of min RTT with EMA smoothing
        final offset = NtpCalculator.calculateOffset(
          _ntpSamples,
          previousOffset: clockOffsetMsNotifier.value,
        );
        clockOffsetMsNotifier.value = offset;
        if (isLan || !PartyLanAccelerator.isLanActiveNotifier.value) {
          measuredRttMsNotifier.value = sample.rtt;
        }

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
            'token': _sessionSecret,
          },
        );
      }
    }
  }

  /// Joiner: Joins an active party using code and room PIN, then performs clock handshake.
  static Future<bool> joinParty(String rawCode, {String? pin}) async {
    final client = SupabaseService.client;
    final trimmedInput = rawCode.trim().toUpperCase();
    if (trimmedInput.isEmpty) return false;

    String cleanCode = trimmedInput;
    String? inlinePin;
    if (trimmedInput.contains('#')) {
      final parts = trimmedInput.split('#');
      cleanCode = parts.first.trim();
      if (parts.length > 1) {
        inlinePin = parts[1].trim();
      }
    }
    final effectivePin = (pin != null && pin.trim().isNotEmpty) ? pin.trim() : (inlinePin ?? '');
    if (cleanCode.isEmpty || effectivePin.isEmpty) {
      return false;
    }

    await leaveParty();
    await SyncPlatform.acquireWifiLocks();
    _localIps = await PartyLanAccelerator.getLocalIpAddresses();

    final roomToken = deriveRoomToken(cleanCode, effectivePin);
    _sessionSecret = roomToken;
    partyCodeNotifier.value = cleanCode;
    partyPinNotifier.value = effectivePin;
    roleNotifier.value = PartyRole.joiner;
    clockOffsetMsNotifier.value = 0;
    measuredRttMsNotifier.value = 0;
    currentDriftMsNotifier.value = 0;
    _lastProcessedSeq = 0;
    syncStatusDescription.value = client != null
        ? 'Connecting to $cleanCode...'
        : 'Searching for $cleanCode on Wi-Fi...';

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

    final channel = client?.channel('party:$cleanCode');

    // Hook direct local Wi-Fi UDP acceleration
    PartyLanAccelerator.onNtpPongReceived = (payload) {
      _handleNtpPong(payload, channel, selfPeer);
    };

    PartyLanAccelerator.onSyncEventReceived = (event, payload) async {
      if (!_shouldProcessEvent(event, payload)) return;
      switch (event) {
        case 'sync_prepare':
          await _handleRemotePrepare(payload);
          break;
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

    PartyLanAccelerator.startJoiner(cleanCode, clientId: _clientId, roomToken: roomToken);

    if (channel != null) {
      channel.onBroadcast(
        event: 'ntp_pong',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
          _handleNtpPong(payload, channel, selfPeer);
        },
      );

      channel.onBroadcast(
        event: 'sync_prepare',
        callback: (payload) async {
          if (!_isValidSessionPayload(payload)) return;
          if (!_shouldProcessEvent('sync_prepare', payload)) return;
          await _handleRemotePrepare(payload);
        },
      );

      channel.onBroadcast(
        event: 'sync_queue',
        callback: (payload) async {
          if (!_isValidSessionPayload(payload)) return;
          if (!_shouldProcessEvent('sync_queue', payload)) return;
          await _handleRemoteQueue(payload);
        },
      );

      channel.onBroadcast(
        event: 'sync_play',
        callback: (payload) async {
          if (!_isValidSessionPayload(payload)) return;
          if (!_shouldProcessEvent('sync_play', payload)) return;
          await _handleRemotePlay(payload);
        },
      );

      channel.onBroadcast(
        event: 'sync_pause',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
          if (!_shouldProcessEvent('sync_pause', payload)) return;
          _handleRemotePause(payload);
        },
      );

      channel.onBroadcast(
        event: 'sync_seek',
        callback: (payload) async {
          if (!_isValidSessionPayload(payload)) return;
          if (!_shouldProcessEvent('sync_seek', payload)) return;
          await _handleRemoteSeek(payload);
        },
      );

      channel.onBroadcast(
        event: 'sync_heartbeat',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
          if (!_shouldProcessEvent('sync_heartbeat', payload)) return;
          _handleHeartbeatReconciliation(payload);
        },
      );

      channel.onBroadcast(
        event: 'party_ended',
        callback: (payload) {
          if (!_isValidSessionPayload(payload)) return;
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
              'lanIps': _localIps,
              'lanPort': PartyLanAccelerator.defaultPort,
              'token': _sessionSecret,
            },
          );
          channel.sendBroadcastMessage(
            event: 'request_state',
            payload: {'senderId': _clientId, 'token': _sessionSecret},
          );
          PartyLanAccelerator.sendDirect('request_state', {'senderId': _clientId, 'token': _sessionSecret});

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
    } else {
      PartyLanAccelerator.sendDirect('request_state', {'senderId': _clientId, 'token': _sessionSecret});
    }

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
          'token': _sessionSecret,
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
            'token': _sessionSecret,
          },
        );
      }
      PartyLanAccelerator.sendLanNtpPing(t0, _clientId, isRolling: true);
      pingsSent++;
    });
  }

  /// Host: Broadcasts current playing track, reference epoch, position, and peer devices
  static void _broadcastCurrentState() {
    if (!isHost) return;
    final pos = audioHandler.player.position.inMilliseconds;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isPlaying = audioHandler.playbackState.value.playing;
    final currentSong = audioHandler.currentSong;

    final seq = ++_currentHostSeq;
    final directUrl = currentSong?.streamUrl ?? DefaultStreamResolver.getCachedStream(currentSong?.id ?? '');
    final payload = {
      'seq': seq,
      'token': _sessionSecret,
      'isPlaying': isPlaying,
      'songId': currentSong?.id,
      'song': currentSong?.toMap(),
      'streamUrl': directUrl,
      'referenceHostEpochMs': now,
      'referencePositionMs': pos,
      'peers': _knownPeers.values.map((p) => p.toMap()).toList(),
      'peerCount': _knownPeers.length,
      'lanIps': _localIps,
      'lanPort': PartyLanAccelerator.defaultPort,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_heartbeat',
      payload: payload,
    );

    // LAN heartbeat with track metadata and stream URL for fast peer reconciliation
    PartyLanAccelerator.sendSyncEvent('sync_heartbeat', {
      'seq': seq,
      'token': _sessionSecret,
      'isPlaying': isPlaying,
      'songId': currentSong?.id,
      'song': currentSong?.toMap(),
      'streamUrl': directUrl,
      'referenceHostEpochMs': now,
      'referencePositionMs': pos,
      'peerCount': _knownPeers.length,
    });
  }

  /// Host: Notifies connected speakers when a new track starts playing via Prepare -> Ack -> Go barrier
  static Future<void> notifyHostPlay(
    Song song, {
    int positionMs = 0,
    List<Song>? queue,
    int? currentIndex,
  }) async {
    if (!isHost) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastAnnouncedSongId = song.id;
    _lastAnnouncedTimeMs = now;
    _cancelPendingScheduledOperations();

    final cmdId = _uuid.v4();
    _pendingPrepareCmdId = cmdId;
    final seq = ++_currentHostSeq;

    final directUrl = song.streamUrl ??
        DefaultStreamResolver.getCachedStream(song.id) ??
        audioHandler.currentSong?.streamUrl;

    // 1. Prepare Phase: Broadcast sync_prepare so all devices buffer the stream
    final preparePayload = {
      'cmdId': cmdId,
      'seq': seq,
      'token': _sessionSecret,
      'song': song.toMap(),
      'songId': song.id,
      'streamUrl': directUrl,
      'positionMs': positionMs,
      'currentIndex': currentIndex ?? 0,
      'queue': queue?.take(30).map((s) => s.toMap()).toList(),
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_prepare',
      payload: preparePayload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_prepare', preparePayload);

    // 2. Prepare Barrier: Wait for peer_ready with adaptive timeout if remote peers exist
    final hasRemotePeers = _knownPeers.values.any((p) => !p.isSelf);
    if (hasRemotePeers) {
      _peerReadyCompleter = Completer<void>();
      final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
      final barrierTimeoutMs = isLan ? 1200 : 3500;
      try {
        await _peerReadyCompleter!.future.timeout(Duration(milliseconds: barrierTimeoutMs));
      } catch (e) {
      AppLogger.debug('PartySyncCoordinator', 'Handled exception: $e');
    }
      _peerReadyCompleter = null;
    }

    // Invariant check: Has a newer skip or track change superseded this prepare cycle?
    if (_pendingPrepareCmdId != cmdId) {
      AppLogger.debug('PartySyncCoordinator', 'Prepare cycle for $cmdId superseded by $_pendingPrepareCmdId; aborting stale play broadcast.');
      return;
    }

    // 3. Go Phase: Audio is now loaded; compute tight startAtEpochMs
    final peerRtts = _knownPeers.values.where((p) => !p.isSelf).map((p) => p.rttMs).toList();
    final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
    final leadTimeMs = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
      peerRtts: peerRtts,
      isLan: isLan,
    );
    final hostNow = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = hostNow + leadTimeMs;

    final playPayload = {
      'cmdId': _uuid.v4(),
      'prepareCmdId': cmdId,
      'seq': ++_currentHostSeq,
      'token': _sessionSecret,
      'song': song.toMap(),
      'songId': song.id,
      'streamUrl': directUrl,
      'positionMs': positionMs,
      'referenceHostEpochMs': startAtEpochMs,
      'referencePositionMs': positionMs,
      'startAtEpochMs': startAtEpochMs,
      'currentIndex': currentIndex ?? 0,
      'isPlaying': true,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: playPayload,
    );
    // Send 2x over LAN with 30ms spacing to prevent UDP loss
    PartyLanAccelerator.sendSyncEvent('sync_play', playPayload);
    Future.delayed(const Duration(milliseconds: 30), () {
      if (isHost) {
        PartyLanAccelerator.sendSyncEvent('sync_play', playPayload);
      }
    });

    // 4. Accurate Timer Arming: pause and pre-position FIRST
    await audioHandler.player.pause();
    if (positionMs > 0) {
      await audioHandler.player.seek(Duration(milliseconds: positionMs));
    } else {
      await audioHandler.player.seek(Duration.zero);
    }

    final remainingDelay = startAtEpochMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingDelay > 10) {
      _pendingScheduledPlayTimer?.cancel();
      _pendingScheduledPlayTimer = Timer(Duration(milliseconds: remainingDelay), () {
        if (isHost) {
          audioHandler.player.play().catchError((e) {
            AppLogger.debug('PartySyncCoordinator', 'Host scheduled play error: $e');
          });
        }
      });
    } else {
      audioHandler.player.play().catchError((e) {
        AppLogger.debug('PartySyncCoordinator', 'Host immediate play error: $e');
      });
    }
  }

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
  }) async {
    if (!isHost) {
      await audioHandler.playSong(nextSong, queue: queue, preserveUserQueue: false);
      return;
    }
    _cancelPendingScheduledOperations();
    await audioHandler.playSong(
      nextSong,
      queue: queue,
      preserveUserQueue: false,
      autoPlay: false,
      isPartySyncInternal: true,
    );
    await notifyHostPlay(nextSong, positionMs: 0, queue: queue, currentIndex: currentIndex);
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
    if (!isHost) return;
    final pos = audioHandler.player.position.inMilliseconds;
    final seq = ++_currentHostSeq;
    final payload = {
      'cmdId': _uuid.v4(),
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
    if (!isHost) return;
    final seq = ++_currentHostSeq;
    final payload = {
      'cmdId': _uuid.v4(),
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
    if (!isHost) return;
    final pos = audioHandler.player.position.inMilliseconds;
    final now = DateTime.now().millisecondsSinceEpoch;
    final curSong = audioHandler.currentSong;
    final seq = ++_currentHostSeq;

    final peerRtts = _knownPeers.values.where((p) => !p.isSelf).map((p) => p.rttMs).toList();
    final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
    final leadTimeMs = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
      peerRtts: peerRtts,
      isLan: isLan,
    );
    final startAtEpochMs = now + leadTimeMs;

    final payload = {
      'cmdId': _uuid.v4(),
      'seq': seq,
      'token': _sessionSecret,
      'song': curSong?.toMap(),
      'songId': curSong?.id,
      'positionMs': pos,
      'referenceHostEpochMs': startAtEpochMs,
      'referencePositionMs': pos,
      'startAtEpochMs': startAtEpochMs,
      'isPlaying': true,
    };

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: payload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_play', {
      'cmdId': payload['cmdId'],
      'seq': seq,
      'token': _sessionSecret,
      'songId': curSong?.id,
      'positionMs': pos,
      'referenceHostEpochMs': startAtEpochMs,
      'referencePositionMs': pos,
      'startAtEpochMs': startAtEpochMs,
      'isPlaying': true,
    });

    final remainingDelay = startAtEpochMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingDelay > 10) {
      await audioHandler.player.pause();
      _pendingScheduledPlayTimer?.cancel();
      _pendingScheduledPlayTimer = Timer(Duration(milliseconds: remainingDelay), () {
        if (isHost) {
          audioHandler.player.play().catchError((e) {
            AppLogger.debug('PartySyncCoordinator', 'Host resume error: $e');
          });
        }
      });
    } else {
      audioHandler.player.play().catchError((e) {
        AppLogger.debug('PartySyncCoordinator', 'Host resume error: $e');
      });
    }
  }

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

  static Future<void> _handleRemotePrepare(Map<String, dynamic> payload) async {
    _cancelPendingScheduledOperations();
    try {
      final songData = payload['song'] as Map<dynamic, dynamic>?;
      final songId = payload['songId']?.toString();
      final rawStreamUrl = payload['streamUrl']?.toString() ??
          (songData != null ? songData['streamUrl']?.toString() : null);
      Song? song;
      if (songData != null) {
        song = Song.fromMap(Map<String, dynamic>.from(songData));
      }
      bool hasLocalFile = false;
      if (song != null) {
        final localCopy = resolveLocalDownloadedCopy(song);
        if (localCopy != null) {
          song = localCopy;
          hasLocalFile = true;
        } else {
          final directStreamUrl = rawStreamUrl != null ? _optimizeStreamUrlForNetwork(rawStreamUrl) : null;
          if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
            song.streamUrl = directStreamUrl;
            DefaultStreamResolver.cacheStream(song.id, directStreamUrl);
          }
        }
      }

      final positionMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
      final currentSong = audioHandler.currentSong;
      final bool isSameSong = (song != null && currentSong?.id == song.id) ||
                              (songId != null && currentSong?.id == songId);

      if (!isSameSong && song != null) {
        _isSyncLoading = true;
        syncStatusDescription.value = hasLocalFile
            ? 'Ready (local file): "${song.title}"'
            : 'Preparing "${song.title}"...';
        try {
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
          if (!hasLocalFile) {
            _prewarmUpcomingTracks(rawQueue, currentIndex: (payload['currentIndex'] as num?)?.toInt() ?? 0);
          }
        } finally {
          _isSyncLoading = false;
        }
      }

      await audioHandler.pause(isPartyDriven: true);
      if (positionMs > 0) {
        await audioHandler.seek(Duration(milliseconds: positionMs), isPartyDriven: true);
      } else {
        await audioHandler.seek(Duration.zero, isPartyDriven: true);
      }

      // Send peer_ready ACK to host over LAN and cloud
      final ackPayload = {
        'peerId': _clientId,
        'cmdId': payload['cmdId'],
        'songId': songId ?? song?.id,
        'hasLocalFile': hasLocalFile,
        'token': _sessionSecret,
      };
      PartyLanAccelerator.sendDirect('peer_ready', ackPayload);
      _partyChannel?.sendBroadcastMessage(
        event: 'peer_ready',
        payload: ackPayload,
      );
      syncStatusDescription.value = hasLocalFile ? 'Ready (local file)' : 'Ready (waiting for host)';
    } catch (e) {
      debugPrint('[PartySyncCoordinator] handleRemotePrepare error: $e');
    }
  }

  /// Joiner: Handles remote scheduled play from host
  static Future<void> _handleRemotePlay(Map<String, dynamic> payload) async {
    _cancelPendingScheduledOperations();

    try {
      final songData = payload['song'] as Map<dynamic, dynamic>?;
      final songId = payload['songId']?.toString();
      final rawStreamUrl = payload['streamUrl']?.toString() ??
          (songData != null ? songData['streamUrl']?.toString() : null);
      final directStreamUrl = rawStreamUrl != null ? _optimizeStreamUrlForNetwork(rawStreamUrl) : null;
      Song? song;
      if (songData != null) {
        song = Song.fromMap(Map<String, dynamic>.from(songData));
      }
      if (song != null && directStreamUrl != null && directStreamUrl.isNotEmpty) {
        song.streamUrl = directStreamUrl;
        DefaultStreamResolver.cacheStream(song.id, directStreamUrl);
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
        _isSyncLoading = true;
        syncStatusDescription.value = 'Syncing "${song.title}"...';
        try {
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
          _prewarmUpcomingTracks(rawQueue, currentIndex: (payload['currentIndex'] as num?)?.toInt() ?? 0);
        } finally {
          _isSyncLoading = false;
        }
      }

      // Accurate Timer Arming: pause and pre-position FIRST
      await audioHandler.pause(isPartyDriven: true);
      if (positionMs > 0) {
        await audioHandler.seek(Duration(milliseconds: positionMs), isPartyDriven: true);
      } else {
        await audioHandler.seek(Duration.zero, isPartyDriven: true);
      }

      final hardwareLatencyMs = SettingsManager.hardwareAudioLatencyMs;
      final bluetoothDelayMs = _effectiveBluetoothDelayMs;
      final latencyOffsetMs = bluetoothDelayMs + hardwareLatencyMs;

      final nowLocal = DateTime.now().millisecondsSinceEpoch;
      final estimatedHostTimeMs = nowLocal + clockOffsetMs;
      final remainingDelayMs = startAtEpochMs - estimatedHostTimeMs - latencyOffsetMs;

      if (remainingDelayMs > 15) {
        // Scheduled barrier is genuinely in the future: hold until remainingDelayMs
        _pendingScheduledPlayTimer?.cancel();
        _pendingScheduledPlayTimer = Timer(Duration(milliseconds: remainingDelayMs), () {
          if (role != PartyRole.joiner) return;
          audioHandler.play().catchError((e) {
            AppLogger.debug('PartySyncCoordinator', 'Joiner play error: $e');
          });
          syncStatusDescription.value = 'In Sync';
        });
      } else {
        // Immediate start anchored to referenceHostEpochMs and referencePositionMs with latency compensation
        final targetPosMs = ScheduledPlaybackCalculator.calculateExpectedPositionMs(
          referenceHostEpochMs: refHostEpoch,
          referenceTrackPositionMs: refHostPos,
          currentLocalEpochMs: nowLocal,
          clockOffsetMs: clockOffsetMs,
          bluetoothDelayMs: bluetoothDelayMs,
          hardwareLatencyMs: hardwareLatencyMs,
          isPlaying: isHostPlaying,
        );

        if (targetPosMs > 0) {
          await audioHandler.seek(Duration(milliseconds: targetPosMs), isPartyDriven: true);
        }
        if (isHostPlaying) {
          audioHandler.play().catchError((e) {
            AppLogger.debug('PartySyncCoordinator', 'Joiner immediate play error: $e');
          });
        } else {
          await audioHandler.pause(isPartyDriven: true);
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
    audioHandler.pause(isPartyDriven: true);
    if (posMs != null && posMs > 0) {
      audioHandler.seek(Duration(milliseconds: posMs), isPartyDriven: true);
    }
    syncStatusDescription.value = 'Host Paused';
  }

  /// Joiner: Handles remote seek from host
  static Future<void> _handleRemoteSeek(Map<String, dynamic> payload) async {
    _cancelPendingScheduledOperations();
    final posMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
    final startAtEpochMs = (payload['startAtEpochMs'] as num?)?.toInt();
    if (startAtEpochMs != null) {
      // Accurate Timer Arming: pause and seek FIRST
      await audioHandler.pause(isPartyDriven: true);
      await audioHandler.seek(Duration(milliseconds: posMs), isPartyDriven: true);

      final hardwareLatencyMs = SettingsManager.hardwareAudioLatencyMs;
      final bluetoothDelayMs = _effectiveBluetoothDelayMs;
      final latencyOffsetMs = bluetoothDelayMs + hardwareLatencyMs;

      final nowLocal = DateTime.now().millisecondsSinceEpoch;
      final estHostTime = nowLocal + clockOffsetMs;
      final remainingDelayMs = startAtEpochMs - estHostTime - latencyOffsetMs;

      if (remainingDelayMs > 15) {
        _pendingSeekTimer = Timer(Duration(milliseconds: remainingDelayMs), () {
          if (role != PartyRole.joiner) return;
          audioHandler.play().catchError((_) => null);
        });
        return;
      }
      audioHandler.play().catchError((_) => null);
      return;
    }
    await audioHandler.seek(Duration(milliseconds: posMs), isPartyDriven: true);
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
            autoPlay: false,
            isPartySyncInternal: true,
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
    PartyLanAccelerator.onSyncEventReceived = null;
    PartyLanAccelerator.onNtpPongReceived = null;
    PartyLanAccelerator.onNtpPingReceived = null;
    await PartyLanAccelerator.stop();
    await SyncPlatform.releaseWifiLocks();

    if (_partyChannel != null) {
      try {
        if (isHost) {
          _partyChannel?.sendBroadcastMessage(
            event: 'party_ended',
            payload: {'hostId': _clientId, 'token': _sessionSecret},
          );
        } else {
          _partyChannel?.sendBroadcastMessage(
            event: 'peer_leave',
            payload: {'id': _clientId, 'token': _sessionSecret},
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
    partyPinNotifier.value = null;
    _sessionSecret = '';
    clockOffsetMsNotifier.value = 0;
    measuredRttMsNotifier.value = 0;
    currentDriftMsNotifier.value = 0;
    peerCountNotifier.value = 0;
    _knownPeers.clear();
    connectedPeersNotifier.value = [];
    syncStatusDescription.value = 'Idle';
    _ntpSamples.clear();
    _processedEventKeys.clear();
    _processedCmdIds.clear();
    _peerReadyCompleter = null;
    _pendingPrepareCmdId = null;
    _lastProcessedSeq = 0;
    _currentHostSeq = 0;
  }
}
