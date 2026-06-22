import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/localization.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/prayer_time_service.dart';
import '../features/group/presentation/group_list_screen.dart';
import 'mandiri_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'notification_screen.dart';
import 'history_screen.dart';
import '../services/personal_history_service.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../features/group/presentation/group_detail_screen.dart';
import 'surah_info_screen.dart';
import 'prayer_time_screen.dart';
import 'qibla_screen.dart';
import 'package:quran/quran.dart' as quran;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'mushaf_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _localNotifPlugin =
      FlutterLocalNotificationsPlugin();
  int _unreadNotificationsCount = 0;
  int _personalKhatamCount = 0;
  RealtimeChannel? _notificationChannel;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  List<Map<String, dynamic>> _activePrograms = [];
  bool _loadingActivePrograms = true;
  bool _isExpanded = false;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _initLocalNotifications();
    WidgetsBinding.instance.addObserver(this);
    _fetchUnreadCount();
    _loadPersonalStats();
    _loadActivePrograms();
    _subscribeToNotifications();
    _initDeepLinkListener();
  }

  Future<void> _initLocalNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifPlugin.initialize(initSettings);
    } catch (e) {
      debugPrint('Error initializing local notifications in HomeScreen: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔔 [App Lifecycle] App resumed (foreground). Refreshing notifications...');
      _fetchUnreadCount();
      _loadPersonalStats();
      _loadActivePrograms();
      _subscribeToNotifications();
    }
  }

  Future<void> _loadPersonalStats() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Trigger Sinkronisasi Awal & Pemulihan (Self-Healing) Riwayat dari Cloud ke Lokal
    await PersonalHistoryService.getHistory(userId);
    
    final localMandiriKhatams = await PersonalHistoryService.getKhatamCount(userId);
    final groupKhatams = await PersonalHistoryService.getGroupKhatamCount(userId);
    
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

    final totalCount = localMandiriKhatams + groupKhatams + (isCurrentMandiriKhatam ? 1 : 0);
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

  Future<void> _loadActivePrograms() async {
    if (!mounted) return;
    if (_activePrograms.isEmpty) {
      setState(() {
        _loadingActivePrograms = true;
      });
    }

    try {
      final programs = await _fetchActivePrograms();
      if (mounted) {
        setState(() {
          _activePrograms = programs;
          _loadingActivePrograms = false;
          if (programs.length <= 2) {
            _isExpanded = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading active programs: $e');
      if (mounted) {
        setState(() {
          _loadingActivePrograms = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchActivePrograms() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    List<Map<String, dynamic>> programs = [];

    // 1. Fetch Mandiri
    try {
      final mandiriRes = await Supabase.instance.client
          .from('khataman_mandiri')
          .select()
          .eq('user_id', userId);

      if (mandiriRes.isNotEmpty) {
        final completedCount = mandiriRes.where((p) => p['selesai'] == true).length;
        if (completedCount < 30) {
          double totalProgressSum = 0.0;
          DateTime latestUpdated = DateTime.fromMillisecondsSinceEpoch(0);
          
          for (var row in mandiriRes) {
            final updatedAtStr = row['updated_at'] as String?;
            if (updatedAtStr != null) {
              final parsedDate = DateTime.parse(updatedAtStr);
              if (parsedDate.isAfter(latestUpdated)) {
                latestUpdated = parsedDate;
              }
            }

            if (row['selesai'] == true) {
              totalProgressSum += 1.0;
            } else {
              final lastAyat = row['ayat_terakhir'] as int? ?? 0;
              if (lastAyat > 0) {
                final juzNum = row['nomor_juz'] as int;
                final surahsInJuz = quran.getSurahAndVersesFromJuz(juzNum);
                int totalAyatInJuz = 0;
                surahsInJuz.forEach((surah, bounds) {
                  totalAyatInJuz += (bounds[1] - bounds[0] + 1);
                });
                if (totalAyatInJuz > 0) {
                  double fraction = lastAyat / totalAyatInJuz;
                  totalProgressSum += fraction > 1.0 ? 1.0 : fraction;
                }
              }
            }
          }

          final progressPercent = (totalProgressSum / 30.0) * 100;
          programs.add({
            'type': 'MANDIRI',
            'title': 'Khataman Mandiri',
            'code': null,
            'progress': progressPercent,
            'updated_at': latestUpdated,
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching active mandiri: $e');
    }

    // 2. Fetch Active Group slots (fetch all user slots in active cycles to get correct latest updated_at)
    try {
      final slotsRes = await Supabase.instance.client
          .from('slot_khataman')
          .select('*, putaran_siklus!inner(*)')
          .eq('user_id', userId)
          .eq('putaran_siklus.status_aktif_selesai', 'AKTIF');

      final slotsList = slotsRes as List;
      if (slotsList.isNotEmpty) {
        // Group by group_id
        Map<String, List<Map<String, dynamic>>> slotsByGroup = {};
        for (var s in slotsList) {
          final putaran = s['putaran_siklus'] as Map<String, dynamic>;
          final groupId = putaran['group_id'] as String;
          slotsByGroup.putIfAbsent(groupId, () => []).add(s);
        }

        if (slotsByGroup.isNotEmpty) {
          final groupIds = slotsByGroup.keys.toList();
          final groupsRes = await Supabase.instance.client
              .from('groups')
              .select('*')
              .inFilter('id_group', groupIds);

          final groupsList = groupsRes as List;
          Map<String, Map<String, dynamic>> groupsMap = {
            for (var g in groupsList) g['id_group'] as String: g
          };

          final putaranIds = slotsList.map((s) => s['putaran_id'] as String).toSet().toList();
          final allSlotsRes = await Supabase.instance.client
              .from('slot_khataman')
              .select('putaran_id, status_checklist')
              .inFilter('putaran_id', putaranIds);

          final allSlotsList = allSlotsRes as List;
          
          Map<String, int> completedSlotsCount = {};
          for (var s in allSlotsList) {
            final pId = s['putaran_id'] as String;
            if (s['status_checklist'] == true) {
              completedSlotsCount[pId] = (completedSlotsCount[pId] ?? 0) + 1;
            }
          }

          for (var entry in slotsByGroup.entries) {
            final groupId = entry.key;
            final groupSlots = entry.value;
            final groupData = groupsMap[groupId];
            if (groupData == null) continue;

            DateTime latestUpdated = DateTime.fromMillisecondsSinceEpoch(0);
            for (var s in groupSlots) {
              final updatedAtStr = s['updated_at'] as String?;
              if (updatedAtStr != null) {
                final parsedDate = DateTime.parse(updatedAtStr);
                if (parsedDate.isAfter(latestUpdated)) {
                  latestUpdated = parsedDate;
                }
              }
            }

            final putaranId = groupSlots.first['putaran_id'] as String;
            final completedCount = completedSlotsCount[putaranId] ?? 0;
            final progressPercent = (completedCount / 30.0) * 100;

            programs.add({
              'type': 'GROUP',
              'title': groupData['nama_grup'] as String,
              'code': groupData['kode_gk_unik'] as String?,
              'progress': progressPercent,
              'updated_at': latestUpdated,
              'groupId': groupId,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching active group slots: $e');
    }

    programs.sort((a, b) => (b['updated_at'] as DateTime).compareTo(a['updated_at'] as DateTime));
    return programs;
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
            if (payload.eventType == PostgresChangeEvent.insert) {
              _showLocalNotification(payload.newRecord);
            }
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

  Future<bool> _isWithinPrayerTimeRange() async {
    try {
      final savedLoc = await PrayerTimeService.getSavedLocation();
      if (savedLoc == null) return false;

      final lat = savedLoc['lat'];
      final lng = savedLoc['lng'];
      if (lat == null || lng == null) return false;

      final city = await PrayerTimeService.getSavedCity() ?? 'Lokasi';
      final calcMethod = await PrayerTimeService.getCalcMethod();
      final madhab = await PrayerTimeService.getMadhab();

      final prayerTimes = PrayerTimeService.calculatePrayerTimes(
        lat: lat,
        lng: lng,
        date: DateTime.now(),
        locationName: city,
        calcMethod: calcMethod,
        madhab: madhab,
      );

      final now = DateTime.now();
      for (final entry in prayerTimes.entries) {
        if (!entry.isFard) continue; // Dzuhur, Ashar, Maghrib, Isya, Subuh
        final diff = entry.time.difference(now).abs();
        if (diff.inMinutes <= 15) {
          debugPrint('⏳ [Overlap Alert] Current time is within 15 minutes of ${entry.name} (${entry.time}). Notification will be silent.');
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error checking prayer time overlap: $e');
    }
    return false;
  }

  Future<void> _showLocalNotification(Map<String, dynamic> record) async {
    final title = record['title'] as String? ?? 'Notifikasi Baru';
    final body = record['body'] as String? ?? '';

    // 1. Check settings
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.groupNotifEnabled) {
      debugPrint('🔔 [Local Notif] Group notifications are disabled in settings.');
      return;
    }

    // 2. Check if the sender is current user
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (record['sender_id'] == myId) {
      debugPrint('🔔 [Local Notif] Self-triggered notification. Skipping.');
      return;
    }

    // 3. Check if we are within a prayer time window
    final isSilent = await _isWithinPrayerTimeRange();

    try {
      final androidDetails = AndroidNotificationDetails(
        isSilent ? 'group_notif_silent' : 'group_notif_default',
        isSilent ? context.translate('home_notif_silent_title') : context.translate('home_notif_default_title'),
        channelDescription: isSilent 
            ? context.translate('home_notif_silent_desc')
            : context.translate('home_notif_default_desc'),
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: !isSilent,
        enableVibration: !isSilent,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !isSilent,
      );

      final notifDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

      // Generate unique notification ID
      final notifId = record['id'].hashCode;

      await _localNotifPlugin.show(
        notifId,
        title,
        body,
        notifDetails,
      );
      debugPrint('🔔 [Local Notif] Notification shown successfully (Silent: $isSilent).');
    } catch (e) {
      debugPrint('🔔 [Local Notif] Error showing notification: $e');
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
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
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final user = authProvider.user;
    final displayName = user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@')[0] ??
        context.translate('home_fallback_name');
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
                  const SizedBox(height: 12),
                  // Header
                  _buildHeader(context, displayName, avatarUrl, authProvider),
                  const SizedBox(height: 18),
                  // Personal History Card
                  _buildPersonalHistoryCard(context),
                  // Active Khataman Section
                  _buildActiveKhatamanSection(context),
                  const SizedBox(height: 18),
                  // Section Title
                  Text(
                    context.translate('home_start_now'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureCard(
                    context,
                    icon: Icons.menu_book_rounded,
                    title: context.translate('home_feat_mushaf_title'),
                    subtitle: context.translate('home_feat_mushaf_subtitle'),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF009688), Color(0xFF004D40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MushafListScreen()),
                    ).then((_) {
                      _loadActivePrograms();
                      _loadPersonalStats();
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildFeatureCard(
                    context,
                    icon: Icons.person_rounded,
                    title: context.translate('home_feat_mandiri_title'),
                    subtitle: context.translate('home_feat_mandiri_subtitle'),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2ECC71), Color(0xFF1A8A4A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MandiriScreen()),
                    ).then((_) {
                      _loadActivePrograms();
                      _loadPersonalStats();
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildFeatureCard(
                    context,
                    icon: Icons.group_rounded,
                    title: context.translate('home_feat_group_title'),
                    subtitle: context.translate('home_feat_group_subtitle'),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3F3D8B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GroupScreen()),
                    ).then((_) {
                      _loadActivePrograms();
                      _loadPersonalStats();
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildFeatureCard(
                    context,
                    icon: Icons.access_time_rounded,
                    title: context.translate('home_feat_prayer_title'),
                    subtitle: context.translate('home_feat_prayer_subtitle'),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00BCD4), Color(0xFF00838F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PrayerTimeScreen()),
                    ).then((_) {
                      _loadActivePrograms();
                      _loadPersonalStats();
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildFeatureCard(
                    context,
                    icon: Icons.explore_rounded,
                    title: context.translate('home_feat_qibla_title'),
                    subtitle: context.translate('home_feat_qibla_subtitle'),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9800), Color(0xFFE65100)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QiblaScreen()),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Stats Row
                  _buildStatsRow(context),
                  const SizedBox(height: 12),
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
                  onBackgroundImageError: (_, __) {},
                  child: avatarUrl == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.translate('home_greeting'),
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
                  tooltip: context.translate('home_tooltip_notification'),
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
              tooltip: context.translate('home_tooltip_settings'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveKhatamanSection(BuildContext context) {
    if (_loadingActivePrograms) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.translate('home_active_khataman'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            _buildHomeShimmerCard(),
            _buildHomeShimmerCard(),
          ],
        ),
      );
    }

    if (_activePrograms.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasMoreThanTwo = _activePrograms.length > 2;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.translate('home_active_khataman'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 10),
          _buildActiveKhatamanList(),
          if (hasMoreThanTwo) ...[
            const SizedBox(height: 4),
            _buildExpandCollapseButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildShimmerBox({double width = double.infinity, double height = 16, double radius = 8}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB);
    final highlightColor = isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6);

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (_, __) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + _shimmerController.value * 3, 0),
              end: Alignment(-0.5 + _shimmerController.value * 3, 0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeShimmerCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? AppTheme.primaryGreen.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.2),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildShimmerBox(width: 50, height: 18, radius: 8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShimmerBox(height: 14, radius: 6),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildShimmerBox(height: 6, radius: 4),
                    ),
                    const SizedBox(width: 12),
                    _buildShimmerBox(width: 36, height: 14, radius: 4),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildShimmerBox(width: 24, height: 24, radius: 12),
        ],
      ),
    );
  }

  Widget _buildActiveKhatamanList() {
    if (_isExpanded) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            children: _activePrograms.map((item) => _buildShortcutCard(context, item)).toList(),
          ),
        ),
      );
    } else {
      final displayItems = _activePrograms.take(2).toList();
      return Column(
        children: displayItems.map((item) => _buildShortcutCard(context, item)).toList(),
      );
    }
  }

  Widget _buildExpandCollapseButton() {
    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isExpanded ? context.translate('home_show_less') : context.translate('home_show_more'),
              style: const TextStyle(
                color: AppTheme.primaryGreen,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppTheme.primaryGreen,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildShortcutCard(BuildContext context, Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGroup = item['type'] == 'GROUP';
    final progress = item['progress'] as double;
    final progressText = '${progress.toStringAsFixed(1)}%';

    return GestureDetector(
      onTap: () {
        if (isGroup) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: item['groupId'] as String),
            ),
          ).then((_) {
            _loadActivePrograms();
            _loadPersonalStats();
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MandiriScreen(),
            ),
          ).then((_) {
            _loadActivePrograms();
            _loadPersonalStats();
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark 
                ? AppTheme.primaryGreen.withOpacity(0.3) 
                : Colors.grey.withOpacity(0.2),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isGroup
                              ? const Color(0xFF6C63FF).withOpacity(isDark ? 0.18 : 0.1)
                              : const Color(0xFF2ECC71).withOpacity(isDark ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isGroup
                                ? const Color(0xFF6C63FF).withOpacity(0.3)
                                : const Color(0xFF2ECC71).withOpacity(0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isGroup ? context.translate('home_type_group') : context.translate('home_type_mandiri'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isGroup ? const Color(0xFF6C63FF) : const Color(0xFF2ECC71),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['title'] as String,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGroup && item['code'] != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '#${item['code']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress / 100,
                            minHeight: 6,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isGroup ? const Color(0xFF6C63FF) : const Color(0xFF2ECC71),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        progressText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 24,
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
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
                  Container(
                    constraints: const BoxConstraints(minHeight: 39),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
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
        Expanded(child: _statCard(context, '30', context.translate('home_stat_total_juz'), Icons.layers_rounded, AppTheme.primaryGreen)),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            '114',
            context.translate('home_stat_surah'),
            Icons.menu_book_rounded,
            AppTheme.accentGold,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SurahInfoScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _statCard(context, '6236', context.translate('home_stat_ayat'), Icons.format_list_numbered_rounded, AppTheme.accentTeal)),
      ],
    );
  }

  Widget _statCard(BuildContext context, String value, String label, IconData icon, Color color, {VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark 
                ? AppTheme.primaryGreen.withOpacity(0.3) 
                : AppTheme.primaryGreen.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
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
        ).then((_) {
          _loadPersonalStats();
          _loadActivePrograms();
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: cardBgGradient,
          borderRadius: BorderRadius.circular(16),
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
                    context.translate('home_history_header'),
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
                        ? context.translate('home_history_title_completed').replaceAll('{count}', '$_personalKhatamCount')
                        : context.translate('home_history_title_empty'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.translate('home_history_subtitle'),
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

  void _showSnackbarHome(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : AppTheme.primaryGreen,
    ));
  }

  void _initDeepLinkListener() async {
    // 1. Handle initial link (when app is opened from cold start by the link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Deep Link Initial error: $e');
    }

    // 2. Handle subsequent links (when app is already running/resumed)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link Stream error: $err');
    });
  }

  void _handleDeepLink(Uri uri) async {
    debugPrint('🔗 [Deep Link] Received URI: $uri');
    if (uri.path == '/join') {
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        _processGroupCode(code);
      }
    }
  }

  void _processGroupCode(String code) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      ),
    );

    try {
      final response = await Supabase.instance.client
          .from('groups')
          .select('id_group, nama_grup, visibility')
          .eq('kode_gk_unik', code)
          .maybeSingle();

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (response == null) {
        _showSnackbarHome(context.translate('home_join_group_not_found').replaceAll('{code}', code), isError: true);
        return;
      }

      final groupId = response['id_group'] as String;
      final groupName = response['nama_grup'] as String;
      final visibility = response['visibility'] as String;

      final memberCheck = await Supabase.instance.client
          .from('group_members')
          .select('approval_status')
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .maybeSingle();

      if (!mounted) return;

      if (memberCheck != null) {
        final status = memberCheck['approval_status'] as String;
        if (status == 'APPROVED') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: groupId),
            ),
          ).then((_) {
            _loadActivePrograms();
            _loadPersonalStats();
          });
        } else if (status == 'PENDING') {
          _showSnackbarHome(context.translate('home_join_group_pending').replaceAll('{groupName}', groupName));
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const GroupScreen(),
            ),
          ).then((_) {
            _loadActivePrograms();
            _loadPersonalStats();
          });
        } else {
          _showSnackbarHome(context.translate('home_join_group_rejected').replaceAll('{groupName}', groupName), isError: true);
        }
      } else {
        _showJoinConfirmationDialog(groupId, groupName, visibility, code);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if open
        _showSnackbarHome(context.translate('home_join_group_failed_link').replaceAll('{error}', e.toString()), isError: true);
      }
    }
  }

  void _showJoinConfirmationDialog(String groupId, String groupName, String visibility, String code) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFFAFCFA),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.group_add_rounded, color: AppTheme.primaryGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.translate('home_join_dialog_title'),
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1D2A22),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            context.translate('home_join_dialog_body').replaceAll('{groupName}', groupName).replaceAll('{code}', code),
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                context.translate('home_join_dialog_cancel'),
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                _joinGroupFromLink(groupId, groupName, visibility);
              },
              child: Text(context.translate('home_join_dialog_confirm'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _joinGroupFromLink(String groupId, String groupName, String visibility) async {
    final isPrivate = visibility == 'PRIVATE';
    final status = isPrivate ? 'PENDING' : 'APPROVED';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      ),
    );

    try {
      await Supabase.instance.client.from('group_members').insert({
        'group_id': groupId,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'approval_status': status,
      });

      final groupRes = await Supabase.instance.client
          .from('groups')
          .select('creator_id')
          .eq('id_group', groupId)
          .maybeSingle();

      if (groupRes != null) {
        final creatorId = groupRes['creator_id'] as String?;
        final senderName = Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] as String? ??
            Supabase.instance.client.auth.currentUser?.email?.split('@')[0] ??
            'Seseorang';

        if (creatorId != null && creatorId != Supabase.instance.client.auth.currentUser?.id) {
          // Bersihkan notifikasi join lama agar tidak bertumpuk
          await NotificationService.deleteJoinNotifications(
            groupId: groupId,
            senderId: Supabase.instance.client.auth.currentUser!.id,
          );

          if (isPrivate) {
            await NotificationService.send(
              userId: creatorId,
              type: 'JOIN_REQUEST',
              title: 'Permintaan Bergabung',
              body: '$senderName meminta bergabung ke grup "$groupName"',
              groupId: groupId,
              senderId: Supabase.instance.client.auth.currentUser?.id,
            );
          } else {
            await NotificationService.send(
              userId: creatorId,
              type: 'MEMBER_JOINED',
              title: 'Anggota Baru Bergabung',
              body: '$senderName telah bergabung ke grup "$groupName"',
              groupId: groupId,
              senderId: Supabase.instance.client.auth.currentUser?.id,
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (isPrivate) {
        _showSnackbarHome(context.translate('home_join_sent_pending'));
      } else {
        _showSnackbarHome(context.translate('home_join_success').replaceAll('{groupName}', groupName));
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupDetailScreen(groupId: groupId),
          ),
        ).then((_) {
          _loadActivePrograms();
          _loadPersonalStats();
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showSnackbarHome(context.translate('home_join_failed').replaceAll('{error}', e.toString()), isError: true);
      }
    }
  }
}