import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../api/calendar_api.dart';
import '../api/conversation_api.dart' show ApiException;
import '../models/calendar_event.dart';
import '../models/calendar_week.dart';
import '../models/chat_message.dart';
import '../models/interpretation_proposal.dart';
import '../models/llm_usage.dart';

class CalendarController extends ChangeNotifier {
  CalendarController({required this.api, DateTime Function()? now})
    : week = CalendarWeek.containing((now ?? DateTime.now)());

  final CalendarApi api;
  CalendarWeek week;
  List<CalendarEvent> events = const [];
  bool loading = false;
  bool editing = false;
  bool needsRefresh = false;
  Map<String, dynamic>? dialogue;
  bool chatBusy = false;
  String? chatError;
  bool useLlm = false;
  int? selectedInterpretationRank;
  String? _proposalId;
  InterpretationProposal? get proposal => dialogue?['interpretation'] == null
      ? null
      : InterpretationProposal.fromJson(
          Map<String, dynamic>.from(dialogue!['interpretation'] as Map),
        );
  InterpretationPreview? get preview {
    final raw = dialogue?['interpretationPreview'];
    if (raw == null) return null;
    final result = InterpretationPreview.fromJson(
      Map<String, dynamic>.from(raw as Map),
    );
    return result.proposalId == proposal?.id &&
            result.rank == selectedInterpretationRank
        ? result
        : null;
  }

  LlmBudget? get llmBudget => dialogue?['llmBudget'] == null
      ? null
      : LlmBudget.fromJson(
          Map<String, dynamic>.from(dialogue!['llmBudget'] as Map),
        );
  bool get canReview =>
      proposal != null && chatStatus == 'interpretation' && !chatBusy;
  bool get canToggleLlm =>
      !chatBusy &&
      !editing &&
      !const [
        'interpretation',
        'interpreting',
        'applying',
        'recovery',
      ].contains(chatStatus);
  void setUseLlm(bool value) {
    if (_disposed || !canToggleLlm || useLlm == value) return;
    useLlm = value;
    notifyListeners();
  }

  void _adoptDialogue(Map<String, dynamic> value) {
    dialogue = value;
    final current = proposal;
    if (_proposalId != current?.id) selectedInterpretationRank = null;
    _proposalId = current?.id;
    if (current != null &&
        current.candidates.isNotEmpty &&
        !current.candidates.any(
          (candidate) => candidate.rank == selectedInterpretationRank,
        )) {
      selectedInterpretationRank = current.candidates.first.rank;
    }
  }

  void selectInterpretation(int rank) {
    if (!canReview ||
        !proposal!.candidates.any((candidate) => candidate.rank == rank)) {
      return;
    }
    selectedInterpretationRank = rank;
    notifyListeners();
  }

  Future<bool> _review(String type, {String? text}) async {
    final current = proposal;
    if (!canReview || current == null) return false;
    await act({
      'type': type,
      'proposalId': current.id,
      if (selectedInterpretationRank != null)
        'rank': selectedInterpretationRank,
      'text': ?text,
    });
    return !_disposed && chatError == null;
  }

  Future<bool> previewInterpretation() => _review('previewInterpretation');
  Future<bool> acceptInterpretation() => _review('acceptInterpretation');
  Future<bool> rejectInterpretation() => _review('rejectInterpretation');
  Future<bool> answerInterpretation(String text) =>
      _review('answerInterpretation', text: text);

  String get chatStatus => dialogue?['status'] as String? ?? 'idle';
  Map? get pendingQuestion => dialogue?['question'] as Map?;
  bool get awaitingAnswer => chatStatus == 'clarify' && pendingQuestion != null;
  bool get canChat =>
      dialogue != null &&
      (!dialoguePending ||
          awaitingAnswer ||
          (canReview && proposal?.canAnswer == true));
  List<ChatMessage> get chatMessages => [
    for (final message in dialogue?['messages'] as List? ?? [])
      ChatMessage.fromJson(Map<String, dynamic>.from(message as Map)),
  ];
  bool get hasDialogueControls =>
      dialoguePending ||
      (dialogue?['canRevise'] == true &&
          (dialogue?['parameters'] as Map? ?? {}).isNotEmpty);

  static dynamic _replyValue(String text, [String? kind]) {
    if (const [
      'text',
      'date',
      'moment',
      'window',
      'condition',
      'clock',
    ].contains(kind)) {
      return text;
    }
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  Future<bool> sendChat(String text) async {
    if (_disposed || chatBusy || !canChat) return false;
    final question = pendingQuestion;
    await act(
      awaitingAnswer && question != null
          ? {
              'type': 'answer',
              'key': question['key'],
              'value': _replyValue(text, question['kind'] as String?),
              if (useLlm) ...{'text': text, 'useLlm': true},
            }
          : {'type': 'start', 'text': text, if (useLlm) 'useLlm': true},
    );
    return !_disposed && chatError == null;
  }

  Future<void> reviseRequirement(String parameter, String text) => act({
    'type': 'revise',
    'key': parameter,
    'value': _replyValue(
      text,
      (dialogue?['parameters'] as Map? ?? {})[parameter] is String
          ? 'text'
          : null,
    ),
  });

  bool get dialoguePending => const [
    'clarify',
    'review',
    'prefix',
    'applying',
    'recovery',
    'interpretation',
    'interpreting',
  ].contains(dialogue?['status']);
  bool get canEdit =>
      !loading &&
      !editing &&
      !chatBusy &&
      !dialoguePending &&
      !needsRefresh &&
      error == null;
  String? error;
  int _request = 0;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    final requestedWeek = week;
    loading = true;
    error = null;
    events = const [];
    notifyListeners();
    try {
      final result = await api.events(requestedWeek);
      if (_disposed || request != _request) return;
      events = result
          .where(
            (event) =>
                event.end.isAfter(requestedWeek.start) &&
                event.start.isBefore(requestedWeek.end),
          )
          .toList();
      needsRefresh = false;
    } on ApiException catch (failure) {
      if (_disposed || request != _request) return;
      error = failure.message;
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> shiftWeek(int offset) {
    if (_disposed || editing) return Future.value();
    if (chatBusy ||
        const ['applying', 'recovery'].contains(dialogue?['status'])) {
      return Future.value();
    }
    if (dialoguePending) return _cancelAndShift(offset);
    week = week.shift(offset);
    return load();
  }

  Future<void> _cancelAndShift(int offset) async {
    await act({'type': 'cancel'});
    if (!dialoguePending && !chatBusy) {
      week = week.shift(offset);
      await load();
    }
  }

  Future<void> loadDialogue() async {
    if (_disposed || chatBusy) return;
    chatBusy = true;
    chatError = null;
    notifyListeners();
    try {
      final result = await api.dialogue();
      if (!_disposed) _adoptDialogue(result);
    } on ApiException catch (failure) {
      if (!_disposed) chatError = failure.message;
    } finally {
      if (!_disposed) {
        chatBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> act(Map<String, dynamic> action) async {
    if (_disposed || chatBusy) return;
    chatBusy = true;
    chatError = null;
    notifyListeners();
    try {
      final result = await api.dialogue({
        ...action,
        'revision': dialogue?['revision'] ?? 0,
        if (action['type'] == 'start') ...{
          'timeMin': week.start.toUtc().toIso8601String(),
          'timeMax': week.end.toUtc().toIso8601String(),
        },
      });
      if (!_disposed) {
        _adoptDialogue(result);
        if (const ['answered', 'idle', 'recovery'].contains(result['status'])) {
          await load();
        }
      }
    } on ApiException catch (failure) {
      if (!_disposed) chatError = failure.message;
    } finally {
      if (!_disposed) {
        chatBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> save({String? id, required Map<String, dynamic> fields}) =>
      _mutate(() => id == null ? api.create(fields) : api.update(id, fields));

  Future<void> delete(String id) => _mutate(() => api.delete(id));

  Future<void> _mutate(Future<void> Function() operation) async {
    if (_disposed || !canEdit) {
      throw const ApiException('Refresh the calendar before editing.');
    }
    editing = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } on CalendarWriteException catch (failure) {
      if (!_disposed && failure.outcomeUnknown) {
        needsRefresh = true;
        error =
            'The change may have completed. Refresh the calendar before editing again.';
      }
      rethrow;
    } finally {
      if (!_disposed) {
        editing = false;
        notifyListeners();
      }
    }
    if (!_disposed) await load();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    api.close();
    super.dispose();
  }
}
