import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/ui/assistant_account_header.dart';
import 'package:cut_list_app/assistant/ui/assistant_overlay.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show settle;

void main() {
  useTestDatabase();
  late AccountService previous;
  setUp(() {
    previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => AccountService.instance = previous);

  Future<void> mountChat(WidgetTester tester) => mount(tester,
      home: const Scaffold(body: Text('Home')),
      speech: FixtureSpeech(),
      interpret: (_) async => throw StateError('No paid AI expected'));

  testWidgets('expired stored session returns to guest and erases its token',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'fixture-expired'});
    var requests = 0;
    AccountService.instance = AccountService.forTesting(MockClient((_) async {
      requests++;
      return http.Response('{"error":{"message":"Expired"}}', 401);
    }));
    await mountChat(tester);
    expect(find.text('Zaloguj się'), findsOneWidget);
    expect(AccountService.instance.needsIdentityRefresh, isFalse);
    expect(
        await const FlutterSecureStorage()
            .read(key: 'railway_account_session_v1'),
        isNull);
    expect(requests, 1);
    await tester.tap(find.byKey(const Key('assistant-account')));
    await settle(tester);
    expect(find.widgetWithText(FilledButton, 'Zaloguj się'), findsOneWidget);
    expect(find.byKey(const Key('account-retry-profile')), findsNothing);
    expect(requests, 1);
  });

  testWidgets(
      'offline retained session retries profile without asking for a password',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'fixture-session'});
    var reads = 0;
    AccountService.instance =
        AccountService.forTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'Bearer fixture-session');
      reads++;
      return reads <= 2
          ? http.Response('{"error":{"message":"Offline fixture"}}', 503)
          : http.Response(
              jsonEncode({
                'account': {
                  'id': 'owner',
                  'email': 'fixture@example.test',
                  'displayName': 'Odzyskany profil',
                  'profession': 'Monter',
                }
              }),
              200);
    }));
    await mountChat(tester);
    expect(find.text('Otwórz profil, aby ponowić'), findsOneWidget);
    final revision = AccountService.instance.sessionRevision;
    await tester.tap(find.byKey(const Key('assistant-account')));
    await settle(tester);
    expect(find.byKey(const Key('account-retry-profile')), findsOneWidget);
    expect(find.textContaining('Hasło (minimum 12 znaków)'), findsNothing);
    await tester.tap(find.byKey(const Key('account-retry-profile')));
    await settle(tester);
    expect(reads, 3);
    expect(AccountService.instance.sessionRevision, revision);
    expect(find.byKey(const Key('account-retry-profile')), findsNothing);
    expect(find.text('fixture@example.test'), findsOneWidget);
    appNavigatorKey.currentState!.pop();
    await settle(tester);
    expect(find.text('Odzyskany profil · Monter'), findsOneWidget);
  });

  testWidgets('guest startup is offline; account button opens private form',
      (tester) async {
    var requests = 0;
    AccountService.instance = AccountService.forTesting(MockClient((_) async {
      requests++;
      return http.Response('{}', 500);
    }));
    await mountChat(tester);
    expect(find.text('Zaloguj się'), findsOneWidget);
    expect(requests, 0);
    expect(tester.getSize(find.byKey(const Key('assistant-account'))).height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const Key('assistant-account')));
    await settle(tester);
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(appRoutes.assistantAvailable, isFalse);
    expect(find.byKey(const Key('assistant-account')), findsNothing);
    expect(requests, 0);
    appNavigatorKey.currentState!.pop();
    await settle(tester);
    expect(find.text('Zaloguj się'), findsOneWidget);
  });

  testWidgets('stored session restores own name and private profession once',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'fixture-session'});
    final pending = Completer<http.Response>();
    var requests = 0;
    AccountService.instance = AccountService.forTesting(MockClient((request) {
      requests++;
      expect(request.url.path, '/api/fitter/account/me');
      expect(request.headers['Authorization'], 'Bearer fixture-session');
      return pending.future;
    }));
    await mountChat(tester);
    expect(find.text('Sprawdzam konto…'), findsOneWidget);
    pending.complete(http.Response(
        jsonEncode({
          'account': {
            'id': 'owner',
            'displayName': 'Anna Kowalska',
            'profession': 'Spawacz TIG',
            'email': 'private@example.test',
            'qualifications': 'private qualification',
            'publicProfile': false,
            'role': 'user'
          }
        }),
        200));
    await settle(tester);
    expect(find.text('Anna Kowalska · Spawacz TIG'), findsOneWidget);
    expect(find.textContaining('private@example.test'), findsNothing);
    expect(find.textContaining('private qualification'), findsNothing);
    expect(requests, 1);
    await AccountService.instance.load();
    await settle(tester);
    expect(requests, 1);
  });

  testWidgets(
      'profile edit updates identity and preserves draft; logout clears both',
      (tester) async {
    var identity = <String, dynamic>{
      'id': 'user',
      'displayName': 'Jan',
      'profession': 'Monter',
    };
    final account = AccountService.forTesting(MockClient((request) async {
      if (request.method == 'PUT') {
        identity = {
          ...identity,
          ...jsonDecode(request.body) as Map<String, dynamic>
        };
      }
      return http.Response(
          jsonEncode({'account': identity, 'token': 'fixture'}), 200);
    }));
    AccountService.instance = account;
    await account.signIn('fixture@example.test', 'fixture-password');
    await mountChat(tester);
    final input = find.byKey(const Key('assistant-command'));
    await tester.enterText(input, 'mój szkic');
    await account
        .saveProfile({'displayName': 'Jan Nowak', 'profession': 'Spawacz'});
    await settle(tester);
    expect(find.text('Jan Nowak · Spawacz'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, 'mój szkic');
    await account.forgetSession();
    await settle(tester);
    expect(find.text('Zaloguj się'), findsOneWidget);
    expect(find.textContaining('Jan Nowak'), findsNothing);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
  });

  for (final language in AppLanguage.values) {
    testWidgets(
        'long own profile fits narrow header at large text in ${language.name}',
        (tester) async {
      AccountService.instance = AccountService.forTesting(
          MockClient((_) async => http.Response('{}', 500)))
        ..account = {
          'displayName': 'Bardzo długa nazwa własnego konta użytkownika',
          'profession': 'Monter konstrukcji i spawacz rur przemysłowych'
        };
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(language),
        child: MaterialApp(
            home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
              body: Center(
                  child: Material(
                      child: SizedBox(
                          width: 200,
                          height: 80,
                          child: AssistantAccountHeader())))),
        )),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final identity = tester
          .widget<Text>(find.byKey(const Key('assistant-account-identity')));
      expect(identity.overflow, TextOverflow.ellipsis);
      expect(identity.maxLines, 1);
    });
  }

  testWidgets(
      'actual compact overlay supports 320px width and double text scale',
      (tester) async {
    AccountService.instance = AccountService.forTesting(
        MockClient((_) async => http.Response('{}', 500)))
      ..account = {'displayName': 'Jan Kowalski', 'profession': 'Spawacz TIG'};
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    AssistantPanelController.instance.setExpanded(true);
    addTearDown(() => AssistantPanelController.instance.setExpanded(false));
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [appRoutes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child:
              AssistantOverlay(assistant: const Text('Rozmowa'), child: child!),
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const Key('assistant-account'))).height, 80);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
