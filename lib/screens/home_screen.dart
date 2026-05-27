import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import 'group_screen.dart';
import 'mandiri_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'notification_screen.dart';
import 'history_screen.dart';
import '../services/personal_history_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _unreadNotificationsCount = 0;
  int _personalKhatamCount = 0;
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUnreadCount();
    _loadPersonalStats();
    _subscribeToNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔔 [App Lifecycle] App resumed (foreground). Refreshing notifications...');
      _fetchUnreadCount();
      _loadPersonalStats();
      _subscribeToNotifications();
    }
  }

  Future<void> _loadPersonalStats() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Trigger Sinkronisasi Awal & Pemulihan (Self-Healing) Riwayat dari Cloud ke Lokal
    await PersonalHistoryService.getHistory(userId);
    
    final localMandiriKhatams = await PersonalHistoryService.getKhatamCount(userId);
    
    // Periksa apakah ronde mandiri saat ini sudah 30 Juz selesai (tetapi belum di-reset)
    bool isCurrentMandiriKhatam = false;
    try {
      final activeMandiriRes = await Supabase.instance.client
          .from('khataman_mandiri')
          .select('selesai')
          .eq('user_id', userId)
          .eq('selesai', true);
      
      final activeCompletedList = activeMandiriRes as List;
      if (activeCompletedList.isNotEmpty) {
        isCurrentMandiriKhatam = activeCompletedList.length == 30;
      }
    } catch (e) {
      debugPrint('Error loading active mandiri count on home: $e');
    }

    final totalCount = localMandiriKhatams + (isCurrentMandiriKhatam ? 1 : 0);
    if (mounted) {
      setState(() {
        _personalKhatamCount = totalCount;
      });
    }
  }

  Future<void> _fetchUnreadCount() async {
    final count = await NotificationService.getUnreadCount();
    if (mounted) {
      setState(() {
        _unreadNotificationsCount = count;
      });
    }
  }

  void _subscribeToNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // debugPrint('🔔 [Realtime] Menghubungkan ke channel notifications...');

    // Hapus channel lama terlebih dahulu jika ada untuk menghindari duplikasi listener
    if (_notificationChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_notificationChannel!);
      } catch (e) {
        debugPrint('🔔 [Realtime] Error removing old channel: $e');
      }
    }

    _notificationChannel = Supabase.instance.client
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('🔔 [Realtime] Event diterima: ${payload.eventType} untuk user $userId. Memperbarui count...');
            _fetchUnreadCount();
          },
        );
    
    _notificationChannel?.subscribe((status, [error]) {
      // debugPrint('🔔 [Realtime] Status channel notifications: $status${error != null ? ', Error: $error' : ''}');
      
      // Jika koneksi terputus, error, atau timeout di Android/mobile, coba hubungkan kembali setelah delay kecil
      if (status == RealtimeSubscribeStatus.channelError || 
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        // debugPrint('🔔 [Realtime] Saluran terputus/error. Mencoba re-koneksi otomatis dalam 3 detik...');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _subscribeToNotifications();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_notificationChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_notificationChannel!);
      } catch (e) {
        debugPrint('🔔 [Realtime] Error removing channel in dispose: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final displayName = user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@')[0] ??
        'Hamba Allah';
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFEEEEEE),
      body: Container(
         decoration: BoxDecoration(gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Header
                  _buildHeader(context, displayName, avatarUrl, authProvider),
                  const SizedBox(height: 32),
                  // Greeting Card
                  _buildGreetingCard(context, displayName),
                  const SizedBox(height: 18),
                  // Personal History Card
                  _buildPersonalHistoryCard(context),
                  const SizedBox(height: 28),
                  // Section Title
                  Text(
                    'Mulai Sekarang',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Feature Cards
                  _buildFeatureCard(
                    context,
                    icon: Icons.person_rounded,
                    title: 'Khataman Mandiri',
                    subtitle: 'Lacak progres membaca Quran Anda sendiri.\nPantau setiap Juz yang sudah Anda selesaikan.',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2ECC71), Color(0xFF1A8A4A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MandiriScreen())),
                  ),
                  const SizedBox(height: 14),
                  _buildFeatureCard(
                    context,
                    icon: Icons.group_rounded,
                    title: 'Khataman Grup',
                    subtitle: 'Buat atau gabung grup khataman bersama.\nDistribusikan 30 Juz secara dinamis ke anggota.',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3F3D8B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupScreen())),
                  ),
                  const SizedBox(height: 32),
                  // Stats Row
                  _buildStatsRow(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String name, String? avatarUrl, AuthProvider auth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left Side: Avatar and Greeting Text
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.6), width: 2),
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assalamu\'alaikum,',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Text(
                  name,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ],
        ),
        // Right Side: Notification and Settings Buttons
        Row(
          children: [
            // Bell Icon for Notifications
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationScreen()),
                    ).then((_) => _fetchUnreadCount());
                  },
                  icon: Icon(Icons.notifications_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'Notifikasi',
                ),
                if (_unreadNotificationsCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$_unreadNotificationsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              icon: Icon(Icons.settings_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: 'Pengaturan',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGreetingCard(BuildContext context, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFF1A3A2A), Color(0xFF0D2118)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFEBFDF3), Color(0xFFD4F8E6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final headerTextColor = isDark ? AppTheme.primaryGreen : AppTheme.darkGreen;
    final bodyTextColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleTextColor = isDark ? Colors.white70 : const Color(0xFF757575);
    final iconBgColor = isDark ? AppTheme.primaryGreen.withOpacity(0.15) : AppTheme.primaryGreen.withOpacity(0.12);
    final iconColor = isDark ? AppTheme.primaryGreen : AppTheme.darkGreen;
    final borderColor = isDark ? AppTheme.primaryGreen.withOpacity(0.3) : AppTheme.primaryGreen.withOpacity(0.2);
    final shadowColor = isDark ? AppTheme.primaryGreen.withOpacity(0.15) : AppTheme.primaryGreen.withOpacity(0.06);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: cardBgGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: shadowColor, blurRadius: 30, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📖  Al-Quran Al-Karim',
                  style: TextStyle(
                    fontSize: 13,
                    color: headerTextColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '"Dan bacalah Al-Quran dengan tartil."',
                  style: TextStyle(fontSize: 15, color: bodyTextColor, fontStyle: FontStyle.italic, height: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '— QS. Al-Muzzammil: 4',
                  style: TextStyle(fontSize: 12, color: subtitleTextColor),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.auto_stories_rounded, color: iconColor, size: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required LinearGradient gradient,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark 
                ? AppTheme.primaryGreen.withOpacity(0.3) 
                : AppTheme.primaryGreen.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: isDark ? gradient : null,
                color: isDark ? null : gradient.colors.first.withOpacity(0.12),
                border: isDark
                    ? null
                    : Border.all(
                        color: gradient.colors.first.withOpacity(0.25),
                        width: 0.8,
                      ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: isDark
                    ? [
                        BoxShadow(
                          color: gradient.colors.first.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon, 
                color: isDark ? Colors.white : gradient.colors.last, 
                size: 28,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _statCard(context, '30', 'Total Juz', Icons.layers_rounded, AppTheme.primaryGreen)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(context, '114', 'Surah', Icons.menu_book_rounded, AppTheme.accentGold)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(context, '6236', 'Ayat', Icons.format_list_numbered_rounded, AppTheme.accentTeal)),
      ],
    );
  }

  Widget _statCard(BuildContext context, String value, String label, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? AppTheme.primaryGreen.withOpacity(0.3) 
              : AppTheme.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildPersonalHistoryCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final cardBgGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFFE5A93C), Color(0xFFC5891C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFFEF9E7), Color(0xFFFDF2D5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
          
    final borderColor = isDark ? Colors.transparent : AppTheme.accentGold.withOpacity(0.25);
    final shadow = isDark
        ? [
            BoxShadow(
              color: const Color(0xFFC5891C).withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ]
        : null;

    final headerColor = isDark ? Colors.white70 : const Color(0xFF8B6508);
    final titleColor = isDark ? Colors.white : const Color(0xFF5C4008);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF8B6508).withOpacity(0.85);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        ).then((_) => _loadPersonalStats());
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: cardBgGradient,
          borderRadius: BorderRadius.circular(20),
          border: isDark ? null : Border.all(color: borderColor, width: 0.8),
          boxShadow: shadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.18) : AppTheme.accentGold.withOpacity(0.12),
                border: isDark ? null : Border.all(color: AppTheme.accentGold.withOpacity(0.25), width: 0.8),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.emoji_events_rounded, color: isDark ? Colors.white : const Color(0xFF8B6508), size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🏆  RIWAYAT & STATISTIK SAYA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: headerColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _personalKhatamCount > 0
                        ? 'Alhamdulillah, $_personalKhatamCount Kali Khatam Al-Quran'
                        : 'Pantau Progres & Statistik Khataman Anda',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lihat riwayat membaca minggu ini, bulan ini, & tahun ini ➔',
                    style: TextStyle(fontSize: 10, color: subtitleColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}