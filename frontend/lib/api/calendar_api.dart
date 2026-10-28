import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/calendar_event.dart';
import '../models/language_examples.dart';
import 'language_help_api.dart';
import '../models/calendar_week.dart';
import 'conversation_api.dart' show ApiException;

class CalendarWriteException extends ApiException {
  const CalendarWriteException(
    super.message, {
    super.statusCode,
    this.outcomeUnknown = false,
    this.eventId,
  });
  final bool outcomeUnknown;
  final String? eventId;
}

class CalendarApi {
  CalendarApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 40),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<LanguageExamples> examples() =>
      fetchLanguageExamples(_client, baseUrl, 'calendar', timeout);

  Future<List<CalendarEvent>> events(CalendarWeek week) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((part) => part.isNotEmpty),
        'calendar',
        'events',
      ],
      queryParameters: {
        'timeMin': week.start.toUtc().toIso8601String(),
        'timeMax': week.end.toUtc().toIso8601String(),
        'timeZone': calendarTimeZone,
      },
    );
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The calendar took too long to respond.');
    } on http.ClientException {
      throw const ApiException('Could not connect to the calendar backend.');
    }
    if (response.statusCode != 200) {
      String? detail;
      try {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is Map<String, dynamic> && json['detail'] is String) {
          detail = json['detail'] as String;
        }
      } catch (_) {}
      throw ApiException(
        detail ?? 'Calendar request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return [
        for (final value in body['events'] as List)
          ?CalendarEvent.fromJson(value as Map<String, dynamic>),
      ];
    } catch (_) {
      throw const ApiException('The server returned invalid calendar data.');
    }
  }

  Future<Map<String, dynamic>> dialogue([Map<String, dynamic>? action]) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((part) => part.isNotEmpty),
        'calendar',
        'dialogue',
      ],
    );
    try {
      final response =
          await (action == null
                  ? _client.get(uri, headers: {'Accept': 'application/json'})
                  : _client.post(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(action),
                    ))
              .timeout(const Duration(minutes: 5));
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw ApiException(
          value is Map && value['detail'] is String
              ? value['detail'] as String
              : 'Calendar dialogue failed.',
          statusCode: response.statusCode,
        );
      }
      if (value is! Map<String, dynamic> ||
          value['revision'] is! int ||
          value['status'] is! String) {
        throw const ApiException('Invalid Calendar dialogue response.');
      }
      return value;
    } on TimeoutException {
      throw const ApiException(
        'Calendar request timed out. Refresh dialogue status before any retry.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Calendar connection lost. Refresh dialogue status before any retry.',
      );
    } on FormatException {
      throw const ApiException('Invalid Calendar dialogue response.');
    }
  }

  void close() => _client.close();

  Future<void> create(Map<String, dynamic> fields) =>
      _write('POST', null, fields);
  Future<void> update(String id, Map<String, dynamic> fields) =>
      _write('PATCH', id, fields);
  Future<void> delete(String id) => _write('DELETE', id, null);

  Future<void> _write(
    String method,
    String? id,
    Map<String, dynamic>? body,
  ) async {
    final uri = baseUrl.replace(
      pathSegments: [
        ...baseUrl.pathSegments.where((part) => part.isNotEmpty),
        'calendar',
        'events',
        ?id,
      ],
    );
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 100));
    } on TimeoutException {
      throw CalendarWriteException(
        'The calendar request timed out. Refresh before trying again.',
        outcomeUnknown: true,
        eventId: id,
      );
    } on http.ClientException {
      throw CalendarWriteException(
        'The calendar response was lost. Refresh before trying again.',
        outcomeUnknown: true,
        eventId: id,
      );
    }
    Map<String, dynamic>? data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode != (method == 'POST' ? 201 : 200)) {
      throw CalendarWriteException(
        data?['detail'] is String
            ? data!['detail'] as String
            : 'Calendar write failed.',
        statusCode: response.statusCode,
        outcomeUnknown:
            data?['outcomeUnknown'] == true || response.statusCode >= 500,
        eventId: data?['eventId'] is String ? data!['eventId'] as String : id,
      );
    }
    final event = data?['event'];
    final valid =
        (data?['verified']) == true &&
        (method == 'DELETE'
            ? (data?['deleted']) == true && (data?['eventId']) == id
            : event is Map &&
                  event['id'] is String &&
                  (id == null || event['id'] == id));
    if (!valid) {
      throw CalendarWriteException(
        'The calendar change could not be confirmed. Refresh before trying again.',
        outcomeUnknown: true,
        eventId: id,
      );
    }
  }
}
