import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';

http.Response identity(String id) => http.Response(
    jsonEncode({
      'token': 'fixture-token-$id',
      'account': {'id': id, 'displayName': id, 'role': 'user'},
    }),
    200);

class DelayedTokenStorage extends FlutterSecureStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (value == 'fixture-token-A') {
      started.complete();
      await release.future;
    }
    await super.write(key: key, value: value);
  }
}

class DelayedOwnerStorage extends FlutterSecureStorage {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (key == 'railway_account_local_owner_v1' &&
        value != null &&
        jsonDecode(value)['id'] == 'A' &&
        !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('superseded owner-cache write cannot bind old owner to the new token',
      () async {
    final storage = DelayedOwnerStorage();
    final service = AccountService.forTesting(
        MockClient((r) async => identity(jsonDecode(r.body)['email'])),
        storage: storage);
    final old = service.signIn('A', 'fixture-password');
    final rejected = expectLater(old, throwsA(isA<AccountException>()));
    await storage.started.future;
    final next = service.signIn('B', 'fixture-password');
    storage.release.complete();
    await rejected;
    await next;
    final owner = jsonDecode(
        (await storage.read(key: 'railway_account_local_owner_v1'))!);
    expect(owner, {'id': 'B', 'token': 'fixture-token-B'});
    expect(service.localOwnerId, 'B');
    expect(await storage.read(key: 'railway_account_session_v1'),
        'fixture-token-B');
  });
  for (final code in [200, 401]) {
    test('late profile retry $code cannot replace or revoke a newer login',
        () async {
      FlutterSecureStorage.setMockInitialValues(
          {'railway_account_session_v1': 'fixture-old-token'});
      var reads = 0;
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final service = AccountService.forTesting(MockClient((request) async {
        if (request.url.path.endsWith('/login')) return identity('B');
        if (++reads == 1) {
          return http.Response('{"error":{"message":"Offline"}}', 503);
        }
        started.complete();
        return pending.future;
      }));
      await service.load();
      expect(service.needsIdentityRefresh, isTrue);
      final retry = service.refreshIdentity();
      final rejected = expectLater(retry, throwsA(isA<AccountException>()));
      await started.future;
      await service.signIn('B', 'fixture-password');
      final revision = service.sessionRevision;
      pending.complete(code == 200
          ? identity('A')
          : http.Response('{"error":{"message":"Expired"}}', 401));
      await rejected;
      expect(service.account!['id'], 'B');
      expect(service.sessionRevision, revision);
      expect(
          await service.headers(), {'Authorization': 'Bearer fixture-token-B'});
      expect(
          await const FlutterSecureStorage()
              .read(key: 'railway_account_session_v1'),
          'fixture-token-B');
    });
  }
  for (final replace in [false, true]) {
    test('queued token write respects ${replace ? 'new login' : 'logout'}',
        () async {
      final storage = DelayedTokenStorage();
      final service = AccountService.forTesting(
          MockClient((r) async => identity(jsonDecode(r.body)['email'])),
          storage: storage);
      final first = service.signIn('A', 'fixture-password');
      final rejected = expectLater(first, throwsA(isA<AccountException>()));
      await storage.started.future;
      final next = replace
          ? service.signIn('B', 'fixture-password')
          : service.forgetSession();
      storage.release.complete();
      await rejected;
      await next;
      expect(service.account?['id'], replace ? 'B' : null);
      expect(await storage.read(key: 'railway_account_session_v1'),
          replace ? 'fixture-token-B' : null);
    });
  }
  for (final code in [200, 401]) {
    test('late authenticated $code response cannot affect newer account',
        () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final service = AccountService.forTesting(MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return identity(jsonDecode(r.body)['email']);
        }
        started.complete();
        return pending.future;
      }));
      await service.signIn('A', 'fixture-password');
      final old = service.saveProfile({'displayName': 'Old profile'});
      final rejected = expectLater(old, throwsA(isA<AccountException>()));
      await started.future;
      await service.signIn('B', 'fixture-password');
      final revision = service.sessionRevision;
      pending.complete(code == 200
          ? identity('A-old')
          : http.Response('{"error":{"message":"Expired"}}', 401));
      await rejected;
      expect(service.account!['id'], 'B');
      expect(service.sessionRevision, revision);
      expect(
          await service.headers(), {'Authorization': 'Bearer fixture-token-B'});
      expect(
          await const FlutterSecureStorage()
              .read(key: 'railway_account_session_v1'),
          'fixture-token-B');
    });
  }
  test('late restored identity cannot overwrite a fresh login', () async {
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'fixture-old-token'});
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final service = AccountService.forTesting(MockClient((r) async {
      if (r.url.path.endsWith('/login')) return identity('B');
      started.complete();
      return pending.future;
    }));
    final restoring = service.load();
    await started.future;
    await service.signIn('B', 'fixture-password');
    pending.complete(identity('A'));
    await restoring;
    expect(service.account!['id'], 'B');
  });
  test('forgetting session cancels in-flight sign-in', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final service = AccountService.forTesting(MockClient((_) async {
      started.complete();
      return pending.future;
    }));
    final login = service.signIn('A', 'fixture-password');
    final rejected = expectLater(login, throwsA(isA<AccountException>()));
    await started.future;
    await service.forgetSession();
    pending.complete(identity('A'));
    await rejected;
    expect(service.account, isNull);
    expect(await service.headers(), isEmpty);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
  test('latest sign-in wins when login responses arrive out of order',
      () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final service = AccountService.forTesting(MockClient((r) async {
      if (jsonDecode(r.body)['email'] == 'B') return identity('B');
      started.complete();
      return pending.future;
    }));
    final first = service.signIn('A', 'fixture-password');
    final rejected = expectLater(first, throwsA(isA<AccountException>()));
    await started.future;
    await service.signIn('B', 'fixture-password');
    pending.complete(identity('A'));
    await rejected;
    expect(service.account!['id'], 'B');
    expect(
        await const FlutterSecureStorage()
            .read(key: 'railway_account_session_v1'),
        'fixture-token-B');
  });
  test('late logout cannot clear a newer login', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final service = AccountService.forTesting(MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        return identity(jsonDecode(r.body)['email']);
      }
      started.complete();
      return pending.future;
    }));
    await service.signIn('A', 'fixture-password');
    final logout = service.signOut();
    final rejected = expectLater(logout, throwsA(isA<AccountException>()));
    await started.future;
    await service.signIn('B', 'fixture-password');
    pending.complete(http.Response('{"ok":true}', 200));
    await rejected;
    expect(service.account!['id'], 'B');
    expect(
        await service.headers(), {'Authorization': 'Bearer fixture-token-B'});
  });
}
