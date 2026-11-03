import 'dart:async';
import 'dart:convert';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<T> settleOperation<T>(WidgetTester t, Future<T> operation) async {
  var done = false;
  T? value;
  Object? failure;
  final observed = operation.then((v) {
    value = v;
    done = true;
  }, onError: (Object e) {
    failure = e;
    done = true;
  });
  for (var i = 0; i < 100 && !done; i++) {
    await t.pump(const Duration(milliseconds: 5));
  }
  expect(done, isTrue);
  await observed;
  if (failure != null) throw failure!;
  return value as T;
}

void main() {
  for (final status in [200, 401, 202]) {
    testWidgets('account deletion $status changes only the correct memory',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      CorrectionMemoryStore.instance.resetForTest();
      final previous = AccountService.instance;
      final pendingDelete = Completer<http.Response>();
      final client = MockClient((r) async {
        if (r.method == 'DELETE') {
          if (status == 202) return pendingDelete.future;
          return http.Response(
              status == 200
                  ? '{"ok":true}'
                  : jsonEncode({
                      'error': {'message': 'Bad password'}
                    }),
              status);
        }
        final email = (jsonDecode(r.body) as Map)['email'] as String;
        return http.Response(
            jsonEncode({
              'token': 'token-$email',
              'account': {
                'id': email,
                'email': email,
                'displayName': 'Fixture user',
                'role': 'user'
              }
            }),
            200);
      });
      final account = AccountService.forTesting(client);
      AccountService.instance = account;
      addTearDown(() {
        AccountService.instance = previous;
        account.dispose();
        client.close();
      });
      const entry = RememberedCorrection(
          question: 'TIG aluminium', correction: 'Chodzi o aluminium');
      await settleOperation(t, account.load());
      await settleOperation(t, CorrectionMemoryStore.instance.remember(entry));
      await settleOperation(
          t, account.signIn('a@example.test', 'fixture-password'));
      await settleOperation(t, CorrectionMemoryStore.instance.remember(entry));
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(AppLanguageScope(
          controller: AppLanguageController(AppLanguage.pl),
          child: const MaterialApp(home: AccountScreen())));
      await t.pumpAndSettle();
      final delete = find.text('Usuń konto');
      await t.ensureVisible(delete);
      await t.tap(delete);
      await t.pumpAndSettle();
      await t.tap(find.text('Usuń').last);
      if (status == 202) {
        await t.pump();
        await settleOperation(
            t, account.signIn('b@example.test', 'fixture-password'));
        await settleOperation(
            t, CorrectionMemoryStore.instance.remember(entry));
        pendingDelete.complete(http.Response('{"ok":true}', 200));
      }
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      if (status == 200) {
        expect(account.account, isNull);
        expect(
            (await settleOperation(t, CorrectionMemoryStore.instance.list())),
            hasLength(1)); // guest unaffected
        // Recreate the account identity to inspect its local partition.
        await settleOperation(
            t, account.signIn('a@example.test', 'fixture-password'));
        expect(
            (await settleOperation(t, CorrectionMemoryStore.instance.list())),
            isEmpty);
      } else if (status == 202) {
        expect(account.account?['id'], 'b@example.test');
        expect(
            (await settleOperation(t, CorrectionMemoryStore.instance.list())),
            hasLength(1));
        await settleOperation(
            t, account.signIn('a@example.test', 'fixture-password'));
        expect(
            (await settleOperation(t, CorrectionMemoryStore.instance.list())),
            isEmpty);
      } else {
        expect(account.account, isNotNull);
        expect(find.text('Bad password'), findsOneWidget);
        expect(
            (await settleOperation(t, CorrectionMemoryStore.instance.list())),
            hasLength(1));
      }
      expect(t.takeException(), isNull);
    });
  }
}
