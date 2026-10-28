import 'conversation_state.dart' show PendingEntry;
import 'world.dart';
import 'grid_world.dart';
import 'cellular_world.dart';

class InterpretationCandidate {
  const InterpretationCandidate({
    required this.rank,
    required this.interpretation,
    required this.translation,
    required this.explanation,
  });

  factory InterpretationCandidate.fromJson(Map<String, dynamic> json) =>
      InterpretationCandidate(
        rank: json['rank'] as int,
        interpretation: json['interpretation'] as String,
        translation: json['translation'] as String,
        explanation: json['explanation'] as String,
      );

  final int rank;
  final String interpretation;
  final String translation;
  final String explanation;
}

class InterpretationFailure {
  const InterpretationFailure({
    required this.interpretation,
    required this.translation,
    required this.reason,
  });

  factory InterpretationFailure.fromJson(Map<String, dynamic> json) =>
      InterpretationFailure(
        interpretation: json['interpretation'] as String,
        translation: json['translation'] as String,
        reason: json['reason'] as String,
      );

  final String interpretation;
  final String translation;
  final String reason;
}

class InterpretationProposal {
  const InterpretationProposal({
    required this.id,
    required this.originalText,
    required this.candidates,
    this.question = '',
    this.explanation = '',
    this.validationFailures = const [],
    this.languageVersion = 'unknown',
    this.translationFormat = 'controlledEnglish',
  });

  factory InterpretationProposal.fromJson(Map<String, dynamic> json) =>
      InterpretationProposal(
        id: json['id'] as String,
        originalText: json['originalText'] as String,
        languageVersion: json['languageVersion'] as String? ?? 'unknown',
        translationFormat:
            json['translationFormat'] as String? ?? 'controlledEnglish',
        question: json['question'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        validationFailures: List.unmodifiable(
          (json['validationFailures'] as List<dynamic>? ?? []).map(
            (value) =>
                InterpretationFailure.fromJson(value as Map<String, dynamic>),
          ),
        ),
        candidates: List.unmodifiable(
          (json['candidates'] as List<dynamic>).map(
            (value) =>
                InterpretationCandidate.fromJson(value as Map<String, dynamic>),
          ),
        ),
      );

  final String id;
  final String originalText;
  final String question;
  final String explanation;
  final List<InterpretationCandidate> candidates;
  final List<InterpretationFailure> validationFailures;
  final String languageVersion;
  final String translationFormat;

  bool get canAnswer =>
      question.isNotEmpty ||
      validationFailures.isNotEmpty ||
      candidates.isEmpty;
}

class InterpretationPreview {
  const InterpretationPreview({
    required this.proposalId,
    required this.rank,
    required this.world,
    required this.feedback,
    this.pending,
    this.changes = const [],
    this.hasClarification = false,
  });

  factory InterpretationPreview.fromJson(Map<String, dynamic> json) =>
      InterpretationPreview(
        proposalId: json['proposalId'] as String,
        rank: json['rank'] as int,
        world: json['world'] == null
            ? null
            : (json['world'] as Map<String, dynamic>).containsKey('cells')
            ? CellularWorld.fromJson(json['world'] as Map<String, dynamic>)
            : World.fromJson(json['world'] as Map<String, dynamic>),
        feedback: json['feedback'] as String,
        changes: List.unmodifiable(
          (json['changes'] as List<dynamic>? ?? []).map(
            (value) => WorldChange.fromJson(value as Map<String, dynamic>),
          ),
        ),
        hasClarification: json['hasClarification'] as bool? ?? false,
        pending: json['pending'] == null
            ? null
            : PendingEntry.fromJson(json['pending'] as Map<String, dynamic>),
      );

  final String proposalId;
  final int rank;
  final GridWorld? world;
  final bool hasClarification;
  World? get objectWorld => world is World ? world as World : null;
  CellularWorld? get cellularWorld =>
      world is CellularWorld ? world as CellularWorld : null;
  final String feedback;
  final PendingEntry? pending;
  final List<WorldChange> changes;
}

class WorldChange {
  const WorldChange({
    required this.objectId,
    required this.kind,
    required this.detail,
  });
  factory WorldChange.fromJson(Map<String, dynamic> json) => WorldChange(
    objectId: json['objectId'] as int,
    kind: json['kind'] as String,
    detail: json['detail'] as String,
  );
  final int objectId;
  final String kind;
  final String detail;
}
