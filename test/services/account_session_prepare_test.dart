import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  AccountService service({void Function()? logout}) =>
      AccountService.forTesting(MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final id = jsonDecode(r.body)['email'];
          return http.Response(
              jsonEncode({
                'token': 'fixture-$id',
                'account': {'id': id}
              }),
              200);
        }
        logout?.call();
        return http.Response('{}', 200);
      }));
  test(
      'failed local flush leaves old identity/token and releases other prepared editors',
      () async {
    var logoutCalls = 0, released = 0;
    var frozen = false;
    final account = service(logout: () => logoutCalls++);
    await account.signIn('A', 'password');
    final revision = account.sessionRevision;
    Future<void Function()> first() async {
      frozen = true;
      return () {
        frozen = false;
        released++;
      };
    }

    Future<void Function()> fail() async =>
        throw AccountException('local write failed');
    account.addSessionPreparer(first);
    account.addSessionPreparer(fail);
    await expectLater(
        account.signIn('B', 'password'), throwsA(isA<AccountException>()));
    expect(account.account!['id'], 'A');
    expect(account.sessionRevision, revision);
    expect(await account.headers(), {'Authorization': 'Bearer fixture-A'});
    expect(frozen, isFalse);
    expect(released, 1);
    await expectLater(account.signOut(), throwsA(isA<AccountException>()));
    expect(logoutCalls, 0);
    expect(released, 2);
    account.removeSessionPreparer(fail);
    await account.signOut();
    expect(logoutCalls, 1);
    expect(account.account, isNull);
    expect(released, 3);
  });
  test(
      'forgetting identity supersedes a login while its local preparation waits',
      () async {
    final account = service();
    await account.signIn('A', 'password');
    final entered = Completer<void>(), release = Completer<void>();
    var calls = 0, unlocks = 0;
    account.addSessionPreparer(() async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return () => unlocks++;
    });
    final login = account.signIn('B', 'password');
    final rejected = expectLater(login, throwsA(isA<AccountException>()));
    await entered.future;
    expect(account.account!['id'], 'A');
    final forget = account.forgetSession();
    release.complete();
    await rejected;
    await forget;
    expect(account.account, isNull);
    expect(unlocks, 2);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
  test(
      'server revocation clears identity without waiting for a local save guard',
      () async {
    final account = AccountService.forTesting(MockClient((r) async =>
        r.url.path.endsWith('/login')
            ? http.Response('{"token":"fixture-A","account":{"id":"A"}}', 200)
            : http.Response('{"error":{"message":"revoked"}}', 401)));
    await account.signIn('A', 'password');
    var calls = 0;
    account.addSessionPreparer(() async {
      calls++;
      throw AccountException('must not block revocation');
    });
    await expectLater(account.saveProfile({'displayName': 'x'}),
        throwsA(isA<AccountException>()));
    expect(account.account, isNull);
    expect(calls, 0);
  });
}
