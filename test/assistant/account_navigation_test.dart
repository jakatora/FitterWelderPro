import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'support/assistant_test_support.dart';

void main() {
  for (final (command, destination) in [
    ('chcę założyć konto', 'account_register'),
    ('proszę utwórz konto', 'account_register'),
    ('zaloguj mnie', 'account'),
    ('pokaż mój profil zawodowy', 'account'),
    ('otwórz ustawienia konta', 'account'),
  ]) {
    test('$command opens the right form without saving anything', () async {
      final h = BrainHarness();
      final reply = await h.say(command, byVoice: true);
      expect(reply.match?.skill.id, 'account.open');
      expect(reply.result, isA<AnswerResult>());
      expect((reply.result as AnswerResult).show?.toolId, destination);
      expect((reply.result as AnswerResult).show?.fields, isEmpty);
      expect(h.actions.savedParams, isEmpty);
      expect(h.actions.savedJournal, isEmpty);
    });
  }
  for (final registering in [false, true]) {
    testWidgets(
        'bridge opens the ${registering ? 'registration' : 'account'} form',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      AccountService.instance = AccountService.forTesting(
          MockClient((_) async => http.Response('{}', 500)));
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start'))),
      ));
      await tester.pumpAndSettle();
      final injected = await showInModule(
          ShowInModule(
              registering ? 'account_register' : 'account', {'role': 'admin'}),
          explicit: true);
      expect(injected, ShowOutcome.unavailable);
      expect(find.byType(AccountScreen), findsNothing);
      final outcome = await showInModule(
          ShowInModule(registering ? 'account_register' : 'account'),
          explicit: true);
      await tester.pumpAndSettle();
      expect(outcome, ShowOutcome.opened);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(
          find.widgetWithText(
              FilledButton, registering ? 'Załóż konto' : 'Zaloguj się'),
          findsOneWidget);
      // Account forms hide the global assistant while credentials are entered.
      expect(appRoutes.assistantAvailable, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
