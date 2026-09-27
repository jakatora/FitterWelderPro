// Rejestr trawienia / pasywacji (v25): zabieg zapisany w bazie, eksport
// CSV z polskimi przecinkami, PDF, miękkie usuwanie.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/passivation_dao.dart';
import 'package:cut_list_app/domain/passivation/passivation_record.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/passivation_screen.dart';
import 'package:cut_list_app/services/passivation_export.dart';

import '../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();

  const rec = PassivationRecord(
    id: 'p1',
    date: '2026-09-25',
    treatment: PassivationTreatment.both,
    line: '2"-WFI-101',
    testPackage: 'TP-03',
    agent: 'Pasta X',
    agentBatch: 'B-12',
    dwellMin: 45,
    tempC: 18.5,
    rinseUsCm: 1.2,
    testMethod: 'ferroxyl',
    testResult: PassivationResult.ok,
    byStamp: 'JK-12',
    createdAt: 1,
    updatedAt: 1,
  );

  test('CSV: nagłówki, przecinek dziesiętny, zabieg PL/EN', () {
    final csv = buildPassivationCsv([rec]);
    expect(csv, contains('Pakiet testowy / Test package'));
    expect(csv, contains('18,5'));
    expect(csv, contains('Trawienie + pasywacja / Pickling + passivation'));
    expect(csv.split('\r\n')[1].split(';').length,
        passivationCsvHeaders.length);
  });

  test('PDF się renderuje', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final doc = await PassivationExport.buildPdfDocument(
      records: [rec],
      font: font('Roboto-Regular.ttf'),
      boldFont: font('Roboto-Bold.ttf'),
      generatedAt: DateTime(2026, 9, 26),
    );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });

  test('DAO: zapis, edycja, miękkie usuwanie i przywrócenie', () async {
    final db = await AppDatabase.get();
    await db.delete('passivation_records');
    final dao = PassivationDao();
    await dao.save(rec);
    await dao.save(PassivationRecord.fromRow({...rec.toRow(), 'area': 'W-1…W-9'}));
    expect((await dao.listAll()).single.area, 'W-1…W-9');
    await dao.softDelete('p1');
    expect(await dao.listAll(), isEmpty);
    expect(await dao.listAll(includeDeleted: true), hasLength(1));
    await dao.restore('p1');
    expect(await dao.listAll(), hasLength(1));
  });

  testWidgets('zakładka „Rejestr”: dodanie zabiegu zapisuje wiersz',
      (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('passivation_records');
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: PassivationScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rejestr'));
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Brak wpisów.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('passivation-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Linia'), 'L-100');
    await tester.enterText(
        find.widgetWithText(TextField, 'Środek (produkt)'), 'Pasta Y');
    await tester.tap(find.byKey(const ValueKey('passivation-save')));
    await tester.pumpAndSettle();
    await _settle(tester);
    await tester.pumpAndSettle();

    final rows =
        (await tester.runAsync(() => PassivationDao().listAll()))!;
    expect(rows.single.line, 'L-100');
    expect(rows.single.agent, 'Pasta Y');
    expect(find.textContaining('L-100'), findsOneWidget);
  });
}
