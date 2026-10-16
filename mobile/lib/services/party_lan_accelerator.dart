import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_logger.dart';

/// PartyLanAccelerator: Direct Local Wi-Fi (LAN) Socket Transport.
///
/// Bypasses cloud servers when devices are connected to the same Wi-Fi router,
/// reducing synchronization packet latency from ~40ms to < 2ms via local UDP datagrams.
/// Seamlessly falls back to Supabase Realtime when on cellular data or different networks.
class PartyLanAccelerator {
  static const int defaultPort = 45454;
  static RawDatagramSocket? _socket;
  static Timer? _hostBeaconTimer;
  static InternetAddress? _discoveredHostAddress;
  static int _discoveredHostPort = defaultPort;
  static String? _currentPartyCode;
  static bool _isHost = false;

  /// Whether direct local Wi-Fi peer transport is currently established
  static final ValueNotifier<bool> isLanActiveNotifier = ValueNotifier<bool>(false);

  // Callbacks hooked into PartySyncCoordinator
  static void Function(Map<String, dynamic> payload, InternetAddress senderAddress, int senderPort)? onNtpPingReceived;
  static void Function(Map<String, dynamic> payload)? onNtpPongReceived;
  static void Function(String event, Map<String, dynamic> payload)? onSyncEventReceived;

  /// Starts Host LAN broadcast on local Wi-Fi network
  static Future<void> startHost(String partyCode) async {
    if (kIsWeb) return;
    await stop();

    _currentPartyCode = partyCode;
    _isHost = true;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        defaultPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket?.broadcastEnabled = true;
      isLanActiveNotifier.value = true;
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
      });
    } catch (e) {
      AppLogger.log('PartyLanAccelerator', 'Host start notice (cellular or firewall): $e');
      isLanActiveNotifier.value = false;
    }
  }

  /// Starts Joiner LAN listener on local Wi-Fi network
  static Future<void> startJoiner(String partyCode) async {
    if (kIsWeb) return;
    await stop();

    _currentPartyCode = partyCode;
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

      // Probe local subnet for active host
      sendBroadcast('joiner_probe', {
        'code': _currentPartyCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      AppLogger.log('PartyLanAccelerator', 'Joiner start notice: $e');
      isLanActiveNotifier.value = false;
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
        if (!isLanActiveNotifier.value) {
          isLanActiveNotifier.value = true;
          AppLogger.log('PartyLanAccelerator', 'Discovered Host on LAN at ${datagram.address.address}:$_discoveredHostPort');
        }
        return;
      }

      // 2. Joiner Probe (Host detects joiner on local Wi-Fi)
      if (event == 'joiner_probe' && _isHost) {
        // Reply with immediate host beacon
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
        if (t0 != null && senderId != null) {
          final t2 = DateTime.now().millisecondsSinceEpoch;
          sendLanNtpPong(t0, t1, t2, senderId, datagram.address, datagram.port, isRolling: isRolling);
        }
        return;
      }

      // 4. Low-Latency NTP Pong (Joiner receives Host response)
      if (event == 'ntp_pong' && !_isHost) {
        onNtpPongReceived?.call(payload);
        return;
      }

      // 5. Synchronized Playback Events (sync_play, sync_pause, sync_seek, sync_heartbeat)
      if (!_isHost) {
        onSyncEventReceived?.call(event, payload);
      }
    } catch (_) {}
  }

  /// Stops LAN accelerator socket and timers
  static Future<void> stop() async {
    _hostBeaconTimer?.cancel();
    _hostBeaconTimer = null;
    _discoveredHostAddress = null;
    _currentPartyCode = null;
    _isHost = false;
    isLanActiveNotifier.value = false;

    if (_socket != null) {
      try {
        _socket?.close();
      } catch (_) {}
      _socket = null;
    }
  }
}
