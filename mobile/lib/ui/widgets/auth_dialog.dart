import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_manager.dart';
import '../screens/onboarding_screen.dart';

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AuthDialog(),
    );
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _loginEmailCtrl = TextEditingController();
  final TextEditingController _loginPassCtrl = TextEditingController();

  final TextEditingController _regUsernameCtrl = TextEditingController();
  final TextEditingController _regEmailCtrl = TextEditingController();
  final TextEditingController _regPassCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailCtrl.text.trim();
    final pass = _loginPassCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await AuthManager.login(email, pass);
      if (!mounted) return;

      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome back, ${AuthManager.currentUser?.username ?? 'Listener'}!'),
            backgroundColor: const Color(0xFF9333EA),
          ),
        );
      } else {
        setState(() => _errorMessage = 'Invalid email or password. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  Future<void> _handleRegister() async {
    final username = _regUsernameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pass = _regPassCtrl.text.trim();
    if (username.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Please complete all registration fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await AuthManager.register(username, email, pass);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      } else {
        setState(() => _errorMessage = 'Registration failed. Email might already be registered.');
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (!mounted) return;
      if (errStr.contains('already registered') || errStr.contains('already exists') || errStr.contains('user already')) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        _tabController.animateTo(0);
        _loginEmailCtrl.text = email;
        _loginPassCtrl.text = pass;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email is already registered! Switched to Sign In.'),
            backgroundColor: Color(0xFF9333EA),
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await AuthManager.loginWithGoogle();
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception:', '').trim();
      setState(() {
        _isLoading = false;
        _errorMessage = msg.isNotEmpty
            ? msg
            : 'Google Sign-In is unavailable right now. Please sign in with email and password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxSheetHeight = mediaQuery.size.height * 0.90;
    final currentUser = AuthManager.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: const Color(0xFF9333EA).withOpacity(0.4), width: 1.5)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: bottomInset + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // If already logged in, show User Profile Card
              if (currentUser != null && !currentUser.isGuest) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF9333EA),
                  child: Text(
                    currentUser.username.isNotEmpty ? currentUser.username[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser.username,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        currentUser.email,
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
                      ),
                      if (currentUser.preferredLanguages.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Languages: ${currentUser.preferredLanguages.join(", ")}',
                            style: GoogleFonts.outfit(color: const Color(0xFF1DB954), fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              },
              icon: const Icon(Icons.tune_rounded, color: Color(0xFF1DB954), size: 18),
              label: Text('Edit Music Taste (Languages & Artists)', style: GoogleFonts.outfit(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: const Color(0xFF1DB954).withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await AuthManager.logout();
                if (mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
              label: Text('Sign Out', style: GoogleFonts.outfit(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ] else ...[
            // Brand Logo & Heading
            Center(
              child: Container(
                width: 54,
                height: 54,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9333EA).withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                ),
              ),
            ),
            Center(
              child: Text(
                'Paatu Padava',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                'Sync playlists, favorites & personalized recommendations',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),

            if (currentUser != null && currentUser.isGuest) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_outline_rounded, color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Currently in Guest Mode (Offline Playlists)',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],

            // Google Sign In Button
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _handleGoogleSignIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.15)),
                backgroundColor: const Color(0xFF0A0E1A),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 26),
              label: Text(
                'Continue with Google',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withOpacity(0.08))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
                ),
                Expanded(child: Divider(color: Colors.white.withOpacity(0.08))),
              ],
            ),
            const SizedBox(height: 14),

            // Animated Neon Sliding Control (Tabs: Sign In / Create Account)
            Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_tabController.index != 0) {
                          _tabController.animateTo(0);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: _tabController.index == 0 ? const Color(0xFF9333EA) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: _tabController.index == 0
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF9333EA).withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            'Sign In',
                            style: GoogleFonts.outfit(
                              color: _tabController.index == 0 ? Colors.white : Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_tabController.index != 1) {
                          _tabController.animateTo(1);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: _tabController.index == 1 ? const Color(0xFF9333EA) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: _tabController.index == 1
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF9333EA).withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            'Create Account',
                            style: GoogleFonts.outfit(
                              color: _tabController.index == 1 ? Colors.white : Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _tabController.index == 0
                  ? _buildSignInForm()
                  : _buildSignUpForm(),
            ),

            const SizedBox(height: 12),

            // Continue as Guest Option
            Center(
              child: TextButton(
                onPressed: () async {
                  await AuthManager.loginAsGuest();
                  if (mounted) Navigator.pop(context);
                },
                child: Text(
                  'Continue in Guest Mode',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildSignInForm() {
    return Column(
      key: const ValueKey('signin_form'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTextField(_loginEmailCtrl, 'Email Address', Icons.email_outlined),
        const SizedBox(height: 12),
        _buildTextField(_loginPassCtrl, 'Password', Icons.lock_outline, isPassword: true),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9333EA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              shadowColor: const Color(0xFF9333EA).withOpacity(0.4),
              elevation: 4,
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Sign In', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpForm() {
    return Column(
      key: const ValueKey('signup_form'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTextField(_regUsernameCtrl, 'Username', Icons.person_outline),
        const SizedBox(height: 8),
        _buildTextField(_regEmailCtrl, 'Email Address', Icons.email_outlined),
        const SizedBox(height: 8),
        _buildTextField(_regPassCtrl, 'Password', Icons.lock_outline, isPassword: true),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9333EA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              shadowColor: const Color(0xFF9333EA).withOpacity(0.4),
              elevation: 4,
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Create Account', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          hintText: hint,
          hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}
