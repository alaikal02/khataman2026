import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

class SlotCard extends StatefulWidget {
  final Map<String, dynamic> slot;
  final bool isOwned;
  final Function(int) onRelease;
  final VoidCallback? onProgressUpdated; // ← Callback baru
  final String? memberName;
  final String? groupId;
  final String? groupName;

  const SlotCard({
    Key? key,
    required this.slot,
    required this.isOwned,
    required this.onRelease,
    this.onProgressUpdated,
    this.memberName,
    this.groupId,
    this.groupName,
  }) : super(key: key);

  @override
  State<SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<SlotCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late TextEditingController _ayatController;
  final _supabase = Supabase.instance.client;
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

  void _initQuranData() {
    final juzNumber = widget.slot['nomor_juz'] as int;
    _surahsInJuz = quran.getSurahAndVersesFromJuz(juzNumber);
    
    _totalAyat = 0;
    _surahsInJuz.forEach((surah, bounds) {
      _totalAyat += (bounds[1] - bounds[0] + 1);
    });

    // Tentukan Surat dan Ayat yang dipilih berdasarkan index absolut
    int absoluteIndex = widget.slot['ayat_terakhir_input'] as int? ?? 0;
    
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

  Future<void> _saveProgress() async {
    final inputAyah = int.tryParse(_ayatController.text);
    if (inputAyah == null || inputAyah < 0 || _selectedSurah == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Input ayat tidak valid'), backgroundColor: Colors.redAccent),
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

    // Hitung index absolut
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

    final isComplete = absoluteIndex == _totalAyat;

    try {
      await _supabase.from('slot_khataman').update({
        'ayat_terakhir_input': absoluteIndex,
        'status_checklist': isComplete,
      }).eq('id_slot', widget.slot['id_slot']);

      // Kirim notifikasi jika Juz selesai
      if (isComplete && widget.groupId != null) {
        try {
          final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
              _supabase.auth.currentUser?.email?.split('@')[0] ??
              'Seseorang';
          final gName = widget.groupName ?? 'Grup';

          await NotificationService.sendToGroup(
            groupId: widget.groupId!,
            type: 'JUZ_COMPLETED',
            title: 'Juz Selesai Dibaca',
            body: '$senderName telah menyelesaikan Juz ${widget.slot['nomor_juz']} di grup "$gName"',
            excludeUserId: _supabase.auth.currentUser?.id,
          );
        } catch (notifErr) {
          print('Error sending juz completed notification: $notifErr');
        }
      }

      if (mounted) {
        // Memperbarui state lokal agar UI langsung berubah tanpa harus muat ulang halaman
        setState(() {
          widget.slot['ayat_terakhir_input'] = absoluteIndex;
          widget.slot['status_checklist'] = isComplete;
          
          if (isComplete) {
            _expanded = false;
            _expandController.reverse();
          }
        });

        // Beritahu parent (GroupDetailScreen) untuk merender ulang persentase total
        widget.onProgressUpdated?.call();

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isComplete ? '✅ Juz ${widget.slot['nomor_juz']} selesai! Alhamdulillah!' : 'Progres disimpan'),
          backgroundColor: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan progres'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _confirmRelease() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Lepas Juz?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Progres Juz ${widget.slot['nomor_juz']} Anda akan direset dan slot ini akan tersedia untuk anggota lain.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('Ya, Lepas Juz'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRelease(widget.slot['id_slot']);
    }
  }

  Future<void> _confirmMarkFinished() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Selesaikan Juz?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Apakah Anda yakin telah membaca seluruh isi Juz ${widget.slot['nomor_juz']} ini? Progres akan otomatis menjadi 100%.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Belum'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGreen),
            child: Text('Ya, Selesai'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _markAsFinished(true);
    }
  }

  Future<void> _markAsFinished(bool isFinished) async {
    try {
      final absoluteIndex = isFinished ? _totalAyat : 0;
      await _supabase.from('slot_khataman').update({
        'ayat_terakhir_input': absoluteIndex,
        'status_checklist': isFinished,
      }).eq('id_slot', widget.slot['id_slot']);

      // Kirim notifikasi jika Juz selesai
      if (isFinished && widget.groupId != null) {
        try {
          final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
              _supabase.auth.currentUser?.email?.split('@')[0] ??
              'Seseorang';
          final gName = widget.groupName ?? 'Grup';

          await NotificationService.sendToGroup(
            groupId: widget.groupId!,
            type: 'JUZ_COMPLETED',
            title: 'Juz Selesai Dibaca',
            body: '$senderName telah menyelesaikan Juz ${widget.slot['nomor_juz']} di grup "$gName"',
            excludeUserId: _supabase.auth.currentUser?.id,
          );
        } catch (notifErr) {
          print('Error sending juz completed notification: $notifErr');
        }
      }

      if (mounted) {
        setState(() {
          widget.slot['ayat_terakhir_input'] = absoluteIndex;
          widget.slot['status_checklist'] = isFinished;
          
          if (isFinished) {
            _expanded = false;
            _expandController.reverse();
          } else {
            _initQuranData(); // Reset input fields if reverting
          }
        });

        widget.onProgressUpdated?.call();

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isFinished ? '✅ Juz ${widget.slot['nomor_juz']} ditandai selesai!' : 'Status selesai dibatalkan.'),
          backgroundColor: isFinished ? AppTheme.primaryGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui status'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  int _calculateProgress() {
    if (_totalAyat == 0) return 0;
    final last = widget.slot['ayat_terakhir_input'] as int? ?? 0;
    final p = ((last / _totalAyat) * 100).round();
    return p > 100 ? 100 : p;
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = widget.slot['status_checklist'] == true;
    final progress = isComplete ? 100 : _calculateProgress();
    final juzNumber = widget.slot['nomor_juz'] as int;
    final lastAyat = widget.slot['ayat_terakhir_input'] as int? ?? 0;

    String lastPositionString = 'Belum dibaca';
    if (lastAyat > 0 && _surahsInJuz.isNotEmpty) {
      int tempAbsolute = lastAyat;
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

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppTheme.primaryGreen.withOpacity(0.5)
              : widget.isOwned
                  ? AppTheme.accentTeal.withOpacity(0.4)
                  : Theme.of(context).dividerColor,
          width: widget.isOwned && !isComplete ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header (always visible) ──────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _toggleExpand,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  // Badge Juz
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: isComplete
                          ? AppTheme.primaryGradient
                          : widget.isOwned
                              ? LinearGradient(colors: [Color(0xFF006064), Color(0xFF00838F)])
                              : null,
                      color: (!isComplete && !widget.isOwned) ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: isComplete
                          ? Icon(Icons.check_rounded, color: Colors.white, size: 22)
                          : Text(
                              '$juzNumber',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: widget.isOwned ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Juz $juzNumber',
                              style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (isComplete) ...[
                              SizedBox(width: 6),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Selesai', style: TextStyle(color: AppTheme.primaryGreen, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                            if (widget.isOwned && !isComplete) ...[
                              SizedBox(width: 6),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentTeal.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Milik Anda', style: TextStyle(color: AppTheme.accentTeal, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.memberName != null ? '@${widget.memberName}' : '',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        SizedBox(height: 8),
                        // Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress / 100,
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
                  SizedBox(width: 10),
                  // Percentage + Arrow
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$progress%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 4),
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

          // ── Expanded Content ─────────────────────────────────
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  SizedBox(height: 14),
                  // Metadata info
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.menu_book_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Juz ini berisi ${_surahsInJuz.length} Surat  •  Total: $_totalAyat ayat',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isOwned && !isComplete) ...[
                    SizedBox(height: 14),
                    Text(
                      'Posisi terakhir: $lastPositionString',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    // Dropdown Surat
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedSurah,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryGreen),
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
                    SizedBox(height: 10),
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
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveProgress,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              padding: EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text('Simpan Progres', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _confirmRelease,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.redAccent),
                            padding: EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Lepas', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _confirmMarkFinished,
                      icon: Icon(Icons.check_circle_rounded),
                      label: Text('Saya Sudah Membaca 1 Juz Penuh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen.withOpacity(0.15),
                        foregroundColor: AppTheme.primaryGreen,
                        elevation: 0,
                        minimumSize: Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ] else if (!widget.isOwned) ...[
                    SizedBox(height: 12),
                    Text(
                      isComplete
                          ? '✅ Juz ini telah selesai dibaca oleh @${widget.memberName ?? '...'}. Alhamdulillah!'
                          : '📖 Juz ini sedang dibaca oleh @${widget.memberName ?? '...'}.',
                      style: TextStyle(
                        color: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ] else ...[
                    SizedBox(height: 12),
                    Text('✅ Juz ini sudah Anda selesaikan. Alhamdulillah!',
                      style: TextStyle(color: AppTheme.primaryGreen, fontSize: 13)),
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _markAsFinished(false),
                      icon: Icon(Icons.undo_rounded, size: 18),
                      label: Text('Batalkan Status Selesai'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        minimumSize: Size(double.infinity, 42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
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