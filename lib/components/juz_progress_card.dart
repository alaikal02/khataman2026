import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

class JuzProgressCard extends StatefulWidget {
  final int juzNumber;
  final int lastAyat;
  final bool isComplete;
  
  // Mode configuration
  final bool isGroupMode;
  final bool isOwned;
  final String? memberName;
  
  // Database IDs / parameters
  final int? slotId;
  final String? groupId;
  final String? groupName;
  
  // Callbacks
  final Function(int absoluteIndex, int total)? onSave;
  final Function(int slotId)? onRelease;
  final Function(int slotId)? onClaim;
  final VoidCallback? onProgressUpdated;

  const JuzProgressCard({
    Key? key,
    required this.juzNumber,
    required this.lastAyat,
    required this.isComplete,
    this.isGroupMode = false,
    this.isOwned = false,
    this.memberName,
    this.slotId,
    this.groupId,
    this.groupName,
    this.onSave,
    this.onRelease,
    this.onClaim,
    this.onProgressUpdated,
  }) : super(key: key);

  @override
  State<JuzProgressCard> createState() => _JuzProgressCardState();
}

class _JuzProgressCardState extends State<JuzProgressCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late TextEditingController _ayatController;
  final _supabase = Supabase.instance.client;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  
  int _totalAyat = 0;
  Map<int, List<int>> _surahsInJuz = {};
  int? _selectedSurah;

  // Local state to keep UI snappy and responsive
  late int _localLastAyat;
  late bool _localIsComplete;

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
    _localLastAyat = widget.lastAyat;
    _localIsComplete = widget.isComplete;
    _initQuranData();
  }

  @override
  void didUpdateWidget(covariant JuzProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastAyat != widget.lastAyat || 
        oldWidget.isComplete != widget.isComplete || 
        oldWidget.juzNumber != widget.juzNumber) {
      _localLastAyat = widget.lastAyat;
      _localIsComplete = widget.isComplete;
      _initQuranData();
    }
  }

  void _initQuranData() {
    _surahsInJuz = quran.getSurahAndVersesFromJuz(widget.juzNumber);
    
    _totalAyat = 0;
    _surahsInJuz.forEach((surah, bounds) {
      _totalAyat += (bounds[1] - bounds[0] + 1);
    });

    int absoluteIndex = _localLastAyat;
    
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
    // Unclaimed slots cannot be expanded
    if (widget.isGroupMode && widget.memberName == null) return;
    
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  Future<void> _handleSave() async {
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

    final isComplete = absoluteIndex == _totalAyat;

    if (widget.isGroupMode) {
      // Group Mode DB operation
      if (widget.slotId == null) return;
      try {
        await _supabase.from('slot_khataman').update({
          'ayat_terakhir_input': absoluteIndex,
          'status_checklist': isComplete,
        }).eq('id_slot', widget.slotId!);

        // Send notifications if completed
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
              body: '$senderName telah menyelesaikan Juz ${widget.juzNumber} di grup "$gName"',
              excludeUserId: _supabase.auth.currentUser?.id,
            );
          } catch (e) {
            debugPrint('Error sending completed notif: $e');
          }
        }

        if (mounted) {
          setState(() {
            _localLastAyat = absoluteIndex;
            _localIsComplete = isComplete;
            if (isComplete) {
              _expanded = false;
              _expandController.reverse();
            }
          });

          widget.onProgressUpdated?.call();

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isComplete ? '✅ Juz ${widget.juzNumber} selesai! Alhamdulillah!' : 'Progres disimpan'),
            backgroundColor: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menyimpan progres'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } else {
      // Individual Mode
      if (widget.onSave != null) {
        widget.onSave!(absoluteIndex, _totalAyat);
        if (isComplete) {
          setState(() {
            _expanded = false;
            _expandController.reverse();
          });
        }
      }
    }
  }

  Future<void> _confirmRelease() async {
    if (widget.slotId == null || widget.onRelease == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Lepas Juz?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Progres Juz ${widget.juzNumber} Anda akan direset dan slot ini akan tersedia untuk anggota lain.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Ya, Lepas Juz'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRelease!(widget.slotId!);
    }
  }

  Future<void> _confirmMarkFinished() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Selesaikan Juz?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Apakah Anda yakin telah membaca seluruh isi Juz ${widget.juzNumber} ini? Progres akan otomatis menjadi 100%.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Belum'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGreen),
            child: const Text('Ya, Selesai'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _markAsFinished(true);
    }
  }

  Future<void> _markAsFinished(bool isFinished) async {
    final absoluteIndex = isFinished ? _totalAyat : 0;

    if (widget.isGroupMode) {
      if (widget.slotId == null) return;
      try {
        await _supabase.from('slot_khataman').update({
          'ayat_terakhir_input': absoluteIndex,
          'status_checklist': isFinished,
        }).eq('id_slot', widget.slotId!);

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
              body: '$senderName telah menyelesaikan Juz ${widget.juzNumber} di grup "$gName"',
              excludeUserId: _supabase.auth.currentUser?.id,
            );
          } catch (e) {
            debugPrint('Error sending finished notif: $e');
          }
        }

        if (mounted) {
          setState(() {
            _localLastAyat = absoluteIndex;
            _localIsComplete = isFinished;
            if (isFinished) {
              _expanded = false;
              _expandController.reverse();
            } else {
              _initQuranData();
            }
          });

          widget.onProgressUpdated?.call();

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isFinished ? '✅ Juz ${widget.juzNumber} ditandai selesai!' : 'Status selesai dibatalkan.'),
            backgroundColor: isFinished ? AppTheme.primaryGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memperbarui status'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } else {
      // Individual Mode
      if (widget.onSave != null) {
        widget.onSave!(absoluteIndex, _totalAyat);
        if (isFinished) {
          setState(() {
            _expanded = false;
            _expandController.reverse();
          });
        }
      }
    }
  }

  int _calculateProgress() {
    if (_totalAyat == 0) return 0;
    final p = ((_localLastAyat / _totalAyat) * 100).round();
    return p > 100 ? 100 : p;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Is this an unclaimed slot?
    final isUnclaimed = widget.isGroupMode && widget.memberName == null;

    if (isUnclaimed) {
      return _buildUnclaimedCard();
    }

    final isComplete = _localIsComplete;
    final progress = isComplete ? 100 : _calculateProgress();
    final surahAwal = _surahsInJuz.isNotEmpty ? quran.getSurahName(_surahsInJuz.keys.first) : '';

    String lastPositionString = 'Belum dibaca';
    if (_localLastAyat > 0 && _surahsInJuz.isNotEmpty) {
      int tempAbsolute = _localLastAyat;
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppTheme.primaryGreen.withAlpha(128)
              : widget.isOwned
                  ? AppTheme.accentTeal.withAlpha(102)
                  : Theme.of(context).dividerColor,
          width: widget.isOwned && !isComplete ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _toggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                              ? const LinearGradient(colors: [Color(0xFF006064), Color(0xFF00838F)])
                              : null,
                      color: (!isComplete && !widget.isOwned) ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: isComplete
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                          : Text(
                              '${widget.juzNumber}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: widget.isOwned ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Juz ${widget.juzNumber}',
                              style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (isComplete) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withAlpha(38),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Selesai', style: TextStyle(color: AppTheme.primaryGreen, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                            if (widget.isOwned && !isComplete) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentTeal.withAlpha(38),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Milik Anda', style: TextStyle(color: AppTheme.accentTeal, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.isGroupMode
                              ? (widget.memberName != null ? '@${widget.memberName}' : 'Slot Kosong')
                              : surahAwal,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
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
                  const SizedBox(width: 10),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  const SizedBox(height: 14),
                  // Metadata info
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
                  
                  // Read Input & Buttons
                  if ((widget.isOwned || !widget.isGroupMode) && !isComplete) ...[
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
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handleSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: const Text('Simpan Progres', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        if (widget.isGroupMode) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _confirmRelease,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Lepas', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _confirmMarkFinished,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Saya Sudah Membaca 1 Juz Penuh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen.withAlpha(38),
                        foregroundColor: AppTheme.primaryGreen,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ] else if (widget.isGroupMode && !widget.isOwned) ...[
                    // Claimed by someone else in the group
                    const SizedBox(height: 12),
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
                    // Completed by the current user
                    const SizedBox(height: 12),
                    const Text('✅ Juz ini sudah Anda selesaikan. Alhamdulillah!',
                      style: TextStyle(color: AppTheme.primaryGreen, fontSize: 13)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _markAsFinished(false),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Batalkan Status Selesai'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        minimumSize: const Size(double.infinity, 42),
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

  Widget _buildUnclaimedCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${widget.juzNumber}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Juz ${widget.juzNumber}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text('Slot Kosong', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ],
          ),
          if (widget.onClaim != null && widget.slotId != null)
            GestureDetector(
              onTap: () => widget.onClaim!(widget.slotId!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Ambil Juz Ini',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}
