import 'world.dart';
import 'chat_message.dart';

class ConversationState {
  const ConversationState({
    required this.id,
    required this.world,
    required this.canUndo,
    this.feedback,
    this.pending,
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
      pending: json['pending'] == null
          ? null
          : PendingEntry.fromJson(json['pending'] as Map<String, dynamic>),
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
  final PendingEntry? pending;
  final List<ChatMessage> messages;
}

class ClarificationCandidate {
  const ClarificationCandidate({required this.objectId, required this.label});
  factory ClarificationCandidate.fromJson(Map<String, dynamic> json) =>
      ClarificationCandidate(
        objectId: json['objectId'] as int,
        label: json['label'] as String,
      );
  final int objectId;
  final String label;
}

class PendingEntry {
  const PendingEntry({required this.sentence, required this.candidates});
  factory PendingEntry.fromJson(Map<String, dynamic> json) => PendingEntry(
    sentence: json['sentence'] as String,
    candidates: List.unmodifiable(
      (json['candidates'] as List<dynamic>).map(
        (value) =>
            ClarificationCandidate.fromJson(value as Map<String, dynamic>),
      ),
    ),
  );
  final String sentence;
  final List<ClarificationCandidate> candidates;
}
