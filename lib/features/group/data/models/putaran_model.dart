class PutaranModel {
  final String idPutaran;
  final String idGrup;
  final int nomorPutaran;
  final bool statusSelesai;
  final DateTime createdAt;

  PutaranModel({
    required this.idPutaran,
    required this.idGrup,
    required this.nomorPutaran,
    required this.statusSelesai,
    required this.createdAt,
  });

  factory PutaranModel.fromJson(Map<String, dynamic> json) {
    return PutaranModel(
      idPutaran: json['id_putaran'] as String? ?? '',
      idGrup: json['id_grup'] as String? ?? '',
      nomorPutaran: json['nomor_putaran'] as int? ?? 1,
      statusSelesai: json['status_selesai'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_putaran': idPutaran,
        'id_grup': idGrup,
        'nomor_putaran': nomorPutaran,
        'status_selesai': statusSelesai,
        'created_at': createdAt.toIso8601String(),
      };
}
