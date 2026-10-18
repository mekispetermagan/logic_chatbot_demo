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
  'domain': 'objects',
  'conversationId': 'saved',
  'world': {'width': 8, 'height': 8, 'objects': []},
  'canUndo': true,
  'pending': {
    'sentence': 'the bloom is red.',
    'candidates': [
      {'objectId': 0, 'label': '#0: blue medium bloom on A1'},
      {'objectId': 1, 'label': '#1: green small bloom on B1'},
    ],
  },
  'messages': [],
};

void main() {
  for (final selectSquare in [true, false]) {
    testWidgets(
      'mixed referent choice submits its type: square=$selectSquare',
      (tester) async {
        final requests = <http.Request>[];
        final state = pausedState();
        state['pending'] = {
          'sentence': 'Does it satisfy at the edge?',
          'candidates': [
            {'objectId': 0, 'label': '#0: red on A1'},
          ],
          'squareChoices': [
            {'x': 0, 'y': 0},
          ],
        };
        final controller = ConversationController(
          store: SavedId(),
          api: ConversationApi(
            baseUrl: Uri.parse('http://localhost:8000'),
            client: MockClient((request) async {
              requests.add(request);
              if (request.method == 'POST') state['pending'] = null;
              return http.Response(
                jsonEncode({...state, 'feedback': 'Resolved'}),
                200,
              );
            }),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(home: DemoScreen(createController: () => controller)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Which referent: object or square?'),
          findsOneWidget,
        );
        expect(find.text('Square A1'), findsOneWidget);
        expect(find.text('Object #0: red on A1'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        await tester.tap(
          find.text(selectSquare ? 'Square A1' : 'Object #0: red on A1'),
        );
        await tester.pumpAndSettle();
        final request = requests.last;
        expect(request.url.path, '/conversations/saved/clarify');
        expect(
          jsonDecode(request.body),
          selectSquare
              ? {
                  'position': {'x': 0, 'y': 0},
                }
              : {'objectId': 0},
        );
        expect(controller.conversation!.pending, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('grouping choices retain parentheses and submit a grouping ID', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final state = pausedState();
    const first =
        'does #0 satisfy color is red or (size is large and shape is bloom)?';
    const second =
        'does #0 satisfy (color is red or size is large) and shape is bloom?';
    state['pending'] = {
      'sentence':
          'Does #0 satisfy color is red or size is large and shape is bloom?',
      'candidates': [],
      'groupingChoices': [
        {'groupingId': 1, 'label': first},
        {'groupingId': 2, 'label': second},
      ],
    };
    final controller = ConversationController(
      store: SavedId(),
      api: ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({...state, 'pending': null, 'feedback': 'Resolved'}),
            200,
          );
        }),
      ),
    )..conversation = ConversationState.fromJson(state);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            messages: const [],
            canSend: false,
            sending: false,
            pending: controller.conversation!.pending,
            onChooseGrouping: controller.clarifyGrouping,
            onSend: (_) async => false,
            onRefresh: () {},
          ),
        ),
      ),
    );
    expect(find.text(first), findsOneWidget);
    expect(find.text(second), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(controller.canEdit, isFalse);
    await tester.tap(find.text(second));
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/conversations/saved/clarify');
    expect(jsonDecode(requests.single.body), {'groupingId': 2});
    expect(controller.conversation!.pending, isNull);
    expect(tester.takeException(), isNull);
  });

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
      expect(find.text('Which object? the bloom is red.'), findsOneWidget);
      await tester.tap(find.text('#1: green small bloom on B1'));
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'square choices render labels and submit coordinates through the controller',
    (tester) async {
      final requests = <http.Request>[];
      final state = pausedState();
      state['pending'] = {
        'sentence': 'move #0 next to #1.',
        'candidates': [],
        'squareChoices': [
          {'x': 3, 'y': 4},
          {'x': 4, 'y': 3},
        ],
      };
      final controller = ConversationController(
        store: SavedId(),
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({...state, 'pending': null, 'feedback': 'Moved'}),
              200,
            );
          }),
        ),
      )..conversation = ConversationState.fromJson(state);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanel(
              messages: const [],
              canSend: false,
              sending: false,
              pending: controller.conversation!.pending,
              onChooseSquare: controller.clarifySquare,
              onSend: (_) async => false,
              onRefresh: () {},
            ),
          ),
        ),
      );
      expect(find.text('Which square? move #0 next to #1.'), findsOneWidget);
      expect(find.text('D5'), findsOneWidget);
      expect(find.text('E4'), findsOneWidget);
      await tester.tap(find.text('D5'));
      await tester.pumpAndSettle();
      expect(requests.single.url.path, '/conversations/saved/clarify');
      expect(jsonDecode(requests.single.body), {
        'position': {'x': 3, 'y': 4},
      });
      expect(controller.conversation!.pending, isNull);
      expect(controller.canEdit, isTrue);
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
      expect(find.text('Which object? the bloom is red.'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(requests.last.url.path, '/conversations/saved/undo');
      expect(find.text('Which object? the bloom is red.'), findsNothing);
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
