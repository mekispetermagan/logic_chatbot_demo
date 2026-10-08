import 'world.dart';

class ConversationState {
  const ConversationState({
    required this.id,
    required this.world,
    required this.canUndo,
    this.feedback,
  });

  factory ConversationState.fromJson(Map<String, dynamic> json) {
    final id = json['conversationId'] as String;
    if (id.isEmpty) throw const FormatException('Missing conversation ID');
    return ConversationState(
      id: id,
      world: World.fromJson(json['world'] as Map<String, dynamic>),
      canUndo: json['canUndo'] as bool,
      feedback: json['feedback'] as String?,
    );
  }

  final String id;
  final World world;
  final bool canUndo;
  final String? feedback;
}
