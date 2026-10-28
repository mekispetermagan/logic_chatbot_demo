import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/language_examples.dart';
import 'conversation_api.dart' show ApiException;

Future<LanguageExamples> fetchLanguageExamples(
  http.Client client,
  Uri baseUrl,
  String domain,
  Duration timeout,
) async {
  final uri = baseUrl.replace(
    pathSegments: [
      ...baseUrl.pathSegments.where((part) => part.isNotEmpty),
      'languages',
      domain,
      'examples',
    ],
    query: '',
  );
  try {
    final response = await client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw const ApiException('Could not load language examples.');
    }
    final examples = LanguageExamples.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
    if (examples.domain != domain || examples.sections.isEmpty) {
      throw const FormatException('Unexpected language examples');
    }
    return examples;
  } on TimeoutException {
    throw const ApiException('Language examples took too long to load.');
  } on http.ClientException {
    throw const ApiException('Could not connect to load language examples.');
  } on FormatException {
    throw const ApiException('The server returned invalid language examples.');
  } on TypeError {
    throw const ApiException('The server returned invalid language examples.');
  }
}
