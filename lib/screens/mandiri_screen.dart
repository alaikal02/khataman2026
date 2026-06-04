import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../components/juz_progress_card.dart';
import '../components/khatam_celebration.dart';
import '../theme/app_theme.dart';
import '../services/personal_history_service.dart';

class MandiriScreen extends StatefulWidget {
  const MandiriScreen({Key? key}) : super(key: key);

  @override
  State<MandiriScreen> createState() => _MandiriScreenState();
}

class _MandiriScreenState extends State<MandiriScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _progress = [];
  bool _isLoading = true;
  late ScrollController _scrollController;
  double _shrinkFactor = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    _loadProgress();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final double newFactor = (offset / 80.0).clamp(0.0, 1.0);
    if (newFactor != _shrinkFactor) {
      setState(() {
        _shrinkFactor = newFactor;
      });
    }
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

      if (isComplete) {
        final desc = 'Alhamdulillah, telah menyelesaikan Juz $juzNumber!';
        await PersonalHistoryService.logReading(
          userId: userId,
          juz: juzNumber,
          description: desc,
          type: 'Mandiri',
          isJuzCompletion: true,
        );
      } else {
        await PersonalHistoryService.removeReadingLog(
          userId: userId,
          juz: juzNumber,
          type: 'Mandiri',
        );
      }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Mulai Khatam Baru?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          'Progress bacaan saat ini akan dimulai kembali dari awal. Riwayat khatam sebelumnya tetap tersimpan.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Mulai Baru', style: TextStyle(fontWeight: FontWeight.bold)),
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
          const SnackBar(
            content: Text('Progres berhasil direset. Bismillah, mulai lagi! \uD83C\uDF19'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal reset: \$e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Menampilkan dialog konfirmasi Doa Khatam Al-Quran untuk Khataman Mandiri.
  /// Jika user sudah membaca doa, progres dicatat ke riwayat dan di-reset.
  void _showDoaKhatamConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.menu_book_rounded,
          color: AppTheme.accentGold,
          size: 40,
        ),
        title: Text(
          'Konfirmasi Khataman',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Apakah Anda sudah selesai membaca Doa Khatam Al-Quran?\n\n'
          'Jika sudah, progres khataman akan dicatat ke dalam riwayat '
          'dan di-reset kembali ke Juz 1.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showDoaKhatamBottomSheet(
                context,
                onConfirmCompletion: _confirmDoaKhatamMandiri,
                confirmationMessage: 'Tindakan ini akan mencatat khataman Mandiri Anda ke riwayat, lalu mereset seluruh progres kembali ke Juz 1 untuk memulai putaran baru. Lanjutkan?',
              );
            },
            icon: const Icon(Icons.auto_stories_rounded, size: 16),
            label: const Text('Belum, Baca Doa', style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentGold,
              side: BorderSide(color: AppTheme.accentGold.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDoaKhatamMandiri();
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Ya, Sudah', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Mencatat khataman mandiri ke riwayat dan mereset seluruh progres.
  Future<void> _confirmDoaKhatamMandiri() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // 1. Catat khatam completion ke riwayat personal
      await PersonalHistoryService.logReading(
        userId: userId,
        juz: 30,
        description: '\uD83C\uDFC6 Menyelesaikan Khataman Mandiri 30 Juz! Alhamdulillah!',
        type: 'Mandiri',
        isJuzCompletion: true,
        isKhatamCompletion: true,
      );

      // 2. Reset seluruh progres mandiri
      await _supabase
          .from('khataman_mandiri')
          .delete()
          .eq('user_id', userId);

      setState(() {
        _progress = [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\uD83C\uDFC6 Khataman berhasil dicatat! Bismillah, mulai lagi!'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mencatat khataman: \$e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalProgressSum = 0.0;
    for (int juzNum = 1; juzNum <= 30; juzNum++) {
      final progress = _getProgressForJuz(juzNum);
      if (progress != null) {
        if (progress['selesai'] == true) {
          totalProgressSum += 1.0;
        } else {
          final lastAyat = progress['ayat_terakhir'] as int? ?? 0;
          if (lastAyat > 0) {
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
    }
    final double realProgressValue = totalProgressSum / 30.0;
    final String totalPercent = (realProgressValue * 100).toStringAsFixed(2);
    final completed = _completedCount();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Khataman Mandiri'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.redAccent),
            tooltip: 'Reset Semua Progres',
            onPressed: _resetAllProgress,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : Column(
              children: [
                // Summary Card
                _buildSummaryCard(completed, realProgressValue, totalPercent),
                if (completed == 30)
                  CongratulatoryCard(
                    onReset: _resetAllProgress,
                    resetLabel: 'Mulai Khataman Baru',
                    showResetButton: false,
                    onDoaKhatam: _showDoaKhatamConfirmation,
                  ),
                // Juz List
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
                    itemCount: 30,
                    itemBuilder: (context, index) {
                      final juzNumber = index + 1;
                      final progress = _getProgressForJuz(juzNumber);
                      return JuzProgressCard(
                        key: ValueKey('mandiri_juz_$juzNumber'),
                        juzNumber: juzNumber,
                        lastAyat: progress?['ayat_terakhir'] as int? ?? 0,
                        isComplete: progress?['selesai'] == true,
                        isGroupMode: false,
                        onSave: (absoluteIndex, total) => _saveProgress(juzNumber, absoluteIndex, total),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(int completed, double realProgressValue, String totalPercent) {
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
    final titleTextColor = isDark ? Colors.white70 : const Color(0xFF757575);
    final valueTextColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final percentColor = isDark ? AppTheme.primaryGreen : AppTheme.darkGreen;
    final progressBgColor = isDark ? Colors.white.withOpacity(0.12) : AppTheme.primaryGreen.withOpacity(0.15);
    final borderColor = isDark ? AppTheme.primaryGreen.withOpacity(0.3) : AppTheme.primaryGreen.withOpacity(0.2);

    // Fluid scroll-linked morphing sizes and values
    final double verticalPadding = 18.0 - (10.0 * _shrinkFactor); // 18.0 down to 8.0
    final double labelOpacity = (1.0 - _shrinkFactor * 1.8).clamp(0.0, 1.0); // Fades out early/quickly for clean layout
    final double labelHeight = 13.0 * labelOpacity;
    final double completedFontSize = 26.0 - (11.0 * _shrinkFactor); // 26.0 down to 15.0
    final double indicatorSize = 88.0 - (48.0 * _shrinkFactor); // 88.0 down to 40.0 (slightly larger to accommodate "100.00%")
    final double percentFontSize = 14.0 - (4.0 * _shrinkFactor); // 14.0 down to 10.0
    final double strokeWidth = 4.5 - (2.0 * _shrinkFactor); // 4.5 down to 2.5
    final double spacerHeight = 4.0 * (1.0 - _shrinkFactor);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: verticalPadding),
      decoration: BoxDecoration(
        gradient: cardBgGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (labelOpacity > 0.0)
                  SizedBox(
                    height: labelHeight,
                    child: Opacity(
                      opacity: labelOpacity,
                      child: Text(
                        'Progres Khataman',
                        style: TextStyle(
                          color: titleTextColor,
                          fontSize: 13,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                if (labelOpacity > 0.0) SizedBox(height: spacerHeight),
                Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Opacity(
                      opacity: (1.0 - _shrinkFactor / 0.5).clamp(0.0, 1.0),
                      child: Text(
                        '$completed / 30 Juz Selesai',
                        style: TextStyle(
                          fontSize: completedFontSize,
                          fontWeight: FontWeight.bold,
                          color: valueTextColor,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: ((_shrinkFactor - 0.4) / 0.6).clamp(0.0, 1.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            color: percentColor,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Progres Mandiri: $completed/30 Juz',
                            style: TextStyle(
                              fontSize: completedFontSize,
                              fontWeight: FontWeight.bold,
                              color: valueTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: indicatorSize,
            height: indicatorSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: indicatorSize,
                  height: indicatorSize,
                  child: CircularProgressIndicator(
                    value: realProgressValue,
                    strokeWidth: strokeWidth,
                    backgroundColor: progressBgColor,
                    valueColor: AlwaysStoppedAnimation<Color>(percentColor),
                  ),
                ),
                Text(
                  '$totalPercent%',
                  style: TextStyle(
                    fontSize: percentFontSize,
                    fontWeight: FontWeight.bold,
                    color: percentColor,
                    letterSpacing: -0.5,
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