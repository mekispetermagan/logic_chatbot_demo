import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

const calendarTimeZone = 'Europe/Budapest';

final tz.Location budapest = _budapest();

tz.Location _budapest() {
  timezone_data.initializeTimeZones();
  return tz.getLocation(calendarTimeZone);
}

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String calendarTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

const calendarMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const calendarWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class CalendarWeek {
  CalendarWeek.containing(DateTime instant)
    : this._(tz.TZDateTime.from(instant, budapest));

  CalendarWeek._(tz.TZDateTime date)
    : start = tz.TZDateTime(
        budapest,
        date.year,
        date.month,
        date.day - date.weekday + 1,
      );

  final tz.TZDateTime start;

  // Construct calendar midnights rather than adding fixed 24-hour durations.
  tz.TZDateTime day(int offset) =>
      tz.TZDateTime(budapest, start.year, start.month, start.day + offset);

  tz.TZDateTime get end => day(7);

  CalendarWeek shift(int weeks) => CalendarWeek._(day(weeks * 7));

  String get label {
    final last = day(6);
    if (start.year != last.year) {
      return '${calendarMonths[start.month - 1]} ${start.year} – '
          '${calendarMonths[last.month - 1]} ${last.year}';
    }
    if (start.month != last.month) {
      return '${calendarMonths[start.month - 1]}–${calendarMonths[last.month - 1]} ${start.year}';
    }
    return '${calendarMonths[start.month - 1]} ${start.year}';
  }
}
