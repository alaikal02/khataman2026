import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../components/mandiri_juz_card.dart';
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
                      final juzNumber = index + 1;
                      final progress = _getProgressForJuz(juzNumber);
                      return MandiriJuzCard(
                        key: ValueKey('mandiri_juz_$juzNumber'),
                        juzNumber: juzNumber,
                        lastAyat: progress?['ayat_terakhir'] as int? ?? 0,
                        isComplete: progress?['selesai'] == true,
                        onSave: (absoluteIndex, total) => _saveProgress(juzNumber, absoluteIndex, total),
                      );
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


}