import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_manager.dart';
import '../theme/app_theme.dart';
import 'auth_dialog.dart';

/// Single unified account entry-point button for top app bars (HomeScreen, LibraryScreen, etc.).
/// Guarantees consistent visual presentation and behavior across all navigation tabs.
class AccountBarButton extends StatelessWidget {
  const AccountBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthManager.authNotifier,
      builder: (context, user, _) {
        final isUser = user != null && !user.isGuest;
        final initial = isUser && user.username.isNotEmpty ? user.username[0].toUpperCase() : 'G';

        return Tooltip(
          message: isUser ? 'Account: ${user.username}' : 'Guest Mode (Tap to Sign In)',
          child: InkWell(
            onTap: () => AuthDialog.show(context),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isUser ? AppColors.neonViolet : Colors.white24,
                  width: 1.5,
                ),
                boxShadow: isUser
                    ? [
                        BoxShadow(
                          color: AppColors.neonViolet.withOpacity(0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: isUser ? AppColors.neonViolet : AppColors.surfaceElevated,
                child: isUser
                    ? Text(
                        initial,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : const Icon(
                        Icons.person_outline_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
