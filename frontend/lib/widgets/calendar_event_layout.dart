import 'dart:math' as math;
import 'package:timezone/timezone.dart' as tz;
import '../models/calendar_event.dart';
import '../models/calendar_week.dart';

/// A visible day slice retaining its original event identity and full interval.
class CalendarSegment {
  CalendarSegment(this.event, tz.TZDateTime day) {
    final next = tz.TZDateTime(budapest, day.year, day.month, day.day + 1);
    continuesBefore = event.start.isBefore(day);
    continuesAfter = event.end.isAfter(next);
    startMinute = continuesBefore ? 0 : event.startMinute;
    endMinute = !event.end.isBefore(next) ? 1440 : event.endMinute;
    // Keep short events in the repeated autumn hour visible without painting
    // beyond the day's 24-hour wall-clock grid.
    if (endMinute <= startMinute) {
      final clippedStart = continuesBefore ? day : event.start;
      final clippedEnd = event.end.isBefore(next) ? event.end : next;
      endMinute = math.min(
        1440,
        startMinute + clippedEnd.difference(clippedStart).inSeconds / 60,
      );
    }
  }
  final CalendarEvent event;
  late final bool continuesBefore;
  late final bool continuesAfter;
  late final double startMinute;
  late double endMinute;

  String get timeLabel =>
      '${continuesBefore ? '↑' : calendarTime(event.start)}–'
      '${continuesAfter
          ? '↓'
          : endMinute == 1440
          ? '24:00'
          : calendarTime(event.end)}';
}

class CalendarPlacement {
  const CalendarPlacement(this.segment, this.lane, this.lanes);
  final CalendarSegment segment;
  CalendarEvent get event => segment.event;
  final int lane;
  final int lanes;
}

/// Clip to the local calendar day, then partition overlaps into stable lanes.
List<CalendarPlacement> layoutCalendarDay(
  List<CalendarEvent> events, {
  tz.TZDateTime? day,
}) {
  final segments = <CalendarSegment>[];
  for (final event in events) {
    final date =
        day ??
        tz.TZDateTime(
          budapest,
          event.start.year,
          event.start.month,
          event.start.day,
        );
    final next = tz.TZDateTime(budapest, date.year, date.month, date.day + 1);
    if (event.start.isBefore(next) && event.end.isAfter(date)) {
      segments.add(CalendarSegment(event, date));
    }
  }
  segments.sort((a, b) {
    final start = a.startMinute.compareTo(b.startMinute);
    if (start != 0) return start;
    final end = b.endMinute.compareTo(a.endMinute);
    return end == 0 ? a.event.id.compareTo(b.event.id) : end;
  });
  final result = <CalendarPlacement>[];
  final group = <(CalendarSegment, int)>[];
  final laneEnds = <double>[];
  var groupEnd = -1.0;
  void flush() {
    result.addAll(
      group.map((item) => CalendarPlacement(item.$1, item.$2, laneEnds.length)),
    );
    group.clear();
    laneEnds.clear();
  }

  for (final segment in segments) {
    if (segment.startMinute >= groupEnd) flush();
    var lane = laneEnds.indexWhere((end) => end <= segment.startMinute);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(segment.endMinute);
    } else {
      laneEnds[lane] = segment.endMinute;
    }
    group.add((segment, lane));
    groupEnd = laneEnds.reduce((a, b) => a > b ? a : b);
  }
  flush();
  return result;
}
