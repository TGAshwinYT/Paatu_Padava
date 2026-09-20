import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'package:flutter/foundation.dart';
import 'download_manager.dart';
import 'saavn_client.dart';
import 'youtube_client.dart';

late PaatuAudioHandler audioHandler;

class PaatuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier<Song?>(null);
  List<Song> _playlist = [];
  int _currentIndex = -1;

  AudioPlayer get player => _player;
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_currentIndex >= 0 && _currentIndex < _playlist.length) ? _playlist[_currentIndex] : null;

  PaatuAudioHandler() {
    _initStreams();
  }

  void _initStreams() {
    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ));
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  Future<void> playSong(Song song, {List<Song>? queue}) async {
    if (queue != null && queue.isNotEmpty) {
      _playlist = List.from(queue);
      _currentIndex = _playlist.indexWhere((s) => s.id == song.id);
      if (_currentIndex == -1) {
        _playlist.insert(0, song);
        _currentIndex = 0;
      }
    } else {
      _playlist = [song];
      _currentIndex = 0;
    }

    await _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(Song song) async {
    try {
      currentSongNotifier.value = song;

      // 1. Check if offline file exists
      if (song.localFilePath != null && File(song.localFilePath!).existsSync()) {
        await _player.setAudioSource(AudioSource.file(song.localFilePath!));
      } else if (DownloadManager.isDownloaded(song.id)) {
        final downloadedSongs = DownloadManager.getDownloadedSongs();
        final match = downloadedSongs.firstWhere((s) => s.id == song.id, orElse: () => song);
        if (match.localFilePath != null && File(match.localFilePath!).existsSync()) {
          await _player.setAudioSource(AudioSource.file(match.localFilePath!));
        } else {
          await _resolveRemoteAndPlay(song);
        }
      } else {
        await _resolveRemoteAndPlay(song);
      }

      // Update System Notification MediaItem
      mediaItem.add(MediaItem(
        id: song.id,
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: Duration(seconds: song.duration),
        artUri: Uri.tryParse(song.coverUrl),
      ));

      await _player.play();
    } catch (e) {
      // If playback fails, advance to next
      skipToNext();
    }
  }

  Future<void> _resolveRemoteAndPlay(Song song) async {
    String? streamUrl = song.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) {
      if (song.source == 'youtube') {
        streamUrl = await YouTubeClient.getAudioStreamUrl(song.id);
      } else {
        final matches = await SaavnClient.search('${song.title} ${song.artist}', limit: 1);
        if (matches.isNotEmpty) {
          streamUrl = matches.first.streamUrl;
        }
      }
    }

    if (streamUrl != null && streamUrl.isNotEmpty) {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
    } else {
      throw Exception("Could not resolve stream URL");
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    currentSongNotifier.value = null;
    await _player.stop();
    await super.stop();
  }

  Future<void> setShuffle(bool enable) async {
    await _player.setShuffleModeEnabled(enable);
  }

  Future<void> toggleLoopMode() async {
    final current = _player.loopMode;
    if (current == LoopMode.off) {
      await _player.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      await _player.setLoopMode(LoopMode.one);
    } else {
      await _player.setLoopMode(LoopMode.off);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex + 1 < _playlist.length) {
      _currentIndex++;
      await _loadAndPlay(_playlist[_currentIndex]);
    } else {
      // End of playlist
      await _player.stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlay(_playlist[_currentIndex]);
    } else {
      await _player.seek(Duration.zero);
    }
  }
}
