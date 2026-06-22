import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/personal_history_service.dart';
import '../services/notification_service.dart';
import '../providers/settings_provider.dart';
import '../data/quran_id_translation.dart';
import '../utils/localization.dart';
import '../services/widget_update_service.dart';

class VerseItem {
  final int surahNumber;
  final int verseNumber;
  VerseItem({required this.surahNumber, required this.verseNumber});
}

class MushafReaderScreen extends StatefulWidget {
  final int? initialSurahNumber;
  final int? initialVerseNumber;
  final int? initialJuzNumber;
  
  // Progress Sync Context
  final bool selectForMandiri;
  final String? selectForGroupId;
  final String? groupName;
  final int? slotId;

  const MushafReaderScreen({
    Key? key,
    this.initialSurahNumber,
    this.initialVerseNumber,
    this.initialJuzNumber,
    this.selectForMandiri = false,
    this.selectForGroupId,
    this.groupName,
    this.slotId,
  }) : super(key: key);

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> {
  final _supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  
  List<VerseItem> _verses = [];
  int? _activeJuz;
  int? _activeSurah;
  
  // Customization Settings (loaded from SharedPreferences)
  double _arabicFontSize = 26.0;
  double _translationFontSize = 14.0;
  bool _showTranslation = true;

  // Selection state
  VerseItem? _selectedVerse;
  int _lastReadVerseIndex = 0;
  bool _isLoading = true;
  
  // Saved Progress offset in database
  int _dbSavedAbsoluteIndex = 0;
  int _totalAyatInJuz = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initVerses();
    _fetchDBSavedProgress();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _arabicFontSize = prefs.getDouble('mushaf_arabic_font_size') ?? 26.0;
        _translationFontSize = prefs.getDouble('mushaf_translation_font_size') ?? 14.0;
        _showTranslation = prefs.getBool('mushaf_show_translation') ?? true;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('mushaf_arabic_font_size', _arabicFontSize);
    await prefs.setDouble('mushaf_translation_font_size', _translationFontSize);
    await prefs.setBool('mushaf_show_translation', _showTranslation);
  }

  void _initVerses() {
    if (widget.initialJuzNumber != null) {
      _activeJuz = widget.initialJuzNumber;
      final surahMap = quran.getSurahAndVersesFromJuz(_activeJuz!);
      _verses = [];
      surahMap.forEach((surahNum, bounds) {
        for (int i = bounds[0]; i <= bounds[1]; i++) {
          _verses.add(VerseItem(surahNumber: surahNum, verseNumber: i));
        }
      });
      _totalAyatInJuz = _verses.length;
    } else if (widget.initialSurahNumber != null) {
      _activeSurah = widget.initialSurahNumber;
      final totalVerses = quran.getVerseCount(_activeSurah!);
      _verses = [];
      for (int i = 1; i <= totalVerses; i++) {
        _verses.add(VerseItem(surahNumber: _activeSurah!, verseNumber: i));
      }
      
      // Infer Juz from the first verse
      _activeJuz = quran.getJuzNumber(_activeSurah!, 1);
      _totalAyatInJuz = 0;
      final surahMap = quran.getSurahAndVersesFromJuz(_activeJuz!);
      surahMap.forEach((surahNum, bounds) {
        _totalAyatInJuz += (bounds[1] - bounds[0] + 1);
      });
    }

    // Scroll to initial verse if specified
    if (widget.initialVerseNumber != null) {
      final idx = _verses.indexWhere((v) => 
        v.surahNumber == (widget.initialSurahNumber ?? _verses.first.surahNumber) && 
        v.verseNumber == widget.initialVerseNumber
      );
      if (idx != -1) {
        _lastReadVerseIndex = idx;
        _selectedVerse = _verses[idx];
      }
    }

    setState(() {
      _isLoading = false;
    });

    // Auto Scroll to the verse after initial build
    if (_lastReadVerseIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToIndex(_lastReadVerseIndex);
      });
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    // Estimate height of each verse row (Arabic + Translation is around 120-160 pixels)
    final offset = index * 140.0;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _fetchDBSavedProgress() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (_activeJuz == null) return;

    try {
      if (widget.slotId != null) {
        // Group Mode
        final res = await _supabase
            .from('slot_khataman')
            .select('ayat_terakhir_input')
            .eq('id_slot', widget.slotId!)
            .maybeSingle();
        if (res != null && mounted) {
          setState(() {
            _dbSavedAbsoluteIndex = res['ayat_terakhir_input'] as int? ?? 0;
          });
        }
      } else if (widget.selectForMandiri) {
        // Mandiri Mode
        final res = await _supabase
            .from('khataman_mandiri')
            .select('ayat_terakhir')
            .eq('user_id', userId)
            .eq('nomor_juz', _activeJuz!)
            .maybeSingle();
        if (res != null && mounted) {
          setState(() {
            _dbSavedAbsoluteIndex = res['ayat_terakhir'] as int? ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching db progress: $e');
    }
  }

  int _calculateAbsoluteIndex(int surah, int verse) {
    if (_activeJuz == null) return 0;
    final surahsInJuz = quran.getSurahAndVersesFromJuz(_activeJuz!);
    int absoluteIndex = 0;
    for (var entry in surahsInJuz.entries) {
      int sNum = entry.key;
      int start = entry.value[0];
      int end = entry.value[1];
      
      if (sNum == surah) {
        if (verse >= start && verse <= end) {
          absoluteIndex += (verse - start + 1);
        } else if (verse > end) {
          absoluteIndex += (end - start + 1);
        }
        break;
      } else {
        absoluteIndex += (end - start + 1);
      }
    }
    return absoluteIndex;
  }

  Future<void> _saveAsLastRead(VerseItem verse) async {
    final prefs = await SharedPreferences.getInstance();
    final surahName = quran.getSurahName(verse.surahNumber);
    final juzNumber = quran.getJuzNumber(verse.surahNumber, verse.verseNumber);

    await prefs.setInt('last_read_surah_number', verse.surahNumber);
    await prefs.setString('last_read_surah_name', surahName);
    await prefs.setInt('last_read_verse_number', verse.verseNumber);
    await prefs.setInt('last_read_juz_number', juzNumber);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('mushaf_reader_bookmark_saved')
              .replaceFirst('{surah}', surahName)
              .replaceFirst('{ayat}', verse.verseNumber.toString())),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    }
  }

  Future<void> _saveProgressToDB(int absoluteIndex) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (_activeJuz == null) return;

    final isComplete = absoluteIndex == _totalAyatInJuz;

    // Direct Logging check: Do not allow reverse progress (Anti-Reduction)
    if (absoluteIndex < _dbSavedAbsoluteIndex && _dbSavedAbsoluteIndex > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('mushaf_reader_err_reverse')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    try {
      if (widget.slotId != null) {
        // Group Mode Save
        await _supabase.from('slot_khataman').update({
          'ayat_terakhir_input': absoluteIndex,
          'status_checklist': isComplete,
        }).eq('id_slot', widget.slotId!);

        if (isComplete) {
          final desc = context.translate('mushaf_reader_log_juz_completed_mushaf')
              .replaceFirst('{juz}', _activeJuz!.toString());
          await PersonalHistoryService.logReading(
            userId: userId,
            juz: _activeJuz!,
            description: desc,
            type: 'Grup: ${widget.groupName ?? context.translate('history_cycle_group_fallback')}',
            isJuzCompletion: true,
          );

          // Send notification
          if (widget.selectForGroupId != null) {
            final settings = Provider.of<SettingsProvider>(context, listen: false);
            final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
                _supabase.auth.currentUser?.email?.split('@')[0] ??
                (settings.language == 'en' ? 'Someone' : 'Seseorang');
            final gName = widget.groupName ?? context.translate('history_cycle_group_fallback');

            await NotificationService.sendToGroup(
              groupId: widget.selectForGroupId!,
              type: 'JUZ_COMPLETED',
              title: context.translate('mushaf_reader_notif_completed_title'),
              body: context.translate('mushaf_reader_notif_completed_body')
                  .replaceFirst('{user}', senderName)
                  .replaceFirst('{juz}', _activeJuz!.toString())
                  .replaceFirst('{group}', gName),
              excludeUserId: userId,
            );
          }
        } else {
          await PersonalHistoryService.removeReadingLog(
            userId: userId,
            juz: _activeJuz!,
            type: 'Grup: ${widget.groupName ?? context.translate('history_cycle_group_fallback')}',
          );
        }

        setState(() {
          _dbSavedAbsoluteIndex = absoluteIndex;
        });

      } else if (widget.selectForMandiri) {
        // Mandiri Mode Save
        await _supabase.from('khataman_mandiri').upsert({
          'user_id': userId,
          'nomor_juz': _activeJuz!,
          'ayat_terakhir': absoluteIndex,
          'selesai': isComplete,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,nomor_juz');

        if (isComplete) {
          final desc = context.translate('mushaf_reader_log_juz_completed_mushaf')
              .replaceFirst('{juz}', _activeJuz!.toString());
          await PersonalHistoryService.logReading(
            userId: userId,
            juz: _activeJuz!,
            description: desc,
            type: 'Mandiri',
            isJuzCompletion: true,
          );
        } else {
          await PersonalHistoryService.removeReadingLog(
            userId: userId,
            juz: _activeJuz!,
            type: 'Mandiri',
          );
        }

        setState(() {
          _dbSavedAbsoluteIndex = absoluteIndex;
        });
      }

      if (mounted) {
        final contentText = isComplete 
            ? context.translate('mushaf_reader_success_completed').replaceFirst('{juz}', _activeJuz!.toString())
            : context.translate('mushaf_reader_success_saved');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(contentText),
            backgroundColor: isComplete ? AppTheme.primaryGreen : const Color(0xFF323232),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      WidgetUpdateService.updateKhatamanWidget();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.translate('mushaf_reader_err_save').replaceFirst('{error}', e.toString())),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.translate('mushaf_reader_settings_title'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Arabic font size slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.translate('mushaf_reader_arabic_text_size'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                      Text('${_arabicFontSize.toInt()} px', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                    ],
                  ),
                  Slider(
                    value: _arabicFontSize,
                    min: 18.0,
                    max: 40.0,
                    divisions: 22,
                    activeColor: AppTheme.primaryGreen,
                    inactiveColor: AppTheme.primaryGreen.withOpacity(0.12),
                    onChanged: (val) {
                      setSheetState(() => _arabicFontSize = val);
                      setState(() => _arabicFontSize = val);
                      _saveSettings();
                    },
                  ),
                  
                  // Translation font size slider
                  if (_showTranslation) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.translate('mushaf_reader_translation_text_size'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                        Text('${_translationFontSize.toInt()} px', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                      ],
                    ),
                    Slider(
                      value: _translationFontSize,
                      min: 11.0,
                      max: 24.0,
                      divisions: 13,
                      activeColor: AppTheme.primaryGreen,
                      inactiveColor: AppTheme.primaryGreen.withOpacity(0.12),
                      onChanged: (val) {
                        setSheetState(() => _translationFontSize = val);
                        setState(() => _translationFontSize = val);
                        _saveSettings();
                      },
                    ),
                  ],
                  
                  // Toggle Translation switch
                  SwitchListTile(
                    title: Text(context.translate('mushaf_reader_show_translation'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                    value: _showTranslation,
                    activeColor: AppTheme.primaryGreen,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setSheetState(() => _showTranslation = val);
                      setState(() => _showTranslation = val);
                      _saveSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<SettingsProvider>(context); // Listen to settings changes
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Page Title
    String pageTitle = '';
    if (_activeJuz != null) {
      pageTitle = context.translate('mushaf_last_read_juz').replaceFirst('{juz}', _activeJuz!.toString());
    } else if (_activeSurah != null) {
      pageTitle = quran.getSurahName(_activeSurah!);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(pageTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: context.translate('mushaf_reader_settings_title'),
            onPressed: _showSettingsBottomSheet,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient,
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
              : Column(
                  children: [
                    // Reading list
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _verses.length,
                        itemBuilder: (context, index) {
                          final item = _verses[index];
                          final isSelected = _selectedVerse != null && 
                              _selectedVerse!.surahNumber == item.surahNumber &&
                              _selectedVerse!.verseNumber == item.verseNumber;

                          // Surah Header (displays at the start of each Surah in Juz-mode, or at verse 1)
                          final showSurahHeader = index == 0 || 
                              _verses[index - 1].surahNumber != item.surahNumber;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showSurahHeader) _buildSurahHeader(item.surahNumber, isDark),
                              _buildVerseRow(item, index, isSelected, isDark),
                            ],
                          );
                        },
                      ),
                    ),

                    // Floating Sync Bar at the bottom
                    _buildFloatingSyncBar(isDark),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSurahHeader(int surahNum, bool isDark) {
    final name = quran.getSurahName(surahNum);
    final place = quran.getPlaceOfRevelation(surahNum) == 'Makkah'
        ? context.translate('mushaf_makkiyah')
        : context.translate('mushaf_madaniyah');
    final arabic = quran.getSurahNameArabic(surahNum);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 18),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Surah $name',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$place • ${context.translate('mushaf_verses_count').replaceFirst('{count}', quran.getVerseCount(surahNum).toString())}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Text(
                arabic,
                style: const TextStyle(
                  fontSize: 22,
                  fontFamily: 'sans-serif',
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
          if (surahNum != 9) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontFamily: 'sans-serif',
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryGreen,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerseRow(VerseItem item, int index, bool isSelected, bool isDark) {
    final settings = Provider.of<SettingsProvider>(context);
    final isEnglish = settings.language == 'en';
    final arabicText = quran.getVerse(item.surahNumber, item.verseNumber);
    final translationText = isEnglish
        ? quran.getVerseTranslation(
            item.surahNumber,
            item.verseNumber,
            translation: quran.Translation.enSaheeh,
          )
        : quranIndonesianTranslation['${item.surahNumber}:${item.verseNumber}'] ?? '';

    // Calculate absolute index inside this Juz to compare with DB progress
    int absoluteIndex = 0;
    bool isReadInDBSaved = false;
    if (_activeJuz != null) {
      absoluteIndex = _calculateAbsoluteIndex(item.surahNumber, item.verseNumber);
      isReadInDBSaved = absoluteIndex <= _dbSavedAbsoluteIndex;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVerse = item;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryGreen.withOpacity(isDark ? 0.12 : 0.06)
              : (isReadInDBSaved 
                  ? AppTheme.primaryGreen.withOpacity(isDark ? 0.05 : 0.02)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryGreen.withOpacity(0.5)
                : (isReadInDBSaved 
                    ? AppTheme.primaryGreen.withOpacity(0.2) 
                    : Colors.transparent),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Verse Top Control Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Verse Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item.surahNumber}:${item.verseNumber}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
                
                // Read indicator / Bookmark button
                Row(
                  children: [
                    if (isReadInDBSaved)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen.withOpacity(0.6), size: 16),
                      ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: context.translate('mushaf_reader_bookmark_label'),
                      onPressed: () => _saveAsLastRead(item),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Arabic Text (Right Aligned)
            Text(
              arabicText,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: _arabicFontSize,
                fontFamily: 'sans-serif',
                height: 1.8,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            
            // Translation Text (Left Aligned)
            if (_showTranslation) ...[
              const SizedBox(height: 14),
              Text(
                translationText,
                style: TextStyle(
                  fontSize: _translationFontSize,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingSyncBar(bool isDark) {
    // Show only if selectForMandiri or selectForGroupId is provided, and we have a selected verse
    final isMandiri = widget.selectForMandiri;
    final isGroup = widget.slotId != null;

    if (!isMandiri && !isGroup) {
      // General Mode: just show a simple prompt to select a verse to log or bookmark
      if (_selectedVerse == null) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.translate('mushaf_reader_selected_verse_title'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    'Surah ${quran.getSurahName(_selectedVerse!.surahNumber)}: ${_selectedVerse!.verseNumber}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _saveAsLastRead(_selectedVerse!),
              icon: const Icon(Icons.bookmark_rounded, size: 16),
              label: Text(context.translate('mushaf_reader_bookmark_label')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_activeJuz == null) return const SizedBox.shrink();

    // Calculate current selection absolute index
    int selectedAbsoluteIndex = _dbSavedAbsoluteIndex;
    if (_selectedVerse != null) {
      selectedAbsoluteIndex = _calculateAbsoluteIndex(_selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
    }

    final hasProgressToSave = selectedAbsoluteIndex > _dbSavedAbsoluteIndex;
    final progressPercent = _totalAyatInJuz > 0 
        ? ((_dbSavedAbsoluteIndex / _totalAyatInJuz) * 100).round() 
        : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Progres Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isGroup 
                        ? '${context.translate('home_type_group')} (${widget.groupName})' 
                        : context.translate('mandiri_title'),
                    style: const TextStyle(fontSize: 11, color: AppTheme.primaryGreen, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.translate('mushaf_reader_juz_progress_text')
                        .replaceFirst('{juz}', _activeJuz!.toString())
                        .replaceFirst('{current}', _dbSavedAbsoluteIndex.toString())
                        .replaceFirst('{total}', _totalAyatInJuz.toString())
                        .replaceFirst('{percent}', progressPercent.toString()),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              
              // Direct complete button
              if (_dbSavedAbsoluteIndex < _totalAyatInJuz)
                TextButton(
                  onPressed: () => _saveProgressToDB(_totalAyatInJuz),
                  child: Text(
                    context.translate('mushaf_reader_mark_juz_done'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Selected Verse & Actions
          if (_selectedVerse != null && hasProgressToSave) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.translate('mushaf_reader_progress_new_label'),
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Surah ${quran.getSurahName(_selectedVerse!.surahNumber)} ayat ${_selectedVerse!.verseNumber}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _saveProgressToDB(selectedAbsoluteIndex),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      context.translate('mushaf_reader_save_progress_label'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              _dbSavedAbsoluteIndex >= _totalAyatInJuz 
                  ? context.translate('mushaf_reader_juz_completed_banner') 
                  : context.translate('mushaf_reader_tap_instruction_banner'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
