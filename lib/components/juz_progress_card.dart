import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/personal_history_service.dart';
import '../screens/mushaf_reader_screen.dart';

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
  final Function(int slotId)? onRequestRelease;
  final Function(int slotId)? onCancelRelease;
  final Function(int slotId)? onClaim;
  final VoidCallback? onProgressUpdated;

  // Release approval status
  final String? approvalLepasStatus;
  final String? usernameSebelumnya;
  final bool isAdmin;

  const JuzProgressCard({
    Key? key,
    required this.juzNumber,
    required this.lastAyat,
    required this.isComplete,
    this.isGroupMode = false,
    this.isOwned = false,
    this.isAdmin = false,
    this.memberName,
    this.slotId,
    this.groupId,
    this.groupName,
    this.onSave,
    this.onRelease,
    this.onRequestRelease,
    this.onCancelRelease,
    this.onClaim,
    this.onProgressUpdated,
    this.approvalLepasStatus,
    this.usernameSebelumnya,
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
  double _sliderValue = 2.0;

  int get _maxAllowedIndex {
    if (_localLastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1) {
      final lastSurahNum = _surahsInJuz.keys.last;
      final bounds = _surahsInJuz[lastSurahNum]!;
      return _totalAyat - (bounds[1] - bounds[0] + 1);
    }
    return _totalAyat;
  }

  double get _maxSliderValue {
    if (_totalAyat <= 0) return 20.0;
    return (_maxAllowedIndex / _totalAyat) * 20.0;
  }

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _tooltipOverlayEntry;

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

      // Auto-collapse jika juz ditandai selesai untuk mencegah race condition realtime rebuild
      if (_localIsComplete && _expanded) {
        _expanded = false;
        _expandController.reverse();
      }
    }
  }

  Map<String, int> _getSurahAndAyatFromAbsolute(int absoluteIndex) {
    if (absoluteIndex <= 0 || _surahsInJuz.isEmpty) {
      final firstSurah = _surahsInJuz.isNotEmpty ? _surahsInJuz.keys.first : 0;
      return {'surah': firstSurah, 'ayat': 0};
    }
    int tempAbsolute = absoluteIndex;
    for (var entry in _surahsInJuz.entries) {
      int surah = entry.key;
      int start = entry.value[0];
      int end = entry.value[1];
      int ayahsInThisSurah = end - start + 1;
      
      if (tempAbsolute <= ayahsInThisSurah) {
        return {'surah': surah, 'ayat': start + tempAbsolute - 1};
      } else {
        tempAbsolute -= ayahsInThisSurah;
      }
    }
    int lastSurah = _surahsInJuz.isNotEmpty ? _surahsInJuz.keys.last : 0;
    final lastAyatInSurah = _surahsInJuz.isNotEmpty && lastSurah > 0 ? _surahsInJuz[lastSurah]![1] : 0;
    return {'surah': lastSurah, 'ayat': lastAyatInSurah};
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
      _sliderValue = 1.0;
    } else if (absoluteIndex == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1) {
      // Special case: only the last surah was completed, first surah(s) unread.
      // Direct the form to the first surah (the one that still needs reading).
      _selectedSurah = _surahsInJuz.keys.first;
      _ayatController.text = '';
      _sliderValue = 1.0;
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
      if (_totalAyat > 0) {
        _sliderValue = ((absoluteIndex / _totalAyat) * 20.0).roundToDouble().clamp(1.0, 20.0);
      } else {
        _sliderValue = 5.0;
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



  @override
  void dispose() {
    _hideTooltip();
    _ayatController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _ensureVisible() {
    if (!mounted || !_expanded) return;
    
    // Tunggu 280ms agar animasi expand selesai sepenuhnya dan tinggi kartu terukur akurat
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || !_expanded) return;
      
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final screenHeight = MediaQuery.of(context).size.height;
      
      // Hitung posisi terbawah dari kartu yang sudah diexpand
      final cardBottom = position.dy + size.height;
      
      // Batas aman: Jika bagian bawah kartu berada di bawah 80% dari tinggi layar,
      // lakukan scroll otomatis agar kartu terangkat ke atas secara elegan.
      if (cardBottom > screenHeight * 0.80) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: widget.juzNumber == 30 ? 0.82 : 0.5,
        );
      }
    });
  }

  void _toggleExpand() {
    // Unclaimed slots cannot be expanded
    if (widget.isGroupMode && widget.memberName == null) return;
    
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandController.forward();
      _ensureVisible();
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

    // PROTEKSI ANTI-REDUCTION: Jangan izinkan progres mundur dari posisi tersimpan
    // Exception: when only the last surah was completed (localLastAyat == totalAyat && !complete),
    // user is now filling in the first surah, so absoluteIndex will naturally be lower.
    final isLastSurahOnlyCase = _localLastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1;
    if (!isLastSurahOnlyCase && absoluteIndex < _localLastAyat && _localLastAyat > 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '🔒 Progres tidak bisa dimundurkan! Ayat harus lebih tinggi dari posisi terakhir.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

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
    if (widget.slotId == null) return;

    // Jika progres > 0%, Juz terkunci permanen (kecuali Admin)
    if (!widget.isAdmin && (_localLastAyat > 0 || _localIsComplete)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🔒 Juz sudah mulai dibaca, tidak dapat dilepas.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    // Jika status PENDING, batalkan pengajuan
    if (widget.approvalLepasStatus == 'PENDING') {
      widget.onCancelRelease?.call(widget.slotId!);
      return;
    }

    // Jika user adalah admin, tampilkan dialog konfirmasi pelepasan langsung (bukan pengajuan)
    if (widget.isAdmin) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Lepas Juz?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          content: Text(
            'Apakah Anda yakin ingin melepas Juz ${widget.juzNumber}? Slot ini akan kosong kembali secara instan dan tersedia untuk anggota lain.',
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
              child: const Text('Ya, Lepas'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        widget.onRequestRelease?.call(widget.slotId!);
      }
      return;
    }

    // Konfirmasi pengajuan lepas baru (onRequestRelease → PENDING)
    if (widget.onRequestRelease == null) {
      // Fallback: gunakan onRelease langsung (admin mode)
      if (widget.onRelease == null) return;
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
      return;
    }

    // Konfirmasi pengajuan lepas Juz (member mode → PENDING)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Ajukan Lepas Juz?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Pengajuan Anda akan dikirim ke admin grup. Selama menunggu persetujuan, Anda bisa membatalkan pengajuan ini.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Ajukan'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRequestRelease!(widget.slotId!);
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
    
    int lastAyat = _localLastAyat;
    if (lastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.isNotEmpty) {
      final lastSurahNum = _surahsInJuz.keys.last;
      final bounds = _surahsInJuz[lastSurahNum]!;
      lastAyat = bounds[1] - bounds[0] + 1;
    }
    
    final p = ((lastAyat / _totalAyat) * 100).round();
    return p > 100 ? 100 : p;
  }

  void _toggleTooltip() {
    if (_tooltipOverlayEntry != null) {
      _hideTooltip();
    } else {
      _showTooltip();
    }
  }

  void _showTooltip() {
    final surahDetails = _surahsInJuz.entries.map((entry) {
      final name = quran.getSurahName(entry.key);
      final bounds = entry.value;
      return '• $name (Ayat ${bounds[0]} - ${bounds[1]})';
    }).join('\n');
    final tooltipMessage = 'Daftar Surat di Juz ${widget.juzNumber}:\n$surahDetails';

    // Measure screen position to determine if we should show the tooltip above or below the badge
    final renderBox = context.findRenderObject() as RenderBox?;
    bool isBottomHalf = false;
    double screenHeight = 800;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      screenHeight = MediaQuery.of(context).size.height;
      isBottomHalf = position.dy > screenHeight * 0.55;
    }

    _tooltipOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hideTooltip,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: isBottomHalf ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor: isBottomHalf ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(0, isBottomHalf ? -6 : 6),
              child: Material(
                color: Colors.transparent,
                child: IntrinsicWidth(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 240,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B), // Premium Dark Slate
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      tooltipMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_tooltipOverlayEntry!);
  }

  void _hideTooltip() {
    _tooltipOverlayEntry?.remove();
    _tooltipOverlayEntry = null;
  }

  Widget _buildIndividualSurahBadge() {
    if (_surahsInJuz.isEmpty) return const SizedBox.shrink();

    final count = _surahsInJuz.length;

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleTooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppTheme.primaryGreen.withOpacity(0.2),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count Surat',
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.info_outline_rounded,
                  size: 11,
                  color: AppTheme.primaryGreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

    final List<Widget> segmentWidgets = [];
    if (_surahsInJuz.isNotEmpty && _totalAyat > 0) {
      final List<MapEntry<int, List<int>>> surahEntries = _surahsInJuz.entries.toList();
      for (int i = 0; i < surahEntries.length; i++) {
        final entry = surahEntries[i];
        final bounds = entry.value;
        final segmentLength = bounds[1] - bounds[0] + 1;
        final segmentWeight = segmentLength / _totalAyat;

        int startAbsolute = 1;
        for (int prev = 0; prev < i; prev++) {
          final prevBounds = surahEntries[prev].value;
          startAbsolute += (prevBounds[1] - prevBounds[0] + 1);
        }
        int endAbsolute = startAbsolute + segmentLength - 1;

        double fillFraction = 0.0;
        if (isComplete) {
          fillFraction = 1.0;
        } else if (_localLastAyat == _totalAyat && !_localIsComplete) {
          if (i == surahEntries.length - 1) {
            fillFraction = 1.0;
          } else {
            fillFraction = 0.0;
          }
        } else {
          if (_localLastAyat < startAbsolute) {
            fillFraction = 0.0;
          } else if (_localLastAyat >= endAbsolute) {
            fillFraction = 1.0;
          } else {
            fillFraction = (_localLastAyat - startAbsolute + 1) / segmentLength;
          }
        }

        segmentWidgets.add(
          Expanded(
            flex: (segmentWeight * 1000).round().clamp(1, 1000),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: fillFraction >= 1.0
                    ? (isComplete ? AppTheme.primaryGreen : AppTheme.accentTeal)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: fillFraction > 0.0 && fillFraction < 1.0
                  ? FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fillFraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isComplete ? AppTheme.primaryGreen : AppTheme.accentTeal,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        );

        if (i < surahEntries.length - 1) {
          segmentWidgets.add(const SizedBox(width: 3));
        }
      }
    }
    final savedPosition = _getSurahAndAyatFromAbsolute(_localLastAyat);
    final savedSurah = savedPosition['surah'] ?? 0;
    final savedAyat = savedPosition['ayat'] ?? 0;

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
                            if (!widget.isGroupMode) ...[
                              const SizedBox(width: 8),
                              _buildIndividualSurahBadge(),
                            ],
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
                              if (widget.isGroupMode) ...[
                                // PENDING badge
                                if (widget.approvalLepasStatus == 'PENDING') ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _confirmRelease,
                                    behavior: HitTestBehavior.opaque,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark 
                                              ? Colors.orange.withAlpha(38) 
                                              : Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isDark 
                                                ? Colors.orange.withOpacity(0.3) 
                                                : Colors.orange.shade200,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          'Batalkan',
                                          style: TextStyle(
                                            color: isDark ? Colors.orange : Colors.orange.shade800,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else if (!widget.isAdmin && (_localLastAyat > 0 || _localIsComplete)) ...[
                                  // Locked: progress > 0%
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _confirmRelease,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark 
                                            ? Colors.grey.withAlpha(38) 
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.lock_rounded, size: 10, 
                                            color: isDark ? Colors.grey : Colors.grey.shade600),
                                          const SizedBox(width: 3),
                                          Text(
                                            'Terkunci',
                                            style: TextStyle(
                                              color: isDark ? Colors.grey : Colors.grey.shade600,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  // Normal: can request release
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _confirmRelease,
                                    behavior: HitTestBehavior.opaque,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark 
                                              ? Colors.redAccent.withAlpha(38) 
                                              : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isDark 
                                                ? Colors.redAccent.withOpacity(0.2) 
                                                : Colors.red.shade100,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          'Lepas',
                                          style: TextStyle(
                                            color: isDark ? Colors.redAccent : Colors.red.shade700,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ],
                        ),
                        if (widget.isGroupMode) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.memberName != null ? '@${widget.memberName}' : 'Slot Kosong',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                        const SizedBox(height: 8),
                        // Segmented Progress Bar
                        if (segmentWidgets.isNotEmpty)
                          Row(
                            children: segmentWidgets,
                          )
                        else
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
                        Icon(
                          Icons.menu_book_rounded, 
                          size: 16, 
                          color: isDark ? Colors.white.withOpacity(0.8) : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Juz ini berisi ${_surahsInJuz.length} Surat  •  Total: $_totalAyat ayat',
                            style: TextStyle(
                              color: isDark ? Colors.white.withOpacity(0.85) : Theme.of(context).colorScheme.onSurfaceVariant, 
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isGroupMode &&
                      widget.usernameSebelumnya != null &&
                      widget.usernameSebelumnya != widget.memberName) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withOpacity(isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.accentGold.withOpacity(isDark ? 0.3 : 0.2),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_rounded, 
                            size: 16, 
                            color: isDark ? AppTheme.accentGold : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Progres sebelumnya oleh: @${widget.usernameSebelumnya}',
                              style: TextStyle(
                                color: isDark ? AppTheme.accentGold : Colors.amber.shade900, 
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Read Input & Buttons
                  if ((widget.isOwned || !widget.isGroupMode) && !isComplete) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Posisi terakhir: $lastPositionString',
                      style: TextStyle(
                        color: isDark ? Colors.white.withOpacity(0.9) : Theme.of(context).colorScheme.onSurfaceVariant, 
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Target Membaca Cepat:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white.withOpacity(0.9) : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.15 : 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.primaryGreen.withOpacity(isDark ? 0.3 : 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '${_sliderValue.round()} Halaman',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackShape: SegmentedSliderTrackShape(
                          surahsInJuz: _surahsInJuz,
                          totalAyat: _totalAyat,
                          localLastAyat: _localLastAyat,
                          isComplete: isComplete,
                          context: context,
                        ),
                        activeTrackColor: AppTheme.primaryGreen,
                        inactiveTrackColor: isDark ? Colors.white10 : Colors.grey.shade200,
                        thumbColor: AppTheme.primaryGreen,
                        overlayColor: AppTheme.primaryGreen.withOpacity(0.12),
                        valueIndicatorColor: AppTheme.primaryGreen,
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      ),
                      child: Slider(
                        value: _sliderValue.clamp(1.0, 20.0),
                        min: 1.0,
                        max: 20.0,
                        divisions: 19,
                        onChanged: (double val) {
                          final isLastSurahOnlyCase = _localLastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1;
                          if (isLastSurahOnlyCase) {
                            final maxAllowed = _maxSliderValue;
                            if (val > maxAllowed) {
                              val = maxAllowed;
                            }
                          }

                          final fraction = val / 20.0;
                          final targetIndex = (fraction * _totalAyat).round();

                          // For normal sequential cases, lock backward dragging
                          if (!isLastSurahOnlyCase && targetIndex < _localLastAyat) {
                            return; // Lock backward dragging
                          }
                          setState(() {
                            _sliderValue = val;
                          });
                        },
                        onChangeEnd: (double val) {
                          final isLastSurahOnlyCase = _localLastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1;
                          if (isLastSurahOnlyCase) {
                            final maxAllowed = _maxSliderValue;
                            if (val > maxAllowed) {
                              val = maxAllowed;
                            }
                          }
                          final fraction = val / 20.0;
                          final targetIndex = (fraction * _totalAyat).round();
                          _setFormProgressFromAbsoluteIndex(targetIndex);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
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
                            final isLastSurahOnlyCase = _localLastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1;
                            final lastSurahNum = _surahsInJuz.keys.last;
                            final isEnabled = isLastSurahOnlyCase
                                ? entry.key != lastSurahNum
                                : entry.key >= savedSurah;
                            return DropdownMenuItem<int>(
                              value: entry.key,
                              enabled: isEnabled,
                              child: Text(
                                '${quran.getSurahName(entry.key)} (Ayat ${bounds[0]} - ${bounds[1]})',
                                style: TextStyle(
                                  color: isEnabled
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            final isLastSurahOnlyCase = _localLastAyat == _totalAyat && !_localIsComplete && _surahsInJuz.length > 1;
                            final lastSurahNum = _surahsInJuz.keys.last;
                            final isAllowed = isLastSurahOnlyCase
                                ? val != lastSurahNum
                                : val >= savedSurah;
                            if (!isAllowed) return;

                            setState(() {
                              _selectedSurah = val;
                              final int targetAyat;
                              if (isLastSurahOnlyCase) {
                                targetAyat = _surahsInJuz[val]![0];
                              } else if (val == savedSurah) {
                                targetAyat = savedAyat;
                              } else {
                                targetAyat = _surahsInJuz[val]![0];
                              }
                              _ayatController.text = targetAyat > 0 ? targetAyat.toString() : '';
                              
                              if (_totalAyat > 0) {
                                int absoluteIndex = 0;
                                for (var entry in _surahsInJuz.entries) {
                                  int surah = entry.key;
                                  int start = entry.value[0];
                                  int end = entry.value[1];
                                  if (surah == val) {
                                    absoluteIndex += (targetAyat - start + 1).clamp(0, end - start + 1);
                                    break;
                                  } else {
                                    absoluteIndex += (end - start + 1);
                                  }
                                }
                                _sliderValue = ((absoluteIndex / _totalAyat) * 20.0).roundToDouble().clamp(1.0, 20.0);
                              }
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
                            ? 'Ayat terakhir (Min ${_selectedSurah == savedSurah ? savedAyat : _surahsInJuz[_selectedSurah]![0]}, Max ${_surahsInJuz[_selectedSurah]![1]})'
                            : 'Pilih surat dulu',
                        helperText: _selectedSurah == savedSurah && savedAyat > 0
                            ? 'Minimal ayat: $savedAyat (posisi tersimpan)'
                            : null,
                        helperStyle: const TextStyle(color: AppTheme.accentGold, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      enabled: _selectedSurah != null,
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      key: const ValueKey('btn_read_in_mushaf'),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MushafReaderScreen(
                              initialJuzNumber: widget.juzNumber,
                              initialSurahNumber: _localLastAyat > 0 ? savedSurah : null,
                              initialVerseNumber: _localLastAyat > 0 ? savedAyat : null,
                              selectForMandiri: !widget.isGroupMode,
                              selectForGroupId: widget.isGroupMode ? widget.groupId : null,
                              groupName: widget.isGroupMode ? widget.groupName : null,
                              slotId: widget.isGroupMode ? widget.slotId : null,
                            ),
                          ),
                        );
                        widget.onProgressUpdated?.call();
                      },
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: const Text('Baca di Mushaf Al-Quran'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentTeal.withOpacity(0.12),
                        foregroundColor: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppTheme.accentTeal.withOpacity(0.4),
                            width: 1.2,
                          ),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      key: const ValueKey('btn_save_progress'),
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
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        key: const ValueKey('btn_mark_finished'),
                        onPressed: _confirmMarkFinished,
                        icon: const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.primaryGreen),
                        label: const Text(
                          'Saya Sudah Membaca 1 Juz Penuh',
                          style: TextStyle(
                            color: AppTheme.primaryGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          foregroundColor: AppTheme.primaryGreen,
                          overlayColor: isDark 
                              ? Colors.white.withOpacity(0.08) 
                              : Colors.black.withOpacity(0.06),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
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
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      key: const ValueKey('btn_read_in_mushaf_other'),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MushafReaderScreen(
                              initialJuzNumber: widget.juzNumber,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.menu_book_rounded, size: 16),
                      label: const Text('Buka di Mushaf Al-Quran'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    // Completed by the current user
                    const SizedBox(height: 12),
                    const Text('✅ Juz ini sudah Anda selesaikan. Alhamdulillah!',
                      style: TextStyle(color: AppTheme.primaryGreen, fontSize: 13)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      key: const ValueKey('btn_read_in_mushaf_completed'),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MushafReaderScreen(
                              initialJuzNumber: widget.juzNumber,
                              selectForMandiri: !widget.isGroupMode,
                              selectForGroupId: widget.isGroupMode ? widget.groupId : null,
                              groupName: widget.isGroupMode ? widget.groupName : null,
                              slotId: widget.isGroupMode ? widget.slotId : null,
                            ),
                          ),
                        );
                        widget.onProgressUpdated?.call();
                      },
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: const Text('Buka di Mushaf Al-Quran'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentTeal.withOpacity(0.12),
                        foregroundColor: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppTheme.accentTeal.withOpacity(0.4),
                            width: 1.2,
                          ),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey('btn_undo_finished'),
                      onPressed: () => _markAsFinished(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
                        minimumSize: const Size(double.infinity, 42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.undo_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Batalkan Status Selesai'),
                          ],
                        ),
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
    final progress = _calculateProgress();
    final hasProgress = progress > 0 && !widget.isComplete;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: hasProgress ? _toggleExpand : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Juz ${widget.juzNumber}',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                                  ),
                                  if (hasProgress) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDark 
                                            ? AppTheme.accentGold.withOpacity(0.15) 
                                            : AppTheme.accentGold.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isDark 
                                              ? AppTheme.accentGold.withOpacity(0.4) 
                                              : AppTheme.accentGold.withOpacity(0.25),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        'Sudah Dicicil $progress%',
                                        style: TextStyle(
                                          color: isDark 
                                              ? AppTheme.accentGold 
                                              : Colors.amber.shade900,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Slot Kosong', 
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
            ),
          ),
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
                        Icon(
                          Icons.person_outline_rounded, 
                          size: 16, 
                          color: isDark ? Colors.white.withOpacity(0.8) : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dibaca sebelumnya oleh: ${widget.usernameSebelumnya != null ? '@${widget.usernameSebelumnya}' : 'pembaca sebelumnya'}',
                            style: TextStyle(
                              color: isDark ? Colors.white.withOpacity(0.85) : Theme.of(context).colorScheme.onSurfaceVariant, 
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SegmentedSliderTrackShape extends SliderTrackShape {
  final Map<int, List<int>> surahsInJuz;
  final int totalAyat;
  final int localLastAyat;
  final bool isComplete;
  final BuildContext context;

  SegmentedSliderTrackShape({
    required this.surahsInJuz,
    required this.totalAyat,
    required this.localLastAyat,
    required this.isComplete,
    required this.context,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      offset: offset,
    );

    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? AppTheme.primaryGreen
      ..style = PaintingStyle.fill;

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey.shade200
      ..style = PaintingStyle.fill;

    final double trackWidth = trackRect.width;
    final double trackHeight = sliderTheme.trackHeight!;
    final double trackLeft = trackRect.left;
    final double trackTop = trackRect.top;

    final surahEntries = surahsInJuz.entries.toList();
    if (surahEntries.isEmpty || totalAyat <= 0) {
      final Paint paint = Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey;
      context.canvas.drawRect(trackRect, paint);
      return;
    }

    // Calculate thumb fraction relative to the track bounds
    final double thumbFraction = (trackWidth > 0)
        ? ((thumbCenter.dx - trackLeft) / trackWidth).clamp(0.0, 1.0)
        : 0.0;

    double currentLeft = trackLeft;

    for (int i = 0; i < surahEntries.length; i++) {
      final entry = surahEntries[i];
      final bounds = entry.value;
      final segmentLength = bounds[1] - bounds[0] + 1;
      final segmentWeight = segmentLength / totalAyat;
      final double segmentWidth = trackWidth * segmentWeight;

      int startAbsolute = 1;
      for (int prev = 0; prev < i; prev++) {
        final prevBounds = surahEntries[prev].value;
        startAbsolute += (prevBounds[1] - prevBounds[0] + 1);
      }
      int endAbsolute = startAbsolute + segmentLength - 1;

      final double startFraction = (startAbsolute - 1) / totalAyat;
      final double endFraction = endAbsolute / totalAyat;

      // 1. Calculate already read fraction
      double readFraction = 0.0;
      if (isComplete) {
        readFraction = 1.0;
      } else if (localLastAyat == totalAyat) {
        // Special case: Only the last Surah is completed
        if (i == surahEntries.length - 1) {
          readFraction = 1.0;
        } else {
          readFraction = 0.0;
        }
      } else {
        if (localLastAyat < startAbsolute) {
          readFraction = 0.0;
        } else if (localLastAyat >= endAbsolute) {
          readFraction = 1.0;
        } else {
          readFraction = (localLastAyat - startAbsolute + 1) / segmentLength;
        }
      }

      // 2. Calculate currently targeted fraction based on visual thumb position
      double targetFraction = 0.0;
      if (thumbFraction > startFraction) {
        if (thumbFraction >= endFraction) {
          targetFraction = 1.0;
        } else {
          targetFraction = (thumbFraction - startFraction) / segmentWeight;
        }
      }

      // 3. Combine both fractions (either read or targeted is painted active)
      double activeFraction = readFraction > targetFraction ? readFraction : targetFraction;

      // Draw inactive background
      final RRect segmentRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(currentLeft, trackTop, segmentWidth, trackHeight),
        const Radius.circular(4),
      );
      context.canvas.drawRRect(segmentRect, inactivePaint);

      // Draw active fill
      if (activeFraction > 0.0) {
        final double activeWidth = segmentWidth * activeFraction;
        final RRect activeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(currentLeft, trackTop, activeWidth, trackHeight),
          const Radius.circular(4),
        );
        context.canvas.drawRRect(activeRect, activePaint);
      }

      currentLeft += segmentWidth;
    }
  }
}

