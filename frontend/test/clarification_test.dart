import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/widgets/chat_panel.dart';
import 'conversation_editing_test.dart' show SavedId;

Map<String, dynamic> pausedState() => {
  'conversationId': 'saved',
  'world': {'width': 8, 'height': 8, 'objects': []},
  'canUndo': true,
  'pending': {
    'sentence': 'the cube is red.',
    'candidates': [
      {'objectId': 0, 'label': '#0: blue medium cube on A1'},
      {'objectId': 1, 'label': '#1: green small cube on B1'},
    ],
  },
  'messages': [],
};

void main() {
  test(
    'pending entry blocks ordinary edits but permits clarification and undo',
    () async {
      final requests = <http.Request>[];
      final controller = ConversationController(
        store: SavedId(),
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            requests.add(request);
            final result = pausedState()..['feedback'] = 'Undone';
            result['pending'] = null;
            return http.Response(jsonEncode(result), 200);
          }),
        ),
      )..conversation = ConversationState.fromJson(pausedState());
      addTearDown(controller.dispose);
      expect(controller.canEdit, isFalse);
      expect(controller.canRequest, isTrue);
      await controller.clear();
      expect(await controller.sendChat('It is blue.'), isFalse);
      expect(requests, isEmpty);
      expect(await controller.clarify(1), isTrue);
      expect(requests.single.url.path, '/conversations/saved/clarify');
      expect(jsonDecode(requests.single.body), {'objectId': 1});
      expect(controller.canEdit, isTrue);
      controller.conversation = ConversationState.fromJson(pausedState());
      await controller.undo();
      expect(requests.last.url.path, '/conversations/saved/undo');
      expect(controller.conversation!.pending, isNull);
    },
  );

  testWidgets(
    'clarification choices disable composer and emit selected identifier',
    (tester) async {
      int? selected;
      final pending = ConversationState.fromJson(pausedState()).pending!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanel(
              messages: const [],
              canSend: false,
              sending: false,
              pending: pending,
              onChoose: (id) => selected = id,
              onSend: (_) async => false,
              onRefresh: () {},
            ),
          ),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('Which object? the cube is red.'), findsOneWidget);
      await tester.tap(find.text('#1: green small cube on B1'));
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'one app bar Undo is available from the mobile Chat tab during clarification',
    (tester) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DemoScreen(
            createController: () => ConversationController(
              store: SavedId(),
              api: ConversationApi(
                baseUrl: Uri.parse('http://localhost:8000'),
                client: MockClient((request) async {
                  requests.add(request);
                  final result = pausedState();
                  if (request.url.path.endsWith('/undo')) {
                    result['pending'] = null;
                    result['canUndo'] = false;
                    result['feedback'] = 'Undone';
                  }
                  return http.Response(jsonEncode(result), 200);
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Undo'), findsOneWidget);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('Which object? the cube is red.'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(requests.last.url.path, '/conversations/saved/undo');
      expect(find.text('Which object? the cube is red.'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Undo',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
