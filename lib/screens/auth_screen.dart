import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // Import kIsWeb
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // Untuk Web, redirect harus ke URL (biasanya localhost saat development)
      // Untuk Mobile, redirect menggunakan custom scheme
      final String redirectTo = kIsWeb 
          ? Uri.base.origin 
          : 'com.example.khataman://login-callback';

      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        queryParams: {
          'prompt': 'select_account',
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login Gagal: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient),
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        // Logo / Icon (Dynamically changes based on theme)
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGreen.withOpacity(isDark ? 0.35 : 0.2),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: Image.asset(
                              isDark ? 'assets/images/app_icon_dark.png' : 'assets/images/app_icon.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Title
                        Text(
                          'Khataman Quran',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Lacak perjalanan spiritual Anda\nbersama atau sendiri.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                        const Spacer(flex: 2),
                        // Feature Badges (Informational, distinct from buttons)
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            _featurePill(Icons.person_rounded, 'Khataman Mandiri', AppTheme.primaryGreen),
                            _featurePill(Icons.group_rounded, 'Khataman Grup', const Color(0xFF6C63FF)),
                            _featurePill(Icons.bolt_rounded, 'Real-time Sync', AppTheme.accentTeal),
                          ],
                        ),
                        const Spacer(flex: 3),
                        // Google Sign In Button
                        SizedBox(
                          width: double.infinity,
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
                              : _googleButton(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Dengan masuk, Anda menyetujui Ketentuan Layanan\ndan Kebijakan Privasi kami.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7), height: 1.5),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
              // Dynamic Theme Toggle Button
              Positioned(
                top: 12,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.4),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: isDark ? AppTheme.accentGold : AppTheme.darkGreen,
                    ),
                    onPressed: () {
                      settings.setThemeMode(
                        isDark ? ThemeMode.light : ThemeMode.dark,
                      );
                    },
                    tooltip: isDark ? 'Mode Terang' : 'Mode Gelap',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featurePill(IconData icon, String label, Color baseColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color tintColor = isDark 
        ? baseColor.withOpacity(0.15) 
        : baseColor.withOpacity(0.08);
    final Color textColor = isDark 
        ? baseColor.withOpacity(0.9) 
        : Color.alphaBlend(Colors.black.withOpacity(0.4), baseColor);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: baseColor.withOpacity(isDark ? 0.3 : 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _signInWithGoogle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131314) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark 
                ? const Color(0xFF8E918F).withOpacity(0.3) 
                : const Color(0xFF747775).withOpacity(0.2),
            width: 1,
          ),
          boxShadow: isDark 
              ? [] 
              : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(
              'https://www.google.com/favicon.ico',
              width: 22,
              height: 22,
              errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Colors.blue, size: 26),
            ),
            const SizedBox(width: 12),
            Text(
              'Masuk dengan Google',
              style: TextStyle(
                color: isDark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}