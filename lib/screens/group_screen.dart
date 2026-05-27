import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'group_detail_screen.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({Key? key}) : super(key: key);

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Set<String> _selectedUsersForInvite = {};
  final _supabase = Supabase.instance.client;
  final _namaGrupController = TextEditingController();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _allGroups = [];
  Set<String> _myGroupIds = {};
  // Map groupId -> approval_status ('APPROVED','PENDING','REJECTED')
  Map<String, String> _myMemberStatus = {};
  bool _isLoading = true;
  final Set<String> _expandedGroupIds = {};
  final Map<String, String> _selectedMemberNamePerGroup = {};
  String _groupVisibility = 'PUBLIC'; // untuk form buat grup
  late TabController _tabController;
  StateSetter? _sheetSetState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _fetchData();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _namaGrupController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sheetSetState?.call(() {});
    });
  }

  /// Get keyboard height directly from the platform View, bypassing MediaQuery overrides.
  double get _keyboardHeight {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  Future<void> _fetchData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final allGroupsData = await _supabase
          .from('groups')
          .select('''
            id_group, nama_grup, kode_gk_unik, creator_id, created_at, visibility,
            users!creator_id(username),
            putaran_siklus(
              id_putaran,
              status_aktif_selesai,
              slot_khataman(
                status_checklist,
                user_id
              )
            ),
            group_members(
              approval_status,
              users(
                id_user,
                username,
                avatar_url
              )
            )
          ''')
          .order('created_at', ascending: false);

      // Ambil status keanggotaan user ini (group_id + approval_status)
      final myGroupsData = await _supabase
          .from('group_members')
          .select('group_id, approval_status')
          .eq('user_id', userId);

      print('Fetched myGroupsData: $myGroupsData');
      final List<Map<String, dynamic>> processedAllGroups = [];
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys();
        for (var group in List<Map<String, dynamic>>.from(allGroupsData)) {
          final prefix = 'archived_group_${group['id_group']}_';
          bool isLocallyArchived = false;
          for (var key in keys) {
            if (key.startsWith(prefix) && prefs.getBool(key) == true) {
              isLocallyArchived = true;
              break;
            }
          }
          if (isLocallyArchived) {
            final mutableGroup = Map<String, dynamic>.from(group);
            mutableGroup['visibility'] = 'ARCHIVED';
            processedAllGroups.add(mutableGroup);
          } else {
            processedAllGroups.add(group);
          }
        }
      } catch (_) {
        processedAllGroups.addAll(List<Map<String, dynamic>>.from(allGroupsData));
      }

      setState(() {
        _allGroups = processedAllGroups;
        _myGroupIds = Set<String>.from(
          myGroupsData.map((item) => item['group_id'].toString()),
        );
        _myMemberStatus = {
          for (final item in myGroupsData)
            item['group_id'].toString(): (item['approval_status'] ?? 'APPROVED') as String
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackbar('Gagal memuat data: $e', isError: true);
    }
  }

  Future<void> _createGroup() async {
    final namaGrup = _namaGrupController.text.trim();
    if (namaGrup.isEmpty) {
      _showSnackbar('Nama grup tidak boleh kosong', isError: true);
      return;
    }

    final uniqueCode = 'GK${1000 + Random().nextInt(9000)}';

    try {
      final data = await _supabase.from('groups').insert({
        'nama_grup': namaGrup,
        'kode_gk_unik': uniqueCode,
        'creator_id': _supabase.auth.currentUser?.id,
        'visibility': _groupVisibility,
      }).select().single();

      // Creator selalu langsung APPROVED
      await _supabase.from('group_members').insert({
        'group_id': data['id_group'],
        'user_id': _supabase.auth.currentUser?.id,
        'approval_status': 'APPROVED',
      });

      _namaGrupController.clear();
      _groupVisibility = 'PUBLIC';
      _showSnackbar('Grup "$namaGrup" berhasil dibuat! Kode: $uniqueCode');
      await _fetchData();

      if (mounted) {
        _showAddMembersDialog(data['id_group']);
      }
    } catch (e) {
      _showSnackbar('Gagal membuat grup: $e', isError: true);
    }
  }

  void _showAddMembersDialog(String groupId) {
    final usersFuture = _supabase.from('users').select().neq('id_user', _supabase.auth.currentUser!.id);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: usersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen)),
              );
            }
            
            final users = snapshot.data ?? [];
            
            return StatefulBuilder(
              builder: (context, setStateSheet) {
                return DraggableScrollableSheet(
                  initialChildSize: 0.7,
                  minChildSize: 0.5,
                  maxChildSize: 0.9,
                  expand: false,
                  builder: (_, scrollController) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40, height: 4,
                                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text('Tambahkan Anggota', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                              const SizedBox(height: 8),
                              Text('Pilih pengguna yang ingin Anda undang ke dalam grup ini.', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: users.isEmpty
                              ? Center(child: Text('Tidak ada pengguna lain', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: users.length,
                                  itemBuilder: (context, index) {
                                    final u = users[index];
                                    final isSelected = _selectedUsersForInvite.contains(u['id_user']);
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        backgroundImage: u['avatar_url'] != null ? NetworkImage(u['avatar_url']) : null,
                                        child: u['avatar_url'] == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
                                      ),
                                      title: Text(u['username'] ?? 'User', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                                      subtitle: Text(u['email'] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                      trailing: Checkbox(
                                        value: isSelected,
                                        activeColor: AppTheme.primaryGreen,
                                        onChanged: (val) {
                                          setStateSheet(() {
                                            if (val == true) {
                                              _selectedUsersForInvite.add(u['id_user']);
                                            } else {
                                              _selectedUsersForInvite.remove(u['id_user']);
                                            }
                                          });
                                        },
                                      ),
                                      onTap: () {
                                        setStateSheet(() {
                                          if (isSelected) {
                                            _selectedUsersForInvite.remove(u['id_user']);
                                          } else {
                                            _selectedUsersForInvite.add(u['id_user']);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
                            ),
                            child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.pop(sheetContext); // Close sheet
                                    _selectedUsersForInvite.clear();
                                    Navigator.push(this.context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
                                  },
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                                  child: const Text('Lewati'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: _selectedUsersForInvite.isEmpty ? null : () async {
                                    // Close sheet first so any error dialog or snackbar is visible
                                    Navigator.pop(sheetContext);
                                    
                                    try {
                                      List<Map<String, dynamic>> inserts = _selectedUsersForInvite.map((uid) => {
                                        'group_id': groupId,
                                        'user_id': uid,
                                      }).toList();
                                      
                                      await _supabase.from('group_members').insert(inserts);
                                      
                                      if (mounted) {
                                        _showSnackbar('${_selectedUsersForInvite.length} anggota berhasil ditambahkan!');
                                        _selectedUsersForInvite.clear();
                                        Navigator.push(this.context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        _selectedUsersForInvite.clear();
                                        showDialog(
                                          context: this.context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Gagal Menambahkan'),
                                            content: Text('Supabase Error: $e\n\nKemungkinan besar database (Row Level Security) melarang Anda menambahkan akun orang lain secara langsung.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.pop(_);
                                                  Navigator.push(this.context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
                                                },
                                                child: const Text('Lanjutkan ke Grup'),
                                              )
                                            ],
                                          )
                                        );
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: Text('Tambahkan (${_selectedUsersForInvite.length})'),
                                ),
                              ),
                            ],
                          ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      // In case they swiped down to dismiss instead of clicking "Lewati"
      if (_selectedUsersForInvite.isEmpty) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
      }
    });
  }

  Future<void> _joinGroup(String groupId, String groupName, String visibility) async {
    final isPrivate = visibility == 'PRIVATE';
    final status = isPrivate ? 'PENDING' : 'APPROVED';

    try {
      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': _supabase.auth.currentUser?.id,
        'approval_status': status,
      });

      // Kirim notifikasi ke pembuat/admin grup
      try {
        final group = _allGroups.firstWhere((g) => g['id_group'].toString() == groupId);
        final creatorId = group['creator_id'] as String?;
        final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
            _supabase.auth.currentUser?.email?.split('@')[0] ??
            'Seseorang';

        if (creatorId != null && creatorId != _supabase.auth.currentUser?.id) {
          if (isPrivate) {
            await NotificationService.send(
              userId: creatorId,
              type: 'JOIN_REQUEST',
              title: 'Permintaan Bergabung',
              body: '$senderName meminta bergabung ke grup "$groupName"',
              groupId: groupId,
              senderId: _supabase.auth.currentUser?.id,
            );
          } else {
            await NotificationService.send(
              userId: creatorId,
              type: 'MEMBER_JOINED',
              title: 'Anggota Baru Bergabung',
              body: '$senderName telah bergabung ke grup "$groupName"',
              groupId: groupId,
              senderId: _supabase.auth.currentUser?.id,
            );
          }
        }
      } catch (notifErr) {
        print('Error sending join notification: $notifErr');
      }

      await _fetchData();

      if (isPrivate) {
        _showSnackbar('Permintaan bergabung terkirim! Tunggu persetujuan Admin.');
      } else {
        _showSnackbar('Berhasil bergabung dengan "$groupName"!');
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupDetailScreen(groupId: groupId),
          ));
        }
      }
    } catch (e) {
      _showSnackbar('Gagal bergabung: sudah terdaftar atau terjadi error', isError: true);
    }
  }

  Future<void> _cancelJoinRequest(String groupId, String groupName) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final res = await _supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .select();
      print('Cancel Join Request result: $res');

      _showSnackbar('Permintaan bergabung ke "$groupName" berhasil dibatalkan.');
      await _fetchData();
    } catch (e) {
      _showSnackbar('Gagal membatalkan permintaan: $e', isError: true);
    }
  }

  void _showCancelJoinDialog(String groupId, String groupName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Batalkan Permintaan?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Apakah Anda yakin ingin membatalkan permintaan bergabung dengan grup "$groupName"?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Batal',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelJoinRequest(groupId, groupName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Batalkan Permintaan'),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : AppTheme.primaryGreen,
    ));
  }

  List<Map<String, dynamic>> get _filteredAllGroups {
    final query = _searchController.text.toLowerCase();
    return _allGroups.where((g) {
      if ((g['visibility'] ?? '') == 'ARCHIVED') return false;
      if (query.isEmpty) return true;
      return (g['nama_grup'] ?? '').toLowerCase().contains(query) ||
          (g['kode_gk_unik'] ?? '').toLowerCase().contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _myGroups =>
      _allGroups.where((g) =>
        _myGroupIds.contains(g['id_group'].toString()) &&
        (g['visibility'] ?? '') != 'ARCHIVED'
      ).toList();

  List<Map<String, dynamic>> get _archivedGroups =>
      _allGroups.where((g) =>
        _myGroupIds.contains(g['id_group'].toString()) &&
        (g['visibility'] ?? '') == 'ARCHIVED'
      ).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Khataman Grup'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchData();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryGreen,
          labelColor: AppTheme.primaryGreen,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          tabs: [
            Tab(text: 'Semua Grup (${_filteredAllGroups.length})'),
            Tab(text: 'Grup Saya (${_myGroups.length})'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.archive_outlined, size: 15),
                  const SizedBox(width: 5),
                  Text('Arsip (${_archivedGroups.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGroupBottomSheet,
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Buat Grup'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAllGroupsTab(),
                _buildMyGroupsTab(),
                _buildArchivedGroupsTab(),
              ],
            ),
    );
  }

  void _showCreateGroupBottomSheet() {
    _groupVisibility = 'PUBLIC';
    _namaGrupController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            _sheetSetState = setModalState;
            final isDark = Theme.of(modalContext).brightness == Brightness.dark;
            final surfaceColor = isDark ? const Color(0xFF161B22) : const Color(0xFFFAFCFA);
            final inputBgColor = isDark ? const Color(0xFF1F2937) : const Color(0xFFEDF2ED);
            final borderColor = isDark ? const Color(0xFF30363D) : const Color(0xFFD4DDD6);
            final onSurfaceColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1D2A22);
            final onSurfaceVariantColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF5F6E65);

            return Padding(
              padding: EdgeInsets.only(bottom: _keyboardHeight),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(modalContext).unfocus(),
                child: SingleChildScrollView(
                  child: Container(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Drag Handle ──
                            Container(
                              width: 40,
                              height: 4.5,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),

                            // ── Header Row ──
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF2ECC71), Color(0xFF1A8A4A)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryGreen.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Buat Grup Baru',
                                        style: TextStyle(
                                          color: onSurfaceColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Khataman Al-Quran bersama',
                                        style: TextStyle(
                                          color: onSurfaceVariantColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pop(modalContext),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.close_rounded, size: 18, color: onSurfaceVariantColor),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // ── Label ──
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Nama Grup',
                                style: TextStyle(
                                  color: onSurfaceVariantColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ── Text Field ──
                            TextField(
                              controller: _namaGrupController,
                              style: TextStyle(color: onSurfaceColor),
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText: 'Contoh: Khataman Keluarga',
                                filled: true,
                                fillColor: inputBgColor,
                                prefixIcon: Icon(Icons.edit_rounded, size: 18, color: onSurfaceVariantColor),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Visibility Label ──
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Visibilitas Grup',
                                style: TextStyle(
                                  color: onSurfaceVariantColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ── Toggle Public / Private ──
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => _groupVisibility = 'PUBLIC'),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      decoration: BoxDecoration(
                                        color: _groupVisibility == 'PUBLIC'
                                            ? AppTheme.primaryGreen
                                            : inputBgColor,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _groupVisibility == 'PUBLIC'
                                              ? AppTheme.primaryGreen
                                              : borderColor,
                                          width: _groupVisibility == 'PUBLIC' ? 1.5 : 1,
                                        ),
                                        boxShadow: _groupVisibility == 'PUBLIC'
                                            ? [
                                                BoxShadow(
                                                  color: AppTheme.primaryGreen.withOpacity(0.25),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.public_rounded,
                                            size: 17,
                                            color: _groupVisibility == 'PUBLIC'
                                                ? Colors.white
                                                : onSurfaceVariantColor,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Publik',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: _groupVisibility == 'PUBLIC'
                                                  ? Colors.white
                                                  : onSurfaceVariantColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => _groupVisibility = 'PRIVATE'),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      decoration: BoxDecoration(
                                        color: _groupVisibility == 'PRIVATE'
                                            ? AppTheme.accentGold
                                            : inputBgColor,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _groupVisibility == 'PRIVATE'
                                              ? AppTheme.accentGold
                                              : borderColor,
                                          width: _groupVisibility == 'PRIVATE' ? 1.5 : 1,
                                        ),
                                        boxShadow: _groupVisibility == 'PRIVATE'
                                            ? [
                                                BoxShadow(
                                                  color: AppTheme.accentGold.withOpacity(0.25),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.lock_rounded,
                                            size: 17,
                                            color: _groupVisibility == 'PRIVATE'
                                                ? Colors.white
                                                : onSurfaceVariantColor,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Privat',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: _groupVisibility == 'PRIVATE'
                                                  ? Colors.white
                                                  : onSurfaceVariantColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // ── Private Info Note ──
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: _groupVisibility == 'PRIVATE'
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accentGold.withOpacity(isDark ? 0.12 : 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: AppTheme.accentGold.withOpacity(0.2),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.accentGold),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Anggota harus disetujui Admin sebelum bergabung.',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: isDark ? AppTheme.accentGold : Colors.amber.shade800,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),

                            const SizedBox(height: 24),

                            // ── Submit Button ──
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF2ECC71), Color(0xFF1A8A4A)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryGreen.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await _createGroup();
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                                  label: const Text(
                                    'Buat Grup Sekarang',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _sheetSetState = null;
    });
  }

  Widget _buildAllGroupsTab() {
    return RefreshIndicator(
      color: AppTheme.primaryGreen,
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _fetchData,
      child: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Cari grup atau kode...',
                prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
          // Group List
          Expanded(
            child: _filteredAllGroups.isEmpty
                ? _buildEmptyState('Tidak ada grup ditemukan')
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 80 + MediaQuery.of(context).padding.bottom),
                    itemCount: _filteredAllGroups.length,
                    itemBuilder: (context, index) {
                      final group = _filteredAllGroups[index];
                      final isJoined = _myGroupIds.contains(group['id_group'].toString());
                      final isCreator = group['creator_id'] == _supabase.auth.currentUser?.id;
                      return _buildGroupCard(group, isJoined: isJoined, isCreator: isCreator);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyGroupsTab() {
    return RefreshIndicator(
      color: AppTheme.primaryGreen,
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _fetchData,
      child: _myGroups.isEmpty
          ? _buildEmptyState('Anda belum bergabung ke grup manapun.\nCari grup di tab "Semua Grup" dan klik Gabung!')
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 80 + MediaQuery.of(context).padding.bottom),
              itemCount: _myGroups.length,
              itemBuilder: (context, index) {
                final group = _myGroups[index];
                final isCreator = group['creator_id'] == _supabase.auth.currentUser?.id;
                return _buildGroupCard(group, isJoined: true, isCreator: isCreator);
              },
            ),
    );
  }

  Widget _buildArchivedGroupsTab() {
    return RefreshIndicator(
      color: AppTheme.primaryGreen,
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _fetchData,
      child: _archivedGroups.isEmpty
          ? _buildEmptyState('Belum ada grup yang diarsipkan.\nGrup akan diarsipkan setelah Doa Khatam Al-Quran selesai dibaca.')
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 80 + MediaQuery.of(context).padding.bottom),
              itemCount: _archivedGroups.length,
              itemBuilder: (context, index) {
                final group = _archivedGroups[index];
                final isCreator = group['creator_id'] == _supabase.auth.currentUser?.id;
                return _buildGroupCard(group, isJoined: true, isCreator: isCreator);
              },
            ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group, {required bool isJoined, required bool isCreator}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupId = group['id_group'].toString();
    final visibility = (group['visibility'] ?? 'PUBLIC') as String;
    final isPrivate = visibility == 'PRIVATE';
    final memberStatus = _myMemberStatus[groupId];
    final isPending = memberStatus == 'PENDING';
    final isApproved = memberStatus == 'APPROVED';
    final canOpen = isJoined && isApproved;
    final isExpanded = _expandedGroupIds.contains(groupId);

    // Calculate group active round reading progress
    final cycles = group['putaran_siklus'] as List<dynamic>? ?? [];
    Map<String, dynamic>? activeCycle;
    for (var c in cycles) {
      if (c['status_aktif_selesai'] == 'AKTIF') {
        activeCycle = c as Map<String, dynamic>;
        break;
      }
    }
    if (activeCycle == null && visibility == 'ARCHIVED') {
      for (var c in cycles) {
        if (c['status_aktif_selesai'] == 'SELESAI') {
          activeCycle = c as Map<String, dynamic>;
          break;
        }
      }
    }

    int completedCount = 0;
    int claimedCount = 0;
    double progress = 0.0;
    double claimedProgress = 0.0;
    if (activeCycle != null) {
      final slots = activeCycle['slot_khataman'] as List<dynamic>? ?? [];
      completedCount = slots.where((s) => s['status_checklist'] == true).length;
      progress = completedCount / 30.0;
      claimedCount = slots.where((s) => s['user_id'] != null).length;
      claimedProgress = claimedCount / 30.0;
    }

    // Extract approved members list
    final rawMembers = group['group_members'] as List<dynamic>? ?? [];
    final approvedMembers = rawMembers.where((m) => m['approval_status'] == 'APPROVED').toList();

    return GestureDetector(
      onTap: canOpen
          ? () {
              setState(() {
                if (isExpanded) {
                  _expandedGroupIds.remove(groupId);
                  _selectedMemberNamePerGroup.remove(groupId);
                } else {
                  _expandedGroupIds.add(groupId);
                }
              });
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPending
                ? AppTheme.accentGold.withOpacity(0.4)
                : isApproved
                    ? (isDark
                        ? AppTheme.primaryGreen.withOpacity(0.3)
                        : AppTheme.primaryGreen.withOpacity(0.35))
                    : (isDark
                        ? const Color(0xFF6C63FF).withOpacity(0.3)
                        : const Color(0xFF6C63FF).withOpacity(0.15)),
          ),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: (isDark ? Colors.black : Colors.grey.shade200).withOpacity(isDark ? 0.3 : 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: isDark
                        ? LinearGradient(
                            colors: canOpen
                                ? [const Color(0xFF2ECC71), const Color(0xFF1A8A4A)]
                                : isPending
                                    ? [const Color(0xFFB8860B), const Color(0xFF8B6508)]
                                    : [const Color(0xFF6C63FF), const Color(0xFF3F3D8B)],
                          )
                        : null,
                    color: isDark
                        ? null
                        : canOpen
                            ? AppTheme.primaryGreen.withOpacity(0.12)
                            : isPending
                                ? AppTheme.accentGold.withOpacity(0.12)
                                : const Color(0xFF6C63FF).withOpacity(0.12),
                    border: isDark
                        ? null
                        : Border.all(
                            color: canOpen
                                ? AppTheme.primaryGreen.withOpacity(0.25)
                                : isPending
                                    ? AppTheme.accentGold.withOpacity(0.25)
                                    : const Color(0xFF6C63FF).withOpacity(0.25),
                            width: 0.8,
                          ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    canOpen
                        ? Icons.group_rounded
                        : isPending
                            ? Icons.hourglass_top_rounded
                            : Icons.group_add_rounded,
                    color: isDark
                        ? Colors.white
                        : canOpen
                            ? AppTheme.darkGreen
                            : isPending
                                ? const Color(0xFF8B6508)
                                : const Color(0xFF3F3D8B),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              group['nama_grup'] ?? 'Grup',
                              style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPrivate) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.lock_rounded, size: 13, color: AppTheme.accentGold),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                       Row(
                        children: [
                          Icon(Icons.tag_rounded, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            group['kode_gk_unik'] ?? '',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                          if (isCreator) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accentGold.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Admin', style: TextStyle(color: AppTheme.accentGold, fontSize: 10)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action Button
                if (canOpen)
                Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => GroupDetailScreen(groupId: group['id_group'])));
                          if (mounted) _fetchData();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isDark 
                                ? AppTheme.primaryGreen.withOpacity(0.15) 
                                : AppTheme.primaryGreen.withOpacity(0.12),
                            border: isDark 
                                ? null 
                                : Border.all(
                                    color: AppTheme.primaryGreen.withOpacity(0.25),
                                    width: 0.8,
                                  ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Buka', 
                            style: TextStyle(
                              color: isDark ? AppTheme.primaryGreen : AppTheme.darkGreen, 
                              fontWeight: FontWeight.w600, 
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                        size: 22,
                      ),
                    ],
                  )
                else if (isPending)
                  GestureDetector(
                    onTap: () => _showCancelJoinDialog(groupId, group['nama_grup'] ?? 'Grup'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark 
                              ? AppTheme.accentGold.withOpacity(0.4) 
                              : AppTheme.accentGold.withOpacity(0.25),
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top_rounded, size: 12, color: AppTheme.accentGold),
                          SizedBox(width: 4),
                          Text(
                            'Menunggu', 
                            style: TextStyle(
                              color: AppTheme.accentGold, 
                              fontWeight: FontWeight.w600, 
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _joinGroup(group['id_group'], group['nama_grup'] ?? 'Grup', visibility),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: isDark
                            ? const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF3F3D8B)],
                              )
                            : null,
                        color: isDark ? null : const Color(0xFF6C63FF).withOpacity(0.12),
                        border: isDark 
                            ? null 
                            : Border.all(
                                color: const Color(0xFF6C63FF).withOpacity(0.25),
                                width: 0.8,
                              ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Gabung', 
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF3F3D8B), 
                          fontWeight: FontWeight.w600, 
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              firstCurve: Curves.easeInOut,
              secondCurve: Curves.easeInOut,
              crossFadeState: (canOpen && isExpanded)
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Divider(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  // Admin Info (Only visible when expanded!)
                  Row(
                    children: [
                      Icon(Icons.person_rounded, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        'Admin: ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        isCreator ? 'Anda' : (group['users']?['username'] ?? '...'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Progress Bar Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progres Grup',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. Label Claimed (Ambil) in Gold/Amber
                          Text(
                            '$claimedCount Diambil',
                            style: TextStyle(
                              color: isDark ? AppTheme.accentGold : Colors.amber.shade800,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                          // 2. Label Completed (Selesai) in Green
                          Text(
                            '$completedCount Selesai (${(progress * 100).toInt()}%)',
                            style: TextStyle(
                              color: isDark ? AppTheme.primaryGreen : AppTheme.darkGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          // Lapisan 1: Pengambilan Juz (Gold) - Ditumpuk di bawah
                          LinearProgressIndicator(
                            value: claimedProgress,
                            minHeight: 6,
                            backgroundColor: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? AppTheme.accentGold : AppTheme.accentGold.withOpacity(0.8),
                            ),
                          ),
                          // Lapisan 2: Selesai Dibaca (Hijau) - Ditumpuk di atas dengan latar belakang transparan
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? AppTheme.primaryGreen : AppTheme.darkGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Group Members Section
                  Row(
                    children: [
                      Text(
                        'Anggota Grup ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (isDark ? AppTheme.primaryGreen : AppTheme.darkGreen).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${approvedMembers.length} Orang',
                          style: TextStyle(
                            color: isDark ? AppTheme.primaryGreen : AppTheme.darkGreen,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (approvedMembers.isEmpty)
                    Text(
                      'Belum ada anggota.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    SizedBox(
                      height: 32,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        clipBehavior: Clip.none, // Allow tooltips to overlap elements above without pushing layout!
                        itemCount: approvedMembers.length,
                        itemBuilder: (context, idx) {
                          final m = approvedMembers[idx];
                          final avatarUrl = m['users']?['avatar_url'] as String?;
                          final name = m['users']?['username'] as String? ?? '...';
                          final isSelected = _selectedMemberNamePerGroup[groupId] == name;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              // Prevent tap bubbling/propagation to parent GestureDetector!
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedMemberNamePerGroup.remove(groupId);
                                  } else {
                                    _selectedMemberNamePerGroup[groupId] = name;
                                  }
                                });
                              },
                              child: SizedBox(
                                width: 28,
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  clipBehavior: Clip.none,
                                  children: [
                                    // 1. Avatar Container
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: (isDark ? AppTheme.primaryGreen : AppTheme.darkGreen).withOpacity(0.15),
                                          width: 1,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: (isDark ? AppTheme.primaryGreen : AppTheme.darkGreen).withOpacity(0.08),
                                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                            ? NetworkImage(avatarUrl)
                                            : null,
                                        child: avatarUrl == null || avatarUrl.isEmpty
                                            ? Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? AppTheme.primaryGreen : AppTheme.darkGreen,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                    // 2. Custom Float Tooltip Box (Centered directly above!)
                                    if (isSelected)
                                      Positioned(
                                        bottom: 34, // Sits perfectly 6px above the 28px avatar
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.85),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}