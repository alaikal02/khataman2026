import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../components/slot_card.dart';
import '../theme/app_theme.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _group;
  Map<String, dynamic>? _putaran;
  List<dynamic> _slots = [];
  List<dynamic> _members = [];
  RealtimeChannel? _subscription;
  bool _isLoading = true; // ← State loading yang sebelumnya tidak ada
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _fetchData();
    _setupRealtime();
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _shimmerController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    // Gunakan nama channel unik per grup agar tidak konflik antar halaman
    final channelName = 'group_detail_${widget.groupId}';
    _subscription = _supabase.channel(channelName).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'slot_khataman',
      callback: (payload) {
        if (mounted) _fetchData(silent: true);
      },
    ).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'putaran_siklus',
      callback: (payload) {
        if (mounted) _fetchData(silent: true);
      },
    ).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'group_members',
      callback: (payload) {
        if (mounted) _fetchData(silent: true);
      },
    ).subscribe();
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
        }
        // Join dengan tabel users untuk langsung dapat username
        sData = await _supabase
            .from('slot_khataman')
            .select('*, users(username)')
            .eq('putaran_id', pData['id_putaran'])
            .order('nomor_juz', ascending: true);
      }

      if (mounted) {
        setState(() {
          _group = groupData;
          _putaran = pData;
          _slots = sData;
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
      final targetDate = DateTime.now().add(const Duration(days: 7));
      final newPutaran = await _supabase.from('putaran_siklus').insert({
        'group_id': widget.groupId,
        'nomor_putaran': 1,
        'target_deadline': targetDate.toIso8601String()
      }).select().single();

      if (isAutoAssign) {
        final members = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', widget.groupId);
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
        ],
      ),
      body: _isLoading
          // ← Shimmer ditampilkan selama loading, bukan empty state
          ? _buildShimmerList()
          : _putaran == null
              ? _buildNoPutaran()
              : _buildSlotList(currentUserId),
    );
  }

  Widget _buildNoPutaran() {
    final code = _group?['kode_gk_unik'] ?? '-';
    return ListView(
      padding: EdgeInsets.all(24),
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
        SizedBox(height: 24),
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

  Widget _buildSlotList(String? currentUserId) {
    final completed = _slots.where((s) => s['status_checklist'] == true).length;
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
                  Text('Putaran ${1}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  SizedBox(height: 4),
                  Text(
                    '$completed / 30 Juz Selesai',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: completed / 30,
                        minHeight: 8,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                      ),
                    ),
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
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primaryGreen,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onRefresh: () => _fetchData(silent: true),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
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