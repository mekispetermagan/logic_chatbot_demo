import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logic_chatbot/widgets/calendar_event_dialog.dart';
import 'package:logic_chatbot/widgets/calendar_week_view.dart';
import 'package:logic_chatbot/widgets/calendar_colors.dart';
import 'calendar_test.dart' show controller, entry, eventsResponse;

void main() {
  final original = entry(
    'demo',
    '2026-10-27T09:00:25+01:00',
    '2026-10-27T10:00:25+01:00',
    title: 'Meeting',
  );

  test('importance decodes every color and encodes canonical IDs', () {
    for (final id in [
      null,
      '',
      '0',
      '1',
      '2',
      '3',
      '4',
      '6',
      '7',
      '8',
      '9',
      '10',
      '12',
    ]) {
      expect(calendarImportance(id), 0);
      expect(calendarEventColor(id), const Color(0xff0b8043));
    }
    expect(calendarImportance('5'), 1);
    expect(calendarEventColor('5'), const Color(0xfff6bf26));
    expect(calendarImportance('11'), 2);
    expect(calendarEventColor('11'), const Color(0xffd50000));
    expect(
      [for (var i = 0; i < 3; i++) calendarImportanceColorId(i)],
      ['10', '5', '11'],
    );
  });

  for (final explicitlySet in [false, true]) {
    testWidgets(
      'level zero preserves or normalizes existing color: $explicitlySet',
      (tester) async {
        final requests = <http.Request>[];
        final subject = controller((request) async {
          requests.add(request);
          if (request.method == 'PATCH') {
            return http.Response(
              jsonEncode({'verified': true, 'event': original}),
              200,
            );
          }
          return eventsResponse([original]);
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
                      event: subject.events.single,
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
        await tester.tap(find.byTooltip('Edit event'));
        await tester.pumpAndSettle();
        if (explicitlySet) {
          await tester.ensureVisible(
            find.byKey(const ValueKey('calendar-importance')),
          );
          await tester.tap(find.byKey(const ValueKey('calendar-importance')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Normal').last);
          await tester.pumpAndSettle();
        } else {
          await tester.enterText(
            find.byKey(const ValueKey('calendar-title')),
            'Renamed',
          );
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(requests.map((r) => r.method), ['GET', 'PATCH', 'GET']);
        expect(
          jsonDecode(requests[1].body),
          explicitlySet ? {'colorId': '10'} : {'summary': 'Renamed'},
        );
      },
    );
  }

  testWidgets('details, cancel, partial edit and verified refresh', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final subject = controller((request) async {
      requests.add(request);
      if (request.method == 'PATCH') {
        return http.Response(
          jsonEncode({'verified': true, 'event': original}),
          200,
        );
      }
      return eventsResponse([original]);
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
                  event: subject.events.single,
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
    expect(
      find.byKey(const ValueKey('calendar-event-details')),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.byTooltip('Edit event'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calendar-title')),
      'Discard',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    await tester.tap(find.byTooltip('Edit event'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calendar-description')),
      '',
    );
    await tester.enterText(
      find.byKey(const ValueKey('calendar-location')),
      'New place',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('calendar-importance')),
    );
    await tester.tap(find.byKey(const ValueKey('calendar-importance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Critical').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.method), ['GET', 'PATCH', 'GET']);
    expect(jsonDecode(requests[1].body), {
      'description': '',
      'location': 'New place',
      'colorId': '11',
    });
    expect(find.byType(CalendarEventDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires Yes and prevents duplicate submission', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final requests = <http.Request>[];
    final subject = controller((request) async {
      requests.add(request);
      if (request.method == 'DELETE') return pending.future;
      return eventsResponse([original]);
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
                  event: subject.events.single,
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
    await tester.tap(find.byTooltip('Delete event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    await tester.tap(find.byTooltip('Delete event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Yes'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'No'))
          .onPressed,
      isNull,
    );
    pending.complete(
      http.Response(
        jsonEncode({'verified': true, 'deleted': true, 'eventId': 'demo'}),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.method), ['GET', 'DELETE', 'GET']);
  });

  testWidgets(
    'empty slot creates a timed event and narrow editor validates title',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final subject = controller((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'verified': true, 'event': original}),
            201,
          );
        }
        return eventsResponse([]);
      });
      addTearDown(subject.dispose);
      await subject.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalendarWeekView(controller: subject)),
        ),
      );
      await tester.pumpAndSettle();
      final grid = tester.getRect(
        find.byKey(const ValueKey('calendar-empty-slots')),
      );
      await tester.tapAt(
        Offset(grid.left + 80, grid.top + 10 + 2.25 * calendarHourHeight),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-event-editor')),
        findsOneWidget,
      );
      expect(find.text('Start 02:15'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a title.'), findsOneWidget);
      expect(requests.length, 1);
      await tester.enterText(
        find.byKey(const ValueKey('calendar-title')),
        'New appointment',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(requests.map((r) => r.method), ['GET', 'POST', 'GET']);
      final fields = jsonDecode(requests[1].body) as Map;
      expect(fields['summary'], 'New appointment');
      expect(fields['colorId'], '10');
      final start = DateTime.parse(fields['start']['dateTime'] as String);
      expect(start.toUtc(), DateTime.utc(2026, 10, 26, 1, 15));
      expect(fields['start']['timeZone'], 'Europe/Budapest');
      expect(
        DateTime.parse(fields['end']['dateTime'] as String).difference(start),
        const Duration(hours: 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'uncertain writes block resubmission until refresh, without retry',
    () async {
      var writes = 0;
      final subject = controller((request) async {
        if (request.method == 'POST') {
          writes++;
          return http.Response('{"outcomeUnknown":true,"eventId":23}', 502);
        }
        return eventsResponse([]);
      });
      addTearDown(subject.dispose);
      await subject.load();
      await expectLater(
        subject.save(fields: {'summary': 'Party'}),
        throwsException,
      );
      expect(subject.needsRefresh, isTrue);
      await expectLater(
        subject.save(fields: {'summary': 'Party'}),
        throwsException,
      );
      expect(writes, 1);
      await subject.load();
      expect(subject.canEdit, isTrue);
    },
  );
}
