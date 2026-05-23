import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      
      // Hapus log lama untuk Juz dan Mode yang sama agar tidak duplikat
      await removeReadingLog(userId: userId, juz: juz, type: type);

      // Load existing history
      final existingData = prefs.getStringList(key) ?? [];
      
      // Create new entry
      final newEntry = {
        'timestamp': DateTime.now().toIso8601String(),
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
      debugPrint('📝 [History Log] Logged successfully: Juz $juz ($type) - $description');
    } catch (e) {
      debugPrint('📝 [History Log] Error saving history: $e');
    }
  }

  // Remove logs for a specific Juz and Type to clean up duplicates / cancelled progress
  static Future<void> removeReadingLog({
    required String userId,
    required int juz,
    required String type,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      final rawList = prefs.getStringList(key) ?? [];
      
      final updatedList = rawList.where((itemJson) {
        try {
          final item = jsonDecode(itemJson) as Map<String, dynamic>;
          // Simpan semua entri KECUALI yang cocok dengan juz dan type ini
          return !(item['juz'] == juz && item['type'] == type);
        } catch (_) {
          return true;
        }
      }).toList();
      
      await prefs.setStringList(key, updatedList);
      debugPrint('📝 [History Log] Cleared log for Juz $juz ($type)');
    } catch (e) {
      debugPrint('📝 [History Log] Error removing log: $e');
    }
  }

  // Get all logs for a user
  static Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      final rawList = prefs.getStringList(key) ?? [];
      
      return rawList.map((e) => jsonDecode(e) as Map<String, dynamic>).toList().reversed.toList();
    } catch (e) {
      debugPrint('📝 [History Log] Error loading history: $e');
      return [];
    }
  }

  // Get Khatam count
  static Future<int> getKhatamCount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final khatamKey = '$_khatamCountPrefix$userId';
      return prefs.getInt(khatamKey) ?? 0;
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
    } catch (e) {
      debugPrint('📝 [History Log] Error clearing history: $e');
    }
  }
}
