import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../controller/juz_assignment_controller.dart';
import '../data/models/slot_khataman_model.dart';
import '../data/models/group_member_model.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/localization.dart';

class JuzAssignmentScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const JuzAssignmentScreen({
    Key? key,
    required this.groupId,
    required this.groupName,
  }) : super(key: key);

  @override
  State<JuzAssignmentScreen> createState() => _JuzAssignmentScreenState();
}

class _JuzAssignmentScreenState extends State<JuzAssignmentScreen> with SingleTickerProviderStateMixin {
  final List<GlobalKey> _juzKeys = List.generate(30, (index) => GlobalKey());
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  RealtimeChannel? _subscription;
  late JuzAssignmentController _controller;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_pulseController);
    
    _controller = JuzAssignmentController();
    _controller.fetchData(widget.groupId);
    _setupRealtime();
  }

  @override
  void dispose() {
    if (_subscription != null) {
      try {
        Supabase.instance.client.removeChannel(_subscription!);
      } catch (e) {
        debugPrint('Error removing realtime channel: $e');
      }
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    final channelName = 'juz_assignment_${widget.groupId}';
    _subscription = Supabase.instance.client.channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'slot_khataman',
          callback: (payload) {
            debugPrint('🔄 [Realtime Admin Grid] Slot khataman changed. Syncing...');
            _controller.fetchData(widget.groupId, silent: true);
          },
        )
        .subscribe();
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '??';
    final cleanName = name.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
    if (cleanName.isEmpty) return '??';
    final parts = cleanName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    if (cleanName.length >= 2) {
      return cleanName.substring(0, 2).toUpperCase();
    }
    return cleanName.toUpperCase();
  }

  Color _getReadableTextColor(Color bg, bool isDark) {
    if (isDark) {
      return bg;
    } else {
      final hsl = HSLColor.fromColor(bg);
      if (hsl.lightness > 0.5) {
        return hsl.withLightness((hsl.lightness - 0.25).clamp(0.2, 0.55)).toColor();
      }
      return Colors.white;
    }
  }

  Future<void> _handleJuzTap(BuildContext context, SlotKhatamanModel slot, int index) async {
    final action = _controller.checkTapAction(index);

    if (action == 'PENDING') {
      final claimedUsername = slot.user?.username ?? 'Anggota';
      final String? claimedUserId = slot.userId;
      final int juzNo = slot.nomorJuz;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            context.translate('juz_assign_notif_release_req_title'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            context.translate('juz_assign_notif_release_req_body')
                .replaceFirst('{user}', claimedUsername)
                .replaceFirst('{juz}', juzNo.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.translate('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _controller.approveRelease(
                    groupId: widget.groupId,
                    slotId: slot.idSlot,
                    claimedUserId: claimedUserId,
                    groupName: widget.groupName,
                    claimedUsername: claimedUsername,
                    juzNo: juzNo,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.translate('juz_assign_success_release').replaceFirst('{juz}', juzNo.toString())),
                      backgroundColor: AppTheme.primaryGreen,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.translate('juz_assign_err_approve').replaceFirst('{error}', e.toString())),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: Text(context.translate('notif_btn_approve_action')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _controller.rejectRelease(
                    groupId: widget.groupId,
                    slotId: slot.idSlot,
                    claimedUserId: claimedUserId,
                    groupName: widget.groupName,
                    juzNo: juzNo,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.translate('juz_assign_success_reject').replaceFirst('{juz}', juzNo.toString())),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.translate('juz_assign_err_reject').replaceFirst('{error}', e.toString())),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(context.translate('notif_btn_reject_action')),
            ),
          ],
        ),
      );
      return;
    }

    final String? previousUserId = slot.userId;
    String? newUserId = _controller.selectedBrushUserId == 'eraser' ? null : _controller.selectedBrushUserId;
    UserProfile? newUserProfile;

    if (previousUserId == newUserId && newUserId != null) {
      newUserId = null;
    } else if (newUserId != null) {
      final member = _controller.members.firstWhere(
        (m) => m.userId == newUserId,
        orElse: () => GroupMember(groupId: '', userId: '', role: '', approvalStatus: '', prioritasJatah: false),
      );
      if (member.userId.isNotEmpty) {
        newUserProfile = member.user;
      }
    }

    Future<void> proceedWithChange() async {
      if (newUserId != null && _controller.isQuotaReached(newUserId)) {
        final memberCount = _controller.members.isEmpty ? 1 : _controller.members.length;
        final batasMaksimal = (30 / memberCount).ceil();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.translate('juz_assign_err_limit_exceeded').replaceFirst('{limit}', batasMaksimal.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (action == 'WARN_TRANSFER') {
        showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(
              context.translate('juz_assign_transfer_title'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              context.translate('juz_assign_transfer_body'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.translate('juz_assign_transfer_no')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(context.translate('juz_assign_transfer_yes')),
              ),
            ],
          ),
        ).then((confirmed) {
          if (confirmed == true) {
            _controller.setHasShownTransferWarning(true);
            _controller.applySlotChange(index, newUserId, newUserProfile);
          }
        });
      } else {
        _controller.applySlotChange(index, newUserId, newUserProfile);
      }
    }

    if (action == 'LOCKED') {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 8),
              Text(
                context.translate('juz_assign_progress_exists_title'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          content: Text(
            context.translate('juz_assign_progress_exists_body').replaceFirst('{juz}', slot.nomorJuz.toString()),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.translate('btn_cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(context.translate('juz_assign_progress_exists_yes')),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true) {
          proceedWithChange();
        }
      });
      return;
    }

    proceedWithChange();
  }

  Future<bool> _showUnsavedChangesDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.accentGold),
            const SizedBox(width: 8),
            Text(
              context.translate('juz_assign_confirm_save_title'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          context.translate('juz_assign_confirm_save_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(context.translate('juz_assign_confirm_save_discard')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: Text(context.translate('btn_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(context.translate('btn_save')),
          ),
        ],
      ),
    );

    if (result == null) {
      return false;
    }

    if (result == true) {
      final success = await _controller.saveDraftChanges(widget.groupId);
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.translate('juz_assign_confirm_save_success')),
            backgroundColor: AppTheme.primaryGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return success;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<JuzAssignmentController>.value(
      value: _controller,
      child: Consumer<JuzAssignmentController>(
        builder: (context, controller, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final scaffoldBg = isDark ? const Color(0xFF0F141C) : const Color(0xFFF4F7F5);
          final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
          final primaryTextColor = isDark ? Colors.white : const Color(0xFF1A2B20);
          final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF5F6E65);
          final dividerColor = isDark ? Colors.white10 : Colors.grey.shade200;

          return PopScope(
            canPop: !controller.hasUnsavedChanges(),
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              final shouldPop = await _showUnsavedChangesDialog(context);
              if (shouldPop && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              backgroundColor: scaffoldBg,
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate('juz_assign_title'),
                      style: TextStyle(
                        color: primaryTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.groupName,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                backgroundColor: cardBg,
                elevation: 0,
                iconTheme: IconThemeData(color: primaryTextColor),
                actions: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.translate('group_detail_settings_limit'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: controller.limitJuz,
                          activeColor: AppTheme.primaryGreen,
                          activeTrackColor: AppTheme.primaryGreen.withOpacity(0.4),
                          onChanged: (val) async {
                            try {
                              await controller.toggleLimitJuz(widget.groupId, val);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      val
                                          ? '🔒 Batasan pengambilan Juz diaktifkan!'
                                          : '🔓 Batasan pengambilan Juz dinonaktifkan!',
                                    ),
                                    backgroundColor: AppTheme.primaryGreen,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal mengubah batasan: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1.0),
                  child: Container(
                    color: dividerColor,
                    height: 1.0,
                  ),
                ),
              ),
              body: controller.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── SECTION 1: DAFTAR ANGGOTA (BAGIAN ATAS) ──
                        Container(
                          color: cardBg,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      context.translate('juz_assign_brush_members'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        controller.setSelectedBrushUserId('eraser');
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: controller.selectedBrushUserId == 'eraser'
                                              ? Colors.redAccent.withOpacity(0.12)
                                              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: controller.selectedBrushUserId == 'eraser'
                                                ? Colors.redAccent
                                                : (isDark ? Colors.white12 : Colors.grey.shade300),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.delete_sweep_outlined,
                                              size: 13,
                                              color: controller.selectedBrushUserId == 'eraser'
                                                  ? Colors.redAccent
                                                  : secondaryTextColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              context.translate('juz_assign_brush_eraser'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: controller.selectedBrushUserId == 'eraser'
                                                    ? Colors.redAccent
                                                    : secondaryTextColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 78,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: controller.members.length,
                                  itemBuilder: (ctx, index) {
                                    final member = controller.members[index];
                                    final userId = member.userId;
                                    final username = member.user?.username ?? 'Umum';
                                    final initials = controller.uniqueInitials[userId] ?? _getInitials(username);
                                    final pastelBg = controller.memberColors[userId] ?? controller.getPastelColor(username);
                                    final isSelected = controller.selectedBrushUserId == userId;
                                    final hasSelection = controller.selectedBrushUserId != 'eraser';
                                    final isDimmed = hasSelection && !isSelected;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: GestureDetector(
                                        onTap: () {
                                          if (controller.selectedBrushUserId == userId) {
                                            controller.setSelectedBrushUserId('eraser');
                                          } else {
                                            controller.setSelectedBrushUserId(userId);
                                          }
                                        },
                                        child: AnimatedOpacity(
                                          duration: const Duration(milliseconds: 200),
                                          opacity: isDimmed ? 0.45 : 1.0,
                                          child: Column(
                                            children: [
                                              AnimatedBuilder(
                                                animation: _pulseAnimation,
                                                builder: (context, child) {
                                                  return AnimatedContainer(
                                                    duration: const Duration(milliseconds: 200),
                                                    padding: EdgeInsets.all(isSelected ? 3.0 : 0),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? (isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF1D2A22).withOpacity(0.9))
                                                            : Colors.transparent,
                                                        width: isSelected ? 2.0 : 0,
                                                      ),
                                                      boxShadow: isSelected
                                                          ? [
                                                              BoxShadow(
                                                                color: (isDark ? AppTheme.accentTeal : AppTheme.primaryGreen)
                                                                    .withOpacity(0.25 + (_pulseAnimation.value * 0.45)),
                                                                blurRadius: 6.0 + (_pulseAnimation.value * 8.0),
                                                                spreadRadius: 1.0 + (_pulseAnimation.value * 2.0),
                                                              )
                                                            ]
                                                          : null,
                                                    ),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(milliseconds: 200),
                                                      width: isSelected ? 48 : 50,
                                                      height: isSelected ? 48 : 50,
                                                      decoration: BoxDecoration(
                                                        color: pastelBg,
                                                        shape: BoxShape.circle,
                                                        boxShadow: !isSelected
                                                            ? [
                                                                BoxShadow(
                                                                  color: Colors.black.withOpacity(0.04),
                                                                  blurRadius: 4,
                                                                  offset: const Offset(0, 2),
                                                                )
                                                              ]
                                                            : null,
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          initials,
                                                          style: const TextStyle(
                                                            color: Color(0xFF1C2D21),
                                                            fontWeight: FontWeight.w800,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 5),
                                              SizedBox(
                                                width: 54,
                                                child: Text(
                                                  '@$username',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                    color: isSelected
                                                        ? _getReadableTextColor(pastelBg, isDark)
                                                        : primaryTextColor,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          color: dividerColor,
                          height: 1.0,
                        ),

                        // Instruction Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: isDark ? const Color(0xFF131A26) : const Color(0xFFEBF2EE),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final memberCount = controller.members.isEmpty ? 1 : controller.members.length;
                                    final batasMinimal = (30 / memberCount).floor();
                                    final batasMaksimal = (30 / memberCount).ceil();

                                    final isEn = Provider.of<SettingsProvider>(context, listen: false).language == 'en';
                                    String text = controller.selectedBrushUserId == 'eraser'
                                        ? context.translate('juz_assign_brush_info_delete')
                                        : context.translate('juz_assign_brush_info_draw');

                                    if (controller.limitJuz) {
                                      if (batasMinimal == batasMaksimal) {
                                        text += isEn 
                                            ? '\n🔒 Limits Active: Each member holds $batasMinimal Juz.'
                                            : '\n🔒 Fitur Batasi Aktif: Setiap anggota memegang $batasMinimal Juz.';
                                      } else {
                                        text += isEn
                                            ? '\n🔒 Limits Active: Each member holds between $batasMinimal and $batasMaksimal Juz.'
                                            : '\n🔒 Fitur Batasi Aktif: Setiap anggota memegang antara $batasMinimal sampai $batasMaksimal Juz.';
                                      }
                                    }

                                    return Text(
                                      text,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? AppTheme.accentTeal : AppTheme.primaryGreen,
                                      ),
                                    );
                                  }
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── SECTION 2: KOTAK GRID JUZ ──
                        Expanded(
                          child: controller.activeCycle == null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.hourglass_empty_rounded,
                                        size: 48,
                                        color: secondaryTextColor.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        context.translate('juz_assign_empty_cycle'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: primaryTextColor,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        context.translate('juz_assign_empty_cycle_desc'),
                                        style: TextStyle(
                                          color: secondaryTextColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : GestureDetector(
                                  onPanStart: (details) {
                                    controller.clearDraggedJuzIndices();
                                    controller.detectDragSelection(details.globalPosition, _juzKeys);
                                  },
                                  onPanUpdate: (details) {
                                    controller.detectDragSelection(details.globalPosition, _juzKeys);
                                  },
                                  child: GridView.builder(
                                    physics: const ClampingScrollPhysics(),
                                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 5,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 1.0,
                                    ),
                                    itemCount: 30,
                                    itemBuilder: (ctx, index) {
                                      final juzNumber = index + 1;
                                      final slot = controller.slots.firstWhere(
                                        (s) => s.nomorJuz == juzNumber,
                                        orElse: () => SlotKhatamanModel(
                                          idSlot: '',
                                          idPutaran: '',
                                          nomorJuz: juzNumber,
                                          ayatTerakhirInput: 0,
                                          statusChecklist: false,
                                        ),
                                      );

                                      if (slot.idSlot.isEmpty) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '$juzNumber',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: secondaryTextColor.withOpacity(0.5),
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      final String? claimedUserId = slot.userId;
                                      final claimedUsername = slot.user?.username;
                                      final hasClaim = claimedUserId != null;
                                      final claimerColor = hasClaim
                                          ? (controller.memberColors[claimedUserId] ?? controller.getPastelColor(claimedUsername ?? ''))
                                          : Colors.transparent;
                                      final claimerInitials = hasClaim
                                          ? (controller.uniqueInitials[claimedUserId] ?? _getInitials(claimedUsername))
                                          : '';
                                      final bool isPending = slot.isPendingRelease;

                                      return GestureDetector(
                                        key: _juzKeys[index],
                                        onTap: () => _handleJuzTap(context, slot, index),
                                        child: AnimatedBuilder(
                                          animation: _pulseAnimation,
                                          builder: (ctx, child) {
                                            return AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              decoration: BoxDecoration(
                                                color: hasClaim
                                                    ? (isPending
                                                        ? claimerColor.withOpacity(isDark ? 0.05 : 0.09)
                                                        : claimerColor.withOpacity(isDark ? 0.12 : 0.20))
                                                    : cardBg,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isPending
                                                      ? claimerColor.withOpacity(0.2 + (_pulseAnimation.value * 0.7))
                                                      : (hasClaim
                                                          ? claimerColor.withOpacity(isDark ? 0.4 : 0.6)
                                                          : (isDark ? Colors.white10 : Colors.grey.shade300)),
                                                  width: isPending ? 3.0 : (hasClaim ? 1.5 : 1),
                                                ),
                                                boxShadow: isPending
                                                    ? [
                                                        BoxShadow(
                                                          color: claimerColor.withOpacity(0.4 * _pulseAnimation.value),
                                                          blurRadius: 6,
                                                          spreadRadius: 1,
                                                        )
                                                      ]
                                                    : (hasClaim
                                                        ? null
                                                        : [
                                                            BoxShadow(
                                                              color: Colors.black.withOpacity(0.02),
                                                              blurRadius: 4,
                                                              offset: const Offset(0, 1),
                                                            )
                                                          ]),
                                              ),
                                              child: child,
                                            );
                                          },
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: Text(
                                                  '$juzNumber',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: hasClaim
                                                        ? (isDark ? Colors.white : Colors.grey.shade800)
                                                        : primaryTextColor,
                                                  ),
                                                ),
                                              ),
                                              if (hasClaim && slot.hasProgress)
                                                Positioned(
                                                  top: 5,
                                                  right: 5,
                                                  child: Icon(
                                                    Icons.lock_rounded,
                                                    size: 11,
                                                    color: isDark
                                                        ? Colors.white.withOpacity(0.4)
                                                        : Colors.black.withOpacity(0.35),
                                                  ),
                                                ),
                                              if (isPending)
                                                Positioned(
                                                  top: 5,
                                                  left: 5,
                                                  child: Icon(
                                                    Icons.hourglass_empty_rounded,
                                                    size: 11,
                                                    color: claimerColor.withOpacity(0.5 + (_pulseAnimation.value * 0.5)),
                                                  ),
                                                ),
                                              if (hasClaim)
                                                Positioned(
                                                  bottom: 4,
                                                  right: 4,
                                                  child: Container(
                                                    width: 18,
                                                    height: 18,
                                                    decoration: BoxDecoration(
                                                      color: claimerColor,
                                                      shape: BoxShape.circle,
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withOpacity(0.1),
                                                          blurRadius: 2,
                                                          spreadRadius: 0.5,
                                                        )
                                                      ],
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        claimerInitials,
                                                        style: const TextStyle(
                                                          color: Color(0xFF1C2D21),
                                                          fontSize: 8,
                                                          fontWeight: FontWeight.w900,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        if (controller.activeCycle != null)
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: dividerColor,
                                    width: 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton.icon(
                                      onPressed: controller.hasUnsavedChanges() ? controller.resetDraftChanges : null,
                                      icon: Icon(
                                        Icons.restart_alt_rounded,
                                        size: 16,
                                        color: controller.hasUnsavedChanges()
                                            ? (isDark ? AppTheme.accentGold : Colors.orange.shade800)
                                            : secondaryTextColor.withOpacity(0.4),
                                      ),
                                      label: Text(
                                        context.translate('juz_assign_btn_reset'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: controller.hasUnsavedChanges()
                                              ? (isDark ? AppTheme.accentGold : Colors.orange.shade800)
                                              : secondaryTextColor.withOpacity(0.4),
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        controller.clearAllSlots();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(context.translate('juz_assign_success_reset')),
                                            backgroundColor: Colors.redAccent,
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.delete_sweep_outlined,
                                        size: 16,
                                        color: Colors.redAccent,
                                      ),
                                      label: Text(
                                        context.translate('juz_assign_btn_clear_all'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
