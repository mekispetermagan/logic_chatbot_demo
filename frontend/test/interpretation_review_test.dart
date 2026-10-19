import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/controllers/conversation_controller.dart';
import 'package:logic_chatbot/main.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/widgets/world_display.dart';

import 'llm_test.dart' show SavedConversation;

const original = '  Give B2 a warm color, please.  ';

/// A server draft stays separate from the committed world until acceptance.
class ReviewServer {
  String domain = 'objects';
  bool offered = false;
  bool accepted = false;
  bool noCandidates = false;
  bool stale = false;
  bool invalid = false;
  bool legacyLanguage = false;
  bool stagedBatch = false;
  int proposalNumber = 0;
  final requests = <String>[];
  final prompts = <String>[];
  final answers = <String>[];

  Map<String, dynamic> world([String? color]) => {
    'width': 8,
    'height': 8,
    'objects': [
      if (color != null)
        {
          'id': 0,
          'attributes': {
            'color': color,
            if (domain == 'network') 'east': 'east',
            if (domain == 'network') 'west': 'west',
          },
          'position': {'x': 1, 'y': 1},
        },
    ],
  };

  Map<String, dynamic> state({int? previewRank}) => {
    'conversationId': 'saved',
    'domain': domain,
    'languageVersion': '$domain-v2',
    'canUndo': accepted,
    'feedback': 'Review state updated.',
    'world': world(accepted ? 'yellow' : null),
    'messages': [
      for (final prompt in prompts) {'role': 'user', 'text': prompt},
    ],
    'proposal': offered
        ? {
            'id': 'proposal-$proposalNumber',
            'languageVersion': legacyLanguage ? '$domain-v1' : '$domain-v2',
            'originalText': prompts.isEmpty ? original : prompts.last,
            'question': noCandidates
                ? 'Which square should change?'
                : 'By warm, do you mean red or yellow?',
            'validationFailures': [
              if (invalid)
                {
                  'interpretation': 'Malformed program',
                  'translation': 'B2 red -sw.',
                  'reason': 'Unsupported syntax: b2 red -sw.',
                },
            ],
            'explanation': 'Two available colors fit a warm color.',
            'candidates': [
              if (!noCandidates)
                for (final color in ['red', 'yellow'])
                  {
                    'rank': color == 'red' ? 1 : 2,
                    'interpretation': 'Use $color',
                    'translation': 'B2 $color.',
                    'explanation': '$color is a warm color.',
                  },
            ],
          }
        : null,
    if (previewRank != null)
      'preview': {
        'proposalId': 'proposal-$proposalNumber',
        'rank': previewRank,
        'world': world(
          stagedBatch
              ? null
              : previewRank == 1
              ? 'red'
              : 'yellow',
        ),
        'feedback': 'B2 changes only in this preview.',
        'changes': [
          if (!stagedBatch)
            {
              'objectId': 0,
              'kind': 'appearance',
              'detail': domain == 'network'
                  ? '#0: pattern ---- -> -e-w'
                  : '#0: color none -> yellow',
            },
        ],
        if (stagedBatch)
          'pending': {
            'sentence': 'Move it next to #3.',
            'candidates': [],
            'squareChoices': [
              {'x': 3, 'y': 4},
            ],
            'stagedWorld': world('yellow'),
          },
      },
  };

  Future<http.Response> respond(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    final action = request.url.pathSegments.last;
    int? previewRank;
    if (request.method == 'POST') {
      if (action == 'chat') {
        prompts.add(jsonDecode(request.body)['text'] as String);
        offered = true;
        proposalNumber++;
      } else if (action == 'answer') {
        answers.add(jsonDecode(request.body)['text'] as String);
        proposalNumber++;
        noCandidates = false;
        invalid = false;
      } else if (action == 'preview' || action == 'accept') {
        if (stale) {
          return http.Response(
            jsonEncode({
              'detail':
                  'Conversation changed; reject this interpretation and resend your prompt',
            }),
            409,
          );
        }
        expect(jsonDecode(request.body), {'rank': 2});
        if (action == 'preview') {
          previewRank = 2;
        } else {
          accepted = true;
          offered = false;
        }
      } else if (action == 'reject') {
        offered = false;
      }
    }
    return http.Response(jsonEncode(state(previewRank: previewRank)), 200);
  }

  ConversationController controller() => ConversationController(
    store: SavedConversation(),
    api: ConversationApi(
      baseUrl: Uri.parse('http://localhost:8000'),
      client: MockClient(respond),
    ),
  )..domain = WorldDomain.values.byName(domain);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final domain in ['objects', 'network']) {
    testWidgets(
      '$domain old-language proposals remain rejectable but cannot execute or accept answers',
      (tester) async {
        final server = ReviewServer()
          ..domain = domain
          ..offered = true
          ..legacyLanguage = true;
        final controller = server.controller();
        await tester.pumpWidget(
          MaterialApp(home: DemoScreen(createController: () => controller)),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Chat'));
        expect(find.textContaining('older language version'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Preview'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
              .onPressed,
          isNull,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue, // The composer remains available for "full reset".
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit answer'),
              )
              .onPressed,
          isNull,
        );
        await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reject'));
        expect(controller.conversation!.proposal, isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          original,
        );
      },
    );
  }

  testWidgets('preview shows explicit identifier and appearance effects', (
    tester,
  ) async {
    final server = ReviewServer();
    final controller = server.controller();
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    await controller.sendChat(original);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Chat'));
    await tapVisible(tester, find.byKey(const ValueKey('interpretation-2')));
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Preview'));
    expect(find.text('Identity and state changes'), findsOneWidget);
    expect(find.text('#0: color none -> yellow'), findsOneWidget);
    expect(controller.conversation!.world.objects, isEmpty);
    expect(controller.preview!.changes.single.kind, 'appearance');
    expect(tester.takeException(), isNull);
  });

  testWidgets('network v2 previews expose port changes without applying', (
    tester,
  ) async {
    final server = ReviewServer()..domain = 'network';
    final controller = server.controller();
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    await controller.sendChat(original);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Chat'));
    await tapVisible(tester, find.byKey(const ValueKey('interpretation-2')));
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Preview'));
    expect(find.text('#0: pattern ---- -> -e-w'), findsOneWidget);
    expect(controller.conversation!.languageVersion, 'network-v2');
    expect(controller.conversation!.world.objects, isEmpty);
    expect(controller.preview!.world.objects.single.attributes, {
      'color': 'yellow',
      'east': 'east',
      'west': 'west',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('atomic preview displays staged world without committing it', (
    tester,
  ) async {
    final server = ReviewServer()..stagedBatch = true;
    final controller = server.controller();
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    await controller.sendChat(original);
    controller.selectInterpretation(2);
    await controller.previewInterpretation();
    await tester.pumpAndSettle();
    expect(controller.conversation!.world.objects, isEmpty);
    expect(controller.preview!.world.objects, isEmpty);
    expect(
      tester
          .widget<WorldDisplay>(find.byType(WorldDisplay))
          .world
          .objects
          .single
          .color,
      ObjectColor.yellow,
    );
    expect(find.widgetWithText(Chip, 'Preview — not applied'), findsOneWidget);
    await tapVisible(tester, find.text('Chat'));
    expect(
      find.textContaining('provisional atomic-batch preview'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'preview, refresh and acceptance keep draft separate from actual world',
    () async {
      final server = ReviewServer();
      final controller = server.controller();
      addTearDown(controller.dispose);
      await controller.load();
      controller.setUseLlm(true);
      expect(await controller.sendChat(original), isTrue);
      expect(controller.conversation!.world.objects, isEmpty);
      expect(
        server.requests.where((path) => path.endsWith('/accept')),
        isEmpty,
      );
      expect(controller.canEdit, isFalse);
      controller.selectInterpretation(2);
      expect(await controller.previewInterpretation(), isTrue);
      expect(
        controller.preview!.world.objects.single.color,
        ObjectColor.yellow,
      );
      expect(controller.conversation!.world.objects, isEmpty);
      controller.selectInterpretation(1);
      expect(controller.preview, isNull);
      controller.selectInterpretation(2);
      // Refresh restores the same proposal but never treats a preview as committed.
      await controller.load();
      expect(controller.selectedInterpretationRank, 2);
      expect(controller.preview, isNull);
      expect(controller.conversation!.proposal!.originalText, original);
      expect(await controller.acceptInterpretation(), isTrue);
      expect(
        controller.conversation!.world.objects.single.color,
        ObjectColor.yellow,
      );
      expect(controller.conversation!.proposal, isNull);
      expect(controller.canEdit, isTrue);
      expect(server.prompts, [original]);
    },
  );

  test(
    'a stale candidate stays rejectable and server detail reaches the UI',
    () async {
      final server = ReviewServer();
      final controller = server.controller();
      addTearDown(controller.dispose);
      await controller.load();
      await controller.sendChat(original);
      controller.selectInterpretation(2);
      server.stale = true;
      expect(await controller.acceptInterpretation(), isFalse);
      expect(controller.error, contains('Conversation changed; reject'));
      expect(controller.canReview, isTrue);
      expect(controller.conversation!.world.objects, isEmpty);
      expect(await controller.rejectInterpretation(), isTrue);
      expect(controller.error, isNull);
      expect(controller.canEdit, isTrue);
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets('ranked preview, reject and amended resend at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = ReviewServer();
      final controller = server.controller();
      await tester.pumpWidget(
        MaterialApp(home: DemoScreen(createController: () => controller)),
      );
      await tester.pumpAndSettle();
      if (width < 900) await tapVisible(tester, find.text('Chat'));
      await tester.enterText(find.byType(TextField), original);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.conversation!.world.objects, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await tapVisible(tester, find.byKey(const ValueKey('interpretation-2')));
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Preview'));
      expect(controller.preview!.rank, 2);
      expect(controller.conversation!.world.objects, isEmpty);
      if (width < 900) await tapVisible(tester, find.text('World'));
      expect(
        tester
            .widget<WorldDisplay>(find.byType(WorldDisplay))
            .world
            .objects
            .single
            .color,
        ObjectColor.yellow,
      );
      expect(
        find.widgetWithText(Chip, 'Preview — not applied'),
        findsOneWidget,
      );
      if (width < 900) await tapVisible(tester, find.text('Chat'));
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reject'));
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, original);
      expect(
        input.controller!.selection,
        TextSelection.collapsed(offset: original.length),
      );
      expect(input.focusNode!.hasFocus, isTrue);
      expect(controller.preview, isNull);
      expect(controller.conversation!.world.objects, isEmpty);
      await tester.enterText(find.byType(TextField), '$original Use yellow.');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(server.prompts, [original, '$original Use yellow.']);
      await tapVisible(tester, find.byKey(const ValueKey('interpretation-2')));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Accept'));
      expect(controller.conversation!.proposal, isNull);
      expect(
        controller.conversation!.world.objects.single.color,
        ObjectColor.yellow,
      );
      expect(controller.preview, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'persisted clarification without candidates allows answers and rejection',
    (tester) async {
      final server = ReviewServer()
        ..offered = true
        ..noCandidates = true;
      final controller = server.controller();
      await tester.pumpWidget(
        MaterialApp(home: DemoScreen(createController: () => controller)),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Chat'));
      expect(find.text('Which square should change?'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Preview'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reject'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        original,
      );
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'validation failure can be clarified then previewed at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final server = ReviewServer()
          ..offered = true
          ..noCandidates = true
          ..invalid = true;
        final controller = server.controller();
        await tester.pumpWidget(
          MaterialApp(home: DemoScreen(createController: () => controller)),
        );
        await tester.pumpAndSettle();
        if (width < 900) await tapVisible(tester, find.text('Chat'));
        expect(find.text('Translation failed validation'), findsOneWidget);
        expect(
          find.textContaining('Discarded translation: Unsupported syntax:'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byType(TextField),
          'Use isolated nodes on B2.',
        );
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Submit answer'),
        );
        expect(server.answers, ['Use isolated nodes on B2.']);
        expect(
          server.requests.last,
          endsWith('/interpretations/proposal-0/answer'),
        );
        expect(server.prompts, isEmpty);
        expect(controller.conversation!.world.objects, isEmpty);
        expect(controller.conversation!.proposal!.originalText, original);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(find.textContaining('Discarded translation:'), findsNothing);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('interpretation-2')),
        );
        await tapVisible(
          tester,
          find.widgetWithText(OutlinedButton, 'Preview'),
        );
        expect(
          controller.preview!.world.objects.single.color,
          ObjectColor.yellow,
        );
        expect(controller.conversation!.world.objects, isEmpty);
        await tapVisible(tester, find.widgetWithText(FilledButton, 'Accept'));
        expect(
          controller.conversation!.world.objects.single.color,
          ObjectColor.yellow,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Enter submits a clarification answer without resending original as chat',
    (tester) async {
      final server = ReviewServer()
        ..offered = true
        ..noCandidates = true;
      final controller = server.controller();
      await tester.pumpWidget(
        MaterialApp(home: DemoScreen(createController: () => controller)),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Chat'));
      await tester.enterText(find.byType(TextField), 'B2, please');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(server.answers, ['B2, please']);
      expect(server.prompts, isEmpty);
      expect(controller.conversation!.world.objects, isEmpty);
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reject'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        original,
      );
    },
  );
}
