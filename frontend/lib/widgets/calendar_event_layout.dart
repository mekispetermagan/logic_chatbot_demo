import '../models/calendar_event.dart';

class CalendarPlacement {
  const CalendarPlacement(this.event, this.lane, this.lanes);
  final CalendarEvent event;
  final int lane;
  final int lanes;
}

/// Partition overlapping wall-clock intervals into stable side-by-side lanes.
List<CalendarPlacement> layoutCalendarDay(List<CalendarEvent> events) {
  double endOf(CalendarEvent event) => event.crossesRepeatedHour
      ? event.startMinute + event.end.difference(event.start).inSeconds / 60
      : event.endMinute;
  final sorted = [...events]
    ..sort((a, b) {
      final start = a.startMinute.compareTo(b.startMinute);
      if (start != 0) return start;
      final end = endOf(b).compareTo(endOf(a));
      return end == 0 ? a.id.compareTo(b.id) : end;
    });
  final result = <CalendarPlacement>[];
  final group = <(CalendarEvent, int)>[];
  final laneEnds = <double>[];
  var groupEnd = -1.0;
  void flush() {
    result.addAll(
      group.map((item) => CalendarPlacement(item.$1, item.$2, laneEnds.length)),
    );
    group.clear();
    laneEnds.clear();
  }

  for (final event in sorted) {
    if (event.startMinute >= groupEnd) flush();
    var lane = laneEnds.indexWhere((end) => end <= event.startMinute);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(endOf(event));
    } else {
      laneEnds[lane] = endOf(event);
    }
    group.add((event, lane));
    groupEnd = laneEnds.reduce((a, b) => a > b ? a : b);
  }
  flush();
  return result;
}
