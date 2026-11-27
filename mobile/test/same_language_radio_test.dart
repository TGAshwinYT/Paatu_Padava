import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/language_detector.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  group('LanguageDetector', () {
    test('infers english for Latin-script English song without Indic cues', () {
      final song = Song(
        id: 'yt_1',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        coverUrl: '',
        duration: 200,
      );
      expect(LanguageDetector.inferSongLanguage(song), equals('english'));
    });

    test('matches multi-language artist Shreya Ghoshal in both tamil and hindi', () {
      final candidate = Song(
        id: 's_1',
        title: 'Munbe Vaa',
        artist: 'Shreya Ghoshal',
        album: 'Sillunu Oru Kaadhal',
        coverUrl: '',
        duration: 240,
      );
      expect(LanguageDetector.isLanguageCompatible(candidate, 'tamil'), isTrue);
      expect(LanguageDetector.isLanguageCompatible(candidate, 'hindi'), isTrue);
    });

    test('blocks Tamil track when targetLang is english', () {
      final tamilSong = Song(
        id: 's_2',
        title: 'Why This Kolaveri Di',
        artist: 'Anirudh Ravichander',
        album: '3',
        coverUrl: '',
        duration: 240,
        language: 'tamil',
      );
      expect(LanguageDetector.isLanguageCompatible(tamilSong, 'english'), isFalse);
    });
  });
}
