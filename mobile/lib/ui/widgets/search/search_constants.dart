import 'package:flutter/material.dart';

class SearchConstants {
  static const List<String> trendingArtists = [
    'Anirudh Ravichander',
    'A.R. Rahman',
    'Arijit Singh',
    'Harris Jayaraj',
    'Sid Sriram',
    'Yuvan Shankar Raja',
    'Shreya Ghoshal',
    'Devi Sri Prasad',
    'Ilaiyaraaja',
    'Santhosh Narayanan',
  ];

  static const List<Map<String, dynamic>> browseCategories = [
    {
      'title': 'Top Tamil Hits',
      'query': 'Top Tamil Hits',
      'colors': [Color(0xFF7C3AED), Color(0xFF9333EA)],
      'icon': Icons.local_fire_department_rounded,
    },
    {
      'title': 'Telugu Beats',
      'query': 'Telugu Top Hits',
      'colors': [Color(0xFF0891B2), Color(0xFF0E7490)],
      'icon': Icons.bolt_rounded,
    },
    {
      'title': 'Hindi Top 50',
      'query': 'Hindi Top Songs',
      'colors': [Color(0xFF6366F1), Color(0xFF4F46E5)],
      'icon': Icons.trending_up_rounded,
    },
    {
      'title': 'English Global Hits',
      'query': 'English Top Hits',
      'colors': [Color(0xFFEC4899), Color(0xFFDB2777)],
      'icon': Icons.public_rounded,
    },
    {
      'title': 'Malayalam Chill',
      'query': 'Malayalam Melodies',
      'colors': [Color(0xFF0D9488), Color(0xFF0F766E)],
      'icon': Icons.nature_people_rounded,
    },
    {
      'title': 'Kannada Hits',
      'query': 'Kannada Top Hits',
      'colors': [Color(0xFFF59E0B), Color(0xFFD97706)],
      'icon': Icons.music_note_rounded,
    },
  ];
}
