import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import 'roam_api.dart';

/// Hosted implementation of the same frontend contract as the local demo API.
/// Only a publishable key belongs here; authorization is enforced by Postgres RLS.
class SupabaseRoamApi extends RoamApi {
  SupabaseRoamApi({SupabaseClient? client})
    : _cloud =
          client ??
          SupabaseClient(
            projectUrl,
            publishableKey,
            authOptions: const AuthClientOptions(
              authFlowType: AuthFlowType.implicit,
            ),
          );

  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ylrgpykdsayuhwbaadij.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_5KJGmIRpEaFR-p3XcYyovQ_pO7gdbXw',
  );
  final SupabaseClient _cloud;

  @override
  bool get isSignedIn => _cloud.auth.currentSession != null;

  String get _uid {
    final user = _cloud.auth.currentUser;
    if (user == null) {
      throw const RoamApiException('Please sign in.', statusCode: 401);
    }
    return user.id;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on AuthException catch (error) {
      throw RoamApiException(
        error.message,
        statusCode: int.tryParse(error.statusCode ?? '') ?? 401,
      );
    } on PostgrestException catch (error) {
      final status = switch (error.code) {
        '42501' => 403,
        '23505' => 409,
        'P0002' || 'PGRST116' => 404,
        _ => 400,
      };
      throw RoamApiException(error.message, statusCode: status);
    } on TimeoutException {
      throw const RoamApiException(
        'The cloud server took too long to respond.',
      );
    } on http.ClientException {
      throw const RoamApiException('Unable to connect to Roam Together.');
    }
  }

  Future<Map<String, dynamic>> _session(AuthResponse auth) async {
    if (auth.session == null) {
      return {
        'confirmation_required': true,
        'user': {'id': auth.user?.id},
      };
    }
    return {
      'confirmation_required': false,
      'expires_at': auth.session!.expiresAt,
      'user': await profile(),
    };
  }

  @override
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String style = 'solo',
  }) => _guard(() async {
    if (name.trim().isEmpty ||
        name.length > 80 ||
        password.length < 12 ||
        password.length > 128) {
      throw const RoamApiException(
        'Use a name of 1–80 characters and password of 12–128 characters.',
        statusCode: 400,
      );
    }
    return _session(
      await _cloud.auth.signUp(
        email: email,
        password: password,
        data: {'name': name.trim(), 'style': style},
      ),
    );
  });

  @override
  Future<Map<String, dynamic>> login(String email, String password) => _guard(
    () async => _session(
      await _cloud.auth.signInWithPassword(email: email, password: password),
    ),
  );

  @override
  Future<void> logout() =>
      _guard(() => _cloud.auth.signOut(scope: SignOutScope.local));

  @override
  Future<Map<String, dynamic>> profile() => _guard(() async {
    final uid = _uid;
    var row = await _cloud
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row == null) {
      final metadata = _cloud.auth.currentUser?.userMetadata ?? {};
      final name = metadata['name'];
      final style = metadata['style'];
      // Metadata supplies display preferences only, never verification/authorization.
      try {
        row = await _cloud
            .from('profiles')
            .insert({
              'id': uid,
              'name': name is String && name.trim().isNotEmpty
                  ? name.substring(0, name.length > 80 ? 80 : name.length)
                  : 'Traveler',
              'style':
                  [
                    'solo',
                    'chill',
                    'adventure',
                    'luxury',
                    'budget',
                    'food',
                  ].contains(style)
                  ? style
                  : 'solo',
            })
            .select()
            .single();
      } on PostgrestException catch (error) {
        if (error.code != '23505') rethrow;
        row = await _cloud.from('profiles').select().eq('id', uid).single();
      }
    }
    return {...row, 'email': _cloud.auth.currentUser?.email};
  });

  @override
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> fields) =>
      _guard(() async {
        if (fields.keys.any((key) => !['name', 'bio', 'style'].contains(key))) {
          throw const RoamApiException(
            'Only name, bio and style can be updated.',
            statusCode: 400,
          );
        }
        await _cloud.from('profiles').update(fields).eq('id', _uid);
        return profile();
      });

  @override
  Future<Map<String, dynamic>> styles() => _guard(() async {
    final rows = await _cloud
        .from('travel_styles')
        .select('id')
        .order('position', ascending: true);
    return {'items': rows.map((row) => row['id']).toList()};
  });

  int _number(
    String? value,
    int fallback, {
    int maximum = 1000000000,
    int minimum = 0,
  }) {
    final result = value == null ? fallback : int.tryParse(value);
    if (result == null || result < minimum || result > maximum) {
      throw const RoamApiException(
        'Invalid pagination value.',
        statusCode: 400,
      );
    }
    return result;
  }

  Map<String, dynamic> _page(
    List<Map<String, dynamic>> rows,
    int limit,
    int offset,
  ) => {
    'items': rows.take(limit).toList(),
    'next_offset': rows.length > limit ? offset + limit : null,
  };

  String _pattern(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  @override
  Future<Map<String, dynamic>> trips({
    Map<String, String>? filters,
  }) => _guard(() async {
    final f = filters ?? {};
    final limit = _number(f['limit'], 20, maximum: 100, minimum: 1);
    final offset = _number(f['offset'], 0);
    var query = _cloud
        .from('trips')
        .select('*, profiles!inner(name,verified)')
        .gte('end', DateTime.now().toUtc().toIso8601String().substring(0, 10));
    if (f['mine'] == 'true') {
      query = query.eq('owner_id', _uid);
    } else {
      query = query.eq('profiles.verified', true);
    }
    for (final key in ['country', 'city', 'style']) {
      if (f[key]?.isNotEmpty ?? false) {
        query = query.ilike(key, _pattern(f[key]!));
      }
    }
    if (f['start']?.isNotEmpty ?? false) query = query.gte('end', f['start']!);
    if (f['end']?.isNotEmpty ?? false) query = query.lte('start', f['end']!);
    if (f['q']?.isNotEmpty ?? false) {
      query = query.ilike('title', '%${_pattern(f['q']!)}%');
    }
    final rows = await query
        .order('start', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + limit);
    return _page(
      rows.map((row) {
        final owner = row.remove('profiles') as Map<String, dynamic>;
        return {
          ...row,
          'owner_name': owner['name'],
          'verified': owner['verified'],
        };
      }).toList(),
      limit,
      offset,
    );
  });

  @override
  Future<Map<String, dynamic>> createTrip(Map<String, dynamic> trip) => _guard(
    () async => _cloud
        .from('trips')
        .insert({...trip, 'owner_id': _uid})
        .select()
        .single(),
  );

  @override
  Future<Map<String, dynamic>> deleteTrip(String tripId) => _guard(() async {
    final rows = await _cloud
        .from('trips')
        .delete()
        .eq('id', tripId)
        .eq('owner_id', _uid)
        .select('id');
    if (rows.isEmpty) {
      throw const RoamApiException('Your trip was not found.', statusCode: 404);
    }
    return {'deleted': true};
  });

  @override
  Future<Map<String, dynamic>> matches(String tripId, {int offset = 0}) =>
      _guard(
        () async => Map<String, dynamic>.from(
          await _cloud.rpc(
            'find_travel_matches',
            params: {'trip_id': tripId, 'page_offset': offset},
          ),
        ),
      );

  @override
  Future<Map<String, dynamic>> connections({int offset = 0}) =>
      _guard(() async {
        final start = _number('$offset', 0);
        final rows = await _cloud
            .from('connections')
            .select()
            .order('created_at', ascending: true)
            .order('id', ascending: true)
            .range(start, start + 20);
        return _page(rows, 20, start);
      });

  @override
  Future<Map<String, dynamic>> connect(String userId) => _guard(
    () async => _cloud
        .from('connections')
        .insert({'sender_id': _uid, 'recipient_id': userId})
        .select()
        .single(),
  );

  @override
  Future<Map<String, dynamic>> respond(
    String connectionId, {
    required bool accept,
  }) => _guard(
    () async => _cloud
        .from('connections')
        .update({'status': accept ? 'accepted' : 'declined'})
        .eq('id', connectionId)
        .select()
        .single(),
  );

  @override
  Future<Map<String, dynamic>> messages(String connectionId, {int after = 0}) =>
      _guard(() async {
        if (after < 0) {
          throw const RoamApiException(
            'Invalid message cursor.',
            statusCode: 400,
          );
        }
        final rows = await _cloud
            .from('messages')
            .select()
            .eq('connection_id', connectionId)
            .gt('id', after)
            .order('id', ascending: true)
            .limit(20);
        return {
          'items': rows,
          'next_after': rows.isEmpty ? after : rows.last['id'],
        };
      });

  @override
  Future<Map<String, dynamic>> sendMessage(String connectionId, String body) =>
      _guard(
        () async => _cloud
            .from('messages')
            .insert({
              'connection_id': connectionId,
              'sender_id': _uid,
              'body': body,
            })
            .select()
            .single(),
      );

  @override
  Future<Map<String, dynamic>> block(String userId) => _guard(() async {
    try {
      await _cloud.from('blocks').insert({
        'user_id': _uid,
        'blocked_id': userId,
      });
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
    return {'blocked': true};
  });

  @override
  Future<Map<String, dynamic>> report(String userId, String reason) =>
      _guard(() async {
        final row = await _cloud
            .from('reports')
            .insert({
              'reporter_id': _uid,
              'reported_id': userId,
              'reason': reason,
            })
            .select('id')
            .single();
        return {...row, 'status': 'received'};
      });

  @override
  void close() {
    unawaited(_cloud.dispose());
    super.close();
  }
}
