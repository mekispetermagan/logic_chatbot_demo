import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/models/chat_message.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/widgets/chat_panel.dart';
import 'conversation_editing_test.dart' show SavedId;

Map<String, dynamic> state({bool history = false}) => {
  'conversationId': 'saved',
  'world': {'width': 8, 'height': 8, 'objects': []},
  'canUndo': false,
  'messages': history
      ? [
          {'role': 'user', 'text': '#0 red?', 'isError': false},
          {'role': 'machine', 'text': '#0 red?\n  true', 'isError': false},
        ]
      : [],
  'feedback': '#0 red?\n  true',
};

void main() {
  test(
    'chat sends text once, blocks edits, and accepts persisted history',
    () async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final subject = ConversationController(
        store: SavedId(),
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) {
            requests.add(request);
            return pending.future;
          }),
        ),
      )..conversation = ConversationState.fromJson(state());
      addTearDown(subject.dispose);
      expect(await subject.sendChat(' \n '), isFalse);
      final sending = subject.sendChat('#0 red?');
      expect(subject.sendingChat, isTrue);
      expect(subject.canEdit, isFalse);
      expect(await subject.sendChat('#0 blue?'), isFalse);
    await subject.clear();
    await Future<void>.delayed(Duration.zero);
      expect(requests.single.url.path, '/conversations/saved/chat');
      expect(jsonDecode(requests.single.body), {'text': '#0 red?'});
      pending.complete(http.Response(jsonEncode(state(history: true)), 200));
      expect(await sending, isTrue);
      expect(subject.conversation!.messages.length, 2);
      expect(subject.sendingChat, isFalse);
      expect(subject.canEdit, isTrue);
    },
  );

  testWidgets(
    'bubble colors distinguish roles and feedback preserves line breaks',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
          ),
          home: Scaffold(
            body: ChatPanel(
              messages: const [
                ChatMessage(role: ChatRole.user, text: '#0 red?'),
                ChatMessage(role: ChatRole.machine, text: '#0 red?\n  true'),
              ],
              canSend: true,
              sending: false,
              onSend: (_) async => true,
              onRefresh: () {},
            ),
          ),
        ),
      );
      final colors = Theme.of(
        tester.element(find.byType(ChatPanel)),
      ).colorScheme;
      final backgrounds = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) => container.decoration is BoxDecoration)
          .map((container) => (container.decoration as BoxDecoration).color);
      expect(
        backgrounds,
        containsAll([colors.primaryContainer, colors.secondaryContainer]),
      );
      expect(find.text('#0 red?\n  true'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composer clears accepted entries, retains failed drafts, and disables duplicate send',
    (tester) async {
      var accepted = false;
      var calls = 0;
      final pending = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanel(
              messages: const [],
              canSend: true,
              sending: false,
              onRefresh: () {},
              onSend: (_) {
                calls++;
                return calls == 1 ? pending.future : Future.value(accepted);
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '#0 red.');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '#0 red.',
      );
      accepted = true;
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
}
