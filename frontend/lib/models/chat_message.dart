import 'llm_usage.dart';

enum ChatRole { user, machine }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
    this.llm,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: ChatRole.values.byName(json['role'] as String),
    text: json['text'] as String,
    isError: json['isError'] as bool? ?? false,
    llm: json['llm'] == null
        ? null
        : LlmUsage.fromJson(json['llm'] as Map<String, dynamic>),
  );

  final ChatRole role;
  final String text;
  final bool isError;
  final LlmUsage? llm;
}
