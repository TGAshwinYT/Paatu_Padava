import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'player_handler.dart';

/// Cross-platform Discord Rich Presence (RPC) & Local Activity Service.
/// Communicates via local IPC sockets to display real-time listening status:
/// "Listening to [Song Title] by [Artist] on Paatu Paadava".
class DiscordRpcService {
  static const String _defaultClientId = '123456789012345678'; // Paatu Padava Discord Application ID
  static bool _isEnabled = true;
  static Socket? _socket;
  static bool _isConnected = false;

  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Initializes the Discord RPC service and hooks into player state changes
  static void init({String clientId = _defaultClientId}) {
    if (!isSupportedPlatform || !_isEnabled) return;

    // Listen to track changes
    audioHandler.currentSongNotifier.addListener(() {
      final current = audioHandler.currentSong;
      if (current != null && audioHandler.player.playing) {
        updatePresence(song: current, isPlaying: true);
      } else {
        clearPresence();
      }
    });

    // Listen to play/pause transitions
    audioHandler.player.playerStateStream.listen((state) {
      final current = audioHandler.currentSong;
      if (current != null) {
        updatePresence(song: current, isPlaying: state.playing);
      } else {
        clearPresence();
      }
    });
  }

  /// Sends updated Rich Presence payload to Discord IPC socket
  static Future<void> updatePresence({
    required Song song,
    required bool isPlaying,
    int? positionSeconds,
  }) async {
    if (!isSupportedPlatform || !_isEnabled) return;

    try {
      if (_socket == null || !_isConnected) {
        await _connect();
      }

      if (_socket == null || !_isConnected) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final startEpoch = nowMs - ((positionSeconds ?? audioHandler.player.position.inSeconds) * 1000);
      final endEpoch = song.duration > 0 ? startEpoch + (song.duration * 1000) : null;

      final detailsText = song.title.length > 128 ? '${song.title.substring(0, 125)}...' : song.title;
      final byArtist = 'by ${song.artist}';
      final stateText = byArtist.length > 128 ? '${byArtist.substring(0, 125)}...' : byArtist;

      final activity = <String, dynamic>{
        'details': detailsText,
        'state': stateText,
        'assets': {
          'large_image': song.coverUrl.isNotEmpty ? song.coverUrl : 'paatu_logo',
          'large_text': song.album.isNotEmpty ? song.album : 'Paatu Paadava Lossless',
          'small_image': isPlaying ? 'play_icon' : 'pause_icon',
          'small_text': isPlaying ? 'Playing' : 'Paused',
        },
      };

      if (isPlaying) {
        final timestamps = <String, dynamic>{
          'start': (startEpoch / 1000).round(),
        };
        if (endEpoch != null) {
          timestamps['end'] = (endEpoch / 1000).round();
        }
        activity['timestamps'] = timestamps;
      }

      final payload = {
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': pid,
          'activity': activity,
        },
        'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      _sendFrame(opCode: 1, jsonPayload: payload);
    } catch (e) {
      debugPrint('[DiscordRpcService] updatePresence notice: $e');
      _isConnected = false;
      _socket = null;
    }
  }

  /// Clears active presence when playback stops
  static Future<void> clearPresence() async {
    if (!isSupportedPlatform || _socket == null || !_isConnected) return;

    try {
      final payload = {
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': pid,
          'activity': null,
        },
        'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      _sendFrame(opCode: 1, jsonPayload: payload);
    } catch (_) {
      _isConnected = false;
      _socket = null;
    }
  }

  static Future<void> _connect() async {
    for (int i = 0; i < 10; i++) {
      try {
        final pipePath = Platform.isWindows
            ? '\\\\.\\pipe\\discord-ipc-$i'
            : (Platform.environment['XDG_RUNTIME_DIR'] != null
                ? '${Platform.environment['XDG_RUNTIME_DIR']}/discord-ipc-$i'
                : '/tmp/discord-ipc-$i');

        Socket? socket;
        try {
          socket = await Socket.connect(
            InternetAddress(pipePath, type: InternetAddressType.unix),
            0,
            timeout: const Duration(milliseconds: 200),
          );
        } catch (_) {}

        if (socket != null) {
          _socket = socket;
          _isConnected = true;

          // Handshake opcode 0
          _sendFrame(opCode: 0, jsonPayload: {
            'v': 1,
            'client_id': _defaultClientId,
          });

          _socket!.listen(
            (data) {},
            onError: (err) {
              _isConnected = false;
              _socket = null;
            },
            onDone: () {
              _isConnected = false;
              _socket = null;
            },
          );
          return;
        }
      } catch (_) {}
    }
  }

  static void _sendFrame({required int opCode, required Map<String, dynamic> jsonPayload}) {
    if (_socket == null) return;
    try {
      final jsonBytes = utf8.encode(json.encode(jsonPayload));
      final header = ByteData(8);
      header.setUint32(0, opCode, Endian.little);
      header.setUint32(4, jsonBytes.length, Endian.little);

      _socket!.add(header.buffer.asUint8List());
      _socket!.add(jsonBytes);
      _socket!.flush();
    } catch (_) {
      _isConnected = false;
      _socket = null;
    }
  }

  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      clearPresence();
    }
  }
}
