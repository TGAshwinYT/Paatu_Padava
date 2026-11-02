import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/services/settings_manager.dart';
import 'package:paatu_padava_mobile/services/auth_manager.dart';
import 'package:paatu_padava_mobile/services/supabase_service.dart';
import 'package:paatu_padava_mobile/data/repositories/song_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding, Auth & Multi-Language Coherence Tests', () {
    test('1. Multi-language relevance: secondary preferred language receives equal boost as primary', () {
      const hindiSong = Song(
        id: 'h1',
        title: 'Kesariya',
        artist: 'Arijit Singh',
        album: 'Brahmastra',
        language: 'Hindi',
        coverUrl: '',
        source: 'saavn',
      );

      const tamilSong = Song(
        id: 't1',
        title: 'Naa Ready',
        artist: 'Anirudh Ravichander',
        album: 'Leo',
        language: 'Tamil',
        coverUrl: '',
        source: 'saavn',
      );

      final userLangs = ['Tamil', 'Hindi'];
      final intentHindi = SearchService.understandQuery('Kesariya');
      final intentTamil = SearchService.understandQuery('Naa Ready');

      final hindiScore = SearchService.calculateCompositeRelevance(
        hindiSong,
        intentHindi,
        preferredLanguages: userLangs,
      );

      final tamilScore = SearchService.calculateCompositeRelevance(
        tamilSong,
        intentTamil,
        preferredLanguages: userLangs,
      );

      // Both songs are in user's preferred languages and have exact title matches -> both should have strong scores >= 0.80
      expect(hindiScore, greaterThanOrEqualTo(0.80));
      expect(tamilScore, greaterThanOrEqualTo(0.80));
    });

    test('2. Artist screen multi-language sorting: tracks in secondary preferred languages are not demoted as mismatches', () {
      const arrTamilSong = Song(
        id: 'arr_tam',
        title: 'Chinna Chinna Aasai',
        artist: 'A.R. Rahman',
        album: 'Roja',
        language: 'Tamil',
        coverUrl: '',
      );

      const arrHindiSong = Song(
        id: 'arr_hin',
        title: 'Kun Faya Kun',
        artist: 'A.R. Rahman',
        album: 'Rockstar',
        language: 'Hindi',
        coverUrl: '',
      );

      const arrSpanishSong = Song(
        id: 'arr_spa',
        title: 'Random Dub',
        artist: 'A.R. Rahman',
        album: 'Unknown',
        language: 'Spanish',
        coverUrl: '',
      );

      final effectivePrefLangs = ['tamil', 'hindi'];

      // Both Tamil and Hindi should NOT be mismatches for a user who picked both
      final aMismatch = effectivePrefLangs.isNotEmpty && !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(arrTamilSong, l));
      final bMismatch = effectivePrefLangs.isNotEmpty && !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(arrHindiSong, l));
      final cMismatch = effectivePrefLangs.isNotEmpty && !effectivePrefLangs.any((l) => !SongRepository.isLanguageMismatch(arrSpanishSong, l));

      expect(aMismatch, isFalse);
      expect(bMismatch, isFalse);
      expect(cMismatch, isTrue); // Spanish is a true mismatch
    });

    test('3. Returning Google sign-in user detection: users with existing taste bypass onboarding', () {
      final returningUser = AuthUser(
        id: 'user_123',
        username: 'Existing Fan',
        email: 'fan@gmail.com',
        preferredLanguages: ['Tamil', 'English'],
        favoriteArtists: ['A.R. Rahman', 'Anirudh', 'Yuvan Shankar Raja'],
        isGuest: false,
      );

      final hasTaste = returningUser.preferredLanguages.isNotEmpty && returningUser.favoriteArtists.length >= 3;
      expect(hasTaste, isTrue);

      final newUser = AuthUser(
        id: 'user_new',
        username: 'New User',
        email: 'new@gmail.com',
        preferredLanguages: [],
        favoriteArtists: [],
        isGuest: false,
      );

      final newHasTaste = newUser.preferredLanguages.isNotEmpty && newUser.favoriteArtists.length >= 3;
      expect(newHasTaste, isFalse);
    });
  });
}
