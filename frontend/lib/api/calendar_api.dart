import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/calendar_event.dart';
import '../models/calendar_week.dart';
import 'conversation_api.dart' show ApiException;

class CalendarApi {
  CalendarApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 40),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

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

  void close() => _client.close();
}
