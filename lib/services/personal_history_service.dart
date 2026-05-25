import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalHistoryService {
  static const String _keyPrefix = 'personal_history_log_';
  static const String _khatamCountPrefix = 'personal_khatam_count_';

  // Helper to normalize timestamp for safe comparison across timezones and formatting
  static String _normalizeTimestamp(String? timestampStr) {
    if (timestampStr == null) return '';
    final dt = DateTime.tryParse(timestampStr);
    if (dt == null) return timestampStr;
    // Gunakan milidetik UTC untuk standardisasi 100% konsisten
    return dt.toUtc().millisecondsSinceEpoch.toString();
  }

  // Helper to compare two timestamps safely
  static bool _areTimestampsEqual(String? t1, String? t2) {
    if (t1 == null || t2 == null) return false;
    return _normalizeTimestamp(t1) == _normalizeTimestamp(t2);
  }

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

      if (isKhatamCompletion) {
        final khatamKey = '$_khatamCountPrefix$userId';
        final currentKhatamCount = prefs.getInt(khatamKey) ?? 0;
        await prefs.setInt(khatamKey, currentKhatamCount + 1);
      }
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

  // Get all logs for a user with bidirectional cloud synchronization
  static Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      
      // 1. Load local history
      final rawList = prefs.getStringList(key) ?? [];
      final List<Map<String, dynamic>> localLogs = rawList.map((e) {
        try {
          return jsonDecode(e) as Map<String, dynamic>;
        } catch (_) {
          return <String, dynamic>{};
        }
      }).where((element) => element.isNotEmpty).toList();

      // 2. Load cloud history from Supabase (defensively)
      List<Map<String, dynamic>> cloudLogs = [];
      bool cloudFetchSuccess = false;
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentUser != null) {
          final res = await supabase
              .from('riwayat_personal')
              .select()
              .eq('user_id', userId);
          
          final list = res as List;
          cloudLogs = list.map((item) => {
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
        debugPrint('⚠️ [History Log] Cloud fetch failed: $e');
      }

      // 3. Bidirectional Sync & De-duplication
      final Map<String, Map<String, dynamic>> mergedMap = {};

      // Add local logs first
      for (final log in localLogs) {
        final timestamp = log['timestamp'] as String? ?? '';
        final juz = log['juz']?.toString() ?? '0';
        final type = log['type'] ?? '';
        
        final uniqueKey = '${_normalizeTimestamp(timestamp)}_${juz}_$type';
        mergedMap[uniqueKey] = log;
      }

      // Merge with cloud logs (Cloud is the absolute source of truth if timestamps match)
      for (final log in cloudLogs) {
        final timestamp = log['timestamp'] as String? ?? '';
        final juz = log['juz']?.toString() ?? '0';
        final type = log['type'] ?? '';
        
        final uniqueKey = '${_normalizeTimestamp(timestamp)}_${juz}_$type';
        mergedMap[uniqueKey] = log;
      }

      final List<Map<String, dynamic>> mergedList = mergedMap.values.toList();

      // Sort chronological descending (newest first)
      mergedList.sort((a, b) {
        final tA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.now();
        final tB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.now();
        return tB.compareTo(tA);
      });

      // 4. Self-Healing Write Back to SharedPreferences
      if (cloudFetchSuccess) {
        final List<String> rawToSave = mergedList.map((e) => jsonEncode(e)).toList();
        // reverse the order back because SharedPreferences was historically stored newest last (then reversed on read)
        final List<String> reversedRawToSave = rawToSave.reversed.toList();
        await prefs.setStringList(key, reversedRawToSave);
        
        // Also upload any local-only logs back to Supabase
        for (final localLog in localLogs) {
          final timestamp = localLog['timestamp'] as String? ?? '';
          final juz = localLog['juz'] as int? ?? 0;
          final type = localLog['type'] ?? '';
          
          final existsInCloud = cloudLogs.any((c) => 
            _areTimestampsEqual(c['timestamp'] as String?, timestamp) && 
            c['juz'].toString() == juz.toString() && 
            c['type'] == type
          );

          if (!existsInCloud) {
            try {
              final supabase = Supabase.instance.client;
              await supabase.from('riwayat_personal').insert({
                'user_id': userId,
                'juz': juz,
                'description': localLog['description'],
                'type': type,
                'is_juz_completion': localLog['isJuzCompletion'] ?? false,
                'is_khatam_completion': localLog['isKhatamCompletion'] ?? false,
                'created_at': timestamp,
              });
              debugPrint('📝 [History Log] Uploaded local log to Supabase: Juz $juz');
            } catch (e) {
              debugPrint('⚠️ [History Log] Upload of local log to Supabase failed: $e');
            }
          }
        }
      }

      return mergedList;
    } catch (e) {
      debugPrint('📝 [History Log] Error loading history: $e');
      return [];
    }
  }

  // Get Khatam count with dynamic self-healing directly from history log
  static Future<int> getKhatamCount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      
      // Hitung log dari data gabungan (yang sudah disinkronkan)
      final rawList = prefs.getStringList(key) ?? [];
      
      int trueCount = 0;
      for (final itemJson in rawList) {
        try {
          final item = jsonDecode(itemJson) as Map<String, dynamic>;
          // Hanya hitung khataman mandiri yang selesai penuh
          if (item['isKhatamCompletion'] == true && item['type'] == 'Mandiri') {
            trueCount++;
          }
        } catch (_) {}
      }
      
      final khatamKey = '$_khatamCountPrefix$userId';
      await prefs.setInt(khatamKey, trueCount);
      return trueCount;
    } catch (e) {
      debugPrint('📝 [History Log] Error loading khatam count: $e');
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
