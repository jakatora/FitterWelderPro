// Zgoda na wysyłkę zdjęcia rysunku przed pierwszym skanem.
//
// Skaner nie publikuje niczego pod nazwiskiem, więc nie pyta o imię (to
// bramka czatu). Pyta o jedno: czy monter zgadza się, żeby zdjęcie poszło na
// nasz serwer i do Anthropic (Claude) do odczytu. Zgoda jest wiązana z wersją
// zasad — po podniesieniu kLegalVersion pytamy ponownie.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/widgets/scan_consent_gate.dart';

Future<bool?> _run(WidgetTester tester, {required String tapLabel}) async {
  bool? result;
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await ensureScanConsent(context),
            child: const Text('skanuj'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('skanuj'));
  await tester.pumpAndSettle();
  if (tapLabel.isNotEmpty) {
    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  setUp(() => ScanConsent.resetForTest());

  testWidgets('pierwszy skan: okno mówi, dokąd idzie zdjęcie; zgoda zapisana',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    bool? result;
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await ensureScanConsent(context),
              child: const Text('skanuj'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('skanuj'));
    await tester.pumpAndSettle();

    // Treść: serwer, Anthropic, brak imienia, sprawdzanie wyniku.
    expect(find.textContaining('Anthropic'), findsWidgets);
    expect(find.textContaining('nie zapisuje'), findsWidgets);
    expect(find.textContaining('sprawdzić'), findsWidgets);
    expect(find.text('Imię'), findsNothing);

    await tester.tap(find.text('Zgadzam się'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('iso_scan_consent_v1')!) as Map;
    expect(saved['version'], kLegalVersion);
  });

  testWidgets('„Anuluj" nie wysyła i nie zapisuje zgody', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final result = await _run(tester, tapLabel: 'Anuluj');
    expect(result, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('iso_scan_consent_v1'), isNull);
  });

  testWidgets('zgoda na bieżącą wersję zasad: bez pytania', (tester) async {
    SharedPreferences.setMockInitialValues({
      'iso_scan_consent_v1': jsonEncode({
        'version': kLegalVersion,
        'acceptedAt': '2026-09-25T10:00:00.000',
      }),
    });
    final result = await _run(tester, tapLabel: '');
    expect(result, isTrue);
    expect(find.text('Zgadzam się'), findsNothing);
  });

  testWidgets('zgoda na starszą wersję zasad: pytamy ponownie', (tester) async {
    SharedPreferences.setMockInitialValues({
      'iso_scan_consent_v1': jsonEncode({
        'version': kLegalVersion - 1,
        'acceptedAt': '2026-01-01T10:00:00.000',
      }),
    });
    final result = await _run(tester, tapLabel: 'Zgadzam się');
    expect(result, isTrue);
  });
}
