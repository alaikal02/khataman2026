import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../providers/settings_provider.dart';
import '../utils/localization.dart';
import '../components/juz_progress_card.dart';
import '../components/khatam_celebration.dart';
import '../theme/app_theme.dart';
import '../services/personal_history_service.dart';
import 'active_khataman_list_screen.dart';
import 'dart:io';
import 'dart:async';
import '../services/widget_update_service.dart';

class MandiriScreen extends StatefulWidget {
  const MandiriScreen({Key? key}) : super(key: key);

  static void invalidateCache() {
    _MandiriScreenState.invalidateCache();
  }

  @override
  State<MandiriScreen> createState() => _MandiriScreenState();
}

class _MandiriScreenState extends State<MandiriScreen> {
  static List<Map<String, dynamic>>? _cachedProgress;
  static String? _cachedUserId;

  static void invalidateCache() {
    _cachedProgress = null;
    _cachedUserId = null;
  }

  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _progress = [];
  bool _isLoading = true;
  bool _isOffline = false;
  Timer? _offlineRetryTimer;
  late ScrollController _scrollController;
  double _shrinkFactor = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);

    final userId = _supabase.auth.currentUser?.id;
    if (userId != _cachedUserId) {
      _cachedUserId = userId;
      _cachedProgress = null;
    }

    _progress = _cachedProgress ?? [];
    _isLoading = _cachedProgress == null;

    _loadProgress();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _offlineRetryTimer?.cancel();
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
      final isOnline = await _checkInternet();
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            _isLoading = false;
          });
          _startOfflineRetryTimer();
        }
        return;
      }

      final data = await _supabase
          .from('khataman_mandiri')
          .select()
          .eq('user_id', userId)
          .order('nomor_juz');

      _cachedProgress = List<Map<String, dynamic>>.from(data);
      if (mounted) {
        setState(() {
          _progress = _cachedProgress!;
          _isLoading = false;
          _isOffline = false;
        });
      }
      _offlineRetryTimer?.cancel();
      _offlineRetryTimer = null;
    } catch (e) {
      final isOnline = await _checkInternet();
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            _isLoading = false;
          });
          _startOfflineRetryTimer();
        }
      } else {
        // Table might not exist yet, create fresh state
        _cachedProgress = [];
        if (mounted) {
          setState(() {
            _progress = [];
            _isLoading = false;
            _isOffline = false;
          });
        }
        _offlineRetryTimer?.cancel();
        _offlineRetryTimer = null;
      }
    }
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('dns.google').timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _startOfflineRetryTimer() {
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isOnline = await _checkInternet();
      if (isOnline) {
        timer.cancel();
        _offlineRetryTimer = null;
        _loadProgress();
      }
    });
  }

  Future<void> _saveProgress(int juzNumber, int ayat, int total) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Validasi TC-02
    if (ayat > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('mandiri_max_ayat_error').replaceAll('{total}', total.toString())),
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

      // Invalidate cache immediately on user mutation
      _cachedProgress = null;
      ActiveKhatamanListScreen.invalidateCache();

      if (isComplete) {
        final desc = context.translate('mandiri_log_juz_completed').replaceAll('{juz}', juzNumber.toString());
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
      WidgetUpdateService.updateKhatamanWidget();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.translate('mandiri_save_failed').replaceAll('{error}', e.toString())), backgroundColor: Colors.redAccent),
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
        title: Text(context.translate('mandiri_reset_dialog_title'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          context.translate('mandiri_reset_dialog_body'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.translate('mandiri_reset_dialog_cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(context.translate('mandiri_reset_dialog_confirm'), style: const TextStyle(fontWeight: FontWeight.bold)),
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

      // Invalidate cache immediately on user mutation
      _cachedProgress = null;
      ActiveKhatamanListScreen.invalidateCache();

      setState(() {
        _progress = [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.translate('mandiri_reset_success')),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.translate('mandiri_reset_failed').replaceAll('{error}', e.toString())), backgroundColor: Colors.redAccent),
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
          context.translate('mandiri_confirm_khatam_title'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          context.translate('mandiri_confirm_khatam_body'),
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
                confirmationMessage: context.translate('mandiri_confirm_khatam_instruction'),
              );
            },
            icon: const Icon(Icons.auto_stories_rounded, size: 16),
            label: Text(context.translate('mandiri_btn_read_doa'), style: const TextStyle(fontWeight: FontWeight.w600)),
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
            label: Text(context.translate('mandiri_btn_yes_done'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
        description: context.translate('mandiri_log_khatam_completed'),
        type: 'Mandiri',
        isJuzCompletion: true,
        isKhatamCompletion: true,
      );

      // 2. Reset seluruh progres mandiri
      await _supabase
          .from('khataman_mandiri')
          .delete()
          .eq('user_id', userId);

      // Invalidate cache immediately on user mutation
      _cachedProgress = null;
      ActiveKhatamanListScreen.invalidateCache();

      setState(() {
        _progress = [];
      });
      WidgetUpdateService.updateKhatamanWidget();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.translate('mandiri_khatam_logged')),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.translate('mandiri_khatam_failed').replaceAll('{error}', e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<SettingsProvider>(context);
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
        title: Text(context.translate('mandiri_title')),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.redAccent),
            tooltip: context.translate('mandiri_tooltip_reset'),
            onPressed: _resetAllProgress,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : Column(
              children: [
                _buildOfflineBanner(),
                // Summary Card
                _buildSummaryCard(completed, realProgressValue, totalPercent),
                if (completed == 30)
                  CongratulatoryCard(
                    onReset: _resetAllProgress,
                    resetLabel: context.translate('mandiri_btn_reset_khatam'),
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
                        onProgressUpdated: _loadProgress,
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
                        context.translate('mandiri_progress_title'),
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
                        context.translate('mandiri_juz_completed_count').replaceAll('{completed}', completed.toString()),
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
                            context.translate('mandiri_progress_short').replaceAll('{completed}', completed.toString()),
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

  Widget _buildOfflineBanner() {
    if (!_isOffline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.redAccent.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            context.translate('mandiri_offline_banner'),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}