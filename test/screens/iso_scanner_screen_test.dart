// Ekran skanera izometryku (przegląd G3, P1): po odczycie AI ekran NIE
// pokazuje wymiaru ISO jako „CUT” ani „Suma CUT” — długości cięcia liczy
// wyłącznie przegląd skanu (jeden silnik). Odczyt jest zapisany w telefonie
// (iso_scans, v24) i otwiera się ponownie bez płatnego skanu.

import 'dart:convert';
import 'dart:async';
import 'package:cut_list_app/config/feature_flags.dart';
import 'dart:io';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/scan_consent.dart';

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
          {
            'id': 'E1',
            'type': 'elbow90',
            'label': '90° LR',
            'confidence': 'high'
          },
          {
            'id': 'E2',
            'type': 'elbow90',
            'label': '90° LR',
            'confidence': 'high'
          },
        ],
      },
      'tookMs': 30000,
      'model': 'claude-sonnet-5',
    };

class _DelayedScanPrefs extends InMemorySharedPreferencesStore {
  _DelayedScanPrefs() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.getAll();
  }
}

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

  for (final lang in AppLanguage.values) {
    for (final size in [const Size(432, 960), const Size(360, 640)]) {
      testWidgets('empty photo picker stays reachable: $lang/$size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(AppLanguageScope(
          controller: AppLanguageController(lang),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const IsoScannerScreen(),
          ),
        ));
        await settle(tester);
        final pick = find
            .text(lang == AppLanguage.en ? 'Choose photo' : 'Wybierz zdjęcie');
        await tester.ensureVisible(pick);
        await tester.pump();
        expect(tester.getRect(pick).top, greaterThanOrEqualTo(0));
        expect(tester.getRect(pick).bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final exhausted in [false, true]) {
    testWidgets('dwuklik nie dubluje skanu i zwalnia blokadę: limit=$exhausted',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ScanConsent.resetForTest();
      late Directory dir;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('fwp-double-scan-');
        final photo = File('${dir.path}/drawing.png');
        await photo.writeAsBytes(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
        await IsoScanDao().insert(IsoScanRecord(
            id: 'double',
            name: 'Dwuklik',
            imagePath: photo.path,
            envelopeJson: jsonEncode(_envelope()),
            createdAt: 1));
      });
      addTearDown(() async {
        await File('${dir.path}/drawing.png').delete();
        await dir.delete();
      });
      await tester.pumpWidget(app(const IsoScannerScreen()));
      await settle(tester);
      await tester.ensureVisible(find.text('Dwuklik'));
      await tester.tap(find.text('Dwuklik'));
      await settle(tester);
      SharedPreferences.setMockInitialValues({});
      final disk = _DelayedScanPrefs();
      if (exhausted) {
        final now = DateTime.now();
        final day =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        await disk.setValue('String', 'flutter.iso_scan_day_v1', day);
        await disk.setValue(
            'Int', 'flutter.iso_scan_count_v1', kAiScanDailyLimitPerDevice);
      }
      SharedPreferencesStorePlatform.instance = disk;
      final scan = find.byTooltip('Analizuj AI');
      await tester.tap(scan);
      await tester.tap(scan);
      await disk.entered.future;
      disk.release.complete();
      await settle(tester);
      expect(
          find.byType(AlertDialog), exhausted ? findsNothing : findsOneWidget);
      if (!exhausted) {
        await tester.tap(find.text('Anuluj').last);
        await settle(tester);
      }
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton && widget.tooltip == 'Analizuj AI'))
              .onPressed,
          isNotNull);
    });
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
