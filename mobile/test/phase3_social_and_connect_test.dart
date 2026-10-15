import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paatu_padava_mobile/models/song.dart';
import 'package:paatu_padava_mobile/services/device_connect_coordinator.dart';
import 'package:paatu_padava_mobile/services/playlist_manager.dart';
import 'package:paatu_padava_mobile/services/favorites_manager.dart';
import 'package:paatu_padava_mobile/ui/widgets/player/device_connect_sheet.dart';
import 'package:paatu_padava_mobile/ui/widgets/library/create_blend_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('phase3_test_hive_');
    Hive.init(tempDir.path);
    await Hive.openBox(PlaylistManager.boxName);
    await Hive.openBox(FavoritesManager.boxName);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('1. DeviceConnectCoordinator (Spotify Connect & Continuity Tests)', () {
    test('Initializes with Local Phone as current device', () {
      final coordinator = DeviceConnectCoordinator.instance;
      expect(coordinator.currentDevice.isLocal, isTrue);
      expect(coordinator.currentDevice.name, equals('This Phone'));
      expect(coordinator.isCasting, isFalse);
    });

    test('scanForDevices discovers TV, Speaker, and Desktop endpoints', () async {
      final coordinator = DeviceConnectCoordinator.instance;
      await coordinator.scanForDevices();

      final devices = coordinator.discoveredDevicesNotifier.value;
      expect(devices.isNotEmpty, isTrue);
      expect(devices.any((d) => d.type == DeviceType.tv), isTrue);
      expect(devices.any((d) => d.type == DeviceType.speaker), isTrue);
      expect(devices.any((d) => d.protocol == ConnectionProtocol.googleCast), isTrue);
      expect(devices.any((d) => d.protocol == ConnectionProtocol.airPlay), isTrue);
    });

    test('switchToDevice updates active target and disconnect restores local phone', () async {
      final coordinator = DeviceConnectCoordinator.instance;
      final tv = coordinator.discoveredDevicesNotifier.value.firstWhere((d) => d.type == DeviceType.tv);

      await coordinator.switchToDevice(tv);
      expect(coordinator.currentDevice.id, equals(tv.id));
      expect(coordinator.currentDevice.name, equals(tv.name));
      expect(coordinator.isCasting, isTrue);

      await coordinator.disconnect();
      expect(coordinator.currentDevice.isLocal, isTrue);
      expect(coordinator.currentDevice.name, equals('This Phone'));
      expect(coordinator.isCasting, isFalse);
    });

    test('setVolume updates volume clamped between 0.0 and 1.0', () async {
      final coordinator = DeviceConnectCoordinator.instance;
      final speaker = coordinator.discoveredDevicesNotifier.value.firstWhere((d) => d.type == DeviceType.speaker);

      await coordinator.switchToDevice(speaker);
      await coordinator.setVolume(0.75);
      expect(coordinator.currentDevice.volume, closeTo(0.75, 0.01));

      await coordinator.setVolume(1.5);
      expect(coordinator.currentDevice.volume, closeTo(1.0, 0.01));

      await coordinator.disconnect();
    });
  });

  group('2. Spotify Blend & Collaborative Playlists Logic Tests', () {
    test('UserPlaylist serializes and deserializes isBlend, blendPartnerName, and tasteMatchScore', () {
      final playlist = UserPlaylist(
        id: 'blend_123',
        title: 'Rahul + You',
        createdAt: 1700000000,
        tracks: [
          Song(
            id: 's_1',
            title: 'Track A',
            artist: 'Anirudh',
            album: 'Album A',
            coverUrl: 'http://img.com/1.jpg',
            source: 'saavn',
            addedBy: 'You',
          ),
          Song(
            id: 's_2',
            title: 'Track B',
            artist: 'A.R. Rahman',
            album: 'Album B',
            coverUrl: 'http://img.com/2.jpg',
            source: 'saavn',
            addedBy: 'Rahul',
          ),
        ],
        isCollaborative: true,
        isBlend: true,
        blendPartnerName: 'Rahul',
        tasteMatchScore: 92,
      );

      final map = playlist.toMap();
      expect(map['is_blend'], isTrue);
      expect(map['blend_partner_name'], equals('Rahul'));
      expect(map['taste_match_score'], equals(92));

      final restored = UserPlaylist.fromMap(map);
      expect(restored.isBlend, isTrue);
      expect(restored.blendPartnerName, equals('Rahul'));
      expect(restored.tasteMatchScore, equals(92));
      expect(restored.tracks.length, equals(2));
      expect(restored.tracks.first.addedBy, equals('You'));
      expect(restored.tracks.last.addedBy, equals('Rahul'));
    });

    test('PlaylistManager.createBlendPlaylist interleaves tracks and generates friendly match score', () async {
      final userTracks = [
        Song(id: 'u1', title: 'Song 1', artist: 'Anirudh', album: 'Alb 1', coverUrl: 'http://1.jpg', source: 'saavn'),
        Song(id: 'u2', title: 'Song 2', artist: 'Harris Jayaraj', album: 'Alb 2', coverUrl: 'http://2.jpg', source: 'saavn'),
      ];

      final partnerTracks = [
        Song(id: 'p1', title: 'Song 3', artist: 'A.R. Rahman', album: 'Alb 3', coverUrl: 'http://3.jpg', source: 'saavn'),
        Song(id: 'p2', title: 'Song 4', artist: 'Yuvan Shankar Raja', album: 'Alb 4', coverUrl: 'http://4.jpg', source: 'saavn'),
      ];

      final blend = await PlaylistManager.createBlendPlaylist(
        partnerName: 'Priya',
        userTracks: userTracks,
        partnerTracks: partnerTracks,
      );

      expect(blend.isBlend, isTrue);
      expect(blend.blendPartnerName, equals('Priya'));
      expect(blend.title, equals('Priya + You'));
      expect(blend.isCollaborative, isTrue);
      expect(blend.tasteMatchScore, inInclusiveRange(68, 98));
      expect(blend.tracks.length, equals(4));

      // Alternating interleaving verification
      expect(blend.tracks[0].id, equals('u1'));
      expect(blend.tracks[0].addedBy, equals('You'));
      expect(blend.tracks[1].id, equals('p1'));
      expect(blend.tracks[1].addedBy, equals('Priya'));
      expect(blend.tracks[2].id, equals('u2'));
      expect(blend.tracks[2].addedBy, equals('You'));
      expect(blend.tracks[3].id, equals('p2'));
      expect(blend.tracks[3].addedBy, equals('Priya'));
    });
  });

  group('3. DeviceConnectSheet & CreateBlendSheet Widget Rendering Tests', () {
    testWidgets('DeviceConnectSheet renders header, current device, and available devices', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeviceConnectSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect to a Device'), findsOneWidget);
      expect(find.text('CURRENT AUDIO OUTPUT'), findsOneWidget);
      expect(find.text('This Phone'), findsOneWidget);
      expect(find.text('AVAILABLE DEVICES ON NETWORK'), findsOneWidget);
      expect(find.text('Living Room TV'), findsOneWidget);
      expect(find.text('Studio Monitor'), findsOneWidget);
      expect(find.text('Start Party Mode (Sync Multiple Phones)'), findsOneWidget);
    });

    testWidgets('CreateBlendSheet renders friend name input, quick picks, and generate button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CreateBlendSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create a Blend'), findsOneWidget);
      expect(find.text("FRIEND'S NAME"), findsOneWidget);
      expect(find.text('QUICK PICKS'), findsOneWidget);
      expect(find.text('Rahul'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Generate Shared Blend'), findsOneWidget);
    });
  });
}
