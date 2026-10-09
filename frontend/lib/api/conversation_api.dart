import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation_state.dart';
import '../models/object_property.dart';
import '../models/world_object.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

class ConversationApi {
  ConversationApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<ConversationState> create() => _request('POST');
  Future<ConversationState> get(String id) => _request('GET', id: id);

  Future<ConversationState> applyProperty(
    String id,
    BoardPosition position,
    ObjectProperty property,
  ) => _request(
    'POST',
    id: id,
    action: 'property',
    body: {
      'position': {'x': position.x, 'y': position.y},
      'property': property.name,
    },
  );

  Future<ConversationState> place(
    String id,
    int objectId,
    BoardPosition position,
  ) => _request(
    'POST',
    id: id,
    action: 'place',
    body: {
      'objectId': objectId,
      'position': {'x': position.x, 'y': position.y},
    },
  );

  Future<ConversationState> erase(String id, BoardPosition position) =>
      _request(
        'POST',
        id: id,
        action: 'erase',
        body: {
          'position': {'x': position.x, 'y': position.y},
        },
      );

  Future<ConversationState> clear(String id) =>
      _request('POST', id: id, action: 'clear');
  Future<ConversationState> undo(String id) =>
      _request('POST', id: id, action: 'undo');

  Future<ConversationState> chat(String id, String text) =>
      _request('POST', id: id, action: 'chat', body: {'text': text});

  Future<ConversationState> clarify(String id, int objectId) =>
      _request('POST', id: id, action: 'clarify', body: {'objectId': objectId});

  Future<ConversationState> _request(
    String method, {
    String? id,
    String? action,
    Map<String, dynamic>? body,
  }) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        'conversations',
        ?id,
        ?action,
      ],
    );
    final http.Response response;
    try {
      response =
          await (method == 'POST'
                  ? _client.post(
                      uri,
                      headers: {
                        'Accept': 'application/json',
                        if (body != null) 'Content-Type': 'application/json',
                      },
                      body: body == null ? null : jsonEncode(body),
                    )
                  : _client.get(uri, headers: {'Accept': 'application/json'}))
              .timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const ApiException('Could not connect to the server.');
    }
    if (response.statusCode !=
        (method == 'POST' && action == null ? 201 : 200)) {
      throw ApiException(
        response.statusCode == 404
            ? 'Conversation not found.'
            : 'Server request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    try {
      final state = ConversationState.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      if (id != null && state.id != id) {
        throw const FormatException('Unexpected conversation');
      }
      if (action != null && state.feedback == null) {
        throw const FormatException('Missing edit feedback');
      }
      return state;
    } catch (_) {
      throw const ApiException(
        'The server returned invalid conversation data.',
      );
    }
  }

  void close() => _client.close();
}
