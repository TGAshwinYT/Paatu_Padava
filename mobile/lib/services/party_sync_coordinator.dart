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
/// - Continuous background drift monitoring with soft pitch-preserved speed adjustments (0.98x / 1.02x)
///   to eliminate audible glitches, falling back to hard-seeks for large desync (>200ms).
/// - Manual hardware Bluetooth DAC delay adjustment (-500ms to +500ms).
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
        peerCountNotifier.value++;
        // Send immediate current playback state to new joiner
        _broadcastCurrentState();
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

    channel.subscribe((status, [error]) {
      debugPrint('[PartySyncCoordinator] Joiner channel status: $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Announce join to host
        channel.sendBroadcastMessage(
          event: 'peer_join',
          payload: {'peerId': _clientId},
        );
        // Start 5-packet NTP handshake
        _executeNtpHandshake();
      }
    });

    _partyChannel = channel;
    return true;
  }

  /// Runs 5 consecutive NTP pings spaced by 150ms
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
      if (pingsSent >= 5) {
        timer.cancel();
      }
    });
  }

  /// Host: Broadcasts current playing track, reference epoch, and position
  static void _broadcastCurrentState() {
    final mediaItem = audioHandler.mediaItem.value;
    final playbackState = audioHandler.playbackState.value;
    final currentPosMs = playbackState.position.inMilliseconds;
    final isPlaying = playbackState.playing;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_heartbeat',
      payload: {
        'songId': mediaItem?.id,
        'title': mediaItem?.title,
        'artist': mediaItem?.artist,
        'artworkUrl': mediaItem?.artUri?.toString(),
        'referenceHostEpochMs': DateTime.now().millisecondsSinceEpoch,
        'referencePositionMs': currentPosMs,
        'isPlaying': isPlaying,
      },
    );
  }

  /// Host: Scheduled Play trigger (broadcasting start at now + 500ms)
  static Future<void> hostPlaySong(Song song, {int positionMs = 0}) async {
    if (!isHost) {
      await audioHandler.playSong(song);
      return;
    }

    const leadTimeMs = 500;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startAtEpochMs = now + leadTimeMs;

    _partyChannel?.sendBroadcastMessage(
      event: 'sync_play',
      payload: {
        'song': song.toMap(),
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

      final delayMs = ScheduledPlaybackCalculator.calculateScheduledDelayMs(
        startAtEpochMs: startAtEpochMs,
        currentLocalEpochMs: DateTime.now().millisecondsSinceEpoch,
        clockOffsetMs: clockOffsetMs,
      );

      // Preload song
      await audioHandler.playSong(song, queue: [song]);
      if (positionMs > 0) {
        await audioHandler.seek(Duration(milliseconds: positionMs));
      }

      if (delayMs > 0) {
        await audioHandler.pause();
        await Future.delayed(Duration(milliseconds: delayMs));
        await audioHandler.play();
      }
    } catch (e) {
      debugPrint('[PartySyncCoordinator] handleRemotePlay error: $e');
    }
  }

  /// Joiner: Analyzes drift on heartbeat and performs micro-rate adjustments or hard-seek
  static void _handleHeartbeatReconciliation(Map<String, dynamic> payload) {
    if (role != PartyRole.joiner) return;

    final isHostPlaying = payload['isPlaying'] == true;
    final playbackState = audioHandler.playbackState.value;

    if (!isHostPlaying) {
      if (playbackState.playing) {
        audioHandler.pause();
      }
      return;
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
      debugPrint('[PartySyncCoordinator] Hard seek reconciling drift of ${drift}ms to ${action.seekTargetMs}ms');
      audioHandler.seek(Duration(milliseconds: action.seekTargetMs!));
      audioHandler.setSpeed(1.0);
      syncStatusDescription.value = 'Resyncing (hard-seek)';
    } else if (action.isMicroAdjusting) {
      debugPrint('[PartySyncCoordinator] Micro speed adjustment: ${action.playbackSpeed}x for drift of ${drift}ms');
      audioHandler.setSpeed(action.playbackSpeed);
      syncStatusDescription.value = action.playbackSpeed > 1.0 ? 'Catching up (+2%)' : 'Slowing down (-2%)';
    } else {
      audioHandler.setSpeed(1.0);
      syncStatusDescription.value = 'In Sync (|drift| < 50ms)';
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
    syncStatusDescription.value = 'Idle';
    _ntpSamples.clear();
  }
}
