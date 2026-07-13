class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;

  String? senderUsername;
  String? senderAvatarUrl;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.isRead,
    required this.createdAt,
    required this.updatedAt,
    this.senderUsername,
    this.senderAvatarUrl,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      isRead: (json['is_read'] as bool?) ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      senderUsername: json['sender_username'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    bool? isRead,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? senderUsername,
    String? senderAvatarUrl,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      senderUsername: senderUsername ?? this.senderUsername,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
    );
  }

  @override
  String toString() {
    final preview = content.length > 20 ? content.substring(0, 20) : content;
    return 'MessageModel(id: $id, senderId: $senderId, content: $preview...)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
