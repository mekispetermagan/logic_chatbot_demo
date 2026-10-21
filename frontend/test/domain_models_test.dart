import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logic_chatbot/api/conversation_api.dart';
import 'package:logic_chatbot/models/attribute_property.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/domain.dart';
import 'package:logic_chatbot/models/world.dart';
import 'package:logic_chatbot/models/cellular_world.dart';
import 'package:logic_chatbot/models/world_object.dart';

Map<String, dynamic> fixture(WorldDomain domain) => {
  'conversationId': 'saved',
  'domain': domain.name,
  'world': jsonDecode(
    File(
      '../backend/shared/${switch (domain) {
        WorldDomain.objects => 'toy_world',
        WorldDomain.network => 'network_world',
        WorldDomain.cellular => 'cellular_world',
      }}.json',
    ).readAsStringSync(),
  ),
  'canUndo': false,
};

void main() {
  test('all domain fixtures decode without losing state', () {
    for (final domain in WorldDomain.values) {
      final state = ConversationState.fromJson(fixture(domain));
      expect(state.domain, domain);
      if (domain == WorldDomain.cellular) {
        expect(
          state.cellularWorld!.cells.where((color) => color == CellColor.black),
          hasLength(5),
        );
      } else {
        expect(state.objectWorld!.objects, hasLength(7));
      }
    }
    final network = World.fromJson(fixture(WorldDomain.network)['world']);
    final node = network.objects.first;
    expect(node.color, ObjectColor.red);
    expect(node.shape, isNull);
    expect(node.size, isNull);
    expect(node.hasPort(NetworkPort.north), isTrue);
    expect(node.hasPort(NetworkPort.east), isTrue);
    expect(node.hasPort(NetworkPort.south), isFalse);
    expect(network.objects[5].attributes, {'color': 'green'});
  });

  test('attribute maps are immutable snapshots and copies preserve ports', () {
    final source = {'color': 'red', 'north': 'north', 'east': 'east'};
    final node = WorldObject(id: 2, attributes: source);
    source['south'] = 'south';
    expect(node.hasPort(NetworkPort.south), isFalse);
    expect(() => node.attributes['south'] = 'south', throwsUnsupportedError);
    final changed = node.withProperty(const AttributeProperty('color', 'blue'));
    expect(changed.attributes, {
      'color': 'blue',
      'north': 'north',
      'east': 'east',
    });
    expect(node.color, ObjectColor.red);
    final placed = changed.withPosition(const BoardPosition(3, 4));
    expect(placed.id, 2);
    expect(placed.attributes, changed.attributes);
    expect(placed.position, const BoardPosition(3, 4));
    expect(placed.withPosition(null).position, isNull);
  });

  test('absent attributes use omission; malformed map values are rejected', () {
    expect(WorldObject.fromJson({'id': 1, 'attributes': {}}).color, isNull);
    for (final data in [
      {'id': 1},
      {'id': 1, 'attributes': null},
      {
        'id': 1,
        'attributes': {'north': null},
      },
      {
        'id': 1,
        'attributes': {'north': true},
      },
    ]) {
      expect(() => WorldObject.fromJson(data), throwsA(anything));
    }
  });

  test(
    'creation sends either domain and rejects a different returned domain',
    () async {
      for (final domain in WorldDomain.values) {
        final api = ConversationApi(
          baseUrl: Uri.parse('http://localhost:8000'),
          client: MockClient((request) async {
            expect(jsonDecode(request.body), {'domain': domain.name});
            return http.Response(jsonEncode(fixture(domain)), 201);
          }),
        );
        expect((await api.create(domain: domain)).domain, domain);
        api.close();
      }
      final api = ConversationApi(
        baseUrl: Uri.parse('http://localhost:8000'),
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(fixture(WorldDomain.objects)), 201),
        ),
      );
      await expectLater(
        api.create(domain: WorldDomain.network),
        throwsA(isA<ApiException>()),
      );
      api.close();
    },
  );

  test('network editing sends canonical attribute/value pairs', () async {
    final api = ConversationApi(
      baseUrl: Uri.parse('http://localhost:8000'),
      client: MockClient((request) async {
        expect(request.url.path, '/conversations/saved/property');
        expect(jsonDecode(request.body), {
          'position': {'x': 2, 'y': 3},
          'property': {'attribute': 'west', 'value': 'west'},
        });
        return http.Response(
          jsonEncode({
            ...fixture(WorldDomain.network),
            'feedback': 'No change',
          }),
          200,
        );
      }),
    );
    expect(
      (await api.applyProperty(
        'saved',
        const BoardPosition(2, 3),
        NetworkPort.west.property,
      )).domain,
      WorldDomain.network,
    );
    api.close();
  });
}
