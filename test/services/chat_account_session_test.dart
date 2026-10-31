import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';

class _DelayedIdentity extends InMemorySharedPreferencesStore {
  _DelayedIdentity() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.fitter_device_id' && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE'
    });
    PremiumService.instance.resetForTest();
  });
  tearDown(() => ApiClient.instance.debugSetClient(null));
  for (final operation in ['list', 'post', 'report']) {
    test('queued chat $operation sends nothing after account change', () async {
      final account = AccountService.forTesting(MockClient((request) async {
        final id = jsonDecode(request.body)['email'];
        return http.Response(
            jsonEncode({
              'token': 'fixture-$id',
              'account': {'id': id, 'displayName': id}
            }),
            200);
      }));
      AccountService.instance = account;
      await account.signIn('A', 'password');
      SharedPreferences.setMockInitialValues({});
      final disk = _DelayedIdentity();
      SharedPreferencesStorePlatform.instance = disk;
      PremiumService.instance.resetForTest();
      final requests = <http.Request>[];
      ApiClient.instance.debugSetClient(MockClient((request) async {
        requests.add(request);
        return http.Response('{"messages":[]}', 200);
      }));
      final Future<dynamic> call = operation == 'list'
          ? ChatService.instance.listMessages('general')
          : operation == 'post'
              ? ChatService.instance
                  .postMessage(room: 'general', text: 'from A')
              : ChatService.instance.report(1);
      final rejected = expectLater(call, throwsA(isA<AccountException>()));
      await disk.entered.future;
      await account.signIn('B', 'password');
      disk.release.complete();
      await rejected;
      expect(requests, isEmpty);
      expect(account.account!['id'], 'B');
    });
    for (final status in [200, 401]) {
      test('late chat $operation $status never returns A data or revokes B',
          () async {
        final account = AccountService.forTesting(MockClient((r) async {
          final id = jsonDecode(r.body)['email'];
          return http.Response(
              jsonEncode({
                'token': 'fixture-$id',
                'account': {'id': id, 'displayName': id}
              }),
              200);
        }));
        AccountService.instance = account;
        await account.signIn('A', 'password');
        final entered = Completer<void>(), pending = Completer<http.Response>();
        ApiClient.instance.debugSetClient(MockClient((request) {
          expect(request.headers['Authorization'], 'Bearer fixture-A');
          entered.complete();
          return pending.future;
        }));
        final Future<dynamic> call = operation == 'list'
            ? ChatService.instance.listMessages('general')
            : operation == 'post'
                ? ChatService.instance
                    .postMessage(room: 'general', text: 'from A')
                : ChatService.instance.report(1);
        final rejected = expectLater(call, throwsA(isA<AccountException>()));
        await entered.future;
        await account.signIn('B', 'password');
        pending.complete(http.Response(
            jsonEncode(status == 401
                ? {
                    'error': {
                      'code': 'ACCOUNT_SESSION_INVALID',
                      'message': 'revoked'
                    }
                  }
                : {'messages': []}),
            status));
        await rejected;
        expect(account.account!['id'], 'B');
        expect(await account.headers(), {'Authorization': 'Bearer fixture-B'});
      });
    }
  }
}
