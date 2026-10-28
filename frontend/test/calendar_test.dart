import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/calendar_api.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/calendar_controller.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/models/calendar_event.dart';
import 'package:logic_chatbot/models/calendar_week.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/storage/conversation_id_store.dart';
import 'package:logic_chatbot/widgets/calendar_event_layout.dart';
import 'package:logic_chatbot/widgets/calendar_week_view.dart';
import 'package:logic_chatbot/widgets/chat_panel.dart';

Map<String, dynamic> entry(
  String id,
  String start,
  String end, {
  String? title,
}) => {
  'id': id,
  'summary': title ?? id,
  'start': {'dateTime': start},
  'end': {'dateTime': end},
  'location': 'Budapest',
  'description': 'Event details',
  'colorId': '9',
};

CalendarEvent appointment(String id, String start, String end) =>
    CalendarEvent.fromJson(
      entry(id, '2026-10-27T$start+01:00', '2026-10-27T$end+01:00'),
    )!;

http.Response eventsResponse(List<Map<String, dynamic>> events) =>
    http.Response(
      jsonEncode({'events': events}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

CalendarController controller(
  Future<http.Response> Function(http.Request) request,
) => CalendarController(
  api: CalendarApi(
    baseUrl: Uri.parse('http://localhost:8000/api'),
    client: MockClient(request),
  ),
  now: () => DateTime.utc(2026, 10, 26, 12),
);

class _Store implements ConversationIdStore {
  @override
  Future<String?> read({WorldDomain domain = WorldDomain.objects}) async =>
      null;
  @override
  Future<void> write(
    String id, {
    WorldDomain domain = WorldDomain.objects,
  }) async {}
}

void main() {
  test(
    'week navigation uses Monday midnights and Budapest DST, not fixed durations',
    () {
      final autumn = CalendarWeek.containing(DateTime.utc(2026, 10, 25, 12));
      expect(autumn.start.day, 19);
      expect(autumn.end.day, 26);
      expect(autumn.end.difference(autumn.start).inHours, 169);
      expect(autumn.shift(1).start.hour, 0);
      final spring = CalendarWeek.containing(DateTime.utc(2026, 3, 29, 12));
      expect(spring.end.difference(spring.start).inHours, 167);
      expect(
        CalendarWeek.containing(DateTime.utc(2026, 10, 26)).label,
        'Oct–Nov 2026',
      );
      expect(
        CalendarWeek.containing(DateTime.utc(2026, 12, 31)).label,
        'Dec 2026 – Jan 2027',
      );
      expect(autumn.shift(2).shift(-2).start, autumn.start);
    },
  );

  test(
    'events use Budapest wall time and omit only all-day and cancelled entries',
    () {
      final event = CalendarEvent.fromJson(
        entry('party', '2026-10-26T21:00:00Z', '2026-10-26T22:00:00Z'),
      )!;
      expect(event.start.hour, 22);
      expect(event.end.hour, 23);
      expect(event.tooltip, contains('Europe/Budapest'));
      expect(event.tooltip, contains('Event details'));
      expect(
        CalendarEvent.fromJson({
          'id': 'day',
          'start': {'date': '2026-10-27'},
          'end': {'date': '2026-10-28'},
        }),
        isNull,
      );
      expect(
        CalendarEvent.fromJson(
          entry(
            'overnight',
            '2026-10-26T23:00:00+01:00',
            '2026-10-27T01:00:00+01:00',
          ),
        ),
        isNotNull,
      );
      expect(
        CalendarEvent.fromJson(
          entry(
            'midnight',
            '2026-10-26T23:00:00+01:00',
            '2026-10-27T00:00:00+01:00',
          ),
        ),
        isNotNull,
      );
      expect(
        CalendarEvent.fromJson({'id': 'cancelled', 'status': 'cancelled'}),
        isNull,
      );
      expect(
        () => CalendarEvent.fromJson(
          entry('naive', '2026-10-27T09:00:00', '2026-10-27T10:00:00'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'overlaps share lanes, touching intervals do not, later groups regain full width',
    () {
      final layout = layoutCalendarDay([
        appointment('a', '09:00:00', '10:00:00'),
        appointment('b', '09:30:00', '11:00:00'),
        appointment('c', '10:00:00', '10:30:00'),
        appointment('d', '11:00:00', '12:00:00'),
      ]);
      expect(layout.map((item) => (item.lane, item.lanes)), [
        (0, 2),
        (1, 2),
        (0, 2),
        (0, 1),
      ]);
      final fallback = CalendarEvent.fromJson(
        entry(
          'fallback',
          '2026-10-25T02:45:00+02:00',
          '2026-10-25T02:15:00+01:00',
        ),
      )!;
      expect(fallback.crossesRepeatedHour, isTrue);
      expect(fallback.tooltip, contains('Clocks move back'));
      expect(layoutCalendarDay([fallback]).single.lanes, 1);
    },
  );

  test(
    'API gets one bounded weekly event list and filters only display exclusions',
    () async {
      final requests = <http.Request>[];
      final subject = controller((request) async {
        requests.add(request);
        return eventsResponse([
          entry(
            'party',
            '2026-10-26T22:00:00+01:00',
            '2026-10-26T23:00:00+01:00',
            title: 'Codex party',
          ),
          {
            'id': 'all-day',
            'start': {'date': '2026-10-27'},
            'end': {'date': '2026-10-28'},
          },
          entry(
            'outside',
            '2026-11-03T09:00:00+01:00',
            '2026-11-03T10:00:00+01:00',
          ),
        ]);
      });
      addTearDown(subject.dispose);
      await subject.load();
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/calendar/events');
      expect(requests.single.url.queryParameters, {
        'timeMin': '2026-10-25T23:00:00.000Z',
        'timeMax': '2026-11-01T23:00:00.000Z',
        'timeZone': 'Europe/Budapest',
      });
      expect(subject.events.single.title, 'Codex party');
    },
  );

  test(
    'late responses cannot replace the selected week and disposal ignores pending work',
    () async {
      final responses = [
        Completer<http.Response>(),
        Completer<http.Response>(),
      ];
      var index = 0;
      final subject = controller((_) => responses[index++].future);
      final first = subject.load();
      final second = subject.shiftWeek(1);
      responses[1].complete(
        eventsResponse([
          entry(
            'new',
            '2026-11-03T09:00:00+01:00',
            '2026-11-03T10:00:00+01:00',
          ),
        ]),
      );
      await second;
      responses[0].complete(eventsResponse([]));
      await first;
      expect(subject.events.single.id, 'new');
      expect(subject.week.start.day, 2);
      subject.dispose();

      final pending = Completer<http.Response>();
      final disposed = controller((_) => pending.future);
      final load = disposed.load();
      disposed.dispose();
      pending.complete(eventsResponse([]));
      await load;
    },
  );

  testWidgets(
    'weekly grid positions events, shows tooltips and scrolls to 24:00',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final subject = controller(
        (_) async => eventsResponse([
          entry(
            'a',
            '2026-10-27T09:15:00+01:00',
            '2026-10-27T10:45:00+01:00',
            title: 'Morning meeting',
          ),
          entry('b', '2026-10-27T10:00:00+01:00', '2026-10-27T11:00:00+01:00'),
          entry(
            'party',
            '2026-10-26T22:00:00+01:00',
            '2026-10-26T23:00:00+01:00',
            title: 'Codex party',
          ),
        ]),
      );
      addTearDown(subject.dispose);
      await subject.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(body: CalendarWeekView(controller: subject)),
        ),
      );
      await tester.pumpAndSettle();
      for (final day in calendarWeekdays) {
        expect(find.text(day), findsOneWidget);
      }
      expect(find.text('Oct–Nov 2026'), findsOneWidget);
      final grid = tester.getRect(
        find.byKey(const ValueKey('calendar-time-grid')),
      );
      final tile = tester.getRect(
        find.byKey(const ValueKey('calendar-event-a')),
      );
      final overlap = tester.getRect(
        find.byKey(const ValueKey('calendar-event-b')),
      );
      expect(
        tile.top - grid.top,
        closeTo(10 + 9.25 * calendarHourHeight, 0.01),
      );
      expect(tile.height, closeTo(1.5 * calendarHourHeight - 2, 0.01));
      expect(tile.right, lessThan(overlap.left));
      final headerTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-day-0')))
          .dy;
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      await mouse.moveTo(tile.center);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(subject.events.first.tooltip), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('24:00'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-event-party')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('calendar-day-0'))).dy,
        headerTop,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, error/retry, empty and narrow layouts remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<http.Response>();
    var calls = 0;
    final subject = controller(
      (_) async => ++calls == 1 ? await pending.future : eventsResponse([]),
    );
    addTearDown(subject.dispose);
    final load = subject.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarWeekView(controller: subject)),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(
      http.Response(
        jsonEncode({'detail': 'Calendar authorization failed.'}),
        503,
      ),
    );
    await load;
    await tester.pumpAndSettle();
    expect(find.text('Calendar authorization failed.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No timed events this week.'), findsOneWidget);
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(subject.week.start.day, 2);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1920.0]) {
    testWidgets(
      'Calendar occupies the World panel at width $width with Calendar dialogue',
      (tester) async {
        tester.view.physicalSize = Size(width, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calendarRequests = <http.Request>[];
        final conversationRequests = <http.Request>[];
        final calendar = controller((request) async {
          calendarRequests.add(request);
          if (request.url.path.endsWith('/dialogue')) {
            return http.Response(
              jsonEncode({'status': 'idle', 'revision': 0, 'messages': []}),
              200,
            );
          }
          return eventsResponse([]);
        });
        final world = jsonDecode(
          File('../backend/shared/toy_world.json').readAsStringSync(),
        );
        final conversation = ConversationController(
          store: _Store(),
          api: ConversationApi(
            baseUrl: Uri.parse('http://localhost:8000'),
            client: MockClient((request) async {
              conversationRequests.add(request);
              return http.Response(
                jsonEncode({
                  'conversationId': 'objects',
                  'domain': 'objects',
                  'canUndo': false,
                  'world': world,
                }),
                201,
              );
            }),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: DemoScreen(
              createController: () => conversation,
              createCalendarController: () => calendar,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calendarRequests, isEmpty);
        if (width < 480) {
          await tester.tap(find.text('Chat'));
          await tester.pumpAndSettle();
        }
        final sharedChatSize = tester.getSize(find.byType(ChatPanel));
        final sharedComposerWidth = tester
            .getSize(find.byType(TextField).last)
            .width;
        void expectUniformChat() {
          expect(tester.getSize(find.byType(ChatPanel)), sharedChatSize);
          expect(
            tester.getSize(find.byType(TextField).last).width,
            sharedComposerWidth,
          );
          expect(find.text('Calendar dialogue'), findsNothing);
          expect(find.byTooltip('Refresh dialogue status'), findsNothing);
          expect(find.text('Enter a sentence to begin.'), findsOneWidget);
        }

        if (width < 480) {
          await tester.tap(find.byKey(const ValueKey('domain-selector')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Calendar').last);
        await tester.pumpAndSettle();
        expect(find.byType(CalendarWeekView), findsOneWidget);
        expect(find.byTooltip('Next week').hitTestable(), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(CalendarWeekView),
            matching: find.byType(PanelFrame),
          ),
          findsOneWidget,
        );
        if (width >= 900) {
          expect(
            tester.getRect(find.byType(CalendarWeekView)).right,
            lessThanOrEqualTo(width / 2),
          );
          expect(find.byType(ChatPanel), findsOneWidget);
          expectUniformChat();
          expect(find.byType(TabBar), findsNothing);
        } else {
          expect(find.byType(TabBar), findsOneWidget);
          await tester.tap(find.text('Chat'));
          await tester.pumpAndSettle();
          expect(find.byType(ChatPanel), findsOneWidget);
          expect(find.byType(TextField).last.hitTestable(), findsOneWidget);
          expectUniformChat();
          await tester.tap(find.text('World'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byTooltip('Undo'), findsNothing);
        expect(calendarRequests, hasLength(2));
        expect(conversationRequests, hasLength(1));
        if (width < 480) {
          await tester.tap(find.byKey(const ValueKey('domain-selector')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Objects').last);
        await tester.pumpAndSettle();
        expect(find.byType(CalendarWeekView), findsNothing);
        expect(conversation.domain, WorldDomain.objects);
        expect(conversationRequests, hasLength(1));
      },
    );
  }

  testWidgets(
    'current-time line tracks Budapest minutes and midnight without fetching',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = DateTime.utc(2026, 10, 27, 8, 15, 30);
      var requests = 0;
      final subject = controller((_) async {
        requests++;
        return eventsResponse([]);
      });
      addTearDown(subject.dispose);
      await subject.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarWeekView(controller: subject, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byKey(const ValueKey('calendar-now-line'));
      final grid = tester.getRect(
        find.byKey(const ValueKey('calendar-time-grid')),
      );
      final line = tester.getRect(finder);
      final dayWidth = (grid.width - 58) / 7;
      expect(line.left - grid.left, closeTo(58 + dayWidth, 0.01));
      expect(line.width, closeTo(dayWidth, 0.01));
      expect(
        line.top - grid.top,
        closeTo(10 + 9.25 * calendarHourHeight, 0.01),
      );
      expect(tester.widget<ColoredBox>(finder).color, Colors.red);

      now = DateTime.utc(2026, 10, 27, 8, 16);
      await tester.pump(const Duration(seconds: 30));
      expect(
        tester.getTopLeft(finder).dy - line.top,
        closeTo(calendarHourHeight / 60, 0.01),
      );
      now = DateTime.utc(2026, 10, 27, 23); // Midnight Wednesday in Budapest.
      await tester.pump(const Duration(minutes: 1));
      expect(
        tester.getTopLeft(finder).dx - grid.left,
        closeTo(58 + dayWidth * 2, 0.01),
      );
      expect(tester.getTopLeft(finder).dy - grid.top, closeTo(10, 0.01));
      expect(requests, 1);

      await subject.shiftWeek(1);
      await tester.pumpAndSettle();
      expect(finder, findsNothing);
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar preview artifact', (tester) async {
    // Optional visual inspection artifact; never contacts the live calendar.
    if (!const bool.fromEnvironment('CALENDAR_PREVIEW')) return;
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final subject = controller(
      (_) async => eventsResponse([
        entry(
          'one',
          '2026-10-27T09:00:00+01:00',
          '2026-10-27T10:00:00+01:00',
          title: 'Test event',
        ),
        {
          ...entry(
            'two',
            '2026-10-27T09:30:00+01:00',
            '2026-10-27T11:00:00+01:00',
            title: 'Team review',
          ),
          'colorId': '2',
        },
        {
          ...entry(
            'three',
            '2026-10-29T11:00:00+01:00',
            '2026-10-29T12:30:00+01:00',
            title: 'Planning',
          ),
          'colorId': '6',
        },
      ]),
    );
    addTearDown(subject.dispose);
    await subject.load();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(body: CalendarWeekView(controller: subject)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/logic-chatbot-calendar-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
