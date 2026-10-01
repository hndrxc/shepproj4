import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:shepproj4/services/roam_api.dart';
import 'package:shepproj4/services/supabase_roam_api.dart';

void main() {
  test('cloud catalog uses the hosted Data API and publishable key', () async {
    final cloud = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/travel_styles');
        expect(request.headers['apikey'], 'sb_publishable_test');
        expect(
          request.url.queryParameters['order'],
          startsWith('position.asc'),
        );
        return http.Response(
          '[{"id":"food"},{"id":"adventure"}]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final api = SupabaseRoamApi(client: cloud);
    addTearDown(api.close);
    expect((await api.styles())['items'], ['food', 'adventure']);
  });

  test('RLS denial is surfaced as a forbidden API error', () async {
    final cloud = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': '42501',
            'message': 'Verification required',
            'details': null,
            'hint': null,
          }),
          403,

          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final api = SupabaseRoamApi(client: cloud);
    addTearDown(api.close);
    await expectLater(
      api.matches('some-trip'),
      throwsA(
        isA<RoamApiException>().having(
          (error) => error.statusCode,
          'status',
          403,
        ),
      ),
    );
  });

  test('profile and writes require a signed-in user', () async {
    final api = SupabaseRoamApi(
      client: SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.profile(),
      throwsA(
        isA<RoamApiException>().having(
          (error) => error.statusCode,
          'status',
          401,
        ),
      ),
    );
    await expectLater(
      api.createTrip({'title': 'Trip'}),
      throwsA(
        isA<RoamApiException>().having(
          (error) => error.statusCode,
          'status',
          401,
        ),
      ),
    );
    await expectLater(
      api.updateProfile({'verified': true}),
      throwsA(isA<RoamApiException>()),
    );
  });

  test(
    'new account waits for confirmation when Supabase returns no session',
    () async {
      final cloud = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/signup');
          return http.Response(
            jsonEncode({
              'id': '12345678-1234-1234-1234-123456789abc',
              'aud': 'authenticated',
              'email': 'test@example.test',
              'created_at': '2026-09-30T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final api = SupabaseRoamApi(client: cloud);
      addTearDown(api.close);
      final result = await api.register(
        name: 'Test',
        email: 'test@example.test',
        password: 'test-password-123',
      );
      expect(result['confirmation_required'], isTrue);
      expect(api.isSignedIn, isFalse);
    },
  );
}
