import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_logger.dart';

/// Represents a registered Joiner device on the local Wi-Fi network
class LanJoinerPeer {
  final String id;
  final InternetAddress address;
  final int port;
  DateTime lastSeen;

  LanJoinerPeer({
    required this.id,
    required this.address,
    required this.port,
    required this.lastSeen,
  });
}

/// PartyLanAccelerator: Direct Local Wi-Fi (LAN) Socket Transport.
///
/// Delivers synchronization packets (< 2ms latency) via direct UDP datagrams
/// between devices connected to the same Wi-Fi router.
///
/// Features:
/// 1. Dynamic Joiner Registration: Host tracks joiners' ephemeral IP/ports and
///    unicasts playback events directly to each joiner, avoiding unreliable broadcast drops.
/// 2. Compact Datagrams: Only essential synchronization metadata is sent over UDP (<500 bytes).
/// 3. Verified Activity Watchdog: `isLanActiveNotifier` is true ONLY after real datagrams
///    have been received within the last 5 seconds.
class PartyLanAccelerator {
  static const int defaultPort = 45454;
  static RawDatagramSocket? _socket;
  static Timer? _hostBeaconTimer;
  static Timer? _joinerProbeTimer;
  static Timer? _activityWatchdogTimer;
  static InternetAddress? _discoveredHostAddress;
  static int _discoveredHostPort = defaultPort;
  static String? _currentPartyCode;
  static String? _selfClientId;
  static bool _isHost = false;
  static int _lastLanActivityEpochMs = 0;

  /// Known registered joiners on the host (senderId -> LanJoinerPeer)
  static final Map<String, LanJoinerPeer> _registeredJoiners = {};

  /// Whether direct local Wi-Fi peer transport is actively receiving events
  static final ValueNotifier<bool> isLanActiveNotifier = ValueNotifier<bool>(false);

  // Callbacks hooked into PartySyncCoordinator
  static void Function(Map<String, dynamic> payload, InternetAddress senderAddress, int senderPort)? onNtpPingReceived;
  static void Function(Map<String, dynamic> payload)? onNtpPongReceived;
  static void Function(String event, Map<String, dynamic> payload)? onSyncEventReceived;

  /// Starts Host LAN socket on local Wi-Fi network
  static Future<void> startHost(String partyCode, {String? clientId}) async {
    if (kIsWeb) return;
    await stop();

    _currentPartyCode = partyCode;
    _selfClientId = clientId;
    _isHost = true;
    _registeredJoiners.clear();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        defaultPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket?.broadcastEnabled = true;
      AppLogger.log('PartyLanAccelerator', 'Host UDP socket bound on port $defaultPort for party $partyCode');

      _socket?.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handleIncomingDatagram(datagram);
            }
          }
        },
        onError: (e) {
          AppLogger.log('PartyLanAccelerator', 'Host socket error: $e');
        },
      );

      // Broadcast beacon every 2.5s so joining phones on the same Wi-Fi instantly discover host
      _hostBeaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        sendBroadcast('host_beacon', {
          'code': _currentPartyCode,
          'port': defaultPort,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // Prune stale joiners inactive for > 10s
        final now = DateTime.now();
        _registeredJoiners.removeWhere((_, peer) => now.difference(peer.lastSeen).inSeconds > 10);
      });

      _startActivityWatchdog();
    } catch (e) {
      AppLogger.log('PartyLanAccelerator', 'Host start notice (cellular or firewall): $e');
      isLanActiveNotifier.value = false;
    }
  }

  /// Starts Joiner LAN listener on local Wi-Fi network
  static Future<void> startJoiner(String partyCode, {String? clientId}) async {
    if (kIsWeb) return;
    await stop();

    _currentPartyCode = partyCode;
    _selfClientId = clientId;
    _isHost = false;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // Ephemeral client port
        reuseAddress: true,
      );
      _socket?.broadcastEnabled = true;
      AppLogger.log('PartyLanAccelerator', 'Joiner UDP socket bound for party $partyCode');

      _socket?.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handleIncomingDatagram(datagram);
            }
          }
        },
        onError: (e) {
          AppLogger.log('PartyLanAccelerator', 'Joiner socket error: $e');
        },
      );

      // Probe local subnet for active host immediately and periodically
      _sendJoinerProbe();
      _joinerProbeTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
        _sendJoinerProbe();
      });

      _startActivityWatchdog();
    } catch (e) {
      AppLogger.log('PartyLanAccelerator', 'Joiner start notice: $e');
      isLanActiveNotifier.value = false;
    }
  }

  static void _sendJoinerProbe() {
    sendBroadcast('joiner_probe', {
      'code': _currentPartyCode,
      'senderId': _selfClientId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static void _startActivityWatchdog() {
    _activityWatchdogTimer?.cancel();
    _activityWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastLanActivityEpochMs == 0 || (now - _lastLanActivityEpochMs > 5000)) {
        if (isLanActiveNotifier.value) {
          isLanActiveNotifier.value = false;
        }
      }
    });
  }

  static void _recordLanActivity() {
    _lastLanActivityEpochMs = DateTime.now().millisecondsSinceEpoch;
    if (!isLanActiveNotifier.value) {
      isLanActiveNotifier.value = true;
    }
  }

  /// Sends a broadcast UDP packet to all devices on the local subnet (255.255.255.255)
  static void sendBroadcast(String event, Map<String, dynamic> payload) {
    if (_socket == null || _currentPartyCode == null) return;
    try {
      final message = jsonEncode({
        'partyCode': _currentPartyCode,
        'event': event,
        'payload': payload,
      });
      final bytes = utf8.encode(message);
      _socket?.send(bytes, InternetAddress('255.255.255.255'), defaultPort);
    } catch (_) {}
  }

  /// Sends synchronization event via direct UNICAST to all registered joiners,
  /// plus a subnet broadcast fallback.
  static void sendSyncEvent(String event, Map<String, dynamic> payload) {
    if (_socket == null || _currentPartyCode == null) return;
    try {
      final message = jsonEncode({
        'partyCode': _currentPartyCode,
        'event': event,
        'payload': payload,
      });
      final bytes = utf8.encode(message);

      // 1. Direct unicast to every registered joiner
      if (_isHost) {
        for (final peer in _registeredJoiners.values) {
          try {
            _socket?.send(bytes, peer.address, peer.port);
          } catch (_) {}
        }
      }

      // 2. Subnet broadcast fallback
      _socket?.send(bytes, InternetAddress('255.255.255.255'), defaultPort);
    } catch (_) {}
  }

  /// Sends direct UDP datagram to discovered host or specific peer
  static void sendDirect(String event, Map<String, dynamic> payload, {InternetAddress? targetAddress, int? targetPort}) {
    if (_socket == null || _currentPartyCode == null) return;
    final dest = targetAddress ?? _discoveredHostAddress;
    final destPort = targetPort ?? _discoveredHostPort;
    if (dest == null) {
      sendBroadcast(event, payload);
      return;
    }
    try {
      final message = jsonEncode({
        'partyCode': _currentPartyCode,
        'event': event,
        'payload': payload,
      });
      final bytes = utf8.encode(message);
      _socket?.send(bytes, dest, destPort);
    } catch (_) {}
  }

  /// Sends an NTP ping directly to the host over LAN
  static void sendLanNtpPing(int t0, String senderId, {bool isRolling = false}) {
    sendDirect('ntp_ping', {
      't0': t0,
      'senderId': senderId,
      'isRolling': isRolling,
    });
  }

  /// Sends an NTP pong directly back to the pinging joiner over LAN
  static void sendLanNtpPong(int t0, int t1, int t2, String recipientId, InternetAddress joinerAddress, int joinerPort, {bool isRolling = false}) {
    sendDirect(
      'ntp_pong',
      {
        't0': t0,
        't1': t1,
        't2': t2,
        'recipientId': recipientId,
        'isRolling': isRolling,
      },
      targetAddress: joinerAddress,
      targetPort: joinerPort,
    );
  }

  static void _handleIncomingDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>?;
      if (json == null) return;

      final code = json['partyCode']?.toString();
      if (code == null || code != _currentPartyCode) return;

      final event = json['event']?.toString() ?? '';
      final payload = json['payload'] as Map<String, dynamic>? ?? {};

      // 1. Host Discovery Beacon (Joiner detects host on local Wi-Fi)
      if (event == 'host_beacon' && !_isHost) {
        _discoveredHostAddress = datagram.address;
        _discoveredHostPort = (payload['port'] as num?)?.toInt() ?? defaultPort;
        _recordLanActivity();
        return;
      }

      // 2. Joiner Probe (Host detects joiner on local Wi-Fi)
      if (event == 'joiner_probe' && _isHost) {
        final senderId = payload['senderId']?.toString();
        if (senderId != null && senderId.isNotEmpty) {
          _registeredJoiners[senderId] = LanJoinerPeer(
            id: senderId,
            address: datagram.address,
            port: datagram.port,
            lastSeen: DateTime.now(),
          );
        }
        _recordLanActivity();

        // Reply with immediate host beacon directly to joiner
        sendDirect(
          'host_beacon',
          {
            'code': _currentPartyCode,
            'port': defaultPort,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          targetAddress: datagram.address,
          targetPort: datagram.port,
        );
        return;
      }

      // 3. Ultra-Low-Latency NTP Ping (Host handles Joiner ping in < 1ms)
      if (event == 'ntp_ping' && _isHost) {
        final t1 = DateTime.now().millisecondsSinceEpoch;
        final t0 = (payload['t0'] as num?)?.toInt();
        final senderId = payload['senderId']?.toString();
        final isRolling = payload['isRolling'] == true;
        if (senderId != null && senderId.isNotEmpty) {
          _registeredJoiners[senderId] = LanJoinerPeer(
            id: senderId,
            address: datagram.address,
            port: datagram.port,
            lastSeen: DateTime.now(),
          );
        }
        _recordLanActivity();

        if (t0 != null && senderId != null) {
          final t2 = DateTime.now().millisecondsSinceEpoch;
          sendLanNtpPong(t0, t1, t2, senderId, datagram.address, datagram.port, isRolling: isRolling);
        }
        return;
      }

      // 4. Low-Latency NTP Pong (Joiner receives Host response)
      if (event == 'ntp_pong' && !_isHost) {
        _recordLanActivity();
        onNtpPongReceived?.call(payload);
        return;
      }

      // 5. Synchronized Playback Events (sync_play, sync_pause, sync_seek, sync_heartbeat)
      if (!_isHost) {
        _recordLanActivity();
        onSyncEventReceived?.call(event, payload);
      }
    } catch (_) {}
  }

  /// Stops LAN accelerator socket and timers
  static Future<void> stop() async {
    _hostBeaconTimer?.cancel();
    _hostBeaconTimer = null;
    _joinerProbeTimer?.cancel();
    _joinerProbeTimer = null;
    _activityWatchdogTimer?.cancel();
    _activityWatchdogTimer = null;
    _discoveredHostAddress = null;
    _currentPartyCode = null;
    _selfClientId = null;
    _isHost = false;
    _lastLanActivityEpochMs = 0;
    _registeredJoiners.clear();
    isLanActiveNotifier.value = false;

    if (_socket != null) {
      try {
        _socket?.close();
      } catch (_) {}
      _socket = null;
    }
  }
}
