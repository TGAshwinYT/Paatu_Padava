import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/logic/stream_resolver.dart';
import 'package:paatu_padava_mobile/models/song.dart';

void main() {
  group('StreamResolver Edge Cases & YouTube Metadata Tests', () {
    test('verifyMatch handles exact title matches when YouTube uploader is listed as artist', () {
      final target1 = Song(
        id: 'rE7nrxZPaN4',
        title: 'Kannumuzhi',
        artist: 'Vikarnan',
        album: 'YouTube Music',
        coverUrl: '',
        duration: 234,
        source: 'youtube',
      );
      final cand1 = Song(
        id: 'saavn_1',
        title: 'Kannumuzhi (From "Mask")',
        artist: 'Karumathur Manimaran',
        album: 'Mask',
        coverUrl: '',
        duration: 225,
        source: 'saavn',
      );
      expect(DefaultStreamResolver.verifyMatch(cand1, target1), isTrue);

      final target2 = Song(
        id: 'zHqGSU7Ymw0',
        title: 'Ooroda Oththa Don',
        artist: 'Balaji Tharaneetharan',
        album: 'YouTube Music',
        coverUrl: '',
        duration: 170,
        source: 'youtube',
      );
      final cand2 = Song(
        id: 'saavn_2',
        title: 'Ooroda Oththa Don (From "Baththa")',
        artist: 'Sai Abhyankkar',
        album: 'Baththa',
        coverUrl: '',
        duration: 172,
        source: 'saavn',
      );
      expect(DefaultStreamResolver.verifyMatch(cand2, target2), isTrue);

      // Rejects unrelated tracks
      final target3 = Song(
        id: '3',
        title: 'Hukum',
        artist: 'Anirudh',
        album: 'Jailer',
        coverUrl: '',
        duration: 200,
        source: 'saavn',
      );
      final cand3 = Song(
        id: '4',
        title: 'Kaavaalaa',
        artist: 'Anirudh',
        album: 'Jailer',
        coverUrl: '',
        duration: 190,
        source: 'saavn',
      );
      expect(DefaultStreamResolver.verifyMatch(cand3, target3), isFalse);

      // Rejects large duration delta (> 60s)
      final cand4 = Song(
        id: '5',
        title: 'Kannumuzhi',
        artist: 'Vikarnan',
        album: '',
        coverUrl: '',
        duration: 650,
        source: 'youtube',
      );
      expect(DefaultStreamResolver.verifyMatch(cand4, target1), isFalse);
    });

    test('resolveStreamUrl resolves tracks with director uploaders on Saavn in sub-second time', () async {
      final resolver = DefaultStreamResolver();

      final song1 = Song(
        id: 'rE7nrxZPaN4',
        title: 'Kannumuzhi',
        artist: 'Vikarnan',
        album: 'YouTube Music',
        coverUrl: '',
        duration: 234,
        source: 'youtube',
      );
      final url1 = await resolver.resolveStreamUrl(song1);
      expect(url1, isNotNull);
      expect(url1!.contains('saavncdn.com'), isTrue);

      final song2 = Song(
        id: 'zHqGSU7Ymw0',
        title: 'Ooroda Oththa Don',
        artist: 'Balaji Tharaneetharan',
        album: 'YouTube Music',
        coverUrl: '',
        duration: 170,
        source: 'youtube',
      );
      final url2 = await resolver.resolveStreamUrl(song2);
      expect(url2, isNotNull);
      expect(url2!.contains('saavncdn.com'), isTrue);

      final bleachers = Song(
        id: 'aBpYk9vuneE',
        title: 'Bleachers - Merry Christmas, Please Don\'t Call',
        artist: 'bleachers',
        album: 'YouTube Music',
        coverUrl: '',
        duration: 199,
        source: 'youtube',
      );
      final urlBleachers = await resolver.resolveStreamUrl(bleachers);
      expect(urlBleachers, isNotNull);
      expect(urlBleachers!.contains('saavncdn.com'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 35)));
  });
}
