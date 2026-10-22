import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'dart:convert';
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
  testWidgets('summary waits for owner and persisted sheet restoration',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final reply = Completer<http.Response>(), entered = Completer<void>();
    FlutterSecureStorage.setMockInitialValues({
      'railway_account_session_v1': 'fixture-A',
      'railway_account_local_owner_v1':
          jsonEncode({'token': 'fixture-A', 'id': 'A'}),
    });
    final account = AccountService.forTesting(MockClient((_) {
      entered.complete();
      return reply.future;
    }));
    AccountService.instance = account;
    await t.runAsync(() async {
      await const FlutterSecureStorage()
          .write(key: 'railway_account_session_v1', value: 'fixture-A');
      expect(
          await const FlutterSecureStorage()
              .read(key: 'railway_account_session_v1'),
          'fixture-A');
      final db = await AppDatabase.get();
      await db.delete('iso_drawings');
      await db.insert('iso_drawings', {
        'id': 'waiting-sheet',
        'owner_scope': 'account:A',
        'name': 'Loaded A',
        'created_at': 1,
        'updated_at': 2,
        'json': jsonEncode({
          'format': 1,
          'name': 'Loaded A',
          'items': [
            {
              'kind': 'seg',
              'tool': 'pipe',
              'a': [64, 100],
              'b': [128, 100],
              'calc': {'iso': '1000', 'ref': 'centreToCentre', 'deducts': []}
            }
          ]
        })
      });
      unawaited(account.load());
    });
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: IsoNotebookScreen())));
    for (var i = 0; i < 8 && !entered.isCompleted; i++) {
      await flushTestDatabase(t);
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(entered.isCompleted, isTrue);
    expect(IsoNotebookController.active, isNotNull);
    expect(IsoNotebookController.active!.summary, isNull);
    reply.complete(http.Response(
        jsonEncode({
          'account': {'id': 'A'}
        }),
        200));
    await settle(t);
    expect(IsoNotebookController.active!.summary!.pipeCount, 1);
    expect(IsoNotebookController.active!.sketchId, 'waiting-sheet');
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'mounted ISO switches sheets by account and old controller cannot edit new account',
      (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    final account = AccountService.forTesting(MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
          }),
          200);
    }));
    AccountService.instance = account;
    await t.runAsync(() async {
      await account.load();
      await (await AppDatabase.get()).delete('iso_drawings');
      await account.signIn('A', 'fixture-password');
    });
    await mount(t, interpret: (_) async => throw StateError('native commands'));
    await say(t, 'Narysuj rura metr w prawo');
    await settle(t);
    await flushTestDatabase(t);
    final old = IsoNotebookController.active!;
    final oldRevision = old.revision;
    final a = (await t.runAsync(() => IsoDrawingDao().latest()))!;
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    final b = IsoNotebookController.active!;
    expect(identical(old, b), isFalse);
    expect(b.summary!.pipeCount, 0);
    expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
    await expectLater(
        old.setRootGap(9, expectedRevision: oldRevision), throwsStateError);
    await say(t, 'Narysuj rura 500 mm w prawo');
    await settle(t);
    await flushTestDatabase(t);
    final bRecord = (await t.runAsync(() => IsoDrawingDao().latest()))!;
    expect(bRecord.id, isNot(a.id));
    await t.runAsync(() => account.signIn('A', 'fixture-password'));
    await settle(t);
    expect(IsoNotebookController.active!.sketchId, a.id);
    expect(IsoNotebookController.active!.summary!.pipeCount, 1);
    expect((await t.runAsync(() => IsoDrawingDao().latest()))!.json, a.json);
    expect(t.takeException(), isNull);
  });
}
