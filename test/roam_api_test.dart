import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shepproj4/services/roam_api.dart';

void main() {
  test('login attaches bearer token; logout clears session', () async {
    final requests = <http.Request>[];
    final api = RoamApi(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"token":"test-token","user":{"id":"a"}}', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    await api.login('alex@example.test', 'a-password-123');
    expect(api.isSignedIn, isTrue);
    await api.profile();
    expect(requests.last.headers['Authorization'], 'Bearer test-token');
    await api.logout();
    expect(api.isSignedIn, isFalse);
    await api.styles();
    expect(requests.last.headers.containsKey('Authorization'), isFalse);
  });

  test('trip filters and messaging payloads use the API contract', () async {
    late http.Request last;
    final api = RoamApi(
      baseUrl: Uri.parse('http://localhost:8080/api/'),
      client: MockClient((request) async {
        last = request;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    await api.trips(filters: {'city': 'New York City', 'style': 'food'});
    expect(last.url.path, '/api/trips');
    expect(last.url.queryParameters['city'], 'New York City');
    await api.sendMessage('abc123', 'Hello!');
    expect(last.method, 'POST');
    expect(last.url.path, '/api/connections/abc123/messages');
    expect(jsonDecode(last.body), {'body': 'Hello!'});
    await api.respond('abc123', accept: false);
    expect(jsonDecode(last.body), {'status': 'declined'});
    await api.messages('abc123', after: 8);
    expect(last.url.queryParameters['after'], '8');
  });

  test('API errors retain status and expired sessions are cleared', () async {
    final api = RoamApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"token":"expired-token"}', 200);
        }
        return http.Response(
          '{"error":{"status":401,"message":"Session expired"}}',
          401,
        );
      }),
    );
    addTearDown(api.close);
    await api.login('alex@example.test', 'a-password-123');
    await expectLater(
      api.profile(),
      throwsA(
        isA<RoamApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', 'Session expired'),
      ),
    );
    expect(api.isSignedIn, isFalse);
  });

  test(
    'invalid server payload and network failures become API exceptions',
    () async {
      for (final payload in ['not json', '[]', '{}']) {
        final api = RoamApi(
          client: MockClient((_) async => http.Response(payload, 200)),
        );
        await expectLater(
          api.login('a@example.test', 'a-password-123'),
          throwsA(isA<RoamApiException>()),
        );
        api.close();
      }
      final api = RoamApi(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      addTearDown(api.close);
      await expectLater(api.profile(), throwsA(isA<RoamApiException>()));
    },
  );

  test('base URL must end with slash and have no query', () {
    expect(
      () => RoamApi(baseUrl: Uri.parse('http://localhost/api')),
      throwsArgumentError,
    );
    expect(
      () => RoamApi(baseUrl: Uri.parse('http://localhost/api/?x=1')),
      throwsArgumentError,
    );
  });
}
