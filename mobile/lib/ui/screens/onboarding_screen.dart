import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/auth_manager.dart';
import '../../services/api_client.dart';
import '../../presentation/screens/onboarding_artists_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onCompleted;

  const OnboardingScreen({super.key, this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 1; // 1 = Languages, 2 = Artists
  bool _isSaving = false;

  // Step 1: Languages
  final List<Map<String, String>> _availableLanguages = [
    {'id': 'tamil', 'native': 'தமிழ்', 'english': 'Tamil'},
    {'id': 'english', 'native': 'English', 'english': 'English'},
    {'id': 'hindi', 'native': 'हिन्दी', 'english': 'Hindi'},
    {'id': 'telugu', 'native': 'తెలుగు', 'english': 'Telugu'},
    {'id': 'malayalam', 'native': 'മലയാളം', 'english': 'Malayalam'},
    {'id': 'kannada', 'native': 'ಕನ್ನಡ', 'english': 'Kannada'},
    {'id': 'punjabi', 'native': 'ਪੰਜਾਬੀ', 'english': 'Punjabi'},
    {'id': 'marathi', 'native': 'मराठी', 'english': 'Marathi'},
    {'id': 'bengali', 'native': 'বাংলা', 'english': 'Bengali'},
  ];
  final Set<String> _selectedLanguages = {'tamil', 'english'};

  // Step 2: Artists
  final List<Map<String, String>> _popularArtists = [
    {
      'name': 'Anirudh Ravichander',
      'image': 'https://c.saavncdn.com/artists/Anirudh_Ravichander_500x500.jpg',
    },
    {
      'name': 'A.R. Rahman',
      'image': 'https://c.saavncdn.com/artists/A_R_Rahman_500x500.jpg',
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
      'name': 'G. V. Prakash Kumar',
      'image': 'https://c.saavncdn.com/artists/G_V_Prakash_Kumar_500x500.jpg',
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
      'image': 'https://c.saavncdn.com/artists/D_Imman_500x500.jpg',
    },
    {
      'name': 'Vijay Antony',
      'image': 'https://c.saavncdn.com/artists/Vijay_Antony_500x500.jpg',
    },
  ];

  final Set<String> _selectedArtists = {};
  final List<Map<String, String>> _customArtists = [];
  final TextEditingController _artistSearchCtrl = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final user = AuthManager.currentUser;
    if (user != null) {
      if (user.preferredLanguages.isNotEmpty) {
        _selectedLanguages.clear();
        _selectedLanguages.addAll(user.preferredLanguages);
      }
      if (user.favoriteArtists.isNotEmpty) {
        _selectedArtists.addAll(user.favoriteArtists);
      }
    }
  }

  @override
  void dispose() {
    _artistSearchCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final result = await ApiClient.searchGlobal(q);
        final artists = result?.artists ?? [];
        final parsed = artists.map((map) {
          return {
            'name': map['name']?.toString() ?? '',
            'image': map['image']?.toString() ?? '',
          };
        }).where((a) => a['name']!.isNotEmpty).toList();

        if (mounted) {
          setState(() {
            _searchResults = parsed;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _toggleLanguage(String id) {
    setState(() {
      if (_selectedLanguages.contains(id)) {
        if (_selectedLanguages.length > 1) {
          _selectedLanguages.remove(id);
        }
      } else {
        _selectedLanguages.add(id);
      }
    });
  }

  void _toggleArtist(String name) {
    setState(() {
      if (_selectedArtists.contains(name)) {
        _selectedArtists.remove(name);
      } else {
        _selectedArtists.add(name);
      }
    });
  }

  void _addCustomArtist(Map<String, String> artist) {
    setState(() {
      if (!_customArtists.any((a) => a['name'] == artist['name']) &&
          !_popularArtists.any((a) => a['name'] == artist['name'])) {
        _customArtists.insert(0, artist);
      }
      _selectedArtists.add(artist['name']!);
      _artistSearchCtrl.clear();
      _searchResults = [];
    });
  }

  Future<void> _handleFinish() async {
    if (_selectedLanguages.isEmpty || _selectedArtists.length < 3) return;

    setState(() => _isSaving = true);
    try {
      await AuthManager.updateLanguagePreferences(_selectedLanguages.toList());
      await AuthManager.updateArtistPreferences(_selectedArtists.toList());
      if (mounted) {
        if (widget.onCompleted != null) {
          widget.onCompleted!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preferences: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _step == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => setState(() => _step = 1),
              )
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 24,
              height: 4,
              decoration: BoxDecoration(
                color: _step == 2
                    ? const Color(0xFF1DB954)
                    : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _step == 1 ? _buildLanguageStep() : _buildArtistStep(),
      ),
    );
  }

  Widget _buildLanguageStep() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What music do you love?',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Select your preferred languages to personalize your daily mix and discover new hits.',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.7,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _availableLanguages.length,
                  itemBuilder: (context, index) {
                    final lang = _availableLanguages[index];
                    final isSelected = _selectedLanguages.contains(lang['id']);
                    return InkWell(
                      onTap: () => _toggleLanguage(lang['id']!),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1DB954).withOpacity(0.16)
                              : const Color(0xFF131B2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF1DB954)
                                : Colors.white.withOpacity(0.08),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  lang['native']!,
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lang['english']!,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                            if (isSelected)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1DB954),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selectedLanguages.isNotEmpty
                  ? () async {
                      await AuthManager.updateLanguagePreferences(_selectedLanguages.toList());
                      if (!mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OnboardingArtistsScreen(
                            onCompleted: widget.onCompleted,
                          ),
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
              ),
              child: Text(
                'Next (${_selectedLanguages.length} selected)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _selectedLanguages.isNotEmpty
                      ? Colors.black
                      : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtistStep() {
    final allArtists = [..._customArtists, ..._popularArtists];
    final remaining = 3 - _selectedArtists.length;
    final canProceed = _selectedArtists.length >= 3;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose 3 or more artists',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                canProceed
                    ? 'Great choices! Select more or start listening now.'
                    : 'Pick at least $remaining more artist${remaining > 1 ? 's' : ''} to build your custom feed.',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: canProceed
                      ? const Color(0xFF1DB954)
                      : Colors.white70,
                  fontWeight: canProceed ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _artistSearchCtrl,
                onChanged: _onSearchChanged,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search for any artist...',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954)),
                          ),
                        )
                      : (_artistSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                              onPressed: () {
                                _artistSearchCtrl.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null),
                  filled: true,
                  fillColor: const Color(0xFF131B2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
            ],
          ),
        ),
        if (_searchResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF182238),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Colors.white.withOpacity(0.06),
              ),
              itemBuilder: (context, i) {
                final artist = _searchResults[i];
                final isSelected = _selectedArtists.contains(artist['name']);
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF23304A),
                    backgroundImage: (artist['image']?.isNotEmpty ?? false)
                        ? CachedNetworkImageProvider(artist['image']!)
                        : null,
                    child: (artist['image']?.isEmpty ?? true)
                        ? const Icon(Icons.person, color: Colors.white60, size: 18)
                        : null,
                  ),
                  title: Text(
                    artist['name']!,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF1DB954), size: 22)
                      : const Icon(Icons.add_circle_outline, color: Colors.white54, size: 22),
                  onTap: () {
                    if (isSelected) {
                      _toggleArtist(artist['name']!);
                    } else {
                      _addCustomArtist(artist);
                    }
                  },
                );
              },
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.78,
              crossAxisSpacing: 14,
              mainAxisSpacing: 16,
            ),
            itemCount: allArtists.length,
            itemBuilder: (context, index) {
              final artist = allArtists[index];
              final name = artist['name']!;
              final isSelected = _selectedArtists.contains(name);
              final imageUrl = artist['image'];

              return InkWell(
                onTap: () => _toggleArtist(name),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF1DB954)
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: const Color(0xFF131B2E),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: const Color(0xFF131B2E),
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white38,
                                        size: 32,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: const Color(0xFF131B2E),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white38,
                                      size: 32,
                                    ),
                                  ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.5),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_circle,
                                color: Color(0xFF1DB954),
                                size: 34,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? const Color(0xFF1DB954) : Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canProceed && !_isSaving ? _handleFinish : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : Text(
                      canProceed
                          ? 'Start Listening'
                          : 'Select at least $remaining more',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: canProceed ? Colors.black : Colors.white38,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
