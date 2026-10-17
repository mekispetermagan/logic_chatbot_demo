import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation_state.dart';
import '../models/attribute_property.dart';
import '../models/domain.dart';
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

  Future<ConversationState> create({
    WorldDomain domain = WorldDomain.objects,
  }) => _request('POST', body: {'domain': domain.name}, expectedDomain: domain);
  Future<ConversationState> get(String id) => _request('GET', id: id);

  Future<ConversationState> applyProperty(
    String id,
    BoardPosition position,
    AttributeProperty property,
  ) => _request(
    'POST',
    id: id,
    action: 'property',
    body: {
      'position': {'x': position.x, 'y': position.y},
      'property': property.toJson(),
    },
  );

  Future<ConversationState> setPorts(
    String id,
    BoardPosition position,
    List<NetworkPort> ports,
  ) => _request(
    'POST',
    id: id,
    action: 'ports',
    body: {
      'position': {'x': position.x, 'y': position.y},
      'ports': ports.map((port) => port.name).toList(),
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

  Future<ConversationState> chat(
    String id,
    String text, {
    bool useLlm = false,
  }) => _request(
    'POST',
    id: id,
    action: 'chat',
    body: {'text': text, 'useLlm': useLlm},
    requestTimeout: useLlm ? const Duration(seconds: 90) : null,
  );

  Future<ConversationState> clarifySquare(String id, BoardPosition position) =>
      _request(
        'POST',
        id: id,
        action: 'clarify',
        body: {
          'position': {'x': position.x, 'y': position.y},
        },
      );

  Future<ConversationState> clarify(String id, int objectId) =>
      _request('POST', id: id, action: 'clarify', body: {'objectId': objectId});

  Future<ConversationState> previewInterpretation(
    String id,
    String proposalId,
    int rank,
  ) => _request(
    'POST',
    id: id,
    action: 'interpretations/$proposalId/preview',
    body: {'rank': rank},
  );

  Future<ConversationState> acceptInterpretation(
    String id,
    String proposalId,
    int rank,
  ) => _request(
    'POST',
    id: id,
    action: 'interpretations/$proposalId/accept',
    body: {'rank': rank},
  );

  Future<ConversationState> rejectInterpretation(
    String id,
    String proposalId,
  ) => _request('POST', id: id, action: 'interpretations/$proposalId/reject');

  Future<ConversationState> answerInterpretation(
    String id,
    String proposalId,
    String text,
  ) => _request(
    'POST',
    id: id,
    action: 'interpretations/$proposalId/answer',
    body: {'text': text},
    requestTimeout: const Duration(seconds: 90),
  );

  Future<ConversationState> _request(
    String method, {
    String? id,
    String? action,
    Map<String, dynamic>? body,
    WorldDomain? expectedDomain,
    Duration? requestTimeout,
  }) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
        'conversations',
        ?id,
        if (action != null) ...action.split('/'),
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
              .timeout(requestTimeout ?? timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const ApiException('Could not connect to the server.');
    }
    if (response.statusCode !=
        (method == 'POST' && action == null ? 201 : 200)) {
      String? detail;
      try {
        final value = jsonDecode(utf8.decode(response.bodyBytes));
        if (value is Map<String, dynamic> && value['detail'] is String) {
          detail = value['detail'] as String;
        }
      } catch (_) {}
      throw ApiException(
        detail ??
            (response.statusCode == 404
                ? 'Conversation not found.'
                : 'Server request failed (${response.statusCode}).'),
        statusCode: response.statusCode,
      );
    }
    try {
      final state = ConversationState.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      if (expectedDomain != null && state.domain != expectedDomain) {
        throw const FormatException('Unexpected domain');
      }
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
