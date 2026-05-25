import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/personal_history_service.dart';

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

  void _setFormProgressFromAbsoluteIndex(int absoluteIndex) {
    if (absoluteIndex <= 0) {
      setState(() {
        _selectedSurah = _surahsInJuz.keys.first;
        _ayatController.text = '';
      });
      return;
    }

    if (absoluteIndex >= _totalAyat) {
      setState(() {
        _selectedSurah = _surahsInJuz.keys.last;
        _ayatController.text = _surahsInJuz[_selectedSurah]![1].toString();
      });
      return;
    }

    int tempAbsolute = absoluteIndex;
    int? foundSurah;
    int foundAyat = 0;

    for (var entry in _surahsInJuz.entries) {
      int surah = entry.key;
      int start = entry.value[0];
      int end = entry.value[1];
      int ayahsInThisSurah = end - start + 1;
      
      if (tempAbsolute <= ayahsInThisSurah) {
        foundSurah = surah;
        foundAyat = start + tempAbsolute - 1;
        break;
      } else {
        tempAbsolute -= ayahsInThisSurah;
      }
    }

    setState(() {
      _selectedSurah = foundSurah ?? _surahsInJuz.keys.last;
      _ayatController.text = foundAyat > 0 
          ? foundAyat.toString() 
          : _surahsInJuz[_selectedSurah]![1].toString();
    });
  }

  Widget _buildTargetChip(String label, double fraction) {
    final targetIndex = (fraction * _totalAyat).round();
    final isActive = _localLastAyat == targetIndex;

    return ActionChip(
      onPressed: () {
        _setFormProgressFromAbsoluteIndex(targetIndex);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Target diatur ke $label (Total $targetIndex ayat)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.accentTeal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
      elevation: 0,
      pressElevation: 2,
      backgroundColor: isActive 
          ? AppTheme.primaryGreen.withOpacity(0.15) 
          : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      side: BorderSide(
        color: isActive 
            ? AppTheme.primaryGreen.withOpacity(0.5) 
            : Theme.of(context).dividerColor.withOpacity(0.3),
        width: isActive ? 1.2 : 0.8,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          color: isActive ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }

  @override
  void dispose() {
    _ayatController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _ensureVisible() {
    if (!mounted || !_expanded) return;
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Hanya lakukan scroll jika bagian bawah kartu berada di bawah 82% dari tinggi layar
    if (position.dy + size.height > screenHeight * 0.82) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.65, // Diangkat lebih tinggi agar tombol terbawah tidak tertutup SnackBar melayang
      );
    }
  }

  void _toggleExpand() {
    // Unclaimed slots cannot be expanded
    if (widget.isGroupMode && widget.memberName == null) return;
    
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 150), () {
          _ensureVisible();
        });
      });
    } else {
      _expandController.reverse();
    }
  }

  Future<void> _handleSave() async {
    final inputAyah = int.tryParse(_ayatController.text);
    if (inputAyah == null || inputAyah < 0 || _selectedSurah == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Input ayat tidak valid', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final bounds = _surahsInJuz[_selectedSurah]!;
    if (inputAyah < bounds[0] || inputAyah > bounds[1]) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ayat harus antara ${bounds[0]} dan ${bounds[1]} untuk surat ini',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

        final currentUserId = _supabase.auth.currentUser?.id;
        if (currentUserId != null) {
          if (isComplete) {
            final desc = 'Alhamdulillah, telah menyelesaikan Juz ${widget.juzNumber}!';
            await PersonalHistoryService.logReading(
              userId: currentUserId,
              juz: widget.juzNumber,
              description: desc,
              type: 'Grup: ${widget.groupName ?? 'Khataman Grup'}',
              isJuzCompletion: true,
            );
          } else {
            await PersonalHistoryService.removeReadingLog(
              userId: currentUserId,
              juz: widget.juzNumber,
              type: 'Grup: ${widget.groupName ?? 'Khataman Grup'}',
            );
          }
        }

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
            content: Text(
              isComplete ? '✅ Juz ${widget.juzNumber} selesai! Alhamdulillah!' : 'Progres disimpan',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            backgroundColor: isComplete ? AppTheme.primaryGreen : const Color(0xFF323232),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gagal menyimpan progres', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
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

        final currentUserId = _supabase.auth.currentUser?.id;
        if (currentUserId != null) {
          if (isFinished) {
            final desc = 'Alhamdulillah, telah menyelesaikan Juz ${widget.juzNumber}!';
            await PersonalHistoryService.logReading(
              userId: currentUserId,
              juz: widget.juzNumber,
              description: desc,
              type: 'Grup: ${widget.groupName ?? 'Khataman Grup'}',
              isJuzCompletion: true,
            );
          } else {
            await PersonalHistoryService.removeReadingLog(
              userId: currentUserId,
              juz: widget.juzNumber,
              type: 'Grup: ${widget.groupName ?? 'Khataman Grup'}',
            );
          }
        }

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
            content: Text(
              isFinished ? '✅ Juz ${widget.juzNumber} ditandai selesai!' : 'Status selesai dibatalkan.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            backgroundColor: isFinished ? AppTheme.primaryGreen : const Color(0xFF323232),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));

          if (!isFinished && _expanded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(const Duration(milliseconds: 100), () {
                _ensureVisible();
              });
            });
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gagal memperbarui status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    // Dynamic Card background
    final Color cardBg;
    if (isComplete) {
      cardBg = isDark ? const Color(0xFF132B1E) : const Color(0xFFEBFDF3);
    } else if (widget.isOwned) {
      cardBg = isDark ? const Color(0xFF0C242A) : const Color(0xFFF4FDF7);
    } else {
      cardBg = Theme.of(context).colorScheme.surface;
    }

    // Dynamic Border color and width
    final Color borderColor;
    final double borderWidth;
    if (isComplete) {
      borderColor = isDark 
          ? AppTheme.primaryGreen.withOpacity(0.3) 
          : AppTheme.primaryGreen.withOpacity(0.35);
      borderWidth = 1.0;
    } else if (widget.isOwned) {
      borderColor = isDark 
          ? AppTheme.accentTeal.withOpacity(0.4) 
          : AppTheme.primaryGreen.withOpacity(0.35);
      borderWidth = 1.5;
    } else {
      borderColor = isDark 
          ? AppTheme.primaryGreen.withOpacity(0.3) 
          : Colors.grey.withOpacity(0.2);
      borderWidth = 1.0;
    }

    // Dynamic Text colors
    final Color primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final Color secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final Color percentTextColor = isComplete 
        ? (isDark ? AppTheme.primaryGreen : AppTheme.darkGreen) 
        : Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
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
                      gradient: (isComplete && isDark)
                          ? AppTheme.primaryGradient
                          : (widget.isOwned && isDark)
                              ? const LinearGradient(colors: [Color(0xFF006064), Color(0xFF00838F)])
                              : null,
                      color: isComplete
                          ? (isDark 
                              ? null 
                              : AppTheme.primaryGreen.withOpacity(0.12))
                          : widget.isOwned
                              ? (isDark 
                                  ? null 
                                  : AppTheme.primaryGreen.withOpacity(0.12))
                              : (isDark 
                                  ? Colors.white.withOpacity(0.08) 
                                  : AppTheme.primaryGreen.withOpacity(0.06)),
                      border: Border.all(
                        color: isDark
                            ? Colors.transparent
                            : isComplete
                                ? AppTheme.primaryGreen.withOpacity(0.25)
                                : widget.isOwned
                                    ? AppTheme.primaryGreen.withOpacity(0.25)
                                    : AppTheme.primaryGreen.withOpacity(0.15),
                        width: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: isComplete
                          ? Icon(
                              Icons.check_rounded, 
                              color: isDark ? Colors.white : AppTheme.darkGreen, 
                              size: 22,
                            )
                          : Text(
                              '${widget.juzNumber}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: widget.isOwned 
                                    ? (isDark ? Colors.white : AppTheme.darkGreen)
                                    : (isDark ? Colors.white70 : AppTheme.darkGreen),
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
                                fontSize: 15, fontWeight: FontWeight.w700, color: primaryTextColor,
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
                                  color: isDark 
                                      ? AppTheme.accentTeal.withAlpha(38) 
                                      : AppTheme.primaryGreen.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Milik Anda', 
                                  style: TextStyle(
                                    color: isDark ? AppTheme.accentTeal : AppTheme.darkGreen, 
                                    fontSize: 10, 
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.isGroupMode
                              ? (widget.memberName != null ? '@${widget.memberName}' : 'Slot Kosong')
                              : surahAwal,
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
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
                          color: percentTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(Icons.keyboard_arrow_down_rounded, color: secondaryTextColor, size: 22),
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
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _confirmMarkFinished,
                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                      label: const Text('Saya Sudah Membaca 1 Juz Penuh'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        side: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(color: Theme.of(context).dividerColor.withOpacity(0.5), height: 1),
                    const SizedBox(height: 14),
                    Text(
                      'Posisi terakhir: $lastPositionString',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Target Membaca Cepat:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildTargetChip('1/10 Juz (2 Hlm)', 1 / 10),
                          const SizedBox(width: 6),
                          _buildTargetChip('1/8 Juz (2.5 Hlm)', 1 / 8),
                          const SizedBox(width: 6),
                          _buildTargetChip('1/4 Juz (5 Hlm)', 1 / 4),
                          const SizedBox(width: 6),
                          _buildTargetChip('1/2 Juz (10 Hlm)', 1 / 2),
                          const SizedBox(width: 6),
                          _buildTargetChip('3/4 Juz (15 Hlm)', 3 / 4),
                          const SizedBox(width: 6),
                          _buildTargetChip('1 Juz Penuh (20 Hlm)', 1.0),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
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
                              backgroundColor: isDark ? const Color(0xFF1B8047) : AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            child: const Text('Simpan Progres'),
                          ),
                        ),
                        if (widget.isGroupMode) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _confirmRelease,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent, width: 1.5),
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            child: const Text('Lepas'),
                          ),
                        ],
                      ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? AppTheme.primaryGreen.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.2),
          width: 1.0,
        ),
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
                  color: isDark 
                      ? Colors.white.withOpacity(0.08) 
                      : AppTheme.primaryGreen.withOpacity(0.06),
                  border: Border.all(
                    color: isDark ? Colors.transparent : AppTheme.primaryGreen.withOpacity(0.15),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${widget.juzNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 16, 
                      color: isDark ? Colors.white70 : AppTheme.darkGreen,
                    ),
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
                  gradient: isDark ? AppTheme.primaryGradient : null,
                  color: isDark ? null : AppTheme.primaryGreen.withOpacity(0.12),
                  border: Border.all(
                    color: isDark ? Colors.transparent : AppTheme.primaryGreen.withOpacity(0.25),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Ambil Juz Ini',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.darkGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
