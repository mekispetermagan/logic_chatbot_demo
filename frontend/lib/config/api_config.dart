import 'package:flutter/foundation.dart';

class ApiConfig {
  static Uri get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    final fallback = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
    final uri = Uri.parse(configured.isEmpty ? fallback : configured);
    if (!uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('API_BASE_URL must be an HTTP or HTTPS URL');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }
}
