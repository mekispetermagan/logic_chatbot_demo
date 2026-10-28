import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/calendar_api.dart';
import 'package:logic_chatbot/controllers/calendar_controller.dart';
import 'package:logic_chatbot/widgets/calendar_chat_panel.dart';
import 'package:logic_chatbot/widgets/interpretation_review.dart';

Map<String, dynamic> proposal({
  bool questionOnly = false,
  bool json = false,
}) => {
  'id': 'calendar-proposal',
  'languageVersion': 'calendar-v1',
  'originalText': 'Find a slot',
  'question': questionOnly
      ? 'Did you mean insertion or explicit movement?'
      : '',
  'explanation': '',
  'validationFailures': [],
  'translationFormat': json ? 'json' : 'controlledEnglish',
  'candidates': questionOnly
      ? []
      : [
          {
            'rank': 1,
            'interpretation': 'Find a free half hour',
            'translation': json
                ? '30'
                : 'Schedule event lasting 30 minutes within thursday morning.',
            'explanation': '',
          },
        ],
};

void main() {
  testWidgets(
    'Calendar reuses review: natural request, preview, acceptance, separate cloud approval',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      var state = <String, dynamic>{
        'status': 'idle',
        'revision': 0,
        'messages': [],
      };
      final api = CalendarApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/events')) {
            return http.Response(jsonEncode({'events': []}), 200);
          }
          if (request.method == 'POST') {
            final action = jsonDecode(request.body) as Map<String, dynamic>;
            requests.add(action);
            state = {...state, 'revision': (state['revision'] as int) + 1};
            switch (action['type']) {
              case 'start':
                state.addAll({
                  'status': 'interpretation',
                  'interpretation': proposal(),
                });
              case 'previewInterpretation':
                state['interpretationPreview'] = {
                  'proposalId': 'calendar-proposal',
                  'rank': 1,
                  'world': null,
                  'feedback': 'Checked provisional schedule.',
                  'changes': [],
                };
              case 'acceptInterpretation':
                state.addAll({'status': 'review', 'plan': []});
                state.remove('interpretation');
                state.remove('interpretationPreview');
              case 'accept':
                state.addAll({'status': 'answered', 'plan': []});
            }
          }
          return http.Response(jsonEncode(state), 200);
        }),
      );
      final controller = CalendarController(api: api);
      addTearDown(controller.dispose);
      await controller.loadDialogue();
      controller.setUseLlm(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalendarChatPanel(controller: controller)),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('calendar-entry')),
        'Find a half hour on Thursday morning',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(requests.first['useLlm'], isTrue);
      expect(find.byType(InterpretationReview), findsOneWidget);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Checked provisional schedule.'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('Accept changes'), findsOneWidget);
      expect(requests.map((r) => r['type']), [
        'start',
        'previewInterpretation',
        'acceptInterpretation',
      ]);
      expect(controller.canEdit, isFalse);
      await tester.tap(find.text('Accept changes'));
      await tester.pumpAndSettle();
      expect(requests.last['type'], 'accept');
    },
  );

  testWidgets(
    'Calendar interpretation clarification submits to interpreter instead of Haskell',
    (tester) async {
      Map<String, dynamic>? submitted;
      final controller = CalendarController(
        api: CalendarApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            if (request.method == 'POST') {
              submitted = jsonDecode(request.body) as Map<String, dynamic>;
            }
            return http.Response(
              jsonEncode({
                'status': 'interpretation',
                'revision': 1,
                'messages': [],
                'interpretation': proposal(questionOnly: true),
              }),
              200,
            );
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.loadDialogue();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalendarChatPanel(controller: controller)),
        ),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('calendar-entry')))
            .enabled,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('calendar-entry')),
        'Insertion please',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(submitted!['type'], 'answerInterpretation');
      expect(submitted!['proposalId'], 'calendar-proposal');
      expect(submitted!['text'], 'Insertion please');
    },
  );

  testWidgets('typed answer proposals are labeled as clarification values', (
    tester,
  ) async {
    final controller = CalendarController(
      api: CalendarApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'status': 'interpretation',
              'revision': 1,
              'messages': [],
              'interpretation': proposal(json: true),
            }),
            200,
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.loadDialogue();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarChatPanel(controller: controller)),
      ),
    );
    expect(find.text('Clarification value'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });
}
