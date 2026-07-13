import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';

class ConversationModel {
  final String id;
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserModel? otherUser;
  MessageModel? lastMessage;
  int unreadCount;

  ConversationModel({
    required this.id,
    required this.createdAt,
    this.updatedAt,
    this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      // updated_at may be null until the first message is sent
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ConversationModel copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    UserModel? otherUser,
    MessageModel? lastMessage,
    int? unreadCount,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  @override
  String toString() {
    return 'ConversationModel(id: $id, otherUser: ${otherUser?.username}, lastMessage: ${lastMessage?.content})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
