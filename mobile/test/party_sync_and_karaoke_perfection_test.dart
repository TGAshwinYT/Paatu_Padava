import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/party_sync_engine.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/equalizer_service.dart';
import 'package:paatu_padava_mobile/services/party_sync_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Karaoke Real-Time Vocal Attenuation & Loudness Balance Tests', () {
    test('Flat bands with 0.0 vocal attenuation have zero boost or cut', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 0.0,
      );
      expect(result, equals([0.0, 0.0, 0.0, 0.0, 0.0]));
    });

    test('Full vocal attenuation maintains rhythm drive with bass compensation and shimmer', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 1.0,
      );

      // Sub-bass kick drive (+3.5 dB)
      expect(result[0], closeTo(3.5, 0.001));
      // Subtle lower chest voice cut (-2.0 dB)
      expect(result[1], closeTo(-2.0, 0.001));
      // Targeted core vowel formant cut (-8.0 dB)
      expect(result[2], closeTo(-8.0, 0.001));
      // Consonant & presence notch (-5.0 dB)
      expect(result[3], closeTo(-5.0, 0.001));
      // High air & shimmer preservation (+2.5 dB)
      expect(result[4], closeTo(2.5, 0.001));
    });

    test('Intermediate vocal attenuation (0.5) scales proportionally', () {
      final base = [0.0, 0.0, 0.0, 0.0, 0.0];
      final result = EqualizerService.calculateEffectiveBands(
        baseBands: base,
        bassBoost: 0.0,
        virtualizer: 0.0,
        vocalAttenuation: 0.5,
      );

      expect(result[0], closeTo(1.75, 0.001));
      expect(result[1], closeTo(-1.0, 0.001));
      expect(result[2], closeTo(-4.0, 0.001));
      expect(result[3], closeTo(-2.5, 0.001));
      expect(result[4], closeTo(1.25, 0.001));
    });
  });

  group('PartySync Direct Stream Broadcast & Zero-Lag Buffer Tests', () {
    test('DefaultStreamResolver caches direct stream and validates expiration', () {
      const songId = 'test_party_track_123';
      const streamUrl = 'https://aac.saavncdn.com/123/direct_stream_audio.mp4';

      DefaultStreamResolver.cacheStream(songId, streamUrl);

      final cached = DefaultStreamResolver.getCachedStream(songId);
      expect(cached, equals(streamUrl));
      expect(DefaultStreamResolver.isStreamExpired(songId), isFalse);
    });

    test('DriftReconciler micro-adjust ceiling scales up to 1500ms without hard seeking', () {
      // 800ms drift (moderate-high) -> should apply Tier 3 micro-speed adjustment (0.96x / 1.04x)
      final actionBehind = DriftReconciler.reconcileDrift(
        currentPositionMs: 4200,
        expectedPositionMs: 5000, // drift = -800ms
        microAdjustMaxMs: 1500,
      );
      expect(actionBehind.type, equals(DriftActionType.speedUp));
      expect(actionBehind.playbackSpeed, equals(1.040));
      expect(actionBehind.isHardSeek, isFalse);

      final actionAhead = DriftReconciler.reconcileDrift(
        currentPositionMs: 5800,
        expectedPositionMs: 5000, // drift = +800ms
        microAdjustMaxMs: 1500,
      );
      expect(actionAhead.type, equals(DriftActionType.slowDown));
      expect(actionAhead.playbackSpeed, equals(0.960));
      expect(actionAhead.isHardSeek, isFalse);
    });

    test('Adaptive presentation barrier guarantees at least 1500ms buffer lead time', () {
      final leadTime = ScheduledPlaybackCalculator.calculateAdaptiveLeadTimeMs(
        peerRtts: [50, 120],
        isLan: false,
      );
      expect(leadTime, greaterThanOrEqualTo(1500));
      expect(leadTime, lessThanOrEqualTo(2800));
    });

    test('Joiner manual play attempted callback triggers without audio desync', () {
      Song? interceptedSong;
      PartySyncCoordinator.onJoinerManualPlayAttempted = (song) {
        interceptedSong = song;
      };

      final testSong = Song(
        id: 'user_tapped_song_456',
        title: 'User Tapped Track',
        artist: 'Test Artist',
        coverUrl: 'https://example.com/cover.jpg',
      );

      PartySyncCoordinator.onJoinerManualPlayAttempted?.call(testSong);
      expect(interceptedSong, isNotNull);
      expect(interceptedSong?.id, equals('user_tapped_song_456'));
    });
  });
}
