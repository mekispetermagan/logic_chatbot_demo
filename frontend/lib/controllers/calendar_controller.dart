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
                !event.start.isBefore(requestedWeek.start) &&
                event.start.isBefore(requestedWeek.end),
          )
          .toList();
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
    if (_disposed) return Future.value();
    week = week.shift(offset);
    return load();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    api.close();
    super.dispose();
  }
}
