import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import 'package:share_plus/share_plus.dart';
import '../components/juz_progress_card.dart';
import '../components/khatam_celebration.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/rolling_juz_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'juz_assignment_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;

  const GroupDetailScreen({Key? key, required this.groupId, this.groupName}) : super(key: key);

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _group;
  Map<String, dynamic>? _putaran;
  List<dynamic> _slots = [];
  List<dynamic> _members = [];
  RealtimeChannel? _subscription;
  bool _isLoading = true;
  int _pendingCount = 0;
  int _completedCount = 0;
  late AnimationController _shimmerController;
  late ScrollController _scrollController;
  double _shrinkFactor = 0.0;
  bool _isExited = false;

  final _memberSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    _fetchData();
    _setupRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_subscription != null) {
      try {
        _supabase.removeChannel(_subscription!);
      } catch (e) {
        debugPrint('🔄 [Realtime Group] Error removing channel on dispose: $e');
      }
    }
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _shimmerController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final double newFactor = (offset / 80.0).clamp(0.0, 1.0);
    if (newFactor != _shrinkFactor) {
      setState(() {
        _shrinkFactor = newFactor;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [App Lifecycle] App resumed in Group Detail. Refreshing data and subscription...');
      _fetchData(silent: true);
      _setupRealtime();
    }
  }

  void _setupRealtime() {
    final channelName = 'group_detail_${widget.groupId}';
    // debugPrint('🔄 [Realtime Group] Menghubungkan ke channel: $channelName...');

    // Bersihkan subscription lama jika ada
    if (_subscription != null) {
      try {
        _supabase.removeChannel(_subscription!);
      } catch (e) {
        debugPrint('🔄 [Realtime Group] Error removing old channel: $e');
      }
    }

    _subscription = _supabase.channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'slot_khataman',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Slot khataman changed. Refreshing...');
            if (mounted) _fetchData(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'putaran_siklus',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Putaran siklus changed. Refreshing...');
            if (mounted) _fetchData(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Group members changed. Refreshing...');
            if (mounted) _fetchData(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Group metadata changed. Refreshing...');
            if (mounted) _fetchData(silent: true);
          },
        );

    _subscription?.subscribe((status, [error]) {
      // debugPrint('🔄 [Realtime Group] Status: $status${error != null ? ', Error: $error' : ''}');
      
      // Re-koneksi otomatis jika terjadi error atau timeout
      if (status == RealtimeSubscribeStatus.channelError || 
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        // debugPrint('🔄 [Realtime Group] Terputus. Menghubungkan kembali dalam 3 detik...');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _setupRealtime();
          }
        });
      }
    });
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    try {
      final groupData = await _supabase
          .from('groups')
          .select()
          .eq('id_group', widget.groupId)
          .single();

      var pData = await _supabase
          .from('putaran_siklus')
          .select()
          .eq('group_id', widget.groupId)
          .order('nomor_putaran', ascending: false)
          .limit(1)
          .maybeSingle();

      List<dynamic> sData = [];
      if (pData != null) {
        // Join dengan tabel users untuk langsung dapat username
        sData = await _supabase
            .from('slot_khataman')
            .select('*, users(username)')
            .eq('putaran_id', pData['id_putaran'])
            .order('nomor_juz', ascending: true);

        // Uji kelengkapan siklus secara mandiri (Self-healing client-side)
        final completedSlotsCount = sData.where((s) => s['status_checklist'] == true).length;
        if (completedSlotsCount == 30 && pData['status_aktif_selesai'] == 'AKTIF') {
          debugPrint('🎉 [Sync] Semua 30 Juz selesai! Menandai putaran siklus sebagai SELESAI...');
          await _supabase
              .from('putaran_siklus')
              .update({'status_aktif_selesai': 'SELESAI'})
              .eq('id_putaran', pData['id_putaran']);

          // Kirim notifikasi khataman selesai ke semua anggota grup
          try {
            final gName = widget.groupName ?? groupData['nama_grup'] ?? 'Grup';
            await NotificationService.sendToGroup(
              groupId: widget.groupId,
              type: 'KHATAMAN_COMPLETE',
              title: '🎉 Khataman Selesai! Alhamdulillah!',
              body: 'Alhamdulillah, khataman di grup "$gName" telah selesai (30/30 Juz). Semoga berkah!',
            );
          } catch (notifErr) {
            debugPrint('Error sending khataman complete notification: $notifErr');
          }

          pData['status_aktif_selesai'] = 'SELESAI';
          _showCelebration();
        }
      }

      int pCount = 0;
      if (groupData['creator_id'] == _supabase.auth.currentUser?.id) {
        final pendingRes = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', widget.groupId)
            .eq('approval_status', 'PENDING');
        pCount = (pendingRes as List).length;
      }

      final membersData = await _supabase
          .from('group_members')
          .select('*, users(username, avatar_url)')
          .eq('group_id', widget.groupId)
          .eq('approval_status', 'APPROVED');
      final membersList = List<dynamic>.from(membersData);

      final completedCountRes = await _supabase
          .from('putaran_siklus')
          .select('id_putaran')
          .eq('group_id', widget.groupId)
          .eq('status_aktif_selesai', 'SELESAI');
      final completedCount = (completedCountRes as List).length;

      // Check if this group was marked completed/archived locally by this user
      try {
        final prefs = await SharedPreferences.getInstance();
        final localArchived = prefs.getBool('archived_group_${widget.groupId}_${pData?['id_putaran']}') ?? false;
        if (localArchived) {
          groupData['visibility'] = 'ARCHIVED';
        }
      } catch (_) {}

      // Self-healing: Creator silently synchronizes permanent group archiving if round is complete
      if (groupData['creator_id'] == _supabase.auth.currentUser?.id &&
          groupData['visibility'] != 'ARCHIVED' &&
          pData != null &&
          pData['status_aktif_selesai'] == 'SELESAI' &&
          groupData['tipe_grup'] != 'RUTIN') {
        debugPrint('🔒 [Self-Healing] Creator detected completed round. Archiving group permanently in background...');
        try {
          await _supabase
              .from('groups')
              .update({'visibility': 'ARCHIVED'})
              .eq('id_group', widget.groupId);
          groupData['visibility'] = 'ARCHIVED';
        } catch (shErr) {
          debugPrint('Error in silent self-healing archive: $shErr');
        }
      }

      final isCreator = groupData['creator_id'] == _supabase.auth.currentUser?.id;
      final isCurrentUserMember = membersList.any((m) => m['user_id'] == _supabase.auth.currentUser?.id);

      if (!isCreator && !isCurrentUserMember && !_isExited && mounted) {
        _isExited = true;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Anda telah dikeluarkan dari grup "${groupData['nama_grup'] ?? 'Grup'}" oleh admin.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (mounted) {
        setState(() {
          _group = groupData;
          _putaran = pData;
          _slots = sData;
          _members = membersList;
          _pendingCount = pCount;
          _completedCount = completedCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCelebration() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Confetti particle system rendering underneath
              const Positioned.fill(
                child: PremiumConfettiOverlay(),
              ),
              
              // Celebratory Card Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: AppTheme.accentGold.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gold trophy with glowing shadow
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: AppTheme.accentGold,
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Maa Syaa Allah! 🎉',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.darkGreen,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Alhamdulillah! Grup Anda telah menyelesaikan target 30 Juz Al-Quran pada putaran ini.\n\nSemoga menjadi berkah dan cahaya bagi seluruh anggota kelompok. Aamiin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Alhamdulillah',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startNewPutaran(int assignMode) async {
    try {
      final now = DateUtils.dateOnly(DateTime.now());
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 1)),
        lastDate: now.add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(
          start: now,
          end: now.add(const Duration(days: 7)),
        ),
        helpText: 'Pilih Periode Khataman',
        cancelText: 'Batal',
        confirmText: 'Pilih',
        saveText: 'Simpan',
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: isDark
                  ? const ColorScheme.dark(
                      primary: AppTheme.primaryGreen,
                      onPrimary: Colors.white,
                      surface: AppTheme.bgCard,
                      onSurface: AppTheme.textPrimary,
                      secondary: AppTheme.accentGold,
                    )
                  : const ColorScheme.light(
                      primary: AppTheme.primaryGreen,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Color(0xFF1A1A2E),
                      secondary: AppTheme.accentGold,
                    ), dialogTheme: DialogThemeData(backgroundColor: isDark ? AppTheme.bgCard : Colors.white),
            ),
            child: child!,
          );
        },
      );

      if (picked == null) {
        return; // Batalkan jika user membatalkan
      }

      final startDate = DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0);
      final endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);

      int nextPutaranNum = 1;
      try {
        final lastPutaranRes = await _supabase
            .from('putaran_siklus')
            .select('nomor_putaran')
            .eq('group_id', widget.groupId)
            .order('nomor_putaran', ascending: false)
            .limit(1)
            .maybeSingle();

        if (lastPutaranRes != null && lastPutaranRes['nomor_putaran'] != null) {
          nextPutaranNum = (lastPutaranRes['nomor_putaran'] as int) + 1;
        }
      } catch (e) {
        debugPrint('Error fetching last putaran number: $e');
      }

      final newPutaran = await _supabase.from('putaran_siklus').insert({
        'group_id': widget.groupId,
        'nomor_putaran': nextPutaranNum,
        'start_date': startDate.toIso8601String(),
        'target_deadline': endDate.toIso8601String()
      }).select().single();

      if (assignMode == 0) {
        // Hanya anggota dengan status APPROVED yang bisa ikut siklus
        final members = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', widget.groupId)
            .eq('approval_status', 'APPROVED');
        if (members.isNotEmpty) {
          List<Map<String, dynamic>> slotsToInsert = [];
          for (int i = 1; i <= 30; i++) {
            final assignee = members[(i - 1) % members.length]['user_id'];
            slotsToInsert.add({
              'putaran_id': newPutaran['id_putaran'],
              'nomor_juz': i,
              'user_id': assignee
            });
          }
          await _supabase.from('slot_khataman').insert(slotsToInsert);
        }
      } else if (assignMode == 3) {
        // Rolling Juz: Acak cerdas berdasarkan riwayat personal
        try {
          final groupName = _group?['nama_grup'] ?? 'Khataman';
          final assignments = await RollingJuzService.generateRollingAssignment(
            groupId: widget.groupId,
            groupName: groupName,
          );
          final slotsToInsert = assignments.map((a) => {
            'putaran_id': newPutaran['id_putaran'],
            'nomor_juz': a['nomor_juz'],
            'user_id': a['user_id'],
          }).toList();
          await _supabase.from('slot_khataman').insert(slotsToInsert);
        } catch (e) {
          debugPrint('Error Rolling Juz: $e');
          // Fallback to empty slots if Rolling Juz fails
          final slotsToInsert = List.generate(30, (i) => {
            'putaran_id': newPutaran['id_putaran'],
            'nomor_juz': i + 1,
            'user_id': null,
          });
          await _supabase.from('slot_khataman').insert(slotsToInsert);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Rolling Juz gagal: $e. Slot dibuat kosong.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        List<Map<String, dynamic>> slotsToInsert = [];
        for (int i = 1; i <= 30; i++) {
          slotsToInsert.add({
            'putaran_id': newPutaran['id_putaran'],
            'nomor_juz': i,
            'user_id': null
          });
        }
        await _supabase.from('slot_khataman').insert(slotsToInsert);
      }

      // Send group notifications about the new cycle!
      try {
        final groupName = _group?['nama_grup'] ?? 'Grup';
        final formattedDate = '${endDate.day}/${endDate.month}/${endDate.year}';
        final adminName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
            _supabase.auth.currentUser?.email?.split('@')[0] ??
            'Admin';
            
        await NotificationService.sendToGroup(
          groupId: widget.groupId,
          type: 'CYCLE_STARTED',
          title: '📖 Putaran Baru Dimulai!',
          body: '$adminName memulai putaran baru di grup "$groupName" dengan tenggat waktu $formattedDate.',
          excludeUserId: _supabase.auth.currentUser?.id,
        );
      } catch (e) {
        debugPrint('Error sending cycle started notif: $e');
      }

      await _fetchData();

      // If manual brush assignment mode, direct immediately to the brush page
      if (assignMode == 2) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JuzAssignmentScreen(
                groupId: widget.groupId,
                groupName: _group?['nama_grup'] ?? 'Khataman',
              ),
            ),
          ).then((_) {
            if (mounted) {
              _fetchData(silent: true);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _showNewPutaranDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRutinGroup = _group?['tipe_grup'] == 'RUTIN';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Mulai Putaran Baru?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Grup Anda telah menyelesaikan siklus khataman ini.\n\nSilakan pilih metode pembagian Juz untuk putaran berikutnya:',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          if (isRutinGroup)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _startNewPutaran(3);
              },
              icon: const Icon(Icons.shuffle_rounded, size: 16),
              label: const Text('Rolling Juz', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startNewPutaran(0);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
            child: const Text('Bagi Rata', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startNewPutaran(2);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF0D5257) : const Color(0xFF007A7C),
            ),
            child: const Text('Bagi Manual', style: TextStyle(color: Colors.white)),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startNewPutaran(1);
            },
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.accentGold)),
            child: const Text('Klaim Mandiri', style: TextStyle(color: AppTheme.accentGold)),
          ),
        ],
      ),
    );
  }

  Future<void> _claimSlot(int slotId) async {
    try {
      if (_group?['limit_juz'] == true) {
        final approvedMembersCount = _members.where((m) => m['approval_status'] == 'APPROVED').length;
        final memberCount = approvedMembersCount == 0 ? 1 : approvedMembersCount;
        final maxSlots = (30 / memberCount).ceil();

        final myUserId = _supabase.auth.currentUser?.id;
        final myClaimsCount = _slots.where((s) => s['user_id'] == myUserId).length;

        if (myClaimsCount >= maxSlots) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ Batas pengambilan juz terpenuhi!\nMaksimal $maxSlots juz per anggota.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      // Update HANYA jika user_id masih NULL (slot belum diambil orang lain)
      final result = await _supabase
          .from('slot_khataman')
          .update({
            'user_id': _supabase.auth.currentUser?.id,
          })
          .eq('id_slot', slotId)
          .isFilter('user_id', null) // ← Kunci: hanya update jika masih kosong
          .select();

      if (result.isEmpty) {
        // Update tidak berhasil → slot sudah diambil orang lain
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Juz ini sudah diambil anggota lain. Pilih Juz lain.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Juz berhasil diambil!'),
              backgroundColor: AppTheme.primaryGreen,
            ),
          );
        }
      }
      _fetchData(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil Juz: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }


  /// Admin langsung melepas slot (digunakan oleh admin approval)
  Future<void> _releaseSlot(int slotId) async {
    final slotObj = _slots.firstWhere(
      (s) => s['id_slot'] == slotId,
      orElse: () => <String, dynamic>{},
    );
    final Map<String, dynamic> slotMap = slotObj is Map<String, dynamic> ? slotObj : {};
    String? prevUsername;
    if (slotMap.isNotEmpty) {
      final usersMap = slotMap['users'] as Map<String, dynamic>?;
      if (usersMap != null) {
        prevUsername = usersMap['username'] as String?;
      }
    }

    await _supabase.from('slot_khataman').update({
      'user_id': null,
      'ayat_terakhir_input': 0,
      'status_checklist': false,
      'approval_lepas_status': null,
      if (prevUsername != null) 'username_sebelumnya': prevUsername,
    }).eq('id_slot', slotId);
    _fetchData(silent: true);
  }

  Future<void> _requestReleaseSlot(int slotId) async {
    try {
      final myUserId = _supabase.auth.currentUser?.id;
      final isAdmin = myUserId == _group?['creator_id'];

      if (isAdmin) {
        // Jika yang melepaskan juz adalah admin, maka dia tidak perlu pengajuan, langsung lepas!
        await _releaseSlot(slotId);
        
        // Kirimkan notifikasi ke anggota bahwa admin melepas juz
        try {
          final userRes = await _supabase
              .from('users')
              .select('username')
              .eq('id_user', myUserId!)
              .maybeSingle();
          final String username = userRes?['username'] as String? ?? '';
          final senderName = username.isNotEmpty ? '@$username' : 'Admin';
          final gName = _group?['nama_grup'] ?? 'Grup';
          final slotObj = _slots.firstWhere(
            (s) => s['id_slot'] == slotId,
            orElse: () => <String, dynamic>{},
          );
          final Map<String, dynamic> slotMap = slotObj is Map<String, dynamic> ? slotObj : {};
          int juzNum = 0;
          if (slotMap.isNotEmpty) {
            juzNum = slotMap['nomor_juz'] as int? ?? 0;
          }

          await NotificationService.sendToGroup(
            groupId: widget.groupId,
            type: 'JUZ_RELEASED',
            title: 'Juz Dilepas oleh Admin 🚪',
            body: '$senderName telah melepas kembali Juz $juzNum di grup "$gName". Sekarang slot ini kosong dan bebas diambil!',
            excludeUserId: myUserId,
          );
        } catch (notifErr) {
          debugPrint('Error sending release slot by admin notification: $notifErr');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Juz berhasil dilepas secara langsung dan notifikasi telah dikirim ke anggota.'),
              backgroundColor: AppTheme.primaryGreen,
            ),
          );
        }
        return;
      }

      // Cek kuota PENDING: maks 2 Juz PENDING bersamaan per anggota
      if (myUserId != null) {
        final pendingSlots = _slots.where((s) =>
          s['user_id'] == myUserId &&
          s['approval_lepas_status'] == 'PENDING'
        ).length;
        if (pendingSlots >= 2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Maks 2 pengajuan lepas Juz bersamaan. Tunggu admin merespons.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      await _supabase.from('slot_khataman').update({
        'approval_lepas_status': 'PENDING',
      }).eq('id_slot', slotId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📤 Pengajuan lepas Juz dikirim. Menunggu persetujuan admin.'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
      _fetchData(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengajukan lepas Juz: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Anggota membatalkan pengajuan lepas (status PENDING → NULL)
  Future<void> _cancelReleaseRequest(int slotId) async {
    try {
      await _supabase.from('slot_khataman').update({
        'approval_lepas_status': null,
      }).eq('id_slot', slotId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('↩️ Pengajuan lepas Juz dibatalkan.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
      _fetchData(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membatalkan pengajuan: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _formatDateRange(String? startStr, String? endStr) {
    if (startStr == null || endStr == null) return '';
    try {
      final start = DateTime.parse(startStr).toLocal();
      final end = DateTime.parse(endStr).toLocal();
      
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 
        'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      
      final startDay = start.day;
      final startMonth = months[start.month - 1];
      final startYear = start.year;
      
      final endDay = end.day;
      final endMonth = months[end.month - 1];
      final endYear = end.year;
      
      if (startYear == endYear) {
        if (startMonth == endMonth) {
          if (startDay == endDay) {
            return '$startDay $startMonth $startYear';
          }
          return '$startDay - $endDay $startMonth $startYear';
        } else {
          return '$startDay $startMonth - $endDay $endMonth $startYear';
        }
      } else {
        return '$startDay $startMonth $startYear - $endDay $endMonth $endYear';
      }
    } catch (e) {
      return '';
    }
  }

  String _getRemainingTime(String? endStr) {
    if (endStr == null) return '';
    try {
      final end = DateTime.parse(endStr).toLocal();
      final now = DateTime.now();
      final difference = end.difference(now);
      
      if (difference.isNegative) {
        return 'Waktu habis';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} hari tersisa';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} jam tersisa';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} menit tersisa';
      } else {
        return 'Beberapa detik tersisa';
      }
    } catch (e) {
      return '';
    }
  }

  // ─────────────────────────────────────────────────────────
  // Kelola Anggota (Persetujuan & Hapus Anggota)
  // ─────────────────────────────────────────────────────────
  void _showManageMembersDialog() async {
    _memberSearchController.clear();
    try {
      // 1. Fetch current members
      final membersData = await _supabase
          .from('group_members')
          .select('user_id, approval_status, prioritas_jatah, users(username, email, avatar_url)')
          .eq('group_id', widget.groupId)
          .neq('user_id', _supabase.auth.currentUser!.id) // Sembunyikan admin dari list
          .order('approval_status', ascending: false); // PENDING di atas, APPROVED di bawah

      // 2. Fetch all other registered users in the database
      final usersData = await _supabase
          .from('users')
          .select('id_user, username, email, avatar_url')
          .neq('id_user', _supabase.auth.currentUser!.id);

      if (!mounted) return;

      final membersList = List<Map<String, dynamic>>.from(membersData);
      
      // Filter out users who are already in the group
      final existingIds = membersList.map((m) => m['user_id'] as String).toSet();
      existingIds.add(_supabase.auth.currentUser!.id);

      final availableUsers = List<Map<String, dynamic>>.from(usersData)
          .where((u) => !existingIds.contains(u['id_user']))
          .toList();

      List<Map<String, dynamic>> filteredAvailableUsers = List.from(availableUsers);

      // State variable for sheet view toggle
      bool showAddMember = false;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        isDismissible: false,
        backgroundColor: Colors.transparent,
        builder: (BuildContext sheetContext) {
          return StatefulBuilder(
            builder: (modalContext, setModalState) {
              final isDark = Theme.of(modalContext).brightness == Brightness.dark;
              final surfaceColor = isDark ? const Color(0xFF161B22) : const Color(0xFFFAFCFA);
              final inputBgColor = isDark ? const Color(0xFF1F2937) : const Color(0xFFEDF2ED);
              final borderColor = isDark ? const Color(0xFF30363D) : const Color(0xFFD4DDD6);
              final onSurfaceColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1D2A22);
              final onSurfaceVariantColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF5F6E65);

              return Container(
                height: MediaQuery.of(modalContext).size.height * 0.85,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                    child: Column(
                      children: [
                        // ── Drag Handle & Header ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (showAddMember)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: ClipOval(
                                        child: Material(
                                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                          child: InkWell(
                                            onTap: () {
                                              setModalState(() {
                                                showAddMember = false;
                                                _memberSearchController.clear();
                                                filteredAvailableUsers = List.from(availableUsers);
                                              });
                                            },
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Icon(Icons.arrow_back_rounded, size: 18, color: onSurfaceColor),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.manage_accounts_rounded,
                                      color: AppTheme.accentGold,
                                      size: 28,
                                    ),
                                  if (!showAddMember) const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          showAddMember ? 'Tambah Anggota Baru' : 'Kelola Anggota',
                                          style: TextStyle(
                                            color: onSurfaceColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          showAddMember 
                                              ? 'Cari dan tambahkan anggota baru ke grup' 
                                              : 'Tambah anggota baru atau kelola anggota saat ini',
                                          style: TextStyle(
                                            color: onSurfaceVariantColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ClipOval(
                                    child: Material(
                                      color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.pop(modalContext);
                                        },
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                              width: 1,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: onSurfaceVariantColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── Body Scroll View ──
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.only(
                              left: 20,
                              right: 20,
                              top: 8,
                              bottom: MediaQuery.of(modalContext).padding.bottom + 24,
                            ),
                            children: [
                              if (showAddMember) ...[
                                // ── VIEW: TAMBAH ANGGOTA ──
                                // Search Input
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16, top: 4),
                                  child: TextField(
                                    controller: _memberSearchController,
                                    autofocus: false,
                                    style: TextStyle(color: onSurfaceColor, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Cari username untuk ditambahkan...',
                                      filled: true,
                                      fillColor: inputBgColor,
                                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primaryGreen),
                                      suffixIcon: _memberSearchController.text.isNotEmpty
                                          ? IconButton(
                                              icon: Icon(Icons.clear_rounded, size: 18, color: onSurfaceVariantColor),
                                              onPressed: () {
                                                _memberSearchController.clear();
                                                setModalState(() {
                                                  filteredAvailableUsers = List.from(availableUsers);
                                                });
                                              },
                                            )
                                          : null,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(color: borderColor),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    onChanged: (val) {
                                      final query = val.trim().toLowerCase();
                                      setModalState(() {
                                        filteredAvailableUsers = availableUsers
                                            .where((u) => (u['username'] ?? '').toString().toLowerCase().contains(query))
                                            .toList();
                                      });
                                    },
                                  ),
                                ),
                                
                                if (filteredAvailableUsers.isNotEmpty) ...[
                                  ...filteredAvailableUsers.map((u) {
                                    final avatar = u['avatar_url'] as String?;
                                    final name = u['username'] ?? 'User';
                                    final email = u['email'] ?? '';

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1F2937).withOpacity(0.4) : const Color(0xFFEDF2ED).withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: borderColor.withOpacity(0.5), width: 0.5),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                        leading: CircleAvatar(
                                          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                                          child: avatar == null ? const Icon(Icons.person) : null,
                                        ),
                                        title: Text(name, style: TextStyle(color: onSurfaceColor, fontSize: 14, fontWeight: FontWeight.w600)),
                                        subtitle: Text(email, style: TextStyle(color: onSurfaceVariantColor, fontSize: 11)),
                                        trailing: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryGreen,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            minimumSize: Size.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            try {
                                              await _supabase.from('group_members').insert({
                                                'group_id': widget.groupId,
                                                'user_id': u['id_user'],
                                                'approval_status': 'APPROVED',
                                              });

                                              // Kirim notifikasi ke anggota baru
                                              try {
                                                final gName = widget.groupName ?? _group?['nama_grup'] ?? 'Grup';
                                                await NotificationService.send(
                                                  userId: u['id_user'] as String,
                                                  type: 'JOIN_APPROVED',
                                                  title: 'Ditambahkan ke Grup Khataman',
                                                  body: 'Anda telah ditambahkan ke grup "$gName" oleh admin.',
                                                  groupId: widget.groupId,
                                                );
                                              } catch (notifErr) {
                                                print('Error sending added notification: $notifErr');
                                              }

                                              setModalState(() {
                                                final addedUser = u;
                                                membersList.insert(0, {
                                                  'user_id': addedUser['id_user'],
                                                  'approval_status': 'APPROVED',
                                                  'users': {
                                                    'username': addedUser['username'],
                                                    'avatar_url': addedUser['avatar_url'],
                                                    'email': 'Anggota Baru'
                                                  }
                                                });
                                                availableUsers.removeWhere((item) => item['id_user'] == addedUser['id_user']);
                                                filteredAvailableUsers.removeWhere((item) => item['id_user'] == addedUser['id_user']);
                                              });
                                              _fetchData(silent: true);

                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('${u['username'] ?? 'User'} berhasil ditambahkan ke grup'),
                                                    backgroundColor: AppTheme.primaryGreen,
                                                  ),
                                                );
                                              }
                                            } catch (err) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Gagal menambahkan: $err'), backgroundColor: Colors.redAccent),
                                              );
                                            }
                                          },
                                          child: const Text('Tambah', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ] else ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 32),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(Icons.person_search_rounded, size: 48, color: onSurfaceVariantColor.withOpacity(0.5)),
                                          const SizedBox(height: 12),
                                          Text(
                                            _memberSearchController.text.isNotEmpty
                                                ? 'Pengguna tidak ditemukan atau sudah bergabung.'
                                                : 'Mulai cari username untuk ditambahkan...',
                                            style: TextStyle(color: onSurfaceVariantColor, fontSize: 13),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ] else ...[
                                // ── VIEW: DAFTAR ANGGOTA SAAT INI ──
                                // Tombol Tambah Anggota Baru (Prominent)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16, top: 4),
                                  child: InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        showAddMember = true;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppTheme.primaryGreen.withOpacity(0.15),
                                            AppTheme.primaryGreen.withOpacity(0.05),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppTheme.primaryGreen.withOpacity(0.3),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.primaryGreen, size: 20),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Tambah Anggota Baru',
                                            style: TextStyle(
                                              color: isDark ? AppTheme.primaryGreen : AppTheme.darkGreen,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Header Anggota Saat Ini
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Daftar Anggota Saat Ini',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: onSurfaceVariantColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: borderColor.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${membersList.length} Orang',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: onSurfaceColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (membersList.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 32),
                                    child: Center(
                                      child: Text(
                                        'Belum ada anggota lain di grup ini.',
                                        style: TextStyle(color: onSurfaceVariantColor, fontStyle: FontStyle.italic, fontSize: 13),
                                      ),
                                    ),
                                  )
                                else
                                  ...membersList.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final member = entry.value;
                                    final user = member['users'] as Map<String, dynamic>? ?? {};
                                    final avatarUrl = user['avatar_url'] as String?;
                                    final isPending = member['approval_status'] == 'PENDING';

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: isPending
                                            ? AppTheme.accentGold.withOpacity(0.04)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isPending
                                              ? AppTheme.accentGold.withOpacity(0.3)
                                              : borderColor.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                        leading: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            CircleAvatar(
                                              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                              child: avatarUrl == null ? const Icon(Icons.person) : null,
                                            ),
                                            if (isPending)
                                              Container(
                                                decoration: BoxDecoration(color: surfaceColor, shape: BoxShape.circle),
                                                child: const Icon(Icons.hourglass_top_rounded, size: 14, color: AppTheme.accentGold),
                                              ),
                                          ],
                                        ),
                                        title: Text(user['username'] ?? 'User', style: TextStyle(color: onSurfaceColor, fontSize: 14, fontWeight: FontWeight.w600)),
                                        subtitle: Text(
                                          isPending ? 'Menunggu Persetujuan' : (user['email'] ?? 'Anggota Aktif'),
                                          style: TextStyle(
                                            color: isPending ? AppTheme.accentGold : onSurfaceVariantColor,
                                            fontSize: 11,
                                            fontWeight: isPending ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                        ),
                                        trailing: isPending
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryGreen, size: 24),
                                                    tooltip: 'Terima',
                                                    onPressed: () async {
                                                      try {
                                                        await _supabase
                                                            .from('group_members')
                                                            .update({'approval_status': 'APPROVED'})
                                                            .eq('user_id', member['user_id'])
                                                            .eq('group_id', widget.groupId);

                                                        // Kirim notifikasi ke anggota yang disetujui
                                                        try {
                                                          final gName = widget.groupName ?? _group?['nama_grup'] ?? 'Grup';
                                                          await NotificationService.send(
                                                            userId: member['user_id'] as String,
                                                            type: 'JOIN_APPROVED',
                                                            title: 'Permintaan Bergabung Disetujui',
                                                            body: 'Selamat! Permintaan Anda bergabung ke grup "$gName" telah disetujui.',
                                                            groupId: widget.groupId,
                                                          );
                                                        } catch (notifErr) {
                                                          print('Error sending approved notification: $notifErr');
                                                        }

                                                        setModalState(() => member['approval_status'] = 'APPROVED');
                                                        _fetchData(silent: true);

                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: Text('${user['username'] ?? 'User'} berhasil disetujui bergabung'),
                                                              backgroundColor: AppTheme.primaryGreen,
                                                            ),
                                                          );
                                                        }
                                                      } catch (e) {
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: Text('Gagal menyetujui: Koneksi bermasalah atau coba lagi ($e)'),
                                                              backgroundColor: Colors.redAccent,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 24),
                                                    tooltip: 'Tolak',
                                                    onPressed: () async {
                                                      final confirm = await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          backgroundColor: Theme.of(context).colorScheme.surface,
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                          title: const Text('Tolak Permintaan?'),
                                                          content: Text('Apakah Anda yakin ingin menolak permintaan bergabung dari ${user['username'] ?? 'pengguna ini'}?'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(ctx, false),
                                                              child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                                            ),
                                                            ElevatedButton(
                                                              onPressed: () => Navigator.pop(ctx, true),
                                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                              child: const Text('Tolak', style: TextStyle(color: Colors.white)),
                                                            ),
                                                          ],
                                                        ),
                                                      );

                                                      if (confirm != true) return;

                                                      try {
                                                        await _supabase
                                                            .from('group_members')
                                                            .delete()
                                                            .eq('user_id', member['user_id'])
                                                            .eq('group_id', widget.groupId);
                                                        setModalState(() => membersList.removeAt(i));
                                                        _fetchData(silent: true);

                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: Text('Permintaan bergabung ${user['username'] ?? 'User'} ditolak'),
                                                              backgroundColor: Colors.redAccent,
                                                            ),
                                                          );
                                                        }
                                                      } catch (e) {
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: Text('Gagal menolak permintaan: Koneksi bermasalah atau coba lagi ($e)'),
                                                              backgroundColor: Colors.redAccent,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    },
                                                  ),
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (_group?['tipe_grup'] == 'RUTIN') ...[
                                                    Tooltip(
                                                      message: 'Prioritas Jatah Kuota',
                                                      child: InkWell(
                                                        onTap: () async {
                                                          final currentPrioritas = member['prioritas_jatah'] == true;
                                                          final nextPrioritas = !currentPrioritas;
                                                          
                                                          try {
                                                            await _supabase
                                                                .from('group_members')
                                                                .update({'prioritas_jatah': nextPrioritas})
                                                                .eq('user_id', member['user_id'])
                                                                .eq('group_id', widget.groupId);
                                                                
                                                            setModalState(() {
                                                              member['prioritas_jatah'] = nextPrioritas;
                                                            });
                                                            
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                  nextPrioritas 
                                                                      ? '⭐ ${user['username']} mendapat prioritas jatah kuota!' 
                                                                      : '⚪ Prioritas jatah ${user['username']} dinonaktifkan.',
                                                                ),
                                                                backgroundColor: AppTheme.primaryGreen,
                                                              ),
                                                            );
                                                            _fetchData(silent: true);
                                                          } catch (e) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(
                                                                content: Text('Gagal mengubah prioritas: $e'),
                                                                backgroundColor: Colors.redAccent,
                                                              ),
                                                            );
                                                          }
                                                        },
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                                                          child: Icon(
                                                            member['prioritas_jatah'] == true
                                                                ? Icons.star_rounded
                                                                : Icons.star_border_rounded,
                                                            color: member['prioritas_jatah'] == true
                                                                ? AppTheme.accentGold
                                                                : onSurfaceVariantColor,
                                                            size: 22,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  IconButton(
                                                    icon: Icon(Icons.person_remove_rounded, color: Colors.redAccent.withOpacity(0.7), size: 20),
                                                    tooltip: 'Keluarkan Anggota',
                                                    onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      backgroundColor: Theme.of(context).colorScheme.surface,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                      title: const Text('Keluarkan Anggota?'),
                                                      content: Text('Apakah Anda yakin ingin mengeluarkan ${user['username'] ?? 'anggota ini'} dari grup? Semua slot yang dipegang yang bersangkutan akan dikosongkan kembali.'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, false),
                                                          child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () => Navigator.pop(ctx, true),
                                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                          child: const Text('Keluarkan', style: TextStyle(color: Colors.white)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm != true) return;

                                                  try {
                                                    final targetUserId = member['user_id'] as String;

                                                    // 1. Kirim notifikasi dikeluarkan dari grup
                                                    try {
                                                      final gName = widget.groupName ?? _group?['nama_grup'] ?? 'Grup';
                                                      await NotificationService.send(
                                                        userId: targetUserId,
                                                        type: 'JOIN_APPROVED',
                                                        title: 'Dikeluarkan dari Grup 🚪',
                                                        body: 'Anda telah dikeluarkan dari grup "$gName" oleh admin.',
                                                        groupId: null,
                                                      );
                                                    } catch (notifErr) {
                                                      debugPrint('Error sending removed notification: $notifErr');
                                                    }

                                                    // Gunakan adminClient (service_role) untuk membypass RLS 100% sukses
                                                    final adminClient = SupabaseClient(
                                                      dotenv.env['SUPABASE_URL'] ?? '',
                                                      dotenv.env['SUPABASE_ANON_KEY'] ?? '',
                                                    );

                                                    // 2. Pelepasan Juz terlebih dahulu (Logika database teratur)
                                                    // Ambil semua id_putaran dari grup ini
                                                    final putaranRes = await adminClient
                                                        .from('putaran_siklus')
                                                        .select('id_putaran')
                                                        .eq('group_id', widget.groupId);

                                                    final List<dynamic> putaranIds = (putaranRes as List).map((p) => p['id_putaran']).toList();

                                                    if (putaranIds.isNotEmpty) {
                                                       await adminClient
                                                           .from('slot_khataman')
                                                           .update({
                                                             'user_id': null,
                                                             'approval_lepas_status': null,
                                                             'username_sebelumnya': user['username'] ?? 'Anggota',
                                                           })
                                                           .inFilter('putaran_id', putaranIds)
                                                           .eq('user_id', targetUserId);
                                                     }

                                                    // 3. Hapus keanggotaan setelah slot bersih
                                                    await adminClient
                                                        .from('group_members')
                                                        .delete()
                                                        .eq('user_id', targetUserId)
                                                        .eq('group_id', widget.groupId);
                                                    
                                                    setModalState(() {
                                                      membersList.removeAt(i);
                                                      final returnedUser = {
                                                        'id_user': targetUserId,
                                                        'username': user['username'],
                                                        'email': user['email'],
                                                        'avatar_url': user['avatar_url']
                                                      };
                                                      availableUsers.add(returnedUser);
                                                      filteredAvailableUsers.add(returnedUser);
                                                    });
                                                    _fetchData(silent: true);

                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text('${user['username'] ?? 'User'} berhasil dikeluarkan dari grup'),
                                                          backgroundColor: Colors.orangeAccent,
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text('Gagal mengeluarkan anggota: Koneksi bermasalah atau coba lagi ($e)'),
                                                          backgroundColor: Colors.redAccent,
                                                        ),
                                                      );
                                                    }
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                      ),
                                    );
                                  }).toList(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat anggota: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _editDeadline() async {
    if (_putaran == null) return;
    try {
      final currentDeadlineStr = _putaran!['target_deadline'] as String?;
      final currentDeadline = currentDeadlineStr != null ? DateTime.parse(currentDeadlineStr) : DateTime.now();

      final picked = await showDatePicker(
        context: context,
        initialDate: currentDeadline,
        firstDate: _putaran!['start_date'] != null ? DateTime.parse(_putaran!['start_date']) : DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        helpText: 'Pilih Tanggal Tenggat Baru',
        cancelText: 'Batal',
        confirmText: 'Simpan',
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: isDark
                  ? const ColorScheme.dark(
                      primary: AppTheme.primaryGreen,
                      onPrimary: Colors.white,
                      surface: AppTheme.bgCard,
                      onSurface: AppTheme.textPrimary,
                      secondary: AppTheme.accentGold,
                    )
                  : const ColorScheme.light(
                      primary: AppTheme.primaryGreen,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Color(0xFF1A1A2E),
                      secondary: AppTheme.accentGold,
                    ),
              dialogTheme: DialogThemeData(backgroundColor: isDark ? AppTheme.bgCard : Colors.white),
            ),
            child: child!,
          );
        },
      );

      if (picked == null) return;

      final newDeadline = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);

      await _supabase
          .from('putaran_siklus')
          .update({'target_deadline': newDeadline.toIso8601String()})
          .eq('id_putaran', _putaran!['id_putaran']);

      // Send group notifications about the new deadline!
      try {
        final groupName = _group?['nama_grup'] ?? 'Grup';
        final formattedDate = '${newDeadline.day}/${newDeadline.month}/${newDeadline.year}';
        final adminName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
            _supabase.auth.currentUser?.email?.split('@')[0] ??
            'Admin';
            
        await NotificationService.sendToGroup(
          groupId: widget.groupId,
          type: 'DEADLINE_CHANGED',
          title: '⏰ Tenggat Grup Diperbarui',
          body: '$adminName mengubah tenggat waktu grup "$groupName" menjadi $formattedDate.',
          excludeUserId: _supabase.auth.currentUser?.id,
        );
      } catch (e) {
        debugPrint('Error sending deadline change notif: $e');
      }

      _fetchData(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Tenggat waktu berhasil diperbarui!'), backgroundColor: AppTheme.primaryGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui tenggat waktu: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showGroupSettings() {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isAdmin = currentUserId == _group?['creator_id'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSheet) {
          final isLimited = _group?['limit_juz'] == true;
          final approvedMembersCount = _members.where((m) => m['approval_status'] == 'APPROVED').length;
          final memberCount = approvedMembersCount == 0 ? 1 : approvedMembersCount;
          final maxSlots = (30 / memberCount).ceil();

          final headerDivider = Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: isDark 
                ? Colors.white.withOpacity(0.08) 
                : Colors.black.withOpacity(0.08),
          );

          final menuDivider = Divider(
            height: 1,
            thickness: 1,
            indent: 72,
            endIndent: 16,
            color: isDark 
                ? Colors.white.withOpacity(0.08) 
                : Colors.black.withOpacity(0.08),
          );

          final dangerZoneDivider = Divider(
            height: 40,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: isDark 
                ? Colors.white.withOpacity(0.08) 
                : Colors.black.withOpacity(0.08),
          );

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Pengaturan Grup',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      headerDivider,
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        leading: const Icon(Icons.share_rounded, color: AppTheme.primaryGreen),
                        title: const Text('Bagikan Kode Undangan'),
                        subtitle: Text(
                          _group?['kode_gk_unik'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (_group != null) {
                            final kode = _group!['kode_gk_unik'];
                            final namaGrup = _group!['nama_grup'] ?? 'Khataman';
                            final inviteLink = 'https://khataman2026.web.app/join?code=$kode';
                            Share.share(
                              'Assalamu\'alaikum! 🌙\n\nYuk gabung di grup khataman Al-Quran "$namaGrup"!\n\nKlik link di bawah ini untuk langsung bergabung:\n🔗 $inviteLink\n\n📋 Atau masukkan Kode Grup berikut di aplikasi:\n*$kode*\n\nBarakallahu fiikum! 🤲',
                            );
                          }
                        },
                      ),
                      if (isAdmin) ...[
                        menuDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.category_rounded, color: AppTheme.accentGold),
                          title: const Text('Tipe Grup'),
                          subtitle: Text(
                            _group?['tipe_grup'] == 'RUTIN'
                                ? '🔁 RUTIN: Siklus berulang tanpa diarsip, mendukung Rolling Juz'
                                : '⚡ INSIDENTAL: Satu kali putaran selesai lalu diarsip',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          trailing: DropdownButton<String>(
                            value: _group?['tipe_grup'] ?? 'INSIDENTAL',
                            underline: const SizedBox(),
                            dropdownColor: Theme.of(context).colorScheme.surface,
                            items: const [
                              DropdownMenuItem(
                                value: 'INSIDENTAL',
                                child: Text('INSIDENTAL'),
                              ),
                              DropdownMenuItem(
                                value: 'RUTIN',
                                child: Text('RUTIN'),
                              ),
                            ],
                            onChanged: (val) async {
                              if (val == null) return;
                              setStateSheet(() {
                                if (_group != null) {
                                  _group!['tipe_grup'] = val;
                                }
                              });
                              setState(() {});
                              try {
                                await _supabase
                                    .from('groups')
                                    .update({'tipe_grup': val})
                                    .eq('id_group', widget.groupId);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Tipe grup diubah menjadi $val!'),
                                    backgroundColor: AppTheme.primaryGreen,
                                  ),
                                );
                                _fetchData(silent: true);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal mengubah tipe grup: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        menuDivider,
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          title: const Text('Batasi Pengambilan Juz'),
                          subtitle: Text(
                            isLimited
                                ? '🔒 Aktif: Maksimal $maxSlots Juz per anggota'
                                : '🔓 Bebas: Anggota bebas mengambil tanpa batas',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          secondary: Icon(
                            Icons.gavel_rounded,
                            color: isLimited ? AppTheme.accentGold : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          value: isLimited,
                          activeColor: AppTheme.primaryGreen,
                          onChanged: (val) async {
                            // Update local state in sheet
                            setStateSheet(() {
                              if (_group != null) {
                                _group!['limit_juz'] = val;
                              }
                            });
                            // Update main detail screen state
                            setState(() {});
                            
                            try {
                              final result = await _supabase
                                  .from('groups')
                                  .update({'limit_juz': val})
                                  .eq('id_group', widget.groupId)
                                  .select();
                              
                              if (result.isEmpty) {
                                throw Exception('Izin update ditolak (RLS).');
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      val
                                          ? '🔒 Batasan pengambilan Juz diaktifkan!'
                                          : '🔓 Batasan pengambilan Juz dinonaktifkan!',
                                    ),
                                    backgroundColor: AppTheme.primaryGreen,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                              _fetchData(silent: true);
                            } catch (e) {
                              // Revert on error
                              setStateSheet(() {
                                if (_group != null) {
                                  _group!['limit_juz'] = !val;
                                }
                              });
                              setState(() {});
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal mengubah batasan: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        menuDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: Badge(
                            isLabelVisible: _pendingCount > 0,
                            label: Text('$_pendingCount'),
                            backgroundColor: Colors.redAccent,
                            child: const Icon(Icons.manage_accounts_rounded, color: AppTheme.accentGold),
                          ),
                          title: const Text('Kelola Anggota'),
                          subtitle: Text(
                            'Setujui permintaan masuk & tambah anggota baru',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showManageMembersDialog();
                          },
                        ),
                        menuDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.grid_view_rounded, color: AppTheme.accentTeal),
                          title: const Text('Pembagian Juz (Admin)'),
                          subtitle: Text(
                            'Kelola pembagian Juz secara cepat menggunakan kuas/pembagi Juz',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JuzAssignmentScreen(
                                  groupId: widget.groupId,
                                  groupName: _group?['nama_grup'] ?? 'Khataman',
                                ),
                              ),
                            ).then((_) {
                              if (mounted) {
                                _fetchData(silent: true);
                              }
                            });
                          },
                        ),
                        if (_putaran != null) ...[
                          menuDivider,
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: const Icon(Icons.edit_calendar_rounded, color: Colors.blueAccent),
                            title: const Text('Ubah Tenggat Waktu (Deadline)'),
                            subtitle: Text(
                              'Perpanjang atau majukan target waktu siklus',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _editDeadline();
                            },
                          ),
                        ],
                        menuDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
                          title: const Text('Riwayat Putaran'),
                          subtitle: Text(
                            'Lihat daftar putaran khataman yang telah selesai',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showKhatamHistorySheet();
                          },
                        ),
                        dangerZoneDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                          title: const Text('Hapus Grup', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'Hapus grup ini secara permanen dari server',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _confirmDeleteGroup();
                          },
                        ),
                      ] else ...[
                        menuDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.people_rounded, color: AppTheme.accentTeal),
                          title: const Text('Daftar Anggota'),
                          subtitle: Text(
                            'Lihat anggota grup saat ini',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showMembersListOnlyDialog();
                          },
                        ),
                        menuDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
                          title: const Text('Riwayat Putaran'),
                          subtitle: Text(
                            'Lihat daftar putaran khataman yang telah selesai',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showKhatamHistorySheet();
                          },
                        ),
                        dangerZoneDivider,
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                          title: const Text('Keluar dari Grup', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'Keluar dan lepaskan semua juz yang Anda klaim',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF5F6E65),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _confirmLeaveGroup();
                          },
                        ),
                      ],
                      SizedBox(height: MediaQuery.of(ctx).padding.bottom + 24),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showMembersListOnlyDialog() async {
    try {
      final membersData = await _supabase
          .from('group_members')
          .select('user_id, approval_status, users(username, email, avatar_url)')
          .eq('group_id', widget.groupId)
          .eq('approval_status', 'APPROVED');

      if (!mounted) return;

      final approvedMembers = List<Map<String, dynamic>>.from(membersData);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('Daftar Anggota'),
          content: SizedBox(
            width: double.maxFinite,
            child: approvedMembers.isEmpty
                ? const Text('Belum ada anggota lain.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: approvedMembers.length,
                    itemBuilder: (_, i) {
                      final m = approvedMembers[i];
                      final user = m['users'] as Map<String, dynamic>? ?? {};
                      final avatarUrl = user['avatar_url'] as String?;
                      final isCreator = m['user_id'] == _group?['creator_id'];

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null ? const Icon(Icons.person) : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                user['username'] ?? 'User',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCreator) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentGold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Admin', style: TextStyle(color: AppTheme.accentGold, fontSize: 9)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          user['email'] ?? '',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup', style: TextStyle(color: AppTheme.primaryGreen)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat daftar anggota: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showKhatamHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.bgCard : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGold.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.emoji_events_rounded, color: AppTheme.accentGold, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Riwayat Khataman',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                'Daftar putaran khataman grup yang selesai',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // Body with FutureBuilder
                  Expanded(
                    child: FutureBuilder<List<dynamic>>(
                      future: _supabase
                          .from('putaran_siklus')
                          .select()
                          .eq('group_id', widget.groupId)
                          .eq('status_aktif_selesai', 'SELESAI')
                          .order('nomor_putaran', ascending: false),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Gagal memuat riwayat: ${snapshot.error}',
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          );
                        }
                        final historyList = snapshot.data ?? [];
                        if (historyList.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.emoji_events_outlined,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Belum ada Riwayat Khataman',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Selesaikan target 30 Juz pada putaran aktif untuk mencatatkan riwayat khataman pertama grup Anda!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: historyList.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              // Trophy Banner Card
                              return Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF1A3A2A), Color(0xFF0D2118)],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.emoji_events_rounded, size: 48, color: AppTheme.accentGold),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Pencapaian Luar Biasa!',
                                            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Total ${historyList.length} Kali Khatam Al-Quran',
                                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Semoga berkah dan istiqomah untuk setiap baris ayat yang dibaca bersama.',
                                            style: TextStyle(color: Colors.white60, fontSize: 10, height: 1.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final cycle = historyList[index - 1];
                            final startStr = cycle['start_date'] != null 
                                ? _formatSimpleDate(DateTime.parse(cycle['start_date'])) 
                                : '-';
                            final endStr = cycle['target_deadline'] != null 
                                ? _formatSimpleDate(DateTime.parse(cycle['target_deadline'])) 
                                : '-';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryGreen.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 20),
                                  ),
                                  title: Text(
                                    'Putaran Ke-${cycle['nomor_putaran']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Periode: $startStr s/d $endStr',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  children: [
                                    FutureBuilder<List<dynamic>>(
                                      future: _supabase
                                          .from('slot_khataman')
                                          .select('nomor_juz, users(username)')
                                          .eq('putaran_id', cycle['id_putaran'])
                                          .order('nomor_juz', ascending: true),
                                      builder: (context, slotSnapshot) {
                                        if (slotSnapshot.connectionState == ConnectionState.waiting) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppTheme.primaryGreen,
                                              ),
                                            ),
                                          );
                                        }
                                        if (slotSnapshot.hasError || !slotSnapshot.hasData || slotSnapshot.data!.isEmpty) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: Text(
                                              'Gagal memuat detail pembaca atau data slot tidak ditemukan.',
                                              style: TextStyle(fontSize: 11, color: Colors.grey),
                                            ),
                                          );
                                        }
                                        final slots = slotSnapshot.data!;
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.2),
                                            borderRadius: const BorderRadius.only(
                                              bottomLeft: Radius.circular(12),
                                              bottomRight: Radius.circular(12),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Padding(
                                                padding: EdgeInsets.only(left: 4, bottom: 8),
                                                child: Text(
                                                  'Daftar Pembaca per Juz:',
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                                                ),
                                              ),
                                              GridView.builder(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  childAspectRatio: 3.8,
                                                  crossAxisSpacing: 8,
                                                  mainAxisSpacing: 6,
                                                ),
                                                itemCount: slots.length,
                                                itemBuilder: (context, sIdx) {
                                                  final slot = slots[sIdx];
                                                  final juzNum = slot['nomor_juz'];
                                                  final username = slot['users']?['username'] ?? 'Umum';
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context).colorScheme.surface,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3)),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme.primaryGreen.withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            'Juz $juzNum',
                                                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text(
                                                            '@$username',
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w500,
                                                              color: Theme.of(context).colorScheme.onSurface,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatSimpleDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _confirmLeaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Keluar Grup'),
        content: const Text('Apakah Anda yakin ingin keluar dari grup khataman ini? Semua juz yang telah Anda klaim akan dilepaskan kembali.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final currentUserId = _supabase.auth.currentUser!.id;

        // 1. Release slots FIRST (sebelum hapus membership, karena RLS mungkin
        //    memerlukan membership aktif untuk mengizinkan update slot)
        if (_putaran != null) {
          try {
            final myMemberObj = _members.firstWhere(
              (m) => m['user_id'] == currentUserId,
              orElse: () => {},
            );
            final myUsername = myMemberObj['users']?['username'] as String?;
            await _supabase
                .from('slot_khataman')
                .update({
                  'user_id': null, 
                  'ayat_terakhir_input': 0, 
                  'status_checklist': false,
                  'username_sebelumnya': myUsername,
                })
                .eq('putaran_id', _putaran!['id_putaran'])
                .eq('user_id', currentUserId);
            debugPrint('[LeaveGroup] Slots released successfully');
          } catch (slotErr) {
            debugPrint('[LeaveGroup] Slot release error (non-fatal): $slotErr');
            // Lanjutkan proses meskipun slot release gagal
          }
        }

        // 2. Delete from group_members
        await _supabase
            .from('group_members')
            .delete()
            .eq('group_id', widget.groupId)
            .eq('user_id', currentUserId);
        debugPrint('[LeaveGroup] Member deleted successfully from group ${widget.groupId}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anda telah keluar dari grup.'), backgroundColor: AppTheme.primaryGreen),
          );
          Navigator.pop(context, true); // Go back to groups list screen with refresh signal
        }
      } catch (e) {
        debugPrint('[LeaveGroup] Error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal keluar grup: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // Hapus Grup
  // ─────────────────────────────────────────────────────────
  Future<void> _confirmDeleteGroup() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Hapus Grup?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Grup ini dan semua progres di dalamnya akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGroup();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup() async {
    setState(() => _isLoading = true);
    try {
      final gName = widget.groupName ?? _group?['nama_grup'] ?? 'Grup';

      // 1. Kirim notifikasi ke semua anggota grup SEBELUM menghapus grupnya
      //    (JANGAN sertakan group_id agar notifikasi TIDAK terhapus cascade saat grup dihapus)
      try {
        final members = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', widget.groupId)
            .eq('approval_status', 'APPROVED');

        final rows = <Map<String, dynamic>>[];
        final currentUserId = _supabase.auth.currentUser?.id;
        for (final m in members) {
          final uid = m['user_id'] as String;
          if (uid == currentUserId) continue;
          rows.add({
            'user_id': uid,
            'type': 'KHATAMAN_COMPLETE', // Tipe terdaftar agar muncul ikon/warna menarik
            'title': 'Grup Khataman Dihapus 🗑️',
            'body': 'Grup "$gName" telah dihapus oleh admin.',
          });
        }

        if (rows.isNotEmpty) {
          await _supabase.from('notifications').insert(rows);
          debugPrint('[DeleteGroup] Group deletion notifications sent successfully');
        }
      } catch (notifErr) {
        debugPrint('[DeleteGroup] Failed to send notifications: $notifErr');
      }

      // 2. Hapus grup dari tabel groups dan kembalikan data yang dihapus
      final deletedData = await _supabase
          .from('groups')
          .delete()
          .eq('id_group', widget.groupId)
          .select();
      
      if (deletedData.isEmpty) {
        throw Exception('Grup gagal dihapus. Anda mungkin tidak memiliki izin (RLS) di database.');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grup berhasil dihapus'), backgroundColor: AppTheme.primaryGreen),
        );
        Navigator.pop(context, true); // Kirim 'true' sebagai tanda berhasil dihapus
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Gagal Menghapus Grup'),
            content: Text('Terjadi kesalahan saat menghapus grup:\n\n$e\n\n(Jika ini masalah izin, tambahkan policy DELETE di tabel groups pada dashboard Supabase)'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
          )
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // Widget Shimmer tanpa package eksternal
  // ─────────────────────────────────────────────────────────
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

  Widget _buildShimmerCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? AppTheme.primaryGreen.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          _buildShimmerBox(width: 44, height: 44, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(width: 100, height: 14),
                const SizedBox(height: 8),
                _buildShimmerBox(height: 5),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildShimmerBox(width: 36, height: 14, radius: 4),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return Column(
      children: [
        // Header shimmer
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShimmerBox(width: 160, height: 14),
              const SizedBox(height: 10),
              _buildShimmerBox(width: 100, height: 26),
              const SizedBox(height: 14),
              _buildShimmerBox(height: 10),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 8,
            itemBuilder: (_, __) => _buildShimmerCard(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_group?['nama_grup'] ?? 'Detail Grup'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_group != null)
            IconButton(
              icon: Badge(
                isLabelVisible: currentUserId == _group!['creator_id'] && _pendingCount > 0,
                label: Text('$_pendingCount'),
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.more_vert_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              tooltip: 'Pengaturan Grup',
              onPressed: _showGroupSettings,
            ),
        ],
      ),
      body: _isLoading
          // ← Shimmer ditampilkan selama loading, bukan empty state
          ? _buildShimmerList()
          : _putaran == null
              ? _buildNoPutaran(currentUserId)
              : _buildSlotList(currentUserId),
    );
  }

  Widget _buildNoPutaran(String? currentUserId) {
    final code = _group?['kode_gk_unik'] ?? '-';
    final isLimited = _group?['limit_juz'] == true;
    final approvedMembersCount = _members.where((m) => m['approval_status'] == 'APPROVED').length;
    final memberCount = approvedMembersCount == 0 ? 1 : approvedMembersCount;
    final maxSlots = (30 / memberCount).ceil();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        if (_completedCount > 0) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A3A2A), Color(0xFF0D2118)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accentGold.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded, size: 40, color: AppTheme.accentGold),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pencapaian Grup',
                        style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🏆 $_completedCount Kali Khataman Selesai!',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _showKhatamHistorySheet,
                        child: const Text(
                          'Lihat Riwayat Lengkap ➔',
                          style: TextStyle(color: AppTheme.accentGold, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        // Kode Group Container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Text('Kode Bergabung', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onLongPress: () {
                      final inviteLink = 'https://khataman2026.web.app/join?code=$code';
                      Clipboard.setData(ClipboardData(text: inviteLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link undangan grup berhasil disalin! 🔗'),
                          backgroundColor: AppTheme.primaryGreen,
                        ),
                      );
                    },
                    child: Tooltip(
                      message: 'Tekan lama untuk menyalin',
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: AppTheme.primaryGreen),
                    tooltip: 'Bagikan Kode Undangan',
                    onPressed: () {
                      final gName = widget.groupName ?? _group?['nama_grup'] ?? 'Grup';
                      final inviteLink = 'https://khataman2026.web.app/join?code=$code';
                      Share.share(
                        'Assalamu\'alaikum! 🌙\n\nYuk gabung di grup khataman Al-Quran "$gName"!\n\nKlik link di bawah ini untuk langsung bergabung:\n🔗 $inviteLink\n\n📋 Atau masukkan Kode Grup berikut di aplikasi:\n*$code*\n\nBarakallahu fiikum! 🤲',
                      );
                    },
                  )
                ],
              ),
              const SizedBox(height: 8),
              Text('Tekan lama kode untuk menyalin, atau ketuk ikon bagikan untuk menyebarkan.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // Members list
        Text('Anggota Bergabung (${_members.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 12),
        ..._members.map((m) {
          final user = m['users'] ?? {};
          final name = user['username'] ?? 'User';
          final avatar = user['avatar_url'];
          final isCreator = m['user_id'] == _group?['creator_id'];

          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCreator) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3), width: 0.5),
                    ),
                    child: const Text(
                      'Admin',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 24),
        
        // Status Indikator Batasan Juz
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isLimited 
                  ? AppTheme.accentGold.withOpacity(0.12) 
                  : AppTheme.primaryGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isLimited 
                    ? AppTheme.accentGold.withOpacity(0.3) 
                    : AppTheme.primaryGreen.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLimited ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                  size: 14,
                  color: isLimited ? AppTheme.accentGold : AppTheme.primaryGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  isLimited 
                      ? 'Batasan Pengambilan Juz: AKTIF (Maks $maxSlots Juz)' 
                      : 'Batasan Pengambilan Juz: NONAKTIF (Bebas)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isLimited ? AppTheme.accentGold : AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        if (_group?['tipe_grup'] == 'RUTIN') ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _startNewPutaran(3),
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Rolling Juz (Acak Cerdas)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startNewPutaran(0),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Bagi Rata Otomatis'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startNewPutaran(2),
            icon: const Icon(Icons.brush_rounded),
            label: const Text('Bagi Manual (Kuas Admin)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF0D5257) : const Color(0xFF007A7C),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _startNewPutaran(1),
            icon: const Icon(Icons.pan_tool_alt_rounded, color: AppTheme.accentGold),
            label: const Text('Klaim Mandiri (Open Slot)', style: TextStyle(color: AppTheme.accentGold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accentGold),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
  /// Menampilkan dialog konfirmasi Doa Khatam Al-Quran untuk Khataman Grup.
  void _showDoaKhatamGroupConfirmation() {
    final bool isRutin = _group?['tipe_grup'] == 'RUTIN';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.menu_book_rounded,
          color: AppTheme.accentGold,
          size: 40,
        ),
        title: Text(
          isRutin ? 'Konfirmasi Selesai Putaran' : 'Konfirmasi Khataman Grup',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          isRutin
              ? 'Apakah Anda sudah selesai membaca Doa Khatam Al-Quran?\n\n'
                  'Jika sudah, putaran siklus ini akan diselesaikan dan dicatat ke dalam riwayat grup. Anda dapat langsung memulai putaran berikutnya.'
              : 'Apakah Anda sudah selesai membaca Doa Khatam Al-Quran?\n\n'
                  'Jika sudah, grup ini akan diarsipkan dan progres khataman '
                  'akan dicatat ke dalam riwayat semua anggota. '
                  'Anggota lain akan menerima notifikasi.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showDoaKhatamBottomSheet(context, onConfirmCompletion: _showDoaKhatamGroupConfirmation);
            },
            icon: const Icon(Icons.auto_stories_rounded, size: 16),
            label: const Text('Belum, Baca Doa', style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentGold,
              side: BorderSide(color: AppTheme.accentGold.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _archiveGroup();
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Ya, Sudah', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Mengarsipkan grup atau menyelesaikan putaran RUTIN: update status, kirim notifikasi, refresh.
  Future<void> _archiveGroup() async {
    try {
      final bool isRutin = _group?['tipe_grup'] == 'RUTIN';

      // 1. Update group visibility to ARCHIVED (hanya untuk INSIDENTAL)
      if (!isRutin) {
        try {
          await _supabase
              .from('groups')
              .update({'visibility': 'ARCHIVED'})
              .eq('id_group', widget.groupId);
        } catch (grpErr) {
          debugPrint('⚠️ [RLS Restriction] Failed to update groups visibility: $grpErr');
          // Proceed anyway; creator self-healing will apply the DB flag silently when creator opens the group
        }

        // Save a local archived flag so this user instantly sees the group in history and archives
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('archived_group_${widget.groupId}_${_putaran?['id_putaran']}', true);
        } catch (prefErr) {
          debugPrint('Error saving local archived flag: $prefErr');
        }
      }

      // 2. Pastikan putaran siklus aktif ditandai SELESAI
      if (_putaran != null && _putaran!['status_aktif_selesai'] != 'SELESAI') {
        await _supabase
            .from('putaran_siklus')
            .update({'status_aktif_selesai': 'SELESAI'})
            .eq('id_putaran', _putaran!['id_putaran']);
      }

      // 3. Kirim notifikasi ke semua anggota grup
      final gName = widget.groupName ?? _group?['nama_grup'] ?? 'Grup';
      final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
          _supabase.auth.currentUser?.email?.split('@')[0] ??
          'Seseorang';
      try {
        await NotificationService.sendToGroup(
          groupId: widget.groupId,
          type: 'KHATAMAN_COMPLETE',
          title: isRutin ? '🎉 Putaran Khataman Selesai!' : '📁 Khataman Diarsipkan',
          body: isRutin
              ? '"$gName" telah menyelesaikan putaran siklus oleh $senderName. Alhamdulillah!'
              : '"$gName" telah diarsipkan oleh $senderName setelah menyelesaikan Doa Khatam Al-Quran. Alhamdulillah!',
          excludeUserId: _supabase.auth.currentUser?.id,
        );
      } catch (notifErr) {
        debugPrint('Error sending archive notification: $notifErr');
      }

      // 4. Refresh data
      await _fetchData(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRutin 
                ? '🎉 Putaran khataman berhasil diselesaikan!' 
                : '📁 Grup telah diarsipkan. Alhamdulillah!'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('🚨 [Archive Group Error] Failed to archive/complete cycle: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyelesaikan khataman: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildSlotList(String? currentUserId) {
    final completed = _slots.where((s) => s['status_checklist'] == true).length;
    final claimed = _slots.where((s) => s['user_id'] != null).length;

    // Menghitung progres riil komulatif (termasuk pecahan juz)
    double totalProgressSum = 0.0;
    for (var slot in _slots) {
      if (slot['status_checklist'] == true) {
        totalProgressSum += 1.0;
      } else {
        final lastAyat = slot['ayat_terakhir_input'] as int? ?? 0;
        if (lastAyat > 0 && slot['user_id'] != null) {
          final juzNum = slot['nomor_juz'] as int? ?? 1;
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
    final double realProgressValue = totalProgressSum / 30.0;
    final dateRangeText = _formatDateRange(_putaran?['start_date'], _putaran?['target_deadline']);
    final remainingText = _getRemainingTime(_putaran?['target_deadline']);
    final isLimited = _group?['limit_juz'] == true;
    final approvedMembersCount = _members.where((m) => m['approval_status'] == 'APPROVED').length;
    final memberCount = approvedMembersCount == 0 ? 1 : approvedMembersCount;
    final maxSlots = (30 / memberCount).ceil();
    final isCreator = _group?['creator_id'] == currentUserId;

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

    final titleTextColor = isDark ? Colors.white70 : AppTheme.darkGreen.withOpacity(0.8);
    final valueTextColor = isDark ? Colors.white : AppTheme.darkGreen;
    final percentColor = isDark ? AppTheme.primaryGreen : AppTheme.darkGreen;
    final progressBgColor = isDark ? Colors.white.withOpacity(0.12) : AppTheme.primaryGreen.withOpacity(0.15);
    final borderColor = isDark ? AppTheme.primaryGreen.withOpacity(0.3) : AppTheme.primaryGreen.withOpacity(0.2);

    // Fluid scroll-linked morphing sizes and values
    final double verticalPadding = 18.0 - (10.0 * _shrinkFactor); // 18.0 down to 8.0
    final double labelOpacity = (1.0 - _shrinkFactor * 1.8).clamp(0.0, 1.0); // Fades out early/quickly for clean layout
    final double completedFontSize = 18.0 - (4.0 * _shrinkFactor); // 18.0 down to 14.0
    final double indicatorSize = 88.0 - (48.0 * _shrinkFactor); // 88.0 down to 40.0
    final double percentFontSize = 13.5 - (3.5 * _shrinkFactor); // 13.5 down to 10.0
    final double strokeWidth = 5.5 - (2.5 * _shrinkFactor); // 5.5 down to 3.0

    return Column(
      children: [
        // Summary Card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: verticalPadding),
          decoration: BoxDecoration(
            gradient: cardBgGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (labelOpacity > 0.0)
                      Opacity(
                        opacity: labelOpacity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Putaran ${_putaran?['nomor_putaran'] ?? 1}${dateRangeText.isNotEmpty ? ' • $dateRangeText' : ''}',
                                  style: TextStyle(color: titleTextColor, fontSize: 12),
                                ),
                                if (_completedCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentGold.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.accentGold.withOpacity(0.5), width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.emoji_events_rounded, size: 10, color: AppTheme.accentGold),
                                        const SizedBox(width: 3),
                                        Text(
                                          '$_completedCount Khatam',
                                          style: const TextStyle(color: AppTheme.accentGold, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isLimited 
                                    ? AppTheme.accentGold.withOpacity(0.15) 
                                    : AppTheme.primaryGreen.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isLimited 
                                      ? AppTheme.accentGold.withOpacity(0.4) 
                                      : AppTheme.primaryGreen.withOpacity(0.4),
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isLimited ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                                    size: 11,
                                    color: isLimited ? AppTheme.accentGold : AppTheme.primaryGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isLimited 
                                        ? 'Dibatasi: Maks $maxSlots Juz/orang' 
                                        : 'Bebas mengambil Juz',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isLimited ? AppTheme.accentGold : AppTheme.primaryGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Opacity(
                          opacity: (1.0 - _shrinkFactor / 0.5).clamp(0.0, 1.0),
                          child: Text(
                            '$completed / 30 Juz Selesai',
                            style: TextStyle(
                              fontSize: completedFontSize,
                              fontWeight: FontWeight.bold,
                              color: valueTextColor,
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: ((_shrinkFactor - 0.4) / 0.6).clamp(0.0, 1.0),
                          child: Row(
                            children: [
                              Icon(Icons.group_rounded, color: percentColor, size: 15),
                              const SizedBox(width: 6),
                              Text(
                                'Putaran ${_putaran?['nomor_putaran'] ?? 1}: $completed/30 Juz Selesai',
                                style: TextStyle(
                                  fontSize: completedFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: valueTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (remainingText.isNotEmpty && labelOpacity > 0.0) ...[
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: labelOpacity,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: remainingText == 'Waktu habis'
                                ? Colors.redAccent.withOpacity(0.15)
                                : AppTheme.accentGold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: remainingText == 'Waktu habis'
                                  ? Colors.redAccent.withOpacity(0.4)
                                  : AppTheme.accentGold.withOpacity(0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            remainingText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: remainingText == 'Waktu habis'
                                  ? Colors.redAccent
                                  : AppTheme.accentGold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: indicatorSize,
                height: indicatorSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Lapisan 1: Pengambilan Juz (Gold)
                    SizedBox(
                      width: indicatorSize,
                      height: indicatorSize,
                      child: CircularProgressIndicator(
                        value: claimed / 30,
                        strokeWidth: strokeWidth,
                        backgroundColor: progressBgColor,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppTheme.accentGold : AppTheme.accentGold.withOpacity(0.8),
                        ),
                      ),
                    ),
                    // Lapisan 2: Selesai Dibaca (Hijau Utama) - Ditumpuk di atas
                    SizedBox(
                      width: indicatorSize,
                      height: indicatorSize,
                      child: CircularProgressIndicator(
                        value: realProgressValue,
                        strokeWidth: strokeWidth,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(percentColor),
                      ),
                    ),
                    // Teks Tengah: Persentase Selesai & Klaim
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(realProgressValue * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: percentFontSize, 
                            fontWeight: FontWeight.bold, 
                            color: percentColor,
                            letterSpacing: -0.2,
                            height: 1.1,
                          ),
                        ),
                        if (labelOpacity > 0.3) ...[
                          const SizedBox(height: 3),
                          Opacity(
                            opacity: ((labelOpacity - 0.3) / 0.7).clamp(0.0, 1.0),
                            child: Text(
                              '$claimed/30',
                              style: TextStyle(
                                fontSize: 10, 
                                fontWeight: FontWeight.w700, 
                                color: isDark ? Colors.white70 : AppTheme.darkGreen.withOpacity(0.7),
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (completed == 30 && _group?['visibility'] != 'ARCHIVED')
          CongratulatoryCard(
            title: 'Maa Syaa Allah, Grup Anda Khatam! \uD83C\uDF89',
            description: 'Alhamdulillah! Grup "${_group?['nama_grup'] ?? 'Grup'}" telah menyelesaikan siklus khataman 30 Juz Al-Quran.',
            resetLabel: 'Putaran Baru',
            showResetButton: isCreator,
            onReset: _showNewPutaranDialog,
            onDoaKhatam: _showDoaKhatamGroupConfirmation,
          ),
        if (_group?['visibility'] == 'ARCHIVED')
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.accentGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.accentGold.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.archive_rounded, color: AppTheme.accentGold, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Grup ini telah diarsipkan. Progres khataman sudah dicatat ke riwayat.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentGold,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primaryGreen,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onRefresh: () => _fetchData(silent: true),
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
              itemCount: _slots.length,
              itemBuilder: (context, index) {
                final slot = _slots[index];
                final memberName = (slot['users'] as Map<String, dynamic>?)?['username'] as String?;
                
                return JuzProgressCard(
                  key: ValueKey('slot_${slot['id_slot']}_${slot['user_id']}'),
                  juzNumber: slot['nomor_juz'] as int,
                  lastAyat: slot['ayat_terakhir_input'] as int? ?? 0,
                  isComplete: slot['status_checklist'] == true,
                  isGroupMode: true,
                  isOwned: slot['user_id'] == currentUserId,
                  isAdmin: currentUserId == _group?['creator_id'],
                  memberName: memberName,
                  usernameSebelumnya: slot['username_sebelumnya'] as String?,
                  slotId: slot['id_slot'] as int?,
                  groupId: widget.groupId,
                  groupName: _group?['nama_grup'],
                  onRelease: _releaseSlot,
                  approvalLepasStatus: slot['approval_lepas_status'] as String?,
                  onRequestRelease: _requestReleaseSlot,
                  onCancelRelease: _cancelReleaseRequest,
                  onClaim: _claimSlot,
                  onProgressUpdated: () {
                    if (mounted) {
                      _fetchData(silent: true);
                    }
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class PremiumConfettiOverlay extends StatefulWidget {
  const PremiumConfettiOverlay({Key? key}) : super(key: key);

  @override
  State<PremiumConfettiOverlay> createState() => _PremiumConfettiOverlayState();
}

class _PremiumConfettiOverlayState extends State<PremiumConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<ConfettiParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        _updateParticles();
      })..repeat();

    // Create initial particles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      for (int i = 0; i < 120; i++) {
        _particles.add(ConfettiParticle.random(size.width, size.height, _random));
      }
    });
  }

  void _updateParticles() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    setState(() {
      for (var p in _particles) {
        p.update(size.width, size.height, _random);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: ConfettiPainter(particles: _particles),
        size: Size.infinite,
      ),
    );
  }
}

class ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;

  ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });

  factory ConfettiParticle.random(double width, double height, Random random) {
    final colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.pinkAccent,
      Colors.purpleAccent,
      Colors.yellowAccent,
      Colors.tealAccent,
    ];
    return ConfettiParticle(
      x: random.nextDouble() * width,
      y: -random.nextDouble() * height,
      vx: (random.nextDouble() - 0.5) * 4,
      vy: random.nextDouble() * 5 + 3,
      size: random.nextDouble() * 8 + 6,
      color: colors[random.nextInt(colors.length)],
      rotation: random.nextDouble() * pi * 2,
      rotationSpeed: (random.nextDouble() - 0.5) * 0.2,
    );
  }

  void update(double width, double height, Random random) {
    x += vx;
    y += vy;
    rotation += rotationSpeed;

    // Reset if it goes out of screen
    if (y > height || x < 0 || x > width) {
      y = -random.nextDouble() * 50;
      x = random.nextDouble() * width;
      vx = (random.nextDouble() - 0.5) * 4;
      vy = random.nextDouble() * 5 + 3;
    }
  }
}

class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;

  ConfettiPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var p in particles) {
      paint.color = p.color;
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      
      // Draw rectangular confetti piece
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}