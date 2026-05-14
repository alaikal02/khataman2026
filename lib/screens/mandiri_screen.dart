import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class MandiriScreen extends StatefulWidget {
  const MandiriScreen({Key? key}) : super(key: key);

  @override
  State<MandiriScreen> createState() => _MandiriScreenState();
}

class _MandiriScreenState extends State<MandiriScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _progress = [];
  bool _isLoading = true;
  int? _expandedIndex;

  // Static data Juz - Nama Surah awal setiap Juz
  static const List<Map<String, dynamic>> _juzInfo = [
    {'juz': 1, 'surah_awal': 'Al-Fatihah', 'surah_akhir': 'Al-Baqarah 141', 'total': 148},
    {'juz': 2, 'surah_awal': 'Al-Baqarah 142', 'surah_akhir': 'Al-Baqarah 252', 'total': 111},
    {'juz': 3, 'surah_awal': 'Al-Baqarah 253', 'surah_akhir': 'Ali Imran 92', 'total': 126},
    {'juz': 4, 'surah_awal': 'Ali Imran 93', 'surah_akhir': 'An-Nisa 23', 'total': 131},
    {'juz': 5, 'surah_awal': 'An-Nisa 24', 'surah_akhir': 'An-Nisa 147', 'total': 124},
    {'juz': 6, 'surah_awal': 'An-Nisa 148', 'surah_akhir': 'Al-Ma\'idah 81', 'total': 110},
    {'juz': 7, 'surah_awal': 'Al-Ma\'idah 82', 'surah_akhir': 'Al-An\'am 110', 'total': 149},
    {'juz': 8, 'surah_awal': 'Al-An\'am 111', 'surah_akhir': 'Al-A\'raf 87', 'total': 142},
    {'juz': 9, 'surah_awal': 'Al-A\'raf 88', 'surah_akhir': 'Al-Anfal 40', 'total': 159},
    {'juz': 10, 'surah_awal': 'Al-Anfal 41', 'surah_akhir': 'At-Taubah 92', 'total': 127},
    {'juz': 11, 'surah_awal': 'At-Taubah 93', 'surah_akhir': 'Hud 5', 'total': 151},
    {'juz': 12, 'surah_awal': 'Hud 6', 'surah_akhir': 'Yusuf 52', 'total': 170},
    {'juz': 13, 'surah_awal': 'Yusuf 53', 'surah_akhir': 'Ibrahim 52', 'total': 154},
    {'juz': 14, 'surah_awal': 'Al-Hijr', 'surah_akhir': 'An-Nahl 128', 'total': 227},
    {'juz': 15, 'surah_awal': 'Al-Isra\'', 'surah_akhir': 'Al-Kahfi 74', 'total': 185},
    {'juz': 16, 'surah_awal': 'Al-Kahfi 75', 'surah_akhir': 'Ta Ha 135', 'total': 269},
    {'juz': 17, 'surah_awal': 'Al-Anbiya\'', 'surah_akhir': 'Al-Hajj 78', 'total': 190},
    {'juz': 18, 'surah_awal': 'Al-Mu\'minun', 'surah_akhir': 'Al-Furqan 20', 'total': 202},
    {'juz': 19, 'surah_awal': 'Al-Furqan 21', 'surah_akhir': 'An-Naml 55', 'total': 339},
    {'juz': 20, 'surah_awal': 'An-Naml 56', 'surah_akhir': 'Al-Ankabut 45', 'total': 171},
    {'juz': 21, 'surah_awal': 'Al-Ankabut 46', 'surah_akhir': 'Al-Ahzab 30', 'total': 178},
    {'juz': 22, 'surah_awal': 'Al-Ahzab 31', 'surah_akhir': 'Ya Sin 27', 'total': 169},
    {'juz': 23, 'surah_awal': 'Ya Sin 28', 'surah_akhir': 'Az-Zumar 31', 'total': 357},
    {'juz': 24, 'surah_awal': 'Az-Zumar 32', 'surah_akhir': 'Fussilat 46', 'total': 175},
    {'juz': 25, 'surah_awal': 'Fussilat 47', 'surah_akhir': 'Al-Jatsiyah 37', 'total': 246},
    {'juz': 26, 'surah_awal': 'Al-Ahqaf', 'surah_akhir': 'Adz-Dzariyat 30', 'total': 195},
    {'juz': 27, 'surah_awal': 'Adz-Dzariyat 31', 'surah_akhir': 'Al-Hadid 29', 'total': 399},
    {'juz': 28, 'surah_awal': 'Al-Mujadilah', 'surah_akhir': 'At-Tahrim 12', 'total': 137},
    {'juz': 29, 'surah_awal': 'Al-Mulk', 'surah_akhir': 'Al-Mursalat 50', 'total': 431},
    {'juz': 30, 'surah_awal': 'An-Naba\'', 'surah_akhir': 'An-Nas', 'total': 564},
  ];

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from('khataman_mandiri')
          .select()
          .eq('user_id', userId)
          .order('nomor_juz');

      setState(() {
        _progress = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      // Table might not exist yet, create fresh state
      setState(() {
        _progress = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProgress(int juzNumber, int ayat, int total) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Validasi TC-02
    if (ayat > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nomor ayat melebihi batas maksimal (Max: $total)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final isComplete = ayat == total;

    try {
      await _supabase.from('khataman_mandiri').upsert({
        'user_id': userId,
        'nomor_juz': juzNumber,
        'ayat_terakhir': ayat,
        'selesai': isComplete,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,nomor_juz');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isComplete ? '✅ Juz $juzNumber selesai! Alhamdulillah!' : 'Progres Juz $juzNumber disimpan'),
          backgroundColor: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
      if (isComplete) setState(() => _expandedIndex = null);
      await _loadProgress();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Map<String, dynamic>? _getProgressForJuz(int juzNumber) {
    try {
      return _progress.firstWhere((p) => p['nomor_juz'] == juzNumber);
    } catch (_) {
      return null;
    }
  }

  int _completedCount() => _progress.where((p) => p['selesai'] == true).length;

  Future<void> _resetAllProgress() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Tampilkan dialog konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Reset Khataman?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Semua progres khataman mandiri Anda akan dihapus dan dimulai dari awal.\n\nApakah Anda yakin?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('Ya, Reset Semua'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('khataman_mandiri')
          .delete()
          .eq('user_id', userId);

      setState(() {
        _progress = [];
        _expandedIndex = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Progres berhasil direset. Bismillah, mulai lagi! 🌙'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal reset: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completedCount();
    final totalPercent = (completed / 30 * 100).round();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Khataman Mandiri'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.restart_alt_rounded, color: Colors.redAccent),
            tooltip: 'Reset Semua Progres',
            onPressed: _resetAllProgress,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : Column(
              children: [
                // Summary Card
                _buildSummaryCard(completed, totalPercent),
                // Juz List
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: 30,
                    itemBuilder: (context, index) {
                      final juz = _juzInfo[index];
                      final progress = _getProgressForJuz(index + 1);
                      return _buildJuzCard(context, juz, progress, index);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(int completed, int totalPercent) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A3A2A), Color(0xFF0D2118)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progres Khataman', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                  SizedBox(height: 4),
                  Text(
                    '$completed / 30 Juz',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ],
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryGreen, width: 3),
                ),
                child: Center(
                  child: Text(
                    '$totalPercent%',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: completed / 30,
              minHeight: 10,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJuzCard(BuildContext context, Map<String, dynamic> juz, Map<String, dynamic>? progress, int index) {
    final juzNumber = juz['juz'] as int;
    final total = juz['total'] as int;
    final isExpanded = _expandedIndex == index;
    final isComplete = progress?['selesai'] == true;
    final lastAyat = progress?['ayat_terakhir'] as int? ?? 0;
    final percentage = (lastAyat / total * 100).round();
    final TextEditingController controller = TextEditingController(text: lastAyat > 0 ? lastAyat.toString() : '');

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppTheme.primaryGreen.withOpacity(0.5)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        children: [
          // Collapsed Header
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expandedIndex = isExpanded ? null : index),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  // Juz Number Badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isComplete
                          ? AppTheme.primaryGreen.withOpacity(0.2)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: isComplete
                          ? Icon(Icons.check_rounded, color: AppTheme.primaryGreen, size: 22)
                          : Text(
                              '$juzNumber',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: 14),
                  // Juz Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Juz $juzNumber',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        SizedBox(height: 4),
                        Text(
                          juz['surah_awal'],
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: isComplete ? 1.0 : (lastAyat / total),
                            minHeight: 5,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isComplete ? AppTheme.primaryGreen : AppTheme.accentTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  // Percentage + Arrow
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isComplete ? '100%' : '$percentage%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 4),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Expanded Content
          if (isExpanded)
            Container(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  SizedBox(height: 14),
                  Text(
                    '${juz['surah_awal']} — ${juz['surah_akhir']}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Total ayat dalam juz ini: $total',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  SizedBox(height: 14),
                  Text('Ayat terakhir yang dibaca:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                  SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Masukkan nomor ayat (1 - $total)',
                      suffixText: '/ $total',
                      suffixStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '${isComplete ? 100 : percentage}% / 100%',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final input = int.tryParse(controller.text);
                        if (input == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Input harus berupa angka'), backgroundColor: Colors.redAccent),
                          );
                          return;
                        }
                        _saveProgress(juzNumber, input, total);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Simpan Progres', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}