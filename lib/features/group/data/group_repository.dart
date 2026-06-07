import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/group_model.dart';
import 'models/putaran_model.dart';
import 'models/slot_khataman_model.dart';
import 'models/group_member_model.dart';

class GroupRepository {
  final SupabaseClient _supabase;

  GroupRepository({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  SupabaseClient get client => _supabase;

  // 1. Fetch Group Metadata
  Future<GroupModel> getGroup(String groupId) async {
    final data = await _supabase
        .from('groups')
        .select('*')
        .eq('id_group', groupId)
        .single();
    return GroupModel.fromJson(data);
  }

  // 2. Fetch Active Putaran (Cycle)
  Future<PutaranModel?> getActivePutaran(String groupId) async {
    final List<dynamic> data = await _supabase
        .from('putaran_siklus')
        .select('*')
        .eq('group_id', groupId)
        .eq('status_aktif_selesai', 'AKTIF');
    if (data.isEmpty) return null;
    return PutaranModel.fromJson(data.first as Map<String, dynamic>);
  }

  // 3. Fetch Group Members
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final List<dynamic> data = await _supabase
        .from('group_members')
        .select('*, users(*)')
        .eq('group_id', groupId);
    return data.map((json) => GroupMember.fromJson(json as Map<String, dynamic>)).toList();
  }

  // 4. Fetch Slots for a specific Putaran
  Future<List<SlotKhatamanModel>> getSlots(String putaranId) async {
    final List<dynamic> data = await _supabase
        .from('slot_khataman')
        .select('*, users(*)')
        .eq('putaran_id', putaranId);
    
    final slots = data.map((json) => SlotKhatamanModel.fromJson(json as Map<String, dynamic>)).toList();
    slots.sort((a, b) => a.nomorJuz.compareTo(b.nomorJuz));
    return slots;
  }

  // 5. Update Limit Juz flag
  Future<void> updateLimitJuz(String groupId, bool limitJuz) async {
    await _supabase
        .from('groups')
        .update({'limit_juz': limitJuz})
        .eq('id_group', groupId);
  }

  // 6. Bulk Save/Update Slots
  Future<void> updateSlots(List<SlotKhatamanModel> slots) async {
    for (final slot in slots) {
      await _supabase
          .from('slot_khataman')
          .update({
            'user_id': slot.userId,
            'approval_lepas_status': slot.approvalLepasStatus,
            'username_sebelumnya': slot.usernameSebelumnya,
            'ayat_terakhir_input': slot.ayatTerakhirInput,
            'status_checklist': slot.statusChecklist,
          })
          .eq('id_slot', slot.idSlot);
    }
  }

  // 7. Approve release request
  Future<void> approveRelease({
    required String slotId,
    required String? usernameSebelumnya,
  }) async {
    await _supabase
        .from('slot_khataman')
        .update({
          'user_id': null,
          'approval_lepas_status': null,
          'username_sebelumnya': usernameSebelumnya,
        })
        .eq('id_slot', slotId);
  }

  // 8. Reject release request
  Future<void> rejectRelease(String slotId) async {
    await _supabase
        .from('slot_khataman')
        .update({
          'approval_lepas_status': null,
        })
        .eq('id_slot', slotId);
  }

  // 9. Transfer Admin Ownership
  Future<void> transferAdmin({
    required String groupId,
    required String newAdminId,
  }) async {
    await _supabase
        .from('groups')
        .update({'creator_id': newAdminId})
        .eq('id_group', groupId);
  }

  // 10. Delete Group
  Future<void> deleteGroup(String groupId) async {
    await _supabase
        .from('groups')
        .delete()
        .eq('id_group', groupId);
  }

  // 11. Leave Group (Member)
  Future<void> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    // Delete from group_members
    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);

    // Release any slots assigned to this user in the active cycle
    final activePutaran = await getActivePutaran(groupId);
    if (activePutaran != null) {
      await _supabase
          .from('slot_khataman')
          .update({'user_id': null, 'approval_lepas_status': null})
          .eq('putaran_id', activePutaran.idPutaran)
          .eq('user_id', userId);
    }
  }
}
