import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/correction_memory_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/test_account.dart';

void main() {
  useGuestAccount();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('memory lists corrections and deletes only the selected one',
      (tester) async {
    final store = CorrectionMemoryStore();
    await store.remember(const RememberedCorrection(
        question: 'Pytanie pierwsze', correction: 'Poprawka pierwsza'));
    await store.remember(const RememberedCorrection(
        question: 'Pytanie drugie', correction: 'Poprawka druga'));
    final language = AppLanguageController(AppLanguage.pl);
    addTearDown(language.dispose);
    await tester.pumpWidget(AppLanguageScope(
        controller: language,
        child: MaterialApp(home: CorrectionMemoryScreen(store: store))));
    await tester.pumpAndSettle();
    expect(find.text('Pytanie pierwsze'), findsOneWidget);
    expect(find.text('Poprawka druga'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Usuń poprawkę').first);
    await tester.pumpAndSettle();
    expect(find.text('Poprawka druga'), findsNothing);
    expect(find.text('Poprawka pierwsza'), findsOneWidget);
    expect((await store.list()).single.correction, 'Poprawka pierwsza');
  });

  testWidgets('clear all requires confirmation and removes all corrections',
      (tester) async {
    final store = CorrectionMemoryStore();
    await store.remember(const RememberedCorrection(
        question: 'Pytanie A', correction: 'Odpowiedź A'));
    await store.remember(const RememberedCorrection(
        question: 'Pytanie B', correction: 'Odpowiedź B'));
    final language = AppLanguageController(AppLanguage.pl);
    addTearDown(language.dispose);
    await tester.pumpWidget(AppLanguageScope(
        controller: language,
        child: MaterialApp(home: CorrectionMemoryScreen(store: store))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyczyść pamięć'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(await store.list(), hasLength(2));
    await tester.tap(find.text('Wyczyść pamięć'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń wszystko'));
    await tester.pumpAndSettle();
    expect(await store.list(), isEmpty);
    expect(find.text('Brak zapamiętanych poprawek.'), findsOneWidget);
  });

  testWidgets(
      'a confirmation from a previous account cannot clear the new account',
      (tester) async {
    final store = CorrectionMemoryStore();
    await store.remember(const RememberedCorrection(
        question: 'Pytanie A', correction: 'Poprawka A'));
    final old = AccountService.instance;
    final client = MockClient((_) async => http.Response('{}', 500));
    final other = AccountService.forTesting(client);
    await other.load();
    other.account = {'id': 'other-account'};
    AccountService.instance = other;
    await store.remember(const RememberedCorrection(
        question: 'Pytanie B', correction: 'Poprawka B'));
    AccountService.instance = old;
    addTearDown(() {
      other.dispose();
      client.close();
    });
    final language = AppLanguageController(AppLanguage.pl);
    addTearDown(language.dispose);
    await tester.pumpWidget(AppLanguageScope(
        controller: language,
        child: MaterialApp(home: CorrectionMemoryScreen(store: store))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyczyść pamięć'));
    await tester.pumpAndSettle();
    AccountService.instance = other;
    await tester.tap(find.text('Usuń wszystko'));
    await tester.pumpAndSettle();
    expect((await store.list()).single.correction, 'Poprawka B');
    AccountService.instance = old;
    expect((await store.list()).single.correction, 'Poprawka A');
  });
}
