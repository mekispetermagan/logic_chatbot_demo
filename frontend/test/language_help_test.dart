import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/calendar_api.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/widgets/chat_panel.dart';
import 'package:logic_chatbot/widgets/language_help_dialog.dart';

Map<String, dynamic> examples(String domain) => {
  'domain': domain,
  'languageVersion': domain == 'calendar' ? 'calendar-v1' : '$domain-v2',
  'sections': [
    for (final title in [
      'Primitive commands',
      'Primitive questions',
      'Conceptual commands',
      'Conceptual questions',
    ])
      {
        'title': title,
        'examples': List.generate(
          8,
          (i) => [
            {'text': '$title concrete sentence $i.'},
          ],
        ),
      },
  ],
};

void main() {
  test(
    'both API clients use their backend base path and selected domain',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(examples(request.url.pathSegments[2])),
          200,
        );
      });
      final api = ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000/api'),
        client: client,
      );
      for (final domain in WorldDomain.values) {
        expect((await api.examples(domain)).domain, domain.name);
      }
      final calendar = CalendarApi(
        baseUrl: Uri.parse('http://localhost:8000/api'),
        client: client,
      );
      expect((await calendar.examples()).domain, 'calendar');
      expect(requests.map((r) => r.url.path), [
        '/api/languages/objects/examples',
        '/api/languages/network/examples',
        '/api/languages/cellular/examples',
        '/api/languages/calendar/examples',
      ]);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      client.close();
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'all reference forms share one highlight color in $brightness',
      (tester) async {
        final body = examples('objects');
        (body['sections'] as List).first['examples'] = [
          [
            {'text': 'Move '},
            {'text': 'it', 'reference': true},
            {'text': ' next to '},
            {'text': 'the object with color red', 'reference': true},
            {'text': '.'},
          ],
          [
            {'text': 'What is the color of '},
            {'text': '#3', 'reference': true},
            {'text': '?'},
          ],
        ];
        final api = ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient(
            (request) async => http.Response(jsonEncode(body), 200),
          ),
        );
        addTearDown(api.close);
        final theme = ThemeData(brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ChatPanel(
                messages: const [],
                canSend: true,
                sending: false,
                onSend: (_) async => true,
                onRefresh: () {},
                loadExamples: () => api.examples(WorldDomain.objects),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Controlled English examples'));
        await tester.pumpAndSettle();
        final texts = tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        );
        final spans = [
          for (final text in texts) ...?text.textSpan?.children,
        ].whereType<TextSpan>().toList();
        final highlighted = spans
            .where((span) => span.style?.color != null)
            .toList();
        expect(highlighted.map((span) => span.text), [
          'it',
          'the object with color red',
          '#3',
        ]);
        expect(highlighted.map((span) => span.style!.color).toSet(), {
          theme.colorScheme.primary,
        });
        expect(spans.firstWhere((span) => span.text == 'Move ').style, isNull);
        expect(
          texts.first.textSpan!.toPlainText(),
          'Move it next to the object with color red.',
        );
      },
    );
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'shared help modal scrolls at width $width without sending chat or losing draft',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var sends = 0;
        var loads = 0;
        final api = CalendarApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            loads++;
            expect(request.url.path, '/languages/calendar/examples');
            return http.Response(jsonEncode(examples('calendar')), 200);
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatPanel(
                messages: const [],
                canSend: true,
                sending: false,
                onSend: (_) async {
                  sends++;
                  return true;
                },
                onRefresh: () {},
                loadExamples: api.examples,
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'unfinished draft');
        await tester.tap(find.byTooltip('Controlled English examples'));
        await tester.pumpAndSettle();
        expect(find.byType(LanguageHelpDialog), findsOneWidget);
        expect(find.text('Primitive commands'), findsOneWidget);
        final list = find.byKey(const ValueKey('language-examples-list'));
        await tester.scrollUntilVisible(
          find.text('Conceptual questions concrete sentence 7.'),
          400,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Conceptual questions concrete sentence 7.').hitTestable(),
          findsOneWidget,
        );
        expect(loads, 1);
        expect(sends, 0);
        await tester.tap(find.byTooltip('Close examples'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'unfinished draft',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('help loading failure offers retry without adding a chat turn', (
    tester,
  ) async {
    var attempts = 0;
    final api = CalendarApi(
      baseUrl: Uri.parse('http://localhost:8000'),
      client: MockClient((request) async {
        attempts++;
        return attempts == 1
            ? http.Response('{}', 503)
            : http.Response(jsonEncode(examples('calendar')), 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            messages: const [],
            canSend: false,
            composerEnabled: false,
            sending: true,
            onSend: (_) async => throw StateError('No submission expected'),
            onRefresh: () {},
            loadExamples: api.examples,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Controlled English examples'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Could not load language examples.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Primitive commands'), findsOneWidget);
    expect(attempts, 2);
  });
}
