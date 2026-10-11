import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  testWidgets('arrows recall user entries and restore the editable draft', (
    tester,
  ) async {
    final messages = <ChatMessage>[
      const ChatMessage(role: ChatRole.user, text: 'first prompt'),
      const ChatMessage(role: ChatRole.machine, text: 'first answer'),
      const ChatMessage(role: ChatRole.user, text: 'typo prompt'),
      const ChatMessage(
        role: ChatRole.machine,
        text: 'parse error',
        isError: true,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ChatPanel(
              messages: messages,
              canSend: true,
              sending: false,
              onRefresh: () {},
              onSend: (text) async {
                update(
                  () => messages.add(
                    ChatMessage(role: ChatRole.user, text: text),
                  ),
                );
                return true;
              },
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    final composer = tester.widget<TextField>(field).controller!;
    Future<void> arrow(LogicalKeyboardKey key) async {
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    await tester.enterText(field, 'unfinished draft');
    final draft = composer.value;
    await arrow(LogicalKeyboardKey.arrowUp);
    expect(composer.text, 'typo prompt');
    await tester.enterText(field, 'corrected prompt');
    await arrow(LogicalKeyboardKey.arrowUp);
    expect(composer.text, 'first prompt');
    await arrow(LogicalKeyboardKey.arrowUp);
    expect(composer.text, 'first prompt');
    await arrow(LogicalKeyboardKey.arrowDown);
    expect(composer.text, 'typo prompt');
    await arrow(LogicalKeyboardKey.arrowDown);
    expect(composer.value, draft);
    await tester.enterText(field, '');
    await arrow(LogicalKeyboardKey.arrowUp);
    await arrow(LogicalKeyboardKey.arrowDown);
    expect(composer.text, isEmpty);
    await arrow(LogicalKeyboardKey.arrowUp);
    await tester.enterText(field, 'corrected prompt');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(composer.text, isEmpty);
    expect(messages.last.text, 'corrected prompt');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await arrow(LogicalKeyboardKey.arrowUp);
    expect(composer.text, 'corrected prompt');
    expect(messages[2].text, 'typo prompt');
  });

  testWidgets(
    'history arrows respect multiline cursor movement and modifiers',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanel(
              messages: const [
                ChatMessage(role: ChatRole.user, text: 'previous'),
              ],
              canSend: true,
              sending: false,
              onRefresh: () {},
              onSend: (_) async => true,
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.enterText(field, 'first line\nsecond line\nthird line');
      final composer = tester.widget<TextField>(field).controller!;
      composer.selection = const TextSelection.collapsed(offset: 15);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(composer.text, 'first line\nsecond line\nthird line');
      expect(composer.selection.extentOffset, lessThan(15));
      composer.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(composer.selection.extentOffset, greaterThan(4));
      composer.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(composer.text, 'first line\nsecond line\nthird line');
      composer.selection = const TextSelection.collapsed(offset: 4);
      final draft = composer.value;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(composer.text, 'previous');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(composer.value, draft);
    },
  );

  testWidgets(
    'Enter submits, Shift+Enter inserts a newline, and mobile Send submits',
    (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanel(
              messages: const [],
              canSend: true,
              sending: false,
              onRefresh: () {},
              onSend: (text) async {
                submitted.add(text);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '#0 red.');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(submitted, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '#0 red.\n',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(submitted, ['#0 red.\n']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '#0 red?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(submitted, ['#0 red.\n', '#0 red?']);
    },
  );
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
