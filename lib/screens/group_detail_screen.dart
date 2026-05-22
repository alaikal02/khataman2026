import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../components/slot_card.dart';
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
      debugPrint('🔄 [Realtime Group] Status: $status' + (error != null ? ', Error: $error' : ''));
      
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

      final pData = await _supabase
          .from('putaran_siklus')
          .select()
          .eq('group_id', widget.groupId)
          .eq('status_aktif_selesai', 'AKTIF')
          .maybeSingle();

      List<dynamic> sData = [];
      if (pData != null) {
        if (_putaran != null &&
            _putaran!['status_aktif_selesai'] == 'AKTIF' &&
            pData['status_aktif_selesai'] == 'SELESAI') {
          _showCelebration();

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
        }
        // Join dengan tabel users untuk langsung dapat username
        sData = await _supabase
            .from('slot_khataman')
            .select('*, users(username)')
            .eq('putaran_id', pData['id_putaran'])
            .order('nomor_juz', ascending: true);
      }

      int pCount = 0;
      if (groupData != null && groupData['creator_id'] == _supabase.auth.currentUser?.id) {
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

      if (mounted) {
        setState(() {
          _group = groupData;
          _putaran = pData;
          _slots = sData;
          _members = membersList;
          _pendingCount = pCount;
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
            child: Text('Tutup', style: TextStyle(color: AppTheme.primaryGreen)),
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
                    ),
              dialogBackgroundColor: isDark ? AppTheme.bgCard : Colors.white,
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

      final newPutaran = await _supabase.from('putaran_siklus').insert({
        'group_id': widget.groupId,
        'nomor_putaran': 1,
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
      _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
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
            SnackBar(
              content: Text('⚠️ Juz ini sudah diambil anggota lain. Pilih Juz lain.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
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
    try {
      final membersData = await _supabase
          .from('group_members')
          .select('user_id, approval_status, users(username, email, avatar_url)')
          .eq('group_id', widget.groupId)
          .neq('user_id', _supabase.auth.currentUser!.id) // Sembunyikan admin dari list
          .order('approval_status', ascending: false); // PENDING di atas, APPROVED di bawah

      if (!mounted) return;

      final membersList = List<Map<String, dynamic>>.from(membersData);

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text('Kelola Anggota', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            content: SizedBox(
              width: double.maxFinite,
              child: membersList.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Belum ada anggota lain di grup ini.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                                child: avatarUrl == null ? Icon(Icons.person) : null,
                              ),
                              if (isPending)
                                Container(
                                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                                  child: Icon(Icons.hourglass_top_rounded, size: 14, color: AppTheme.accentGold),
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
                                      icon: Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryGreen),
                                      tooltip: 'Terima',
                                      onPressed: () async {
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
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.cancel_outlined, color: Colors.redAccent),
                                      tooltip: 'Tolak',
                                      onPressed: () async {
                                        await _supabase
                                            .from('group_members')
                                            .delete()
                                            .eq('user_id', member['user_id'])
                                            .eq('group_id', widget.groupId);
                                        setStateDialog(() => membersList.removeAt(i));
                                        _fetchData(silent: true);
                                      },
                                    ),
                                  ],
                                )
                              : IconButton(
                                  icon: Icon(Icons.person_remove_rounded, color: Colors.redAccent.withOpacity(0.7)),
                                  tooltip: 'Keluarkan Anggota',
                                  onPressed: () async {
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

                                    setStateDialog(() => membersList.removeAt(i));
                                    _fetchData(silent: true);
                                  },
                                ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Tutup', style: TextStyle(color: AppTheme.primaryGreen)),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat anggota: $e'), backgroundColor: Colors.redAccent),
        );
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
            child: Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGroup();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('Ya, Hapus'),
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
          SnackBar(content: Text('Grup berhasil dihapus'), backgroundColor: AppTheme.primaryGreen),
        );
        Navigator.pop(context, true); // Kirim 'true' sebagai tanda berhasil dihapus
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Gagal Menghapus Grup'),
            content: Text('Terjadi kesalahan saat menghapus grup:\n\n$e\n\n(Jika ini masalah izin, tambahkan policy DELETE di tabel groups pada dashboard Supabase)'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Tutup'))],
          )
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // Widget Shimmer tanpa package eksternal
  // ─────────────────────────────────────────────────────────
  Widget _buildShimmerBox({double width = double.infinity, double height = 16, double radius = 8}) {
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
                Color(0xFF1F2937),
                Color(0xFF374151),
                Color(0xFF1F2937),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          _buildShimmerBox(width: 44, height: 44, radius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(width: 100, height: 14),
                SizedBox(height: 8),
                _buildShimmerBox(height: 5),
              ],
            ),
          ),
          SizedBox(width: 12),
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
          margin: EdgeInsets.fromLTRB(16, 12, 16, 16),
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShimmerBox(width: 160, height: 14),
              SizedBox(height: 10),
              _buildShimmerBox(width: 100, height: 26),
              SizedBox(height: 14),
              _buildShimmerBox(height: 10),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16),
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_group != null) IconButton(
            icon: Icon(Icons.copy_rounded, color: AppTheme.primaryGreen),
            tooltip: 'Salin Kode Grup',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _group!['kode_gk_unik']));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kode Grup disalin: ${_group!['kode_gk_unik']}')));
            },
          ),
          // Tombol Kelola Anggota (hanya untuk Admin)
          if (_group != null && currentUserId == _group!['creator_id'])
            IconButton(
              icon: Badge(
                isLabelVisible: _pendingCount > 0,
                label: Text('$_pendingCount'),
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.manage_accounts_rounded, color: AppTheme.accentGold),
              ),
              tooltip: 'Kelola Anggota',
              onPressed: _showManageMembersDialog,
            ),
          if (_group != null && currentUserId == _group!['creator_id'])
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Hapus Grup',
              onPressed: _confirmDeleteGroup,
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
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        // Kode Group Container
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Text('Kode Bergabung', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(code, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: AppTheme.primaryGreen)),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: AppTheme.primaryGreen),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kode disalin: $code')));
                    },
                  )
                ],
              ),
              SizedBox(height: 8),
              Text('Bagikan kode ini agar anggota lain dapat bergabung sebelum siklus dimulai.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5)),
            ],
          ),
        ),
        SizedBox(height: 32),
        // Members list
        Text('Anggota Bergabung (${_members.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        SizedBox(height: 12),
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
        _buildLimitToggleCard(currentUserId == _group?['creator_id']),
        const SizedBox(height: 24),
        // Divider
        Divider(color: Theme.of(context).dividerColor),
        SizedBox(height: 24),
        // Admin actions
        Text(
          'Mulai Siklus Khataman',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
        ),
        SizedBox(height: 8),
        Text(
          'Admin dapat memulai siklus dan memilih cara pembagian Juz untuk anggota yang telah bergabung.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5, fontSize: 13),
        ),
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startNewPutaran(true),
            icon: Icon(Icons.auto_awesome_rounded),
            label: Text('Bagi Rata Otomatis'),
          ),
        ),
        SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _startNewPutaran(false),
            icon: Icon(Icons.pan_tool_alt_rounded, color: AppTheme.accentGold),
            label: Text('Klaim Mandiri (Open Slot)', style: TextStyle(color: AppTheme.accentGold)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.accentGold),
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLimitToggleCard(bool isAdmin) {
    final isLimited = _group?['limit_juz'] == true;
    final approvedMembersCount = _members.where((m) => m['approval_status'] == 'APPROVED').length;
    final memberCount = approvedMembersCount == 0 ? 1 : approvedMembersCount;
    final maxSlots = (30 / memberCount).ceil();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.gavel_rounded,
                      size: 18,
                      color: isLimited ? AppTheme.accentGold : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Batasi Pengambilan Juz',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isLimited
                      ? 'Dibatasi: Maks $maxSlots Juz per anggota ($memberCount anggota)'
                      : 'Bebas: Anggota dapat mengambil Juz tanpa batas',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin)
            Switch(
              value: isLimited,
              activeColor: AppTheme.primaryGreen,
              onChanged: (value) async {
                setState(() {
                  if (_group != null) {
                    _group!['limit_juz'] = value;
                  }
                });
                try {
                  final result = await _supabase
                      .from('groups')
                      .update({'limit_juz': value})
                      .eq('id_group', widget.groupId)
                      .select();
                  
                  if (result.isEmpty) {
                    throw Exception('Izin update ditolak (RLS). Pastikan Anda adalah pembuat grup di database.');
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? '🔒 Batasan pengambilan Juz diaktifkan!'
                              : '🔓 Batasan pengambilan Juz dinonaktifkan!',
                        ),
                        backgroundColor: AppTheme.primaryGreen,
                      ),
                    );
                  }
                  _fetchData(silent: true);
                } catch (e) {
                  setState(() {
                    if (_group != null) {
                      _group!['limit_juz'] = !value;
                    }
                  });
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
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isLimited
                    ? AppTheme.accentGold.withOpacity(0.15)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isLimited ? 'Aktif' : 'Nonaktif',
                style: TextStyle(
                  color: isLimited ? AppTheme.accentGold : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlotList(String? currentUserId) {
    final completed = _slots.where((s) => s['status_checklist'] == true).length;
    final dateRangeText = _formatDateRange(_putaran?['start_date'], _putaran?['target_deadline']);
    final remainingText = _getRemainingTime(_putaran?['target_deadline']);

    return Column(
      children: [
        // Summary Card
        Container(
          margin: EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A3A2A), Color(0xFF0D2118)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Putaran ${_putaran?['nomor_putaran'] ?? 1}${dateRangeText.isNotEmpty ? ' • $dateRangeText' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$completed / 30 Juz Selesai',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: completed / 30,
                            minHeight: 8,
                            backgroundColor: Colors.white.withOpacity(0.12),
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                          ),
                        ),
                      ),
                      if (remainingText.isNotEmpty) ...[
                        const SizedBox(width: 8),
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
                ],
              ),
              Text(
                '${(completed / 30 * 100).round()}%',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
              ),
            ],
          ),
        ),
        _buildLimitToggleCard(currentUserId == _group?['creator_id']),
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
                if (slot['user_id'] != null) {
                  // Ambil username langsung dari hasil join query
                  final memberName = (slot['users'] as Map<String, dynamic>?)?['username'] as String?;
                  return SlotCard(
                    key: ValueKey('slot_${slot['id_slot']}_${slot['user_id']}'),
                    slot: slot,
                    memberName: memberName,
                    isOwned: slot['user_id'] == currentUserId,
                    onRelease: _releaseSlot,
                    groupId: widget.groupId,
                    groupName: _group?['nama_grup'],
                    onProgressUpdated: () {
                      if (mounted) setState(() {});
                    },
                );
              } else {
                return Container(
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '${slot['nomor_juz']}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Juz ${slot['nomor_juz']}',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                              Text('Slot Kosong', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => _claimSlot(slot['id_slot']),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('Ambil Juz Ini',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          ),
        ),
      ],
    );
  }
}