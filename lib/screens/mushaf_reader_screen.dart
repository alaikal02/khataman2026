import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import 'package:provider/provider.dart';
import 'dart:ui' show PathMetric;
import '../theme/app_theme.dart';
import '../services/personal_history_service.dart';
import '../services/notification_service.dart';
import '../providers/settings_provider.dart';
import '../data/quran_id_translation.dart';
import '../utils/localization.dart';
import '../services/widget_update_service.dart';
import '../features/group/presentation/group_list_screen.dart';

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

  // Dynamically managed active user programs
  List<Map<String, dynamic>> _userPrograms = [];
  Map<String, dynamic>? _currentProgram;

  Timer? _autoHideTimer;

  bool _isScrolling = false;
  double _scrollOffset = 0.0;
  int? _currentVisibleSurah;
  Timer? _scrollDebounceTimer;
  List<double> _itemOffsets = [];
  bool _showSurahInfoTooltip = false;
  bool _isMinimized = false;
  bool _minimizeToLeft = false;
  bool _showNextJuzButton = false;
  double? _bubbleLeft;
  double? _bubbleTop;

  String _cleanArabicText(String text) {
    // 1. Replace Uthmani sukun (small high jazm) with normal sukun
    text = text.replaceAll('\u06e1', '\u0652');
    
    // 2. Replace Alef Wasla with normal Alef
    text = text.replaceAll('\u0671', '\u0627');
    
    // 3. Remove fatha when combined with superscript alif to prevent stacking
    text = text.replaceAll('\u064e\u0670', '\u0670');
    text = text.replaceAll('\u0670\u064e', '\u0670');
    
    // 4. Specifically convert Uthmani "insan" spelling to Indo-Pak/Indonesian spelling
    // Uthmani: إِنسَٰن (U+0625, U+0650, U+0646, U+0633, U+064E, U+0670, U+0646)
    // Indopak/Indonesian: إِنْسَان (U+0625, U+0650, U+0646, U+0652, U+0633, U+064E, U+0627, U+0646)
    text = text.replaceAll('\u0625\u0650\u0646\u0633\u064e\u0670\u0646', '\u0625\u0650\u0646\u0652\u0633\u064e\u0627\u0646');
    text = text.replaceAll('\u0625\u0650\u0646\u0633\u0670\u0646', '\u0625\u0650\u0646\u0652\u0633\u064e\u0627\u0646');
    
    return text;
  }

  void _safePrecomputeOffsets() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _precomputeOffsets();
        });
      }
    });
  }

  void _precomputeOffsets() {
    if (_verses.isEmpty || !mounted) return;
    _itemOffsets = [];
    double currentOffset = 0.0;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth - 32; // ListView padding horizontal: 16 * 2
    final textWidth = contentWidth - 32; // Verse container padding: 16 * 2
    
    final showTranslation = _showTranslation;
    final isEnglish = Provider.of<SettingsProvider>(context, listen: false).language == 'en';
    
    for (int i = 0; i < _verses.length; i++) {
      _itemOffsets.add(currentOffset);
      
      final item = _verses[i];
      final showSurahHeader = i == 0 || _verses[i - 1].surahNumber != item.surahNumber;
      
      if (showSurahHeader) {
        if (item.surahNumber != 9) {
          currentOffset += 70.0; // Bismillah only: margin 12 + text ~58
        }
      }
      
      double verseHeight = 32.0 + 24.0 + 12.0; // Padding 32 + Badge row 24 + Spacing 12
      
      final rawArabicText = quran.getVerse(item.surahNumber, item.verseNumber);
      final arabicText = _cleanArabicText(rawArabicText);
      
      final arabicPainter = TextPainter(
        text: TextSpan(
          text: arabicText,
          style: TextStyle(
            fontSize: _arabicFontSize,
            fontFamily: 'LPMQ-IsepMisbah',
            height: 1.8,
          ),
        ),
        textDirection: TextDirection.rtl,
      );
      arabicPainter.layout(maxWidth: textWidth);
      verseHeight += arabicPainter.height;
      
      if (showTranslation) {
        verseHeight += 14.0; // Spacing 14
        
        final translationText = isEnglish
            ? quran.getVerseTranslation(
                item.surahNumber,
                item.verseNumber,
                translation: quran.Translation.enSaheeh,
              )
            : quranIndonesianTranslation['${item.surahNumber}:${item.verseNumber}'] ?? '';
            
        final translationPainter = TextPainter(
          text: TextSpan(
            text: translationText,
            style: TextStyle(
              fontSize: _translationFontSize,
              height: 1.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        translationPainter.layout(maxWidth: textWidth);
        verseHeight += translationPainter.height;
      }
      
      currentOffset += verseHeight + 12.0; // Verse item bottom margin
    }
  }

  void _onScroll() {
    final offset = _scrollController.offset;

    if (offset != _scrollOffset) {
      setState(() {
        _scrollOffset = offset;
      });
    }

    if (!_isScrolling) {
      setState(() {
        _isScrolling = true;
      });
    }

    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isScrolling = false;
        });
        _saveLastReadFromScroll();
      }
    });

    if (_itemOffsets.isNotEmpty) {
      int visibleIndex = 0;
      for (int i = 0; i < _itemOffsets.length; i++) {
        if (_itemOffsets[i] > offset) {
          visibleIndex = (i - 1).clamp(0, _itemOffsets.length - 1);
          break;
        }
        if (i == _itemOffsets.length - 1) {
          visibleIndex = i;
        }
      }

      int currentSurah = _verses[visibleIndex].surahNumber;
      if (currentSurah != _currentVisibleSurah) {
        setState(() {
          _currentVisibleSurah = currentSurah;
        });
      }
    }
  }

  Future<void> _saveLastReadFromScroll() async {
    if (_itemOffsets.isEmpty || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (offset <= 0) return;

    int visibleIndex = 0;
    for (int i = 0; i < _itemOffsets.length; i++) {
      if (_itemOffsets[i] > offset) {
        visibleIndex = (i - 1).clamp(0, _itemOffsets.length - 1);
        break;
      }
      if (i == _itemOffsets.length - 1) {
        visibleIndex = i;
      }
    }

    if (visibleIndex >= 0 && visibleIndex < _verses.length) {
      final verse = _verses[visibleIndex];
      final prefs = await SharedPreferences.getInstance();
      
      final currentSurahNum = prefs.getInt('last_read_surah_number');
      final currentVerseNum = prefs.getInt('last_read_verse_number');
      if (currentSurahNum != verse.surahNumber || currentVerseNum != verse.verseNumber) {
        final surahName = quran.getSurahName(verse.surahNumber);
        final juzNumber = quran.getJuzNumber(verse.surahNumber, verse.verseNumber);
        await prefs.setInt('last_read_surah_number', verse.surahNumber);
        await prefs.setString('last_read_surah_name', surahName);
        await prefs.setInt('last_read_verse_number', verse.verseNumber);
        await prefs.setInt('last_read_juz_number', juzNumber);
        debugPrint('Auto-saved last read on scroll: $surahName Ayat ${verse.verseNumber}');
      }
    }
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _selectedVerse != null) {
        final selJuz = quran.getJuzNumber(_selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
        final absoluteIndex = _calculateAbsoluteIndex(selJuz, _selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
        final hasProgressToSave = absoluteIndex > _dbSavedAbsoluteIndex;
        if (!hasProgressToSave) {
          setState(() {
            _selectedVerse = null;
            _updateSelectedProgramContext();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initVerses();
    _scrollController.addListener(_onScroll);
    
    // Set initial preset program context synchronously if preset
    if (widget.slotId != null || widget.selectForMandiri) {
      if (widget.slotId != null) {
        _currentProgram = {
          'type': 'GROUP',
          'id': 'group_${widget.slotId}',
          'juz': widget.initialJuzNumber ?? _activeJuz,
          'name': '${widget.groupName ?? 'Grup'} (Juz ${widget.initialJuzNumber ?? _activeJuz})',
          'slotId': widget.slotId,
          'groupId': widget.selectForGroupId,
          'groupName': widget.groupName,
          'ayat_terakhir': 0,
        };
      } else {
        _currentProgram = {
          'type': 'MANDIRI',
          'id': 'mandiri_${widget.initialJuzNumber ?? _activeJuz}',
          'juz': widget.initialJuzNumber ?? _activeJuz,
          'name': 'Khataman Mandiri (Juz ${widget.initialJuzNumber ?? _activeJuz})',
          'ayat_terakhir': 0,
        };
      }
      _fetchDBSavedProgress().then((_) {
        if (mounted) {
          setState(() {
            if (_currentProgram != null) {
              _currentProgram!['ayat_terakhir'] = _dbSavedAbsoluteIndex;
            }
          });
        }
      });
    }

    _loadAllActivePrograms();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _arabicFontSize = prefs.getDouble('mushaf_arabic_font_size') ?? 26.0;
        _translationFontSize = prefs.getDouble('mushaf_translation_font_size') ?? 14.0;
        _showTranslation = prefs.getBool('mushaf_show_translation') ?? true;
      });
      _safePrecomputeOffsets();
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

    if (_verses.isNotEmpty) {
      _currentVisibleSurah = _verses.first.surahNumber;
    }

    setState(() {
      _isLoading = false;
    });

    _safePrecomputeOffsets();

    // Auto Scroll to the verse after initial build
    if (_lastReadVerseIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToIndex(_lastReadVerseIndex);
      });
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    double offset = index * 140.0;
    if (_itemOffsets.isNotEmpty && index < _itemOffsets.length) {
      offset = _itemOffsets[index];
    }
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

  Future<void> _loadAllActivePrograms() async {
    final userId = _supabase.auth.currentUser?.id;
    debugPrint('DEBUG_MR: _loadAllActivePrograms starting. userId: $userId');
    if (userId == null) {
      debugPrint('DEBUG_MR: userId is null, returning early.');
      return;
    }

    final List<Map<String, dynamic>> programs = [];

    // 1. Fetch Mandiri (all rows to check completions)
    try {
      debugPrint('DEBUG_MR: Fetching khataman_mandiri...');
      final mandiriData = await _supabase
          .from('khataman_mandiri')
          .select()
          .eq('user_id', userId);
      debugPrint('DEBUG_MR: Fetching khataman_mandiri done. Count: ${mandiriData.length}');

      // Convert mandiriData to a Map for fast lookup
      final Map<int, Map<String, dynamic>> mandiriMap = {};
      for (var row in mandiriData) {
        final juz = row['nomor_juz'] as int;
        mandiriMap[juz] = row;
      }

      // For every Juz 1 to 30, add as active Mandiri program
      for (int juzNum = 1; juzNum <= 30; juzNum++) {
        final row = mandiriMap[juzNum];
        programs.add({
          'type': 'MANDIRI',
          'id': 'mandiri_$juzNum',
          'juz': juzNum,
          'name': 'Khataman Mandiri (Juz $juzNum)',
          'ayat_terakhir': row != null ? (row['ayat_terakhir'] as int? ?? 0) : 0,
        });
      }
      debugPrint('DEBUG_MR: Mandiri programs generated. Total programs currently: ${programs.length}');
    } catch (e) {
      debugPrint('DEBUG_MR: Error loading active mandiri programs: $e');
    }

    // 2. Fetch Active Group Slots claimed by user
    try {
      debugPrint('DEBUG_MR: Fetching active group slots...');
      final slotsData = await _supabase
          .from('slot_khataman')
          .select('*, putaran_siklus!inner(group_id, groups:groups!putaran_siklus_group_id_fkey(nama_grup, id_group, kode_gk_unik))')
          .eq('user_id', userId)
          .eq('status_checklist', false)
          .eq('putaran_siklus.status_aktif_selesai', 'AKTIF');
      debugPrint('DEBUG_MR: Fetching active group slots done. Count: ${slotsData.length}');

      for (var slot in slotsData as List) {
        final putaran = slot['putaran_siklus'] as Map<String, dynamic>?;
        final group = putaran != null ? putaran['groups'] as Map<String, dynamic>? : null;
        final groupName = group != null ? group['nama_grup'] as String? : 'Grup';
        final juzNum = slot['nomor_juz'] as int;

        programs.add({
          'type': 'GROUP',
          'id': 'group_${slot['id_slot']}',
          'juz': juzNum,
          'name': '$groupName (Juz $juzNum)',
          'slotId': slot['id_slot'] as int,
          'groupId': group != null ? group['id_group'] as String? : null,
          'groupName': groupName,
          'ayat_terakhir': slot['ayat_terakhir_input'] as int? ?? 0,
        });
      }
      debugPrint('DEBUG_MR: Group slots added. Total programs count: ${programs.length}');
    } catch (e) {
      debugPrint('DEBUG_MR: Error loading active group slots: $e');
    }

    if (mounted) {
      setState(() {
        _userPrograms = programs;
        debugPrint('DEBUG_MR: setState called with ${programs.length} programs.');
        _updateSelectedProgramContext();
      });
    }
  }

  void _updateSelectedProgramContext() {
    debugPrint('DEBUG_MR: _updateSelectedProgramContext starting. selectForMandiri: ${widget.selectForMandiri}, slotId: ${widget.slotId}');
    if (widget.slotId != null || widget.selectForMandiri) {
      // Locked context
      if (_currentProgram == null) {
        if (widget.slotId != null) {
          _currentProgram = {
            'type': 'GROUP',
            'id': 'group_${widget.slotId}',
            'juz': widget.initialJuzNumber ?? _activeJuz,
            'name': '${widget.groupName ?? 'Grup'} (Juz ${widget.initialJuzNumber ?? _activeJuz})',
            'slotId': widget.slotId,
            'groupId': widget.selectForGroupId,
            'groupName': widget.groupName,
            'ayat_terakhir': _dbSavedAbsoluteIndex,
          };
        } else {
          _currentProgram = {
            'type': 'MANDIRI',
            'id': 'mandiri_${widget.initialJuzNumber ?? _activeJuz}',
            'juz': widget.initialJuzNumber ?? _activeJuz,
            'name': 'Khataman Mandiri (Juz ${widget.initialJuzNumber ?? _activeJuz})',
            'ayat_terakhir': _dbSavedAbsoluteIndex,
          };
        }
      }
      debugPrint('DEBUG_MR: Locked context set. _currentProgram: $_currentProgram');
      return;
    }

    // Dynamic Context Mode
    int targetJuz = _activeJuz ?? 1;
    if (_selectedVerse != null) {
      targetJuz = quran.getJuzNumber(_selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
    }
    debugPrint('DEBUG_MR: Dynamic context mode. targetJuz: $targetJuz, _activeJuz: $_activeJuz, selectedVerse: ${_selectedVerse?.surahNumber}:${_selectedVerse?.verseNumber}');

    final matching = _userPrograms.where((p) => p['juz'] == targetJuz).toList();
    debugPrint('DEBUG_MR: Matching programs count for Juz $targetJuz: ${matching.length}. Matching: $matching');

    if (matching.isNotEmpty) {
      final currentIsStillMatching = _currentProgram != null && 
          matching.any((p) => p['id'] == _currentProgram!['id']);
      
      if (!currentIsStillMatching) {
        setState(() {
          _currentProgram = matching.first;
          _dbSavedAbsoluteIndex = _currentProgram!['ayat_terakhir'] as int;
        });
        debugPrint('DEBUG_MR: _currentProgram updated dynamically to: $_currentProgram, _dbSavedAbsoluteIndex: $_dbSavedAbsoluteIndex');
      } else {
        final updatedProg = matching.firstWhere((p) => p['id'] == _currentProgram!['id']);
        setState(() {
          _currentProgram = updatedProg;
          _dbSavedAbsoluteIndex = updatedProg['ayat_terakhir'] as int;
        });
        debugPrint('DEBUG_MR: _currentProgram updated details from DB: $_currentProgram, _dbSavedAbsoluteIndex: $_dbSavedAbsoluteIndex');
      }
    } else {
      setState(() {
        _currentProgram = null;
        _dbSavedAbsoluteIndex = 0;
      });
      debugPrint('DEBUG_MR: No matching programs found for Juz $targetJuz. _currentProgram reset to null.');
    }
  }

  Future<void> _startMandiriForJuz(int juzNum) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      await _supabase.from('khataman_mandiri').upsert({
        'user_id': userId,
        'nomor_juz': juzNum,
        'ayat_terakhir': 0,
        'selesai': false,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,nomor_juz');
      
      await _loadAllActivePrograms();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Khataman Mandiri untuk Juz $juzNum berhasil dimulai!', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting mandiri: $e');
    }
  }

  void _onProgramChanged(Map<String, dynamic>? newProgram) {
    if (newProgram == null) return;
    setState(() {
      _currentProgram = newProgram;
      _dbSavedAbsoluteIndex = newProgram['ayat_terakhir'] as int;
    });

    final int newJuz = newProgram['juz'] as int;
    _changeJuz(newJuz, targetVerseAbsoluteIndex: newProgram['ayat_terakhir'] as int?);
  }

  void _changeJuz(int juzNum, {int? targetVerseAbsoluteIndex}) {
    if (juzNum == _activeJuz) {
      if (targetVerseAbsoluteIndex != null && targetVerseAbsoluteIndex > 0) {
        int idx = 0;
        int currentAbsolute = 0;
        final surahMap = quran.getSurahAndVersesFromJuz(juzNum);
        bool found = false;
        for (var entry in surahMap.entries) {
          int sNum = entry.key;
          int start = entry.value[0];
          int end = entry.value[1];
          int count = end - start + 1;
          
          if (currentAbsolute + count >= targetVerseAbsoluteIndex) {
            int verseNum = start + (targetVerseAbsoluteIndex - currentAbsolute - 1);
            int itemIdx = _verses.indexWhere((v) => v.surahNumber == sNum && v.verseNumber == verseNum);
            if (itemIdx != -1) {
              idx = itemIdx;
              found = true;
            }
            break;
          } else {
            currentAbsolute += count;
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToIndex(found ? idx : 0);
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _activeJuz = juzNum;
      _selectedVerse = null;
      final surahMap = quran.getSurahAndVersesFromJuz(juzNum);
      _verses = [];
      surahMap.forEach((surahNum, bounds) {
        for (int i = bounds[0]; i <= bounds[1]; i++) {
          _verses.add(VerseItem(surahNumber: surahNum, verseNumber: i));
        }
      });
      _totalAyatInJuz = _verses.length;
      
      _dbSavedAbsoluteIndex = _currentProgram != null ? (_currentProgram!['ayat_terakhir'] as int? ?? 0) : 0;
      
      if (_verses.isNotEmpty) {
        _currentVisibleSurah = _verses.first.surahNumber;
      }
      
      _isLoading = false;
    });

    _safePrecomputeOffsets();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (targetVerseAbsoluteIndex != null && targetVerseAbsoluteIndex > 0) {
        int idx = 0;
        int currentAbsolute = 0;
        final surahMap = quran.getSurahAndVersesFromJuz(juzNum);
        bool found = false;
        for (var entry in surahMap.entries) {
          int sNum = entry.key;
          int start = entry.value[0];
          int end = entry.value[1];
          int count = end - start + 1;
          
          if (currentAbsolute + count >= targetVerseAbsoluteIndex) {
            int verseNum = start + (targetVerseAbsoluteIndex - currentAbsolute - 1);
            int itemIdx = _verses.indexWhere((v) => v.surahNumber == sNum && v.verseNumber == verseNum);
            if (itemIdx != -1) {
              idx = itemIdx;
              found = true;
            }
            break;
          } else {
            currentAbsolute += count;
          }
        }
        _scrollToIndex(found ? idx : 0);
      } else {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      }
    });
  }

  int _calculateAbsoluteIndex(int juz, int surah, int verse) {
    final surahsInJuz = quran.getSurahAndVersesFromJuz(juz);
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
          content: Text(
            context.translate('mushaf_reader_bookmark_saved')
                .replaceFirst('{surah}', surahName)
                .replaceFirst('{ayat}', verse.verseNumber.toString()),
            style: const TextStyle(color: Colors.white),
          ),
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
    
    final targetJuz = _currentProgram != null 
        ? _currentProgram!['juz'] as int 
        : _activeJuz!;

    int totalAyat = _totalAyatInJuz;
    if (_currentProgram != null && _currentProgram!['juz'] != _activeJuz) {
      final surahMap = quran.getSurahAndVersesFromJuz(_currentProgram!['juz']);
      int count = 0;
      surahMap.forEach((surahNum, bounds) {
        count += (bounds[1] - bounds[0] + 1);
      });
      totalAyat = count;
    }

    final isComplete = absoluteIndex == totalAyat;

    // Direct Logging check: Do not allow reverse progress (Anti-Reduction)
    if (absoluteIndex < _dbSavedAbsoluteIndex && _dbSavedAbsoluteIndex > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('mushaf_reader_err_reverse'), style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    try {
      if (_currentProgram != null && _currentProgram!['type'] == 'GROUP') {
        // Group Mode Save
        final slotId = _currentProgram!['slotId'] as int;
        final groupId = _currentProgram!['groupId'] as String?;
        final groupName = _currentProgram!['groupName'] as String?;

        await _supabase.from('slot_khataman').update({
          'ayat_terakhir_input': absoluteIndex,
          'status_checklist': isComplete,
        }).eq('id_slot', slotId);

        if (isComplete) {
          final desc = context.translate('mushaf_reader_log_juz_completed_mushaf')
              .replaceFirst('{juz}', targetJuz.toString());
          await PersonalHistoryService.logReading(
            userId: userId,
            juz: targetJuz,
            description: desc,
            type: 'Grup: ${groupName ?? context.translate('history_cycle_group_fallback')}',
            isJuzCompletion: true,
          );

          // Send notification
          if (groupId != null) {
            final settings = Provider.of<SettingsProvider>(context, listen: false);
            final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
                _supabase.auth.currentUser?.email?.split('@')[0] ??
                (settings.language == 'en' ? 'Someone' : 'Seseorang');
            final gName = groupName ?? context.translate('history_cycle_group_fallback');

            await NotificationService.sendToGroup(
              groupId: groupId,
              type: 'JUZ_COMPLETED',
              title: context.translate('mushaf_reader_notif_completed_title'),
              body: context.translate('mushaf_reader_notif_completed_body')
                  .replaceFirst('{user}', senderName)
                  .replaceFirst('{juz}', targetJuz.toString())
                  .replaceFirst('{group}', gName),
              excludeUserId: userId,
            );
          }
        } else {
          await PersonalHistoryService.removeReadingLog(
            userId: userId,
            juz: targetJuz,
            type: 'Grup: ${groupName ?? context.translate('history_cycle_group_fallback')}',
          );
        }

      } else if (_currentProgram != null && _currentProgram!['type'] == 'MANDIRI') {
        // Mandiri Mode Save
        await _supabase.from('khataman_mandiri').upsert({
          'user_id': userId,
          'nomor_juz': targetJuz,
          'ayat_terakhir': absoluteIndex,
          'selesai': isComplete,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,nomor_juz');

        if (isComplete) {
          final desc = context.translate('mushaf_reader_log_juz_completed_mushaf')
              .replaceFirst('{juz}', targetJuz.toString());
          await PersonalHistoryService.logReading(
            userId: userId,
            juz: targetJuz,
            description: desc,
            type: 'Mandiri',
            isJuzCompletion: true,
          );
        } else {
          await PersonalHistoryService.removeReadingLog(
            userId: userId,
            juz: targetJuz,
            type: 'Mandiri',
          );
        }
      }

      if (mounted) {
        final contentText = isComplete 
            ? context.translate('mushaf_reader_success_completed').replaceFirst('{juz}', targetJuz.toString())
            : context.translate('mushaf_reader_success_saved');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(contentText, style: const TextStyle(color: Colors.white)),
            backgroundColor: isComplete ? AppTheme.primaryGreen : const Color(0xFF323232),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }

      // Update last read locally when progress is saved
      if (absoluteIndex > 0 && absoluteIndex <= _verses.length) {
        final lastReadVerse = _verses[absoluteIndex - 1];
        final prefs = await SharedPreferences.getInstance();
        final surahName = quran.getSurahName(lastReadVerse.surahNumber);
        final juzNumber = quran.getJuzNumber(lastReadVerse.surahNumber, lastReadVerse.verseNumber);
        await prefs.setInt('last_read_surah_number', lastReadVerse.surahNumber);
        await prefs.setString('last_read_surah_name', surahName);
        await prefs.setInt('last_read_verse_number', lastReadVerse.verseNumber);
        await prefs.setInt('last_read_juz_number', juzNumber);
      }
      
      WidgetUpdateService.updateKhatamanWidget();

      if (mounted) {
        setState(() {
          _selectedVerse = null;
        });
      }

      if (widget.slotId == null && !widget.selectForMandiri) {
        await _loadAllActivePrograms();
      } else {
        setState(() {
          _dbSavedAbsoluteIndex = absoluteIndex;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.translate('mushaf_reader_err_save').replaceFirst('{error}', e.toString()),
              style: const TextStyle(color: Colors.white),
            ),
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
                      setState(() {
                        _arabicFontSize = val;
                      });
                      _safePrecomputeOffsets();
                      _saveSettings();
                    },
                  ),
                  
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
                        setState(() {
                          _translationFontSize = val;
                        });
                        _safePrecomputeOffsets();
                        _saveSettings();
                      },
                    ),
                  ],
                  
                  SwitchListTile(
                    title: Text(context.translate('mushaf_reader_show_translation'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                    value: _showTranslation,
                    activeColor: AppTheme.primaryGreen,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setSheetState(() => _showTranslation = val);
                      setState(() {
                        _showTranslation = val;
                      });
                      _safePrecomputeOffsets();
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
    final isSurahMode = widget.initialSurahNumber != null && widget.initialJuzNumber == null;
    String pageTitle = '';
    if (isSurahMode && _activeSurah != null) {
      pageTitle = 'Surah ${quran.getSurahName(_activeSurah!)}';
    } else if (_activeJuz != null) {
      pageTitle = context.translate('mushaf_last_read_juz').replaceFirst('{juz}', _activeJuz!.toString());
    } else if (_activeSurah != null) {
      pageTitle = quran.getSurahName(_activeSurah!);
    }

    final infoSurahNum = isSurahMode ? (_activeSurah ?? 1) : (_currentVisibleSurah ?? (_verses.isNotEmpty ? _verses.first.surahNumber : 1));
    final infoSurahName = quran.getSurahName(infoSurahNum);
    final firstVerseOfInfoSurah = _verses.firstWhere(
      (v) => v.surahNumber == infoSurahNum,
      orElse: () => VerseItem(surahNumber: infoSurahNum, verseNumber: 1),
    );
    final infoJuzNum = quran.getJuzNumber(infoSurahNum, firstVerseOfInfoSurah.verseNumber);
    final infoPlaceOfRev = quran.getPlaceOfRevelation(infoSurahNum) == 'Makkah'
        ? context.translate('mushaf_makkiyah')
        : context.translate('mushaf_madaniyah');
    final infoVerseCount = quran.getVerseCount(infoSurahNum);
    final infoArabicName = quran.getSurahNameArabic(infoSurahNum);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_showSurahInfoTooltip) {
          setState(() {
            _showSurahInfoTooltip = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Container(
          decoration: BoxDecoration(
            gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient,
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final parentWidth = constraints.maxWidth;
                    final parentHeight = constraints.maxHeight;

                    final statusBarHeight = MediaQuery.of(context).padding.top;
                    final minTop = statusBarHeight + 16.0;
                    final maxTop = parentHeight - 72.0;
                    const minLeft = 16.0;
                    final maxLeft = parentWidth - 72.0;

                    _bubbleLeft ??= _minimizeToLeft ? minLeft : maxLeft;
                    _bubbleTop ??= parentHeight - 120.0;
                    _bubbleLeft = _bubbleLeft!.clamp(minLeft, maxLeft);
                    _bubbleTop = _bubbleTop!.clamp(minTop, maxTop);

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: SafeArea(
                            child: Column(
                              children: [
                                _buildCustomAppBar(context, pageTitle),
                                AnimatedCrossFade(
                                  firstChild: _buildStickySurahHeader(isDark),
                                  secondChild: const SizedBox(width: double.infinity),
                                  crossFadeState: !isSurahMode && _scrollOffset > 80 && _currentVisibleSurah != null
                                      ? CrossFadeState.showFirst
                                      : CrossFadeState.showSecond,
                                  duration: const Duration(milliseconds: 200),
                                ),
                                Expanded(
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (ScrollNotification notification) {
                                      if (notification is ScrollUpdateNotification) {
                                        final metrics = notification.metrics;
                                        // Detect overscroll at the bottom (45px past the end)
                                        if (metrics.pixels >= metrics.maxScrollExtent + 45.0) {
                                          if (!_showNextJuzButton && (_activeJuz ?? 1) < 30) {
                                            setState(() {
                                              _showNextJuzButton = true;
                                            });
                                          }
                                        }
                                        // Hide only if they scroll back up significantly (80px above the bottom)
                                        else if (metrics.pixels < metrics.maxScrollExtent - 80.0) {
                                          if (_showNextJuzButton) {
                                            setState(() {
                                              _showNextJuzButton = false;
                                            });
                                          }
                                        }
                                      }
                                      return false;
                                    },
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        top: 12,
                                        bottom: 240, // Bottom padding to prevent content from being covered by floating sync bar
                                      ),
                                      itemCount: _verses.length,
                                      itemBuilder: (context, index) {
                                        final item = _verses[index];
                                        final isSelected = _selectedVerse != null && 
                                            _selectedVerse!.surahNumber == item.surahNumber &&
                                            _selectedVerse!.verseNumber == item.verseNumber;

                                        final showSurahHeader = index == 0 || 
                                            _verses[index - 1].surahNumber != item.surahNumber;

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            if (showSurahHeader && item.surahNumber != 9 && item.surahNumber != 1) _buildBismillah(isDark),
                                            _buildVerseRow(item, index, isSelected, isDark),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: AnimatedSlide(
                              offset: (_isScrolling || _isMinimized) ? const Offset(0, 1.2) : Offset.zero,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: SafeArea(
                                top: false,
                                child: _buildFloatingSyncBar(isDark),
                              ),
                            ),
                          ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          bottom: _showNextJuzButton && (_activeJuz ?? 1) < 30
                              ? (_isMinimized ? 24.0 : 200.0)
                              : -100.0,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: AnimatedOpacity(
                              opacity: _showNextJuzButton && (_activeJuz ?? 1) < 30 ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: _buildNextJuzButton(),
                            ),
                          ),
                        ),
                          if (_isMinimized)
                            Positioned(
                              left: _bubbleLeft,
                              top: _bubbleTop,
                              child: _buildMinimizedBubble(isDark, parentWidth, parentHeight),
                            ),
                          if (_showSurahInfoTooltip)
                            Positioned(
                              top: MediaQuery.of(context).padding.top + 56.0,
                              left: 16,
                              right: 16,
                              child: GestureDetector(
                                onTap: () {}, // Prevent taps inside the card from closing it
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.primaryGreen.withOpacity(isDark ? 0.3 : 0.2),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Surah $infoSurahName (Surah ke-$infoSurahNum)',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurface,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            infoArabicName,
                                            style: const TextStyle(
                                              color: AppTheme.primaryGreen,
                                              fontFamily: 'LPMQ-IsepMisbah',
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Juz $infoJuzNum • $infoPlaceOfRev • $infoVerseCount Ayat',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar(BuildContext context, String pageTitle) {
    return Container(
      height: 56.0,
      width: double.infinity,
      color: Colors.transparent,
      child: NavigationToolbar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        middle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pageTitle,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20.0,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  _showSurahInfoTooltip = !_showSurahInfoTooltip;
                });
              },
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.text_fields_rounded),
          tooltip: context.translate('mushaf_reader_settings_title'),
          onPressed: _showSettingsBottomSheet,
        ),
        centerMiddle: true,
      ),
    );
  }


  Widget _buildStickySurahHeader(bool isDark) {
    if (_currentVisibleSurah == null) return const SizedBox.shrink();
    final name = quran.getSurahName(_currentVisibleSurah!);
    final place = quran.getPlaceOfRevelation(_currentVisibleSurah!) == 'Makkah'
        ? context.translate('mushaf_makkiyah')
        : context.translate('mushaf_madaniyah');
    final totalVerses = quran.getVerseCount(_currentVisibleSurah!);
    final arabic = quran.getSurahNameArabic(_currentVisibleSurah!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.primaryGreen.withOpacity(0.18),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Surah $name ($_currentVisibleSurah)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$place • $totalVerses Ayat',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            arabic,
            style: const TextStyle(
              fontSize: 18,
              fontFamily: 'LPMQ-IsepMisbah',
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBismillah(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        _cleanArabicText(quran.getVerse(1, 1)),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 22,
          fontFamily: 'LPMQ-IsepMisbah',
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryGreen,
        ),
      ),
    );
  }

  Widget _buildVerseRow(VerseItem item, int index, bool isSelected, bool isDark) {
    final settings = Provider.of<SettingsProvider>(context);
    final isEnglish = settings.language == 'en';
    final rawArabicText = quran.getVerse(item.surahNumber, item.verseNumber);
    final arabicText = _cleanArabicText(rawArabicText);
    final translationText = isEnglish
        ? quran.getVerseTranslation(
            item.surahNumber,
            item.verseNumber,
            translation: quran.Translation.enSaheeh,
          )
        : quranIndonesianTranslation['${item.surahNumber}:${item.verseNumber}'] ?? '';

    // Calculate absolute index inside this Juz to compare with DB progress
    final verseJuz = quran.getJuzNumber(item.surahNumber, item.verseNumber);
    final absoluteIndex = _calculateAbsoluteIndex(verseJuz, item.surahNumber, item.verseNumber);
    final isReadInDBSaved = _currentProgram != null && 
        _currentProgram!['juz'] == verseJuz && 
        absoluteIndex <= _dbSavedAbsoluteIndex;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVerse = item;
          _updateSelectedProgramContext();
        });
        _startAutoHideTimer();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item.verseNumber}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
                
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
            
            Text(
              arabicText,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: _arabicFontSize,
                fontFamily: 'LPMQ-IsepMisbah',
                height: 1.8,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            
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

  void _showVerseSelectorDialog(BuildContext context, int targetJuz) {
    final surahMap = quran.getSurahAndVersesFromJuz(targetJuz);
    final List<int> surahNumbers = surahMap.keys.toList();

    int selectedSurah = surahNumbers.first;
    int selectedVerse = surahMap[selectedSurah]![0];

    VerseItem? defaultVerse;
    if (_dbSavedAbsoluteIndex > 0 && _dbSavedAbsoluteIndex <= _verses.length) {
      defaultVerse = _verses[_dbSavedAbsoluteIndex - 1];
    } else if (_verses.isNotEmpty) {
      defaultVerse = _verses.first;
    }

    if (defaultVerse != null && surahNumbers.contains(defaultVerse.surahNumber)) {
      selectedSurah = defaultVerse.surahNumber;
      final bounds = surahMap[selectedSurah]!;
      if (defaultVerse.verseNumber >= bounds[0] && defaultVerse.verseNumber <= bounds[1]) {
        selectedVerse = defaultVerse.verseNumber;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bounds = surahMap[selectedSurah]!;
            final List<int> versesInJuz = List<int>.generate(
              bounds[1] - bounds[0] + 1,
              (index) => bounds[0] + index,
            );

            if (selectedVerse < bounds[0] || selectedVerse > bounds[1]) {
              selectedVerse = bounds[0];
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: AppTheme.primaryGreen.withOpacity(0.2),
                  width: 1,
                ),
              ),
              title: Row(
                children: [
                  const Icon(Icons.menu_book_rounded, color: AppTheme.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.translate('mushaf_reader_dialog_select_verse_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.translate('home_stat_surah'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedSurah,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: surahNumbers.map((sNum) {
                          return DropdownMenuItem<int>(
                            value: sNum,
                            child: Text(
                              'Surah ${quran.getSurahName(sNum)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedSurah = val;
                              final newBounds = surahMap[selectedSurah]!;
                              selectedVerse = newBounds[0];
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.translate('home_stat_ayat'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedVerse,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: versesInJuz.map((vNum) {
                          return DropdownMenuItem<int>(
                            value: vNum,
                            child: Text(
                              'Ayat $vNum',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedVerse = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    context.translate('btn_cancel'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    setState(() {
                      _selectedVerse = VerseItem(
                        surahNumber: selectedSurah,
                        verseNumber: selectedVerse,
                      );
                      _updateSelectedProgramContext();
                    });
                    _startAutoHideTimer();

                    final idx = _verses.indexWhere((v) => 
                      v.surahNumber == selectedSurah && 
                      v.verseNumber == selectedVerse
                    );
                    if (idx != -1) {
                      _scrollToIndex(idx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(context.translate('mushaf_reader_btn_apply')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingSyncBar(bool isDark) {
    final isPreset = widget.slotId != null || widget.selectForMandiri;

    int targetJuz = _activeJuz ?? 1;
    if (_selectedVerse != null) {
      targetJuz = quran.getJuzNumber(_selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
    }

    final matching = isPreset
        ? (_currentProgram != null ? [_currentProgram!] : <Map<String, dynamic>>[])
        : _userPrograms.where((p) => p['juz'] == targetJuz).toList();

    // Determine target Juz

    if (matching.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: Colors.orange.withOpacity(0.3),
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
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.translate('mushaf_reader_no_program_title').replaceFirst('{juz}', targetJuz.toString()),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.grey, size: 20),
                  onPressed: () {
                    setState(() {
                      _isMinimized = true;
                    });
                  },
                  tooltip: 'Minimize',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.translate('mushaf_reader_no_program_desc'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_userPrograms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Text(
                      context.translate('mushaf_reader_switch_program_label'),
                      style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          isExpanded: true,
                          value: null,
                          hint: Text(
                            'Pilih Program Aktif Lain...',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          isDense: true,
                          menuMaxHeight: 300,
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.primaryGreen),
                          dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
                          items: () {
                            final mandiriProgram = _userPrograms.firstWhere(
                              (p) => p['type'] == 'MANDIRI' && p['juz'] == targetJuz,
                              orElse: () => _userPrograms.firstWhere((p) => p['type'] == 'MANDIRI'),
                            );
                            final groupPrograms = _userPrograms.where((p) => p['type'] == 'GROUP').toList();
                            return [mandiriProgram, ...groupPrograms].map((prog) {
                              final isMandiri = prog['type'] == 'MANDIRI';
                              final displayName = isMandiri ? 'Khataman Mandiri' : (prog['name'] as String);
                              return DropdownMenuItem<Map<String, dynamic>>(
                                value: prog,
                                child: Text(
                                  displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList();
                          }(),
                          onChanged: _onProgramChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GroupScreen()),
                      ).then((_) {
                        if (widget.slotId == null && !widget.selectForMandiri) {
                          _loadAllActivePrograms();
                        }
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      context.translate('mushaf_reader_btn_find_group'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _startMandiriForJuz(targetJuz),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      context.translate('mushaf_reader_btn_start_mandiri'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final activeProgram = _currentProgram ?? matching.first;

    int totalAyat = _totalAyatInJuz;
    if (activeProgram['juz'] != _activeJuz) {
      final surahMap = quran.getSurahAndVersesFromJuz(activeProgram['juz']);
      int count = 0;
      surahMap.forEach((surahNum, bounds) {
        count += (bounds[1] - bounds[0] + 1);
      });
      totalAyat = count;
    }

    int selectedAbsoluteIndex = _dbSavedAbsoluteIndex;
    if (_selectedVerse != null) {
      final selJuz = quran.getJuzNumber(_selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
      selectedAbsoluteIndex = _calculateAbsoluteIndex(selJuz, _selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
    }

    final hasProgressToSave = selectedAbsoluteIndex > _dbSavedAbsoluteIndex;
    final progressPercent = totalAyat > 0 
        ? ((_dbSavedAbsoluteIndex / totalAyat) * 100).round() 
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
          // Row 1: Header Row (Progress Title & Action Buttons)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Progress Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.translate('mushaf_reader_juz_progress_text')
                          .replaceFirst('{juz}', activeProgram['juz'].toString())
                          .replaceFirst('{current}', _dbSavedAbsoluteIndex.toString())
                          .replaceFirst('{total}', totalAyat.toString())
                          .replaceFirst('{percent}', progressPercent.toString()),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressPercent / 100.0,
                        minHeight: 6.0,
                        backgroundColor: AppTheme.primaryGreen.withOpacity(0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action Buttons (Tandai Selesai & Minimize)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dbSavedAbsoluteIndex < totalAyat)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _saveProgressToDB(totalAyat),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppTheme.primaryGreen),
                      label: Text(
                        context.translate('mushaf_reader_mark_juz_done'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.grey, size: 18),
                    onPressed: () {
                      setState(() {
                        _isMinimized = true;
                      });
                    },
                    tooltip: 'Minimize',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Program Switcher Row (Full Width)
          if (_userPrograms.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Text(
                    context.translate('mushaf_reader_switch_program_label'),
                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        isExpanded: true,
                        value: () {
                          final currentJuz = activeProgram['juz'] as int;
                          final mandiriProgram = _userPrograms.firstWhere(
                            (p) => p['type'] == 'MANDIRI' && p['juz'] == currentJuz,
                            orElse: () => _userPrograms.firstWhere((p) => p['type'] == 'MANDIRI'),
                          );
                          final groupPrograms = _userPrograms.where((p) => p['type'] == 'GROUP').toList();
                          final list = [mandiriProgram, ...groupPrograms];
                          return list.any((p) => p['id'] == activeProgram['id'])
                              ? list.firstWhere((p) => p['id'] == activeProgram['id'])
                              : mandiriProgram;
                        }(),
                        isDense: true,
                        menuMaxHeight: 300,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.primaryGreen),
                        dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
                        items: () {
                          final currentJuz = activeProgram['juz'] as int;
                          final mandiriProgram = _userPrograms.firstWhere(
                            (p) => p['type'] == 'MANDIRI' && p['juz'] == currentJuz,
                            orElse: () => _userPrograms.firstWhere((p) => p['type'] == 'MANDIRI'),
                          );
                          final groupPrograms = _userPrograms.where((p) => p['type'] == 'GROUP').toList();
                          return [mandiriProgram, ...groupPrograms].map((prog) {
                            final isMandiri = prog['type'] == 'MANDIRI';
                            final displayName = isMandiri ? 'Khataman Mandiri' : (prog['name'] as String);
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: prog,
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            );
                          }).toList();
                        }(),
                        onChanged: _onProgramChanged,
                      ),
                    ),
                  ),
                  if (activeProgram['type'] == 'MANDIRI') ...[
                    const SizedBox(width: 12),
                    const Text(
                      'Juz:',
                      style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: activeProgram['juz'] as int,
                        isDense: true,
                        menuMaxHeight: 300,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.primaryGreen),
                        dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
                        items: List.generate(30, (i) => i + 1).map((juzNum) {
                          return DropdownMenuItem<int>(
                            value: juzNum,
                            child: Text(
                              '$juzNum',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (newJuz) {
                          if (newJuz != null) {
                            final newMandiriProg = _userPrograms.firstWhere(
                              (p) => p['type'] == 'MANDIRI' && p['juz'] == newJuz,
                            );
                            _onProgramChanged(newMandiriProg);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            Text(
              activeProgram['name'] as String,
              style: const TextStyle(fontSize: 11, color: AppTheme.primaryGreen, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),

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
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedVerse = null;
                        _updateSelectedProgramContext();
                      });
                    },
                    tooltip: context.translate('btn_cancel'),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 8),
                  ),
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
          ] else if (_selectedVerse != null && !hasProgressToSave) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedVerse = null;
                        _updateSelectedProgramContext();
                      });
                    },
                    tooltip: context.translate('btn_cancel'),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 8),
                  ),
                  const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryGreen, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Surah ${quran.getSurahName(_selectedVerse!.surahNumber)} ayat ${_selectedVerse!.verseNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.translate('mushaf_reader_err_reverse'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppTheme.primaryGreen, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.translate('mushaf_reader_select_verse_tip'),
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _showVerseSelectorDialog(context, targetJuz),
                    icon: const Icon(Icons.menu_book_rounded, size: 16),
                    label: Text(
                      context.translate('mushaf_reader_btn_select_verse'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMinimizedBubble(bool isDark, double parentWidth, double parentHeight) {
    // Get active program progress or default progress
    final isPreset = widget.slotId != null || widget.selectForMandiri;
    int targetJuz = _activeJuz ?? 1;
    if (_selectedVerse != null) {
      targetJuz = quran.getJuzNumber(_selectedVerse!.surahNumber, _selectedVerse!.verseNumber);
    }
    final matching = isPreset
        ? (_currentProgram != null ? [_currentProgram!] : <Map<String, dynamic>>[])
        : _userPrograms.where((p) => p['juz'] == targetJuz).toList();

    double progressPercent = 0.0;
    bool hasActive = false;

    if (matching.isNotEmpty) {
      hasActive = true;
      final activeProgram = _currentProgram ?? matching.first;
      int totalAyat = _totalAyatInJuz;
      if (activeProgram['juz'] != _activeJuz) {
        final surahMap = quran.getSurahAndVersesFromJuz(activeProgram['juz']);
        int count = 0;
        surahMap.forEach((surahNum, bounds) {
          count += (bounds[1] - bounds[0] + 1);
        });
        totalAyat = count;
      }
      final currentSaved = activeProgram['ayat_terakhir'] as int? ?? 0;
      progressPercent = totalAyat > 0 ? (currentSaved / totalAyat) : 0.0;
    }

    final statusBarHeight = MediaQuery.of(context).padding.top;
    final minTop = statusBarHeight + 16.0;
    final maxTop = parentHeight - 72.0;
    const minLeft = 16.0;
    final maxLeft = parentWidth - 72.0;

    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _bubbleLeft = (_bubbleLeft! + details.delta.dx).clamp(minLeft, maxLeft);
          _bubbleTop = (_bubbleTop! + details.delta.dy).clamp(minTop, maxTop);
        });
      },
      onPanEnd: (details) {
        // Keep the bubble exactly where it was dropped (including the middle),
        // but keep track of which side of the screen it is on for initial position context.
        setState(() {
          _minimizeToLeft = _bubbleLeft! < (parentWidth - 56.0) / 2;
        });
      },
      onTap: () {
        setState(() {
          _isMinimized = false;
        });
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : AppTheme.primaryGreen.withOpacity(0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark 
                  ? AppTheme.primaryGreen.withOpacity(0.35) 
                  : Colors.black.withOpacity(0.12),
              blurRadius: isDark ? 16 : 12,
              spreadRadius: isDark ? 2 : 0,
              offset: Offset(0, isDark ? 2 : 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (hasActive)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: CircularProgressIndicator(
                    value: progressPercent,
                    strokeWidth: 3.5,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                    backgroundColor: isDark ? Colors.white10 : AppTheme.primaryGreen.withOpacity(0.12),
                  ),
                ),
              ),
            if (hasActive)
              Text(
                '${(progressPercent * 100).round()}%',
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.primaryGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              Icon(
                Icons.menu_book_rounded,
                color: isDark ? Colors.white : AppTheme.primaryGreen,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  void _proceedToNextJuz() {
    if ((_activeJuz ?? 1) >= 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Anda sudah berada di akhir Juz 30!', style: TextStyle(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    
    final int nextJuz = (_activeJuz ?? 1) + 1;
    
    setState(() {
      _showNextJuzButton = false;
    });

    // If the active program is MANDIRI, switch to the next Juz Mandiri program
    if (_currentProgram != null && _currentProgram!['type'] == 'MANDIRI') {
      final nextMandiriProg = _userPrograms.firstWhere(
        (p) => p['type'] == 'MANDIRI' && p['juz'] == nextJuz,
        orElse: () => {
          'type': 'MANDIRI',
          'id': 'mandiri_$nextJuz',
          'juz': nextJuz,
          'name': 'Khataman Mandiri (Juz $nextJuz)',
          'ayat_terakhir': 0,
        },
      );
      _onProgramChanged(nextMandiriProg);
    } else {
      // Otherwise, just change the active Juz
      _changeJuz(nextJuz);
    }
    
    // Scroll list back to top
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget _buildNextJuzButton() {
    final nextJuz = (_activeJuz ?? 1) + 1;
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
        onPressed: _proceedToNextJuz,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: Text(
          'Lanjut ke Juz $nextJuz',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

}

class DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.gap = 4.0,
    this.dash = 6.0,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path path = Path();
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    ));

    final Path dashedPath = Path();
    double distance = 0.0;
    for (final PathMetric measurePath in path.computeMetrics()) {
      while (distance < measurePath.length) {
        dashedPath.addPath(
          measurePath.extractPath(distance, distance + dash),
          Offset.zero,
        );
        distance += dash + gap;
      }
      distance = 0.0;
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(DashedRectPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      gap != oldDelegate.gap ||
      dash != oldDelegate.dash ||
      radius != oldDelegate.radius;
}
