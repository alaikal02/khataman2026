import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class JuzAssignmentScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const JuzAssignmentScreen({
    Key? key,
    required this.groupId,
    required this.groupName,
  }) : super(key: key);

  @override
  State<JuzAssignmentScreen> createState() => _JuzAssignmentScreenState();
}

class _JuzAssignmentScreenState extends State<JuzAssignmentScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _slots = [];
  List<Map<String, dynamic>> _originalSlots = [];
  Map<String, dynamic>? _activeCycle;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _limitJuz = false;
  String _selectedBrushUserId = 'eraser'; // 'eraser' = eraser, or user_id

  // Precomputed unique initials and contrast colors for all approved members
  final Map<String, String> _uniqueInitials = {};
  final Map<String, Color> _memberColors = {};

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_pulseController);
    _fetchData();
    _setupRealtime();
  }

  @override
  void dispose() {
    if (_subscription != null) {
      try {
        _supabase.removeChannel(_subscription!);
      } catch (e) {
        debugPrint('Error removing realtime channel: $e');
      }
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    final channelName = 'juz_assignment_${widget.groupId}';
    _subscription = _supabase.channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'slot_khataman',
          callback: (payload) {
            debugPrint('🔄 [Realtime Admin Grid] Slot khataman changed. Syncing...');
            if (mounted) {
              _fetchData(silent: true);
            }
          },
        )
        .subscribe();
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 1. Fetch approved group members
      final membersData = await _supabase
          .from('group_members')
          .select('user_id, users(id_user, username, email, avatar_url)')
          .eq('group_id', widget.groupId)
          .eq('approval_status', 'APPROVED');

      // 2. Fetch active putaran_siklus
      final cycleData = await _supabase
          .from('putaran_siklus')
          .select()
          .eq('group_id', widget.groupId)
          .order('nomor_putaran', ascending: false) // Latest active
          .limit(1)
          .maybeSingle();

      List<Map<String, dynamic>> slotsList = [];

      if (cycleData != null) {
        // 3. Fetch slot_khataman for this active cycle
        final slotsData = await _supabase
            .from('slot_khataman')
            .select('*, users(id_user, username, avatar_url)')
            .eq('putaran_id', cycleData['id_putaran'])
            .order('nomor_juz', ascending: true);

        slotsList = List<Map<String, dynamic>>.from(slotsData);
      }

      // Fetch group details to get limit_juz
      final groupData = await _supabase
          .from('groups')
          .select('limit_juz')
          .eq('id_group', widget.groupId)
          .maybeSingle();

      final bool limitJuz = groupData != null ? (groupData['limit_juz'] == true) : false;

      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(membersData);
          _activeCycle = cycleData;
          _slots = slotsList;
          _originalSlots = slotsList.map((slot) => Map<String, dynamic>.from(slot)).toList();
          _limitJuz = limitJuz;
          _isLoading = false;
          _generateUniqueInitialsAndColors();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat data: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _clearAllSlots() {
    setState(() {
      for (var slot in _slots) {
        final lastAyat = slot['ayat_terakhir_input'] as int? ?? 0;
        final statusChecklist = slot['status_checklist'] == true;
        if (lastAyat > 0 || statusChecklist) continue;

        slot['user_id'] = null;
        slot['users'] = null;
        slot['ayat_terakhir_input'] = 0;
        slot['status_checklist'] = false;
      }
      _selectedBrushUserId = 'eraser';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draf pembagian yang belum dibaca berhasil dibersihkan'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _cancelDraftChanges() {
    setState(() {
      _slots = _originalSlots.map((slot) => Map<String, dynamic>.from(slot)).toList();
      _selectedBrushUserId = 'eraser';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Perubahan draf dibatalkan'),
        backgroundColor: Colors.grey,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _saveDraftChanges() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final List<Future> updateFutures = [];

      for (int i = 0; i < _slots.length; i++) {
        final slot = _slots[i];
        final orig = _originalSlots.firstWhere(
          (o) => o['id_slot'] == slot['id_slot'],
          orElse: () => {},
        );
        
        if (orig.isNotEmpty) {
          if (slot['user_id'] != orig['user_id']) {
            String? prevUsername;
            if (slot['user_id'] == null) {
              final usersMap = orig['users'] as Map<String, dynamic>?;
              prevUsername = usersMap?['username'] as String?;
            }
            updateFutures.add(
              _supabase.from('slot_khataman').update({
                'user_id': slot['user_id'],
                'ayat_terakhir_input': slot['ayat_terakhir_input'],
                'status_checklist': slot['status_checklist'],
                if (slot['user_id'] == null) 'username_sebelumnya': prevUsername,
              }).eq('id_slot', slot['id_slot'])
            );
          }
        }
      }

      if (updateFutures.isNotEmpty) {
        await Future.wait(updateFutures);
      }

      setState(() {
        _originalSlots = _slots.map((s) => Map<String, dynamic>.from(s)).toList();
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pembagian Juz berhasil disimpan!'),
            backgroundColor: AppTheme.primaryGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan pembagian Juz: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Locked high-contrast color palette (Open Color standard)
  static const List<Color> _contrastPalette = [
    Color(0xFF339AF0), // 1. Biru Langit (Sky Blue)
    Color(0xFF51CF66), // 2. Hijau Daun (Leaf Green)
    Color(0xFFFCC419), // 3. Kuning Cerah (Bright Yellow)
    Color(0xFFFF922B), // 4. Oranye (Orange)
    Color(0xFFFF6B6B), // 5. Merah (Red)
    Color(0xFFF06595), // 6. Merah Muda/Pink (Pink)
    Color(0xFFCC5DE8), // 7. Ungu (Purple)
    Color(0xFFAD7A56), // 8. Cokelat (Brown)
    Color(0xFF868E96), // 9. Abu-abu Tua (Blue Gray)
    Color(0xFF20C997), // 10. Toska (Teal/Turquoise)
  ];

  Color _getPastelColor(String input) {
    final int hash = input.hashCode;
    final int index = hash.abs() % _contrastPalette.length;
    return _contrastPalette[index];
  }

  String _getInitials2(String name) {
    final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').trim();
    if (clean.isEmpty) return 'UM';
    if (clean.length >= 2) {
      return clean.substring(0, 2).toUpperCase();
    }
    return clean.toUpperCase();
  }

  bool _checkCollisionInGroup(String candidate, String currentName, List<String> group) {
    for (var otherName in group) {
      if (otherName == currentName) continue;
      
      final otherClean = otherName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').trim();
      final otherCandidate = otherClean.length >= 3 
          ? otherClean.substring(0, 3).toUpperCase() 
          : '${otherClean}X'.toUpperCase().substring(0, 3);
      
      if (otherCandidate == candidate) return true;
    }
    return false;
  }

  String _getInitials3(String name, List<String> duplicateGroup) {
    final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').trim();
    if (clean.isEmpty) return 'UMM';
    
    String candidate = clean.length >= 3 
        ? clean.substring(0, 3).toUpperCase() 
        : '${clean}X'.toUpperCase().substring(0, 3);
        
    int attempts = 2; // start using character at index 2 (3rd char)
    String currentCandidate = candidate;
    bool hasCollision = _checkCollisionInGroup(currentCandidate, name, duplicateGroup);
    
    while (hasCollision && attempts < clean.length) {
      final nextChar = clean[attempts].toUpperCase();
      currentCandidate = '${clean.substring(0, 2).toUpperCase()}$nextChar';
      hasCollision = _checkCollisionInGroup(currentCandidate, name, duplicateGroup);
      attempts++;
    }
    
    if (hasCollision) {
      final idx = duplicateGroup.indexOf(name);
      currentCandidate = '${clean.substring(0, 2).toUpperCase()}${idx + 1}';
    }
    
    return currentCandidate;
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '??';
    final cleanName = name.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
    if (cleanName.isEmpty) return '??';
    final parts = cleanName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    if (cleanName.length >= 2) {
      return cleanName.substring(0, 2).toUpperCase();
    }
    return cleanName.toUpperCase();
  }

  void _generateUniqueInitialsAndColors() {
    _uniqueInitials.clear();
    _memberColors.clear();

    // 1. Generate unique colors sequentially to guarantee maximum contrast between adjacent members
    for (int i = 0; i < _members.length; i++) {
      final member = _members[i];
      final userId = member['user_id'] as String;
      final color = _contrastPalette[i % _contrastPalette.length];
      _memberColors[userId] = color;
    }

    // 2. Generate unique initials (2 letters by default, 3 letters if duplicates found)
    final Map<String, List<String>> reverseMap = {}; // initials -> list of usernames
    for (var member in _members) {
      final user = member['users'] as Map<String, dynamic>? ?? {};
      final username = user['username'] as String? ?? 'Umum';
      final initials = _getInitials2(username);
      reverseMap.putIfAbsent(initials, () => []).add(username);
    }

    for (var member in _members) {
      final user = member['users'] as Map<String, dynamic>? ?? {};
      final username = user['username'] as String? ?? 'Umum';
      final userId = member['user_id'] as String;
      final initials = _getInitials2(username);

      if (reverseMap[initials]!.length > 1) {
        _uniqueInitials[userId] = _getInitials3(username, reverseMap[initials]!);
      } else {
        _uniqueInitials[userId] = initials;
      }
    }
  }

  void _applySlotChange(Map<String, dynamic> slot, String? newUserId, Map<String, dynamic>? newUsers) {
    setState(() {
      slot['user_id'] = newUserId;
      slot['users'] = newUsers;
      slot['ayat_terakhir_input'] = 0;
      slot['status_checklist'] = false;
      if (newUserId == null) {
        _selectedBrushUserId = 'eraser';
      }
    });
  }

  void _handleJuzTap(Map<String, dynamic> slot) {
    // Intercept jika slot statusnya PENDING (pengajuan lepas dari anggota)
    if (slot['approval_lepas_status'] == 'PENDING') {
      final claimedUser = slot['users'] as Map<String, dynamic>? ?? {};
      final claimedUsername = claimedUser['username'] as String? ?? 'Anggota';
      final int juzNo = slot['nomor_juz'] as int;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text(
            'Persetujuan Lepas Juz',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Anggota "$claimedUsername" mengajukan untuk melepas Juz $juzNo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  // SETUJUI: user_id = NULL, pertahankan progres, set approval_lepas_status = NULL
                  await _supabase.from('slot_khataman').update({
                    'user_id': null,
                    'approval_lepas_status': null,
                    'username_sebelumnya': claimedUsername,
                  }).eq('id_slot', slot['id_slot']);
                  _fetchData(silent: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Juz $juzNo berhasil dilepas.'),
                      backgroundColor: AppTheme.primaryGreen,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menyetujui: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Setujui'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  // TOLAK: set approval_lepas_status = NULL
                  await _supabase.from('slot_khataman').update({
                    'approval_lepas_status': null,
                  }).eq('id_slot', slot['id_slot']);
                  _fetchData(silent: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Pengajuan lepas Juz $juzNo ditolak.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menolak: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Tolak'),
            ),
          ],
        ),
      );
      return;
    }

    // 1. Logika Proteksi Juz yang Sudah Dicicil (Progres > 0%)
    final lastAyat = slot['ayat_terakhir_input'] as int? ?? 0;
    final statusChecklist = slot['status_checklist'] == true;

    Future<void> proceedWithChange() async {
      final String? previousUserId = slot['user_id'];

      // Determine new user info
      String? newUserId;
      Map<String, dynamic>? newUsers;

      if (_selectedBrushUserId == 'eraser') {
        newUserId = null;
        newUsers = null;
      } else {
        final member = _members.firstWhere(
          (m) => m['user_id'] == _selectedBrushUserId,
          orElse: () => {},
        );
        if (member.isNotEmpty) {
          newUserId = _selectedBrushUserId;
          newUsers = member['users'];
        }
      }

      // Do nothing if same state
      if (previousUserId == newUserId) return;

      // 2. Rumus Dinamis Rentang Kuota (Pengecekan Saklar Kuota Maksimal)
      if (_limitJuz && newUserId != null) {
        final memberCount = _members.isEmpty ? 1 : _members.length;
        final batasMaksimal = (30 / memberCount).ceil();
        final currentCount = _slots.where((s) => s['user_id'] == newUserId).length;

        if (currentCount >= batasMaksimal) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal! Anggota ini sudah mencapai batas maksimal pembagian rata ($batasMaksimal Juz).'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      // 3. Logika Pop-up Peringatan Untuk Juz Yang Belum Dibaca (Progres = 0%)
      if (previousUserId != null) {
        showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: const Text(
              'Pindahkan Pembagian Juz?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Juz ini sudah ditugaskan tetapi BELUM mulai dibaca. Apakah Anda yakin ingin memindahkannya?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Tidak'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Ya, Pindahkan'),
              ),
            ],
          ),
        ).then((confirmed) {
          if (confirmed == true) {
            _applySlotChange(slot, newUserId, newUsers);
          }
        });
      } else {
        _applySlotChange(slot, newUserId, newUsers);
      }
    }

    if (lastAyat > 0 || statusChecklist) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 8),
              Text(
                'Juz Sudah Dibaca!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          content: Text(
            'Juz ${slot['nomor_juz']} ini sudah memiliki progres membaca. Apakah Anda yakin ingin memaksa mengubah pembagian atau menghapus progresnya? Tindakan ini akan mereset progres pembacaan juz tersebut.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Ya, Paksa Ubah'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true && mounted) {
          proceedWithChange();
        }
      });
      return;
    }

    proceedWithChange();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Aesthetic Color Palette
    final scaffoldBg = isDark ? const Color(0xFF0F141C) : const Color(0xFFF4F7F5);
    final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1A2B20);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF5F6E65);
    final dividerColor = isDark ? Colors.white10 : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pembagian Juz',
              style: TextStyle(
                color: primaryTextColor,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.groupName,
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: cardBg,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryTextColor),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: dividerColor,
            height: 1.0,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── SECTION 1: DAFTAR ANGGOTA (BAGIAN ATAS) ──
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '🎨 Kuas Anggota',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Row(
                              children: [
                                if (_selectedBrushUserId != 'eraser') ...[
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedBrushUserId = 'eraser';
                                      });
                                    },
                                    child: Text(
                                      'Batal Pilih',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                ],
                                GestureDetector(
                                  onTap: _clearAllSlots,
                                  child: const Text(
                                    'Bersihkan Semua',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 78,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _members.length + 1, // +1 for the Eraser Brush
                          itemBuilder: (ctx, index) {
                            // First item is the Eraser
                            if (index == 0) {
                              final isSelected = _selectedBrushUserId == 'eraser';
                              const activeBlue = Color(0xFF339AF0); // Vibrant sky blue
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedBrushUserId = 'eraser';
                                    });
                                  },
                                  child: Column(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: isSelected 
                                              ? activeBlue.withOpacity(0.12)
                                              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isSelected
                                                ? activeBlue
                                                : (isDark ? Colors.white12 : Colors.grey.shade300),
                                            width: isSelected ? 2.5 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: activeBlue.withOpacity(0.4),
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.delete_rounded,
                                            size: 22,
                                            color: isSelected
                                                ? activeBlue
                                                : (isDark ? Colors.white60 : Colors.grey.shade600),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      const Text(
                                        'Hapus',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            // Members
                            final memberIndex = index - 1;
                            final member = _members[memberIndex];
                            final userId = member['user_id'] as String;
                            final user = member['users'] as Map<String, dynamic>? ?? {};
                            final username = user['username'] as String? ?? 'Umum';
                            final initials = _uniqueInitials[userId] ?? _getInitials(username);
                            final pastelBg = _memberColors[userId] ?? _getPastelColor(username);
                            final isSelected = _selectedBrushUserId == userId;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedBrushUserId == userId) {
                                      _selectedBrushUserId = 'eraser';
                                    } else {
                                      _selectedBrushUserId = userId;
                                    }
                                  });
                                },
                                child: Column(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: pastelBg,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? (isDark ? AppTheme.accentTeal : AppTheme.primaryGreen)
                                              : Colors.transparent,
                                          width: isSelected ? 3.0 : 0,
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: (isDark ? AppTheme.accentTeal : AppTheme.primaryGreen).withOpacity(0.4),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                )
                                              ]
                                            : [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.04),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                )
                                              ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          initials,
                                          style: const TextStyle(
                                            color: Color(0xFF1C2D21), // Dark forest text for high contrast on pastel
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    SizedBox(
                                      width: 54,
                                      child: Text(
                                        '@$username',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected 
                                              ? (isDark ? AppTheme.accentTeal : AppTheme.primaryGreen)
                                              : primaryTextColor,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: dividerColor,
                  height: 1.0,
                ),

                // Instruction Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFF131A26) : const Color(0xFFEBF2EE),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final memberCount = _members.isEmpty ? 1 : _members.length;
                            final batasMinimal = (30 / memberCount).floor();
                            final batasMaksimal = (30 / memberCount).ceil();

                            String text = _selectedBrushUserId == 'eraser'
                                ? 'Kuas Hapus aktif! Ketuk kotak Juz untuk mengosongkan pembagian.'
                                : 'Kuas aktif! Ketuk kotak Juz untuk membagi langsung.';

                            if (_limitJuz) {
                              if (batasMinimal == batasMaksimal) {
                                text += '\n🔒 Fitur Batasi Aktif: Setiap anggota memegang $batasMinimal Juz.';
                              } else {
                                text += '\n🔒 Fitur Batasi Aktif: Setiap anggota memegang antara $batasMinimal sampai $batasMaksimal Juz.';
                              }
                            }

                            return Text(
                              text,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                              ),
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                ),

                // ── SECTION 2: KOTAK GRID JUZ 6 - JUZ 30 (BAGIAN BAWAH) ──
                Expanded(
                  child: _activeCycle == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.hourglass_empty_rounded,
                                size: 48,
                                color: secondaryTextColor.withOpacity(0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Tidak ada siklus aktif',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Mulai putaran siklus baru terlebih dahulu.',
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.0, // Fixed 1:1 ratio for perfect squares
                          ),
                          itemCount: 30, // Juz 1 to Juz 30
                          itemBuilder: (ctx, index) {
                            final juzNumber = index + 1;
                            
                            // Find the slot for this Juz number
                            final slot = _slots.firstWhere(
                              (s) => s['nomor_juz'] == juzNumber,
                              orElse: () => {},
                            );

                            if (slot.isEmpty) {
                              // Slot doesn't exist yet for this Juz in active cycle
                              return Container(
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '$juzNumber',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: secondaryTextColor.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              );
                            }

                             final String? claimedUserId = slot['user_id'];
                             final claimedUser = slot['users'] as Map<String, dynamic>? ?? {};
                             final claimedUsername = claimedUser['username'] as String?;
                             
                             final hasClaim = claimedUserId != null;
                             final claimerColor = hasClaim ? (_memberColors[claimedUserId] ?? _getPastelColor(claimedUsername ?? '')) : Colors.transparent;
                             final claimerInitials = hasClaim ? (_uniqueInitials[claimedUserId] ?? _getInitials(claimedUsername)) : '';

                             final bool isPending = slot['approval_lepas_status'] == 'PENDING';

                            return GestureDetector(
                              onTap: () => _handleJuzTap(slot),
                              child: AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (ctx, child) {
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: hasClaim 
                                          ? (isPending 
                                              ? Colors.amber.withOpacity(isDark ? 0.08 : 0.15)
                                              : claimerColor.withOpacity(isDark ? 0.12 : 0.20))
                                          : cardBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isPending
                                            ? Colors.amber.withOpacity(_pulseAnimation.value)
                                            : (hasClaim
                                                ? claimerColor.withOpacity(isDark ? 0.4 : 0.6)
                                                : (isDark ? Colors.white10 : Colors.grey.shade300)),
                                        width: isPending ? 3.0 : (hasClaim ? 1.5 : 1),
                                      ),
                                      boxShadow: isPending
                                          ? [
                                              BoxShadow(
                                                color: Colors.amber.withOpacity(0.3 * _pulseAnimation.value),
                                                blurRadius: 6,
                                                spreadRadius: 1,
                                              )
                                            ]
                                          : (hasClaim
                                              ? null
                                              : [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.02),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  )
                                                ]),
                                    ),
                                    child: child,
                                  );
                                },
                                child: Stack(
                                  children: [
                                    // Juz Number Centered
                                    Center(
                                      child: Text(
                                        '$juzNumber',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: hasClaim
                                              ? (isDark ? Colors.white : Colors.grey.shade800)
                                              : primaryTextColor,
                                        ),
                                      ),
                                    ),

                                    // Lock Icon in Top-Right if slot has progress > 0%
                                    if (hasClaim && ((slot['ayat_terakhir_input'] as int? ?? 0) > 0 || slot['status_checklist'] == true))
                                      Positioned(
                                        top: 5,
                                        right: 5,
                                        child: Icon(
                                          Icons.lock_rounded,
                                          size: 11,
                                          color: isDark 
                                              ? Colors.white.withOpacity(0.4) 
                                              : Colors.black.withOpacity(0.35),
                                        ),
                                      ),

                                    // Pending Icon in Top-Left if slot is awaiting release approval
                                    if (isPending)
                                      Positioned(
                                        top: 5,
                                        left: 5,
                                        child: Icon(
                                          Icons.hourglass_empty_rounded,
                                          size: 11,
                                          color: Colors.amber.shade700,
                                        ),
                                      ),

                                    // Claimer Initials Badge in Bottom-Right
                                    if (hasClaim)
                                      Positioned(
                                        bottom: 4,
                                        right: 4,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: claimerColor,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.1),
                                                blurRadius: 2,
                                                spreadRadius: 0.5,
                                              )
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              claimerInitials,
                                              style: const TextStyle(
                                                color: Color(0xFF1C2D21), // Forest dark color for contrast
                                                fontSize: 8,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _isLoading || _activeCycle == null
          ? null
          : Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(
                  top: BorderSide(color: dividerColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isSaving ? null : _cancelDraftChanges,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.redAccent.withOpacity(0.8),
                      ),
                      child: const Text(
                        'Batalkan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveDraftChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Simpan Pembagian',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
