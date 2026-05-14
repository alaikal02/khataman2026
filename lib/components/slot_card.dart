import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class SlotCard extends StatefulWidget {
  final Map<String, dynamic> slot;
  final bool isOwned;
  final Function(int) onRelease;
  final String? memberName; // ← Diterima dari parent, tidak perlu fetch lagi

  const SlotCard({
    Key? key,
    required this.slot,
    required this.isOwned,
    required this.onRelease,
    this.memberName,
  }) : super(key: key);

  @override
  State<SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<SlotCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late TextEditingController _ayatController;
  Map<String, dynamic>? _metadata;
  final _supabase = Supabase.instance.client;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _ayatController = TextEditingController(
      text: (widget.slot['ayat_terakhir_input'] ?? 0) > 0
          ? widget.slot['ayat_terakhir_input'].toString()
          : '',
    );
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    _fetchMetadata();
  }

  @override
  void dispose() {
    _ayatController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  Future<void> _fetchMetadata() async {
    try {
      final data = await _supabase
          .from('metadata_quran_juz')
          .select()
          .eq('nomor_juz', widget.slot['nomor_juz'])
          .maybeSingle();
      if (data != null && mounted) {
        setState(() => _metadata = data);
      }
    } catch (e) {
      debugPrint('Error fetching metadata: $e');
    }
  }

  Future<void> _saveProgress() async {
    if (_metadata == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data metadata belum siap, coba lagi'), backgroundColor: Colors.orange),
      );
      return;
    }

    final inputAyah = int.tryParse(_ayatController.text);
    if (inputAyah == null || inputAyah < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Input ayat tidak valid'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final totalAyat = _metadata!['total_ayat_dalam_juz'] as int;
    if (inputAyah > totalAyat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nomor ayat melebihi batas (Max: $totalAyat)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final isComplete = inputAyah == totalAyat;

    try {
      await _supabase.from('slot_khataman').update({
        'ayat_terakhir_input': inputAyah,
        'status_checklist': isComplete,
      }).eq('id_slot', widget.slot['id_slot']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isComplete ? '✅ Juz ${widget.slot['nomor_juz']} selesai! Alhamdulillah!' : 'Progres disimpan'),
          backgroundColor: isComplete ? AppTheme.primaryGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
        ));
        if (isComplete) {
          setState(() => _expanded = false);
          _expandController.reverse();
        }
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

  int _calculateProgress() {
    if (_metadata == null) return 0;
    final last = widget.slot['ayat_terakhir_input'] as int? ?? 0;
    final total = _metadata!['total_ayat_dalam_juz'] as int;
    if (total == 0) return 0;
    final p = ((last / total) * 100).round();
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
    final totalAyat = _metadata?['total_ayat_dalam_juz'] as int? ?? 0;

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
                  if (_metadata != null)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Surah ${_metadata!['surat_mulai_id']} ayat ${_metadata!['ayat_mulai']} — Surah ${_metadata!['surat_selesai_id']} ayat ${_metadata!['ayat_selesai']}  •  Total: $totalAyat ayat',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.isOwned && !isComplete) ...[
                    SizedBox(height: 14),
                    Text(
                      'Posisi terakhir: ayat $lastAyat / $totalAyat',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: _ayatController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Masukkan ayat terakhir (1 - $totalAyat)',
                        suffixText: '/ $totalAyat',
                        suffixStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
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