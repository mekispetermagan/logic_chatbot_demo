enum ChatRole { user, machine }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: ChatRole.values.byName(json['role'] as String),
    text: json['text'] as String,
    isError: json['isError'] as bool? ?? false,
  );

  final ChatRole role;
  final String text;
  final bool isError;
}
