import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Membuka bottom sheet premium doa khatam Al-Quran.
/// Komponen ini reusable dan dapat dipanggil dari mana saja.
void showDoaKhatamBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Doa Khatam Al-Quran',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.15)),
                  ),
                  child: const Text(
                    'اللَّهُمَّ ارْحَمْنِي بِالْقُرْآنِ، وَاجْعَلْهُ لِي إِمَامًا وَنُورًا وَهُدًى وَرَحْمَةً، اللَّهُمَّ ذَكِّرْنِي مِنْهُ مَا نَسِيتُ، وَعَلِّمْنِي مِنْهُ مَا جَهِلْتُ، وَارْزُقْنِي تِلَاوَتَهُ آنَاءَ اللَّيْلِ وَأَطْرَافَ النَّهَارِ، وَاجْعَلْهُ لِي حُجَّةً يَا رَبَّ الْعَالَمِينَ',
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.8,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'serif',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Transliterasi:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Allahummarhamni bil quran. Wajalhu li imaman wa nuran wa hudan wa rahmah. Allahumma dzakkirni minhu ma nasitu wa allimni minhu ma jahiltu warzuqni tilawatahu anallaili wa athrafannahar wajalhu li hujjatan ya rabbal alamin.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Arti / Terjemahan:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '“Ya Allah, rahmatilah aku dengan Al-Quran. Jadikanlah ia bagiku sebagai pemimpin, cahaya, petunjuk, dan rahmat. Ya Allah, ingatkanlah aku atas apa yang terlupakan darinya, ajarilah aku atas apa yang belum aku ketahui darinya, dan berikanlah aku rezeki untuk membacanya di malam hari dan ujung-ujung siang. Dan jadikanlah ia bagiku sebagai pembela, wahai Tuhan semesta alam.”',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Card ucapan selamat khatam 30 Juz yang elegan dan reusable.
class CongratulatoryCard extends StatelessWidget {
  final VoidCallback onReset;
  final String title;
  final String description;
  final String resetLabel;
  final bool showResetButton;

  const CongratulatoryCard({
    Key? key,
    required this.onReset,
    this.title = 'Maa Syaa Allah, Barakallah! 🎉',
    this.description = 'Selamat! Anda telah menyelesaikan khataman 30 Juz Al-Quran.',
    this.resetLabel = 'Reset Progres',
    this.showResetButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE5A93C), Color(0xFFC5891C), Color(0xFF9E680E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC5891C).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, color: AppTheme.accentGold, size: 44),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDoaKhatamBottomSheet(context),
                  icon: const Icon(Icons.menu_book_rounded, size: 16, color: Colors.white),
                  label: const Text('Doa Khatam', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (showResetButton) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: Text(resetLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF9E680E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
