import 'package:flutter_test/flutter_test.dart';
import 'package:paatu_padava_mobile/services/auth_manager.dart';

void main() {
  group('AuthUser & Auth State Transition Tests', () {
    test('guest user has expected default fields', () {
      final guest = AuthUser.guest();
      expect(guest.isGuest, isTrue);
      expect(guest.id, equals('guest'));
      expect(guest.email, equals('guest@paatupaadava.app'));
      expect(guest.username, equals('Guest Listener'));
      expect(guest.favoriteArtists, isEmpty);
    });

    test('authenticated user serialization round-trip', () {
      final user = AuthUser(
        id: 'usr_abc_123',
        email: 'user@example.com',
        username: 'TestUser',
        isGuest: false,
        favoriteArtists: ['A.R. Rahman', 'Anirudh Ravichander', 'Yuvan Shankar Raja'],
      );

      final map = user.toJson();
      expect(map['id'], equals('usr_abc_123'));
      expect(map['email'], equals('user@example.com'));
      expect(map['username'], equals('TestUser'));
      expect(map['is_guest'], isFalse);
      expect((map['favorite_artists'] as List).length, equals(3));

      final restored = AuthUser.fromJson(map);
      expect(restored.id, equals(user.id));
      expect(restored.email, equals(user.email));
      expect(restored.username, equals(user.username));
      expect(restored.isGuest, isFalse);
      expect(restored.favoriteArtists, contains('Anirudh Ravichander'));
    });

    test('AuthManager authNotifier reacts to state transitions', () {
      final states = <AuthUser?>[];
      void listener() {
        states.add(AuthManager.authNotifier.value);
      }

      AuthManager.authNotifier.addListener(listener);

      // Transition to Guest
      final guest = AuthUser.guest();
      AuthManager.authNotifier.value = guest;
      expect(AuthManager.currentUser?.isGuest, isTrue);
      expect(AuthManager.isLoggedIn, isFalse);

      // Transition to Authenticated User
      final authUser = AuthUser(
        id: 'supa_user_999',
        email: 'ashwin@example.com',
        username: 'ashwin',
        isGuest: false,
        favoriteArtists: ['Sid Sriram'],
      );
      AuthManager.authNotifier.value = authUser;
      expect(AuthManager.currentUser?.id, equals('supa_user_999'));
      expect(AuthManager.currentUser?.isGuest, isFalse);

      // Transition to Logged Out (null)
      AuthManager.authNotifier.value = null;
      expect(AuthManager.currentUser, isNull);
      expect(AuthManager.isLoggedIn, isFalse);

      expect(states.length, equals(3));
      AuthManager.authNotifier.removeListener(listener);
    });
  });
}
