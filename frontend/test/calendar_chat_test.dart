import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logic_chatbot/widgets/chat_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/calendar_api.dart';
import 'package:logic_chatbot/controllers/calendar_controller.dart';
import 'package:logic_chatbot/models/calendar_event.dart';
import 'package:logic_chatbot/widgets/calendar_chat_panel.dart';

void main() {
  test('empty title stays empty in data and gets a display label', () {
    final event = CalendarEvent.fromJson({
      'id': 'a',
      'summary': '',
      'start': {'dateTime': '2026-10-29T09:00:00+01:00'},
      'end': {'dateTime': '2026-10-29T10:00:00+01:00'},
    })!;
    expect(event.title, '');
    expect(event.displayTitle, '(Untitled)');
  });

  testWidgets('clarification disables editing and submits its typed option', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final controller = CalendarController(
      api: CalendarApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'status': 'review',
                'revision': 8,
                'messages': [],
                'plan': [],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'status': 'clarify',
              'revision': 7,
              'messages': [],
              'question': {
                'key': '0.threshold',
                'prompt': 'What may move?',
                'kind': 'importance',
                'options': [
                  ['Normal', 0],
                ],
              },
            }),
            200,
          );
        }),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarChatPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.canEdit, isFalse);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('calendar-entry')))
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    expect(requests.single, {
      'type': 'answer',
      'key': '0.threshold',
      'value': 0,
      'revision': 7,
    });
    expect(find.text('Accept changes'), findsOneWidget);
    expect(controller.canEdit, isFalse);
    expect(requests.where((r) => r['type'] == 'accept'), isEmpty);
  });

  testWidgets('failed submission preserves entry for repair', (tester) async {
    final controller = CalendarController(
      api: CalendarApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient(
          (request) async => request.method == 'POST'
              ? http.Response(
                  jsonEncode({'detail': 'Invalid Calendar language'}),
                  422,
                )
              : http.Response(
                  jsonEncode({'status': 'idle', 'revision': 0, 'messages': []}),
                  200,
                ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarChatPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calendar-entry')),
      'broken entry',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid Calendar language'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('calendar-entry')))
          .controller!
          .text,
      'broken entry',
    );
  });
  testWidgets(
    'Calendar reuses shared chat: Enter submits, Shift Enter adds a line, arrows recall history',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'text': 'first failed entry'},
        {'role': 'machine', 'text': 'Syntax error', 'isError': true},
        {'role': 'user', 'text': 'second entry'},
      ];
      final controller = CalendarController(
        api: CalendarApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/events')) {
              return http.Response(jsonEncode({'events': []}), 200);
            }
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              requests.add(body);
              messages.add({'role': 'user', 'text': body['text']});
              messages.add({
                'role': 'machine',
                'text': 'Invalid Calendar language',
                'isError': true,
              });
            }
            return http.Response(
              jsonEncode({
                'status': 'error',
                'revision': requests.length,
                'messages': messages,
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalendarChatPanel(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatPanel), findsOneWidget);
      final input = find.byKey(const ValueKey('calendar-entry'));
      await tester.enterText(input, 'draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(tester.widget<TextField>(input).controller!.text, 'second entry');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'first failed entry',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(tester.widget<TextField>(input).controller!.text, 'draft');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tester.widget<TextField>(input).controller!.text, 'draft\n');
      expect(requests, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(requests.single['text'], 'draft\n');
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.text('Invalid Calendar language'), findsOneWidget);
      await controller.loadDialogue();
      await tester.pumpAndSettle();
      await tester.tap(input);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(tester.widget<TextField>(input).controller!.text, 'draft\n');
      expect(controller.dialogue!['messages'], hasLength(5));
    },
  );
}
