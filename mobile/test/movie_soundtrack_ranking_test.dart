import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/domain/models/clustered_track_result.dart';
import 'package:paatu_padava_mobile/services/user_preference_matrix.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/logic/track_quality_filter.dart';

void main() {
  test('Movie Soundtrack Tracks rank at top ahead of foreign title matches', () {
    final intent = SearchService.understandQuery('mersal');

    final arabicSong = Song(
      id: 'arabic_1',
      title: 'Mersal',
      artist: 'Alaa Abdel Khalek',
      album: 'Tayyara Waraq',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      language: 'arabic',
    );

    final aalaporaan = Song(
      id: 'aalaporaan_1',
      title: 'Aalaporaan Thamizhan',
      artist: 'A.R. Rahman, Kailash Kher',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    final neethanae = Song(
      id: 'neethanae_1',
      title: 'Neethanae',
      artist: 'A.R. Rahman, Shreya Ghoshal',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    final mersalArasan = Song(
      id: 'mersal_arasan_1',
      title: 'Mersal Arasan',
      artist: 'A.R. Rahman, G.V. Prakash',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    final maacho = Song(
      id: 'maacho_1',
      title: 'Maacho',
      artist: 'A.R. Rahman, Sid Sriram',
      album: 'Mersal',
      coverUrl: 'https://c.saavncdn.com/492/Mersal-Tamil-2017-500x500.jpg',
      source: 'saavn',
      language: 'tamil',
    );

    // 1. Verify foreign language purge: Arabic song gets score 0.0
    final arabicScore = SearchService.calculateCompositeRelevance(arabicSong, intent);
    expect(arabicScore, 0.0, reason: 'Non-regional language song must be purged to 0.0');

    // 2. Movie soundtrack songs must get 1.0
    final aalaScore = SearchService.calculateCompositeRelevance(aalaporaan, intent);
    expect(aalaScore, 1.0, reason: 'Movie soundtrack track must score 1.0');

    // 3. Re-ranking: movie soundtrack songs must be at top positions
    final pool = [arabicSong, aalaporaan, neethanae, mersalArasan, maacho];
    final reranked = UserPreferenceMatrix.reRankWithPreferences(pool, 'mersal');

    expect(reranked.take(4).map((s) => s.album).toSet(), {'Mersal'});
    expect(reranked.any((s) => s.album == 'Mersal'), isTrue);
  });

  test('Dialogue and non-music punch tracks are rejected when searching for a movie (Maari 2)', () {
    final intent = SearchService.understandQuery('Maari 2');

    final dialogueSong = Song(
      id: 'yt_dialogue_1',
      title: 'Maari 2 Dialogue',
      artist: 'DJ VISHAL S',
      album: 'Maari 2',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'youtube',
      duration: 120,
    );

    final rowdyBaby = Song(
      id: 'saavn_rowdy_1',
      title: 'Rowdy Baby',
      artist: 'Dhanush, Dhee',
      album: 'Maari 2',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      duration: 280,
    );

    // 1. Relevance score must be 0.0 for dialogue track when query is "Maari 2"
    final dialogueScore = SearchService.calculateCompositeRelevance(dialogueSong, intent);
    expect(dialogueScore, 0.0, reason: 'Spoken dialogue must be rejected with 0.0 when user searched for movie');

    // 2. TrackQualityFilter must classify dialogue track as rejectedJunk
    final classification = TrackQualityFilter.classifyTrack(
      title: dialogueSong.title,
      durationSec: dialogueSong.duration,
      source: dialogueSong.source,
      artist: dialogueSong.artist,
      query: 'Maari 2',
    );
    expect(classification, ContentClassification.rejectedJunk);

    // 3. Official musical song must score high
    final songScore = SearchService.calculateCompositeRelevance(rowdyBaby, intent);
    expect(songScore, greaterThan(0.70));
  });

  test('Dialogue tracks are preserved when user explicitly searches for dialogue', () {
    final intent = SearchService.understandQuery('Maari 2 Dialogue');

    final dialogueSong = Song(
      id: 'yt_dialogue_1',
      title: 'Maari 2 Dialogue',
      artist: 'DJ VISHAL S',
      album: 'Maari 2',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'youtube',
      duration: 120,
    );

    final score = SearchService.calculateCompositeRelevance(dialogueSong, intent);
    expect(score, greaterThan(0.0), reason: 'Dialogue must be allowed when user explicitly asks for dialogue');

    final classification = TrackQualityFilter.classifyTrack(
      title: dialogueSong.title,
      durationSec: dialogueSong.duration,
      source: dialogueSong.source,
      artist: dialogueSong.artist,
      query: 'Maari 2 Dialogue',
    );
    expect(classification, isNot(ContentClassification.rejectedJunk));
  });

  test('filterGenuineAlbums preserves regional single-dub releases matching movie entity (Hi Nanna - Tamil)', () {
    final rawAlbums = [
      {
        'id': '101',
        'title': 'Hi Nanna - Tamil',
        'song_count': '1', // Reported as 1-song release in Saavn
        'artist': 'Hesham Abdul Wahab',
      },
      {
        'id': '102',
        'title': 'Hi Nanna - Telugu',
        'song_count': '6',
        'artist': 'Hesham Abdul Wahab',
      },
      {
        'id': '103',
        'title': 'Random Unrelated Single',
        'song_count': '1',
        'artist': 'Unknown',
      },
    ];

    final filtered = SearchService.filterGenuineAlbums(rawAlbums, query: 'Hi Nanna');

    // Must preserve "Hi Nanna - Tamil" despite song_count <= 1
    final titles = filtered.map((a) => a['title']).toList();
    expect(titles.contains('Hi Nanna - Tamil'), isTrue);
    expect(titles.contains('Hi Nanna - Telugu'), isTrue);
    expect(titles.contains('Random Unrelated Single'), isFalse);
  });

  test('filterPlaylistsByRelevanceAndLanguage rejects unrelated language playlists (Bacchiko Nannali for Hi Nanna)', () {
    final rawPlaylists = [
      {
        'id': 'p1',
        'title': 'Bacchiko Nannali', // Substring contains "hi" in bacchiko and "nanna" in nannali
        'language': 'kannada',
      },
      {
        'id': 'p2',
        'title': 'Hi Nanna Hits',
        'language': 'tamil',
      },
      {
        'id': 'p3',
        'title': 'Best of Hi Nanna',
        'language': 'telugu',
      },
    ];

    final filtered = SearchService.filterPlaylistsByRelevanceAndLanguage(
      rawPlaylists,
      query: 'Hi Nanna',
      language: 'tamil',
    );

    final titles = filtered.map((p) => p['title']).toList();
    expect(titles.contains('Bacchiko Nannali'), isFalse, reason: 'Kannada playlist with accidental token substring must be rejected');
    expect(titles.contains('Hi Nanna Hits'), isTrue);
    expect(titles.contains('Best of Hi Nanna'), isTrue);
  });

  test('Short queries (<= 3 chars, e.g. hi) suppress unrelated English YouTube bedroom-pop noise', () {
    final intent = SearchService.understandQuery('hi');

    final englishYtNoise = Song(
      id: 'yt_noise_1',
      title: 'Hi!',
      artist: 'MRCH',
      album: 'Indigging',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'youtube',
      duration: 180,
    );

    final regionalSong = Song(
      id: 'regional_hi_1',
      title: 'Kannakuzhiya',
      artist: 'Jen Martin, G.V. Prakash',
      album: 'Hi',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      language: 'tamil',
      duration: 210,
    );

    final noiseScore = SearchService.calculateCompositeRelevance(englishYtNoise, intent, preferredLanguages: ['tamil']);
    expect(noiseScore, 0.0, reason: 'Unrelated English YouTube song must score 0.0 for short query');

    final regionalScore = SearchService.calculateCompositeRelevance(regionalSong, intent, preferredLanguages: ['tamil']);
    expect(regionalScore, greaterThan(0.70), reason: 'Regional Tamil track matching Hi album must score high');
  });
  test('Mersal soundtrack tracks outrank Arabic tracks and Arabic tracks get score 0.0', () {
    final intent = SearchService.understandQuery('Mersal');

    final aalaporan = Song(
      id: 'mersal_1',
      title: 'Aalaporaan Thamizhan',
      artist: 'A.R. Rahman, Kailash Kher',
      album: 'Mersal',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      language: 'tamil',
      duration: 348,
    );

    final neethanae = Song(
      id: 'mersal_2',
      title: 'Neethanae',
      artist: 'A.R. Rahman, Shreya Ghoshal',
      album: 'Mersal',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      language: 'tamil',
      duration: 269,
    );

    final alaaArabic = Song(
      id: 'arabic_saavn_1',
      title: 'Mersal',
      artist: 'Alaa Abdel Khalek',
      album: 'Mersal',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'saavn',
      language: 'arabic',
      duration: 210,
    );

    final marioArabicYt = Song(
      id: 'arabic_yt_1',
      title: 'Mersal',
      artist: 'Mario El Hajj',
      album: 'Mersal',
      coverUrl: 'https://example.com/cover.jpg',
      source: 'youtube',
      duration: 230,
    );

    // 1. Arabic tracks must be purged with 0.0 score
    final alaaScore = SearchService.calculateCompositeRelevance(alaaArabic, intent, preferredLanguages: ['tamil']);
    expect(alaaScore, 0.0, reason: 'Arabic Saavn track must be rejected');

    final marioScore = SearchService.calculateCompositeRelevance(marioArabicYt, intent, preferredLanguages: ['tamil']);
    expect(marioScore, 0.0, reason: 'Arabic YouTube track must be rejected');

    // 2. Mersal tracks must score 1.0 due to album entity match
    final aalaporanScore = SearchService.calculateCompositeRelevance(aalaporan, intent, preferredLanguages: ['tamil']);
    final neethanaeScore = SearchService.calculateCompositeRelevance(neethanae, intent, preferredLanguages: ['tamil']);
    expect(aalaporanScore, 1.0, reason: 'Aalaporaan Thamizhan from Mersal album must score 1.0');
    expect(neethanaeScore, 1.0, reason: 'Neethanae from Mersal album must score 1.0');
  });

  test('Hi Nanna single-track EP releases like Samayama (From "Hi Nanna") are preserved and matched', () {
    final rawAlbums = [
      {
        'id': 'hn_1',
        'title': 'Samayama (From "Hi Nanna")',
        'song_count': '1',
        'artist': 'Hesham Abdul Wahab, Anurag Kulkarni',
      },
      {
        'id': 'hn_2',
        'title': 'Odiyamma (From "Hi Nanna") - Tamil',
        'song_count': '1',
        'artist': 'Hesham Abdul Wahab, Dhruv Vikram',
      },
      {
        'id': 'hn_3',
        'title': 'Random 1-Track Single',
        'song_count': '1',
        'artist': 'Unknown',
      },
    ];

    expect(SearchService.isAlbumOrMovieEntityMatch('Samayama (From "Hi Nanna")', 'Hi Nanna'), isTrue);
    expect(SearchService.isAlbumOrMovieEntityMatch('Odiyamma (From "Hi Nanna") - Tamil', 'Hi Nanna'), isTrue);

    final filtered = SearchService.filterGenuineAlbums(rawAlbums, query: 'Hi Nanna');
    final titles = filtered.map((a) => a['title']).toList();
    expect(titles.contains('Samayama (From "Hi Nanna")'), isTrue);
    expect(titles.contains('Odiyamma (From "Hi Nanna") - Tamil'), isTrue);
    expect(titles.contains('Random 1-Track Single'), isFalse);
  });
}
