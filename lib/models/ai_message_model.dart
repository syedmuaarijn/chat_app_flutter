enum AiMessageRole { user, assistant }

class AiMessageModel {
  const AiMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final AiMessageRole role;
  final String content;
  final DateTime createdAt;

  bool get isMe => role == AiMessageRole.user;

  factory AiMessageModel.fromJson(Map<String, dynamic> json) {
    return AiMessageModel(
      id: json['id'] as String,
      role: json['role'] == 'user'
          ? AiMessageRole.user
          : AiMessageRole.assistant,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
