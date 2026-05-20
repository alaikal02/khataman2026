import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'group_detail_screen.dart';
import '../theme/app_theme.dart';
import 'dart:math';

class GroupScreen extends StatefulWidget {
  const GroupScreen({Key? key}) : super(key: key);

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with SingleTickerProviderStateMixin {
  final Set<String> _selectedUsersForInvite = {};
  final _supabase = Supabase.instance.client;
  final _namaGrupController = TextEditingController();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _allGroups = [];
  Set<String> _myGroupIds = {};
  bool _isLoading = true;
  bool _showCreateForm = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _namaGrupController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Ambil SEMUA grup
      final allGroupsData = await _supabase
          .from('groups')
          .select('id_group, nama_grup, kode_gk_unik, creator_id, created_at')
          .order('created_at', ascending: false);

      // Ambil grup yang sudah diikuti user ini
      final myGroupsData = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', userId);

      setState(() {
        _allGroups = List<Map<String, dynamic>>.from(allGroupsData);
        _myGroupIds = Set<String>.from(
          myGroupsData.map((item) => item['group_id'].toString()),
        );
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
      }).select().single();

      await _supabase.from('group_members').insert({
        'group_id': data['id_group'],
        'user_id': _supabase.auth.currentUser?.id,
      });

      _namaGrupController.clear();
      setState(() => _showCreateForm = false);
      _showSnackbar('Grup "${namaGrup}" berhasil dibuat! Kode: $uniqueCode');
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: usersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
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
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40, height: 4,
                                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              SizedBox(height: 20),
                              Text('Tambahkan Anggota', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                              SizedBox(height: 8),
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
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
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
                                  child: Text('Lewati'),
                                  style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16)),
                                ),
                              ),
                              SizedBox(width: 12),
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
                                            title: Text('Gagal Menambahkan'),
                                            content: Text('Supabase Error: $e\n\nKemungkinan besar database (Row Level Security) melarang Anda menambahkan akun orang lain secara langsung.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.pop(_);
                                                  Navigator.push(this.context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
                                                },
                                                child: Text('Lanjutkan ke Grup'),
                                              )
                                            ],
                                          )
                                        );
                                      }
                                    }
                                  },
                                  child: Text('Tambahkan (${_selectedUsersForInvite.length})'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryGreen,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                  ),
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
        Navigator.push(this.context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
      }
    });
  }

  Future<void> _joinGroup(String groupId, String groupName) async {
    try {
      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': _supabase.auth.currentUser?.id,
      });

      _showSnackbar('Berhasil bergabung dengan "$groupName"!');
      await _fetchData();

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => GroupDetailScreen(groupId: groupId),
        ));
      }
    } catch (e) {
      _showSnackbar('Gagal bergabung: sudah terdaftar atau terjadi error', isError: true);
    }
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
    if (query.isEmpty) return _allGroups;
    return _allGroups.where((g) =>
      (g['nama_grup'] ?? '').toLowerCase().contains(query) ||
      (g['kode_gk_unik'] ?? '').toLowerCase().contains(query)
    ).toList();
  }

  List<Map<String, dynamic>> get _myGroups =>
      _allGroups.where((g) => _myGroupIds.contains(g['id_group'].toString())).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Khataman Grup'),
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
            Tab(text: 'Semua Grup (${_allGroups.length})'),
            Tab(text: 'Grup Saya (${_myGroups.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showCreateForm = !_showCreateForm),
        backgroundColor: AppTheme.primaryGreen,
        icon: Icon(_showCreateForm ? Icons.close_rounded : Icons.add_rounded),
        label: Text(_showCreateForm ? 'Tutup' : 'Buat Grup'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : Column(
              children: [
                // Create Form
                if (_showCreateForm) _buildCreateForm(),
                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAllGroupsTab(),
                      _buildMyGroupsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCreateForm() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Buat Grup Khataman Baru', style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 15,
          )),
          SizedBox(height: 10),
          TextField(
            controller: _namaGrupController,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: const InputDecoration(hintText: 'Nama grup (misal: Khataman Keluarga)'),
          ),
          SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _createGroup,
              child: Text('Buat Grup Sekarang'),
            ),
          ),
        ],
      ),
    );
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
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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

  Widget _buildGroupCard(Map<String, dynamic> group, {required bool isJoined, required bool isCreator}) {
    return GestureDetector(
      onTap: isJoined
          ? () async {
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => GroupDetailScreen(groupId: group['id_group'])));
              if (mounted) _fetchData();
            }
          : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isJoined
                ? AppTheme.primaryGreen.withOpacity(0.3)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isJoined
                      ? [const Color(0xFF2ECC71), const Color(0xFF1A8A4A)]
                      : [const Color(0xFF6C63FF), const Color(0xFF3F3D8B)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isJoined ? Icons.group_rounded : Icons.group_add_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group['nama_grup'] ?? 'Grup',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.tag_rounded, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 3),
                      Text(
                        group['kode_gk_unik'] ?? '',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                      if (isCreator) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Admin', style: TextStyle(color: AppTheme.accentGold, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Action Button
            if (isJoined)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Buka', style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600, fontSize: 13)),
              )
            else
              GestureDetector(
                onTap: () => _joinGroup(group['id_group'], group['nama_grup'] ?? 'Grup'),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3F3D8B)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Gabung', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
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
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
            SizedBox(height: 16),
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