import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An API or transport failure suitable for presentation by the UI.
class RoamApiException implements Exception {
  const RoamApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Shared integration layer for the Roam Together UI.
///
/// Tokens stay in memory. Call [close] when the application disposes this client.
/// Configure API_BASE_URL with a trailing /api/ path for the target device.
class RoamApi {
  RoamApi({Uri? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? Uri.parse(defaultBaseUrl),
      _client = client ?? http.Client() {
    if (!this.baseUrl.hasAuthority ||
        !['http', 'https'].contains(this.baseUrl.scheme) ||
        !this.baseUrl.path.endsWith('/') ||
        this.baseUrl.hasQuery ||
        this.baseUrl.hasFragment) {
      throw ArgumentError(
        'baseUrl must be an absolute HTTP(S) URL ending in /',
      );
    }
  }

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080/api/',
  );

  final Uri baseUrl;
  final http.Client _client;
  String? _token;

  bool get isSignedIn => _token != null;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = baseUrl.resolve(path).replace(queryParameters: query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    late http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const RoamApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const RoamApiException(
        'Unable to connect to the Roam Together server.',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw RoamApiException(
        'The server returned an invalid response.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded['error'] : null;
      final message = error is Map ? error['message'] : null;
      if (response.statusCode == 401 && !path.startsWith('auth/')) {
        _token = null;
      }
      throw RoamApiException(
        message is String ? message : 'The request failed.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RoamApiException('The server returned an invalid response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _authenticate(
    String action,
    Map<String, dynamic> body,
  ) async {
    final result = await _request('POST', 'auth/$action', body: body);
    final token = result['token'];
    if (token is! String || token.isEmpty) {
      throw const RoamApiException(
        'The server did not return a session token.',
      );
    }
    _token = token;
    return result;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String style = 'solo',
  }) => _authenticate('register', {
    'name': name,
    'email': email,
    'password': password,
    'style': style,
  });

  Future<Map<String, dynamic>> login(String email, String password) =>
      _authenticate('login', {'email': email, 'password': password});

  Future<void> logout() async {
    try {
      await _request('POST', 'auth/logout');
    } on RoamApiException catch (error) {
      if (error.statusCode != 401) rethrow;
    }
    _token = null;
  }

  Future<Map<String, dynamic>> profile() => _request('GET', 'me');
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> fields) =>
      _request('PATCH', 'me', body: fields);
  Future<Map<String, dynamic>> styles() => _request('GET', 'styles');
  Future<Map<String, dynamic>> trips({Map<String, String>? filters}) =>
      _request('GET', 'trips', query: filters);
  Future<Map<String, dynamic>> createTrip(Map<String, dynamic> trip) =>
      _request('POST', 'trips', body: trip);
  Future<Map<String, dynamic>> deleteTrip(String tripId) =>
      _request('DELETE', 'trips/${Uri.encodeComponent(tripId)}');
  Future<Map<String, dynamic>> matches(String tripId, {int offset = 0}) =>
      _request(
        'GET',
        'matches',
        query: {'trip_id': tripId, 'offset': '$offset'},
      );
  Future<Map<String, dynamic>> connections({int offset = 0}) =>
      _request('GET', 'connections', query: {'offset': '$offset'});
  Future<Map<String, dynamic>> connect(String userId) =>
      _request('POST', 'connections', body: {'recipient_id': userId});
  Future<Map<String, dynamic>> respond(
    String connectionId, {
    required bool accept,
  }) => _request(
    'PATCH',
    'connections/${Uri.encodeComponent(connectionId)}',
    body: {'status': accept ? 'accepted' : 'declined'},
  );
  Future<Map<String, dynamic>> messages(String connectionId, {int after = 0}) =>
      _request(
        'GET',
        'connections/${Uri.encodeComponent(connectionId)}/messages',
        query: {'after': '$after'},
      );
  Future<Map<String, dynamic>> sendMessage(String connectionId, String body) =>
      _request(
        'POST',
        'connections/${Uri.encodeComponent(connectionId)}/messages',
        body: {'body': body},
      );
  Future<Map<String, dynamic>> block(String userId) =>
      _request('POST', 'blocks', body: {'user_id': userId});
  Future<Map<String, dynamic>> report(String userId, String reason) =>
      _request('POST', 'reports', body: {'user_id': userId, 'reason': reason});

  void close() => _client.close();
}
