import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_manager.dart';
import '../../services/playlist_manager.dart';
import '../../services/sync_manager.dart';
import '../theme/app_theme.dart';

/// Prompts the user on login when device-local Guest playlists exist,
/// asking whether to import them into their cloud-synced Account playlists.
class GuestPlaylistImportDialog extends StatefulWidget {
  final int guestCount;
  final String userId;

  const GuestPlaylistImportDialog({
    super.key,
    required this.guestCount,
    required this.userId,
  });

  static bool _isShowing = false;

  static Future<void> showIfNeeded(BuildContext context) async {
    final userId = AuthManager.currentUser?.id;
    final count = AuthManager.pendingGuestImportCountNotifier.value;
    if (_isShowing || !AuthManager.isLoggedIn || userId == null || count <= 0) return;

    _isShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => GuestPlaylistImportDialog(guestCount: count, userId: userId),
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  State<GuestPlaylistImportDialog> createState() => _GuestPlaylistImportDialogState();
}

class _GuestPlaylistImportDialogState extends State<GuestPlaylistImportDialog> {
  bool _isBusy = false;

  Future<void> _decline() async {
    setState(() => _isBusy = true);
    await PlaylistManager.markGuestImportDeclined(widget.userId);
    AuthManager.pendingGuestImportCountNotifier.value = 0;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _approve() async {
    setState(() => _isBusy = true);
    final imported = await PlaylistManager.importGuestPlaylistsToAccount(widget.userId);
    AuthManager.pendingGuestImportCountNotifier.value = 0;
    if (imported.isNotEmpty) {
      await SyncManager.pushImportedAccountPlaylists(imported);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.guestCount == 1 ? 'playlist' : 'playlists';
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Import Guest Playlists?',
        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: Text(
        'You have ${widget.guestCount} Guest $label on this device. Would you like to import them into your account?',
        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : _decline,
          child: Text('Keep Local Only', style: GoogleFonts.outfit(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: _isBusy ? null : _approve,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.neonViolet,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Import to Account', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
