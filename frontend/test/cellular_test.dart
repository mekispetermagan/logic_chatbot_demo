import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/models/cellular_world.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/widgets/cellular_world_widget.dart';
import 'package:logic_chatbot/widgets/conversation_world_panel.dart';
import 'package:logic_chatbot/widgets/world_display.dart';

import 'network_editor_test.dart' show DomainStore;

Map<String, dynamic> _world(WorldDomain domain, {int generation = 0}) {
  final filename = switch (domain) {
    WorldDomain.objects => 'toy_world',
    WorldDomain.network => 'network_world',
    WorldDomain.cellular => 'cellular_world',
  };
  final world =
      jsonDecode(File('../backend/shared/$filename.json').readAsStringSync())
          as Map<String, dynamic>;
  if (domain == WorldDomain.cellular) {
    world['generation'] = generation;
    if (generation == 1) {
      // Known first-generation response from the Haskell glider fixture.
      final cells = List.filled(256, 'white');
      for (final (x, y) in [(7, 8), (9, 8), (8, 7), (9, 7), (8, 6)]) {
        cells[x + 16 * y] = 'black';
      }
      world['cells'] = cells;
    }
  }
  return world;
}

Map<String, dynamic> _state({
  WorldDomain domain = WorldDomain.cellular,
  int generation = 0,
  bool saved = false,
}) => {
  'conversationId': domain.name,
  'domain': domain.name,
  'languageVersion': '${domain.name}-v2',
  'world': _world(domain, generation: generation),
  'canUndo': generation > 0,
  'feedback': 'Generation $generation',
  'changedCells': generation == 1 ? 4 : null,
  'worldSlots': [
    for (var slot = 1; slot <= 5; slot++)
      {'slot': slot, 'savedAt': saved && slot == 1 ? 'now' : null},
  ],
};

http.Response _reply(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

class _Server {
  final history = [0];
  int? saved;
  final requests = <http.Request>[];

  Future<http.Response> call(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/conversations') {
      final domain = WorldDomain.values.byName(
        jsonDecode(request.body)['domain'] as String,
      );
      return _reply(_state(domain: domain), 201);
    }
    final domain = WorldDomain.values.byName(request.url.pathSegments[1]);
    if (domain == WorldDomain.cellular && request.method == 'POST') {
      final action = request.url.pathSegments.skip(2).join('/');
      switch (action) {
        case 'step':
          history.add(1);
        case 'undo':
          if (history.length > 1) history.removeLast();
        case 'slots/1/save':
          saved = history.last;
        case 'slots/1/load':
          history.add(saved!);
        default:
          throw StateError('Unexpected cellular action: $action');
      }
    }
    return _reply({
      ..._state(
        domain: domain,
        generation: domain == WorldDomain.cellular ? history.last : 0,
        saved: domain == WorldDomain.cellular && saved != null,
      ),
      'canUndo': domain == WorldDomain.cellular && history.length > 1,
    });
  }
}

void main() {
  test(
    'cellular snapshots decode without object identities and remain immutable',
    () {
      final state = ConversationState.fromJson(_state());
      final world = state.cellularWorld!;
      expect(state.domain, WorldDomain.cellular);
      expect(state.objectWorld, isNull);
      expect(world.colorAt(8, 9), CellColor.black);
      expect(world.colorAt(0, 0), CellColor.white);
      expect(world.ruleset.palette, [CellColor.white, CellColor.black]);
      expect(world.ruleset.rules[CellColor.black]!.counts, {
        0,
        1,
        4,
        5,
        6,
        7,
        8,
      });
      expect(() => world.cells[0] = CellColor.black, throwsUnsupportedError);
      expect(() => world.ruleset.rules.clear(), throwsUnsupportedError);
      expect(
        () => world.ruleset.rules[CellColor.black]!.counts.add(2),
        throwsUnsupportedError,
      );
      expect(ConversationState.fromJson(_state(generation: 1)).changedCells, 4);
      final six = _world(WorldDomain.cellular);
      six['ruleset'] = {
        'palette': CellColor.values.map((color) => color.name).toList(),
        'neighborhood': 4,
        'rules': <String, dynamic>{},
      };
      six['cells'] = List.generate(
        256,
        (index) => CellColor.values[index % 6].name,
      );
      expect(
        CellularWorld.fromJson(six).cells.toSet(),
        CellColor.values.toSet(),
      );
      final invalid = _world(WorldDomain.cellular);
      invalid['cells'] = ['white'];
      expect(() => CellularWorld.fromJson(invalid), throwsFormatException);
      final duplicate = _world(WorldDomain.cellular);
      duplicate['ruleset']['rules']['white']['counts'] = [3, 3];
      expect(() => CellularWorld.fromJson(duplicate), throwsFormatException);
    },
  );

  test(
    'step waits for server state, blocks duplicates and suppresses object edits',
    () async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final controller =
          ConversationController(
              store: DomainStore(),
              api: ConversationApi(
                baseUrl: Uri.parse('http://localhost:8000/api'),
                client: MockClient((request) {
                  requests.add(request);
                  return pending.future;
                }),
              ),
            )
            ..domain = WorldDomain.cellular
            ..conversation = ConversationState.fromJson(_state());
      addTearDown(controller.dispose);
      final previous = controller.conversation;
      final stepping = controller.step();
      expect(controller.editing, isTrue);
      expect(controller.canStep, isFalse);
      expect(controller.conversation, same(previous));
      await controller.step();
      await controller.paint(0, 0);
      await controller.erase(0, 0);
      await controller.clear();
      expect(await controller.sendChat('Step.'), isFalse);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/conversations/cellular/step');
      expect(requests.single.body, isEmpty);
      pending.complete(_reply(_state(generation: 1)));
      await stepping;
      expect(controller.conversation!.cellularWorld!.generation, 1);
      expect(
        controller.conversation!.cellularWorld!.colorAt(7, 8),
        CellColor.black,
      );
      expect(controller.canStep, isTrue);
      expect(controller.canUndo, isTrue);
      await controller.paint(0, 0);
      await controller.erase(0, 0);
      await controller.clear();
      expect(await controller.sendChat('Advance 1 generation.'), isTrue);
      expect(requests, hasLength(2));
      expect(requests.last.url.path, '/api/conversations/cellular/chat');
    },
  );

  test(
    'failed step preserves board; refresh recovers without repeating it',
    () async {
      final methods = <String>[];
      final store = DomainStore()..ids[WorldDomain.cellular] = 'cellular';
      final controller =
          ConversationController(
              store: store,
              api: ConversationApi(
                baseUrl: Uri.parse('http://localhost:8000'),
                client: MockClient((request) async {
                  methods.add(request.method);
                  if (request.method == 'POST') {
                    throw http.ClientException('Lost response');
                  }
                  return _reply(_state(generation: 1));
                }),
              ),
            )
            ..domain = WorldDomain.cellular
            ..conversation = ConversationState.fromJson(_state());
      addTearDown(controller.dispose);
      await controller.step();
      expect(controller.conversation!.cellularWorld!.generation, 0);
      expect(controller.error, isNotNull);
      await controller.step();
      await controller.load();
      expect(methods, ['POST', 'GET']);
      expect(controller.conversation!.cellularWorld!.generation, 1);
      expect(controller.error, isNull);
    },
  );

  testWidgets(
    'grid uses chessboard orientation and stays fixed while updating',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var clicks = 0;
      Future<void> display({bool busy = false, int generation = 0}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: ConversationWorldPanel(
                  conversation: ConversationState.fromJson(
                    _state(generation: generation),
                  ),
                  loading: false,
                  editing: busy,
                  error: null,
                  onRetry: () {},
                  onStep: () => clicks++,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (!busy) await tester.pumpAndSettle();
      }

      Finder square(String value) =>
          find.byKey(ValueKey('cellular-cell-$value'));
      Color color(String value) =>
          (tester.widget<DecoratedBox>(square(value)).decoration
                  as BoxDecoration)
              .color!;
      await display();
      final a1 = tester.getRect(square('A1'));
      expect(tester.getRect(square('A8')).top, lessThan(a1.top));
      expect(tester.getRect(square('B1')).left, greaterThan(a1.left));
      expect(color('I10'), Colors.black);
      expect(color('H9'), Colors.white);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('P'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(tester.getRect(square('P16')).right, greaterThan(a1.right));
      expect(tester.getRect(square('P16')).top, lessThan(a1.top));
      expect(find.byType(WorldDisplay), findsNothing);
      await tester.tap(find.byKey(const ValueKey('cellular-step')));
      expect(clicks, 1);
      expect(find.text('Generation 0'), findsOneWidget);
      await display(busy: true);
      expect(tester.getRect(square('A1')), a1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('cellular-step')))
            .onPressed,
        isNull,
      );
      await display(generation: 1);
      expect(tester.getRect(square('A1')), a1);
      expect(color('I10'), Colors.white);
      expect(color('H9'), Colors.black);
      expect(find.text('Generation 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'cell painting waits for the server and blocks concurrent actions',
    () async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final controller =
          ConversationController(
              store: DomainStore(),
              api: ConversationApi(
                baseUrl: Uri.parse('http://localhost:8000'),
                client: MockClient((request) {
                  requests.add(request);
                  return pending.future;
                }),
              ),
            )
            ..domain = WorldDomain.cellular
            ..conversation = ConversationState.fromJson(_state());
      addTearDown(controller.dispose);
      final previous = controller.conversation;
      controller.selectCellColor(CellColor.red);
      expect(controller.selectedCellColor, CellColor.black);
      final painting = controller.paintCell(15, 15);
      await Future<void>.delayed(Duration.zero);
      expect(controller.conversation, same(previous));
      expect(controller.canEditCells, isFalse);
      controller.selectCellColor(CellColor.white);
      expect(controller.selectedCellColor, CellColor.black);
      await controller.paintCell(0, 0);
      await controller.step();
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/conversations/cellular/cell');
      expect(jsonDecode(requests.single.body), {
        'position': {'x': 15, 'y': 15},
        'color': 'black',
      });
      final response = _state();
      response['world']['cells'][255] = 'black';
      response['canUndo'] = true;
      pending.complete(_reply(response));
      await painting;
      expect(
        controller.conversation!.cellularWorld!.colorAt(15, 15),
        CellColor.black,
      );
      expect(controller.conversation!.cellularWorld!.generation, 0);
      expect(controller.canUndo, isTrue);
      expect(controller.canEditCells, isTrue);
    },
  );

  test(
    'failed paint preserves the board and refresh reconciles palette selection',
    () async {
      final methods = <String>[];
      final store = DomainStore()..ids[WorldDomain.cellular] = 'cellular';
      final updated = _state();
      updated['world']['ruleset'] = {
        'palette': ['red', 'blue'],
        'neighborhood': 4,
        'rules': <String, dynamic>{},
      };
      updated['world']['cells'] = List.filled(256, 'red');
      final controller =
          ConversationController(
              store: store,
              api: ConversationApi(
                baseUrl: Uri.parse('http://localhost:8000'),
                client: MockClient((request) async {
                  methods.add(request.method);
                  if (request.method == 'POST') {
                    throw http.ClientException('Lost response');
                  }
                  return _reply(updated);
                }),
              ),
            )
            ..domain = WorldDomain.cellular
            ..conversation = ConversationState.fromJson(_state());
      addTearDown(controller.dispose);
      final previous = controller.conversation;
      await controller.paintCell(0, 0);
      expect(controller.conversation, same(previous));
      expect(controller.error, isNotNull);
      await controller.paintCell(0, 0);
      await controller.load();
      expect(methods, ['POST', 'GET']);
      expect(controller.selectedCellColor, CellColor.red);
      controller.selectCellColor(CellColor.blue);
      expect(controller.selectedCellColor, CellColor.blue);
      controller.selectCellColor(CellColor.black);
      expect(controller.selectedCellColor, CellColor.blue);
    },
  );

  testWidgets('cell editor selects one active color and paints only on tap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var state = _state();
    final paints = <Map<String, dynamic>>[];
    final controller = ConversationController(
      store: DomainStore()..ids[WorldDomain.cellular] = 'cellular',
      api: ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/conversations/cellular/cell');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            paints.add(body);
            // Test server returns the authoritative snapshot without advancing time.
            state = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
            final p = body['position'];
            state['world']['cells'][p['x'] + 16 * p['y']] = body['color'];
            state['canUndo'] = true;
          }
          return _reply(state);
        }),
      ),
    )..domain = WorldDomain.cellular;
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    Finder swatch(CellColor color) =>
        find.byKey(ValueKey('cellular-color-${color.name}'));
    bool selected(CellColor color) =>
        tester.widget<Semantics>(swatch(color)).properties.selected == true;
    final square = find.byKey(const ValueKey('cellular-cell-A1'));
    final rect = tester.getRect(square);
    expect(selected(CellColor.black), isTrue);
    expect(selected(CellColor.white), isFalse);
    expect(swatch(CellColor.red), findsNothing);
    await tester.tap(square, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.longPress(square);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(paints, isEmpty);
    await tester.tap(square);
    await tester.pumpAndSettle();
    expect(paints.single, {
      'position': {'x': 0, 'y': 0},
      'color': 'black',
    });
    await tester.tap(swatch(CellColor.white));
    await tester.pumpAndSettle();
    expect(selected(CellColor.white), isTrue);
    expect(selected(CellColor.black), isFalse);
    await tester.tap(swatch(CellColor.white));
    await tester.pumpAndSettle();
    expect(selected(CellColor.white), isTrue);
    await tester.tap(square);
    await tester.pumpAndSettle();
    expect(paints.last['color'], 'white');
    expect(
      controller.conversation!.cellularWorld!.colorAt(0, 0),
      CellColor.white,
    );
    expect(controller.conversation!.cellularWorld!.generation, 0);
    expect(tester.getRect(square), rect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('six-color palette scrolls without changing the grid size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    CellColor selected = CellColor.black;
    Future<void> display(bool six) async {
      final state = _state();
      if (six) {
        state['world']['ruleset']['palette'] = CellColor.values
            .map((c) => c.name)
            .toList();
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: ConversationWorldPanel(
                conversation: ConversationState.fromJson(state),
                loading: false,
                error: null,
                onRetry: () {},
                selectedCellColor: selected,
                onCellColorChanged: (color) => selected = color,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await display(false);
    final a1 = find.byKey(const ValueKey('cellular-cell-A1'));
    final rect = tester.getRect(a1);
    await display(true);
    final yellow = find.byKey(const ValueKey('cellular-color-yellow'));
    await tester.ensureVisible(yellow);
    await tester.tap(yellow);
    await tester.pumpAndSettle();
    expect(selected, CellColor.yellow);
    expect(tester.getRect(a1), rect);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'player wires domain switching, step, slots and undo at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final store = DomainStore();
        final server = _Server();
        final controller = ConversationController(
          store: store,
          api: ConversationApi(
            baseUrl: Uri.parse('http://localhost:8000'),
            client: MockClient(server.call),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(home: DemoScreen(createController: () => controller)),
        );
        await tester.pumpAndSettle();
        controller.setUseLlm(true);
        Future<void> choose(String domain) async {
          if (width < 480) {
            await tester.tap(find.byKey(const ValueKey('domain-selector')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text(domain).last);
          await tester.pumpAndSettle();
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await choose('Cellular');
        expect(controller.domain, WorldDomain.cellular);
        expect(find.byType(CellularWorldWidget), findsOneWidget);
        expect(find.text('Generation 0'), findsOneWidget);
        expect(find.byTooltip('Clear world'), findsNothing);
        expect(controller.llmEnabled, isTrue);
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
        expect(controller.canChat, isTrue);
        await tap(find.byKey(const ValueKey('save-slot-1')));
        await tap(find.byKey(const ValueKey('cellular-step')));
        expect(find.text('Generation 1'), findsOneWidget);
        await tap(find.byKey(const ValueKey('load-slot-1')));
        expect(find.text('Generation 0'), findsOneWidget);
        await tap(find.byTooltip('Undo'));
        expect(find.text('Generation 1'), findsOneWidget);
        await choose('Network');
        expect(controller.llmEnabled, isTrue);
        await choose('Cellular');
        expect(find.text('Generation 1'), findsOneWidget);
        expect(store.ids.keys.toSet(), WorldDomain.values.toSet());
        expect(
          server.requests.where((r) => r.url.path == '/conversations'),
          hasLength(3),
        );
        expect(
          server.requests.where((r) => r.url.path.endsWith('/step')),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
