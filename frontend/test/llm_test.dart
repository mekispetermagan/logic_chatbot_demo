import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/models/chat_message.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/storage/conversation_id_store.dart';
import 'package:logic_chatbot/widgets/chat_panel.dart';

class SavedConversation implements ConversationIdStore {
  @override
  Future<String?> read({WorldDomain domain = WorldDomain.objects}) async =>
      'saved';
  @override
  Future<void> write(
    String id, {
    WorldDomain domain = WorldDomain.objects,
  }) async {}
}

Map<String, dynamic> state({bool translated = false}) => {
  'conversationId': 'saved',
  'domain': 'objects',
  'canUndo': translated,
  'world': {'width': 8, 'height': 8, 'objects': []},
  'llmBudget': {
    'limitUsd': 1,
    'spentUsd': translated ? 0.0001095 : 0,
    'reservedUsd': 0,
    'remainingUsd': translated ? 0.9998905 : 1,
    'requestCount': translated ? 1 : 0,
  },
  'messages': translated
      ? [
          {'role': 'user', 'text': 'paint A1 red'},
          {
            'role': 'machine',
            'text': 'Interpreted as: A1 red.\n\nA1 is red.\n  Created #0',
            'llm': {
              'status': 'translated',
              'model': 'gpt-6-luna',
              'costUsd': 0.0001095,
              'reservedUsd': 0,
              'inputTokens': 1000,
              'outputTokens': 50,
            },
          },
        ]
      : [],
  if (translated) 'feedback': 'Interpreted as: A1 red.',
};

void main() {
  test(
    'each chat request carries the current opt-in flag, initially false',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final controller = ConversationController(
        store: SavedConversation(),
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            final chat = request.url.path.endsWith('/chat');
            if (chat) {
              bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            }
            return http.Response(jsonEncode(state(translated: chat)), 200);
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.useLlm, isFalse);
      await controller.sendChat('A1 red.');
      controller.setUseLlm(true);
      await controller.sendChat('paint A1 red');
      controller.setUseLlm(false);
      await controller.sendChat('A1 blue.');
      expect(bodies.map((body) => body['useLlm']), [false, true, false]);
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets('LLM switch and cost reporting fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ConversationController(
        store: SavedConversation(),
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            final chat = request.url.path.endsWith('/chat');
            if (chat) expect(jsonDecode(request.body)['useLlm'], isTrue);
            return http.Response(jsonEncode(state(translated: chat)), 200);
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: DemoScreen(createController: () => controller)),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(controller.useLlm, isTrue);
      if (width < 900) {
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'paint A1 red');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('LLM cost: \$0.000110'), findsOneWidget);
      expect(find.text('LLM: \$0.000110 / \$1.00'), findsOneWidget);
      expect(find.textContaining('Interpreted as:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uncertain charges are shown as reserved rather than free', (
    tester,
  ) async {
    final message = ChatMessage.fromJson({
      'role': 'machine',
      'text': 'LLM unavailable',
      'isError': true,
      'llm': {
        'status': 'unavailable',
        'model': 'gpt-6-luna',
        'costUsd': null,
        'reservedUsd': 0.0035,
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatBubble(message: message)),
      ),
    );
    expect(find.text('LLM cost unknown · \$0.003500 reserved'), findsOneWidget);
  });

  testWidgets('courtesy displays as chat without a proposal or world change', (
    tester,
  ) async {
    final controller = ConversationController(
      store: SavedConversation(),
      api: ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          final value = state();
          if (request.url.path.endsWith('/chat')) {
            expect(jsonDecode(request.body), {'text': 'Hello', 'useLlm': true});
            value['feedback'] = 'Hello!';
            value['proposal'] = null;
            value['messages'] = [
              {'role': 'user', 'text': 'Hello'},
              {
                'role': 'machine',
                'text': 'Hello!',
                'llm': {
                  'status': 'conversation',
                  'model': 'gpt-6-luna',
                  'costUsd': .0001,
                },
              },
            ];
          }
          return http.Response(jsonEncode(value), 200);
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('Review interpretation'), findsNothing);
    expect(find.text('Accept'), findsNothing);
    expect(controller.conversation!.world.objects, isEmpty);
    expect(controller.conversation!.canUndo, isFalse);
    expect(controller.canEdit, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
