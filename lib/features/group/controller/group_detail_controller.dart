import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/notification_service.dart';
import '../data/group_repository.dart';
import '../data/models/group_member_model.dart';
import '../data/models/group_model.dart';
import '../data/models/putaran_model.dart';
import '../data/models/slot_khataman_model.dart';
import '../presentation/group_list_screen.dart';
import '../../../screens/active_khataman_list_screen.dart';

class GroupDetailController extends ChangeNotifier {
  final GroupRepository _repository;
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;

  GroupDetailController({GroupRepository? repository})
      : _repository = repository ?? GroupRepository();

  GroupModel? _group;
  PutaranModel? _putaran;
  List<SlotKhatamanModel> _slots = [];
  List<GroupMember> _members = [];
  bool _isLoading = true;
  int _pendingCount = 0;
  int _completedCount = 0;
  bool _isExited = false;
  bool _hasConfirmedDoa = false;

  // Getters
  GroupModel? get group => _group;
  PutaranModel? get putaran => _putaran;
  List<SlotKhatamanModel> get slots => _slots;
  List<GroupMember> get members => _members;
  bool get isLoading => _isLoading;
  int get pendingCount => _pendingCount;
  int get completedCount => _completedCount;
  bool get isExited => _isExited;
  bool get hasConfirmedDoa => _hasConfirmedDoa;

  double get percent {
    if (_slots.isEmpty) return 0.0;
    final comp = _slots.where((s) => s.statusChecklist).length;
    return (comp / 30) * 100;
  }

  void setIsExited(bool val) {
    _isExited = val;
    notifyListeners();
  }

  // Setup Realtime subscriptions
  void setupRealtime(String groupId) {
    if (_subscription != null) {
      try {
        _supabase.removeChannel(_subscription!);
      } catch (e) {
        debugPrint('🔄 [Realtime Group] Error removing old channel: $e');
      }
    }

    final channelName = 'group_detail_$groupId';
    _subscription = _supabase.channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'slot_khataman',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Slot changed. Refreshing...');
            GroupScreen.invalidateCache();
            ActiveKhatamanListScreen.invalidateCache();
            fetchData(groupId, silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'putaran_siklus',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Putaran changed. Refreshing...');
            GroupScreen.invalidateCache();
            ActiveKhatamanListScreen.invalidateCache();
            fetchData(groupId, silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Members changed. Refreshing...');
            GroupScreen.invalidateCache();
            ActiveKhatamanListScreen.invalidateCache();
            fetchData(groupId, silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          callback: (payload) {
            debugPrint('🔄 [Realtime Group] Group changed. Refreshing...');
            GroupScreen.invalidateCache();
            ActiveKhatamanListScreen.invalidateCache();
            fetchData(groupId, silent: true);
          },
        );

    _subscription?.subscribe((status, [error]) {
      if (error != null) {
        debugPrint('🔄 [Realtime Group] Subscription status: $status, error: $error');
      }
    });
  }

  // Fetch data
  Future<void> fetchData(String groupId, {bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final groupData = await _repository.getGroup(groupId);
      final activePutaran = await _repository.getActivePutaran(groupId);
      List<SlotKhatamanModel> slotsList = [];

      if (activePutaran != null) {
        slotsList = await _repository.getSlots(activePutaran.idPutaran);

        // Self-healing: complete cycle if 30 slots finished
        final completedSlotsCount = slotsList.where((s) => s.statusChecklist).length;
        if (completedSlotsCount == 30 && activePutaran.statusSelesai == false) {
          debugPrint('🎉 [Sync] Semua 30 Juz selesai! Menandai putaran siklus sebagai SELESAI...');
          await _supabase
              .from('putaran_siklus')
              .update({'status_aktif_selesai': 'SELESAI'})
              .eq('id_putaran', activePutaran.idPutaran);

          // Send notification
          try {
            await NotificationService.sendToGroup(
              groupId: groupId,
              type: 'KHATAMAN_COMPLETE',
              title: '🎉 Khataman Selesai! Alhamdulillah!',
              body: 'Alhamdulillah, khataman di grup "${groupData.namaGrup}" telah selesai (30/30 Juz). Semoga berkah!',
            );
          } catch (notifErr) {
            debugPrint('Error sending completion notification: $notifErr');
          }

          // Fetch updated cycle details
          return fetchData(groupId, silent: silent);
        }
      }

      int pendingCount = 0;
      final currentUserId = _supabase.auth.currentUser?.id;
      if (groupData.creatorId == currentUserId) {
        final pendingRes = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', groupId)
            .eq('approval_status', 'PENDING');
        pendingCount = (pendingRes as List).length;
      }

      final membersList = await _repository.getGroupMembers(groupId);
      final approvedMembers = membersList.where((m) => m.approvalStatus == 'APPROVED').toList();

      final completedCountRes = await _supabase
          .from('putaran_siklus')
          .select('id_putaran')
          .eq('group_id', groupId)
          .eq('status_aktif_selesai', 'SELESAI');
      final completedCyclesCount = (completedCountRes as List).length;

      // Local archived state persistence
      var localGroup = groupData;
      if (activePutaran != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final localArchived = prefs.getBool('archived_group_${groupId}_${activePutaran.idPutaran}') ?? false;
          if (localArchived) {
            localGroup = GroupModel(
              idGrup: groupData.idGrup,
              namaGrup: groupData.namaGrup,
              deskripsi: groupData.deskripsi,
              creatorId: groupData.creatorId,
              tipeGrup: groupData.tipeGrup,
              visibility: 'ARCHIVED',
              limitJuz: groupData.limitJuz,
              createdAt: groupData.createdAt,
            );
          }
        } catch (_) {}
      }

      // Self-healing: Creator silently synchronizes permanent group archiving if round is complete
      if (groupData.creatorId == currentUserId &&
          localGroup.visibility != 'ARCHIVED' &&
          activePutaran != null &&
          activePutaran.statusSelesai == true &&
          groupData.tipeGrup != 'RUTIN') {
        debugPrint('🔒 [Self-Healing] Creator detected completed round. Archiving group permanently in background...');
        try {
          await _repository.client
              .from('groups')
              .update({'visibility': 'ARCHIVED'})
              .eq('id_group', groupId);
          
          localGroup = GroupModel(
            idGrup: groupData.idGrup,
            namaGrup: groupData.namaGrup,
            deskripsi: groupData.deskripsi,
            creatorId: groupData.creatorId,
            tipeGrup: groupData.tipeGrup,
            visibility: 'ARCHIVED',
            limitJuz: groupData.limitJuz,
            createdAt: groupData.createdAt,
          );
        } catch (shErr) {
          debugPrint('Error in silent self-healing archive: $shErr');
        }
      }

      final isCreator = groupData.creatorId == currentUserId;
      final isCurrentUserMember = approvedMembers.any((m) => m.userId == currentUserId);

      if (!isCreator && !isCurrentUserMember && !_isExited) {
        _isExited = true;
        _isLoading = false;
        notifyListeners();
        return;
      }

      bool hasConfirmedDoa = false;
      if (activePutaran != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          hasConfirmedDoa = prefs.getBool('doa_confirmed_${activePutaran.idPutaran}') ?? false;
        } catch (e) {
          debugPrint('🚨 [Preferences] Error reading local flag: $e');
        }
      }

      _group = localGroup;
      _putaran = activePutaran;
      _slots = slotsList;
      _members = approvedMembers;
      _pendingCount = pendingCount;
      _completedCount = completedCyclesCount;
      _hasConfirmedDoa = hasConfirmedDoa;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Confirm reading of Doa Khatam / Archive Group logic
  Future<void> archiveGroup(String groupId, {String? customGroupName}) async {
    GroupScreen.invalidateCache();
    ActiveKhatamanListScreen.invalidateCache();
    if (_putaran != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('doa_confirmed_${_putaran!.idPutaran}', true);
      } catch (prefErr) {
        debugPrint('Error saving local doa confirmed flag: $prefErr');
      }
    }

    _hasConfirmedDoa = true;
    notifyListeners();

    final isRutin = _group?.tipeGrup == 'RUTIN';

    // 1. Update group visibility to ARCHIVED (only for inciden groups)
    if (!isRutin) {
      try {
        await _repository.client
            .from('groups')
            .update({'visibility': 'ARCHIVED'})
            .eq('id_group', groupId);
        
        _group = GroupModel(
          idGrup: _group!.idGrup,
          namaGrup: _group!.namaGrup,
          deskripsi: _group!.deskripsi,
          creatorId: _group!.creatorId,
          tipeGrup: _group!.tipeGrup,
          visibility: 'ARCHIVED',
          limitJuz: _group!.limitJuz,
          createdAt: _group!.createdAt,
        );
      } catch (grpErr) {
        debugPrint('⚠️ [RLS Restriction] Failed to update groups visibility: $grpErr');
      }

      if (_putaran != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('archived_group_${groupId}_${_putaran!.idPutaran}', true);
        } catch (prefErr) {
          debugPrint('Error saving local archived flag: $prefErr');
        }
      }
    }

    // 2. Mark cycle complete
    if (_putaran != null) {
      await _repository.client
          .from('putaran_siklus')
          .update({'status_aktif_selesai': 'SELESAI'})
          .eq('id_putaran', _putaran!.idPutaran);
    }

    // 3. Send Notification
    final gName = customGroupName ?? _group?.namaGrup ?? 'Grup';
    final senderName = _supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
        _supabase.auth.currentUser?.email?.split('@')[0] ??
        'Seseorang';

    try {
      await NotificationService.sendToGroup(
        groupId: groupId,
        type: 'KHATAMAN_COMPLETE',
        title: isRutin ? '🎉 Putaran Khataman Selesai!' : '📁 Khataman Diarsipkan',
        body: isRutin
            ? '"$gName" telah menyelesaikan putaran siklus oleh $senderName. Alhamdulillah!'
            : '"$gName" telah diarsipkan oleh $senderName setelah menyelesaikan Doa Khatam Al-Quran. Alhamdulillah!',
        excludeUserId: _supabase.auth.currentUser?.id,
      );
    } catch (notifErr) {
      debugPrint('Error sending archive notification: $notifErr');
    }

    await fetchData(groupId, silent: true);
  }

  // Transfer Ownership (Admin promotion)
  Future<void> transferAdmin(String groupId, String newAdminId) async {
    GroupScreen.invalidateCache();
    ActiveKhatamanListScreen.invalidateCache();
    await _repository.transferAdmin(groupId: groupId, newAdminId: newAdminId);
  }

  // Delete Group
  Future<void> deleteGroup(String groupId) async {
    GroupScreen.invalidateCache();
    ActiveKhatamanListScreen.invalidateCache();
    await _repository.deleteGroup(groupId);
  }

  // Leave Group
  Future<void> leaveGroup(String groupId, String userId) async {
    GroupScreen.invalidateCache();
    ActiveKhatamanListScreen.invalidateCache();
    await _repository.leaveGroup(groupId: groupId, userId: userId);
  }

  @override
  void dispose() {
    if (_subscription != null) {
      try {
        _supabase.removeChannel(_subscription!);
      } catch (e) {
        debugPrint('Error removing channel on dispose: $e');
      }
    }
    super.dispose();
  }
}
