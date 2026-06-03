import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import '../data/surah_info_data.dart';
import '../theme/app_theme.dart';

class SurahDetailScreen extends StatelessWidget {
  final SurahInfo surahInfo;

  const SurahDetailScreen({
    Key? key,
    required this.surahInfo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final arabicName = quran.getSurahNameArabic(surahInfo.number);
    final place = quran.getPlaceOfRevelation(surahInfo.number) == 'Makkah' ? 'Makkiyah' : 'Madaniyah';
    final totalVerses = quran.getVerseCount(surahInfo.number);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(surahInfo.name),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Premium Top Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2A5298).withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        arabicName,
                        style: const TextStyle(
                          fontSize: 32,
                          fontFamily: 'sans-serif',
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Surah Ke-${surahInfo.number} • $place • $totalVerses Ayat',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Arti: ${surahInfo.translation}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.accentGold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section 1: Arti & Makna
                _buildInfoCard(
                  context: context,
                  title: 'Arti & Makna',
                  icon: Icons.menu_book_rounded,
                  iconColor: AppTheme.primaryGreen,
                  content: surahInfo.makna,
                ),
                const SizedBox(height: 18),

                // Section 2: Asbabun Nuzul / Hadis
                _buildInfoCard(
                  context: context,
                  title: 'Hadis & Asbabun Nuzul',
                  subtitle: 'Mengapa surah ini diturunkan',
                  icon: Icons.history_edu_rounded,
                  iconColor: AppTheme.accentGold,
                  content: surahInfo.asbabunNuzul,
                ),
                const SizedBox(height: 18),

                // Section 3: Dampak & Keutamaan
                _buildInfoCard(
                  context: context,
                  title: 'Dampak & Keutamaan',
                  subtitle: 'Manfaat & faedah pengamalan',
                  icon: Icons.favorite_rounded,
                  iconColor: AppTheme.accentTeal,
                  content: surahInfo.dampak,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
    required String content,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark 
              ? AppTheme.primaryGreen.withOpacity(0.2) 
              : AppTheme.primaryGreen.withOpacity(0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }
}
