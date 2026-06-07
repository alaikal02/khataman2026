class GroupModel {
  final String idGrup;
  final String namaGrup;
  final String? deskripsi;
  final String creatorId;
  final String tipeGrup; // 'RUTIN' or 'SEKALI'
  final String visibility; // 'ACTIVE' or 'ARCHIVED'
  final bool limitJuz;
  final DateTime createdAt;

  GroupModel({
    required this.idGrup,
    required this.namaGrup,
    this.deskripsi,
    required this.creatorId,
    required this.tipeGrup,
    required this.visibility,
    required this.limitJuz,
    required this.createdAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      idGrup: json['id_grup'] as String? ?? '',
      namaGrup: json['nama_grup'] as String? ?? '',
      deskripsi: json['deskripsi'] as String?,
      creatorId: json['creator_id'] as String? ?? '',
      tipeGrup: json['tipe_grup'] as String? ?? 'SEKALI',
      visibility: json['visibility'] as String? ?? 'ACTIVE',
      limitJuz: json['limit_juz'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_grup': idGrup,
        'nama_grup': namaGrup,
        'deskripsi': deskripsi,
        'creator_id': creatorId,
        'tipe_grup': tipeGrup,
        'visibility': visibility,
        'limit_juz': limitJuz,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isRutin => tipeGrup == 'RUTIN';
  bool get isArchived => visibility == 'ARCHIVED';
}
