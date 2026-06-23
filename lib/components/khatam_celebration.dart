import 'package:flutter/material.dart';
import '../utils/localization.dart';
import '../theme/app_theme.dart';

/// Membuka bottom sheet premium doa khatam Al-Quran.
/// Komponen ini reusable dan dapat dipanggil dari mana saja.
void showDoaKhatamBottomSheet(
  BuildContext context, {
  VoidCallback? onConfirmCompletion,
  String? confirmationMessage,
}) {
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
                  context.translate('doa_title'),
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
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                onConfirmCompletion != null
                    ? 24
                    : 24 + MediaQuery.of(context).padding.bottom,
              ),
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
                      fontFamily: 'LPMQ-IsepMisbah',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  context.translate('doa_transliteration_header'),
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
                  context.translate('doa_translation_header'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.translate('doa_translation_text'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          if (onConfirmCompletion != null) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 12 + MediaQuery.of(context).padding.bottom),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text(
                          context.translate('doa_confirm_complete_title'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Text(
                          confirmationMessage ?? context.translate('doa_confirm_complete_body'),
                          style: const TextStyle(height: 1.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            child: Text(
                              context.translate('btn_cancel'),
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(dialogCtx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            child: Text(context.translate('doa_btn_yes_complete'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      Navigator.pop(ctx);
                      onConfirmCompletion();
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    context.translate('doa_btn_read_already'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Card ucapan selamat khatam 30 Juz yang elegan dan reusable.
class CongratulatoryCard extends StatelessWidget {
  final VoidCallback onReset;
  final String? title;
  final String? description;
  final String? resetLabel;
  final bool showResetButton;
  final VoidCallback? onDoaKhatam;

  const CongratulatoryCard({
    Key? key,
    required this.onReset,
    this.title,
    this.description,
    this.resetLabel,
    this.showResetButton = true,
    this.onDoaKhatam,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title ?? context.translate('congrats_title');
    final resolvedDescription = description ?? context.translate('congrats_desc');
    final resolvedResetLabel = resetLabel ?? context.translate('congrats_btn_reset');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBgGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFFE5A93C), Color(0xFFC5891C), Color(0xFF9E680E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFFEF9E7), Color(0xFFFDF2D5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    final borderColor = isDark ? Colors.white.withOpacity(0.2) : AppTheme.accentGold.withOpacity(0.25);
    final titleColor = isDark ? Colors.white : const Color(0xFF5C4008);
    final descriptionColor = isDark ? Colors.white70 : const Color(0xFF8B6508).withOpacity(0.85);

    final shadow = [
      BoxShadow(
        color: isDark ? const Color(0xFFC5891C).withOpacity(0.3) : AppTheme.accentGold.withOpacity(0.06),
        blurRadius: 15,
        offset: const Offset(0, 5),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: cardBgGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: shadow,
        border: Border.all(color: borderColor, width: isDark ? 1 : 0.8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_rounded, 
            color: isDark ? AppTheme.accentGold : const Color(0xFF8B6508), 
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            resolvedTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: titleColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            resolvedDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12, 
              color: descriptionColor, 
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (showResetButton) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    resolvedResetLabel, 
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : const Color(0xFFC5891C),
                  foregroundColor: isDark ? const Color(0xFF9E680E) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  if (onDoaKhatam != null) {
                    onDoaKhatam!();
                  } else {
                    showDoaKhatamBottomSheet(context);
                  }
                },
                icon: Icon(
                  Icons.menu_book_rounded, 
                  size: 16, 
                  color: isDark ? Colors.white70 : const Color(0xFF8B6508),
                ),
                label: Text(
                  context.translate('congrats_btn_doa'), 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF8B6508),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (onDoaKhatam != null) {
                    onDoaKhatam!();
                  } else {
                    showDoaKhatamBottomSheet(context);
                  }
                },
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: Text(
                  context.translate('congrats_btn_doa'), 
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : const Color(0xFFC5891C),
                  foregroundColor: isDark ? const Color(0xFF9E680E) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
