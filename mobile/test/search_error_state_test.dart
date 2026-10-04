import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/domain/models/app_error.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/search_service.dart';
import 'package:paatu_padava_mobile/ui/screens/search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummySong = Song(
    id: 'test_song_1',
    title: 'Vaathi Coming',
    artist: 'Anirudh Ravichander',
    album: 'Master',
    duration: 230,
    coverUrl: 'https://example.com/cover.jpg',
  );

  group('SearchResults Domain Model Error States', () {
    test('Genuine empty results: isEmpty is true, hasError is false', () {
      final results = SearchResults(
        songs: [],
        albums: [],
        artists: [],
        error: null,
      );

      expect(results.isEmpty, isTrue);
      expect(results.hasError, isFalse);
      expect(results.error, isNull);
    });

    test('Network failure results: isEmpty is true, hasError is true with offline category', () {
      final offlineErr = AppError.offline();
      final results = SearchResults(
        songs: [],
        albums: [],
        artists: [],
        error: offlineErr,
      );

      expect(results.isEmpty, isTrue);
      expect(results.hasError, isTrue);
      expect(results.error?.category, equals(AppErrorCategory.offline));
      expect(results.error?.actionType, equals(AppActionType.openDownloads));
    });

    test('Server timeout results: hasError is true with timeout category', () {
      final timeoutErr = AppError.timeout();
      final results = SearchResults(
        songs: [],
        albums: [],
        artists: [],
        error: timeoutErr,
      );

      expect(results.isEmpty, isTrue);
      expect(results.hasError, isTrue);
      expect(results.error?.category, equals(AppErrorCategory.timeout));
      expect(results.error?.actionType, equals(AppActionType.retry));
    });

    test('Successful results: isEmpty is false, hasError is false', () {
      final results = SearchResults(
        songs: [dummySong],
        albums: [],
        artists: [],
        error: null,
      );

      expect(results.isEmpty, isFalse);
      expect(results.hasError, isFalse);
      expect(results.error, isNull);
    });
  });

  group('SearchResultsState Screen State Representation', () {
    test('State cleanly distinguishes genuine empty results from error states', () {
      const emptyState = SearchResultsState(
        songs: [],
        albums: [],
        artists: [],
        ytSongs: [],
        error: null,
      );

      expect(emptyState.isEmpty, isTrue);
      expect(emptyState.hasError, isFalse);

      final errorState = SearchResultsState(
        songs: [],
        albums: [],
        artists: [],
        ytSongs: [],
        error: AppError.offline(),
      );

      expect(errorState.isEmpty, isTrue);
      expect(errorState.hasError, isTrue);
      expect(errorState.error?.userMessage.toLowerCase(), contains('internet connection'));
    });

    test('SearchResultsState retains server waking up category and action', () {
      final wakingState = SearchResultsState(
        error: AppError.serverWaking(),
      );

      expect(wakingState.hasError, isTrue);
      expect(wakingState.error?.category, equals(AppErrorCategory.serverWaking));
      expect(wakingState.error?.actionType, equals(AppActionType.retry));
    });
  });
}
