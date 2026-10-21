import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/models/world_slot.dart';
import 'package:logic_chatbot/storage/conversation_id_store.dart';
import 'package:logic_chatbot/widgets/world_slots.dart';

class _SavedIdStore implements ConversationIdStore {
  @override
  Future<String?> read({WorldDomain domain = WorldDomain.objects}) async =>
      'saved';

  @override
  Future<void> write(
    String id, {
    WorldDomain domain = WorldDomain.objects,
  }) async {}
}

Map<String, dynamic> _state({bool saved = false, bool loaded = false}) => {
  'domain': 'objects',
  'conversationId': 'saved',
  'world': {
    'width': 8,
    'height': 8,
    'objects': loaded
        ? []
        : [
            {'id': 3, 'attributes': <String, String>{}, 'position': null},
          ],
  },
  'canUndo': loaded,
  'feedback': loaded ? 'Loaded slot 2' : 'Saved slot 2',
  'worldSlots': [
    for (var slot = 1; slot <= 5; slot++)
      {
        'slot': slot,
        'savedAt': saved && slot == 2 ? '2026-10-19T09:00:00Z' : null,
      },
  ],
};

void main() {
  test(
    'slot requests use server state, preserve saves and clear loaded selection',
    () async {
      final requests = <http.Request>[];
      final controller = ConversationController(
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000/api'),
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(
                _state(saved: true, loaded: request.url.path.endsWith('/load')),
              ),
              200,
            );
          }),
        ),
        store: _SavedIdStore(),
      )..conversation = ConversationState.fromJson(_state());
      addTearDown(controller.dispose);
      controller.selectUnplacedObject(3);
      expect(await controller.saveWorldSlot(2), isTrue);
      expect(requests.last.url.path, '/api/conversations/saved/slots/2/save');
      expect(jsonDecode(requests.last.body), {'overwrite': false});
      expect(controller.conversation!.worldSlots[1].isSaved, isTrue);
      expect(controller.conversation!.canUndo, isFalse);
      expect(controller.selectedUnplacedObjectId, 3);
      await controller.saveWorldSlot(2, overwrite: true);
      expect(jsonDecode(requests.last.body), {'overwrite': true});
      expect(await controller.loadWorldSlot(2), isTrue);
      expect(requests.last.url.path, '/api/conversations/saved/slots/2/load');
      expect(requests.last.body, isEmpty);
      expect(controller.conversation!.objectWorld!.objects, isEmpty);
      expect(controller.conversation!.canUndo, isTrue);
      expect(controller.selectedUnplacedObjectId, isNull);
      controller.conversation = ConversationState.fromJson({
        ..._state(),
        'pending': {'sentence': 'Which object?', 'candidates': []},
      });
      expect(await controller.saveWorldSlot(2), isFalse);
      expect(await controller.loadWorldSlot(2), isFalse);
      expect(requests.length, 3);
    },
  );

  testWidgets('five compact slots disable empty loads and confirm overwrites', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final saves = <(int, bool)>[];
    final loads = <int>[];
    var slots = <WorldSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) => WorldSlots(
                  slots: slots,
                  onSave: (slot, overwrite) async {
                    saves.add((slot, overwrite));
                    setState(
                      () => slots = [WorldSlot(slot: slot, savedAt: 'now')],
                    );
                    return true;
                  },
                  onLoad: (slot) async {
                    loads.add(slot);
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    IconButton load(int slot) =>
        tester.widget<IconButton>(find.byKey(ValueKey('load-slot-$slot')));
    final initialSize = tester.getSize(find.byType(WorldSlots));
    for (var slot = 1; slot <= 5; slot++) {
      expect(find.byKey(ValueKey('save-slot-$slot')), findsOneWidget);
      expect(load(slot).onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('save-slot-2')));
    await tester.pumpAndSettle();
    expect(saves, [(2, false)]);
    expect(load(2).onPressed, isNotNull);
    expect(tester.getSize(find.byType(WorldSlots)), initialSize);
    await tester.tap(find.byKey(const ValueKey('load-slot-2')));
    await tester.pumpAndSettle();
    expect(loads, [2]);
    await tester.tap(find.byKey(const ValueKey('save-slot-2')));
    await tester.pumpAndSettle();
    expect(find.text('Overwrite slot 2?'), findsOneWidget);
    expect(saves.length, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saves.length, 1);
    await tester.tap(find.byKey(const ValueKey('save-slot-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overwrite'));
    await tester.pumpAndSettle();
    expect(saves, [(2, false), (2, true)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled controls cannot save a provisional world', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorldSlots(slots: [WorldSlot(slot: 1, savedAt: 'now')]),
        ),
      ),
    );
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
  });
}
