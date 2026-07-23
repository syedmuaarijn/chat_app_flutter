enum MessageStatus { sending, sent, delivered, read }

class MessageModel {
  final String id;
  final String conversationId;
  final String? senderId;
  final String content;
  final bool isRead;
  final bool isDelivered;
  final DateTime createdAt;
  final DateTime updatedAt;

  final List<String> deletedFor;

  final bool isSystemMessage;

  final String type; // 'text', 'image', 'video', 'audio', 'document'
  final String? mediaUrl;
  final String? fileName;
  final int? fileSize;
  final int? audioDuration;
  final bool isForwarded;

  String? senderUsername;
  String? senderAvatarUrl;

  MessageStatus get status {
    if (id.startsWith('temp_')) return MessageStatus.sending;
    if (isRead) return MessageStatus.read;
    if (isDelivered) return MessageStatus.delivered;
    return MessageStatus.sent;
  }

  MessageModel({
    required this.id,
    required this.conversationId,
    this.senderId,
    required this.content,
    required this.isRead,
    this.isDelivered = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedFor = const [],
    this.senderUsername,
    this.senderAvatarUrl,
    this.isSystemMessage = false,
    this.type = 'text',
    this.mediaUrl,
    this.fileName,
    this.fileSize,
    this.audioDuration,
    this.isForwarded = false,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String?,
      content: json['content'] as String,
      isRead: (json['is_read'] as bool?) ?? false,
      isDelivered: (json['is_delivered'] as bool?) ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      deletedFor:
          (json['deleted_for'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      senderUsername: json['sender_username'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      isSystemMessage: (json['is_system_message'] as bool?) ?? false,
      type: (json['type'] as String?) ?? 'text',
      mediaUrl: json['media_url'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] != null
          ? (json['file_size'] as num).toInt()
          : null,
      audioDuration: json['audio_duration'] != null
          ? (json['audio_duration'] as num).toInt()
          : null,
      isForwarded: (json['is_forwarded'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'is_read': isRead,
      'is_delivered': isDelivered,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_for': deletedFor,
      'is_system_message': isSystemMessage,
      'type': type,
      'media_url': mediaUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'audio_duration': audioDuration,
      'is_forwarded': isForwarded,
    };
  }

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    bool? isRead,
    bool? isDelivered,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? deletedFor,
    String? senderUsername,
    String? senderAvatarUrl,
    bool? isSystemMessage,
    String? type,
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    int? audioDuration,
    bool? isForwarded,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedFor: deletedFor ?? this.deletedFor,
      senderUsername: senderUsername ?? this.senderUsername,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      audioDuration: audioDuration ?? this.audioDuration,
      isForwarded: isForwarded ?? this.isForwarded,
    );
  }

  @override
  String toString() {
    final preview = content.length > 20 ? content.substring(0, 20) : content;
    return 'MessageModel(id: $id, senderId: $senderId, content: $preview..., isSystem: $isSystemMessage)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
