import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/auth_manager.dart';
import '../../services/supabase_service.dart';
import '../../data/repositories/song_repository.dart';
import '../../services/artist_sanitizer.dart';
import '../../services/error_handler.dart';
import '../theme/app_theme.dart';

class OnboardingArtistsScreen extends StatefulWidget {
  final VoidCallback? onCompleted;
  final bool isStandalone;

  const OnboardingArtistsScreen({
    super.key,
    this.onCompleted,
    this.isStandalone = false,
  });

  @override
  State<OnboardingArtistsScreen> createState() => _OnboardingArtistsScreenState();
}

class _OnboardingArtistsScreenState extends State<OnboardingArtistsScreen> with TickerProviderStateMixin {
  final Set<String> _selectedArtistNames = {};
  final Map<String, Map<String, String>> _selectedArtistDetails = {};
  bool _isSaving = false;

  // Collaborations / Related Artists Knowledge Graph for instant Spotify-grade expansion
  static final Map<String, List<Map<String, String>>> _artistCollaborations = {
    'hiphop tamizha': [
      {'name': 'Kaushik Krish', 'image': 'https://c.saavncdn.com/artists/Kaushik_Krish_500x500.jpg'},
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
    ],
    'sid sriram': [
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
      {'name': 'Jonita Gandhi', 'image': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg'},
    ],
    'anirudh ravichander': [
      {'name': 'Jonita Gandhi', 'image': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
      {'name': 'Anthony Daasan', 'image': 'https://c.saavncdn.com/artists/Anthony_Daasan_500x500.jpg'},
    ],
    'a.r. rahman': [
      {'name': 'Haricharan', 'image': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg'},
      {'name': 'Shreya Ghoshal', 'image': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_004_20221118121516_500x500.jpg'},
      {'name': 'Chinmayi', 'image': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg'},
    ],
    'yuvan shankar raja': [
      {'name': 'Ilaiyaraaja', 'image': 'https://c.saavncdn.com/artists/Ilaiyaraaja_004_20220602053931_500x500.jpg'},
      {'name': 'Vijay Yesudas', 'image': 'https://c.saavncdn.com/artists/Vijay_Yesudas_500x500.jpg'},
      {'name': 'Andrea Jeremiah', 'image': 'https://c.saavncdn.com/artists/Andrea_Jeremiah_500x500.jpg'},
    ],
    'harris jayaraj': [
      {'name': 'Karthik', 'image': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg'},
      {'name': 'Bombay Jayashri', 'image': 'https://c.saavncdn.com/artists/Bombay_Jayashri_500x500.jpg'},
      {'name': 'Harish Raghavendra', 'image': 'https://c.saavncdn.com/artists/Harish_Raghavendra_500x500.jpg'},
    ],
    'santhosh narayanan': [
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Arivu', 'image': 'https://c.saavncdn.com/artists/Arivu_500x500.jpg'},
    ],
    'g.v. prakash kumar': [
      {'name': 'Saindhavi', 'image': 'https://c.saavncdn.com/artists/Saindhavi_500x500.jpg'},
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
    ],
    'chinmayi': [
      {'name': 'Haricharan', 'image': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg'},
      {'name': 'Karthik', 'image': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg'},
      {'name': 'Bombay Jayashri', 'image': 'https://c.saavncdn.com/artists/Bombay_Jayashri_500x500.jpg'},
    ],
    'anthony daasan': [
      {'name': 'Sean Roldan', 'image': 'https://c.saavncdn.com/artists/Sean_Roldan_500x500.jpg'},
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
    ],
    'haricharan': [
      {'name': 'Shreya Ghoshal', 'image': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_004_20221118121516_500x500.jpg'},
      {'name': 'Chinmayi', 'image': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg'},
      {'name': 'Karthik', 'image': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg'},
    ],
    'kaushik krish': [
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Jonita Gandhi', 'image': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
    ],
    'pradeep kumar': [
      {'name': 'Sean Roldan', 'image': 'https://c.saavncdn.com/artists/Sean_Roldan_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_500x500.jpg'},
      {'name': 'Arivu', 'image': 'https://c.saavncdn.com/artists/Arivu_500x500.jpg'},
    ],
    'dhee': [
      {'name': 'Arivu', 'image': 'https://c.saavncdn.com/artists/Arivu_500x500.jpg'},
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Sid Sriram', 'image': 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg'},
    ],
    'jonita gandhi': [
      {'name': 'Anirudh Ravichander', 'image': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg'},
      {'name': 'Haricharan', 'image': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg'},
      {'name': 'Sid Sriram', 'image': 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg'},
    ],
    'karthik': [
      {'name': 'Bombay Jayashri', 'image': 'https://c.saavncdn.com/artists/Bombay_Jayashri_500x500.jpg'},
      {'name': 'Harish Raghavendra', 'image': 'https://c.saavncdn.com/artists/Harish_Raghavendra_500x500.jpg'},
      {'name': 'Shreya Ghoshal', 'image': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg'},
    ],
    'ilaiyaraaja': [
      {'name': 'S.P. Balasubrahmanyam', 'image': 'https://c.saavncdn.com/artists/S_P__Balasubrahmanyam_500x500.jpg'},
      {'name': 'K.S. Chithra', 'image': 'https://c.saavncdn.com/artists/K_S__Chithra_500x500.jpg'},
      {'name': 'K.J. Yesudas', 'image': 'https://c.saavncdn.com/artists/K_J__Yesudas_500x500.jpg'},
    ],
    'shreya ghoshal': [
      {'name': 'Haricharan', 'image': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg'},
      {'name': 'Karthik', 'image': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg'},
      {'name': 'Chinmayi', 'image': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg'},
    ],
    'd. imman': [
      {'name': 'Anthony Daasan', 'image': 'https://c.saavncdn.com/artists/Anthony_Daasan_500x500.jpg'},
      {'name': 'Shreya Ghoshal', 'image': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg'},
      {'name': 'Sid Sriram', 'image': 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg'},
    ],
    'vijay antony': [
      {'name': 'Harris Jayaraj', 'image': 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg'},
      {'name': 'Yuvan Shankar Raja', 'image': 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg'},
      {'name': 'D. Imman', 'image': 'https://c.saavncdn.com/artists/D__Imman_500x500.jpg'},
    ],
    'saindhavi': [
      {'name': 'Haricharan', 'image': 'https://c.saavncdn.com/artists/Haricharan_500x500.jpg'},
      {'name': 'Chinmayi', 'image': 'https://c.saavncdn.com/artists/Chinmayi_Sripada_500x500.jpg'},
      {'name': 'Karthik', 'image': 'https://c.saavncdn.com/artists/Karthik_500x500.jpg'},
    ],
    'andrea jeremiah': [
      {'name': 'Anirudh Ravichander', 'image': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg'},
      {'name': 'Yuvan Shankar Raja', 'image': 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg'},
      {'name': 'Jonita Gandhi', 'image': 'https://c.saavncdn.com/artists/Jonita_Gandhi_500x500.jpg'},
    ],
    'arivu': [
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_20180510121326_500x500.jpg'},
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Sean Roldan', 'image': 'https://c.saavncdn.com/artists/Sean_Roldan_500x500.jpg'},
    ],
    'sean roldan': [
      {'name': 'Pradeep Kumar', 'image': 'https://c.saavncdn.com/artists/Pradeep_Kumar_500x500.jpg'},
      {'name': 'Anthony Daasan', 'image': 'https://c.saavncdn.com/artists/Anthony_Daasan_500x500.jpg'},
      {'name': 'Dhee', 'image': 'https://c.saavncdn.com/artists/Dhee_20180510121326_500x500.jpg'},
    ],
  };

  // Initial core seed list
  final List<Map<String, String>> _displayedArtists = [
    {
      'name': 'Anirudh Ravichander',
      'image': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg',
    },
    {
      'name': 'A.R. Rahman',
      'image': 'https://c.saavncdn.com/artists/AR_Rahman_002_20210120084455_500x500.jpg',
    },
    {
      'name': 'Yuvan Shankar Raja',
      'image': 'https://c.saavncdn.com/artists/Yuvan_Shankar_Raja_500x500.jpg',
    },
    {
      'name': 'Harris Jayaraj',
      'image': 'https://c.saavncdn.com/artists/Harris_Jayaraj_500x500.jpg',
    },
    {
      'name': 'Hiphop Tamizha',
      'image': 'https://c.saavncdn.com/artists/Hiphop_Tamizha_500x500.jpg',
    },
    {
      'name': 'Santhosh Narayanan',
      'image': 'https://c.saavncdn.com/artists/Santhosh_Narayanan_500x500.jpg',
    },
    {
      'name': 'Sid Sriram',
      'image': 'https://c.saavncdn.com/artists/Sid_Sriram_500x500.jpg',
    },
    {
      'name': 'G.V. Prakash Kumar',
      'image': 'https://c.saavncdn.com/artists/G_V__Prakash_Kumar_003_20251113063655_500x500.jpg',
    },
    {
      'name': 'Shreya Ghoshal',
      'image': 'https://c.saavncdn.com/artists/Shreya_Ghoshal_500x500.jpg',
    },
    {
      'name': 'Ilaiyaraaja',
      'image': 'https://c.saavncdn.com/artists/Ilaiyaraaja_500x500.jpg',
    },
    {
      'name': 'D. Imman',
      'image': 'https://c.saavncdn.com/artists/D__Imman_500x500.jpg',
    },
    {
      'name': 'Vijay Antony',
      'image': 'https://c.saavncdn.com/artists/Vijay_Antony_500x500.jpg',
    },
  ];

  final Set<String> _expandedArtistTriggers = {};
  final GlobalKey<AnimatedGridState> _gridKey = GlobalKey<AnimatedGridState>();

  @override
  void initState() {
    super.initState();
    _loadExistingFavorites();
  }

  Future<void> _loadExistingFavorites() async {
    final user = AuthManager.currentUser;
    if (user != null && user.favoriteArtists.isNotEmpty) {
      setState(() {
        _selectedArtistNames.addAll(user.favoriteArtists);
        for (final a in _displayedArtists) {
          if (_selectedArtistNames.contains(a['name'])) {
            _selectedArtistDetails[a['name']!] = a;
          }
        }
      });
    }
  }

  /// When a user taps an artist, select it and dynamically fetch & insert 3 related
  /// collaborating artists smoothly into the grid with an animated expansion.
  Future<void> _handleArtistTap(int index, Map<String, String> artist) async {
    final name = artist['name']!;
    final isSelected = _selectedArtistNames.contains(name);

    setState(() {
      if (isSelected) {
        _selectedArtistNames.remove(name);
        _selectedArtistDetails.remove(name);
      } else {
        _selectedArtistNames.add(name);
        _selectedArtistDetails[name] = artist;
      }
    });

    // If selecting and not yet expanded for this artist, dynamically fetch & insert related artists
    if (!isSelected && !_expandedArtistTriggers.contains(name)) {
      _expandedArtistTriggers.add(name);
      await _fetchAndInsertRelatedArtists(index, name);
    }
  }

  Future<void> _fetchAndInsertRelatedArtists(int sourceIndex, String artistName) async {
    final norm = artistName.toLowerCase().trim();
    final canonicalName = ArtistSanitizer.canonicalArtistName(artistName);
    final canonicalNorm = canonicalName.toLowerCase().trim();

    List<Map<String, String>> candidates = _artistCollaborations[norm] ??
        _artistCollaborations[canonicalNorm] ??
        [];

    // Fallback: If not in static collaboration graph, dynamically discover genuine collaborating artists
    // from the artist's hit songs (e.g. co-singers / composers) rather than querying the artist's own name.
    if (candidates.isEmpty) {
      try {
        final querySongs = await SongRepository.getArtistSampleSongs(canonicalName, limit: 12);
        final discovered = <Map<String, String>>[];
        final seenDiscovered = <String>{};

        for (final song in querySongs) {
          // Extract genuine musicians from song attribution
          final primary = ArtistSanitizer.extractPrimaryGenuineArtist(song.artist);
          final candidatesFromSong = [primary, ...song.artist.split(RegExp(r'[,&/|]')).map((s) => s.trim())];

          for (final rawCand in candidatesFromSong) {
            if (rawCand.isEmpty) continue;
            if (ArtistSanitizer.isCompositeOrMultiArtist(rawCand)) continue;
            if (!ArtistSanitizer.isGenuineArtist(rawCand)) continue;

            final candCanon = ArtistSanitizer.canonicalArtistName(rawCand);
            if (ArtistSanitizer.areSameOrVariantArtists(candCanon, canonicalName)) continue;
            if (seenDiscovered.add(candCanon.toLowerCase())) {
              discovered.add({
                'name': candCanon,
                'image': song.coverUrl,
              });
            }
          }
          if (discovered.length >= 6) break;
        }

        // If songs yielded candidates, use them
        if (discovered.isNotEmpty) {
          candidates = discovered;
        } else {
          // Last resort: Top language artists
          final topResults = await SongRepository.getTopArtists(language: 'Tamil', limit: 10);
          candidates = topResults
              .where((a) {
                final n = a['name']?.toString() ?? '';
                return n.isNotEmpty &&
                    !ArtistSanitizer.isCompositeOrMultiArtist(n) &&
                    ArtistSanitizer.isGenuineArtist(n) &&
                    !ArtistSanitizer.areSameOrVariantArtists(n, canonicalName);
              })
              .map((a) => {
                    'name': ArtistSanitizer.canonicalArtistName(a['name']?.toString() ?? ''),
                    'image': a['image']?.toString() ?? '',
                  })
              .toList();
        }
      } catch (_) {}
    }

    if (candidates.isEmpty) return;

    // Filter candidates against displayed artists using canonical and variant checks
    final newArtists = <Map<String, String>>[];
    for (final c in candidates) {
      final name = c['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      if (ArtistSanitizer.isCompositeOrMultiArtist(name)) continue;
      if (!ArtistSanitizer.isGenuineArtist(name)) continue;

      final candCanonical = ArtistSanitizer.canonicalArtistName(name);

      // Must not match the tapped artist or any alias/variant of it
      if (ArtistSanitizer.areSameOrVariantArtists(candCanonical, canonicalName)) continue;

      // Must not match ANY existing displayed artist or variant of it
      final alreadyDisplayed = _displayedArtists.any((existing) =>
          ArtistSanitizer.areSameOrVariantArtists(existing['name'] ?? '', candCanonical));
      if (alreadyDisplayed) continue;

      // Must not duplicate an item in the current batch
      final alreadyInBatch = newArtists.any((item) =>
          ArtistSanitizer.areSameOrVariantArtists(item['name'] ?? '', candCanonical));
      if (alreadyInBatch) continue;

      newArtists.add({
        'name': candCanonical,
        'image': c['image']?.toString() ?? '',
      });

      if (newArtists.length >= 3) break;
    }

    if (newArtists.isEmpty) return;

    // Insert smoothly right after the tapped artist
    final insertPos = (sourceIndex + 1).clamp(0, _displayedArtists.length);
    for (int i = 0; i < newArtists.length; i++) {
      final item = newArtists[i];
      final targetIndex = insertPos + i;
      _displayedArtists.insert(targetIndex, item);
      _gridKey.currentState?.insertItem(
        targetIndex,
        duration: Duration(milliseconds: 300 + (i * 100)),
      );
    }

    if (mounted) setState(() {});
  }

  Future<void> _handleSave() async {
    if (_selectedArtistNames.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least 3 favorite artists to continue.',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final selectedList = _selectedArtistDetails.values.toList();

      // 1. Save directly into Supabase table `user_favorite_artists`
      final supaUser = SupabaseService.currentUser;
      if (supaUser != null) {
        await SupabaseService.saveUserFavoriteArtists(
          userId: supaUser.id,
          artists: selectedList,
        );
      }

      // 2. Update local AuthManager preferences
      await AuthManager.updateArtistPreferences(_selectedArtistNames.toList());

      if (mounted) {
        if (widget.onCompleted != null) {
          widget.onCompleted!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final err = ErrorHandler.resolve(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save artists: ${err.userMessage}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selectedArtistNames.length;
    final isReady = count >= 3;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose Your Artists',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select at least 3 artists to personalize your feed',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isReady
                          ? AppColors.electricCyan.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isReady ? AppColors.electricCyan : Colors.white24,
                      ),
                    ),
                    child: Text(
                      '$count selected',
                      style: GoogleFonts.outfit(
                        color: isReady ? AppColors.electricCyan : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Animated Grid of Artists
            Expanded(
              child: AnimatedGrid(
                key: _gridKey,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                initialItemCount: _displayedArtists.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index, animation) {
                  final artist = _displayedArtists[index];
                  final name = artist['name']!;
                  final image = artist['image']!;
                  final isSelected = _selectedArtistNames.contains(name);

                  return ScaleTransition(
                    scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                    child: FadeTransition(
                      opacity: animation,
                      child: GestureDetector(
                        onTap: () => _handleArtistTap(index, artist),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // Glowing Selection Ring
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? AppColors.electricCyan : Colors.transparent,
                                      width: 3.5,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.electricCyan.withValues(alpha: 0.55),
                                              blurRadius: 14,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: image,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 200,
                                      memCacheHeight: 200,
                                      placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.surfaceElevated,
                                        child: const Icon(Icons.person_rounded, color: Colors.white30, size: 36),
                                      ),
                                    ),
                                  ),
                                ),

                                // Checkmark Badge when Selected
                                if (isSelected)
                                  Positioned(
                                    bottom: 0,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        gradient: AppColors.neonGradient,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Finish Button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (isReady && !_isSaving) ? _handleSave : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricCyan,
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: isReady ? 8 : 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                        )
                      : Text(
                          isReady ? 'Done ($count Artists)' : 'Select ${3 - count} more to continue',
                          style: GoogleFonts.outfit(
                            color: isReady ? Colors.black : Colors.white38,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
