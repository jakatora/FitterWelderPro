import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/ai_professional_context.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/services/premium_service.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final preferences = AiProfessionalContext.instance;
  late AccountService account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    preferences.resetForTest();
    account = AccountService.forTesting(MockClient((request) async {
      final email = jsonDecode(request.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$email',
            'account': {
              'id': email,
              'displayName': 'Private name',
              'email': email,
              'profession': 'Welder'
            }
          }),
          200);
    }));
    AccountService.instance = account;
    await account.load();
  });
  Future<void> login(String id) => account.signIn(id, 'fixture-password');
  test(
      'disabled by default, persisted for A only, guest never sends account identity',
      () async {
    expect((await preferences.capture()).body, isEmpty);
    await login('A');
    expect((await preferences.capture()).headers, isEmpty);
    await preferences.setEnabled(true);
    final a = await preferences.capture();
    expect(a.body, {'use_professional_profile': true});
    expect(a.headers, {'Authorization': 'Bearer fixture-A'});
    await login('B');
    expect((await preferences.capture()).body, isEmpty);
    expect(a.requireCurrent, throwsA(isA<AccountException>()));
    await account.forgetSession();
    expect((await preferences.capture()).headers, isEmpty);
    await login('A');
    preferences.resetForTest();
    expect((await preferences.capture()).enabled, isTrue);
    await preferences.setEnabled(false);
    preferences.resetForTest();
    expect((await preferences.capture()).body, isEmpty);
  });
  test(
      'capture is invalidated by consent revocation even when session is unchanged',
      () async {
    await login('A');
    await preferences.setEnabled(true);
    final capture = await preferences.capture();
    await preferences.setEnabled(false);
    expect(capture.requireCurrent, throwsA(isA<AccountException>()));
  });
  test('guest cannot enable personalization', () async {
    await expectLater(
        preferences.setEnabled(true), throwsA(isA<AccountException>()));
    expect((await preferences.capture()).body, isEmpty);
  });
  const request = <String, Object?>{
    'capabilities': [
      {'id': 'module.open'}
    ]
  };
  String response() => jsonEncode(
      {'kind': 'clarify', 'steps': [], 'message': 'Co chcesz zrobić?'});
  test(
      'interpreter sends installation plus optional bearer and flag, never local profile data',
      () async {
    await login('A');
    final requests = <http.Request>[];
    final client = AssistantAiClient(
        identity: () async => {'X-Device-Id': 'installation'},
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(response(), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    addTearDown(client.close);
    await client.interpret(request);
    expect(requests.last.headers.containsKey('Authorization'), isFalse);
    expect(
        jsonDecode(requests.last.body).containsKey('use_professional_profile'),
        isFalse);
    await preferences.setEnabled(true);
    await client.interpret(request);
    expect(requests.last.headers['Authorization'], 'Bearer fixture-A');
    expect(requests.last.headers['X-Device-Id'], 'installation');
    expect(jsonDecode(requests.last.body),
        {...request, 'use_professional_profile': true});
    expect(requests.last.body, isNot(contains('Private name')));
  });
  test('late interpreter response after opt-out is rejected', () async {
    await login('A');
    await preferences.setEnabled(true);
    final entered = Completer<void>(), release = Completer<void>();
    final client = AssistantAiClient(
        identity: () async => {},
        client: MockClient((r) async {
          entered.complete();
          await release.future;
          return http.Response(response(), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    addTearDown(client.close);
    final pending = expectLater(
        client.interpret(request), throwsA(isA<AssistantAiUnavailable>()));
    await entered.future;
    await preferences.setEnabled(false);
    release.complete();
    await pending;
  });

  test('knowledge chat sends same opt-in and account header as interpreter',
      () async {
    SharedPreferences.setMockInitialValues({
      'fitter_device_id': '0123456789abcdef0123456789abcdef',
      'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
    });
    PremiumService.instance.resetForTest();
    await login('A');
    await preferences.setEnabled(true);
    final requests = <http.Request>[];
    final result = await http.runWithClient(
        () => AiChatService.instance.sendMessage('Jak działa TIG?'),
        () => MockClient((r) async {
              requests.add(r);
              return http.Response('{"text":"Odpowiedź"}', 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
    expect(result.kind, AiReplyKind.live);
    expect(requests.single.headers['Authorization'], 'Bearer fixture-A');
    expect(
        jsonDecode(requests.single.body)['use_professional_profile'], isTrue);
    expect(requests.single.body, isNot(contains('Private name')));
  });

  for (final language in AppLanguage.values) {
    testWidgets('account opt-in is usable at 320px in ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLanguageController.current = language;
      addTearDown(() => AppLanguageController.current = AppLanguage.pl);
      await tester.runAsync(() async {
        await login('A');
        await preferences.load();
      });
      final controller = AppLanguageController(language);
      addTearDown(controller.dispose);
      await tester.pumpWidget(AppLanguageScope(
          controller: controller,
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!),
              home: const AccountScreen())));
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('account-ai-professional-context'));
      await tester.scrollUntilVisible(toggle, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(toggle.hitTestable(), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(preferences.enabled, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.runAsync(account.forgetSession);
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
