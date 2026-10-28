import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../api/calendar_api.dart';
import '../api/conversation_api.dart' show ApiException;
import '../models/calendar_event.dart';
import '../models/calendar_week.dart';
import '../models/chat_message.dart';
import '../models/interpretation_proposal.dart';
import '../models/llm_usage.dart';

enum CalendarChatMode { symbolic, llmOnly }

class CalendarController extends ChangeNotifier {
  CalendarController({required this.api, DateTime Function()? now})
    : week = CalendarWeek.containing((now ?? DateTime.now)());

  @override
  void notifyListeners() {
    if (!_disposed && hasListeners && (llmBudget?.pendingUsageCount ?? 0) > 0) {
      _usageTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshUsage(),
      );
    } else {
      _usageTimer?.cancel();
      _usageTimer = null;
    }
    super.notifyListeners();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _usageTimer?.cancel();
      _usageTimer = null;
    }
  }

  Timer? _usageTimer;
  bool _usageRefreshing = false;
  Future<void> _refreshUsage() async {
    final before = dialogue;
    final mode = chatMode;
    if (_disposed ||
        chatBusy ||
        editing ||
        _usageRefreshing ||
        (llmBudget?.pendingUsageCount ?? 0) == 0) {
      return;
    }
    _usageRefreshing = true;
    try {
      final updated = await _dialogueRequest();
      if (!_disposed &&
          !chatBusy &&
          !editing &&
          chatMode == mode &&
          identical(dialogue, before)) {
        _adoptDialogue(updated);
        notifyListeners();
      }
    } catch (_) {
      // Accounting refresh must not interrupt the pending dialogue.
    } finally {
      _usageRefreshing = false;
    }
  }

  final CalendarApi api;
  CalendarWeek week;
  List<CalendarEvent> events = const [];
  bool loading = false;
  bool editing = false;
  bool needsRefresh = false;
  CalendarChatMode chatMode = CalendarChatMode.symbolic;
  final _dialogues = <CalendarChatMode, Map<String, dynamic>>{};
  final _uncertainModes = <CalendarChatMode>{};
  Map<String, dynamic>? get dialogue => _dialogues[chatMode];
  set dialogue(Map<String, dynamic>? value) {
    if (value == null) {
      _dialogues.remove(chatMode);
    } else {
      _dialogues[chatMode] = value;
    }
  }

  bool get isLlmOnly => chatMode == CalendarChatMode.llmOnly;
  bool get canSwitchChatMode => !chatBusy && !editing;
  bool get statusUncertain => _uncertainModes.contains(chatMode);
  bool get otherChatPending {
    final otherMode = isLlmOnly
        ? CalendarChatMode.symbolic
        : CalendarChatMode.llmOnly;
    return _uncertainModes.contains(otherMode) ||
        (dialogue?['peerBusy'] as bool? ??
            _pendingStatus(_dialogues[otherMode]?['status']));
  }

  Future<Map<String, dynamic>> _dialogueRequest([
    Map<String, dynamic>? action,
  ]) => isLlmOnly ? api.llmOnlyDialogue(action) : api.dialogue(action);

  Future<void> selectChatMode(CalendarChatMode mode) async {
    if (_disposed || !canSwitchChatMode) return;
    chatMode = mode;
    chatError = null;
    notifyListeners();
    await loadDialogue();
  }

  static bool _pendingStatus(dynamic status) => const {
    'clarify',
    'review',
    'prefix',
    'applying',
    'recovery',
    'interpretation',
    'interpreting',
    'clarification',
    'running',
    'suspended',
  }.contains(status);

  bool get canNavigate =>
      !editing &&
      !chatBusy &&
      !otherChatPending &&
      _uncertainModes.isEmpty &&
      !const ['applying', 'recovery'].contains(chatStatus);

  bool chatBusy = false;
  String? chatError;
  bool useLlm = false;
  int? selectedInterpretationRank;
  String? _proposalId;
  InterpretationProposal? get proposal =>
      isLlmOnly || dialogue?['interpretation'] == null
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
      !isLlmOnly &&
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
  bool get awaitingAnswer => isLlmOnly
      ? chatStatus == 'clarification'
      : chatStatus == 'clarify' && pendingQuestion != null;
  bool get canChat =>
      !chatBusy &&
      !editing &&
      !otherChatPending &&
      !statusUncertain &&
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
      otherChatPending ||
      statusUncertain ||
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
    if (isLlmOnly) {
      await act({'type': 'message', 'text': text});
      return !_disposed && chatError == null;
    }
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

  bool get dialoguePending => _pendingStatus(dialogue?['status']);
  bool get canEdit =>
      !loading &&
      !editing &&
      !chatBusy &&
      !dialoguePending &&
      !otherChatPending &&
      _uncertainModes.isEmpty &&
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
    if (_disposed || !canNavigate) {
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
      final result = await _dialogueRequest();
      if (!_disposed) {
        _adoptDialogue(result);
        _uncertainModes.remove(chatMode);
        if (isLlmOnly) await load();
      }
    } on ApiException catch (failure) {
      if (!_disposed) {
        chatError = failure.message;
        if (isLlmOnly) _uncertainModes.add(chatMode);
      }
    } finally {
      if (!_disposed) {
        chatBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> act(Map<String, dynamic> action) async {
    if (_disposed || chatBusy || statusUncertain || otherChatPending) return;
    chatBusy = true;
    chatError = null;
    notifyListeners();
    try {
      final result = await _dialogueRequest({
        ...action,
        'revision': dialogue?['revision'] ?? 0,
        if (action['type'] == 'start' ||
            (isLlmOnly && action['type'] == 'message' && !awaitingAnswer)) ...{
          'timeMin': week.start.toUtc().toIso8601String(),
          'timeMax': week.end.toUtc().toIso8601String(),
        },
      });
      if (!_disposed) {
        _adoptDialogue(result);
        if (isLlmOnly ||
            const ['answered', 'idle', 'recovery'].contains(result['status'])) {
          await load();
        }
      }
    } on ApiException catch (failure) {
      if (!_disposed) {
        chatError = failure.message;
        if (isLlmOnly) _uncertainModes.add(chatMode);
      }
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
    _usageTimer?.cancel();
    _disposed = true;
    ++_request;
    api.close();
    super.dispose();
  }
}
