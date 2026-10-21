import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/storage/conversation_id_store.dart';

class _IdStore implements ConversationIdStore {
  String id = 'old';
  bool failWrite = false;

  @override
  Future<String?> read({WorldDomain domain = WorldDomain.objects}) async => id;

  @override
  Future<void> write(
    String value, {
    WorldDomain domain = WorldDomain.objects,
  }) async {
    if (failWrite) throw StateError('Device storage unavailable');
    id = value;
  }
}

Map<String, dynamic> _state({bool reset = false, bool pending = false}) => {
  'conversationId': reset ? 'new' : 'old',
  'domain': 'objects',
  'languageVersion': 'objects-v2',
  'resetFrom': reset ? 'old' : null,
  'resetPending': pending,
  'world': {
    'width': 8,
    'height': 8,
    'objects': reset
        ? []
        : [
            {
              'id': 0,
              'attributes': {'color': 'red'},
              'position': null,
            },
          ],
  },
  'canUndo': !reset,
  'messages': [
    if (!reset) {'role': 'user', 'text': 'old prompt'},
    {
      'role': 'machine',
      'text': reset
          ? 'Conversation reset. New conversation started.'
          : 'Reply yes or no.',
    },
  ],
  'feedback': reset ? 'Conversation reset.' : 'Reply yes or no.',
  'worldSlots': [
    {'slot': 1, 'savedAt': '2026-10-19T12:00:00Z'},
  ],
};

void main() {
  test(
    'API requires explicit reset handover for a changed conversation ID',
    () async {
      for (final source in [null, 'wrong', 'old']) {
        final payload = {..._state(reset: true), 'resetFrom': source};
        final api = ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient(
            (_) async => http.Response(jsonEncode(payload), 200),
          ),
        );
        if (source == 'old') {
          expect((await api.get('old')).id, 'new');
          expect((await api.chat('old', 'yes')).id, 'new');
          await expectLater(api.clear('old'), throwsA(isA<ApiException>()));
        } else {
          await expectLater(api.get('old'), throwsA(isA<ApiException>()));
        }
        api.close();
      }
    },
  );

  test(
    'new ID persistence failure can be retried without another reset',
    () async {
      final store = _IdStore()..failWrite = true;
      var requests = 0;
      final controller = ConversationController(
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            requests++;
            expect(request.url.path, '/conversations/old/chat');
            return http.Response(jsonEncode(_state(reset: true)), 200);
          }),
        ),
        store: store,
      )..conversation = ConversationState.fromJson(_state(pending: true));
      addTearDown(controller.dispose);
      expect(await controller.sendChat('yes'), isFalse);
      expect(controller.conversation!.id, 'new');
      expect(controller.conversation!.objectWorld!.objects, isEmpty);
      expect(controller.error, contains('Refresh'));
      store.failWrite = false;
      await controller.load();
      expect(store.id, 'new');
      expect(controller.error, isNull);
      expect(requests, 1);
    },
  );

  test('lost reset response is recovered from the old saved ID', () async {
    final store = _IdStore();
    final requests = <String>[];
    final controller = ConversationController(
      api: ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          requests.add(request.method);
          if (request.method == 'POST') {
            throw http.ClientException('Response lost');
          }
          expect(request.url.path, '/conversations/old');
          return http.Response(jsonEncode(_state(reset: true)), 200);
        }),
      ),
      store: store,
    )..conversation = ConversationState.fromJson(_state(pending: true));
    addTearDown(controller.dispose);
    expect(await controller.sendChat('yes'), isFalse);
    await controller.load();
    expect(store.id, 'new');
    expect(controller.conversation!.canUndo, isFalse);
    expect(requests, ['POST', 'GET']);
  });

  for (final review in [false, true]) {
    testWidgets(
      'chat reset bypasses ${review ? 'LLM review' : 'symbolic clarification'} and clears input history',
      (tester) async {
        final store = _IdStore();
        final requests = <String>[];
        var pendingReset = false;
        var reset = false;
        Map<String, dynamic> response() => {
          ..._state(reset: reset, pending: pendingReset),
          if (!reset && !review)
            'pending': {
              'sentence': 'Choose an object',
              'candidates': [
                {'objectId': 0, 'label': '#0: red'},
              ],
            },
          if (!reset && review)
            'proposal': {
              'id': 'proposal',
              'originalText': 'paint it',
              'languageVersion': 'objects-v2',
              'question': 'Which color?',
              'candidates': [],
            },
        };
        final controller = ConversationController(
          api: ConversationApi(
            baseUrl: Uri.parse('http://localhost:8000'),
            client: MockClient((request) async {
              requests.add(request.url.path);
              if (request.method == 'POST') {
                expect(request.url.path, '/conversations/old/chat');
                final text = (jsonDecode(request.body)['text'] as String)
                    .trim()
                    .toLowerCase();
                if (text == 'full reset') pendingReset = true;
                if (text == 'no') pendingReset = false;
                if (text == 'yes') {
                  reset = true;
                  pendingReset = false;
                }
              }
              return http.Response(jsonEncode(response()), 200);
            }),
          ),
          store: store,
        );
        await tester.pumpWidget(
          MaterialApp(home: DemoScreen(createController: () => controller)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        await tester.enterText(find.byType(TextField), 'full reset');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(controller.conversation!.resetPending, isTrue);
        expect(controller.canUndo, isFalse);
        expect(controller.canEdit, isFalse);
        expect(controller.canReview, isFalse);
        await tester.enterText(find.byType(TextField), 'no');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(controller.conversation!.resetPending, isFalse);
        expect(controller.conversation!.id, 'old');
        await tester.enterText(find.byType(TextField), 'full reset');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'yes');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(controller.conversation!.id, 'new');
        expect(store.id, 'new');
        expect(controller.conversation!.objectWorld!.objects, isEmpty);
        expect(controller.conversation!.worldSlots.single.isSaved, isTrue);
        expect(controller.canUndo, isFalse);
        expect(controller.conversation!.pending, isNull);
        expect(controller.conversation!.proposal, isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.tap(find.byType(TextField));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(
          requests.where((path) => path.contains('/interpretations/')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
