// „Importuj spoiny" na ekranie wyceny, z prawdziwą bazą testową: spoiny
// pakietu z dziennika i mapa spoin zapisanego skanu ISO (złoty zestaw)
// → podgląd → pozycje w wycenie (i w bazie po autozapisie).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/iso_scan_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/features/quotes/quote_edit_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/quote_settings.dart';

import '../../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

WeldEntry _weld(
  String id, {
  required String project,
  required String package,
  String type = 'BW',
  String od = '114.3',
  String t = '6.02',
  String position = '',
  String shopField = '',
}) =>
    WeldEntry(
      id: id,
      weldNo: id.toUpperCase(),
      projectName: project,
      pipeName: '',
      material: '',
      od: od,
      t: t,
      method: '',
      welder: '',
      date: '',
      notes: '',
      status: WeldStatus.pending,
      testPackage: package,
      jointType: type,
      position: position,
      shopField: shopField,
    );

WeldQuote _quote(QuoteSite site) => WeldQuote(
      id: 'q-import',
      number: 'WYC/2026/010',
      title: 'Dokończenie instalacji',
      site: site,
      createdAt: DateTime(2026, 10, 17).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 10, 17).millisecondsSinceEpoch,
    );

Future<void> _clean() async {
  final db = await AppDatabase.get();
  for (final t in [
    'weld_quotes',
    'weld_journal',
    'weld_journal_history',
    'weld_repairs',
    'iso_scans',
  ]) {
    await db.delete(t);
  }
}

Future<void> _openEditor(WidgetTester tester, WeldQuote quote) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(
      home: QuoteEditPage(
        quote: quote,
        settings: const QuoteSettings(),
        saveDelay: const Duration(milliseconds: 100),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<List<QuoteJoint>> _savedJoints(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await _settle(tester);
  final rows = (await tester.runAsync(() => WeldQuoteDao().listAll()))!;
  return rows.single.joints;
}

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'dziennik: pakiet TP-03 → podgląd → odznaczenie mufy → pozycja w wycenie',
      (tester) async {
    await tester.runAsync(() async {
      await _clean();
      final dao = WeldJournalDao();
      for (final e in [
        _weld('w1',
            project: 'Rafineria',
            package: 'TP-03',
            position: 'PF',
            shopField: WeldLocation.field),
        _weld('w2',
            project: 'Rafineria',
            package: 'TP-03',
            position: '5G',
            shopField: WeldLocation.field),
        _weld('w3',
            project: 'Rafineria',
            package: 'TP-03',
            od: '114,3',
            t: '6,02',
            position: 'PF',
            shopField: WeldLocation.shop),
        _weld('w4',
            project: 'Rafineria',
            package: 'TP-03',
            type: 'SW',
            od: '33.4',
            t: '4.55'),
        // Bez OD — pominięta, nie zgadywana.
        _weld('w5', project: 'Rafineria', package: 'TP-03', od: ''),
        // Usunięta — nie wchodzi.
        _weld('d1', project: 'Rafineria', package: 'TP-03'),
        _weld('w6',
            project: 'Rafineria', package: 'TP-04', od: '168.3', t: '7.11'),
        _weld('w7', project: 'Inny', package: 'TP-01'),
      ]) {
        await dao.insert(e);
      }
      await dao.softDelete('d1');
    });

    await _openEditor(tester, _quote(QuoteSite.shop));
    await tester.tap(find.byKey(const ValueKey('import-joints')));
    await tester.pumpAndSettle();
    expect(find.text('Importuj spoiny'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-source-journal')));
    await _settle(tester);
    await tester.pumpAndSettle();

    // Projekt: domyślnie pierwszy alfabetycznie („Inny") → Rafineria.
    await tester.tap(find.byKey(const ValueKey('import-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Rafineria').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-package-Rafineria')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TP-03').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Zaznaczone: 2 z 2 pozycji (4 z 4 spoin)'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('import-skipped')), findsOneWidget);
    expect(find.textContaining('Pominięte (brak wymiaru): 1'), findsOneWidget);
    expect(find.textContaining('W5'), findsOneWidget);
    expect(find.text('3×'), findsOneWidget);
    expect(find.text('obiekt 2  ·  warsztat 1'), findsNothing);
    expect(find.text('warsztat 1  ·  obiekt 2'), findsOneWidget);

    // Mufy nie wchodzą.
    const socketKey = ValueKey('import-group-PIPE_FILLET|33.40|4.55|0.00|PA');
    expect(find.byKey(socketKey), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(socketKey), matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dodaj do wyceny (3 spoin)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-confirm')));
    await tester.pumpAndSettle();

    // Z powrotem w zakładce „Spoiny": jedna pozycja 3× z etykietą pakietu.
    expect(find.byKey(const ValueKey('import-joints')), findsOneWidget);
    expect(find.text('3×'), findsOneWidget);
    expect(find.text('TP-03'), findsOneWidget);
    expect(find.textContaining('Ø114,3 × 6,02'), findsOneWidget);
    expect(find.text('Dodano pozycji: 1 (spoin: 3).'), findsOneWidget);

    final joints = await _savedJoints(tester);
    expect(joints, hasLength(1));
    final j = joints.single;
    expect(j.kind, JointKind.pipeButt);
    expect(j.count, 3);
    expect(j.odMm, 114.3);
    expect(j.wallMm, 6.02);
    expect(j.sizeLabel, 'DN100 Sch 40');
    expect(j.position, WeldPosition.pf);
    expect(j.label, 'TP-03');
    expect(j.isValid, isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'skan ISO (złoty zestaw 17): 6 spoin → zmiana pozycji → wycena → Cofnij',
      (tester) async {
    final golden = jsonDecode(
        File('test/golden_iso/17-spoole-spoiny-montazowe.json')
            .readAsStringSync()) as Map<String, dynamic>;
    await tester.runAsync(() async {
      await _clean();
      await IsoScanDao().insert(IsoScanRecord(
        id: 'scan17',
        name: 'Linia 3001',
        envelopeJson: jsonEncode(golden['envelope']),
        createdAt: DateTime(2026, 10, 10, 9, 30).millisecondsSinceEpoch,
      ));
    });

    await _openEditor(tester, _quote(QuoteSite.field));
    await tester.tap(find.byKey(const ValueKey('import-joints')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-source-scan')));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('ISO-P-3001 rev A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-scan-scan17')));
    await tester.pumpAndSettle();

    expect(find.text('Podgląd importu'), findsOneWidget);
    expect(find.textContaining('Zaznaczone: 1 z 1 pozycji (6 z 6 spoin)'),
        findsOneWidget);
    expect(find.text('6×'), findsOneWidget);
    expect(find.text('warsztat 4  ·  obiekt 2'), findsOneWidget);
    expect(find.text('Rodzaj nieoznaczony (6) — przyjęto doczołową'),
        findsOneWidget);
    // Obiekt → pozycja z wyceny PF, jako założenie.
    expect(
        find.text('PF·PH / 5G  ·  przyjęta z wyceny (brak w danych)'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('import-skipped')), findsNothing);

    // Monter wie lepiej: rura pochylona.
    await tester.tap(find.byTooltip('Pozycja spawania'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
        CheckedPopupMenuItem<WeldPosition>, WeldPosition.hl045.labelPl));
    await tester.pumpAndSettle();
    expect(find.text('H-L045 / 6G  ·  zmieniona ręcznie'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('6×'), findsOneWidget);
    expect(find.text('ISO-P-3001 rev A'), findsOneWidget);

    var joints = await _savedJoints(tester);
    expect(joints, hasLength(1));
    expect(joints.single.count, 6);
    expect(joints.single.kind, JointKind.pipeButt);
    expect(joints.single.position, WeldPosition.hl045);
    expect(joints.single.label, 'ISO-P-3001 rev A');
    expect((joints.single.odMm, joints.single.wallMm), (114.3, 6.02));

    // „Cofnij" zdejmuje tylko zaimportowane pozycje.
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.text('6×'), findsNothing);
    joints = await _savedJoints(tester);
    expect(joints, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('brak zapisanych skanów — komunikat zamiast listy',
      (tester) async {
    await tester.runAsync(_clean);
    await _openEditor(tester, _quote(QuoteSite.shop));
    await tester.tap(find.byKey(const ValueKey('import-joints')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-source-scan')));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie ma zapisanych skanów'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
    // Wstecz → wybór źródła, zamknięcie → wycena bez zmian.
    await tester.tap(find.byKey(const ValueKey('import-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-source-journal')), findsOneWidget);
    await tester.tap(find.byTooltip('Zamknij'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-joints')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-source-scan')), findsNothing);
  });
}
