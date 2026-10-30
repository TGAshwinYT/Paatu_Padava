import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/track_quality_filter.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  bool keep(String title, int sec, {bool unknownOk = false}) => TrackQualityFilter.shouldKeep(
        title: title,
        durationSec: sec,
        allowUnknownDuration: unknownOk,
      );

  group('TrackQualityFilter', () {
    test('keeps normal songs', () {
      expect(keep('Aaluma Doluma', 255), isTrue);
      expect(keep('Believer (Official Video)', 204), isTrue);
      expect(keep('Kadhal Sadugudu', 331), isTrue);
    });

    test('drops anything longer than 10 minutes', () {
      expect(keep('Ilaiyaraaja Melodies', 601), isFalse);
      expect(keep('Anirudh Hits - Non Stop Jukebox', 3600), isFalse);
      expect(keep('Aaluma Doluma', 600), isTrue); // exactly at the cap is allowed
    });

    test('drops live streams / unknown duration (search) but not automix', () {
      expect(keep('lofi radio - beats to relax', 0), isFalse);
      expect(keep('Some track', 0, unknownOk: true), isTrue);
    });

    test('drops teasers and clips', () {
      expect(keep('Song Teaser', 30), isFalse);
    });

    test('mix words only matter on long videos (real songs named "Mix"/"Nonstop" survive)', () {
      expect(keep('Nonstop', 230), isTrue);
      expect(keep('Mashup 2024', 240), isTrue);
      expect(keep('Tamil Songs Mashup', 480), isFalse);
      expect(keep('90s Hits Jukebox', 450), isFalse);
    });

    test('hours-long / 24-7 markers are rejected', () {
      expect(keep('1 Hour Loop Kutti Story', 300), isFalse);
      expect(keep('Tamil lofi 24/7 live stream', 300), isFalse);
    });

    test('rejectReason explains why', () {
      expect(TrackQualityFilter.rejectReason(title: 'x', durationSec: 5000), contains('longer'));
      expect(TrackQualityFilter.rejectReason(title: 'Song', durationSec: 200), isNull);
    });

    test('filterSongs only judges YouTube songs', () {
      final saavnLong = Song(id: 's', title: 'Long Saavn', artist: 'A', album: 'B', coverUrl: '', duration: 900, source: 'saavn');
      final ytMix = Song(id: 'y1', title: 'Best Of Rahman Jukebox', artist: 'A', album: 'B', coverUrl: '', duration: 3000, source: 'youtube');
      final ytSong = Song(id: 'y2', title: 'Real Song', artist: 'A', album: 'B', coverUrl: '', duration: 240, source: 'youtube');
      final out = TrackQualityFilter.filterSongs([saavnLong, ytMix, ytSong]);
      expect(out.map((s) => s.id), ['s', 'y2']);
    });
  });
}
