// Zgoda na wysyłkę zdjęcia rysunku przed pierwszym skanem.
//
// Skaner nie publikuje niczego pod nazwiskiem, więc nie pyta o imię (to
// bramka czatu). Pyta o jedno: czy monter zgadza się, żeby zdjęcie poszło na
// nasz serwer i do Anthropic (Claude) do odczytu. Zgoda jest wiązana z wersją
// zasad — po podniesieniu kLegalVersion pytamy ponownie.

import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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

class _DelayedConsentDisk extends InMemorySharedPreferencesStore {
  _DelayedConsentDisk() : super.empty();
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${ScanConsent.prefsKey}') {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  setUp(() => ScanConsent.resetForTest());

  test('wycofanie nie przegrywa z rozpoczętym zapisem zgody', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedConsentDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final accepting = ScanConsent.accept();
    await disk.entered.future;
    final clearing = ScanConsent.clear();
    expect(ScanConsent.isAccepted, isFalse);
    await Future<void>.delayed(Duration.zero);
    disk.release.complete();
    await Future.wait([accepting, clearing]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(ScanConsent.prefsKey), isNull);
    ScanConsent.resetForTest();
    await ScanConsent.load();
    expect(ScanConsent.isAccepted, isFalse);
  });

  test('ponowne potwierdzenie po wycofaniu pozostaje zapisane', () async {
    SharedPreferences.setMockInitialValues({});
    await ScanConsent.accept();
    final clearing = ScanConsent.clear();
    final accepting = ScanConsent.accept();
    await Future.wait([clearing, accepting]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    ScanConsent.resetForTest();
    await ScanConsent.load();
    expect(ScanConsent.isAccepted, isTrue);
    expect(ScanConsent.acceptedAt, isNotNull);
  });

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
  for (final record in <Map<String, Object?>>[
    {'version': kLegalVersion},
    {'version': kLegalVersion, 'acceptedAt': 'invalid'},
    {'version': kLegalVersion + 0.5, 'acceptedAt': '2026-09-25T10:00:00.000'},
  ]) {
    testWidgets('uszkodzony zapis zgody wymaga potwierdzenia: $record',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        ScanConsent.prefsKey: jsonEncode(record),
      });
      final result = await _run(tester, tapLabel: 'Anuluj');
      expect(result, isFalse);
      expect(ScanConsent.isAccepted, isFalse);
      expect(ScanConsent.acceptedAt, isNull);
    });
  }
}
