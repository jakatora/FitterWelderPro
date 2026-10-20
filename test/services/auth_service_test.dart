import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const token = 'test-session-not-a-production-credential';
  const account = {
    'id': 'id',
    'email': 'welder@example.com',
    'displayName': 'Jan Kowalski',
    'role': 'user'
  };
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('Railway login stores only session token and revokes it on logout',
      () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.path);
      if (req.url.path.endsWith('/login')) {
        expect(jsonDecode(req.body)['password'], 'a-private-password');
        return http.Response(
            jsonEncode({'account': account, 'token': token}), 200);
      }
      expect(req.headers['Authorization'], 'Bearer $token');
      return http.Response('{"ok":true}', 200);
    });
    final service = AccountService.forTesting(client);
    await service.signIn('welder@example.com', 'a-private-password');
    expect(service.isAdmin, false);
    final saved = await const FlutterSecureStorage().readAll();
    expect(saved.values, [token]);
    expect(saved.toString(), isNot(contains('a-private-password')));
    expect(await service.headers(), {'Authorization': 'Bearer $token'});
    await service.signOut();
    expect(service.account, isNull);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(calls.last, endsWith('/logout'));
    client.close();
  });
  test(
      'expired session clears local identity, transport failure preserves token',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': token});
    final offline = AccountService.forTesting(
        MockClient((_) async => throw http.ClientException('offline')));
    await offline.load();
    expect(
        await const FlutterSecureStorage()
            .read(key: 'railway_account_session_v1'),
        token);
    final expired = AccountService.forTesting(MockClient(
        (_) async => http.Response('{"error":{"message":"Expired"}}', 401)));
    await expired.load();
    expect(await expired.headers(), isEmpty);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
  test('registration records accepted policy and never supplies an admin role',
      () async {
    final service = AccountService.forTesting(MockClient((req) async {
      expect(req.url.path, endsWith('/register'));
      final body = jsonDecode(req.body) as Map;
      expect(body['legalVersion'], 4);
      expect(body.containsKey('role'), false);
      return http.Response(
          jsonEncode({'account': account, 'token': token}), 201);
    }));
    await service.signIn('welder@example.com', 'a-private-password',
        displayName: 'Jan Kowalski');
    expect(service.account!['displayName'], 'Jan Kowalski');
  });
}
