import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../features/group/presentation/group_detail_screen.dart';
import '../features/group/presentation/juz_assignment_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];
  Map<String, String> _memberStatuses = {}; // key: "${groupId}_${senderId}" -> approval_status
  final Set<String> _processingNotifIds = {};

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final list = await NotificationService.getAll();
    
    // Batch fetch status group members untuk JOIN_REQUEST
    final Map<String, String> statuses = {};
    try {
      final joinRequests = list.where((n) {
        return n['type'] == 'JOIN_REQUEST' && 
               n['group_id'] != null && 
               n['sender_id'] != null;
      }).toList();

      if (joinRequests.isNotEmpty) {
        final List<String> groupIds = joinRequests.map((n) => n['group_id'] as String).toSet().toList();
        final List<String> senderIds = joinRequests.map((n) => n['sender_id'] as String).toSet().toList();

        final memberStatuses = await Supabase.instance.client
            .from('group_members')
            .select('group_id, user_id, approval_status')
            .inFilter('group_id', groupIds)
            .inFilter('user_id', senderIds);

        for (final m in memberStatuses) {
          final gid = m['group_id'] as String;
          final uid = m['user_id'] as String;
          final status = m['approval_status'] as String? ?? 'PENDING';
          statuses['${gid}_$uid'] = status;
        }
      }
    } catch (e) {
      debugPrint('Error batch-fetching member statuses: $e');
    }

    if (mounted) {
      setState(() {
        _notifications = list;
        _memberStatuses = statuses;
        _isLoading = false;
      });
    }
  }

  Future<void> _approveJoinRequest(Map<String, dynamic> notif) async {
    final notifId = notif['id'] as String;
    final groupId = notif['group_id'] as String?;
    final senderId = notif['sender_id'] as String?;
    
    if (groupId == null || senderId == null) return;
    
    setState(() {
      _processingNotifIds.add(notifId);
    });

    try {
      final client = Supabase.instance.client;
      
      // Update status keanggotaan
      await client
          .from('group_members')
          .update({'approval_status': 'APPROVED'})
          .eq('user_id', senderId)
          .eq('group_id', groupId);

      // Update tipe notifikasi asli di DB agar permanen disetujui
      await client
          .from('notifications')
          .update({
            'type': 'JOIN_APPROVED',
            'title': 'Permintaan Disetujui',
          })
          .eq('id', notifId);

      // Kirim notifikasi ke pemohon
      try {
        String groupName = 'Grup';
        if (notif['groups'] != null && notif['groups']['nama_grup'] != null) {
          groupName = notif['groups']['nama_grup'] as String;
        }
        await NotificationService.send(
          userId: senderId,
          type: 'JOIN_APPROVED',
          title: 'Permintaan Bergabung Disetujui',
          body: 'Selamat! Permintaan Anda bergabung ke grup "$groupName" telah disetujui.',
          groupId: groupId,
        );
      } catch (notifErr) {
        debugPrint('Error sending approved notification: $notifErr');
      }

      // Tandai notifikasi pembuat/admin sebagai telah dibaca
      await NotificationService.markAsRead(notifId);

      // Update state lokal
      if (mounted) {
        setState(() {
          _memberStatuses['${groupId}_$senderId'] = 'APPROVED';
          // Mark notification as read locally and set type
          final idx = _notifications.indexWhere((element) => element['id'] == notifId);
          if (idx != -1) {
            _notifications[idx]['is_read'] = true;
            _notifications[idx]['type'] = 'JOIN_APPROVED';
            _notifications[idx]['title'] = 'Permintaan Disetujui';
          }
          _processingNotifIds.remove(notifId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permintaan bergabung berhasil disetujui'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processingNotifIds.remove(notifId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyetujui permintaan: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _rejectJoinRequest(Map<String, dynamic> notif) async {
    final notifId = notif['id'] as String;
    final groupId = notif['group_id'] as String?;
    final senderId = notif['sender_id'] as String?;
    
    if (groupId == null || senderId == null) return;

    // Tampilkan dialog konfirmasi sebelum menolak untuk menghindari salah pencet
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tolak Permintaan?'),
        content: const Text('Apakah Anda yakin ingin menolak permintaan bergabung ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    
    setState(() {
      _processingNotifIds.add(notifId);
    });

    try {
      final client = Supabase.instance.client;
      
      // Hapus data keanggotaan
      await client
          .from('group_members')
          .delete()
          .eq('user_id', senderId)
          .eq('group_id', groupId);

      // Update tipe notifikasi asli di DB agar permanen ditolak
      await client
          .from('notifications')
          .update({
            'type': 'JOIN_REJECTED',
            'title': 'Permintaan Ditolak',
          })
          .eq('id', notifId);

      // Tandai notifikasi sebagai telah dibaca
      await NotificationService.markAsRead(notifId);

      // Update state lokal
      if (mounted) {
        setState(() {
          _memberStatuses.remove('${groupId}_$senderId'); // status menjadi null (artinya ditolak/dihapus)
          // Mark notification as read locally and set type
          final idx = _notifications.indexWhere((element) => element['id'] == notifId);
          if (idx != -1) {
            _notifications[idx]['is_read'] = true;
            _notifications[idx]['type'] = 'JOIN_REJECTED';
            _notifications[idx]['title'] = 'Permintaan Ditolak';
          }
          _processingNotifIds.remove(notifId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permintaan bergabung berhasil ditolak'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processingNotifIds.remove(notifId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menolak permintaan: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    // Show quick loading indicator
    setState(() => _isLoading = true);
    await NotificationService.markAllAsRead();
    await _loadNotifications();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Semua notifikasi telah ditandai dibaca')),
    );
  }

  Future<void> _deleteNotification(String notifId) async {
    setState(() {
      _processingNotifIds.add(notifId);
    });

    try {
      await NotificationService.delete(notifId);
      
      if (mounted) {
        setState(() {
          _notifications.removeWhere((n) => n['id'] == notifId);
          _processingNotifIds.remove(notifId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifikasi berhasil dihapus 🗑️'),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processingNotifIds.remove(notifId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus notifikasi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _deleteAllNotifications() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFFAFCFA),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Hapus Semua Notifikasi?',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Apakah Anda yakin ingin menghapus seluruh riwayat notifikasi Anda? Tindakan ini tidak dapat dibatalkan.',
            style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF5F6E65)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Batal',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus Semua', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await NotificationService.deleteAll();
      await _loadNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seluruh notifikasi berhasil dibersihkan'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus semua notifikasi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notif) async {
    final notifId = notif['id'] as String;
    final isRead = notif['is_read'] as bool? ?? false;
    final groupId = notif['group_id'] as String?;

    if (!isRead) {
      await NotificationService.markAsRead(notifId);
      // Update local state quietly
      if (mounted) {
        setState(() {
          final idx = _notifications.indexWhere((element) => element['id'] == notifId);
          if (idx != -1) {
            _notifications[idx]['is_read'] = true;
          }
        });
      }
    }

    if (groupId != null && mounted) {
      // Find the group name
      String groupName = 'Detail Grup';
      if (notif['groups'] != null && notif['groups']['nama_grup'] != null) {
        groupName = notif['groups']['nama_grup'] as String;
      }

      final String? type = notif['type'] as String?;
      if (type == 'RELEASE_REQUEST') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JuzAssignmentScreen(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        ).then((_) => _loadNotifications());
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupDetailScreen(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        ).then((_) => _loadNotifications()); // Reload on back to reflect changes
      }
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'MEMBER_JOINED':
        return Icons.person_add_rounded;
      case 'JOIN_REQUEST':
        return Icons.group_add_rounded;
      case 'JOIN_CANCELLED':
      case 'JOIN_REJECTED':
      case 'RELEASE_REJECTED':
        return Icons.cancel_outlined;
      case 'JOIN_APPROVED':
      case 'RELEASE_APPROVED':
        return Icons.check_circle_rounded;
      case 'JUZ_COMPLETED':
        return Icons.menu_book_rounded;
      case 'KHATAMAN_COMPLETE':
        return Icons.emoji_events_rounded;
      case 'RELEASE_REQUEST':
        return Icons.assignment_return_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'MEMBER_JOINED':
        return AppTheme.primaryGreen;
      case 'JOIN_REQUEST':
        return AppTheme.accentGold;
      case 'JOIN_CANCELLED':
        return Colors.grey;
      case 'JOIN_REJECTED':
      case 'RELEASE_REJECTED':
        return Colors.redAccent;
      case 'JOIN_APPROVED':
      case 'RELEASE_APPROVED':
        return AppTheme.primaryGreen;
      case 'JUZ_COMPLETED':
        return AppTheme.accentGold;
      case 'KHATAMAN_COMPLETE':
        return Colors.orangeAccent;
      case 'RELEASE_REQUEST':
        return Colors.orangeAccent;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dateTime = DateTime.parse(dateStr).toLocal();
      final difference = DateTime.now().difference(dateTime);

      if (difference.inSeconds < 60) {
        return 'Baru saja';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} menit yang lalu';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} jam yang lalu';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} hari yang lalu';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !(n['is_read'] as bool? ?? false)).length;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFEEEEEE),
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all_rounded),
              tooltip: 'Tandai semua dibaca',
              onPressed: _markAllAsRead,
            ),
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Hapus semua notifikasi',
              onPressed: _deleteAllNotifications,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBgGradient
              : AppTheme.lightBgGradient,
        ),
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          color: AppTheme.primaryGreen,
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> notif, String notifId, String groupId, String senderId, String? approvalStatus, String type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. Jika tipe notifikasi sudah permanen JOIN_CANCELLED, JOIN_REJECTED, atau JOIN_APPROVED
    if (type == 'JOIN_CANCELLED') {
      return _buildStatusBadge(
        context,
        icon: Icons.cancel_outlined,
        text: 'Permintaan dibatalkan',
        color: isDark ? Colors.white60 : Colors.grey.shade700,
        bgColor: Colors.grey.withOpacity(0.12),
        borderColor: Colors.grey.withOpacity(0.35),
      );
    }

    if (type == 'JOIN_REJECTED') {
      return _buildStatusBadge(
        context,
        icon: Icons.cancel_rounded,
        text: 'Permintaan ditolak',
        color: Colors.redAccent,
        bgColor: Colors.redAccent.withOpacity(0.1),
        borderColor: Colors.redAccent.withOpacity(0.3),
      );
    }

    if (type == 'JOIN_APPROVED' || approvalStatus == 'APPROVED') {
      return _buildStatusBadge(
        context,
        icon: Icons.check_circle_rounded,
        text: 'Permintaan disetujui',
        color: AppTheme.primaryGreen,
        bgColor: AppTheme.primaryGreen.withOpacity(0.1),
        borderColor: AppTheme.primaryGreen.withOpacity(0.3),
      );
    }

    final isProcessing = _processingNotifIds.contains(notifId);

    if (isProcessing) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: AppTheme.primaryGreen,
          ),
        ),
      );
    }

    if (approvalStatus == null) {
      // Jika statusnya null (data keanggotaan terhapus di group_members),
      // namun tipe notifikasi bukan JOIN_REJECTED (karena kalau ditolak oleh admin tipenya diubah ke JOIN_REJECTED),
      // maka ini berarti permintaan dibatalkan oleh pemohon!
      return _buildStatusBadge(
        context,
        icon: Icons.cancel_outlined,
        text: 'Permintaan bergabung dibatalkan',
        color: isDark ? Colors.white60 : Colors.grey.shade700,
        bgColor: Colors.grey.withOpacity(0.12),
        borderColor: Colors.grey.withOpacity(0.35),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: () => _approveJoinRequest(notif),
              icon: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              label: const Text('Setujui', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: () => _rejectJoinRequest(notif),
              icon: const Icon(Icons.close_rounded, size: 14, color: Colors.redAccent),
              label: const Text('Tolak', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      );
    }

    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
                  ),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 64,
                    color: onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Belum Ada Notifikasi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Aktivitas grup Anda akan muncul di sini.',
                  style: TextStyle(
                    fontSize: 14,
                    color: onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notif = _notifications[index];
        final isRead = notif['is_read'] as bool? ?? false;
        var type = notif['type'] as String? ?? 'GENERAL';
        var title = notif['title'] as String? ?? '';
        final body = notif['body'] as String? ?? '';
        final timeStr = _formatTime(notif['created_at'] as String?);
        final notifId = notif['id'] as String;
        final groupId = notif['group_id'] as String?;
        final senderId = notif['sender_id'] as String?;

        // Deteksi apakah notifikasi ini sudah digantikan oleh aktivitas yang lebih baru
        bool isSuperseded = false;
        if (type == 'JOIN_REQUEST' && groupId != null && senderId != null) {
          for (int j = 0; j < index; j++) {
            final other = _notifications[j];
            if (other['group_id'] == groupId && other['sender_id'] == senderId) {
              isSuperseded = true;
              break;
            }
          }
        }

        if (isSuperseded) {
          type = 'JOIN_CANCELLED';
          title = 'Permintaan Dibatalkan';
        }

        final cardBg = isRead
            ? (isDark ? AppTheme.bgCard : Colors.white)
            : (isDark ? AppTheme.bgCardLight.withOpacity(0.7) : const Color(0xFFEBFDF3));

        return Dismissible(
          key: Key(notifId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
          ),
          onDismissed: (direction) {
            _deleteNotification(notifId);
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => _handleNotificationTap(notif),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isRead 
                      ? Colors.transparent 
                      : AppTheme.primaryGreen.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: isRead 
                    ? [] 
                    : [
                        BoxShadow(
                          color: AppTheme.primaryGreen.withOpacity(0.08),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Indicator / Icon
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getColorForType(type).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIconForType(type),
                          color: _getColorForType(type),
                          size: 24,
                        ),
                      ),
                      if (!isRead)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Texts
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                  color: onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _deleteNotification(notifId),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: onSurfaceVariant.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 13,
                            color: isRead ? onSurfaceVariant : onSurface.withOpacity(0.9),
                            height: 1.4,
                          ),
                        ),
                        if ((type == 'JOIN_REQUEST' || type == 'JOIN_CANCELLED') && groupId != null && senderId != null)
                          GestureDetector(
                            onTap: () {}, // Mencegah tap card terpicu saat menekan tombol aksi
                            child: _buildActionButtons(
                              notif,
                              notifId,
                              groupId,
                              senderId,
                              _memberStatuses['${groupId}_$senderId'],
                              type,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    );
  }
}
