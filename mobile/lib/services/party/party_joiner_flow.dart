part of '../party_sync_coordinator.dart';

Future<bool> _joinPartyImpl(String rawCode, {String? pin}) async {
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

  await PartySyncCoordinator.leaveParty();
  await SyncPlatform.acquireWifiLocks();
  PartySyncCoordinator._localIps = await PartyLanAccelerator.getLocalIpAddresses();

  final roomToken = PartySyncCoordinator.deriveRoomToken(cleanCode, effectivePin);
  PartySyncCoordinator._sessionSecret = roomToken;
  PartySyncCoordinator.partyCodeNotifier.value = cleanCode;
  PartySyncCoordinator.partyPinNotifier.value = effectivePin;
  PartySyncCoordinator.roleNotifier.value = PartyRole.joiner;
  PartySyncCoordinator.clockOffsetMsNotifier.value = 0;
  PartySyncCoordinator.measuredRttMsNotifier.value = 0;
  PartySyncCoordinator.currentDriftMsNotifier.value = 0;
  PartySyncCoordinator._lastProcessedSeq = 0;
  PartySyncCoordinator.syncStatusDescription.value = client != null
      ? 'Connecting to $cleanCode...'
      : 'Searching for $cleanCode on Wi-Fi...';

  final selfPeer = PeerDeviceInfo(
    id: PartySyncCoordinator._clientId,
    deviceName: PartySyncCoordinator.localDeviceName,
    role: 'Speaker',
    rttMs: 0,
    lastSeen: DateTime.now(),
    isSelf: true,
  );
  PartySyncCoordinator._knownPeers.clear();
  PartySyncCoordinator._knownPeers[PartySyncCoordinator._clientId] = selfPeer;
  PartySyncCoordinator.connectedPeersNotifier.value = [selfPeer];
  PartySyncCoordinator.peerCountNotifier.value = 1;

  final channel = client?.channel('party:$cleanCode');

  // Hook direct local Wi-Fi UDP acceleration
  PartyLanAccelerator.onNtpPongReceived = (payload) {
    PartySyncCoordinator._handleNtpPong(payload, channel, selfPeer);
  };

  PartyLanAccelerator.onSyncEventReceived = (event, payload) async {
    if (!PartySyncCoordinator._shouldProcessEvent(event, payload)) return;
    switch (event) {
      case 'sync_prepare':
        await PartySyncCoordinator._handleRemotePrepare(payload);
        break;
      case 'sync_prepare_next':
        await PartySyncCoordinator._handleRemotePrepareNext(payload);
        break;
      case 'sync_play':
        await PartySyncCoordinator._handleRemotePlay(payload);
        break;
      case 'sync_pause':
        PartySyncCoordinator._handleRemotePause(payload);
        break;
      case 'sync_seek':
        await PartySyncCoordinator._handleRemoteSeek(payload);
        break;
      case 'sync_heartbeat':
        PartySyncCoordinator._handleHeartbeatReconciliation(payload);
        break;
      case 'sync_queue':
        await PartySyncCoordinator._handleRemoteQueue(payload);
        break;
    }
  };

  PartyLanAccelerator.startJoiner(cleanCode, clientId: PartySyncCoordinator._clientId, roomToken: roomToken);

  if (channel != null) {
    channel.onBroadcast(
      event: 'ntp_pong',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        PartySyncCoordinator._handleNtpPong(payload, channel, selfPeer);
      },
    );

    channel.onBroadcast(
      event: 'sync_prepare',
      callback: (payload) async {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_prepare', payload)) return;
        await PartySyncCoordinator._handleRemotePrepare(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_prepare_next',
      callback: (payload) async {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_prepare_next', payload)) return;
        await PartySyncCoordinator._handleRemotePrepareNext(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_queue',
      callback: (payload) async {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_queue', payload)) return;
        await PartySyncCoordinator._handleRemoteQueue(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_play',
      callback: (payload) async {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_play', payload)) return;
        await PartySyncCoordinator._handleRemotePlay(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_pause',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_pause', payload)) return;
        PartySyncCoordinator._handleRemotePause(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_seek',
      callback: (payload) async {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_seek', payload)) return;
        await PartySyncCoordinator._handleRemoteSeek(payload);
      },
    );

    channel.onBroadcast(
      event: 'sync_heartbeat',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        if (!PartySyncCoordinator._shouldProcessEvent('sync_heartbeat', payload)) return;
        PartySyncCoordinator._handleHeartbeatReconciliation(payload);
      },
    );

    channel.onBroadcast(
      event: 'party_ended',
      callback: (payload) {
        if (!PartySyncCoordinator._isValidSessionPayload(payload)) return;
        PartySyncCoordinator.leaveParty();
        PartySyncCoordinator.syncStatusDescription.value = 'Host ended party session';
      },
    );

    channel.subscribe((status, [error]) {
      debugPrint('[PartySyncCoordinator] Joiner channel status: $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        channel.sendBroadcastMessage(
          event: 'peer_join',
          payload: {
            'peerId': PartySyncCoordinator._clientId,
            'deviceName': PartySyncCoordinator.localDeviceName,
            'lanIps': PartySyncCoordinator._localIps,
            'lanPort': PartyLanAccelerator.defaultPort,
            'token': PartySyncCoordinator._sessionSecret,
          },
        );
        channel.sendBroadcastMessage(
          event: 'request_state',
          payload: {'senderId': PartySyncCoordinator._clientId, 'token': PartySyncCoordinator._sessionSecret},
        );
        PartyLanAccelerator.sendDirect('request_state', {'senderId': PartySyncCoordinator._clientId, 'token': PartySyncCoordinator._sessionSecret});

        PartySyncCoordinator._startNtpHandshake(channel);
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

    PartySyncCoordinator._partyChannel = channel;
  } else {
    PartyLanAccelerator.sendDirect('request_state', {'senderId': PartySyncCoordinator._clientId, 'token': PartySyncCoordinator._sessionSecret});
  }

  return true;
}
