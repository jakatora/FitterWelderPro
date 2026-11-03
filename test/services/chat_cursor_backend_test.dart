import 'dart:io';

import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/api_client.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_account.dart';

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useGuestAccount();
  final server = Platform.environment['FWP_CONTRACT_SERVER'];

  test('actual client pages through local backend by message id', () async {
    final base = Uri.parse(server!);
    expect(base.scheme, 'http');
    expect(base.host, '127.0.0.1');
    SharedPreferences.setMockInitialValues({});
    PremiumService.instance.resetForTest();
    await AccountService.instance.load();
    final actual = HttpOverrides.runWithHttpOverrides(
        () => IOClient(HttpClient()), _LocalHttpOverrides());
    addTearDown(actual.close);
    ApiClient.instance.debugSetClient(MockClient((request) {
      expect(request.url.path, '/api/fitter/chat/messages');
      return actual.get(base.replace(
          path: request.url.path, query: request.url.query), headers: request.headers);
    }));
    addTearDown(() => ApiClient.instance.debugSetClient(null));

    final first = await ChatService.instance.listMessageBatch('general', afterId: 0, limit: 100);
    expect(first.supportsIdCursor, isTrue);
    expect(first.messages, hasLength(100));
    final second = await ChatService.instance.listMessageBatch('general',
        afterId: first.messages.last.id, limit: 100);
    expect(second.supportsIdCursor, isTrue);
    expect(second.messages, hasLength(25));
    final ids = [...first.messages, ...second.messages].map((m) => m.id).toList();
    expect(ids.toSet(), hasLength(125));
    expect(ids, orderedEquals([...ids]..sort()));
  }, skip: server == null ? 'Requires the local chat cursor fixture' : false);
}
