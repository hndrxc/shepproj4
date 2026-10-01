import 'dart:io';

import 'package:shepproj4/services/supabase_roam_api.dart';

/// Read-only live verification: never creates users, sends email, or writes data.
Future<void> main() async {
  final api = SupabaseRoamApi();
  try {
    final result = await api.styles();
    final styles = result['items'] as List;
    if (styles.length != 6 || !styles.contains('food')) {
      throw StateError('Unexpected cloud catalog: $styles');
    }
    stdout.writeln(
      'PASS: Flutter/Dart client read ${styles.length} styles over HTTPS from ${SupabaseRoamApi.projectUrl}',
    );
  } finally {
    api.close();
  }
}
