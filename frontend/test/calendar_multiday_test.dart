import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:logic_chatbot/models/calendar_event.dart';
import 'package:logic_chatbot/models/calendar_week.dart';
import 'package:logic_chatbot/widgets/calendar_event_layout.dart';
import 'package:logic_chatbot/widgets/calendar_event_dialog.dart';
import 'package:logic_chatbot/widgets/calendar_week_view.dart';
import 'calendar_test.dart' show entry, eventsResponse, controller;

CalendarEvent event(String id, String start, String end) =>
    CalendarEvent.fromJson(entry(id, start, end))!;

void main() {
  final week = CalendarWeek.containing(DateTime.utc(2026, 10, 27));
  final overnight = event(
    'overnight',
    '2026-10-26T22:00:00+01:00',
    '2026-10-28T09:00:00+01:00',
  );

  test(
    'multi-day slices retain identity, clip to day, and expose continuation',
    () {
      final slices = [
        for (var day = 0; day < 3; day++)
          layoutCalendarDay([overnight], day: week.day(day)).single.segment,
      ];
      expect(slices.map((s) => (s.startMinute, s.endMinute)), [
        (1320, 1440),
        (0, 1440),
        (0, 540),
      ]);
      expect(slices.map((s) => s.timeLabel), ['22:00–↓', '↑–↓', '↑–09:00']);
      expect(slices.every((s) => identical(s.event, overnight)), isTrue);
      expect(overnight.crossesRepeatedHour, isFalse);
      expect(overnight.tooltip, contains('Start: Mon, 26 Oct 2026 22:00'));
      expect(overnight.tooltip, contains('End: Wed, 28 Oct 2026 09:00'));
      expect(overnight.tooltip, isNot(contains('Clocks move back')));
      expect(layoutCalendarDay([overnight], day: week.day(3)), isEmpty);
      final other = event(
        'other',
        '2026-10-27T09:00:00+01:00',
        '2026-10-27T10:00:00+01:00',
      );
      expect(
        layoutCalendarDay([
          overnight,
          other,
        ], day: week.day(1)).map((p) => p.lanes),
        [2, 2],
      );
    },
  );

  test('midnight end is exclusive; midnight start is an actual boundary', () {
    final ending = event(
      'end',
      '2026-10-26T23:00:00+01:00',
      '2026-10-27T00:00:00+01:00',
    );
    final first = layoutCalendarDay([ending], day: week.day(0)).single.segment;
    expect(first.endMinute, 1440);
    expect(first.continuesAfter, isFalse);
    expect(layoutCalendarDay([ending], day: week.day(1)), isEmpty);
    final starting = event(
      'start',
      '2026-10-27T00:00:00+01:00',
      '2026-10-27T01:00:00+01:00',
    );
    final second = layoutCalendarDay([
      starting,
    ], day: week.day(1)).single.segment;
    expect(second.continuesBefore, isFalse);
    expect(second.timeLabel, '00:00–01:00');
  });

  test('daily boundaries use local midnights across both DST changes', () {
    for (final date in [
      DateTime.utc(2026, 3, 29, 12),
      DateTime.utc(2026, 10, 25, 12),
    ]) {
      final local = tz.TZDateTime.from(date, budapest);
      final day = tz.TZDateTime(budapest, local.year, local.month, local.day);
      final next = tz.TZDateTime(
        budapest,
        local.year,
        local.month,
        local.day + 1,
      );
      final span = CalendarEvent(
        id: 'dst',
        title: 'DST',
        start: day,
        end: next,
      );
      final slice = layoutCalendarDay([span], day: day).single.segment;
      expect((slice.startMinute, slice.endMinute), (0, 1440));
      expect(slice.continuesBefore || slice.continuesAfter, isFalse);
      expect(layoutCalendarDay([span], day: next), isEmpty);
      expect(next.difference(day).inHours, local.month == 3 ? 23 : 25);
    }
  });

  test(
    'weekly load includes overlapping events, excludes boundary-only touches',
    () async {
      final subject = controller(
        (_) async => eventsResponse([
          entry(
            'before',
            '2026-10-25T22:00:00+01:00',
            '2026-10-26T02:00:00+01:00',
          ),
          entry(
            'after',
            '2026-11-01T22:00:00+01:00',
            '2026-11-02T02:00:00+01:00',
          ),
          entry(
            'entire',
            '2026-10-01T00:00:00+02:00',
            '2026-12-01T00:00:00+01:00',
          ),
          entry(
            'touch-start',
            '2026-10-25T22:00:00+01:00',
            '2026-10-26T00:00:00+01:00',
          ),
          entry(
            'touch-end',
            '2026-11-02T00:00:00+01:00',
            '2026-11-02T01:00:00+01:00',
          ),
        ]),
      );
      addTearDown(subject.dispose);
      await subject.load();
      expect(subject.events.map((e) => e.id), ['before', 'after', 'entire']);
    },
  );

  testWidgets(
    'continuation segment opens original event; unrelated edit preserves interval',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final raw = entry(
        'overnight',
        '2026-10-26T22:00:25+01:00',
        '2026-10-28T09:00:25+01:00',
      );
      final subject = controller((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({'verified': true, 'event': raw}),
            200,
          );
        }
        return eventsResponse([raw]);
      });
      addTearDown(subject.dispose);
      await subject.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalendarWeekView(controller: subject)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-event-overnight')),
        findsNWidgets(3),
      );
      final grid = tester.getRect(
        find.byKey(const ValueKey('calendar-time-grid')),
      );
      final dayWidth = (grid.width - 58) / 7;
      await tester.tapAt(
        Offset(grid.left + 58 + 1.5 * dayWidth, grid.top + 60),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start: Mon, 26 Oct 2026 22:00'), findsOneWidget);
      expect(
        find.text('End: Wed, 28 Oct 2026 09:00 · Europe/Budapest'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit event'));
      await tester.pumpAndSettle();
      expect(find.text('Start date: 26 Oct 2026'), findsOneWidget);
      expect(find.text('End date: 28 Oct 2026'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('calendar-title')),
        'Renamed',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests[1].body), {'summary': 'Renamed'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late creation defaults across midnight and allows independent end date',
    (tester) async {
      final requests = <http.Request>[];
      final raw = entry(
        'created',
        '2026-10-27T23:30:00+01:00',
        '2026-10-29T00:30:00+01:00',
      );
      final subject = controller((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'verified': true, 'event': raw}),
            201,
          );
        }
        return eventsResponse([]);
      });
      addTearDown(subject.dispose);
      await subject.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CalendarEventDialog(
                    controller: subject,
                    initialStart: tz.TZDateTime(budapest, 2026, 10, 27, 23, 30),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('End date: 28 Oct 2026'), findsOneWidget);
      expect(find.text('End 00:30'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-end-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('29'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('calendar-title')),
        'Late event',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final fields = jsonDecode(requests[1].body);
      expect(
        DateTime.parse(fields['start']['dateTime']).toUtc(),
        DateTime.utc(2026, 10, 27, 22, 30),
      );
      expect(
        DateTime.parse(fields['end']['dateTime']).toUtc(),
        DateTime.utc(2026, 10, 28, 23, 30),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
