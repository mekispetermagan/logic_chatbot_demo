import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/calendar_api.dart';
import 'package:logic_chatbot/controllers/calendar_controller.dart';
import 'package:logic_chatbot/widgets/calendar_chat_panel.dart';

void main() {
  late CalendarController controller;
  late Map<String, dynamic> state;
  late List<http.Request> posts;
  late bool fail;
  late int eventReads;
  setUp(() {
    state = {'status': 'idle', 'revision': 3, 'messages': []};
    posts = [];
    fail = false;
    eventReads = 0;
    controller = CalendarController(
      api: CalendarApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/events')) {
            eventReads++;
            return http.Response(jsonEncode({'events': []}), 200);
          }
          if (request.method == 'POST') {
            posts.add(request);
            if (fail) return http.Response('{"detail":"Connection lost"}', 503);
          }
          return http.Response(jsonEncode(state), 200);
        }),
      ),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'separate routes and histories; clarification keeps frozen scope',
    () async {
      await controller.loadDialogue();
      final symbolic = controller.dialogue;
      await controller.selectChatMode(CalendarChatMode.llmOnly);
      expect(controller.canToggleLlm, isFalse);
      state = {'status': 'clarification', 'revision': 4, 'messages': []};
      await controller.sendChat('Find time for lunch');
      final first = jsonDecode(posts.single.body) as Map;
      expect(posts.single.url.path, '/calendar/llm-only/dialogue');
      expect(first['type'], 'message');
      expect(first['timeMin'], isNotNull);
      expect(first.containsKey('useLlm'), isFalse);
      await controller.sendChat('Thirty minutes');
      final reply = jsonDecode(posts.last.body) as Map;
      expect(reply['text'], 'Thirty minutes');
      expect(reply.containsKey('timeMin'), isFalse);
      expect(controller.canEdit, isFalse);
      final pending = controller.dialogue;
      state = {'status': 'idle', 'revision': 3, 'messages': []};
      await controller.selectChatMode(CalendarChatMode.symbolic);
      expect(controller.dialogue, symbolic);
      expect(controller.otherChatPending, isTrue);
      expect(controller.canChat, isFalse);
      expect(controller.canEdit, isFalse);
      expect(controller.canNavigate, isFalse);
      state = pending!;
      await controller.selectChatMode(CalendarChatMode.llmOnly);
      expect(controller.awaitingAnswer, isTrue);
    },
  );

  test(
    'failed POST cannot be repeated until explicit status refresh',
    () async {
      await controller.selectChatMode(CalendarChatMode.llmOnly);
      fail = true;
      expect(await controller.sendChat('Move lunch'), isFalse);
      expect(controller.statusUncertain, isTrue);
      expect(controller.canEdit, isFalse);
      await controller.sendChat('Move lunch');
      expect(posts, hasLength(1));
      fail = false;
      state = {...state, 'peerBusy': false};
      await controller.selectChatMode(CalendarChatMode.symbolic);
      expect(controller.canChat, isFalse);
      expect(controller.otherChatPending, isTrue);
      await controller.selectChatMode(CalendarChatMode.llmOnly);
      await controller.loadDialogue();
      expect(controller.statusUncertain, isFalse);
      expect(controller.canChat, isTrue);
      expect(posts, hasLength(1));
    },
  );

  testWidgets('review uses shared composer and exact approval payload', (
    tester,
  ) async {
    state = {
      'status': 'review',
      'revision': 8,
      'messages': [],
      'review': {
        'id': 'proposal-1',
        'operations': [
          {
            'tool': 'create-event',
            'arguments': {'summary': 'Lunch'},
          },
        ],
      },
    };
    await controller.selectChatMode(CalendarChatMode.llmOnly);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarChatPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-llm-only-entry')),
      findsOneWidget,
    );
    expect(find.text('Title: Lunch'), findsOneWidget);
    expect(posts, isEmpty);
    state = {'status': 'answered', 'revision': 9, 'messages': []};
    final reads = eventReads;
    await tester.tap(find.text('Accept changes'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posts.single.body), {
      'type': 'accept',
      'proposalId': 'proposal-1',
      'revision': 8,
    });
    expect(eventReads, greaterThan(reads));
    expect(controller.canEdit, isTrue);
  });

  testWidgets('recovery requires reconciliation before remaining writes', (
    tester,
  ) async {
    state = {
      'status': 'recovery',
      'revision': 4,
      'messages': [],
      'journal': [],
      'canContinue': false,
    };
    await controller.selectChatMode(CalendarChatMode.llmOnly);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarChatPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final authorize = find.widgetWithText(
      TextButton,
      'Authorize remaining writes',
    );
    expect(tester.widget<TextButton>(authorize).onPressed, isNull);
    state = {...state, 'canContinue': true};
    await tester.tap(find.text('Reconcile (read only)'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posts.single.body)['type'], 'reconcile');
    expect(tester.widget<TextButton>(authorize).onPressed, isNotNull);
    expect(controller.canEdit, isFalse);
  });
}
