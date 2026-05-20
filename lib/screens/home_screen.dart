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

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _unreadNotificationsCount = 0;
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUnreadCount();
    _subscribeToNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔔 [App Lifecycle] App resumed (foreground). Refreshing notifications...');
      _fetchUnreadCount();
      _subscribeToNotifications();
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

    debugPrint('🔔 [Realtime] Menghubungkan ke channel notifications...');

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
      debugPrint('🔔 [Realtime] Status channel notifications: $status' + (error != null ? ', Error: $error' : ''));
      
      // Jika koneksi terputus, error, atau timeout di Android/mobile, coba hubungkan kembali setelah delay kecil
      if (status == RealtimeSubscribeStatus.channelError || 
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('🔔 [Realtime] Saluran terputus/error. Mencoba re-koneksi otomatis dalam 3 detik...');
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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.bgGradient),
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
                  const SizedBox(height: 32),
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
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
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
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGreetingCard(BuildContext context, String name) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A3A2A), Color(0xFF0D2118)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: AppTheme.primaryGreen.withOpacity(0.15), blurRadius: 30, spreadRadius: 2),
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
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '"Dan bacalah Al-Quran dengan tartil."',
                  style: TextStyle(fontSize: 15, color: Colors.white, fontStyle: FontStyle.italic, height: 1.5),
                ),
                SizedBox(height: 4),
                Text(
                  '— QS. Al-Muzzammil: 4',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.auto_stories_rounded, color: AppTheme.primaryGreen, size: 36),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: gradient.colors.first.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                  SizedBox(height: 6),
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
        SizedBox(width: 12),
        Expanded(child: _statCard(context, '114', 'Surah', Icons.menu_book_rounded, AppTheme.accentGold)),
        SizedBox(width: 12),
        Expanded(child: _statCard(context, '6236', 'Ayat', Icons.format_list_numbered_rounded, AppTheme.accentTeal)),
      ],
    );
  }

  Widget _statCard(BuildContext context, String value, String label, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}