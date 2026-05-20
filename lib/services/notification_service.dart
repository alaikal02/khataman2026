import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _supabase = Supabase.instance.client;

  /// Kirim notifikasi ke 1 user
  static Future<void> send({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? groupId,
    String? senderId,
  }) async {
    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'group_id': groupId,
        'sender_id': senderId,
      });
    } catch (e) {
      // Silently fail — notifikasi tidak boleh mengganggu flow utama
      print('NotificationService.send error: $e');
    }
  }

  /// Kirim notifikasi ke semua anggota grup (kecuali excludeUserId)
  static Future<void> sendToGroup({
    required String groupId,
    required String type,
    required String title,
    required String body,
    String? excludeUserId,
  }) async {
    try {
      // Ambil semua anggota APPROVED di grup ini
      final members = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .eq('approval_status', 'APPROVED');

      final rows = <Map<String, dynamic>>[];
      for (final m in members) {
        final uid = m['user_id'] as String;
        if (uid == excludeUserId) continue;
        rows.add({
          'user_id': uid,
          'type': type,
          'title': title,
          'body': body,
          'group_id': groupId,
        });
      }

      if (rows.isNotEmpty) {
        await _supabase.from('notifications').insert(rows);
      }
    } catch (e) {
      print('NotificationService.sendToGroup error: $e');
    }
  }

  /// Ambil jumlah notifikasi belum dibaca
  static Future<int> getUnreadCount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      final res = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      return (res as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Ambil semua notifikasi user (diurutkan terbaru dulu)
  static Future<List<Map<String, dynamic>>> getAll() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final res = await _supabase
          .from('notifications')
          .select('*, groups(nama_grup)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      return [];
    }
  }

  /// Tandai 1 notifikasi dibaca
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      print('NotificationService.markAsRead error: $e');
    }
  }

  /// Tandai semua notifikasi user dibaca
  static Future<void> markAllAsRead() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      print('NotificationService.markAllAsRead error: $e');
    }
  }
}
