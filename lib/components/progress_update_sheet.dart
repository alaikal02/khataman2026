import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import '../theme/app_theme.dart';
import '../utils/localization.dart';
import '../services/personal_history_service.dart';
import '../services/notification_service.dart';
import '../services/widget_update_service.dart';

class ProgressUpdateSheet extends StatefulWidget {
  final VoidCallback onSaved;

  const ProgressUpdateSheet({
    Key? key,
    required this.onSaved,
  }) : super(key: key);

  @override
  State<ProgressUpdateSheet> createState() => _ProgressUpdateSheetState();
}

class _ProgressUpdateSheetState extends State<ProgressUpdateSheet> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  // Data lists
  List<Map<String, dynamic>> _mandiriProgress = [];
  List<Map<String, dynamic>> _groupSlots = [];

  // Dropdown options
  List<Map<String, dynamic>> _programOptions = [];
  Map<String, dynamic>? _selectedProgram;

  List<int> _juzOptions = [];
  int? _selectedJuz;

  List<int> _surahOptions = [];
  int? _selectedSurah;

  // Inputs
  final _ayatController = TextEditingController();
  bool _markAsComplete = false;
  bool _isSaving = false;

  // Calculated values for current selection
  int _totalAyatInJuz = 0;
  Map<int, List<int>> _surahsInJuz = {};
  int _currentLastAyatIndex = 0; // Absolute index in Juz

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _ayatController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not logged in';
        });
      }
      return;
    }

    // 1. Fetch Mandiri Progress
    try {
      final mandiriData = await _supabase
          .from('khataman_mandiri')
          .select()
          .eq('user_id', userId);
      _mandiriProgress = List<Map<String, dynamic>>.from(mandiriData);
    } catch (e) {
      debugPrint('Error fetching mandiri progress: $e');
    }

    // 2. Fetch Active Group Slots
    try {
      final slotsData = await _supabase
          .from('slot_khataman')
          .select('*, putaran_siklus!inner(group_id, groups:groups!putaran_siklus_group_id_fkey(nama_grup, id_group, kode_gk_unik))')
          .eq('user_id', userId)
          .eq('putaran_siklus.status_aktif_selesai', 'AKTIF');
      _groupSlots = List<Map<String, dynamic>>.from(slotsData as List);
    } catch (e) {
      debugPrint('Error fetching group slots: $e');
    }

    try {
      // Build program options
      _programOptions = [];
      
      // Check if Mandiri has active progress (i.e. not completely finished 30 Juz, or just show it as standard)
      final completedMandiri = _mandiriProgress.where((p) => p['selesai'] == true).length;
      if (completedMandiri < 30) {
        _programOptions.add({
          'type': 'MANDIRI',
          'id': 'mandiri',
          'name': 'Khataman Mandiri',
        });
      }

      for (var slot in _groupSlots) {
        final putaran = slot['putaran_siklus'] as Map<String, dynamic>?;
        final group = putaran != null ? putaran['groups'] as Map<String, dynamic>? : null;
        final groupName = group != null ? group['nama_grup'] as String? : 'Grup';
        final juzNum = slot['nomor_juz'] as int;

        _programOptions.add({
          'type': 'GROUP',
          'id': slot['id_slot'].toString(),
          'name': '$groupName (Juz $juzNum)',
          'slot': slot,
        });
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_programOptions.isNotEmpty) {
            _selectedProgram = _programOptions.first;
            _onProgramChanged(_selectedProgram);
          } else {
            _errorMessage = 'Tidak ada program khataman aktif yang bisa diupdate progresnya.';
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading progress update options: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Gagal memuat data program: ${e.toString()}';
        });
      }
    }
  }

  void _onProgramChanged(Map<String, dynamic>? program) {
    if (program == null) return;

    setState(() {
      _selectedProgram = program;
      _markAsComplete = false;
      _ayatController.clear();
      
      if (program['type'] == 'MANDIRI') {
        // Show Juz 1-30 for Mandiri, but filter to ones not completed
        final completedJuzs = _mandiriProgress
            .where((p) => p['selesai'] == true)
            .map((p) => p['nomor_juz'] as int)
            .toSet();
        
        _juzOptions = List.generate(30, (i) => i + 1)
            .where((juz) => !completedJuzs.contains(juz))
            .toList();

        if (_juzOptions.isNotEmpty) {
          _selectedJuz = _juzOptions.first;
          _onJuzChanged(_selectedJuz);
        } else {
          _selectedJuz = null;
          _surahOptions = [];
          _selectedSurah = null;
        }
      } else {
        // Group Mode: Juz is fixed by the slot
        final slot = program['slot'] as Map<String, dynamic>;
        final juzNum = slot['nomor_juz'] as int;
        _juzOptions = [juzNum];
        _selectedJuz = juzNum;
        _onJuzChanged(juzNum);
      }
    });
  }

  void _onJuzChanged(int? juz) {
    if (juz == null) return;

    setState(() {
      _selectedJuz = juz;
      _markAsComplete = false;
      
      // Load surahs in this Juz
      _surahsInJuz = quran.getSurahAndVersesFromJuz(juz);
      _surahOptions = _surahsInJuz.keys.toList();

      // Calculate total verses in this Juz
      _totalAyatInJuz = 0;
      _surahsInJuz.forEach((surah, bounds) {
        _totalAyatInJuz += (bounds[1] - bounds[0] + 1);
      });

      // Load current progress to prefill
      int currentAbsoluteIndex = 0;
      if (_selectedProgram?['type'] == 'MANDIRI') {
        final mandiriRow = _mandiriProgress.firstWhere(
          (p) => p['nomor_juz'] == juz,
          orElse: () => {},
        );
        currentAbsoluteIndex = mandiriRow['ayat_terakhir'] as int? ?? 0;
      } else {
        final slot = _selectedProgram?['slot'] as Map<String, dynamic>;
        currentAbsoluteIndex = slot['ayat_terakhir_input'] as int? ?? 0;
      }

      _currentLastAyatIndex = currentAbsoluteIndex;

      // Prefill Surah and Ayat based on current absolute index
      if (currentAbsoluteIndex <= 0) {
        _selectedSurah = _surahOptions.first;
        _ayatController.text = '';
      } else if (currentAbsoluteIndex >= _totalAyatInJuz) {
        _selectedSurah = _surahOptions.last;
        _ayatController.text = _surahsInJuz[_selectedSurah]![1].toString();
        _markAsComplete = true;
      } else {
        int tempAbsolute = currentAbsoluteIndex;
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

        _selectedSurah = foundSurah ?? _surahOptions.first;
        _ayatController.text = foundAyat > 0 ? foundAyat.toString() : '';
      }
    });
  }

  void _onSurahChanged(int? surah) {
    if (surah == null) return;
    setState(() {
      _selectedSurah = surah;
      _ayatController.clear();
      _markAsComplete = false;
    });
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

  Future<void> _handleSave() async {
    if (_selectedJuz == null || _selectedSurah == null) return;

    int absoluteIndex = 0;
    final bounds = _surahsInJuz[_selectedSurah]!;

    if (_markAsComplete) {
      absoluteIndex = _totalAyatInJuz;
    } else {
      final inputAyah = int.tryParse(_ayatController.text);
      if (inputAyah == null || inputAyah < bounds[0] || inputAyah > bounds[1]) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Input ayat tidak valid. Harus antara ${bounds[0]} s.d ${bounds[1]} untuk surat ini.',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Calculate absolute index in Juz
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
    }

    // Protection: Prevent progress reduction
    if (absoluteIndex < _currentLastAyatIndex) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔒 Progres tidak bisa dimundurkan! Silakan pilih ayat yang lebih tinggi.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final isComplete = absoluteIndex == _totalAyatInJuz;

    try {
      if (_selectedProgram?['type'] == 'MANDIRI') {
        // Save Mandiri
        await _supabase.from('khataman_mandiri').upsert({
          'user_id': userId,
          'nomor_juz': _selectedJuz,
          'ayat_terakhir': absoluteIndex,
          'selesai': isComplete,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,nomor_juz');

        if (isComplete) {
          final desc = context.translate('mandiri_log_juz_completed').replaceAll('{juz}', _selectedJuz.toString());
          await PersonalHistoryService.logReading(
            userId: userId,
            juz: _selectedJuz!,
            description: desc,
            type: 'Mandiri',
            isJuzCompletion: true,
          );
        } else {
          await PersonalHistoryService.removeReadingLog(
            userId: userId,
            juz: _selectedJuz!,
            type: 'Mandiri',
          );
        }

        WidgetUpdateService.updateKhatamanWidget();
      } else {
        // Save Group Slot
        final slot = _selectedProgram?['slot'] as Map<String, dynamic>;
        final slotId = slot['id_slot'] as int;
        final putaran = slot['putaran_siklus'] as Map<String, dynamic>?;
        final group = putaran != null ? putaran['groups'] as Map<String, dynamic>? : null;
        final groupName = group != null ? group['nama_grup'] as String? : 'Grup';
        final groupId = group != null ? group['id_group'] as String? : null;

        await _supabase.from('slot_khataman').update({
          'ayat_terakhir_input': absoluteIndex,
          'status_checklist': isComplete,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id_slot', slotId);

        if (isComplete) {
          final desc = 'Alhamdulillah, telah menyelesaikan Juz ${_selectedJuz}!';
          await PersonalHistoryService.logReading(
            userId: userId,
            juz: _selectedJuz!,
            description: desc,
            type: 'Grup: ${groupName ?? 'Khataman Grup'}',
            isJuzCompletion: true,
          );

          if (groupId != null) {
            final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
                _supabase.auth.currentUser?.email?.split('@')[0] ??
                'Seseorang';

            await NotificationService.sendToGroup(
              groupId: groupId,
              type: 'JUZ_COMPLETED',
              title: 'Juz Selesai Dibaca',
              body: '$senderName telah menyelesaikan Juz ${_selectedJuz} di grup "$groupName"',
              excludeUserId: userId,
            );
          }
        } else {
          await PersonalHistoryService.removeReadingLog(
            userId: userId,
            juz: _selectedJuz!,
            type: 'Grup: ${groupName ?? 'Khataman Grup'}',
          );
        }

        WidgetUpdateService.updateKhatamanWidget();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isComplete
                  ? '✅ Juz $_selectedJuz ditandai selesai! Alhamdulillah!'
                  : 'Progres berhasil disimpan!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: isComplete ? AppTheme.primaryGreen : const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      debugPrint('Error updating progress from sheet: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan progres: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    if (_isLoading) {
      return Container(
        height: 350,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryGreen),
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        height: 250,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent.shade200, size: 40),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Tutup', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    }

    // Determine current bounds for the input helper
    List<int> bounds = [1, 7];
    if (_selectedSurah != null && _surahsInJuz.containsKey(_selectedSurah)) {
      bounds = _surahsInJuz[_selectedSurah]!;
    }

    // Determine current last read surah name and verse for display
    String lastReadDisplay = 'Belum ada progres tersimpan';
    if (_currentLastAyatIndex > 0) {
      final info = _getSurahAndAyatFromAbsolute(_currentLastAyatIndex);
      final sName = quran.getSurahName(info['surah']!);
      lastReadDisplay = 'Posisi terakhir: $sName ayat ${info['ayat']}';
    }

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFFCFDFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? AppTheme.primaryGreen.withOpacity(0.3) : AppTheme.primaryGreen.withOpacity(0.15),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 45,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: AppTheme.primaryGreen, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Update Progres Mengaji',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Program dropdown
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedProgram,
              decoration: _inputDecoration('Pilih Program Khataman', Icons.event_repeat_rounded),
              dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
              items: _programOptions.map((prog) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: prog,
                  child: Text(
                    prog['name'] as String,
                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: _onProgramChanged,
            ),
            const SizedBox(height: 12),

            // Row for Juz and Surah
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Juz Dropdown (Fixed if Group, Selectable if Mandiri)
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    value: _selectedJuz,
                    decoration: _inputDecoration('Juz', Icons.layers_rounded),
                    dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
                    disabledHint: _selectedJuz != null
                        ? Text(
                            'Juz $_selectedJuz',
                            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                          )
                        : null,
                    items: _selectedProgram?['type'] == 'GROUP'
                        ? null // Disabled dropdown for groups (Juz is fixed)
                        : _juzOptions.map((juz) {
                            return DropdownMenuItem<int>(
                              value: juz,
                              child: Text(
                                'Juz $juz',
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                              ),
                            );
                          }).toList(),
                    onChanged: _selectedProgram?['type'] == 'GROUP' ? null : _onJuzChanged,
                  ),
                ),
                const SizedBox(width: 10),

                // Surah Dropdown
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<int>(
                    value: _selectedSurah,
                    decoration: _inputDecoration('Surat', Icons.menu_book_rounded),
                    dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
                    items: _surahOptions.map((surahNum) {
                      return DropdownMenuItem<int>(
                        value: surahNum,
                        child: Text(
                          quran.getSurahName(surahNum),
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _markAsComplete ? null : _onSurahChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Verses input helper & input box
            if (!_markAsComplete) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ayatController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('Ayat Terakhir Dibaca', Icons.format_list_numbered_rounded),
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Verse bounds tip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Batas Ayat:',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${bounds[0]} s.d ${bounds[1]}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Current progress indicator
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  lastReadDisplay,
                  style: TextStyle(
                    fontSize: 11,
                    color: _currentLastAyatIndex > 0 ? AppTheme.accentGold : theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Checkbox to complete the whole Juz
            CheckboxListTile(
              value: _markAsComplete,
              title: const Text(
                'Saya telah menyelesaikan Juz ini',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Menandai progres Juz $_selectedJuz sebagai 100% Selesai.',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
              activeColor: AppTheme.primaryGreen,
              checkColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _markAsComplete = val;
                  if (val) {
                    _selectedSurah = _surahOptions.last;
                    _ayatController.text = _surahsInJuz[_selectedSurah]![1].toString();
                  } else {
                    _onJuzChanged(_selectedJuz);
                  }
                });
              },
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(
                        color: isDark ? Colors.white24 : Colors.grey.shade400,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Simpan Progres',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String labelText, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isDark ? Colors.white60 : Colors.black54,
      ),
      prefixIcon: Icon(icon, color: AppTheme.primaryGreen, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.01),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.primaryGreen, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
    );
  }
}
