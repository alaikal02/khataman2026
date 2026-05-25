import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/personal_history_service.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _history = [];
  int _khatamCount = 0;
  bool _isCurrentMandiriKhatam = false;
  bool _isLoading = true;

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

    // 1. Ambil riwayat membaca mandiri (lokal) & jumlah khatam lokal
    final historyList = await PersonalHistoryService.getHistory(userId);
    final localMandiriKhatams = await PersonalHistoryService.getKhatamCount(userId);

    // 2. Ambil putaran siklus grup selesai yang diikuti oleh user dari Supabase
    List<Map<String, dynamic>> fetchedGroupKhatamLogs = [];
    
    try {
      final completedGroupSlots = await _supabase
          .from('slot_khataman')
          .select('putaran_id, nomor_juz, putaran_siklus!inner(id_putaran, group_id, nomor_putaran, start_date, target_deadline, status_aktif_selesai, groups(nama_grup))')
          .eq('user_id', userId)
          .eq('putaran_siklus.status_aktif_selesai', 'SELESAI');

      final slotsList = completedGroupSlots as List;
      if (slotsList.isNotEmpty) {
        
        // Kelompokkan slot berdasarkan putaran_id untuk menghitung putaran unik
        final Map<dynamic, List<dynamic>> cyclesMap = {};
        for (var slot in slotsList) {
          final pId = slot['putaran_id'];
          if (pId != null) {
            cyclesMap.putIfAbsent(pId, () => []).add(slot);
          }
        }
        

        // Buat entri log riwayat untuk khataman grup yang selesai
        for (var pId in cyclesMap.keys) {
          final slots = cyclesMap[pId]!;
          final firstSlot = slots.first;
          final putaran = firstSlot['putaran_siklus'];
          final groupName = putaran['groups']?['nama_grup'] ?? 'Grup';
          final completionDate = putaran['target_deadline'] ?? putaran['start_date'] ?? DateTime.now().toIso8601String();
          final juzs = slots.map((s) => s['nomor_juz']).toList()..sort();

          fetchedGroupKhatamLogs.add({
            'timestamp': completionDate,
            'juz': juzs.join(', '),
            'description': '🏆 Menyelesaikan Khataman Grup bersama "$groupName"! Anda berkontribusi membaca Juz ${juzs.join(', ')}.',
            'type': 'Grup: $groupName',
            'isJuzCompletion': true,
            'isKhatamCompletion': true,
            'isGroupKhatam': true,
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading group khatams: $e');
    }

    // 3. Periksa apakah ronde mandiri saat ini sudah 30 Juz selesai (tetapi belum di-reset)
    bool isCurrentMandiriKhatam = false;
    try {
      final activeMandiriRes = await _supabase
          .from('khataman_mandiri')
          .select('selesai')
          .eq('user_id', userId)
          .eq('selesai', true);
      
      final activeCompletedList = activeMandiriRes as List;
      if (activeCompletedList.isNotEmpty) {
        isCurrentMandiriKhatam = activeCompletedList.length == 30;
      }
    } catch (e) {
      debugPrint('Error loading active mandiri status: $e');
    }

    // Gabungkan riwayat lokal & riwayat grup khatam, lalu urutkan kronologis (terbaru di atas)
    final combinedHistory = [...historyList, ...fetchedGroupKhatamLogs];
    combinedHistory.sort((a, b) {
      final tA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.now();
      final tB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.now();
      return tB.compareTo(tA);
    });

    // Menghitung total khatam mandiri
    final displayKhatamCount = localMandiriKhatams + (isCurrentMandiriKhatam ? 1 : 0);

    if (mounted) {
      setState(() {
        _history = combinedHistory;
        _isCurrentMandiriKhatam = isCurrentMandiriKhatam;
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
            offset: const Offset(-210, -78),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 220,
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
                  'Jumlah total dari penyelesaian Khataman Mandiri 30 Juz Anda.',
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

  // Menghitung berapa kali khatam 30 Juz dalam rentang waktu tertentu (Mandiri)
  int _getKhatamStatsCount({required int daysRange}) {
    final now = DateTime.now();
    final limit = now.subtract(Duration(days: daysRange));
    int count = 0;
    
    // 1. Khatam Mandiri yang tercatat di riwayat gabungan
    for (var item in _history) {
      if (item['isKhatamCompletion'] == true && item['isGroupKhatam'] != true) {
        final date = DateTime.tryParse(item['timestamp'] ?? '');
        if (date != null && date.isAfter(limit)) {
          count++;
        }
      }
    }

    // 2. Khatam Mandiri Aktif saat ini yang belum di-reset
    if (_isCurrentMandiriKhatam) {
      count++;
    }
    
    return count;
  }

  // Menghitung berapa Juz yang terselesaikan (bukan khatam penuh 30 juz)
  int _getJuzCompletedCount({required int daysRange}) {
    final now = DateTime.now();
    final limit = now.subtract(Duration(days: daysRange));
    int count = 0;

    for (var item in _history) {
      if (item['isJuzCompletion'] == true && item['isKhatamCompletion'] != true) {
        final date = DateTime.tryParse(item['timestamp'] ?? '');
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
          if (_history.isNotEmpty)
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
                      if (_history.isNotEmpty)
                        Text(
                          '${_history.length} Catatan',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Daftar riwayat
                  if (_history.isEmpty)
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
                      itemCount: _history.length,
                      itemBuilder: (context, idx) {
                        final log = _history[idx];
                        final isJuzComplete = log['isJuzCompletion'] == true;
                        final isKhatam = log['isKhatamCompletion'] == true;
                        final type = log['type'] ?? 'Mandiri';
                        final isGroup = type.toString().startsWith('Grup');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isKhatam
                                  ? AppTheme.accentGold.withOpacity(0.4)
                                  : Theme.of(context).dividerColor.withOpacity(0.5),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon container
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isKhatam
                                      ? AppTheme.accentGold.withOpacity(0.15)
                                      : isJuzComplete
                                          ? AppTheme.primaryGreen.withOpacity(0.15)
                                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isKhatam
                                      ? Icons.emoji_events_rounded
                                      : isJuzComplete
                                          ? Icons.check_circle_rounded
                                          : Icons.chrome_reader_mode_rounded,
                                  color: isKhatam
                                      ? AppTheme.accentGold
                                      : isJuzComplete
                                          ? AppTheme.primaryGreen
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Rincian log
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDisplayTime(log['timestamp'] ?? ''),
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                          ),
                                        ),
                                        // Badge Sumber
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isGroup
                                                ? const Color(0xFF6C63FF).withOpacity(0.12)
                                                : AppTheme.primaryGreen.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            type,
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
                                    const SizedBox(height: 6),
                                    Text(
                                      log['isGroupKhatam'] == true ? 'Khatam 30 Juz' : 'Juz ${log['juz']}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      log['description'] ?? '',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
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
