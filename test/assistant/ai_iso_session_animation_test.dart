import 'dart:async';
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
      'session transition finishes full animated command, freezes new work and saves only A',
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
      await account.signIn('A', 'password');
    });
    await mount(t, interpret: (_) async => throw StateError('native only'));
    await say(t, 'Otwórz zeszyt ISO');
    final c = IsoNotebookController.active!;
    expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
    final drawing = c.draw(const [
      IsoPipe(lengthMm: 1000, dir: IsoDir.right),
      IsoTurn(toDir: IsoDir.up),
      IsoPipe(lengthMm: 2000)
    ], stepDelay: const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 20));
    expect(c.isBusy, isTrue);
    var checkedFreeze = false;
    account.addSessionPreparer(() async {
      expect(c.summary, isNull);
      await expectLater(
          c.setRootGap(9, expectedRevision: c.revision), throwsStateError);
      checkedFreeze = true;
      return () {};
    });
    var switched = false;
    Object? failure;
    unawaited(account.signIn('B', 'password').then((_) => switched = true,
        onError: (Object error, StackTrace _) {
      failure = error;
      switched = true;
    }));
    for (var i = 0; i < 30 && !switched; i++) {
      await flushTestDatabase(t);
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(switched, isTrue);
    expect(failure, isNull);
    expect(checkedFreeze, isTrue);
    await t.pump(const Duration(seconds: 3));
    await settle(t);
    await drawing;
    expect(account.account!['id'], 'B');
    expect(await t.runAsync(() => IsoDrawingDao().latest()), isNull);
    final rows = await t.runAsync(() async => (await AppDatabase.get()).query(
        'iso_drawings',
        where: 'owner_scope=?',
        whereArgs: ['account:A']));
    final pipes =
        ((jsonDecode(rows!.single['json'] as String) as Map)['items'] as List)
            .where((r) => r['tool'] == 'pipe');
    expect(pipes.map((r) => r['calc']['iso']), ['1000', '2000']);
    expect(IsoNotebookController.active!.summary!.pipeCount, 0);
    expect(t.takeException(), isNull);
  });
}
