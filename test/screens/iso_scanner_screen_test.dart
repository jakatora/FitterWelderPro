// Ekran skanera izometryku (przegląd G3, P1): po odczycie AI ekran NIE
// pokazuje wymiaru ISO jako „CUT” ani „Suma CUT” — długości cięcia liczy
// wyłącznie przegląd skanu (jeden silnik). Odczyt jest zapisany w telefonie
// (iso_scans, v24) i otwiera się ponownie bez płatnego skanu.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_scan_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/iso_scanner_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

import '../support/test_database.dart';

/// Kolano–kolano 1200 (przypadek 01 złotego zestawu, bez spoin).
Map<String, dynamic> _envelope() => <String, dynamic>{
      'result': <String, dynamic>{
        'drawingStandard': 'ISO',
        'sizeNotation': 'DN',
        'titleBlock': <String, dynamic>{
          'lineNumber': 'DN100-P-1001-A1A',
          'pipeClass': 'CL150',
          'material': 'A312 TP316L',
          'schedule': 'Sch 40',
        },
        'segments': [
          {
            'id': 's1',
            'fromId': null,
            'toId': 'E1',
            'dimensionMm': 1500,
            'rawDimension': '1500',
            'confidence': 'high'
          },
          {
            'id': 's2',
            'fromId': 'E1',
            'toId': 'E2',
            'dimensionMm': 1200,
            'rawDimension': '1200',
            'confidence': 'high'
          },
          {
            'id': 's3',
            'fromId': 'E2',
            'toId': null,
            'dimensionMm': 700,
            'rawDimension': '700',
            'confidence': 'high'
          },
        ],
        'components': [
          {'id': 'E1', 'type': 'elbow90', 'label': '90° LR', 'confidence': 'high'},
          {'id': 'E2', 'type': 'elbow90', 'label': '90° LR', 'confidence': 'high'},
        ],
      },
      'tookMs': 30000,
      'model': 'claude-sonnet-5',
    };

void main() {
  useTestDatabase();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await AppDatabase.get();
    await db.delete(IsoScanDao.table);
  });

  Widget app(Widget home) => AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(home: home),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets(
      'po odczycie: wymiary jako ISO, nigdzie „CUT 1200” ani „Suma CUT”; '
      'przegląd liczy 1200 − 2×152 = 896', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scan = AiScanResult.fromEnvelope(_envelope());
    await tester.pumpWidget(app(IsoScannerScreen(initialScan: scan)));
    await settle(tester);

    expect(find.text('1200'), findsOneWidget, reason: 'wymiar odczytany');
    expect(find.textContaining('NIE są długości cięcia'), findsOneWidget);
    expect(find.textContaining('CUT 1200'), findsNothing);
    expect(find.textContaining('Suma CUT'), findsNothing);
    expect(find.textContaining('1200.0 mm'), findsNothing);

    final button = find.byKey(const ValueKey('scan-open-review'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await settle(tester);

    expect(find.text('Sprawdź skan'), findsOneWidget);
    expect(find.textContaining('CUT 896.0 mm'), findsOneWidget);
    expect(find.textContaining('CUT 1200'), findsNothing);
  });

  testWidgets('zapisany odczyt otwiera się ponownie bez skanu', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => IsoScanDao().insert(IsoScanRecord(
          id: 'scan-1',
          name: 'DN100-P-1001-A1A',
          envelopeJson: jsonEncode(_envelope()),
          createdAt: DateTime(2026, 9, 26, 10, 30).millisecondsSinceEpoch,
        )));

    await tester.pumpWidget(app(const IsoScannerScreen()));
    await settle(tester);

    expect(find.text('ZAPISANE SKANY'), findsOneWidget);
    await tester.tap(find.text('DN100-P-1001-A1A'));
    await settle(tester);

    expect(find.text('1200'), findsOneWidget);
    final button = find.byKey(const ValueKey('scan-open-review'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    // Nothing was spent: the counter still shows the full day.
    expect(find.textContaining('Pozostało dziś'), findsOneWidget);
  });
}
