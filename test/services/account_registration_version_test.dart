import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/legal/legal_texts.dart' as rendered;
import 'package:cut_list_app/legal/legal_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'registration records the same version as the displayed policy; login does not fabricate new consent',
      () async {
    final requests = <http.Request>[];
    final account = AccountService.forTesting(MockClient((r) async {
      requests.add(r);
      return http.Response(
          '{"token":"fixture-token","account":{"id":"fixture-account"}}', 200);
    }));
    expect(kLegalVersion, rendered.kLegalVersion);
    expect(kLegalUpdated, rendered.kLegalUpdated);
    await account.signIn('fixture@example.com', 'fixture-password',
        displayName: 'Fixture user');
    expect(requests.last.url.path, endsWith('/register'));
    final registration = jsonDecode(requests.last.body) as Map;
    expect(registration['legalVersion'], rendered.kLegalVersion);
    expect(registration.keys.toSet(),
        {'email', 'password', 'displayName', 'legalVersion'});
    await account.signIn('fixture@example.com', 'fixture-password');
    expect(requests.last.url.path, endsWith('/login'));
    expect(jsonDecode(requests.last.body).containsKey('legalVersion'), isFalse);
    expect((await const FlutterSecureStorage().readAll()).values.join(),
        isNot(contains('fixture-password')));
  });
}
