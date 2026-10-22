import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_drawing_dao.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useTestDatabase();
  for (final scenario in [(false, false), (true, false), (false, true)]) {
    final (fail, logout) = scenario;
    testWidgets(
        'pending ISO name is saved for old owner before login; storage failure blocks transition: $fail logout: $logout',
        (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      final account = AccountService.forTesting(MockClient((r) async {
        if (r.url.path.endsWith('/logout')) return http.Response('{}', 200);
        final id = jsonDecode(r.body)['email'];
        return http.Response(
            jsonEncode({
              'token': 'fixture-$id',
              'account': {'id': id}
            }),
            200);
      }));
      AccountService.instance = account;
      Future<Object?> switchToB() async {
        var completed = false;
        Object? failure;
        unawaited((logout ? account.signOut() : account.signIn('B', 'password'))
            .then((_) {
          completed = true;
        }, onError: (Object error, StackTrace _) {
          failure = error;
          completed = true;
        }));
        for (var i = 0; i < 20 && !completed; i++) {
          await flushTestDatabase(t);
          await t.pump(const Duration(milliseconds: 10));
        }
        expect(completed, isTrue, reason: 'session preparation must finish');
        return failure;
      }

      await t.runAsync(() async {
        await account.load();
        await (await AppDatabase.get()).delete('iso_drawings');
        await account.signIn('A', 'password');
      });
      await mount(t, interpret: (_) async => throw StateError('native only'));
      await say(t, 'Narysuj rura metr w prawo');
      await flushTestDatabase(t);
      final controller = IsoNotebookController.active!;
      final before = (await t.runAsync(() => IsoDrawingDao().latest()))!;
      await t.tap(find.byTooltip('Dotknij, aby zmienić nazwę projektu'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('iso-sketch-name')), 'Pending A');
      await t.tap(find.widgetWithText(ElevatedButton, 'OK'));
      await t.pumpAndSettle();
      expect(controller.sketchName, 'Pending A');
      expect(
          (await t.runAsync(() => IsoDrawingDao().latest()))!.name, before.name,
          reason: 'The autosave debounce must still be pending');
      if (fail) {
        await t.runAsync(() async => (await AppDatabase.get()).execute(
            "CREATE TRIGGER fail_session_flush BEFORE UPDATE ON iso_drawings BEGIN SELECT RAISE(FAIL, 'fixture write failure'); END"));
      }
      try {
        final failure = await switchToB();
        if (fail) {
          expect(failure, isA<AccountException>());
          expect(account.account!['id'], 'A');
          expect(identical(IsoNotebookController.active, controller), isTrue);
          expect(controller.summary, isNotNull,
              reason: 'failed transition must release the editor');
          await t.runAsync(() async => (await AppDatabase.get())
              .execute('DROP TRIGGER fail_session_flush'));
          expect(await switchToB(), isNull);
        } else {
          expect(failure, isNull);
        }
        await settle(t);
        expect(account.account?['id'], logout ? null : 'B');
        expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
        final aRows = await t.runAsync(() async => (await AppDatabase.get())
            .query('iso_drawings',
                where: 'id=? AND owner_scope=?',
                whereArgs: [before.id, 'account:A']));
        expect(aRows!.single['name'], 'Pending A');
        var returned = false;
        unawaited(account.signIn('A', 'password').then((_) => returned = true));
        for (var i = 0; i < 20 && !returned; i++) {
          await flushTestDatabase(t);
          await t.pump(const Duration(milliseconds: 10));
        }
        expect(returned, isTrue);
        await settle(t);
        expect(IsoNotebookController.active!.sketchName, 'Pending A');
        expect(t.takeException(), isNull);
      } finally {
        await t.runAsync(() async => (await AppDatabase.get())
            .execute('DROP TRIGGER IF EXISTS fail_session_flush'));
      }
    });
  }
}
