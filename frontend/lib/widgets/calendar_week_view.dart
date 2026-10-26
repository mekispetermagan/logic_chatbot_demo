import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../controllers/calendar_controller.dart';
import '../models/calendar_event.dart';
import '../models/calendar_week.dart';
import 'calendar_event_layout.dart';

const calendarHourHeight = 64.0;
const _axisWidth = 58.0;
const _gridTop = 10.0;

class CalendarWeekView extends StatefulWidget {
  const CalendarWeekView({super.key, required this.controller, this.now});
  final CalendarController controller;
  final DateTime Function()? now;

  @override
  State<CalendarWeekView> createState() => _CalendarWeekViewState();
}

class _CalendarWeekViewState extends State<CalendarWeekView>
    with WidgetsBindingObserver {
  CalendarController get controller => widget.controller;
  late tz.TZDateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateTime();
  }

  void _updateTime() {
    _now = tz.TZDateTime.from((widget.now ?? DateTime.now)(), budapest);
    _timer?.cancel();
    final elapsed =
        _now.second * Duration.microsecondsPerSecond +
        _now.millisecond * Duration.microsecondsPerMillisecond +
        _now.microsecond;
    _timer = Timer(
      Duration(microseconds: Duration.microsecondsPerMinute - elapsed),
      () => setState(_updateTime),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(_updateTime);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () => controller.shiftWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: () => controller.shiftWeek(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.week.label,
                    key: const ValueKey('calendar-week-label'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 600)
                  Text(calendarTimeZone, style: theme.textTheme.bodySmall),
                IconButton(
                  tooltip: 'Refresh calendar',
                  onPressed: controller.loading ? null : controller.load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error)),
                    TextButton(
                      onPressed: controller.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = math.max(640.0, constraints.maxWidth);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: width,
                          height: constraints.maxHeight,
                          child: Column(
                            children: [
                              _DayHeaders(week: controller.week, today: _now),
                              SizedBox(
                                height: 3,
                                child: controller.loading
                                    ? const LinearProgressIndicator()
                                    : null,
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: SingleChildScrollView(
                                        key: const ValueKey(
                                          'calendar-hours-scroll',
                                        ),
                                        child: _WeekGrid(
                                          week: controller.week,
                                          events: controller.events,
                                          now: _now,
                                        ),
                                      ),
                                    ),
                                    if (!controller.loading &&
                                        controller.error == null &&
                                        controller.events.isEmpty)
                                      const Positioned(
                                        top: 18,
                                        left: _axisWidth,
                                        right: 0,
                                        child: Center(
                                          child: Card(
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              child: Text(
                                                'No timed events this week.',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _DayHeaders extends StatelessWidget {
  const _DayHeaders({required this.week, required this.today});
  final CalendarWeek week;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 80,
      child: Row(
        children: [
          SizedBox(
            width: _axisWidth,
            child: Center(
              child: Text(
                'CET/\nCEST',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          for (var index = 0; index < 7; index++)
            Expanded(
              child: Container(
                key: ValueKey('calendar-day-$index'),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      calendarWeekdays[index],
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: sameCalendarDay(week.day(index), today)
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sameCalendarDay(week.day(index), today)
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                      ),
                      child: Text(
                        '${week.day(index).day}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: sameCalendarDay(week.day(index), today)
                              ? theme.colorScheme.onPrimary
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.week,
    required this.events,
    required this.now,
  });
  final CalendarWeek week;
  final List<CalendarEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dayWidth = (constraints.maxWidth - _axisWidth) / 7;
      return SizedBox(
        key: const ValueKey('calendar-time-grid'),
        height: 24 * calendarHourHeight + _gridTop * 2,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _CalendarGridPainter(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  weekend: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
              ),
            ),
            for (var hour = 0; hour <= 24; hour++)
              Positioned(
                left: 0,
                width: _axisWidth - 8,
                top: _gridTop + hour * calendarHourHeight - 8,
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            for (var day = 0; day < 7; day++)
              for (final placement in layoutCalendarDay(
                events
                    .where(
                      (event) => sameCalendarDay(event.start, week.day(day)),
                    )
                    .toList(),
              ))
                _positionedEvent(placement, day, dayWidth),
            for (var day = 0; day < 7; day++)
              if (sameCalendarDay(now, week.day(day)))
                Positioned(
                  left: _axisWidth + day * dayWidth,
                  top:
                      _gridTop +
                      (now.hour + now.minute / 60) * calendarHourHeight,
                  width: dayWidth,
                  height: 2,
                  child: IgnorePointer(
                    child: Semantics(
                      label:
                          'Current time: ${calendarTime(now)} $calendarTimeZone',
                      child: const ColoredBox(
                        key: ValueKey('calendar-now-line'),
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );

  Widget _positionedEvent(
    CalendarPlacement placement,
    int day,
    double dayWidth,
  ) {
    final event = placement.event;
    final minutes = event.crossesRepeatedHour
        ? event.end.difference(event.start).inSeconds / 60
        : event.endMinute - event.startMinute;
    final width = dayWidth / placement.lanes;
    return Positioned(
      left: _axisWidth + day * dayWidth + placement.lane * width + 2,
      top: _gridTop + event.startMinute / 60 * calendarHourHeight,
      width: math.max(1, width - 4),
      height: math.max(4, minutes / 60 * calendarHourHeight - 2),
      child: _EventTile(
        key: ValueKey('calendar-event-${event.id}'),
        event: event,
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({super.key, required this.event});
  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    const colors = {
      '1': Color(0xff7986cb),
      '2': Color(0xff33b679),
      '3': Color(0xff8e24aa),
      '4': Color(0xffe67c73),
      '5': Color(0xfff6bf26),
      '6': Color(0xfff4511e),
      '7': Color(0xff039be5),
      '8': Color(0xff616161),
      '9': Color(0xff3f51b5),
      '10': Color(0xff0b8043),
      '11': Color(0xffd50000),
    };
    final color = colors[event.colorId] ?? const Color(0xff4285f4);
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Tooltip(
      message: event.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        label: event.tooltip,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Padding(
              padding: EdgeInsets.all(constraints.maxHeight < 20 ? 1 : 6),
              child: Text(
                constraints.maxHeight >= 44
                    ? '${event.title}\n${calendarTime(event.start)}–${calendarTime(event.end)}'
                    : event.title,
                maxLines: constraints.maxHeight >= 44 ? 3 : 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarGridPainter extends CustomPainter {
  const _CalendarGridPainter({required this.color, required this.weekend});
  final Color color;
  final Color weekend;

  @override
  void paint(Canvas canvas, Size size) {
    final dayWidth = (size.width - _axisWidth) / 7;
    canvas.drawRect(
      Rect.fromLTWH(
        _axisWidth + dayWidth * 5,
        _gridTop,
        dayWidth * 2,
        calendarHourHeight * 24,
      ),
      Paint()..color = weekend,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7;
    for (var hour = 0; hour <= 24; hour++) {
      final y = _gridTop + hour * calendarHourHeight;
      canvas.drawLine(Offset(_axisWidth, y), Offset(size.width, y), paint);
    }
    for (var day = 0; day <= 7; day++) {
      final x = _axisWidth + day * dayWidth;
      canvas.drawLine(
        Offset(x, _gridTop),
        Offset(x, _gridTop + calendarHourHeight * 24),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CalendarGridPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.weekend != weekend;
}
