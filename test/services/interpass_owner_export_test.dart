import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/services/interpass_export.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';

const channel = MethodChannel('plugins.flutter.io/path_provider');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountService account;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final previous = AccountService.instance;
    final client = MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
          }),
          200);
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await account.load();
    await account.signIn('A', 'fixture-password');
  });
  final weld = InterpassWeld.blank(id: 'private', now: DateTime(2026, 10, 22))
      .copyWith(weldNo: 'A_PRIVATE');
  test('stale PDF export is refused before platform I/O', () async {
    final owner = await LocalRecordOwner.capture();
    await account.signIn('B', 'fixture-password');
    await expectLater(
        InterpassExport.sharePdf(weld,
            english: false,
            unit: InterpassUnit.c,
            validateOwner: owner.requireCurrent),
        throwsA(isA<AccountException>()));
  });
  test(
      'account transition while PDF requests a temp directory prevents creation and share',
      () async {
    final owner = await LocalRecordOwner.capture();
    final temp =
        await Directory.systemTemp.createTemp('fwp_interpass_export_owner_');
    final entered = Completer<void>(), release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        entered.complete();
        return release.future;
      }
      return null;
    });
    final operation = InterpassExport.sharePdf(weld,
        english: false,
        unit: InterpassUnit.c,
        validateOwner: owner.requireCurrent);
    final rejected = expectLater(operation, throwsA(isA<AccountException>()));
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('B', 'fixture-password');
    release.complete(temp.path);
    await rejected;
    expect(await temp.list().toList(), isEmpty);
    await temp.delete();
  });
}
