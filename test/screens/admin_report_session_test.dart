import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../test_prefs.dart';

http.Response reports(String text) => http.Response(
    jsonEncode({
      'items': [
        {
          'id': 1,
          'kind': 'notUnderstood',
          'occurrences': 1,
          'text': text,
          'receivedAt': '2026-10-22',
          'app': 'fixture',
          'platform': 'android',
          'status': 'new'
        }
      ],
    }),
    200);

Future<AccountService> fixture(
    WidgetTester t, Future<http.Response> Function(http.Request) handler,
    {String user = 'adminA'}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final previous = AccountService.instance;
  final client = MockClient((r) async {
    if (r.url.path.endsWith('/login')) {
      final id = jsonDecode(r.body)['email'] as String;
      return http.Response(
          jsonEncode({
            'token': 'fixture-token-$id',
            'account': {
              'id': id,
              'email': '$id@example.test',
              'displayName': id,
              'role': id.startsWith('admin') ? 'admin' : 'user'
            },
          }),
          200);
    }
    return handler(r);
  });
  final service = AccountService.forTesting(client);
  AccountService.instance = service;
  addTearDown(() {
    AccountService.instance = previous;
    client.close();
  });
  await t.runAsync(() => service.signIn(user, 'fixture-password'));
  return service;
}

Future<void> mount(WidgetTester t) async {
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: AdminReportsScreen())));
  await flush(t);
}

Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('late report status cannot show an error in the next session',
      (t) async {
    final pending = Completer<http.Response>();
    var updates = 0;
    final service = await fixture(t, (r) {
      if (r.method == 'PUT') {
        updates++;
        return pending.future;
      }
      return Future.value(reports(
          r.headers['Authorization'] == 'Bearer fixture-token-adminA'
              ? 'Old private report'
              : 'Current private report'));
    });
    await mount(t);
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('W realizacji').last);
    await flush(t);
    expect(updates, 1);
    await t.runAsync(() => service.signIn('adminB', 'fixture-password'));
    await flush(t);
    pending.complete(http.Response('{"ok":true}', 200));
    await flush(t);
    expect(find.text('Old private report'), findsNothing);
    expect(find.text('Current private report'), findsOneWidget);
    expect(find.text('Nie zapisano statusu.'), findsNothing);
  });
  testWidgets('account form refreshes when authenticated identity changes',
      (t) async {
    seedFreshInstall();
    final service =
        await fixture(t, (_) async => http.Response('{"ok":true}', 200));
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: const MaterialApp(home: AccountScreen())));
    for (var i = 0; i < 3; i++) {
      await flush(t);
    }
    Iterable<String> texts() => t
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text);
    expect(texts(), contains('adminA'));
    await t.runAsync(() => service.signIn('welder', 'fixture-password'));
    await flush(t);
    expect(texts(), contains('welder'));
    expect(texts(), isNot(contains('adminA')));
    await t.runAsync(service.forgetSession);
    await flush(t);
    expect(texts(), isNot(contains('welder')));
  });
  testWidgets('ordinary account cannot fetch or display admin reports',
      (t) async {
    var calls = 0;
    await fixture(t, (_) async {
      calls++;
      return reports('Private fixture');
    }, user: 'welder');
    await mount(t);
    expect(calls, 0);
    expect(find.text('Dostęp tylko dla administratora.'), findsOneWidget);
    expect(find.text('Private fixture'), findsNothing);
  });
  testWidgets('loaded private reports disappear immediately on logout',
      (t) async {
    final service = await fixture(t, (_) async => reports('Private fixture'));
    await mount(t);
    expect(find.text('Private fixture'), findsOneWidget);
    await t.runAsync(service.forgetSession);
    await t.pump();
    expect(find.text('Private fixture'), findsNothing);
    expect(find.text('Dostęp tylko dla administratora.'), findsOneWidget);
  });
  testWidgets('late report response is hidden from subsequent ordinary account',
      (t) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final service = await fixture(t, (_) {
      calls++;
      return pending.future;
    });
    await mount(t);
    expect(calls, 1);
    await t.runAsync(() => service.signIn('welder', 'fixture-password'));
    pending.complete(reports('Old private report'));
    await flush(t);
    expect(find.text('Old private report'), findsNothing);
    expect(find.text('Dostęp tylko dla administratora.'), findsOneWidget);
    expect(calls, 1);
  });
  testWidgets(
      'old admin response cannot replace reports in newer admin session',
      (t) async {
    final pending = Completer<http.Response>();
    final service = await fixture(
        t,
        (r) => r.headers['Authorization'] == 'Bearer fixture-token-adminA'
            ? pending.future
            : Future.value(reports('Current private report')));
    await mount(t);
    await t.runAsync(() => service.signIn('adminB', 'fixture-password'));
    await flush(t);
    expect(find.text('Current private report'), findsOneWidget);
    pending.complete(reports('Old private report'));
    await flush(t);
    expect(find.text('Old private report'), findsNothing);
    expect(find.text('Current private report'), findsOneWidget);
    expect(find.textContaining('Nie udało się pobrać'), findsNothing);
  });
}
