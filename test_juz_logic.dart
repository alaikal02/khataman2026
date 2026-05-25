import 'package:quran/quran.dart' as quran;

void main() {
  print('Starting Juz progress simulation test...');
  for (int juz = 1; juz <= 30; juz++) {
    final surahsInJuz = quran.getSurahAndVersesFromJuz(juz);
    int totalAyat = 0;
    surahsInJuz.forEach((surah, bounds) {
      totalAyat += (bounds[1] - bounds[0] + 1);
    });
    print('Juz $juz: Total Ayat = $totalAyat, Surahs = ${surahsInJuz.keys.toList()}');

    // Test all absolute indices from 0 to totalAyat + 5
    for (int absoluteIndex = 0; absoluteIndex <= totalAyat + 5; absoluteIndex++) {
      try {
        // Test _initQuranData logic
        int? selectedSurah;
        String ayatText = '';
        
        if (absoluteIndex == 0) {
          selectedSurah = surahsInJuz.keys.first;
          ayatText = '';
        } else {
          int tempAbsolute = absoluteIndex;
          for (var entry in surahsInJuz.entries) {
            int surah = entry.key;
            int start = entry.value[0];
            int end = entry.value[1];
            int ayahsInThisSurah = end - start + 1;
            
            if (tempAbsolute <= ayahsInThisSurah) {
              selectedSurah = surah;
              ayatText = (start + tempAbsolute - 1).toString();
              break;
            } else {
              tempAbsolute -= ayahsInThisSurah;
            }
          }
          if (selectedSurah == null) {
            selectedSurah = surahsInJuz.keys.last;
            ayatText = surahsInJuz[selectedSurah]![1].toString();
          }
        }

        // Test lastPositionString logic
        String lastPositionString = 'Belum dibaca';
        if (absoluteIndex > 0 && surahsInJuz.isNotEmpty) {
          int tempAbsolute = absoluteIndex;
          for (var entry in surahsInJuz.entries) {
            int surah = entry.key;
            int start = entry.value[0];
            int end = entry.value[1];
            int ayahsInThisSurah = end - start + 1;
            
            if (tempAbsolute <= ayahsInThisSurah) {
              int ayatNum = start + tempAbsolute - 1;
              lastPositionString = '${quran.getSurahName(surah)}: $ayatNum';
              break;
            } else {
              tempAbsolute -= ayahsInThisSurah;
            }
          }
        }
      } catch (e, stack) {
        print('FAILED on Juz $juz, absoluteIndex $absoluteIndex!');
        print('Error: $e');
        print(stack);
        return;
      }
    }
  }
  print('SUCCESS: All 30 Juz and absolute indices simulated perfectly without errors!');
}
