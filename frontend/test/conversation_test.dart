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
import 'package:logic_chatbot/storage/conversation_id_store.dart';
import 'package:logic_chatbot/widgets/conversation_world_panel.dart';

class MemoryStore implements ConversationIdStore {
  MemoryStore([this.id]);
  String? id;
  bool failWrite = false;
  @override
  Future<String?> read() async => id;
  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('storage unavailable');
    id = value;
  }
}

void main() {
  final world = jsonDecode(
    File('../backend/shared/toy_world.json').readAsStringSync(),
  );
  Map<String, dynamic> state([String id = 'saved']) => {
    'conversationId': id,
    'world': world,
    'canUndo': false,
  };
  http.Response response([String id = 'saved', int status = 200]) =>
      http.Response(jsonEncode(state(id)), status);
  ConversationController controller(MemoryStore store, MockClient client) =>
      ConversationController(
        api: ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000/api'),
          client: client,
        ),
        store: store,
      );

  test(
    'creates and persists once, then resumes server world including partial objects',
    () async {
      final store = MemoryStore();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return response('saved', request.method == 'POST' ? 201 : 200);
      });
      final subject = controller(store, client);
      addTearDown(subject.dispose);
      await subject.load();
      expect(store.id, 'saved');
      expect(subject.conversation!.world.objects.length, 7);
      expect(subject.conversation!.world.objects[2].color, isNull);
      expect(subject.conversation!.world.objects[5].position, isNull);
      await subject.load();
      expect(requests.map((r) => r.method), ['POST', 'GET']);
      expect(requests.first.url.path, '/api/conversations');
      expect(requests.last.url.path, '/api/conversations/saved');
      expect(requests.first.body, isEmpty);
    },
  );

  test('only missing conversations are replaced', () async {
    for (final status in [404, 500]) {
      final store = MemoryStore('old');
      final methods = <String>[];
      final subject = controller(
        store,
        MockClient((request) async {
          methods.add(request.method);
          return request.method == 'GET'
              ? http.Response('', status)
              : response('new', 201);
        }),
      );
      await subject.load();
      expect(methods, status == 404 ? ['GET', 'POST'] : ['GET']);
      expect(store.id, status == 404 ? 'new' : 'old');
      expect(subject.error == null, status == 404);
      subject.dispose();
    }
  });

  test('retry preserves ID after network failure', () async {
    final store = MemoryStore('saved');
    var calls = 0;
    final subject = controller(
      store,
      MockClient((request) async {
        expect(request.method, 'GET');
        if (++calls == 1) throw http.ClientException('offline');
        return response();
      }),
    );
    addTearDown(subject.dispose);
    await subject.load();
    expect(subject.error, contains('connect'));
    expect(store.id, 'saved');
    await subject.load();
    expect(subject.error, isNull);
    expect(subject.conversation!.id, 'saved');
  });

  test('failed persistence retries without another creation', () async {
    final store = MemoryStore()..failWrite = true;
    var calls = 0;
    final subject = controller(
      store,
      MockClient((_) async {
        calls++;
        return response('new', 201);
      }),
    );
    addTearDown(subject.dispose);
    await subject.load();
    expect(subject.error, isNotNull);
    store.failWrite = false;
    await subject.load();
    expect(calls, 1);
    expect(store.id, 'new');
  });

  test(
    'overlapping loads coalesce and disposal prevents persistence',
    () async {
      final pending = Completer<http.Response>();
      final store = MemoryStore();
      var calls = 0;
      final subject = controller(
        store,
        MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
      final loading = subject.load();
      await Future<void>.delayed(Duration.zero);
      await subject.load();
      expect(calls, 1);
      subject.dispose();
      pending.complete(response('new', 201));
      await loading;
      expect(store.id, isNull);
    },
  );

  test('rejects malformed state and mismatching conversation ID', () async {
    for (final payload in ['{}', jsonEncode(state('other'))]) {
      final api = ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient((_) async => http.Response(payload, 200)),
      );
      await expectLater(api.get('saved'), throwsA(isA<ApiException>()));
      api.close();
    }
  });

  testWidgets('loading, error/retry and read-only world states', (
    tester,
  ) async {
    Widget panel({
      bool loading = false,
      String? error,
      ConversationState? conversation,
      VoidCallback? retry,
    }) => MaterialApp(
      home: Scaffold(
        body: ConversationWorldPanel(
          conversation: conversation,
          loading: loading,
          error: error,
          onRetry: retry ?? () {},
        ),
      ),
    );
    await tester.pumpWidget(panel(loading: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    var retries = 0;
    await tester.pumpWidget(panel(error: 'Offline', retry: () => retries++));
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    await tester.pumpWidget(
      panel(conversation: ConversationState.fromJson(state())),
    );
    final selector = tester.widget<SegmentedButton<ObjectProperty>>(
      find.byType(SegmentedButton<ObjectProperty>),
    );
    expect(selector.onSelectionChanged, isNull);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(find.text('World editing will be available soon.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
