import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// JSON client with JWT stored in the platform keychain/keystore and transparent token refresh.
class Api {
  Api._();
  static final Api I = Api._();
  final _store = const FlutterSecureStorage();
  final _http = http.Client();
  String? _access, _refresh;
  void Function()? onSessionExpired;

  Future<bool> restore() async {
    _access = await _store.read(key: 'access');
    _refresh = await _store.read(key: 'refresh');
    return _refresh != null;
  }

  Future<void> saveTokens(Map data) async {
    _access = data['access'];
    _refresh = data['refresh'] ?? _refresh;
    await _store.write(key: 'access', value: _access);
    if (_refresh != null) await _store.write(key: 'refresh', value: _refresh);
  }

  Future<void> clear() async {
    final r = _refresh;
    _access = _refresh = null;
    await _store.deleteAll();
    if (r != null) {
      try {
        await _http.post(Uri.parse('$apiBase/auth/logout/'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh': r}));
      } catch (_) {}
    }
  }

  Future<bool> _doRefresh() async {
    if (_refresh == null) return false;
    final res = await _http.post(Uri.parse('$apiBase/auth/refresh/'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh': _refresh}));
    if (res.statusCode != 200) return false;
    await saveTokens(jsonDecode(res.body));
    return true;
  }

  Future<dynamic> get(String path, [Map<String, String>? q]) => _send('GET', path, query: q);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body: body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Multipart upload (field name "file").
  Future<dynamic> upload(String path, List<int> bytes, String filename, {bool retried = false}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase$path'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mime(filename)));
    if (_access != null) req.headers['Authorization'] = 'Bearer $_access';
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
    if (res.statusCode == 401 && !retried && await _doRefresh()) return upload(path, bytes, filename, retried: true);
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, _errorText(data));
    return data;
  }

  MediaType _mime(String f) {
    final ext = f.split('.').last.toLowerCase();
    return ext == 'pdf' ? MediaType('application', 'pdf') : MediaType('image', ext == 'png' ? 'png' : 'jpeg');
  }

  Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query, bool retried = false}) async {
    var uri = Uri.parse('$apiBase$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json';
    if (_access != null) req.headers['Authorization'] = 'Bearer $_access';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    if (res.statusCode == 401 && !retried && _refresh != null) {
      if (await _doRefresh()) return _send(method, path, body: body, query: query, retried: true);
      await clear();
      onSessionExpired?.call();
    }
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, _errorText(data));
    return data;
  }

  String _errorText(dynamic d) {
    if (d is Map) {
      if (d['detail'] != null) return d['detail'].toString();
      return d.entries.map((e) => e.value is List ? (e.value as List).join(' ') : e.value.toString()).join('\n');
    }
    if (d is List) return d.join('\n');
    return 'Something went wrong';
  }
}
