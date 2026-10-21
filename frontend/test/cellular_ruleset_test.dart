import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/cellular_ruleset_controller.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/models/cellular_presets.dart';
import 'package:logic_chatbot/models/cellular_world.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/widgets/cellular_ruleset_dialog.dart';

import 'network_editor_test.dart' show DomainStore;

Map<String, dynamic> fixture() =>
    jsonDecode(File('../backend/shared/cellular_world.json').readAsStringSync())
        as Map<String, dynamic>;
CellularWorld world() => CellularWorld.fromJson(fixture());
Map<String, dynamic> state(
  Map<String, dynamic> world, {
  bool canUndo = false,
}) => {
  'conversationId': 'cellular',
  'domain': 'cellular',
  'languageVersion': 'cellular-v2',
  'world': world,
  'canUndo': canUndo,
  'feedback': 'Ruleset updated',
};

void main() {
  test(
    'Life converts to target-color counts and leaves the initial state intact',
    () {
      final initial = world();
      final draft = CellularRulesetController(
        world: initial,
        onSubmit: (_, _) async => true,
      );
      addTearDown(draft.dispose);
      expect(draft.ruleFor(CellColor.black).target, CellColor.white);
      expect(draft.ruleFor(CellColor.black).counts, {0, 1, 2, 3, 4, 7, 8});
      expect(draft.buildRuleset().toJson(), CellularPresets.life.toJson());
      expect(
        initial.ruleset.rules[CellColor.black]!.neighborColor,
        CellColor.black,
      );
      expect(initial.ruleset.rules[CellColor.black]!.counts, {
        0,
        1,
        4,
        5,
        6,
        7,
        8,
      });
      expect(
        CellularRuleset.fromJson(draft.buildRuleset().toJson()).toJson(),
        draft.buildRuleset().toJson(),
      );
    },
  );

  test(
    'draft validates palette, targets and out-of-range counts before submission',
    () async {
      var calls = 0;
      final draft = CellularRulesetController(
        world: world(),
        onSubmit: (_, _) async {
          calls++;
          return true;
        },
      );
      addTearDown(draft.dispose);
      draft.setNeighborhood(4);
      expect(draft.validationError, contains('above 4'));
      expect(await draft.submit(refill: false), isFalse);
      expect(calls, 0);
      draft.setRule(CellColor.black, clearInvalid: true);
      expect(draft.canSubmit, isTrue);
      draft.toggleColor(CellColor.white);
      expect(draft.validationError, contains('at least two'));
      draft.toggleColor(CellColor.red);
      expect(draft.validationError, contains('target for black'));
      draft.setRule(CellColor.black, target: CellColor.red);
      draft.setRule(
        CellColor.red,
        target: CellColor.black,
        enabled: true,
        toggleCount: 2,
      );
      expect(draft.canSubmit, isTrue);
      expect(draft.requiresRefill, isTrue);
      expect(await draft.submit(refill: false), isFalse);
      expect(calls, 0);
      expect(await draft.submit(refill: true), isTrue);
      expect(calls, 1);
    },
  );

  test(
    'presets replace only the draft and RGB submits one complete ruleset',
    () async {
      final submissions = <(CellularRuleset, bool)>[];
      final original = world();
      final draft = CellularRulesetController(
        world: original,
        onSubmit: (config, refill) async {
          submissions.add((config, refill));
          return true;
        },
      );
      addTearDown(draft.dispose);
      draft.setNeighborhood(4);
      draft.usePreset(CellularPresets.rgb);
      expect(submissions, isEmpty);
      expect(draft.neighborhood, 8);
      expect(draft.palette.toSet(), {
        CellColor.red,
        CellColor.green,
        CellColor.blue,
      });
      for (final (source, target) in [
        (CellColor.red, CellColor.green),
        (CellColor.green, CellColor.blue),
        (CellColor.blue, CellColor.red),
      ]) {
        expect(draft.ruleFor(source).target, target);
        expect(draft.ruleFor(source).counts, {2, 3, 4, 5, 6, 7, 8});
        expect(draft.ruleFor(source).enabled, isTrue);
      }
      expect(await draft.submit(refill: true), isTrue);
      expect(submissions, hasLength(1));
      expect(submissions.single.$2, isTrue);
      expect(
        submissions.single.$1.rules.values.every(
          (r) => r.targetColor == r.neighborColor,
        ),
        isTrue,
      );
      expect(original.cells.toSet(), {CellColor.white, CellColor.black});
      draft.usePreset(CellularPresets.life);
      expect(draft.requiresRefill, isFalse);
      expect(draft.buildRuleset().toJson(), CellularPresets.life.toJson());
    },
  );

  test(
    'pending and failed submissions cannot be repeated or change the submitted draft',
    () async {
      final result = Completer<bool>();
      var calls = 0;
      final draft = CellularRulesetController(
        world: world(),
        onSubmit: (_, _) {
          calls++;
          return result.future;
        },
      );
      addTearDown(draft.dispose);
      final submitting = draft.submit(refill: false);
      draft.usePreset(CellularPresets.rgb);
      draft.toggleColor(CellColor.red);
      draft.setNeighborhood(4);
      draft.setRule(CellColor.white, toggleCount: 2);
      expect(draft.palette, [CellColor.white, CellColor.black]);
      expect(draft.neighborhood, 8);
      expect(draft.ruleFor(CellColor.white).counts, {3});
      expect(await draft.submit(refill: false), isFalse);
      expect(calls, 1);
      result.complete(false);
      expect(await submitting, isFalse);
      expect(draft.submissionError, contains('refresh'));
      expect(draft.canSubmit, isFalse);
      expect(await draft.submit(refill: false), isFalse);
      expect(calls, 1);
    },
  );

  test(
    'unrepresentable stored rules are flagged rather than silently rewritten',
    () {
      final initial = world();
      final config = CellularRuleset(
        palette: [CellColor.white, CellColor.black, CellColor.red],
        neighborhood: 8,
        rules: initial.ruleset.rules,
      );
      final draft = CellularRulesetController(
        world: CellularWorld(
          cells: initial.cells,
          ruleset: config,
          generation: 0,
          rulesetRevision: 1,
        ),
        onSubmit: (_, _) async => true,
      );
      addTearDown(draft.dispose);
      expect(draft.validationError, contains('black'));
      draft.setRule(CellColor.black, target: CellColor.white);
      expect(draft.canSubmit, isTrue);
    },
  );

  testWidgets(
    'modal validates and edits counts without submitting individual changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CellularRulesetDialog(
                    world: world(),
                    onSubmit: (_, _) async {
                      calls++;
                      return true;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('von Neumann (4)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rule-count-white-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('rule-count-white-5')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('submit-cellular-rules')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Remove counts above 4'));
      await tester.tap(find.text('Remove counts above 4'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('submit-cellular-rules')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('rule-count-white-2')),
      );
      await tester.tap(find.byKey(const ValueKey('rule-count-white-2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('rule-count-white-2')),
            )
            .selected,
        isTrue,
      );
      expect(calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CellularRulesetDialog), findsNothing);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets('preset, refill confirmation, atomic submit and undo at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final initial = fixture()..['generation'] = 7;
      final history = [initial];
      final requests = <http.Request>[];
      final gate = Completer<void>();
      final controller = ConversationController(
        store: DomainStore()..ids[WorldDomain.cellular] = 'cellular',
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            requests.add(request);
            if (request.method == 'POST' &&
                request.url.path.endsWith('/ruleset')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body.keys.toSet(), {'ruleset', 'refill'});
              expect(body['refill'], isTrue);
              final config = CellularRuleset.fromJson(body['ruleset']);
              expect(config.palette.toSet(), {
                CellColor.red,
                CellColor.green,
                CellColor.blue,
              });
              await gate.future;
              // Fixture server supplies a complete response; Flutter never fills cells.
              history.add({
                ...initial,
                'generation': 0,
                'rulesetRevision': 2,
                'ruleset': config.toJson(),
                'cells': List.generate(256, (i) => config.palette[i % 3].name),
              });
            } else if (request.method == 'POST' &&
                request.url.path.endsWith('/undo')) {
              history.removeLast();
            } else {
              expect(request.method, 'GET');
            }
            return http.Response(
              jsonEncode(state(history.last, canUndo: history.length > 1)),
              200,
            );
          }),
        ),
      )..domain = WorldDomain.cellular;
      await tester.pumpWidget(
        MaterialApp(home: DemoScreen(createController: () => controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit rules'));
      await tester.pumpAndSettle();
      final rgb = find.byKey(const ValueKey('preset-rgb'));
      await tester.ensureVisible(rgb);
      await tester.tap(rgb);
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      expect(controller.conversation!.cellularWorld!.generation, 7);
      await tester.tap(find.byKey(const ValueKey('submit-cellular-rules')));
      await tester.pumpAndSettle();
      expect(find.text('Randomly refill the board?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      expect(find.byType(CellularRulesetDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('submit-cellular-rules')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-cellular-refill')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Submitting…'), findsOneWidget);
      expect(controller.conversation!.cellularWorld!.generation, 7);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel').last)
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CellularRulesetDialog), findsNothing);
      expect(controller.conversation!.cellularWorld!.generation, 0);
      expect(controller.selectedCellColor, CellColor.red);
      expect(controller.conversation!.cellularWorld!.cells.toSet(), {
        CellColor.red,
        CellColor.green,
        CellColor.blue,
      });
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(controller.conversation!.cellularWorld!.generation, 7);
      expect(
        controller.conversation!.cellularWorld!.ruleset.toJson(),
        world().ruleset.toJson(),
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/ruleset')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
