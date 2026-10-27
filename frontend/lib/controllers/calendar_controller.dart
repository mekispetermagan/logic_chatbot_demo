import 'package:flutter/foundation.dart';

import '../api/calendar_api.dart';
import '../api/conversation_api.dart' show ApiException;
import '../models/calendar_event.dart';
import '../models/calendar_week.dart';

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
  bool get dialoguePending => const [
    'clarify',
    'review',
    'prefix',
    'applying',
    'recovery',
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
      if (!_disposed) dialogue = result;
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
        dialogue = result;
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
