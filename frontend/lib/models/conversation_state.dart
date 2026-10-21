import 'domain.dart';
import 'world.dart';
import 'grid_world.dart';
import 'cellular_world.dart';
import 'world_object.dart';
import 'chat_message.dart';
import 'llm_usage.dart';
import 'interpretation_proposal.dart';
import 'world_slot.dart';

class ConversationState {
  const ConversationState({
    required this.id,
    required this.domain,
    required this.world,
    required this.canUndo,
    this.feedback,
    this.pending,
    this.messages = const [],
    this.llmBudget,
    this.proposal,
    this.preview,
    this.languageVersion = 'unknown',
    this.worldSlots = const [],
    this.resetPending = false,
    this.resetFrom,
    this.changedCells,
  });

  factory ConversationState.fromJson(Map<String, dynamic> json) {
    final id = json['conversationId'] as String;
    if (id.isEmpty) throw const FormatException('Missing conversation ID');
    final domain = WorldDomain.values.byName(json['domain'] as String);
    final changedCells = json['changedCells'] as int?;
    if (changedCells != null &&
        (changedCells < 0 || changedCells > CellularWorld.cellCount)) {
      throw const FormatException('Invalid changed-cell count');
    }
    return ConversationState(
      id: id,
      domain: domain,
      languageVersion: json['languageVersion'] as String? ?? 'unknown',
      world: domain == WorldDomain.cellular
          ? CellularWorld.fromJson(json['world'] as Map<String, dynamic>)
          : World.fromJson(json['world'] as Map<String, dynamic>),
      changedCells: changedCells,
      canUndo: json['canUndo'] as bool,
      resetPending: json['resetPending'] as bool? ?? false,
      resetFrom: json['resetFrom'] as String?,
      worldSlots: List.unmodifiable(
        (json['worldSlots'] as List<dynamic>? ?? []).map(
          (slot) => WorldSlot.fromJson(slot as Map<String, dynamic>),
        ),
      ),
      llmBudget: json['llmBudget'] == null
          ? null
          : LlmBudget.fromJson(json['llmBudget'] as Map<String, dynamic>),
      feedback: json['feedback'] as String?,
      pending: json['pending'] == null
          ? null
          : PendingEntry.fromJson(json['pending'] as Map<String, dynamic>),
      proposal: json['proposal'] == null
          ? null
          : InterpretationProposal.fromJson(
              json['proposal'] as Map<String, dynamic>,
            ),
      preview: json['preview'] == null
          ? null
          : InterpretationPreview.fromJson(
              json['preview'] as Map<String, dynamic>,
            ),
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? []).map(
          (message) => ChatMessage.fromJson(message as Map<String, dynamic>),
        ),
      ),
    );
  }

  final String id;
  final WorldDomain domain;
  final GridWorld world;
  World? get objectWorld => world is World ? world as World : null;
  CellularWorld? get cellularWorld =>
      world is CellularWorld ? world as CellularWorld : null;
  final bool canUndo;
  final String? feedback;
  final PendingEntry? pending;
  final List<ChatMessage> messages;
  final LlmBudget? llmBudget;
  final InterpretationProposal? proposal;
  final InterpretationPreview? preview;
  final String languageVersion;
  final List<WorldSlot> worldSlots;
  final bool resetPending;
  final String? resetFrom;
  final int? changedCells;
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

class GroupingCandidate {
  const GroupingCandidate({required this.groupingId, required this.label});
  factory GroupingCandidate.fromJson(Map<String, dynamic> json) =>
      GroupingCandidate(
        groupingId: json['groupingId'] as int,
        label: json['label'] as String,
      );
  final int groupingId;
  final String label;
}

class PendingEntry {
  const PendingEntry({
    required this.sentence,
    required this.candidates,
    this.squareChoices = const [],
    this.groupingChoices = const [],
    this.stagedWorld,
  });
  factory PendingEntry.fromJson(Map<String, dynamic> json) => PendingEntry(
    sentence: json['sentence'] as String,
    groupingChoices: List.unmodifiable(
      (json['groupingChoices'] as List<dynamic>? ?? []).map(
        (value) => GroupingCandidate.fromJson(value as Map<String, dynamic>),
      ),
    ),
    stagedWorld: json['stagedWorld'] == null
        ? null
        : (json['stagedWorld'] as Map<String, dynamic>).containsKey('cells')
        ? CellularWorld.fromJson(json['stagedWorld'] as Map<String, dynamic>)
        : World.fromJson(json['stagedWorld'] as Map<String, dynamic>),
    squareChoices: List.unmodifiable(
      (json['squareChoices'] as List<dynamic>? ?? []).map(
        (value) => BoardPosition.fromJson(value as Map<String, dynamic>),
      ),
    ),
    candidates: List.unmodifiable(
      (json['candidates'] as List<dynamic>).map(
        (value) =>
            ClarificationCandidate.fromJson(value as Map<String, dynamic>),
      ),
    ),
  );
  final String sentence;
  final List<ClarificationCandidate> candidates;
  final List<BoardPosition> squareChoices;
  final List<GroupingCandidate> groupingChoices;
  final GridWorld? stagedWorld;
}
