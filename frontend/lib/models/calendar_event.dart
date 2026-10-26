import 'package:timezone/timezone.dart' as tz;

import 'calendar_week.dart';

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
    this.location = '',
    this.colorId,
  });

  final String id;
  final String title;
  final tz.TZDateTime start;
  final tz.TZDateTime end;
  final String description;
  final String location;
  final String? colorId;

  static CalendarEvent? fromJson(Map<String, dynamic> json) {
    if (json['status'] == 'cancelled') return null;
    final startValue = json['start'] as Map<String, dynamic>?;
    final endValue = json['end'] as Map<String, dynamic>?;
    if (startValue?['date'] != null || endValue?['date'] != null) return null;
    tz.TZDateTime parse(Map<String, dynamic>? value) {
      final text = value?['dateTime'];
      if (text is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
        throw const FormatException(
          'Calendar timestamps must include an offset',
        );
      }
      return tz.TZDateTime.from(DateTime.parse(text), budapest);
    }

    final start = parse(startValue);
    final end = parse(endValue);
    if (!sameCalendarDay(start, end)) return null;
    if (!end.isAfter(start) || json['id'] is! String) {
      throw const FormatException('Invalid calendar event');
    }
    final title = json['summary'] as String?;
    return CalendarEvent(
      id: json['id'] as String,
      title: title == null || title.trim().isEmpty ? '(Untitled)' : title,
      start: start,
      end: end,
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      colorId: json['colorId'] as String?,
    );
  }

  double get startMinute => start.hour * 60 + start.minute + start.second / 60;
  double get endMinute => end.hour * 60 + end.minute + end.second / 60;

  bool get crossesRepeatedHour => endMinute <= startMinute;

  String get tooltip {
    final offset = start.timeZoneOffset;
    final sign = offset.isNegative ? '−' : '+';
    final hours = offset.inMinutes.abs() ~/ 60;
    final minutes = offset.inMinutes.abs() % 60;
    return [
      title,
      '${calendarWeekdays[start.weekday - 1]}, ${start.day} '
          '${calendarMonths[start.month - 1]} ${start.year}',
      '${calendarTime(start)}–${calendarTime(end)} · $calendarTimeZone',
      'UTC$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}'
          '${start.timeZoneOffset != end.timeZoneOffset ? ' → UTC+${end.timeZoneOffset.inHours.toString().padLeft(2, '0')}:00' : ''}',
      if (crossesRepeatedHour)
        'Clocks move back during this event; height shows elapsed duration.',
      if (location.isNotEmpty) location,
      if (description.isNotEmpty) description,
    ].join('\n');
  }
}
