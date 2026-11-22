import 'package:flutter/material.dart';
import '../../../services/auth_manager.dart';
import '../auth_dialog.dart';

/// User account header card with scoped auth listener
class SettingsAccountCard extends StatelessWidget {
  const SettingsAccountCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthManager.authNotifier,
      builder: (context, user, _) {
        final isLoggedIn = user != null && !user.isGuest;
        final isCompact = MediaQuery.sizeOf(context).width < 340;

        return Container(
          padding: EdgeInsets.all(isCompact ? 10 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: isCompact ? 18 : 26,
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  isLoggedIn && user.username.isNotEmpty ? user.username.substring(0, 1).toUpperCase() : 'G',
                  style: TextStyle(color: Colors.white, fontSize: isCompact ? 14 : 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoggedIn ? user.username : 'Guest User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoggedIn
                          ? (user.email.isNotEmpty ? user.email : 'Synced with Paatu Cloud')
                          : 'Local Mode • Cloud sync unavailable',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!isLoggedIn)
                ElevatedButton(
                  onPressed: () => AuthDialog.show(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                )
              else
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFF94A3B8)),
                  onPressed: () async {
                    await AuthManager.logout();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signed out successfully')),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
