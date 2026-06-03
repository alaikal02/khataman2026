import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalHistoryService {
  static const String _keyPrefix = 'personal_history_log_';
  static const String _khatamCountPrefix = 'personal_khatam_count_';


  // Log a reading event
  static Future<void> logReading({
    required String userId,
    required int juz,
    required String description, // e.g. "Membaca Juz 15 s/d ayat 50" or "Selesai Juz 15!"
    required String type, // "Mandiri" or "Grup: Nama Grup"
    bool isJuzCompletion = false,
    bool isKhatamCompletion = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      
      // Hapus log lama untuk Juz dan Mode yang sama agar tidak duplikat di sesi aktif
      await removeReadingLog(userId: userId, juz: juz, type: type);

      // Load existing history
      final existingData = prefs.getStringList(key) ?? [];
      
      final timestamp = DateTime.now().toIso8601String();

      // Create new entry
      final newEntry = {
        'timestamp': timestamp,
        'juz': juz,
        'description': description,
        'type': type,
        'isJuzCompletion': isJuzCompletion,
        'isKhatamCompletion': isKhatamCompletion,
      };
      
      existingData.add(jsonEncode(newEntry));
      await prefs.setStringList(key, existingData);



      debugPrint('📝 [History Log] Logged locally successfully: Juz $juz ($type) - $description');

      // Attempt to sync to Supabase (defensively)
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          await supabase.from('riwayat_personal').insert({
            'user_id': userId,
            'juz': juz,
            'description': description,
            'type': type,
            'is_juz_completion': isJuzCompletion,
            'is_khatam_completion': isKhatamCompletion,
            'created_at': timestamp,
          });
          debugPrint('📝 [History Log] Synced to Supabase: Juz $juz');
        }
      } catch (e) {
        debugPrint('⚠️ [History Log] Sync to Supabase failed (this is fine if table riwayat_personal is not created yet): $e');
      }
    } catch (e) {
      debugPrint('📝 [History Log] Error saving history: $e');
    }
  }

  // Remove ONLY the latest active log for a specific Juz and Type to clean up cancelled progress
  static Future<void> removeReadingLog({
    required String userId,
    required int juz,
    required String type,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      final rawList = prefs.getStringList(key) ?? [];
      
      // Hapus hanya entri TERBARU (terakhir ditambahkan) agar tidak menghapus riwayat historis khataman lama
      final List<String> updatedList = [];
      bool deleted = false;
      
      for (final itemJson in rawList.reversed) {
        try {
          final item = jsonDecode(itemJson) as Map<String, dynamic>;
          if (!deleted && item['juz'].toString() == juz.toString() && item['type'] == type) {
            deleted = true; // Tandai sudah terhapus dan lewati item ini
            continue;
          }
        } catch (_) {}
        updatedList.add(itemJson);
      }
      
      await prefs.setStringList(key, updatedList.reversed.toList());
      debugPrint('📝 [History Log] Cleared active log locally for Juz $juz ($type)');

      // Sync deletion of only the latest entry to Supabase
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          // Ambil ID dari entri terbaru terlebih dahulu
          final res = await supabase
              .from('riwayat_personal')
              .select('id')
              .eq('user_id', userId)
              .eq('juz', juz)
              .eq('type', type)
              .order('created_at', ascending: false)
              .limit(1);

          final list = res as List;
          if (list.isNotEmpty) {
            final latestId = list.first['id'];
            await supabase.from('riwayat_personal').delete().eq('id', latestId);
            debugPrint('📝 [History Log] Synced deletion of ID $latestId to Supabase: Juz $juz ($type)');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [History Log] Sync deletion to Supabase failed: $e');
      }
    } catch (e) {
      debugPrint('📝 [History Log] Error removing log: $e');
    }
  }

  // Get all logs for a user. Supabase is the single source of truth.
  // Local SharedPreferences is used only as offline fallback cache.
  static Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';

      // 1. Try to fetch from Supabase (single source of truth)
      List<Map<String, dynamic>> cloudLogs = [];
      bool cloudFetchSuccess = false;
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          final res = await supabase
              .from('riwayat_personal')
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: false);

          final list = res as List;
          cloudLogs = list.map((item) => <String, dynamic>{
            'timestamp': item['created_at'] as String? ?? DateTime.now().toIso8601String(),
            'juz': item['juz'] as int? ?? 0,
            'description': item['description'] as String? ?? '',
            'type': item['type'] as String? ?? '',
            'isJuzCompletion': item['is_juz_completion'] as bool? ?? false,
            'isKhatamCompletion': item['is_khatam_completion'] as bool? ?? false,
          }).toList();
          cloudFetchSuccess = true;
          debugPrint('📝 [History Log] Fetched ${cloudLogs.length} logs from Supabase');
        }
      } catch (e) {
        debugPrint('⚠️ [History Log] Cloud fetch failed, falling back to local cache: $e');
      }

      if (cloudFetchSuccess) {
        // Cloud is available — use it as the definitive source.
        // Cache to SharedPreferences for offline fallback.
        final List<String> rawToSave = cloudLogs.map((e) => jsonEncode(e)).toList();
        await prefs.setStringList(key, rawToSave);
        return cloudLogs;
      }

      // 2. Fallback: Load from local cache if cloud is unavailable
      final rawList = prefs.getStringList(key) ?? [];
      final List<Map<String, dynamic>> localLogs = rawList.map((e) {
        try {
          return jsonDecode(e) as Map<String, dynamic>;
        } catch (_) {
          return <String, dynamic>{};
        }
      }).where((element) => element.isNotEmpty).toList();

      // Sort chronological descending (newest first)
      localLogs.sort((a, b) {
        final tA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.now();
        final tB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.now();
        return tB.compareTo(tA);
      });

      return localLogs;
    } catch (e) {
      debugPrint('📝 [History Log] Error loading history: $e');
      return [];
    }
  }

  // Get Khatam count from Supabase (single source of truth) with local fallback
  static Future<int> getKhatamCount(String userId) async {
    try {
      // Try Supabase first
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          final res = await supabase
              .from('riwayat_personal')
              .select('id')
              .eq('user_id', userId)
              .eq('type', 'Mandiri')
              .eq('is_khatam_completion', true);

          final count = (res as List).length;
          // Cache the count locally
          final prefs = await SharedPreferences.getInstance();
          final khatamKey = '$_khatamCountPrefix$userId';
          await prefs.setInt(khatamKey, count);
          return count;
        }
      } catch (e) {
        debugPrint('⚠️ [History Log] Cloud khatam count fetch failed: $e');
      }

      // Fallback to local
      final prefs = await SharedPreferences.getInstance();
      final khatamKey = '$_khatamCountPrefix$userId';
      return prefs.getInt(khatamKey) ?? 0;
    } catch (e) {
      debugPrint('📝 [History Log] Error loading khatam count: $e');
      return 0;
    }
  }

  // Get completed group khatams count
  static Future<int> getGroupKhatamCount(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser == null) return 0;

      final completedGroupSlots = await supabase
          .from('slot_khataman')
          .select('putaran_id, putaran_siklus!inner(id_putaran, group_id, status_aktif_selesai, groups(visibility))')
          .eq('user_id', userId)
          .eq('putaran_siklus.status_aktif_selesai', 'SELESAI');

      final slotsList = List<Map<String, dynamic>>.from(completedGroupSlots as List);
      final prefs = await SharedPreferences.getInstance();

      final archivedSlots = slotsList.where((s) {
        final p = s['putaran_siklus'] as Map<String, dynamic>?;
        final g = p?['groups'] as Map<String, dynamic>?;
        final pId = s['putaran_id'];

        final localArchived = prefs.getBool('archived_group_${p?['group_id']}_$pId') ?? false;
        return g?['visibility'] == 'ARCHIVED' || localArchived;
      }).toList();

      final cyclesMap = <dynamic, List<Map<String, dynamic>>>{};
      for (var slot in archivedSlots) {
        final pId = slot['putaran_id'];
        if (pId != null) cyclesMap.putIfAbsent(pId, () => []).add(slot);
      }

      return cyclesMap.keys.length;
    } catch (e) {
      debugPrint('📝 [History Log] Error loading group khatam count: $e');
      return 0;
    }
  }

  // Set manual Khatam count
  static Future<void> setKhatamCount(String userId, int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final khatamKey = '$_khatamCountPrefix$userId';
      await prefs.setInt(khatamKey, count);
    } catch (e) {
      debugPrint('📝 [History Log] Error setting manual khatam count: $e');
    }
  }

  // Clear history
  static Future<void> clearHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$userId');
      await prefs.remove('$_khatamCountPrefix$userId');

      // Clear from Supabase defensively
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          await supabase.from('riwayat_personal').delete().eq('user_id', userId);
          debugPrint('📝 [History Log] Cleared cloud history successfully');
        }
      } catch (e) {
        debugPrint('⚠️ [History Log] Cloud history clear failed: $e');
      }
    } catch (e) {
      debugPrint('📝 [History Log] Error clearing history: $e');
    }
  }
}
