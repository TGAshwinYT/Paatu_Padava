import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../platform/sync_platform.dart';
import 'app_logger.dart';

/// Represents a registered Joiner device on the local Wi-Fi network
class LanJoinerPeer {
  final String id;
  final InternetAddress address;
  final int port;
  DateTime lastSeen;
  LanJoinerPeer({required this.id, required this.address, required this.port, required this.lastSeen});
}

/// Direct Local Wi-Fi (LAN) Socket Transport (< 2ms latency) with subnet broadcast & direct unicast.
class PartyLanAccelerator {
  static const int defaultPort = 45454;
  static const int maxClockSkewMs = 30000;
  static RawDatagramSocket? _socket;
  static Timer? _hostBeaconTimer;
  static Timer? _joinerProbeTimer;
  static Timer? _activityWatchdogTimer;
  static InternetAddress? _discoveredHostAddress;
  static int _discoveredHostPort = defaultPort;
  static String? _currentPartyCode;
  static String? _selfClientId;
  static String? _roomToken;
  static bool _isHost = false;
  static int _lastLanActivityEpochMs = 0;
  static final Set<InternetAddress> _broadcastAddresses = {InternetAddress('255.255.255.255')};

  /// Known registered joiners on the host (senderId -> LanJoinerPeer)
  static final Map<String, LanJoinerPeer> _registeredJoiners = {};

  /// Whether direct local Wi-Fi peer transport is actively receiving events
  static final ValueNotifier<bool> isLanActiveNotifier = ValueNotifier<bool>(false);

  // Callbacks hooked into PartySyncCoordinator
  static void Function(Map<String, dynamic> payload, InternetAddress senderAddress, int senderPort)? onNtpPingReceived;
  static void Function(Map<String, dynamic> payload)? onNtpPongReceived;
  static void Function(String event, Map<String, dynamic> payload)? onSyncEventReceived;

  /// Refreshes local subnet broadcast addresses using native Wi-Fi subnet mask, hotspot subnets, and network interfaces
  static Future<void> _refreshBroadcastAddresses() async {
    _broadcastAddresses.clear();
    _broadcastAddresses.add(InternetAddress('255.255.255.255'));
    // Always include standard Android personal hotspot and Wi-Fi Direct broadcast subnets
    _broadcastAddresses.add(InternetAddress('192.168.43.255'));
    _broadcastAddresses.add(InternetAddress('192.168.49.255'));
    try {
      final wifiBroadcast = await SyncPlatform.getWifiBroadcastAddress();
      if (wifiBroadcast != null && wifiBroadcast.isNotEmpty) {
        _broadcastAddresses.add(InternetAddress(wifiBroadcast));
      }
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              _broadcastAddresses.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
            }
          }
        }
      }
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
  }

  /// Returns active non-loopback local IPv4 addresses
  static Future<List<String>> getLocalIpAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return interfaces
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback)
          .map((a) => a.address)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Registers a known peer LAN address from cloud handshake
  /// (Does not activate LAN flag until a verified UDP packet arrives)
  static void registerPeerAddress(String peerId, String ipAddress, int port) {
    if (_registeredJoiners.containsKey(peerId) && isLanActiveNotifier.value) {
      return;
    }
    try {
      _registeredJoiners[peerId] = LanJoinerPeer(
        id: peerId,
        address: InternetAddress(ipAddress),
        port: port,
        lastSeen: DateTime.now(),
      );
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
  }

  /// Registers the discovered host LAN address from cloud handshake
  /// (Does not activate LAN flag until a verified UDP packet arrives)
  static void registerHostAddress(String ipAddress, int port) {
    if (_discoveredHostAddress != null && isLanActiveNotifier.value) {
      return;
    }
    try {
      _discoveredHostAddress = InternetAddress(ipAddress);
      _discoveredHostPort = port;
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
  }

  /// Starts Host LAN socket on local Wi-Fi network
  static Future<void> startHost(String partyCode, {String? clientId, String? roomToken}) async {
    if (kIsWeb) return;
    await stop();

    _currentPartyCode = partyCode;
    _selfClientId = clientId;
    _roomToken = (roomToken != null && roomToken.isNotEmpty) ? roomToken : null;
    _isHost = true;
    _registeredJoiners.clear();
    await _refreshBroadcastAddresses();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        defaultPort,
        reuseAddress: true,
        reusePort: false,
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
  static Future<void> startJoiner(String partyCode, {String? clientId, String? roomToken}) async {
    if (kIsWeb) return;
    await stop();

    _currentPartyCode = partyCode;
    _selfClientId = clientId;
    _roomToken = (roomToken != null && roomToken.isNotEmpty) ? roomToken : null;
    _isHost = false;
    await _refreshBroadcastAddresses();

    try {
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          defaultPort,
          reuseAddress: true,
        );
      } catch (_) {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0, // Ephemeral fallback port
          reuseAddress: true,
        );
      }
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

      // Aggressive initial probe (every 350ms for first ~3s) for sub-second LAN discovery
      int probeCount = 0;
      _sendJoinerProbe();
      _joinerProbeTimer?.cancel();
      _joinerProbeTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
        probeCount++;
        _sendJoinerProbe();
        if (probeCount >= 8 || _discoveredHostAddress != null) {
          timer.cancel();
          // Settle into steady-state background probe
          _joinerProbeTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
            _sendJoinerProbe();
          });
        }
      });

      _startActivityWatchdog();
    } catch (e) {
      AppLogger.log('PartyLanAccelerator', 'Joiner start notice: $e');
      isLanActiveNotifier.value = false;
    }
  }

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, dynamic>();
      for (final entry in value.entries) {
        sorted[entry.key.toString()] = _canonicalize(entry.value);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }

  /// Constant-time string comparison to prevent timing side-channels.
  static bool constantTimeEquals(String? a, String? b) {
    if (a == null || b == null) return false;
    final bytesA = utf8.encode(a);
    final bytesB = utf8.encode(b);
    if (bytesA.length != bytesB.length || bytesA.isEmpty) return false;
    int diff = 0;
    for (int i = 0; i < bytesA.length; i++) {
      diff |= bytesA[i] ^ bytesB[i];
    }
    return diff == 0;
  }

  /// Computes deterministic HMAC-SHA256 signature over partyCode, event, timestamp, and canonical payload.
  static String computePacketSignature(
    String partyCode,
    String event,
    int ts,
    Map<String, dynamic> payload,
    String roomToken,
  ) {
    final canonicalPayload = jsonEncode(_canonicalize(payload));
    final signingInput = '$partyCode|$event|$ts|$canonicalPayload';
    final hmac = Hmac(sha256, utf8.encode(roomToken));
    return hmac.convert(utf8.encode(signingInput)).toString();
  }

  /// Verifies incoming LAN packet room token signature and replay timestamp window.
  /// `host_beacon` packets are discovery-only and carry no control state or room secrets.
  static bool verifyIncomingPacket(
    Map<String, dynamic> json, {
    required String expectedCode,
    required String? expectedRoomToken,
    int? nowEpochMs,
  }) {
    final code = json['partyCode']?.toString();
    if (code == null || code != expectedCode) return false;
    if (json['payload'] is! Map) return false;

    final event = json['event']?.toString() ?? '';
    if (event.isEmpty) return false;
    if (event == 'host_beacon') return true;

    if (expectedRoomToken == null || expectedRoomToken.isEmpty) return false;

    final ts = (json['ts'] as num?)?.toInt();
    final sig = json['sig']?.toString();
    if (ts == null || sig == null || sig.isEmpty) return false;

    final now = nowEpochMs ?? DateTime.now().millisecondsSinceEpoch;
    if ((now - ts).abs() > maxClockSkewMs) return false;

    final payloadMap = Map<String, dynamic>.from(json['payload'] as Map);
    final expectedSig = computePacketSignature(code, event, ts, payloadMap, expectedRoomToken);
    return constantTimeEquals(sig, expectedSig);
  }

  static String _encodePacket(String event, Map<String, dynamic> payload) {
    final packet = <String, dynamic>{
      'partyCode': _currentPartyCode,
      'event': event,
      'payload': payload,
    };
    if (event != 'host_beacon' && _roomToken != null && _roomToken!.isNotEmpty) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      packet['ts'] = ts;
      packet['sig'] = computePacketSignature(_currentPartyCode!, event, ts, payload, _roomToken!);
    }
    return jsonEncode(packet);
  }

  static void _sendJoinerProbe() {
    final payload = {
      'code': _currentPartyCode,
      'senderId': _selfClientId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    sendBroadcast('joiner_probe', payload);
    // Direct hotspot gateway probe: if joiner is connected to personal hotspot, host is at 192.168.43.1 or 192.168.49.1
    try {
      final message = _encodePacket('joiner_probe', payload);
      final bytes = utf8.encode(message);
      _socket?.send(bytes, InternetAddress('192.168.43.1'), defaultPort);
      _socket?.send(bytes, InternetAddress('192.168.49.1'), defaultPort);
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
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

  /// Sends a broadcast UDP packet to all devices on the local subnet (255.255.255.255 & directed subnets)
  static void sendBroadcast(String event, Map<String, dynamic> payload) {
    if (_socket == null || _currentPartyCode == null) return;
    try {
      final message = _encodePacket(event, payload);
      final bytes = utf8.encode(message);
      for (final bcast in _broadcastAddresses) {
        try {
          _socket?.send(bytes, bcast, defaultPort);
        } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
      }
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
  }

  /// Sends synchronization event via direct UNICAST to all registered joiners,
  /// plus a subnet broadcast fallback.
  static void sendSyncEvent(String event, Map<String, dynamic> payload) {
    if (_socket == null || _currentPartyCode == null) return;
    try {
      final message = _encodePacket(event, payload);
      final bytes = utf8.encode(message);

      // 1. Direct unicast to every registered joiner
      if (_isHost) {
        for (final peer in _registeredJoiners.values) {
          try {
            _socket?.send(bytes, peer.address, peer.port);
          } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
        }
      }

      // 2. Directed subnet broadcast fallback
      for (final bcast in _broadcastAddresses) {
        try {
          _socket?.send(bytes, bcast, defaultPort);
        } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
      }
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
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
      final message = _encodePacket(event, payload);
      final bytes = utf8.encode(message);
      _socket?.send(bytes, dest, destPort);
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
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
      if (json == null || _currentPartyCode == null) return;

      if (!verifyIncomingPacket(
        json,
        expectedCode: _currentPartyCode!,
        expectedRoomToken: _roomToken,
      )) {
        return;
      }

      final event = json['event']?.toString() ?? '';
      final payload = Map<String, dynamic>.from(json['payload'] as Map);

      // 1. Host Discovery Beacon (Joiner detects host on local Wi-Fi)
      if (event == 'host_beacon' && !_isHost) {
        final wasUnset = _discoveredHostAddress == null;
        _discoveredHostAddress = datagram.address;
        _discoveredHostPort = (payload['port'] as num?)?.toInt() ?? defaultPort;
        _recordLanActivity();
        if (wasUnset && _selfClientId != null) {
          // Immediately send burst of 4 LAN NTP pings to lock clock (< 50ms)
          for (int i = 0; i < 4; i++) {
            Future.delayed(Duration(milliseconds: i * 40), () {
              if (_discoveredHostAddress != null && _selfClientId != null) {
                sendLanNtpPing(DateTime.now().millisecondsSinceEpoch, _selfClientId!);
              }
            });
          }
        }
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
        payload['isLan'] = true;
        onNtpPongReceived?.call(payload);
        return;
      }

      // 5. Synchronized Playback Events (sync_play, sync_prepare, sync_pause, sync_seek, sync_heartbeat, peer_ready, request_state)
      if (!_isHost || event == 'peer_ready' || event == 'request_state') {
        _recordLanActivity();
        onSyncEventReceived?.call(event, payload);
      }
    } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
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
    _roomToken = null;
    _isHost = false;
    _lastLanActivityEpochMs = 0;
    _registeredJoiners.clear();
    isLanActiveNotifier.value = false;

    if (_socket != null) {
      try {
        _socket?.close();
      } catch (e) {
      AppLogger.debug('PartyLanAccelerator', 'Handled exception: $e');
    }
      _socket = null;
    }
  }
}
