import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';

class ParticipantInfo {
  final String userId;
  final String role;
  final String status;
  final UserModel? user;

  ParticipantInfo({
    required this.userId,
    required this.role,
    required this.status,
    this.user,
  });

  factory ParticipantInfo.fromJson(Map<String, dynamic> json) {
    return ParticipantInfo(
      userId: json['user_id'] as String,
      role: json['role'] as String? ?? 'member',
      status: json['status'] as String? ?? 'active',
      user: json['profiles'] != null
          ? UserModel.fromJson(json['profiles'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'role': role,
      'status': status,
    };
  }
}

class ConversationModel {
  final String id;
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserModel? otherUser;
  MessageModel? lastMessage;
  int unreadCount;

  final bool isGroup;
  final String? name;
  final String? description;
  final String? avatarUrl;
  final String? createdBy;
  final bool onlyAdminsCanMessage;
  final bool onlyAdminsCanEditInfo;
  final int participantCount;
  List<ParticipantInfo>? participants;

  String get displayName {
    if (isGroup) return name ?? 'Group';
    return otherUser?.fullName.isNotEmpty == true
        ? otherUser!.fullName
        : (otherUser?.username ?? '');
  }

  String get displayAvatar {
    if (isGroup) return avatarUrl ?? '';
    return otherUser?.avatarUrl ?? '';
  }

  String get displayInitial {
    final n = displayName;
    return n.isNotEmpty ? n[0].toUpperCase() : '?';
  }

  /// Group bio/description to show. Legacy groups stored "N participants" in the
  /// description column; for those we prefer the live participant count instead
  /// of the stale string. A real bio always wins.
  String? get displayDescription {
    final desc = description;
    if (desc != null &&
        desc.isNotEmpty &&
        !desc.endsWith('participants')) {
      return desc;
    }
    if (isGroup && participantCount > 0) {
      return '$participantCount participants';
    }
    return desc;
  }

  ConversationModel({
    required this.id,
    required this.createdAt,
    this.updatedAt,
    this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
    this.isGroup = false,
    this.name,
    this.description,
    this.avatarUrl,
    this.createdBy,
    this.onlyAdminsCanMessage = false,
    this.onlyAdminsCanEditInfo = false,
    this.participantCount = 0,
    this.participants,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as int?) ?? 0,
      isGroup: (json['is_group'] as bool?) ?? false,
      name: json['name'] as String?,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdBy: json['created_by'] as String?,
      onlyAdminsCanMessage: (json['only_admins_can_message'] as bool?) ?? false,
      onlyAdminsCanEditInfo: (json['only_admins_can_edit_info'] as bool?) ?? false,
      participantCount: (json['participant_count'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_group': isGroup,
      'name': name,
      'description': description,
      'avatar_url': avatarUrl,
      'created_by': createdBy,
      'only_admins_can_message': onlyAdminsCanMessage,
      'only_admins_can_edit_info': onlyAdminsCanEditInfo,
      'participant_count': participantCount,
    };
  }

  ConversationModel copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    UserModel? otherUser,
    MessageModel? lastMessage,
    int? unreadCount,
    bool? isGroup,
    String? name,
    String? description,
    String? avatarUrl,
    String? createdBy,
    bool? onlyAdminsCanMessage,
    bool? onlyAdminsCanEditInfo,
    int? participantCount,
    List<ParticipantInfo>? participants,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdBy: createdBy ?? this.createdBy,
      onlyAdminsCanMessage: onlyAdminsCanMessage ?? this.onlyAdminsCanMessage,
      onlyAdminsCanEditInfo: onlyAdminsCanEditInfo ?? this.onlyAdminsCanEditInfo,
      participantCount: participantCount ?? this.participantCount,
      participants: participants ?? this.participants,
    );
  }

  @override
  String toString() {
    return 'ConversationModel(id: $id, isGroup: $isGroup, displayName: $displayName, lastMessage: ${lastMessage?.content})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
