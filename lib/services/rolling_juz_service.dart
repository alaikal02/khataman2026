import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service untuk algoritma pengacakan Juz cerdas (Rolling Juz).
/// Memastikan setiap anggota mendapat Juz yang belum pernah dibaca
/// di putaran sebelumnya, dengan distribusi kuota yang adil.
class RollingJuzService {
  static final _supabase = Supabase.instance.client;
  static final _random = Random();

  /// Generate pembagian Rolling Juz untuk putaran baru.
  ///
  /// Returns: List of `{nomor_juz: int, user_id: String}` siap insert ke slot_khataman.
  ///
  /// Aturan:
  /// 1. Anggota dengan `prioritas_jatah = TRUE` mendapat kuota ceil(30/N)
  /// 2. Anggota biasa mendapat kuota floor(30/N), sisa dibagi merata
  /// 3. Hindari Juz yang sudah pernah dibaca di putaran sebelumnya
  /// 4. Fallback: jika semua 30 Juz sudah pernah dibaca, izinkan overlap
  static Future<List<Map<String, dynamic>>> generateRollingAssignment({
    required String groupId,
    required String groupName,
  }) async {
    // 1. Ambil daftar anggota APPROVED beserta flag prioritas_jatah
    final membersData = await _supabase
        .from('group_members')
        .select('user_id, prioritas_jatah')
        .eq('group_id', groupId)
        .eq('approval_status', 'APPROVED');

    final List<Map<String, dynamic>> members =
        List<Map<String, dynamic>>.from(membersData);

    if (members.isEmpty) {
      throw Exception('Tidak ada anggota APPROVED di grup ini.');
    }

    final int totalMembers = members.length;
    final int batasMinimal = (30 / totalMembers).floor();
    final int batasMaksimal = (30 / totalMembers).ceil();

    // 2. Pisahkan anggota prioritas dan biasa
    final List<String> priorityMembers = [];
    final List<String> regularMembers = [];

    for (final m in members) {
      final userId = m['user_id'] as String;
      if (m['prioritas_jatah'] == true) {
        priorityMembers.add(userId);
      } else {
        regularMembers.add(userId);
      }
    }

    // 3. Hitung kuota per anggota
    // Priority members get ceil, regular members get floor
    // Adjust so total = 30
    final Map<String, int> quotaMap = {};
    int totalAssigned = 0;

    for (final uid in priorityMembers) {
      quotaMap[uid] = batasMaksimal;
      totalAssigned += batasMaksimal;
    }

    for (final uid in regularMembers) {
      quotaMap[uid] = batasMinimal;
      totalAssigned += batasMinimal;
    }

    // Distribute remaining slots to regular members (round-robin)
    int remaining = 30 - totalAssigned;
    int idx = 0;
    final allMembers = [...priorityMembers, ...regularMembers];
    while (remaining > 0) {
      final uid = allMembers[idx % allMembers.length];
      if (quotaMap[uid]! < batasMaksimal) {
        quotaMap[uid] = quotaMap[uid]! + 1;
        remaining--;
      }
      idx++;
      // Safety: break jika sudah iterasi semua anggota tapi masih ada sisa
      if (idx > allMembers.length * 2) {
        // Force distribute to anyone
        for (final uid in allMembers) {
          if (remaining <= 0) break;
          quotaMap[uid] = quotaMap[uid]! + 1;
          remaining--;
        }
        break;
      }
    }

    // 4. Ambil riwayat Juz yang sudah pernah diselesaikan per user di grup ini
    final Map<String, Set<int>> completedJuzPerUser = {};
    for (final uid in allMembers) {
      completedJuzPerUser[uid] = {};
    }

    try {
      final groupTypeStr = 'Grup: $groupName';
      final historyData = await _supabase
          .from('riwayat_personal')
          .select('user_id, juz')
          .eq('is_juz_completion', true)
          .eq('type', groupTypeStr);

      for (final row in historyData) {
        final uid = row['user_id'] as String;
        final juz = row['juz'] as int;
        if (completedJuzPerUser.containsKey(uid)) {
          completedJuzPerUser[uid]!.add(juz);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [RollingJuz] Gagal ambil riwayat personal: $e');
      // Continue with empty history — fallback to random without avoidance
    }

    // 5. Shuffled pool of Juz 1-30
    final List<int> juzPool = List.generate(30, (i) => i + 1);
    juzPool.shuffle(_random);

    // 6. Assign Juz to members using greedy algorithm with history avoidance
    final Map<String, List<int>> assignmentMap = {};
    for (final uid in allMembers) {
      assignmentMap[uid] = [];
    }

    final Set<int> assignedJuz = {};

    // Sort members by priority (priority first) then shuffle within groups
    final List<String> orderedMembers = [];
    final shuffledPriority = List<String>.from(priorityMembers)..shuffle(_random);
    final shuffledRegular = List<String>.from(regularMembers)..shuffle(_random);
    orderedMembers.addAll(shuffledPriority);
    orderedMembers.addAll(shuffledRegular);

    // First pass: assign Juz that user hasn't read before
    for (final uid in orderedMembers) {
      final quota = quotaMap[uid]!;
      final completedJuz = completedJuzPerUser[uid] ?? {};

      for (final juz in juzPool) {
        if (assignmentMap[uid]!.length >= quota) break;
        if (assignedJuz.contains(juz)) continue;
        if (!completedJuz.contains(juz)) {
          assignmentMap[uid]!.add(juz);
          assignedJuz.add(juz);
        }
      }
    }

    // Second pass: fill remaining slots with any available Juz (fallback for users who read all 30)
    for (final uid in orderedMembers) {
      final quota = quotaMap[uid]!;
      if (assignmentMap[uid]!.length >= quota) continue;

      for (final juz in juzPool) {
        if (assignmentMap[uid]!.length >= quota) break;
        if (assignedJuz.contains(juz)) continue;
        assignmentMap[uid]!.add(juz);
        assignedJuz.add(juz);
      }
    }

    // 7. Build final result
    final List<Map<String, dynamic>> result = [];
    for (final entry in assignmentMap.entries) {
      for (final juz in entry.value) {
        result.add({
          'nomor_juz': juz,
          'user_id': entry.key,
        });
      }
    }

    // Sort by nomor_juz for consistency
    result.sort((a, b) => (a['nomor_juz'] as int).compareTo(b['nomor_juz'] as int));

    debugPrint('✅ [RollingJuz] Generated ${result.length} slot assignments for $totalMembers members');
    return result;
  }
}
