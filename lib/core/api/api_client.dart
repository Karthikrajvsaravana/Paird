import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/token_store.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

/// Thin JSON client for the Paird API.
///
/// * Attaches the in-memory access token.
/// * On a 401 it refreshes the session once (single-flight, so concurrent
///   requests share one refresh) and retries the request.
/// * If the refresh fails, [onSessionExpired] is called and the error is
///   rethrown so screens can stop loading.
class ApiClient {
  ApiClient({
    required this.tokenStore,
    http.Client? httpClient,
    String? baseUrl,
    this.timeout = AppConfig.requestTimeout,
  })  : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final TokenStore tokenStore;
  final http.Client _http;
  final String baseUrl;
  final Duration timeout;

  String? _accessToken;

  /// Friendly connection error. Debug builds add the address that was tried,
  /// because a physical phone cannot use the emulator default (10.0.2.2).
  ApiException _networkError({bool timeout = false}) {
    var message = timeout
        ? 'The server took too long to respond. Check your connection.'
        : "Can't reach Paird. Check your internet connection.";
    if (kDebugMode) {
      message += '\n\nServer: $baseUrl';
      if (AppConfig.usingEmulatorDefault && baseUrl.contains('10.0.2.2')) {
        message += '\nOn a physical phone, run with --dart-define=API_BASE_URL=http://<your-PC-LAN-IP>:8001/api/v1';
      }
    }
    return ApiException(code: timeout ? 'timeout' : 'network_error', message: message);
  }
  Completer<bool>? _refreshing;
  void Function()? onSessionExpired;

  bool get hasAccessToken => _accessToken != null;

  /// Headers for authenticated image requests (Image.network).
  Map<String, String> get imageHeaders => {if (_accessToken != null) 'Authorization': 'Bearer $_accessToken'};

  Future<void> setSession({required String access, required String refresh}) async {
    _accessToken = access;
    await tokenStore.saveRefreshToken(refresh);
  }

  Future<void> clearSession() async {
    _accessToken = null;
    await tokenStore.clear();
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalized');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        if (value.isNotEmpty) params[key] = value.join(',');
      } else if (value.toString().isNotEmpty) {
        params[key] = value.toString();
      }
    });
    return uri.replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Unauthenticated POST (sign in, sign up, password reset).
  Future<dynamic> postPublic(String path, Object body) => _send('POST', path, body: body, authenticated: false);

  Future<dynamic> upload(String path, {required String field, required List<int> bytes, required String filename}) {
    return _send('POST', path, multipart: (field: field, bytes: bytes, filename: filename));
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
    ({String field, List<int> bytes, String filename})? multipart,
    bool isRetry = false,
  }) async {
    if (baseUrl.isEmpty) {
      throw ApiException(code: 'not_configured', message: 'This build has no server configured (API_BASE_URL).');
    }
    if (authenticated && _accessToken == null && !isRetry) {
      final refreshed = await refreshSession();
      if (!refreshed) {
        onSessionExpired?.call();
        throw ApiException(statusCode: 401, code: 'not_authenticated', message: 'Please sign in again.');
      }
    }

    final http.BaseRequest request;
    if (multipart != null) {
      final r = http.MultipartRequest(method, _uri(path, query));
      r.files.add(http.MultipartFile.fromBytes(multipart.field, multipart.bytes, filename: multipart.filename));
      request = r;
    } else {
      final r = http.Request(method, _uri(path, query));
      if (body != null) {
        r.headers['Content-Type'] = 'application/json';
        r.body = jsonEncode(body);
      }
      request = r;
    }
    request.headers['Accept'] = 'application/json';
    if (authenticated && _accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw _networkError(timeout: true);
    } on http.ClientException {
      throw _networkError();
    }

    if (response.statusCode == 401 && authenticated && !isRetry) {
      final refreshed = await refreshSession();
      if (refreshed) {
        return _send(method, path, body: body, query: query, multipart: multipart, isRetry: true);
      }
      onSessionExpired?.call();
    }

    final decoded = _decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    throw ApiException.fromResponse(response.statusCode, decoded);
  }

  dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// Exchange the stored refresh token for a new token pair.
  /// Returns false if there is no valid session.
  Future<bool> refreshSession() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;
    final completer = Completer<bool>();
    _refreshing = completer;
    () async {
      try {
        final refresh = await tokenStore.readRefreshToken();
        if (refresh == null) {
          completer.complete(false);
          return;
        }
        final response = await _http
            .post(
              _uri('/auth/refresh/'),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({'refresh': refresh}),
            )
            .timeout(timeout);
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          await setSession(access: data['access'] as String, refresh: (data['refresh'] ?? refresh) as String);
          completer.complete(true);
        } else if (response.statusCode == 401 || response.statusCode == 400) {
          await clearSession();
          completer.complete(false);
        } else {
          completer.completeError(ApiException.fromResponse(response.statusCode, null));
        }
      } on TimeoutException {
        completer.completeError(_networkError(timeout: true));
      } on http.ClientException {
        completer.completeError(_networkError());
      } catch (e) {
        completer.completeError(ApiException(message: 'Could not restore your session.'));
      } finally {
        _refreshing = null;
      }
    }();
    return completer.future;
  }

  String absoluteUrl(String pathOrUrl) => pathOrUrl.startsWith('http') ? pathOrUrl : '$baseUrl$pathOrUrl';
}
