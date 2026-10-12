import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/models/network_shape.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/storage/conversation_id_store.dart';
import 'package:logic_chatbot/widgets/network_selector.dart';
import 'package:logic_chatbot/widgets/network_glyph.dart';
import 'package:logic_chatbot/main.dart';

class DomainStore implements ConversationIdStore {
  final ids = <WorldDomain, String>{};
  @override
  Future<String?> read({WorldDomain domain = WorldDomain.objects}) async =>
      ids[domain];
  @override
  Future<void> write(
    String id, {
    WorldDomain domain = WorldDomain.objects,
  }) async {
    ids[domain] = id;
  }
}

Map<String, dynamic> state(WorldDomain domain) => {
  'conversationId': domain.name,
  'domain': domain.name,
  'canUndo': false,
  'world': jsonDecode(
    File(
      '../backend/shared/${domain == WorldDomain.objects ? 'toy_world' : 'network_world'}.json',
    ).readAsStringSync(),
  ),
};

void main() {
  test(
    'domain IDs persist separately, shapes replace ports, colors cancel shapes',
    () async {
      final store = DomainStore();
      final calls = <http.Request>[];
      final controller = ConversationController(
        store: store,
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            calls.add(request);
            final creating = request.url.path == '/conversations';
            final domain = creating
                ? WorldDomain.values.byName(jsonDecode(request.body)['domain'])
                : WorldDomain.values.byName(request.url.pathSegments[1]);
            return http.Response(
              jsonEncode({
                ...state(domain),
                if (!creating) 'feedback': 'No change',
              }),
              creating ? 201 : 200,
            );
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.switchDomain(WorldDomain.network);
      expect(store.ids, {
        WorldDomain.objects: 'objects',
        WorldDomain.network: 'network',
      });
      controller.selectNetworkShape(NetworkShape.northEast);
      await controller.paint(2, 3);
      expect(jsonDecode(calls.last.body), {
        'position': {'x': 2, 'y': 3},
        'ports': ['north', 'east'],
      });
      controller.selectNetworkColor(ObjectColor.yellow);
      await controller.paint(2, 3);
      expect(jsonDecode(calls.last.body)['property'], {
        'attribute': 'color',
        'value': 'yellow',
      });
      await controller.switchDomain(WorldDomain.objects);
      expect(calls.last.method, 'GET');
      expect(controller.conversation!.domain, WorldDomain.objects);
      await controller.switchDomain(WorldDomain.network);
      expect(calls.where((r) => r.url.path == '/conversations'), hasLength(2));
    },
  );

  test('all 16 independent patterns map to distinct assets', () {
    expect(
      NetworkShape.values.map((s) => s.mask).toSet(),
      Set.from(List.generate(16, (i) => i)),
    );
    expect(NetworkShape.northEast.assetName, 'ne');
    expect(NetworkShape.southWest.assetName, 'sw');
    for (final shape in NetworkShape.values) {
      expect(
        File(
          'assets/images/network_shapes/${shape.assetName}.svg',
        ).existsSync(),
        isTrue,
      );
    }
  });

  testWidgets(
    'twenty selector buttons wrap at mobile width and all SVGs render',
    (tester) async {
      tester.view.physicalSize = const Size(280, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      NetworkShape? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkSelector(
              selectedShape: NetworkShape.empty,
              selectedColor: null,
              onShapeChanged: (shape) => selected = shape,
              onColorChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(20));
      expect(find.byType(NetworkGlyph), findsNWidgets(16));
      await tester.tap(find.byKey(const ValueKey('network-shape-nesw')));
      expect(selected, NetworkShape.all);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('app bar switches domains without overflowing on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ConversationController(
      store: DomainStore(),
      api: ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          final domain = WorldDomain.values.byName(
            jsonDecode(request.body)['domain'],
          );
          return http.Response(jsonEncode(state(domain)), 201);
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(controller.conversation!.domain, WorldDomain.network);
    expect(find.byType(NetworkSelector), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
