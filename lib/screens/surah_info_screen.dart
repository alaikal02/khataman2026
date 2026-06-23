import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import 'package:provider/provider.dart';
import '../data/surah_info_data.dart';
import '../providers/settings_provider.dart';
import '../utils/localization.dart';
import 'surah_detail_screen.dart';
import '../theme/app_theme.dart';

class SurahInfoScreen extends StatefulWidget {
  const SurahInfoScreen({Key? key}) : super(key: key);

  @override
  State<SurahInfoScreen> createState() => _SurahInfoScreenState();
}

class _SurahInfoScreenState extends State<SurahInfoScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<SurahInfo> _allSurah = [];
  List<SurahInfo> _filteredSurah = [];

  @override
  void initState() {
    super.initState();
    _allSurah = SurahInfoRepository.getAllSurahInfo();
    _filteredSurah = _allSurah;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSurah = _allSurah;
      } else {
        _filteredSurah = _allSurah.where((surah) {
          final matchName = surah.name.toLowerCase().contains(query);
          final matchTranslation = surah.translation.toLowerCase().contains(query);
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
        title: Text(context.translate('surah_info_title')),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Search Field Container
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: context.translate('surah_info_search_hint'),
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
              // Surah List
              Expanded(
                child: _filteredSurah.isEmpty
                    ? Center(
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
                              context.translate('surah_info_empty_search'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
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
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SurahDetailScreen(surahInfo: surah),
                                  ),
                                );
                              },
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryGreen.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${surah.number}',
                                    style: const TextStyle(
                                      fontSize: 13,
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
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    arabicName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryGreen,
                                      fontFamily: 'LPMQ-IsepMisbah',
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${surah.translation} • $place • $versesText',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
