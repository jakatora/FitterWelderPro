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
