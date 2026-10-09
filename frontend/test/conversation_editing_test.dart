import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/object_property.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/storage/conversation_id_store.dart';
import 'package:logic_chatbot/widgets/conversation_world_panel.dart';
import 'package:logic_chatbot/widgets/world_display.dart';
import 'package:logic_chatbot/widgets/world_widget.dart';

class SavedId implements ConversationIdStore {
  @override
  Future<String?> read() async => 'saved';
  @override
  Future<void> write(String id) async {}
}

Map<String, dynamic> fixture({String? feedback, bool canUndo = false}) => {
  'conversationId': 'saved',
  'world': jsonDecode(
    File('../backend/shared/toy_world.json').readAsStringSync(),
  ),
  'canUndo': canUndo,
  'feedback': ?feedback,
};

http.Response reply(Map<String, dynamic> state) =>
    http.Response(jsonEncode(state), 200);

ConversationController controller(MockClient client, {bool canUndo = false}) =>
    ConversationController(
      api: ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000/api'),
        client: client,
      ),
      store: SavedId(),
    )..conversation = ConversationState.fromJson(fixture(canUndo: canUndo));

void main() {
  test('all editing calls use the API contract and parse feedback', () async {
    final requests = <http.Request>[];
    final api = ConversationApi(
      baseUrl: Uri.parse('http://localhost:8000/api'),
      client: MockClient((request) async {
        requests.add(request);
        return reply(fixture(feedback: 'No change'));
      }),
    );
    addTearDown(api.close);
    for (final property in ObjectProperty.values) {
      expect(
        (await api.applyProperty(
          'saved',
          const BoardPosition(2, 3),
          property,
        )).feedback,
        'No change',
      );
      expect(jsonDecode(requests.last.body), {
        'position': {'x': 2, 'y': 3},
        'property': property.name,
      });
      expect(requests.last.headers['content-type'], 'application/json');
      expect(requests.last.url.path, '/api/conversations/saved/property');
    }
    await api.place('saved', 5, const BoardPosition(0, 0));
    expect(jsonDecode(requests.last.body), {
      'objectId': 5,
      'position': {'x': 0, 'y': 0},
    });
    expect(requests.last.url.path, endsWith('/place'));
    await api.erase('saved', const BoardPosition(7, 7));
    expect(jsonDecode(requests.last.body), {
      'position': {'x': 7, 'y': 7},
    });
    expect(requests.last.url.path, endsWith('/erase'));
    await api.clear('saved');
    expect(requests.last.url.path, endsWith('/clear'));
    expect(requests.last.body, isEmpty);
    await api.undo('saved');
    expect(requests.last.url.path, endsWith('/undo'));
    expect(requests.last.body, isEmpty);
    expect(requests.every((request) => request.method == 'POST'), isTrue);
  });

  test(
    'pending edits disable controls and apply only returned state',
    () async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final subject = controller(
        MockClient((request) {
          requests.add(request);
          return pending.future;
        }),
      );
      addTearDown(subject.dispose);
      final original = subject.conversation;
      subject.selectProperty(ObjectProperty.blue);
      final editing = subject.paint(1, 7);
      expect(subject.editing, isTrue);
      expect(subject.canEdit, isFalse);
      expect(subject.conversation, same(original));
      subject.selectProperty(ObjectProperty.green);
      await subject.erase(1, 7);
      await subject.load();
      expect(subject.selectedProperty, ObjectProperty.blue);
      final returned = fixture(feedback: '#0: red -> blue', canUndo: true);
      returned['world']['objects'][0]['color'] = 'blue';
      pending.complete(reply(returned));
      await editing;
      expect(requests.length, 1);
      expect(subject.conversation!.world.objects.first.color, ObjectColor.blue);
      expect(subject.conversation!.canUndo, isTrue);
      expect(subject.canEdit, isTrue);
    },
  );

  test(
    'blocked placement retains selection and successful placement clears it',
    () async {
      var blocked = true;
      final subject = controller(
        MockClient((request) async {
          expect(request.url.path, endsWith('/place'));
          expect(jsonDecode(request.body)['objectId'], 5);
          final returned = fixture(
            feedback: blocked ? 'B8 occupied' : '#5: none -> on A1',
            canUndo: !blocked,
          );
          if (!blocked) {
            returned['world']['objects'][5]['position'] = {'x': 0, 'y': 0};
          }
          return reply(returned);
        }),
      );
      addTearDown(subject.dispose);
      subject.selectUnplacedObject(0);
      expect(subject.selectedUnplacedObjectId, isNull);
      subject.selectUnplacedObject(5);
      await subject.paint(1, 7);
      expect(subject.selectedUnplacedObjectId, 5);
      blocked = false;
      await subject.paint(0, 0);
      expect(subject.selectedUnplacedObjectId, isNull);
      expect(
        subject.conversation!.world.objects[5].position,
        const BoardPosition(0, 0),
      );
      subject.selectUnplacedObject(6);
      subject.selectProperty(ObjectProperty.red);
      expect(subject.selectedUnplacedObjectId, isNull);
    },
  );

  test('clear and undo clear selection and respect server canUndo', () async {
    final actions = <String>[];
    final subject = controller(
      MockClient((request) async {
        actions.add(request.url.pathSegments.last);
        return reply(fixture(feedback: 'No change', canUndo: true));
      }),
    );
    addTearDown(subject.dispose);
    await subject.undo();
    expect(actions, isEmpty);
    subject.selectUnplacedObject(5);
    await subject.clear();
    expect(subject.selectedUnplacedObjectId, isNull);
    subject.selectUnplacedObject(5);
    await subject.undo();
    expect(subject.selectedUnplacedObjectId, isNull);
    expect(actions, ['clear', 'undo']);
  });

  test(
    'failed edit preserves world; recovery fetches state without replaying mutation',
    () async {
      final methods = <String>[];
      final subject = controller(
        MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'POST') throw http.ClientException('offline');
          final returned = fixture(canUndo: true);
          returned['world']['objects'] = [];
          return reply(returned);
        }),
      );
      addTearDown(subject.dispose);
      final original = subject.conversation;
      subject.selectUnplacedObject(5);
      await subject.paint(0, 0);
      expect(subject.conversation, same(original));
      expect(subject.selectedUnplacedObjectId, 5);
      expect(subject.error, isNotNull);
      await subject.clear();
      expect(methods, ['POST']);
      await subject.load();
      expect(methods, ['POST', 'GET']);
      expect(subject.conversation!.world.objects, isEmpty);
      expect(subject.selectedUnplacedObjectId, isNull);
      expect(subject.canEdit, isTrue);
    },
  );

  test(
    'edit rejects missing feedback and ignores completion after disposal',
    () async {
      final invalid = ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((_) async => reply(fixture())),
      );
      addTearDown(invalid.close);
      await expectLater(invalid.clear('saved'), throwsA(isA<ApiException>()));
      final pending = Completer<http.Response>();
      final subject = controller(MockClient((_) => pending.future));
      final original = subject.conversation;
      final editing = subject.clear();
      subject.dispose();
      pending.complete(reply(fixture(feedback: 'World cleared')));
      await editing;
      expect(subject.conversation, same(original));
    },
  );

  testWidgets(
    'board gestures send coordinates, pending state disables controls, failure keeps board',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final subject = controller(
        MockClient((request) {
          requests.add(request);
          return pending.future;
        }),
      );
      addTearDown(subject.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: subject,
              builder: (context, child) => ConversationWorldPanel(
                conversation: subject.conversation,
                loading: subject.loading,
                editing: subject.editing,
                error: subject.error,
                onRetry: subject.load,
                selectedProperty: subject.selectedProperty,
                selectedUnplacedObjectId: subject.selectedUnplacedObjectId,
                onPropertyChanged: subject.selectProperty,
                onUnplacedObjectSelected: subject.selectUnplacedObject,
                onPaint: subject.paint,
                onErase: subject.erase,
                onClear: subject.clear,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('blue'));
      await tester.pump();
      final board = find
          .descendant(
            of: find.byType(WorldWidget),
            matching: find.byType(GestureDetector),
          )
          .first;
      final origin = tester.getTopLeft(board);
      final cell = tester.getSize(board).width / 8;
      await tester.tapAt(origin + Offset(cell / 2, cell * 7.5));
      await tester.pump();
      expect(jsonDecode(requests.single.body), {
        'position': {'x': 0, 'y': 0},
        'property': 'blue',
      });
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester.widget<WorldDisplay>(find.byType(WorldDisplay)).onPaint,
        isNull,
      );
      pending.complete(http.Response('', 503));
      await tester.pumpAndSettle();
      expect(find.byType(WorldWidget), findsOneWidget);
      expect(find.text('Refresh world'), findsOneWidget);
      expect(
        tester.widget<WorldDisplay>(find.byType(WorldDisplay)).onClear,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
