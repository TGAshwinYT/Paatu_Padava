part of '../party_sync_coordinator.dart';

void _handleNtpPongImpl(
  Map<String, dynamic> payload,
  RealtimeChannel? channel,
  PeerDeviceInfo selfPeer,
) {
  final recipientId = payload['recipientId']?.toString();
  if (recipientId != PartySyncCoordinator._clientId) return;

  final t3 = DateTime.now().millisecondsSinceEpoch;
  final t0 = (payload['t0'] as num?)?.toInt();
  final t1 = (payload['t1'] as num?)?.toInt();
  final t2 = (payload['t2'] as num?)?.toInt();
  final isRolling = payload['isRolling'] == true;
  final isLan = payload['isLan'] == true;

  if (t0 != null && t1 != null && t2 != null) {
    final sample = NtpSample(t0: t0, t1: t1, t2: t2, t3: t3, isLan: isLan);
    if (isLan) {
      PartySyncCoordinator._ntpSamples.removeWhere((s) => !s.isLan);
    }
    PartySyncCoordinator._ntpSamples.add(sample);
    while (PartySyncCoordinator._ntpSamples.length > 16) {
      PartySyncCoordinator._ntpSamples.removeAt(0);
    }

    final offset = NtpCalculator.calculateOffset(
      PartySyncCoordinator._ntpSamples,
      previousOffset: PartySyncCoordinator.clockOffsetMsNotifier.value,
    );
    PartySyncCoordinator.clockOffsetMsNotifier.value = offset;
    if (isLan || !PartyLanAccelerator.isLanActiveNotifier.value) {
      PartySyncCoordinator.measuredRttMsNotifier.value = sample.rtt;
    }

    if (!isRolling) {
      PartySyncCoordinator.syncStatusDescription.value =
          'In Sync (RTT: ${sample.rtt}ms, Offset: ${offset}ms)';
    }

    PartySyncCoordinator._knownPeers[PartySyncCoordinator._clientId] =
        selfPeer.copyWith(rttMs: sample.rtt);
    PartySyncCoordinator.connectedPeersNotifier.value =
        PartySyncCoordinator._knownPeers.values.toList();
    channel?.sendBroadcastMessage(
      event: 'peer_presence',
      payload: {
        'id': PartySyncCoordinator._clientId,
        'deviceName': PartySyncCoordinator.localDeviceName,
        'role': 'Speaker',
        'rttMs': sample.rtt,
        'token': PartySyncCoordinator._sessionSecret,
      },
    );
  }
}

void _startNtpHandshakeImpl(RealtimeChannel channel) {
  PartySyncCoordinator._ntpSamples.clear();
  int pingsSent = 0;

  PartySyncCoordinator._ntpHandshakeTimer?.cancel();
  PartySyncCoordinator._ntpHandshakeTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
    if (PartySyncCoordinator.role != PartyRole.joiner || PartySyncCoordinator._partyChannel == null) {
      timer.cancel();
      return;
    }

    final t0 = DateTime.now().millisecondsSinceEpoch;
    channel.sendBroadcastMessage(
      event: 'ntp_ping',
      payload: {
        't0': t0,
        'senderId': PartySyncCoordinator._clientId,
        'isRolling': false,
        'token': PartySyncCoordinator._sessionSecret,
      },
    );
    PartyLanAccelerator.sendLanNtpPing(t0, PartySyncCoordinator._clientId);

    pingsSent++;
    if (pingsSent >= 8) {
      timer.cancel();
      _startRollingNtpImpl(channel);
    }
  });
}

void _startRollingNtpImpl(RealtimeChannel channel) {
  PartySyncCoordinator._rollingNtpTimer?.cancel();
  int pingsSent = 0;

  PartySyncCoordinator._rollingNtpTimer = Timer.periodic(const Duration(milliseconds: 3000), (timer) {
    if (PartySyncCoordinator.role != PartyRole.joiner || PartySyncCoordinator._partyChannel == null) {
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
          'senderId': PartySyncCoordinator._clientId,
          'isRolling': true,
          'token': PartySyncCoordinator._sessionSecret,
        },
      );
    }
    PartyLanAccelerator.sendLanNtpPing(t0, PartySyncCoordinator._clientId, isRolling: true);
  });
}
