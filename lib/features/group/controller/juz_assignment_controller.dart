import 'package:flutter/material.dart';
import '../../../services/notification_service.dart';
import '../data/group_repository.dart';
import '../data/models/group_member_model.dart';
import '../data/models/putaran_model.dart';
import '../data/models/slot_khataman_model.dart';
import '../presentation/group_list_screen.dart';
import '../../../screens/active_khataman_list_screen.dart';

class JuzAssignmentController extends ChangeNotifier {
  final GroupRepository _repository;

  JuzAssignmentController({GroupRepository? repository})
      : _repository = repository ?? GroupRepository();

  List<GroupMember> _members = [];
  List<SlotKhatamanModel> _slots = [];
  List<SlotKhatamanModel> _originalSlots = [];
  PutaranModel? _activeCycle;
  bool _isLoading = true;
  bool _limitJuz = false;
  String _selectedBrushUserId = 'eraser';
  bool _hasShownTransferWarning = false;

  final Map<String, String> _uniqueInitials = {};
  final Map<String, Color> _memberColors = {};
  final Set<int> _draggedJuzIndices = {};
  bool? _dragSelectIsAssignMode;

  // Getters
  List<GroupMember> get members => _members;
  List<SlotKhatamanModel> get slots => _slots;
  PutaranModel? get activeCycle => _activeCycle;
  bool get isLoading => _isLoading;
  bool get limitJuz => _limitJuz;
  String get selectedBrushUserId => _selectedBrushUserId;
  bool get hasShownTransferWarning => _hasShownTransferWarning;
  Map<String, String> get uniqueInitials => _uniqueInitials;
  Map<String, Color> get memberColors => _memberColors;
  Set<int> get draggedJuzIndices => _draggedJuzIndices;
  bool? get dragSelectIsAssignMode => _dragSelectIsAssignMode;

  void setSelectedBrushUserId(String userId) {
    _selectedBrushUserId = userId;
    notifyListeners();
  }

  void setDragSelectIsAssignMode(bool? val) {
    _dragSelectIsAssignMode = val;
  }

  void clearDraggedJuzIndices() {
    _draggedJuzIndices.clear();
    _dragSelectIsAssignMode = null;
  }

  void setHasShownTransferWarning(bool val) {
    _hasShownTransferWarning = val;
    notifyListeners();
  }

  // Precomputed unique initials and colors
  static const List<Color> _contrastPalette = [
    Color(0xFF339AF0),
    Color(0xFF51CF66),
    Color(0xFFFCC419),
    Color(0xFFFF922B),
    Color(0xFFFF6B6B),
    Color(0xFFF06595),
    Color(0xFFCC5DE8),
    Color(0xFFAD7A56),
    Color(0xFF868E96),
    Color(0xFF20C997),
  ];

  Color getPastelColor(String input) {
    final int hash = input.hashCode;
    final int index = hash.abs() % _contrastPalette.length;
    return _contrastPalette[index];
  }

  void _generateUniqueInitialsAndColors() {
    _uniqueInitials.clear();
    _memberColors.clear();

    for (int i = 0; i < _members.length; i++) {
      final member = _members[i];
      final color = _contrastPalette[i % _contrastPalette.length];
      _memberColors[member.userId] = color;
    }

    final Set<String> assigned = {};
    for (var member in _members) {
      final username = member.user?.username ?? 'Umum';
      final clean = username.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').trim();
      String initial = '';
      if (clean.length >= 2) {
        initial = clean.substring(0, 2).toUpperCase();
      } else if (clean.isNotEmpty) {
        initial = '${clean.toUpperCase()}X'.substring(0, 2);
      } else {
        initial = 'UM';
      }

      if (assigned.contains(initial)) {
        if (clean.length >= 3) {
          initial = clean.substring(0, 3).toUpperCase();
        } else if (clean.length >= 2) {
          initial = '${clean.substring(0, 2)}1'.toUpperCase();
        }
      }

      int suffix = 1;
      while (assigned.contains(initial)) {
        if (clean.length >= 2) {
          final prefix = clean.substring(0, 2).toUpperCase();
          initial = '$prefix$suffix';
        } else {
          initial = 'UM$suffix';
        }
        suffix++;
      }

      assigned.add(initial);
      _uniqueInitials[member.userId] = initial;
    }
  }

  Future<void> fetchData(String groupId, {bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final membersList = await _repository.getGroupMembers(groupId);
      final approvedMembers = membersList.where((m) => m.approvalStatus == 'APPROVED').toList();

      final activeCycle = await _repository.getActivePutaran(groupId);
      List<SlotKhatamanModel> slotsList = [];

      if (activeCycle != null) {
        slotsList = await _repository.getSlots(activeCycle.idPutaran);
      }

      final group = await _repository.getGroup(groupId);

      _members = approvedMembers;
      _activeCycle = activeCycle;
      _slots = slotsList;
      _originalSlots = slotsList.map((s) => SlotKhatamanModel.fromJson(s.toJson())).toList();
      _limitJuz = group.limitJuz;
      _isLoading = false;

      _generateUniqueInitialsAndColors();
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  void clearAllSlots() {
    for (var slot in _slots) {
      if (slot.hasProgress) continue;

      final idx = _slots.indexOf(slot);
      _slots[idx] = SlotKhatamanModel(
        idSlot: slot.idSlot,
        idPutaran: slot.idPutaran,
        nomorJuz: slot.nomorJuz,
        userId: null,
        ayatTerakhirInput: 0,
        statusChecklist: false,
        approvalLepasStatus: null,
        usernameSebelumnya: null,
        user: null,
      );
    }
    _selectedBrushUserId = 'eraser';
    notifyListeners();
  }

  void resetDraftChanges() {
    _slots = _originalSlots.map((s) => SlotKhatamanModel.fromJson(s.toJson())).toList();
    _selectedBrushUserId = 'eraser';
    notifyListeners();
  }

  Future<bool> saveDraftChanges(String groupId) async {
    try {
      final List<SlotKhatamanModel> changedSlots = [];
      for (var slot in _slots) {
        final orig = _originalSlots.firstWhere(
          (o) => o.idSlot == slot.idSlot,
          orElse: () => SlotKhatamanModel(
            idSlot: '',
            idPutaran: '',
            nomorJuz: 0,
            ayatTerakhirInput: 0,
            statusChecklist: false,
          ),
        );

        if (orig.idSlot.isNotEmpty && slot.userId != orig.userId) {
          String? prevUsername;
          if (slot.userId == null) {
            prevUsername = orig.user?.username;
          }
          
          changedSlots.add(SlotKhatamanModel(
            idSlot: slot.idSlot,
            idPutaran: slot.idPutaran,
            nomorJuz: slot.nomorJuz,
            userId: slot.userId,
            ayatTerakhirInput: slot.ayatTerakhirInput,
            statusChecklist: slot.statusChecklist,
            approvalLepasStatus: slot.approvalLepasStatus,
            usernameSebelumnya: slot.userId == null ? prevUsername : slot.usernameSebelumnya,
            user: slot.user,
          ));
        }
      }

      if (changedSlots.isNotEmpty) {
        await _repository.updateSlots(changedSlots);
        GroupScreen.invalidateCache();
        ActiveKhatamanListScreen.invalidateCache();
      }

      _originalSlots = _slots.map((s) => SlotKhatamanModel.fromJson(s.toJson())).toList();
      notifyListeners();
      return true;
    } catch (e) {
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleLimitJuz(String groupId, bool val) async {
    final originalVal = _limitJuz;
    _limitJuz = val;
    notifyListeners();

    try {
      await _repository.updateLimitJuz(groupId, val);
      GroupScreen.invalidateCache();
      ActiveKhatamanListScreen.invalidateCache();
    } catch (e) {
      _limitJuz = originalVal;
      notifyListeners();
      rethrow;
    }
  }

  bool hasUnsavedChanges() {
    for (var slot in _slots) {
      final orig = _originalSlots.firstWhere(
        (o) => o.idSlot == slot.idSlot,
        orElse: () => SlotKhatamanModel(
          idSlot: '',
          idPutaran: '',
          nomorJuz: 0,
          ayatTerakhirInput: 0,
          statusChecklist: false,
        ),
      );
      if (orig.idSlot.isNotEmpty) {
        if (slot.userId != orig.userId ||
            slot.ayatTerakhirInput != orig.ayatTerakhirInput ||
            slot.statusChecklist != orig.statusChecklist) {
          return true;
        }
      }
    }
    return false;
  }

  void applySlotChange(int index, String? newUserId, UserProfile? newUserProfile) {
    final slot = _slots[index];
    _slots[index] = SlotKhatamanModel(
      idSlot: slot.idSlot,
      idPutaran: slot.idPutaran,
      nomorJuz: slot.nomorJuz,
      userId: newUserId,
      ayatTerakhirInput: 0,
      statusChecklist: false,
      approvalLepasStatus: null,
      usernameSebelumnya: slot.usernameSebelumnya,
      user: newUserProfile,
    );
    notifyListeners();
  }

  String checkTapAction(int index) {
    final slot = _slots[index];
    if (slot.approvalLepasStatus == 'PENDING') {
      return 'PENDING';
    }

    if (slot.hasProgress) {
      return 'LOCKED';
    }

    final String? previousUserId = slot.userId;
    String? newUserId = _selectedBrushUserId == 'eraser' ? null : _selectedBrushUserId;

    if (previousUserId == newUserId && newUserId != null) {
      newUserId = null;
    }

    if (previousUserId != null && newUserId != null && !_hasShownTransferWarning) {
      return 'WARN_TRANSFER';
    }

    return 'NONE';
  }

  bool isQuotaReached(String userId) {
    if (!_limitJuz) return false;
    final memberCount = _members.isEmpty ? 1 : _members.length;
    final batasMaksimal = (30 / memberCount).ceil();
    final currentCount = _slots.where((s) => s.userId == userId).length;
    return currentCount >= batasMaksimal;
  }

  void handleJuzDragSelected(int index) {
    if (index < 0 || index >= _slots.length) return;
    final slot = _slots[index];

    if (slot.hasProgress || slot.approvalLepasStatus == 'PENDING') return;

    final String? previousUserId = slot.userId;
    String? newUserId;
    UserProfile? newUsers;

    String? brushUserId = _selectedBrushUserId == 'eraser' ? null : _selectedBrushUserId;
    UserProfile? brushUserProfile;
    if (brushUserId != null) {
      final member = _members.firstWhere(
        (m) => m.userId == brushUserId,
        orElse: () => GroupMember(groupId: '', userId: '', role: '', approvalStatus: '', prioritasJatah: false),
      );
      if (member.userId.isNotEmpty) {
        brushUserProfile = member.user;
      }
    }

    if (_dragSelectIsAssignMode == true) {
      newUserId = brushUserId;
      newUsers = brushUserProfile;

      if (previousUserId == newUserId) return;
    } else {
      if (_selectedBrushUserId != 'eraser' && previousUserId != _selectedBrushUserId) return;
      newUserId = null;
      newUsers = null;
    }

    if (newUserId != null && isQuotaReached(newUserId)) return;

    if (previousUserId != null && newUserId != null && !_hasShownTransferWarning) return;

    applySlotChange(index, newUserId, newUsers);
  }

  void detectDragSelection(Offset globalPosition, List<GlobalKey> juzKeys) {
    for (int i = 0; i < 30; i++) {
      final key = juzKeys[i];
      final context = key.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final size = box.size;
          final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
          if (rect.contains(globalPosition)) {
            if (!_draggedJuzIndices.contains(i)) {
              if (_dragSelectIsAssignMode == null) {
                final slot = _slots[i];
                if (_selectedBrushUserId == 'eraser' || slot.userId == _selectedBrushUserId) {
                  _dragSelectIsAssignMode = false;
                } else {
                  _dragSelectIsAssignMode = true;
                }
              }

              _draggedJuzIndices.add(i);
              handleJuzDragSelected(i);
            }
            break;
          }
        }
      }
    }
  }

  Future<void> approveRelease({
    required String groupId,
    required String slotId,
    required String? claimedUserId,
    required String groupName,
    required String claimedUsername,
    required int juzNo,
  }) async {
    GroupScreen.invalidateCache();
    ActiveKhatamanListScreen.invalidateCache();
    await _repository.approveRelease(slotId: slotId, usernameSebelumnya: claimedUsername);

    if (claimedUserId != null) {
      try {
        await NotificationService.send(
          userId: claimedUserId,
          type: 'RELEASE_APPROVED',
          title: 'Pengajuan Lepas Juz Disetujui 💚',
          body: 'Pengajuan pelepasan Juz $juzNo Anda di grup "$groupName" telah disetujui oleh admin.',
          groupId: groupId,
        );

        await _repository.client
            .from('notifications')
            .update({
              'type': 'RELEASE_APPROVED',
              'title': 'Pengajuan Lepas Juz Disetujui',
              'is_read': true,
            })
            .eq('group_id', groupId)
            .eq('sender_id', claimedUserId)
            .eq('type', 'RELEASE_REQUEST');
      } catch (err) {
        debugPrint('Error updating release notification: $err');
      }
    }

    await fetchData(groupId, silent: true);
  }

  Future<void> rejectRelease({
    required String groupId,
    required String slotId,
    required String? claimedUserId,
    required String groupName,
    required int juzNo,
  }) async {
    GroupScreen.invalidateCache();
    ActiveKhatamanListScreen.invalidateCache();
    await _repository.rejectRelease(slotId);

    if (claimedUserId != null) {
      try {
        await NotificationService.send(
          userId: claimedUserId,
          type: 'RELEASE_REJECTED',
          title: 'Pengajuan Lepas Juz Ditolak ⚠️',
          body: 'Pengajuan pelepasan Juz $juzNo Anda di grup "$groupName" ditolak oleh admin.',
          groupId: groupId,
        );

        await _repository.client
            .from('notifications')
            .update({
              'type': 'RELEASE_REJECTED',
              'title': 'Pengajuan Lepas Juz Ditolak',
              'is_read': true,
            })
            .eq('group_id', groupId)
            .eq('sender_id', claimedUserId)
            .eq('type', 'RELEASE_REQUEST');
      } catch (err) {
        debugPrint('Error updating release notification: $err');
      }
    }

    await fetchData(groupId, silent: true);
  }
}
