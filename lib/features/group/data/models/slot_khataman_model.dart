import 'group_member_model.dart';

class SlotKhatamanModel {
  final String idSlot;
  final String idPutaran;
  final int nomorJuz;
  final String? userId;
  final int ayatTerakhirInput;
  final bool statusChecklist;
  final String? approvalLepasStatus;
  final String? usernameSebelumnya;
  final UserProfile? user;

  SlotKhatamanModel({
    required this.idSlot,
    required this.idPutaran,
    required this.nomorJuz,
    this.userId,
    required this.ayatTerakhirInput,
    required this.statusChecklist,
    this.approvalLepasStatus,
    this.usernameSebelumnya,
    this.user,
  });

  factory SlotKhatamanModel.fromJson(Map<String, dynamic> json) {
    return SlotKhatamanModel(
      idSlot: json['id_slot'] as String? ?? '',
      idPutaran: json['id_putaran'] as String? ?? '',
      nomorJuz: json['nomor_juz'] as int? ?? 1,
      userId: json['user_id'] as String?,
      ayatTerakhirInput: json['ayat_terakhir_input'] as int? ?? 0,
      statusChecklist: json['status_checklist'] == true,
      approvalLepasStatus: json['approval_lepas_status'] as String?,
      usernameSebelumnya: json['username_sebelumnya'] as String?,
      user: json['users'] != null
          ? UserProfile.fromJson(json['users'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id_slot': idSlot,
        'id_putaran': idPutaran,
        'nomor_juz': nomorJuz,
        'user_id': userId,
        'ayat_terakhir_input': ayatTerakhirInput,
        'status_checklist': statusChecklist,
        'approval_lepas_status': approvalLepasStatus,
        'username_sebelumnya': usernameSebelumnya,
      };

  bool get hasProgress => ayatTerakhirInput > 0 || statusChecklist;
  bool get isPendingRelease => approvalLepasStatus == 'PENDING';
}
