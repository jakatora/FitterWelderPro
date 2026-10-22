import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/ai_professional_context.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  testWidgets(
      'account form requires explicit consent and sends the displayed policy version',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AiProfessionalContext.instance.resetForTest();
    FeedbackConsent.instance.resetForTest();
    final requests = <http.Request>[];
    final account = AccountService.forTesting(MockClient((r) async {
      requests.add(r);
      return http.Response(
          jsonEncode({
            'token': 'fixture-token',
            'account': {
              'id': 'fixture-account',
              'email': 'fixture@example.com',
              'displayName': 'Fixture user',
              'role': 'user'
            }
          }),
          200);
    }));
    AccountService.instance = account;
    await t.runAsync(() async {
      await account.load();
      await AiProfessionalContext.instance.load();
      await FeedbackConsent.instance.isGranted();
    });
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: const MaterialApp(home: AccountScreen(initialRegister: true))));
    await t.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    await t.enterText(field('E-mail'), 'fixture@example.com');
    await t.enterText(field('Hasło (minimum 12 znaków)'), 'fixture-password');
    await t.enterText(field('Imię i nazwisko na czacie'), 'Fixture user');
    final create = find.widgetWithText(FilledButton, 'Załóż konto');
    await t.ensureVisible(create);
    await t.tap(create);
    await t.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('Przeczytaj i zaakceptuj zasady konta.'), findsOneWidget);
    await t.ensureVisible(find.text('Regulamin'));
    await t.tap(find.text('Regulamin'));
    await t.pumpAndSettle();
    expect(find.text('Aktualizacja: $kLegalUpdated'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.ensureVisible(create);
    await t.tap(create);
    for (var i = 0; i < 10 && account.account == null; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body)['legalVersion'], kLegalVersion);
    expect(account.account!['id'], 'fixture-account');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
