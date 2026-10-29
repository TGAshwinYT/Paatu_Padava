import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_theme.dart';

/// Renders a Spotify-style dynamic collage cover for continuous listening sessions.
/// - If 4 distinct artwork URLs exist: 2x2 grid.
/// - If 2-3 artwork URLs exist: 2 halves or dominant image.
/// - If 1 artwork URL exists: Full hero image.
/// - If 0 artwork URLs exist: Sleek neon musical gradient placeholder.
class SessionCollageCover extends StatelessWidget {
  final List<String> coverUrls;
  final double size;
  final double borderRadius;

  const SessionCollageCover({
    super.key,
    required this.coverUrls,
    this.size = 120,
    this.borderRadius = 14,
  });

  Widget _buildSingleImage(String url, {required double width, required double height}) {
    if (url.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: const Icon(Icons.music_note_rounded, color: Colors.white38),
      );
    }

    if (url.startsWith('/') || url.startsWith('file://')) {
      final cleanPath = url.replaceFirst('file://', '');
      return Image.file(
        File(cleanPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: AppColors.surfaceElevated,
          child: const Icon(Icons.music_note_rounded, color: Colors.white38),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      memCacheWidth: 200,
      memCacheHeight: 200,
      placeholder: (_, __) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
      ),
      errorWidget: (_, __, ___) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: const Icon(Icons.music_note_rounded, color: Colors.white38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validCovers = coverUrls.where((u) => u.trim().isNotEmpty).toList();

    Widget content;
    if (validCovers.length >= 4) {
      final half = size / 2;
      content = Column(
        children: [
          Row(
            children: [
              _buildSingleImage(validCovers[0], width: half, height: half),
              _buildSingleImage(validCovers[1], width: half, height: half),
            ],
          ),
          Row(
            children: [
              _buildSingleImage(validCovers[2], width: half, height: half),
              _buildSingleImage(validCovers[3], width: half, height: half),
            ],
          ),
        ],
      );
    } else if (validCovers.length >= 2) {
      final half = size / 2;
      content = Row(
        children: [
          _buildSingleImage(validCovers[0], width: half, height: size),
          _buildSingleImage(validCovers[1], width: half, height: size),
        ],
      );
    } else if (validCovers.isNotEmpty) {
      content = _buildSingleImage(validCovers.first, width: size, height: size);
    } else {
      content = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.queue_music_rounded, color: Colors.white, size: 36),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: content,
      ),
    );
  }
}
