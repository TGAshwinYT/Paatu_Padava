part of '../party_sync_coordinator.dart';

Future<String?> _startPartyImpl({String? pin}) async {
  final client = SupabaseService.client;
  await PartySyncCoordinator.leaveParty();
  await SyncPlatform.acquireWifiLocks();

  final code = PartySyncCoordinator.generatePartyCode();
  final effectivePin = (pin != null && pin.trim().isNotEmpty)
      ? pin.trim()
      : (1000 + PartySyncCoordinator._random.nextInt(9000)).toString();
  PartySyncCoordinator._sessionSecret = PartySyncCoordinator.deriveRoomToken(code, effectivePin);
  PartySyncCoordinator._currentHostSeq = 0;
  PartySyncCoordinator._lastProcessedSeq = 0;
  PartySyncCoordinator._localIps = await PartyLanAccelerator.getLocalIpAddresses();

  PartySyncCoordinator.partyCodeNotifier.value = code;
  PartySyncCoordinator.partyPinNotifier.value = effectivePin;
  PartySyncCoordinator.roleNotifier.value = PartyRole.host;
  PartySyncCoordinator.clockOffsetMsNotifier.value = 0;
  PartySyncCoordinator.currentDriftMsNotifier.value = 0;

  final selfPeer = PeerDeviceInfo(
    id: PartySyncCoordinator._clientId,
    deviceName: '${PartySyncCoordinator.localDeviceName} (Host)',
    role: 'Host',
    rttMs: 0,
    lastSeen: DateTime.now(),
    isSelf: true,
  );
  PartySyncCoordinator._knownPeers.clear();
  PartySyncCoordinator._knownPeers[PartySyncCoordinator._clientId] = selfPeer;
  PartySyncCoordinator.connectedPeersNotifier.value = [selfPeer];
  PartySyncCoordinator.peerCountNotifier.value = 1;

  if (client != null) {
    PartySyncCoordinator.syncStatusDescription.value = 'Hosting Party ($code)';
    final channel = client.channel('party:$code');

    channel.onBroadcast(
      event: 'ntp_ping',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
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
              'token': PartySyncCoordinator._sessionSecret,
            },
          );
        }
      },
    );

    channel.onBroadcast(
      event: 'peer_join',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        final peerId = payload['peerId']?.toString();
        final devName = payload['deviceName']?.toString() ?? 'Guest Phone';
        final peerLanIps = (payload['lanIps'] as List<dynamic>?)?.map((e) => e.toString()).toList();
        final peerPort = (payload['lanPort'] as num?)?.toInt() ?? PartyLanAccelerator.defaultPort;
        if (peerId != null) {
          PartySyncCoordinator._knownPeers[peerId] = PeerDeviceInfo(
            id: peerId,
            deviceName: devName,
            role: 'Speaker',
            rttMs: 0,
            lastSeen: DateTime.now(),
          );
          PartySyncCoordinator.connectedPeersNotifier.value =
              PartySyncCoordinator._knownPeers.values.toList();
          PartySyncCoordinator.peerCountNotifier.value =
              PartySyncCoordinator._knownPeers.length;

          if (peerLanIps != null && peerLanIps.isNotEmpty) {
            for (final ip in peerLanIps) {
              PartyLanAccelerator.registerPeerAddress(peerId, ip, peerPort);
            }
          }
        }
        PartySyncCoordinator._broadcastCurrentState();
      },
    );

    channel.onBroadcast(
      event: 'peer_presence',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        final peerId = payload['id']?.toString();
        final devName = payload['deviceName']?.toString() ?? 'Guest Phone';
        final rtt = (payload['rttMs'] as num?)?.toInt() ?? 0;
        if (peerId != null && peerId != PartySyncCoordinator._clientId) {
          PartySyncCoordinator._knownPeers[peerId] = PeerDeviceInfo(
            id: peerId,
            deviceName: devName,
            role: 'Speaker',
            rttMs: rtt,
            lastSeen: DateTime.now(),
          );
          PartySyncCoordinator.connectedPeersNotifier.value =
              PartySyncCoordinator._knownPeers.values.toList();
          PartySyncCoordinator.peerCountNotifier.value =
              PartySyncCoordinator._knownPeers.length;
        }
      },
    );

    channel.onBroadcast(
      event: 'peer_leave',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        final peerId = payload['id']?.toString();
        if (peerId != null) {
          PartySyncCoordinator._knownPeers.remove(peerId);
          PartySyncCoordinator.connectedPeersNotifier.value =
              PartySyncCoordinator._knownPeers.values.toList();
          PartySyncCoordinator.peerCountNotifier.value =
              PartySyncCoordinator._knownPeers.length;
          PartySyncCoordinator._broadcastCurrentState();
        }
      },
    );

    channel.onBroadcast(
      event: 'request_state',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        PartySyncCoordinator._broadcastCurrentState();
      },
    );

    channel.onBroadcast(
      event: 'peer_ready',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        PartySyncCoordinator._handlePeerReady(payload);
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

    PartySyncCoordinator._partyChannel = channel;
  } else {
    PartySyncCoordinator.syncStatusDescription.value = 'Hosting Party (Wi-Fi Only - $code)';
  }

  PartyLanAccelerator.onSyncEventReceived = (event, payload) async {
    if (event == 'peer_ready') {
      PartySyncCoordinator._handlePeerReady(payload);
    } else if (event == 'request_state') {
      PartySyncCoordinator._broadcastCurrentState();
    }
  };
  PartyLanAccelerator.startHost(
    code,
    clientId: PartySyncCoordinator._clientId,
    roomToken: PartySyncCoordinator._sessionSecret,
  );

  PartySyncCoordinator._hostHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
    final now = DateTime.now();
    final initialCount = PartySyncCoordinator._knownPeers.length;
    PartySyncCoordinator._knownPeers.removeWhere((id, peer) {
      if (peer.isSelf) return false;
      return now.difference(peer.lastSeen).inSeconds > 14;
    });
    if (PartySyncCoordinator._knownPeers.length != initialCount) {
      PartySyncCoordinator.connectedPeersNotifier.value =
          PartySyncCoordinator._knownPeers.values.toList();
      PartySyncCoordinator.peerCountNotifier.value =
          PartySyncCoordinator._knownPeers.length;
    }

    if (PartySyncCoordinator.role != PartyRole.host) return;
    final curSong = audioHandler.currentSong;
    final isPlaying = audioHandler.playbackState.value.playing;
    final posMs = audioHandler.player.position.inMilliseconds;
    final nowMs = now.millisecondsSinceEpoch;
    final seq = ++PartySyncCoordinator._currentHostSeq;

    final heartbeatPayload = {
      'seq': seq,
      'token': PartySyncCoordinator._sessionSecret,
      'songId': curSong?.id,
      'positionMs': posMs,
      'referenceHostEpochMs': nowMs,
      'referencePositionMs': posMs,
      'isPlaying': isPlaying,
    };

    PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
      event: 'sync_heartbeat',
      payload: heartbeatPayload,
    );
    PartyLanAccelerator.sendSyncEvent('sync_heartbeat', heartbeatPayload);
  });

  return code;
}

Future<void> _leavePartyImpl() async {
  PartySyncCoordinator._cancelPendingScheduledOperations();

  if (isAudioHandlerInitialized) {
    try {
      audioHandler.setSpeed(1.0);
    } catch (e) {
      AppLogger.debug('PartySyncCoordinator', 'Could not reset playback speed: $e');
    }
  }

  PartySyncCoordinator._hostHeartbeatTimer?.cancel();
  PartySyncCoordinator._hostHeartbeatTimer = null;
  PartySyncCoordinator._ntpHandshakeTimer?.cancel();
  PartySyncCoordinator._ntpHandshakeTimer = null;
  PartySyncCoordinator._rollingNtpTimer?.cancel();
  PartySyncCoordinator._rollingNtpTimer = null;
  PartyLanAccelerator.onSyncEventReceived = null;
  PartyLanAccelerator.onNtpPongReceived = null;
  PartyLanAccelerator.onNtpPingReceived = null;
  await PartyLanAccelerator.stop();
  await SyncPlatform.releaseWifiLocks();

  if (PartySyncCoordinator._partyChannel != null) {
    try {
      if (PartySyncCoordinator.isHost) {
        PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
          event: 'party_ended',
          payload: {'hostId': PartySyncCoordinator._clientId, 'token': PartySyncCoordinator._sessionSecret},
        );
      } else {
        PartySyncCoordinator._partyChannel?.sendBroadcastMessage(
          event: 'peer_leave',
          payload: {'id': PartySyncCoordinator._clientId, 'token': PartySyncCoordinator._sessionSecret},
        );
      }
      SupabaseService.client?.removeChannel(PartySyncCoordinator._partyChannel!);
    } catch (e) {
      AppLogger.log('PartySyncCoordinator', 'Remove channel notice: $e');
    }
    PartySyncCoordinator._partyChannel = null;
  }

  if (isAudioHandlerInitialized) {
    try {
      audioHandler.setSpeed(1.0);
    } catch (e) {
      AppLogger.debug('PartySyncCoordinator', 'Could not reset playback speed: $e');
    }
  }

  PartySyncCoordinator.roleNotifier.value = PartyRole.none;
  PartySyncCoordinator.partyCodeNotifier.value = null;
  PartySyncCoordinator.partyPinNotifier.value = null;
  PartySyncCoordinator._sessionSecret = '';
  PartySyncCoordinator.clockOffsetMsNotifier.value = 0;
  PartySyncCoordinator.measuredRttMsNotifier.value = 0;
  PartySyncCoordinator.currentDriftMsNotifier.value = 0;
  PartySyncCoordinator.peerCountNotifier.value = 0;
  PartySyncCoordinator._knownPeers.clear();
  PartySyncCoordinator.connectedPeersNotifier.value = [];
  PartySyncCoordinator.syncStatusDescription.value = 'Idle';
  PartySyncCoordinator._ntpSamples.clear();
  PartySyncCoordinator._processedEventKeys.clear();
  PartySyncCoordinator._processedCmdIds.clear();
  PartySyncCoordinator._peerReadyCompleter = null;
  PartySyncCoordinator._pendingPrepareCmdId = null;
  PartySyncCoordinator._lastProcessedSeq = 0;
  PartySyncCoordinator._currentHostSeq = 0;
}

String _optimizeStreamUrlForNetworkImpl(String url) {
  if (url.isEmpty) return url;
  final isLan = PartyLanAccelerator.isLanActiveNotifier.value;
  final rtt = PartySyncCoordinator.measuredRttMsNotifier.value;
  if (!isLan && (rtt > 120 || rtt == 0)) {
    if (url.contains('_320.mp4')) {
      return url.replaceAll('_320.mp4', '_96.mp4');
    }
  }
  return url;
}

void _handlePeerReadyImpl(Map<String, dynamic> payload) {
  final peerId = payload['peerId']?.toString();
  final cmdId = payload['cmdId']?.toString();
  if (peerId != null && PartySyncCoordinator._knownPeers.containsKey(peerId)) {
    PartySyncCoordinator._knownPeers[peerId] =
        PartySyncCoordinator._knownPeers[peerId]!.copyWith(lastSeen: DateTime.now());
  }
  if (PartySyncCoordinator._pendingPrepareCmdId != null &&
      cmdId == PartySyncCoordinator._pendingPrepareCmdId) {
    if (PartySyncCoordinator._peerReadyCompleter != null &&
        !PartySyncCoordinator._peerReadyCompleter!.isCompleted) {
      PartySyncCoordinator._peerReadyCompleter!.complete();
    }
  } else {
    AppLogger.debug('PartySyncCoordinator',
        'Ignoring stale or mismatched peer_ready ACK (received: $cmdId, active: ${PartySyncCoordinator._pendingPrepareCmdId})');
  }
}

bool _shouldProcessEventImpl(String event, Map<String, dynamic> payload) {
  final cmdId = payload['cmdId']?.toString();
  if (cmdId != null && cmdId.isNotEmpty) {
    if (PartySyncCoordinator._processedCmdIds.contains(cmdId)) return false;
    PartySyncCoordinator._processedCmdIds.add(cmdId);
    if (PartySyncCoordinator._processedCmdIds.length > 100) {
      PartySyncCoordinator._processedCmdIds.remove(PartySyncCoordinator._processedCmdIds.first);
    }
    return true;
  }

  final seq = (payload['seq'] as num?)?.toInt();
  final hasPayload = payload['song'] != null || payload['streamUrl'] != null;

  final key = '${event}_${payload['seq']}_${payload['startAtEpochMs']}_${payload['positionMs']}_${payload['songId']}_$hasPayload';
  if (PartySyncCoordinator._processedEventKeys.contains(key)) return false;
  PartySyncCoordinator._processedEventKeys.add(key);
  if (PartySyncCoordinator._processedEventKeys.length > 50) {
    PartySyncCoordinator._processedEventKeys.remove(PartySyncCoordinator._processedEventKeys.first);
  }

  if (seq != null) {
    if (seq < PartySyncCoordinator._lastProcessedSeq) {
      return false;
    }
    if (seq == PartySyncCoordinator._lastProcessedSeq && !hasPayload) {
      return false;
    }
    PartySyncCoordinator._lastProcessedSeq = seq;
  }

  return true;
}
