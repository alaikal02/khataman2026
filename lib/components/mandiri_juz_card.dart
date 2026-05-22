import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import '../theme/app_theme.dart';

class MandiriJuzCard extends StatefulWidget {
  final int juzNumber;
  final int lastAyat;
  final bool isComplete;
  final Function(int absoluteIndex, int totalAyat) onSave;

  const MandiriJuzCard({
    Key? key,
    required this.juzNumber,
    required this.lastAyat,
    required this.isComplete,
    required this.onSave,
  }) : super(key: key);

  @override
  State<MandiriJuzCard> createState() => _MandiriJuzCardState();
}

class _MandiriJuzCardState extends State<MandiriJuzCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late TextEditingController _ayatController;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  int _totalAyat = 0;
  Map<int, List<int>> _surahsInJuz = {};
  int? _selectedSurah;

  @override
  void initState() {
    super.initState();
    _ayatController = TextEditingController();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    _initQuranData();
  }

  @override
  void didUpdateWidget(covariant MandiriJuzCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jika data dari parent berubah, kita re-inisialisasi
    if (oldWidget.lastAyat != widget.lastAyat || oldWidget.isComplete != widget.isComplete) {
      _initQuranData();
    }
  }

  void _initQuranData() {
    _surahsInJuz = quran.getSurahAndVersesFromJuz(widget.juzNumber);
    
    _totalAyat = 0;
    _surahsInJuz.forEach((surah, bounds) {
      _totalAyat += (bounds[1] - bounds[0] + 1);
    });

    int absoluteIndex = widget.lastAyat;
    
    if (absoluteIndex == 0) {
      _selectedSurah = _surahsInJuz.keys.first;
      _ayatController.text = '';
    } else {
      int tempAbsolute = absoluteIndex;
      for (var entry in _surahsInJuz.entries) {
        int surah = entry.key;
        int start = entry.value[0];
        int end = entry.value[1];
        int ayahsInThisSurah = end - start + 1;
        
        if (tempAbsolute <= ayahsInThisSurah) {
          _selectedSurah = surah;
          _ayatController.text = (start + tempAbsolute - 1).toString();
          break;
        } else {
          tempAbsolute -= ayahsInThisSurah;
        }
      }
      if (_selectedSurah == null) {
        _selectedSurah = _surahsInJuz.keys.last;
        _ayatController.text = _surahsInJuz[_selectedSurah]![1].toString();
      }
    }
  }

  @override
  void dispose() {
    _ayatController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  void _handleSave() {
    final inputAyah = int.tryParse(_ayatController.text);
    if (inputAyah == null || inputAyah < 0 || _selectedSurah == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Input ayat tidak valid'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final bounds = _surahsInJuz[_selectedSurah]!;
    if (inputAyah < bounds[0] || inputAyah > bounds[1]) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ayat harus antara ${bounds[0]} dan ${bounds[1]} untuk surat ini'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    int absoluteIndex = 0;
    for (var entry in _surahsInJuz.entries) {
      int surah = entry.key;
      int start = entry.value[0];
      int end = entry.value[1];
      
      if (surah == _selectedSurah) {
        absoluteIndex += (inputAyah - start + 1);
        break;
      } else {
        absoluteIndex += (end - start + 1);
      }
    }

    // Panggil callback parent (di mana db akan diupdate)
    widget.onSave(absoluteIndex, _totalAyat);
    
    if (absoluteIndex == _totalAyat) {
      setState(() => _expanded = false);
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = widget.isComplete;
    final percentage = _totalAyat == 0 ? 0 : ((widget.lastAyat / _totalAyat) * 100).round();
    final pClamp = percentage > 100 ? 100 : percentage;

    String lastPositionString = 'Belum dibaca';
    if (widget.lastAyat > 0 && _surahsInJuz.isNotEmpty) {
      int tempAbsolute = widget.lastAyat;
      for (var entry in _surahsInJuz.entries) {
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

    // Nama surat awal untuk UI
    String surahAwal = _surahsInJuz.isNotEmpty ? quran.getSurahName(_surahsInJuz.keys.first) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppTheme.primaryGreen.withOpacity(0.5)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        children: [
          // Collapsed Header
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _toggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Juz Number Badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isComplete
                          ? AppTheme.primaryGreen.withOpacity(0.2)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: isComplete
                          ? const Icon(Icons.check_rounded, color: AppTheme.primaryGreen, size: 22)
                          : Text(
                              '${widget.juzNumber}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Juz Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Juz ${widget.juzNumber}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          surahAwal,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: isComplete ? 1.0 : (widget.lastAyat / _totalAyat),
                            minHeight: 5,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isComplete ? AppTheme.primaryGreen : AppTheme.accentTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Percentage + Arrow
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isComplete ? '100%' : '$pClamp%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 22),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Expanded Content
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  const SizedBox(height: 14),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.menu_book_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Juz ini berisi ${_surahsInJuz.length} Surat  •  Total: $_totalAyat ayat',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  if (!isComplete) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Posisi terakhir: $lastPositionString',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    // Dropdown Surat
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedSurah,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryGreen),
                          items: _surahsInJuz.entries.map((entry) {
                            final bounds = entry.value;
                            return DropdownMenuItem<int>(
                              value: entry.key,
                              child: Text(
                                '${quran.getSurahName(entry.key)} (Ayat ${bounds[0]} - ${bounds[1]})',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedSurah = val;
                              _ayatController.text = ''; // Clear ayat when surah changes
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ayatController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: _selectedSurah != null 
                            ? 'Ayat terakhir (Min ${_surahsInJuz[_selectedSurah]![0]}, Max ${_surahsInJuz[_selectedSurah]![1]})'
                            : 'Pilih surat dulu',
                      ),
                      enabled: _selectedSurah != null,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Simpan Progres', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text('✅ Juz ini sudah Anda selesaikan. Alhamdulillah!',
                      style: TextStyle(color: AppTheme.primaryGreen, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
