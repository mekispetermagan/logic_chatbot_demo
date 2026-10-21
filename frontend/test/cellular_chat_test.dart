import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/models/cellular_world.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/models/interpretation_proposal.dart';
import 'package:logic_chatbot/models/object_property.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/widgets/cellular_world_widget.dart';
import 'package:logic_chatbot/widgets/conversation_world_panel.dart';

import 'network_editor_test.dart' show DomainStore;

Map<String, dynamic> board({bool changed = false}) {
  final value =
      jsonDecode(
            File('../backend/shared/cellular_world.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  if (changed) value['cells'][0] = 'black';
  return value;
}

Map<String, dynamic> pending({bool staged = false}) => {
  'sentence': 'set color of it to white.',
  'candidates': [],
  'candidateIds': [],
  'squareChoices': [
    {'x': 15, 'y': 15},
  ],
  if (staged) 'stagedWorld': board(changed: true),
};
Map<String, dynamic> state({Map<String, dynamic>? clarification}) => {
  'conversationId': 'cellular',
  'domain': 'cellular',
  'languageVersion': 'cellular-v2',
  'world': board(),
  'canUndo': clarification != null,
  'pending': clarification,
  'feedback': 'Cellular response',
};

void main() {
  test(
    'cellular chat and P16 clarification use existing API and controller',
    () async {
      final requests = <http.Request>[];
      final controller =
          ConversationController(
              store: DomainStore(),
              api: ConversationApi(
                baseUrl: Uri.parse('http://localhost:8000'),
                client: MockClient((request) async {
                  requests.add(request);
                  return http.Response(
                    jsonEncode(
                      state(
                        clarification: request.url.path.endsWith('/chat')
                            ? pending()
                            : null,
                      ),
                    ),
                    200,
                  );
                }),
              ),
            )
            ..domain = WorldDomain.cellular
            ..conversation = ConversationState.fromJson(state());
      addTearDown(controller.dispose);
      controller.setUseLlm(true);
      expect(controller.canChat, isTrue);
      expect(await controller.sendChat('Paint the last cell.'), isTrue);
      expect(requests.single.url.path, '/conversations/cellular/chat');
      expect(jsonDecode(requests.single.body), {
        'text': 'Paint the last cell.',
        'useLlm': true,
      });
      expect(controller.canChat, isFalse);
      expect(controller.canStep, isFalse);
      expect(
        await controller.clarifySquare(const BoardPosition(15, 15)),
        isTrue,
      );
      expect(requests.last.url.path, '/conversations/cellular/clarify');
      expect(jsonDecode(requests.last.body), {
        'position': {'x': 15, 'y': 15},
      });
      expect(controller.conversation!.pending, isNull);
      expect(controller.canStep, isTrue);
    },
  );

  test(
    'cellular staged batches and previews retain their dense world type',
    () {
      final conversation = ConversationState.fromJson(
        state(clarification: pending(staged: true)),
      );
      expect(conversation.pending!.stagedWorld, isA<CellularWorld>());
      expect(
        (conversation.pending!.stagedWorld! as CellularWorld).colorAt(0, 0),
        CellColor.black,
      );
      final preview = InterpretationPreview.fromJson({
        'proposalId': 'proposal',
        'rank': 1,
        'world': board(changed: true),
        'feedback': 'Preview only',
        'pending': pending(staged: true),
      });
      expect(preview.cellularWorld!.colorAt(0, 0), CellColor.black);
      expect(preview.objectWorld, isNull);
      expect(preview.pending!.stagedWorld, isA<CellularWorld>());
      expect(conversation.cellularWorld!.colorAt(0, 0), CellColor.white);
    },
  );

  testWidgets(
    'cellular preview paints a provisional board without changing current state',
    (tester) async {
      final conversation = ConversationState.fromJson(state());
      final preview = CellularWorld.fromJson(board(changed: true));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationWorldPanel(
              conversation: conversation,
              previewWorld: preview,
              loading: false,
              error: null,
              onRetry: () {},
              selectedProperty: ObjectProperty.red,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CellularWorldWidget>(find.byType(CellularWorldWidget))
            .world
            .colorAt(0, 0),
        CellColor.black,
      );
      expect(find.text('Preview — not applied'), findsOneWidget);
      expect(conversation.cellularWorld!.colorAt(0, 0), CellColor.white);
      expect(tester.takeException(), isNull);
    },
  );
}
