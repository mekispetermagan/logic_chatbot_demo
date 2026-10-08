import 'world.dart';
import 'chat_message.dart';

class ConversationState {
  const ConversationState({
    required this.id,
    required this.world,
    required this.canUndo,
    this.feedback,
    this.messages = const [],
  });

  factory ConversationState.fromJson(Map<String, dynamic> json) {
    final id = json['conversationId'] as String;
    if (id.isEmpty) throw const FormatException('Missing conversation ID');
    return ConversationState(
      id: id,
      world: World.fromJson(json['world'] as Map<String, dynamic>),
      canUndo: json['canUndo'] as bool,
      feedback: json['feedback'] as String?,
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? []).map(
          (message) => ChatMessage.fromJson(message as Map<String, dynamic>),
        ),
      ),
    );
  }

  final String id;
  final World world;
  final bool canUndo;
  final String? feedback;
  final List<ChatMessage> messages;
}
