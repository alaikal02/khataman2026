import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quran/quran.dart' as quran;
import 'package:provider/provider.dart';
import '../data/surah_info_data.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../utils/localization.dart';
import 'mushaf_reader_screen.dart';

class MushafListScreen extends StatefulWidget {
  final bool selectForMandiri;
  final String? selectForGroupId;
  final int? initialJuz;

  const MushafListScreen({
    Key? key,
    this.selectForMandiri = false,
    this.selectForGroupId,
    this.initialJuz,
  }) : super(key: key);

  @override
  State<MushafListScreen> createState() => _MushafListScreenState();
}

class _MushafListScreenState extends State<MushafListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<SurahInfo> _allSurah = [];
  List<SurahInfo> _filteredSurah = [];

  // Last Read State
  int? _lastReadSurahNum;
  String? _lastReadSurahName;
  int? _lastReadVerseNum;
  int? _lastReadJuzNum;

  @override
  void initState() {
    super.initState();
    _allSurah = SurahInfoRepository.getAllSurahInfo();
    _filteredSurah = _allSurah;
    _searchController.addListener(_onSearchChanged);
    
    // Switch to Juz tab if initialJuz is provided
    _tabController = TabController(
      length: 2, 
      vsync: this,
      initialIndex: widget.initialJuz != null ? 1 : 0,
    );

    _loadLastRead();
  }

  Future<void> _loadLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastReadSurahNum = prefs.getInt('last_read_surah_number');
        _lastReadSurahName = prefs.getString('last_read_surah_name');
        _lastReadVerseNum = prefs.getInt('last_read_verse_number');
        _lastReadJuzNum = prefs.getInt('last_read_juz_number');
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    final isEnglish = Provider.of<SettingsProvider>(context, listen: false).language == 'en';
    setState(() {
      if (query.isEmpty) {
        _filteredSurah = _allSurah;
      } else {
        _filteredSurah = _allSurah.where((surah) {
          final matchName = surah.name.toLowerCase().contains(query);
          final translationText = isEnglish 
              ? quran.getSurahNameEnglish(surah.number) 
              : surah.translation;
          final matchTranslation = translationText.toLowerCase().contains(query);
          final matchNumber = surah.number.toString() == query;
          return matchName || matchTranslation || matchNumber;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<SettingsProvider>(context); // Listen to settings changes
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.translate('mushaf_title')),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryGreen,
          labelColor: AppTheme.primaryGreen,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: context.translate('mushaf_tab_surah')),
            Tab(text: context.translate('mushaf_tab_juz')),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Resume Last Read Banner (if exists)
              if (_lastReadSurahNum != null) _buildLastReadBanner(isDark),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSurahTab(isDark),
                    _buildJuzTab(isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastReadBanner(bool isDark) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MushafReaderScreen(
              initialSurahNumber: _lastReadSurahNum,
              initialVerseNumber: _lastReadVerseNum,
              initialJuzNumber: _lastReadJuzNum,
              selectForMandiri: widget.selectForMandiri,
              selectForGroupId: widget.selectForGroupId,
            ),
          ),
        ).then((_) => _loadLastRead());
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF009688), Color(0xFF004D40)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.translate('mushaf_last_read_header'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastReadSurahName != null
                        ? context.translate('mushaf_last_read_surah_ayat')
                            .replaceFirst('{surah}', _lastReadSurahName!)
                            .replaceFirst('{ayat}', _lastReadVerseNum.toString())
                        : context.translate('mushaf_last_read_juz')
                            .replaceFirst('{juz}', _lastReadJuzNum.toString()),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              context.translate('mushaf_last_read_continue'),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.accentGold,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.accentGold, size: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSurahTab(bool isDark) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: context.translate('mushaf_search_hint'),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryGreen),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
        ),

        // List
        Expanded(
          child: _filteredSurah.isEmpty
              ? _buildEmptySearch()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _filteredSurah.length,
                  itemBuilder: (context, index) {
                    final surah = _filteredSurah[index];
                    final totalVerses = quran.getVerseCount(surah.number);
                    final place = quran.getPlaceOfRevelation(surah.number) == 'Makkah'
                        ? context.translate('mushaf_makkiyah')
                        : context.translate('mushaf_madaniyah');
                    final versesText = context.translate('mushaf_verses_count')
                        .replaceFirst('{count}', totalVerses.toString());
                    final arabicName = quran.getSurahNameArabic(surah.number);
                    final isEnglish = Provider.of<SettingsProvider>(context, listen: false).language == 'en';
                    final surahTranslation = isEnglish 
                        ? quran.getSurahNameEnglish(surah.number) 
                        : surah.translation;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark 
                              ? AppTheme.primaryGreen.withOpacity(0.2) 
                              : AppTheme.primaryGreen.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MushafReaderScreen(
                                initialSurahNumber: surah.number,
                                selectForMandiri: widget.selectForMandiri,
                                selectForGroupId: widget.selectForGroupId,
                              ),
                            ),
                          ).then((_) => _loadLastRead());
                        },
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryGreen.withOpacity(0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${surah.number}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                surah.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              arabicName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryGreen,
                                fontFamily: 'LPMQ-IsepMisbah',
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$surahTranslation • $place • $versesText',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildJuzTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 30,
      itemBuilder: (context, index) {
        final juzNum = index + 1;
        // Find surah and verses bounds in this juz using quran package
        final surahMap = quran.getSurahAndVersesFromJuz(juzNum);
        String detailsText = '';
        if (surahMap.isNotEmpty) {
          final firstSurah = surahMap.keys.first;
          final lastSurah = surahMap.keys.last;
          final firstSurahName = quran.getSurahName(firstSurah);
          final lastSurahName = quran.getSurahName(lastSurah);
          
          if (firstSurah == lastSurah) {
            detailsText = context.translate('mushaf_juz_detail_single')
                .replaceFirst('{surah}', firstSurahName)
                .replaceFirst('{start}', surahMap[firstSurah]![0].toString())
                .replaceFirst('{end}', surahMap[firstSurah]![1].toString());
          } else {
            detailsText = context.translate('mushaf_juz_detail_multi')
                .replaceFirst('{start}', firstSurahName)
                .replaceFirst('{end}', lastSurahName);
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark 
                  ? AppTheme.primaryGreen.withOpacity(0.2) 
                  : AppTheme.primaryGreen.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MushafReaderScreen(
                    initialJuzNumber: juzNum,
                    selectForMandiri: widget.selectForMandiri,
                    selectForGroupId: widget.selectForGroupId,
                  ),
                ),
              ).then((_) => _loadLastRead());
            },
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryGreen.withOpacity(0.3),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: Text(
                  '$juzNum',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ),
            ),
            title: Text(
              context.translate('mushaf_last_read_juz').replaceFirst('{juz}', juzNum.toString()),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detailsText,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptySearch() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.translate('mushaf_empty_search'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
