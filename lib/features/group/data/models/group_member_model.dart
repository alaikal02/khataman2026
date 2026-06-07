class UserProfile {
  final String id;
  final String username;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] ?? json['id_user'] ?? '') as String,
      username: json['username'] as String? ?? 'Umum',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatar_url': avatarUrl,
      };
}

class GroupMember {
  final String? idMember;
  final String groupId;
  final String userId;
  final String role;
  final String approvalStatus;
  final bool prioritasJatah;
  final UserProfile? user;

  GroupMember({
    this.idMember,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.approvalStatus,
    required this.prioritasJatah,
    this.user,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      idMember: json['id_member'] as String?,
      groupId: json['group_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      role: json['role'] as String? ?? 'MEMBER',
      approvalStatus: json['approval_status'] as String? ?? 'PENDING',
      prioritasJatah: json['prioritas_jatah'] == true,
      user: json['users'] != null
          ? UserProfile.fromJson(json['users'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (idMember != null) 'id_member': idMember,
        'group_id': groupId,
        'user_id': userId,
        'role': role,
        'approval_status': approvalStatus,
        'prioritas_jatah': prioritasJatah,
      };
}
