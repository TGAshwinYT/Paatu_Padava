import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/song.dart';
import '../../theme/app_theme.dart';

class SearchVersionsSheet {
  static void show(
    BuildContext context,
    Song primary, {
    required void Function(Song) onSelectSong,
  }) {
    final allVersions = [primary, ...primary.versions];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    'Available Versions',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  child: Text(
                    primary.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Divider(color: AppColors.surfaceBorder, height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: allVersions.length,
                    itemBuilder: (context, idx) {
                      final v = allVersions[idx];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: CachedNetworkImage(
                              imageUrl: v.coverUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                            ),
                          ),
                        ),
                        title: Text(
                          v.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${v.versionTag} • ${v.artist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: v.source == 'youtube'
                                ? AppColors.electricCyan.withValues(alpha: 0.2)
                                : AppColors.neonViolet.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            v.source == 'youtube' ? 'YT' : '320K',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: v.source == 'youtube' ? AppColors.electricCyan : AppColors.neonViolet,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onSelectSong(v);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
