import 'dart:convert';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'cleanup failure after server deletion clears revoked session and reports partial failure',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final client = MockClient((r) async => r.method == 'DELETE'
        ? http.Response('{"ok":true}', 200)
        : http.Response(
            jsonEncode({
              'token': 'token-a',
              'account': {'id': 'a', 'role': 'user'}
            }),
            200));
    final account = AccountService.forTesting(client);
    await account.load();
    await account.signIn('a@example.test', 'password');
    await expectLater(
        account.deleteAccount('password',
            expectedRevision: account.sessionRevision,
            clearDeletedAccountMemory: () async =>
                throw StateError('storage unavailable')),
        throwsA(isA<AccountException>()
            .having((e) => e.message, 'message', contains('Konto usunięto'))));
    expect(account.account, isNull);
    expect(await account.headers(), isEmpty);
    account.dispose();
    client.close();
  });
  for (final body in ['{}', '{"ok":false}', '<html>success</html>']) {
    test('unconfirmed 2xx does not erase memory or session: $body', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final client = MockClient((r) async => r.method == 'DELETE'
          ? http.Response(body, 200)
          : http.Response(
              jsonEncode({
                'token': 'token-a',
                'account': {'id': 'a', 'role': 'user'}
              }),
              200));
      final account = AccountService.forTesting(client);
      await account.load();
      await account.signIn('a@example.test', 'password');
      var cleared = false;
      await expectLater(
          account.deleteAccount('password',
              expectedRevision: account.sessionRevision,
              clearDeletedAccountMemory: () async {
            cleared = true;
          }),
          throwsA(isA<AccountException>().having(
              (e) => e.message, 'message', contains('Nie potwierdzono'))));
      expect(cleared, isFalse);
      expect(account.account?['id'], 'a');
      account.dispose();
      client.close();
    });
  }
}
