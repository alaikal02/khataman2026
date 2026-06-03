import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/personal_history_service.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _cycles = [];
  int _khatamCount = 0;
  bool _isLoading = true;
  final Set<int> _expandedIndices = {};

  OverlayEntry? _infoOverlayEntry;
  final LayerLink _infoLayerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Ambil riwayat membaca mandiri (lokal)
    final historyList = await PersonalHistoryService.getHistory(userId);

    // 2. Kelompokkan log mandiri menjadi siklus khataman berdasarkan isKhatamCompletion
    final sortedLocal = List<Map<String, dynamic>>.from(historyList)
      ..sort((a, b) {
        final tA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.utc(1970);
        final tB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.utc(1970);
        return tA.compareTo(tB);
      });

    final mandiriCycles = <Map<String, dynamic>>[];
    var currentJuzs = <Map<String, dynamic>>[];

    for (var log in sortedLocal) {
      if (log['type'] != 'Mandiri') continue;
      if (log['isKhatamCompletion'] == true) {
        if (log['isJuzCompletion'] == true) {
          currentJuzs.add(log);
        }
        // Deduplikasi: hanya simpan 1 entri per juz dalam siklus ini
        final deduped = <int, Map<String, dynamic>>{};
        for (var j in currentJuzs) {
          final jNum = int.tryParse(j['juz']?.toString() ?? '0') ?? 0;
          if (jNum > 0) deduped[jNum] = j;
        }
        final juzList = deduped.values.toList()
          ..sort((a, b) => (int.tryParse(a['juz']?.toString() ?? '0') ?? 0)
              .compareTo(int.tryParse(b['juz']?.toString() ?? '0') ?? 0));
        mandiriCycles.add({
          'title': 'Khataman Mandiri',
          'type': 'Mandiri',
          'timestamp': log['timestamp'] ?? DateTime.now().toIso8601String(),
          'description': log['description'] ?? '🏆 Khataman Mandiri 30 Juz!',
          'juzDetails': juzList,
        });
        currentJuzs.clear();
      } else if (log['isJuzCompletion'] == true) {
        currentJuzs.add(log);
      }
    }

    // 3. Ambil siklus grup yang diarsipkan
    final groupCycles = <Map<String, dynamic>>[];
    try {
      final completedGroupSlots = await _supabase
          .from('slot_khataman')
          .select('putaran_id, nomor_juz, updated_at, putaran_siklus!inner(id_putaran, group_id, nomor_putaran, start_date, target_deadline, status_aktif_selesai, groups(nama_grup, visibility))')
          .eq('user_id', userId)
          .eq('putaran_siklus.status_aktif_selesai', 'SELESAI');

      final slotsList = List<Map<String, dynamic>>.from(completedGroupSlots as List);
      // Filter hanya grup yang sudah diarsipkan di DB atau ditandai selesai/arsip lokal
      final prefs = await SharedPreferences.getInstance();
      final archivedSlots = slotsList.where((s) {
        final p = s['putaran_siklus'] as Map<String, dynamic>?;
        final g = p?['groups'] as Map<String, dynamic>?;
        final pId = s['putaran_id'];
        
        final localArchived = prefs.getBool('archived_group_${p?['group_id']}_$pId') ?? false;
        return g?['visibility'] == 'ARCHIVED' || localArchived;
      }).toList();

      final cyclesMap = <dynamic, List<Map<String, dynamic>>>{};
      for (var slot in archivedSlots) {
        final pId = slot['putaran_id'];
        if (pId != null) cyclesMap.putIfAbsent(pId, () => []).add(slot);
      }

      for (var pId in cyclesMap.keys) {
        final slots = cyclesMap[pId]!;
        final firstSlot = slots.first;
        final putaran = firstSlot['putaran_siklus'] as Map<String, dynamic>;
        final groupName = (putaran['groups'] as Map<String, dynamic>?)?['nama_grup'] ?? 'Grup';
        final completionDate = putaran['target_deadline'] ?? putaran['start_date'] ?? DateTime.now().toIso8601String();
        slots.sort((a, b) => ((a['nomor_juz'] as int?) ?? 0).compareTo((b['nomor_juz'] as int?) ?? 0));

        final juzDetails = slots.map((s) => <String, dynamic>{
          'juz': s['nomor_juz'],
          'timestamp': s['updated_at'] ?? completionDate,
        }).toList();

        groupCycles.add({
          'title': 'Khataman Grup "$groupName"',
          'type': 'Grup: $groupName',
          'timestamp': completionDate,
          'description': '🏆 Khataman Grup bersama "$groupName"! Kontribusi ${juzDetails.length} Juz.',
          'juzDetails': juzDetails,
        });
      }
    } catch (e) {
      debugPrint('Error loading group khatams: $e');
    }

    // 4. Gabungkan & urutkan siklus (terbaru di atas)
    final combined = [...mandiriCycles, ...groupCycles];
    combined.sort((a, b) {
      final tA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.now();
      final tB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.now();
      return tB.compareTo(tA);
    });

    final localMandiriKhatams = await PersonalHistoryService.getKhatamCount(userId);
    final displayKhatamCount = localMandiriKhatams + groupCycles.length;

    if (mounted) {
      setState(() {
        _cycles = combined;
        _khatamCount = displayKhatamCount;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _dismissInfoOverlay();
    super.dispose();
  }

  void _toggleInfoOverlay() {
    if (_infoOverlayEntry != null) {
      _dismissInfoOverlay();
      return;
    }

    final overlay = Overlay.of(context);
    
    _infoOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Invisible detector to dismiss overlay when tapping anywhere else
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissInfoOverlay,
              child: const SizedBox(),
            ),
          ),
          // Chat bubble
          CompositedTransformFollower(
            link: _infoLayerLink,
            showWhenUnlinked: false,
            // Offset to place the bubble right above and centered leftwards of the target icon
            offset: const Offset(-230, -92),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 240,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Sleek, premium dark slate bubble matching premium dark themes
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                ),
                child: const Text(
                  'Jumlah total penyelesaian Khataman Al-Quran Anda, gabungan dari Khataman Mandiri dan kontribusi Khataman Grup.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_infoOverlayEntry!);
  }

  void _dismissInfoOverlay() {
    _infoOverlayEntry?.remove();
    _infoOverlayEntry = null;
  }

  Future<void> _confirmClearHistory() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Hapus Seluruh Riwayat?', style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          'Semua catatan aktivitas membaca dan statistik khatam personal Anda akan dihapus secara permanen.\n\nTindakan ini tidak dapat dibatalkan.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Ya, Hapus Semua'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PersonalHistoryService.clearHistory(userId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seluruh riwayat personal Anda telah dibersihkan.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  // Menghitung berapa kali khatam 30 Juz dalam rentang waktu tertentu
  int _getKhatamStatsCount({required int daysRange}) {
    final now = DateTime.now();
    final limit = now.subtract(Duration(days: daysRange));
    int count = 0;
    for (var cycle in _cycles) {
      final date = DateTime.tryParse(cycle['timestamp'] ?? '');
      if (date != null && date.isAfter(limit)) {
        count++;
      }
    }
    return count;
  }

  // Menghitung berapa Juz yang terselesaikan
  int _getJuzCompletedCount({required int daysRange}) {
    final now = DateTime.now();
    final limit = now.subtract(Duration(days: daysRange));
    int count = 0;
    for (var cycle in _cycles) {
      final juzDetails = cycle['juzDetails'] as List? ?? [];
      for (var juzLog in juzDetails) {
        final date = DateTime.tryParse(juzLog['timestamp'] ?? '');
        if (date != null && date.isAfter(limit)) {
          count++;
        }
      }
    }
    return count;
  }

  String _formatDisplayTime(String timestampStr) {
    try {
      final dt = DateTime.parse(timestampStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return 'Baru saja';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes} menit yang lalu';
      } else if (diff.inHours < 24) {
        return '${diff.inHours} jam yang lalu';
      } else if (diff.inDays == 1) {
        return 'Kemarin, ${_pad(dt.hour)}:${_pad(dt.minute)}';
      } else {
        return '${dt.day}/${dt.month}/${dt.year} - ${_pad(dt.hour)}:${_pad(dt.minute)}';
      }
    } catch (_) {
      return '';
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    // Menghitung statistik khatam 30 Juz
    final weekKhatamCount = _getKhatamStatsCount(daysRange: 7);
    final monthKhatamCount = _getKhatamStatsCount(daysRange: 30);
    final yearKhatamCount = _getKhatamStatsCount(daysRange: 365);

    // Menghitung statistik juz selesai
    final weekJuzCompleted = _getJuzCompletedCount(daysRange: 7);
    final monthJuzCompleted = _getJuzCompletedCount(daysRange: 30);
    final yearJuzCompleted = _getJuzCompletedCount(daysRange: 365);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Riwayat & Statistik Saya'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_cycles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Hapus Semua Riwayat',
              onPressed: _confirmClearHistory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : RefreshIndicator(
              color: AppTheme.primaryGreen,
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // Gold Gradient Lifetime Trophy Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3C72), Color(0xFF2A5298), Color(0xFF1A2A6C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2A5298).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.accentGold.withOpacity(0.4), width: 1.5),
                              ),
                              child: const Icon(Icons.emoji_events_rounded, color: AppTheme.accentGold, size: 42),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL KHATAM AL-QURAN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text(
                                        '$_khatamCount Kali',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Pojok kanan bawah tombol tanda seru info
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CompositedTransformTarget(
                            link: _infoLayerLink,
                            child: GestureDetector(
                              onTap: _toggleInfoOverlay,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Interactive Reading Statistics Title
                  Text(
                    'Statistik Membaca Saya',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tiga panel statistik periodik berdampingan
                  Row(
                    children: [
                      Expanded(
                        child: _buildPeriodStatCard(
                          context: context,
                          title: 'Minggu Ini',
                          khatamCount: weekKhatamCount,
                          juzCount: weekJuzCompleted,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPeriodStatCard(
                          context: context,
                          title: 'Bulan Ini',
                          khatamCount: monthKhatamCount,
                          juzCount: monthJuzCompleted,
                          color: AppTheme.accentGold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPeriodStatCard(
                          context: context,
                          title: 'Tahun Ini',
                          khatamCount: yearKhatamCount,
                          juzCount: yearJuzCompleted,
                          color: AppTheme.accentTeal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Judul daftar log
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Catatan Riwayat Aktivitas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (_cycles.isNotEmpty)
                        Text(
                          '${_cycles.length} Khataman',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Daftar riwayat
                  if (_cycles.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.auto_stories_outlined,
                              size: 56,
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Mulai Membaca Al-Quran',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Simpan progres membaca Anda di Khataman Mandiri atau Khataman Grup untuk melihat histori membaca Anda di sini.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cycles.length,
                      itemBuilder: (context, idx) {
                        final cycle = _cycles[idx];
                        final isExpanded = _expandedIndices.contains(idx);
                        final title = cycle['title'] ?? 'Khataman';
                        final timestamp = cycle['timestamp'] ?? '';
                        final description = cycle['description'] ?? '';
                        final type = cycle['type'] ?? 'Mandiri';
                        final juzDetails = cycle['juzDetails'] as List? ?? [];
                        final isGroup = type.toString().startsWith('Grup');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.accentGold.withOpacity(0.35),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: PageStorageKey<int>(idx),
                              initiallyExpanded: isExpanded,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  if (expanded) {
                                    _expandedIndices.add(idx);
                                  } else {
                                    _expandedIndices.remove(idx);
                                  }
                                });
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentGold.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.emoji_events_rounded,
                                  color: AppTheme.accentGold,
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isGroup
                                          ? const Color(0xFF6C63FF).withOpacity(0.12)
                                          : AppTheme.primaryGreen.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isGroup ? 'Grup' : 'Mandiri',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: isGroup
                                            ? const Color(0xFF6C63FF)
                                            : AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _formatDisplayTime(timestamp),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                  ),
                                ),
                              ),
                              trailing: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Divider(height: 1),
                                      const SizedBox(height: 12),
                                      Text(
                                        description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Rincian Juz yang Dibaca:',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (juzDetails.isEmpty)
                                        Text(
                                          'Tidak ada detail juz terekam.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: juzDetails.map((j) {
                                            final juzNum = j['juz'];
                                            final timeStr = _formatDisplayTime(j['timestamp'] ?? '');
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryGreen.withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Juz $juzNum',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.primaryGreen,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '($timeStr)',
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodStatCard({
    required BuildContext context,
    required String title,
    required int khatamCount,
    required int juzCount,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$khatamCount Kali',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Text(
            'Khatam 30 Juz',
            style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 10, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$juzCount Juz',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const Text(
            'Juz Selesai',
            style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
