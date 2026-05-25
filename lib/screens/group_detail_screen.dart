import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../components/juz_progress_card.dart';
import '../components/khatam_celebration.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
    _shimmerController.dispose();
    super.dispose();
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
    debugPrint('🔄 [Realtime Group] Menghubungkan ke channel: $channelName...');

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
      debugPrint('🔄 [Realtime Group] Status: $status${error != null ? ', Error: $error' : ''}');
      
      // Re-koneksi otomatis jika terjadi error atau timeout
      if (status == RealtimeSubscribeStatus.channelError || 
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('🔄 [Realtime Group] Terputus. Menghubungkan kembali dalam 3 detik...');
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
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('🎉 Alhamdulillah!', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Siklus Khataman telah selesai!\nSemua 30 Juz telah dibaca.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup', style: TextStyle(color: AppTheme.primaryGreen)),
          ),
        ],
      ),
    );
  }

  Future<void> _startNewPutaran(bool isAutoAssign) async {
    try {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(
          start: DateTime.now(),
          end: DateTime.now().add(const Duration(days: 7)),
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

      if (isAutoAssign) {
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
          body: '$adminName memulai putaran baru di kelompok "$groupName" dengan tenggat waktu $formattedDate.',
          excludeUserId: _supabase.auth.currentUser?.id,
        );
      } catch (e) {
        debugPrint('Error sending cycle started notif: $e');
      }

      _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _showNewPutaranDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Mulai Putaran Baru?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Kelompok Anda telah menyelesaikan siklus khataman ini.\n\nSilakan pilih metode pembagian Juz untuk putaran berikutnya:',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startNewPutaran(true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
            child: const Text('Bagi Rata Otomatis', style: TextStyle(color: Colors.white)),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startNewPutaran(false);
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
          .update({'user_id': _supabase.auth.currentUser?.id})
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


  Future<void> _releaseSlot(int slotId) async {
    await _supabase.from('slot_khataman').update({
      'user_id': null,
      'ayat_terakhir_input': 0,
      'status_checklist': false
    }).eq('id_slot', slotId);
    _fetchData(silent: true);
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
    final searchController = TextEditingController();
    try {
      // 1. Fetch current members
      final membersData = await _supabase
          .from('group_members')
          .select('user_id, approval_status, users(username, email, avatar_url)')
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

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text('Kelola Anggota', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  TextField(
                    controller: searchController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Cari username untuk ditambahkan...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryGreen),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                searchController.clear();
                                setStateDialog(() {
                                  filteredAvailableUsers = List.from(availableUsers);
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      final query = val.trim().toLowerCase();
                      setStateDialog(() {
                        filteredAvailableUsers = availableUsers
                            .where((u) => (u['username'] ?? '').toString().toLowerCase().contains(query))
                            .toList();
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Pengguna Terdaftar (Rekomendasi)
                  if (filteredAvailableUsers.isNotEmpty) ...[
                    Text('Tambah Anggota Baru', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredAvailableUsers.length,
                        itemBuilder: (subCtx, idx) {
                          final u = filteredAvailableUsers[idx];
                          final avatar = u['avatar_url'] as String?;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                              child: avatar == null ? const Icon(Icons.person) : null,
                            ),
                            title: Text(u['username'] ?? 'User', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
                            subtitle: Text(u['email'] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

                                  setStateDialog(() {
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
                                } catch (err) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Gagal menambahkan: $err'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              },
                              child: const Text('Tambah', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                  ] else if (searchController.text.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          'Pengguna tidak ditemukan atau sudah bergabung.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ),
                    const Divider(),
                  ],

                  const SizedBox(height: 6),
                  Text('Daftar Anggota Saat Ini', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  
                  // Members List
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: membersList.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('Belum ada anggota lain di grup ini.',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: membersList.length,
                            itemBuilder: (_, i) {
                              final member = membersList[i];
                              final user = member['users'] as Map<String, dynamic>? ?? {};
                              final avatarUrl = user['avatar_url'] as String?;
                              final isPending = member['approval_status'] == 'PENDING';

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                      child: avatarUrl == null ? const Icon(Icons.person) : null,
                                    ),
                                    if (isPending)
                                      Container(
                                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                                        child: const Icon(Icons.hourglass_top_rounded, size: 14, color: AppTheme.accentGold),
                                      ),
                                  ],
                                ),
                                title: Text(user['username'] ?? 'User',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                                subtitle: Text(
                                    isPending ? 'Menunggu Persetujuan' : (user['email'] ?? 'Anggota Aktif'),
                                    style: TextStyle(
                                        color: isPending ? AppTheme.accentGold : Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 11)),
                                trailing: isPending
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryGreen),
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

                                                setStateDialog(() => member['approval_status'] = 'APPROVED');
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
                                            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                                            tooltip: 'Tolak',
                                            onPressed: () async {
                                              try {
                                                await _supabase
                                                    .from('group_members')
                                                    .delete()
                                                    .eq('user_id', member['user_id'])
                                                    .eq('group_id', widget.groupId);
                                                setStateDialog(() => membersList.removeAt(i));
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
                                    : IconButton(
                                        icon: Icon(Icons.person_remove_rounded, color: Colors.redAccent.withOpacity(0.7)),
                                        tooltip: 'Keluarkan Anggota',
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Keluarkan Anggota?'),
                                              content: Text('Apakah Anda yakin ingin mengeluarkan ${user['username'] ?? 'anggota ini'} dari grup?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, false),
                                                  child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                  child: const Text('Keluarkan'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm != true) return;

                                          try {
                                            // Keluarkan anggota
                                            await _supabase
                                                .from('group_members')
                                                .delete()
                                                .eq('user_id', member['user_id'])
                                                .eq('group_id', widget.groupId);
                                            
                                            // Bersihkan slot yang sedang dia pegang jika ada
                                            await _supabase
                                                .from('slot_khataman')
                                                .update({'user_id': null, 'ayat_terakhir_input': 0, 'status_checklist': false})
                                                .eq('user_id', member['user_id']);

                                            setStateDialog(() {
                                              membersList.removeAt(i);
                                              // Kembalikan ke daftar sugesti
                                              final returnedUser = {
                                                'id_user': member['user_id'],
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
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup', style: TextStyle(color: AppTheme.primaryGreen)),
              ),
            ],
          ),
        ),
      );
      searchController.dispose();
    } catch (e) {
      searchController.dispose();
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
          title: '⏰ Tenggat Kelompok Diperbarui',
          body: '$adminName mengubah tenggat waktu kelompok "$groupName" menjadi $formattedDate.',
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

    showModalBottomSheet(
      context: context,
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

          return SafeArea(
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
                const SizedBox(height: 16),
                Text(
                  'Pengaturan Kelompok',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: AppTheme.primaryGreen),
                  title: const Text('Salin Kode Undangan'),
                  subtitle: Text(_group?['kode_gk_unik'] ?? ''),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_group != null) {
                      Clipboard.setData(ClipboardData(text: _group!['kode_gk_unik']));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Kode Grup disalin: ${_group!['kode_gk_unik']}')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded, color: AppTheme.accentGold),
                  title: const Text('Riwayat Khataman'),
                  subtitle: const Text('Lihat pencapaian & sejarah khataman kelompok'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showKhatamHistorySheet();
                  },
                ),
                const Divider(),
                if (isAdmin) ...[
                  SwitchListTile(
                    title: const Text('Batasi Pengambilan Juz'),
                    subtitle: Text(
                      isLimited
                          ? '🔒 Aktif: Maksimal $maxSlots Juz per anggota'
                          : '🔓 Bebas: Anggota bebas mengambil tanpa batas',
                      style: const TextStyle(fontSize: 11),
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
                  const Divider(),
                  ListTile(
                    leading: Badge(
                      isLabelVisible: _pendingCount > 0,
                      label: Text('$_pendingCount'),
                      backgroundColor: Colors.redAccent,
                      child: const Icon(Icons.manage_accounts_rounded, color: AppTheme.accentGold),
                    ),
                    title: const Text('Kelola Anggota'),
                    subtitle: const Text('Setujui permintaan masuk & tambah anggota baru'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showManageMembersDialog();
                    },
                  ),
                  if (_putaran != null)
                    ListTile(
                      leading: const Icon(Icons.edit_calendar_rounded, color: Colors.blueAccent),
                      title: const Text('Ubah Tenggat Waktu (Deadline)'),
                      subtitle: const Text('Perpanjang atau majukan target waktu siklus'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _editDeadline();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                    title: const Text('Hapus Kelompok', style: TextStyle(color: Colors.redAccent)),
                    subtitle: const Text('Hapus grup ini secara permanen dari server'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeleteGroup();
                    },
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.people_rounded, color: AppTheme.accentTeal),
                    title: const Text('Daftar Anggota'),
                    subtitle: const Text('Lihat anggota kelompok saat ini'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showMembersListOnlyDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                    title: const Text('Keluar dari Kelompok', style: TextStyle(color: Colors.redAccent)),
                    subtitle: const Text('Keluar dan lepaskan semua juz yang Anda klaim'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmLeaveGroup();
                    },
                  ),
                ],
                const SizedBox(height: 16),
              ],
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
                            Text(user['username'] ?? 'User', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
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
                        subtitle: Text(user['email'] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
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
                                'Daftar putaran khataman kelompok yang selesai',
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
                                    'Selesaikan target 30 Juz pada putaran aktif untuk mencatatkan riwayat khataman pertama kelompok Anda!',
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
        title: const Text('Keluar Kelompok'),
        content: const Text('Apakah Anda yakin ingin keluar dari kelompok khataman ini? Semua juz yang telah Anda klaim akan dilepaskan kembali.'),
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

        // 1. Delete from group_members
        await _supabase
            .from('group_members')
            .delete()
            .eq('group_id', widget.groupId)
            .eq('user_id', currentUserId);

        // 2. Release slots in current cycle
        if (_putaran != null) {
          await _supabase
              .from('slot_khataman')
              .update({'user_id': null, 'ayat_terakhir_input': 0, 'status_checklist': false})
              .eq('putaran_id', _putaran!['id_putaran'])
              .eq('user_id', currentUserId);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anda telah keluar dari kelompok.'), backgroundColor: AppTheme.primaryGreen),
          );
          Navigator.pop(context); // Go back to groups list screen
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal keluar kelompok: $e'), backgroundColor: Colors.redAccent),
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
      // Hapus grup dari tabel groups dan kembalikan data yang dihapus
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
                child: Icon(Icons.settings_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              tooltip: 'Pengaturan Kelompok',
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
                        'Pencapaian Kelompok',
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
                  Text(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: AppTheme.primaryGreen)),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: AppTheme.primaryGreen),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kode disalin: $code')));
                    },
                  )
                ],
              ),
              const SizedBox(height: 8),
              Text('Bagikan kode ini agar anggota lain dapat bergabung sebelum siklus dimulai.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5)),
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
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
            ),
            title: Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startNewPutaran(true),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Bagi Rata Otomatis'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _startNewPutaran(false),
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

    return Column(
      children: [
        // Summary Card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: cardBgGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text(
                    '$completed / 30 Juz Selesai',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueTextColor),
                  ),
                  if (remainingText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
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
                  ],
                ],
              ),
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Lapisan 1: Pengambilan Juz (Gold)
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CircularProgressIndicator(
                        value: claimed / 30,
                        strokeWidth: 5.5,
                        backgroundColor: progressBgColor,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppTheme.accentGold : AppTheme.accentGold.withOpacity(0.8),
                        ),
                      ),
                    ),
                    // Lapisan 2: Selesai Dibaca (Hijau Utama) - Ditumpuk di atas
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CircularProgressIndicator(
                        value: realProgressValue,
                        strokeWidth: 5.5,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(percentColor),
                      ),
                    ),
                    // Teks Tengah: Persentase Selesai & Klaim
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(realProgressValue * 100).toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 13.5, 
                            fontWeight: FontWeight.bold, 
                            color: percentColor,
                            letterSpacing: -0.2,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$claimed/30',
                          style: TextStyle(
                            fontSize: 10, 
                            fontWeight: FontWeight.w700, 
                            color: isDark ? Colors.white70 : AppTheme.darkGreen.withOpacity(0.7),
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (completed == 30)
          CongratulatoryCard(
            title: 'Maa Syaa Allah, Kelompok Anda Khatam! 🎉',
            description: 'Alhamdulillah! Kelompok "${_group?['nama_grup'] ?? 'Grup'}" telah menyelesaikan siklus khataman 30 Juz Al-Quran.',
            resetLabel: 'Putaran Baru',
            showResetButton: isCreator,
            onReset: _showNewPutaranDialog,
          ),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primaryGreen,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onRefresh: () => _fetchData(silent: true),
            child: ListView.builder(
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
                  memberName: memberName,
                  slotId: slot['id_slot'] as int?,
                  groupId: widget.groupId,
                  groupName: _group?['nama_grup'],
                  onRelease: _releaseSlot,
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