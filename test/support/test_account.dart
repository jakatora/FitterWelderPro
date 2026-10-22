import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/user_profile.dart';

Future<void> seedGuestAccount() async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance = AccountService.forTesting(
      MockClient((_) async => http.Response('{}', 500)));
  await AccountService.instance.load();
}

/// Explicit account fixture for chat tests. No request reaches the network.
Future<void> seedSignedInAccount() async {
  FlutterSecureStorage.setMockInitialValues({});
  final name =
      (await UserProfileService.instance.get())?.fullName ?? 'Jan Nowak';
  final client = MockClient((_) async => http.Response(
      jsonEncode({
        'account': {
          'id': 'test-account',
          'displayName': name,
          'role': 'user',
          'email': 'fixture@example.com'
        },
        'token': 'test-token-no-production-access',
      }),
      200));
  AccountService.instance = AccountService.forTesting(client);
  await AccountService.instance
      .signIn('fixture@example.com', 'fixture-password');
}

/// Fresh offline guest identity for tests which now open account-scoped data.
void useGuestAccount() {
  setUp(() {
    final previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
    final client =
        MockClient((_) async => throw StateError('Unexpected account HTTP'));
    final account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });
  });
}
