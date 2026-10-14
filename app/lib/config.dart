import 'package:flutter/foundation.dart';

/// Pass at build time: flutter build web --dart-define=API_BASE=https://api.example.com/api/v1
const String _apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000/api/v1');
const _loopback = {'localhost', '127.0.0.1', '10.0.2.2'}; // 10.0.2.2 = host machine from Android emulator

String get apiBase {
  // Release builds must talk to a remote backend over TLS only; plain http is allowed for loopback testing.
  final uri = Uri.parse(_apiBase);
  if (kReleaseMode && uri.scheme != 'https' && !_loopback.contains(uri.host)) {
    throw StateError('API_BASE must use https:// in release builds');
  }
  return _apiBase;
}
