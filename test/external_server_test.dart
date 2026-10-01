import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shepproj4/services/roam_api.dart';

void main() {
  test(
    'Flutter client uses a separate Python HTTP server and persistent data',
    () async {
      final directory = await Directory.systemTemp.createTemp('roam-external-');
      addTearDown(() => directory.delete(recursive: true));
      final server = await Process.start('python3', [
        '-u',
        '-c',
        'import sys; from backend.server import App, make_server; '
            's = make_server(App(sys.argv[1]), port=0); '
            'print(s.server_port, flush=True); s.serve_forever()',
        '${directory.path}/roam.sqlite3',
      ]);
      final errors = StringBuffer();
      final stderr = server.stderr.transform(utf8.decoder).listen(errors.write);
      addTearDown(() async {
        server.kill();
        await server.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            server.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        await stderr.cancel();
      });
      final port = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      final api = RoamApi(baseUrl: Uri.parse('http://127.0.0.1:$port/api/'));
      final second = RoamApi(baseUrl: api.baseUrl);
      addTearDown(api.close);
      addTearDown(second.close);
      final styles = await api.styles();
      expect(styles['items'], contains('food'));
      await api.register(
        name: 'External Server Test',
        email: 'external@example.test',
        password: 'test-password-123',
      );
      final start = DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String()
          .substring(0, 10);
      final trip = await api.createTrip({
        'title': 'External server trip',
        'country': 'Japan',
        'city': 'Tokyo',
        'start': start,
        'end': start,
        'style': 'food',
      });
      await second.login('external@example.test', 'test-password-123');
      final saved = await second.trips(filters: {'mine': 'true'});
      expect((saved['items'] as List).single['id'], trip['id']);
      expect(await File('${directory.path}/roam.sqlite3').exists(), isTrue);
      expect(errors.toString(), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
