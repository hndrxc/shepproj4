import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shepproj4/main.dart';
import 'package:shepproj4/services/roam_api.dart';

void main() {
  testWidgets('entry screen renders only styles returned by the server', (
    tester,
  ) async {
    final api = RoamApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/styles');
        return http.Response('{"items":["food"]}', 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(MainApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Food & culture'), findsOneWidget);
    expect(find.text('Adventure & outdoors'), findsNothing);
  });

  testWidgets('server failure offers retry and recovers', (tester) async {
    var calls = 0;
    final api = RoamApi(
      client: MockClient((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('offline');
        return http.Response('{"items":["adventure"]}', 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(MainApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    await tester.ensureVisible(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Adventure & outdoors'), findsOneWidget);
    expect(calls, 2);
  });
}
