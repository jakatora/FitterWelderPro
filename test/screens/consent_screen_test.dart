// Scenariusz audytu `consent`: użytkownik akceptuje wymagane zasady przed
// użyciem aplikacji. Sprawdzamy przypadki błędne (brak zaznaczenia, podwójne
// stuknięcie) i trwały zapis zgody z bieżącą wersją dokumentu.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';

import '../test_prefs.dart';

Future<void> _pumpSome(WidgetTester tester, [int n = 6]) async {
  // Bez pumpAndSettle: po akceptacji kręci się wskaźnik zapisu.
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pumpConsent(WidgetTester tester, VoidCallback onAccepted) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Wibracje idą kanałem platformy. W teście odpowiadamy na nie pustym wynikiem.
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: ConsentScreen(onAccepted: onAccepted)),
  ));
  await _pumpSome(tester, 2);
}

FilledButton _acceptButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  setUp(() {
    seedProfileWithoutConsent();
  });

  testWidgets('bez zaznaczenia zgody przycisk nic nie zapisuje',
      (tester) async {
    var calls = 0;
    await _pumpConsent(tester, () => calls++);

    expect(find.text('I accept'), findsOneWidget);
    expect(_acceptButton(tester).onPressed, isNull,
        reason: 'przycisk aktywny bez zaznaczonej zgody');

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await _pumpSome(tester);

    expect(calls, 0);
    expect(LegalConsent.instance.isAccepted, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('legal_consent_v1'), isNull);
  });

  testWidgets('zaznaczenie włącza przycisk, odznaczenie znów go wyłącza',
      (tester) async {
    await _pumpConsent(tester, () {});

    await tester.tap(find.byType(Checkbox));
    await _pumpSome(tester, 2);
    expect(_acceptButton(tester).onPressed, isNotNull);

    await tester.tap(find.byType(Checkbox));
    await _pumpSome(tester, 2);
    expect(_acceptButton(tester).onPressed, isNull);
    expect(LegalConsent.instance.isAccepted, isFalse);
  });

  testWidgets('akceptacja zapisuje bieżącą wersję zasad i przechodzi dalej',
      (tester) async {
    var calls = 0;
    await _pumpConsent(tester, () => calls++);

    await tester.tap(find.byType(Checkbox));
    await _pumpSome(tester, 2);
    await tester.tap(find.text('I accept'));
    await _pumpSome(tester);

    expect(calls, 1);
    expect(LegalConsent.instance.isAccepted, isTrue);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('legal_consent_v1');
    expect(raw, isNotNull, reason: 'zgoda nie trafiła na dysk');
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['version'], kLegalVersion);
    expect(DateTime.tryParse(decoded['acceptedAt'] as String), isNotNull);
  });

  testWidgets('dwa szybkie stuknięcia przechodzą dalej tylko raz',
      (tester) async {
    var calls = 0;
    await _pumpConsent(tester, () => calls++);

    await tester.tap(find.byType(Checkbox));
    await _pumpSome(tester, 2);

    final button = find.byType(FilledButton);
    // Bez klatki między stuknięciami: przycisk jeszcze się nie wyłączył.
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await _pumpSome(tester);

    expect(calls, 1, reason: 'brama startowa przełączona więcej niż raz');
    expect(LegalConsent.instance.isAccepted, isTrue);
  });
}
