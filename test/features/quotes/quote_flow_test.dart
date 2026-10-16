// Wyceny spawalnicze: zapis w bazie (v26), PDF, tekst do wysłania,
// „moje stawki" i przepływ na ekranie: nowa wycena → spoina → zapis.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/quotes/quote_process.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/features/quotes/quote_joint_page.dart';
import 'package:cut_list_app/features/quotes/quote_list_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/quote_export.dart';
import 'package:cut_list_app/services/quote_settings.dart';

import '../../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

WeldQuote _sample({String id = 'q1', String number = 'WYC/2026/001'}) =>
    WeldQuote(
      id: id,
      number: number,
      title: 'Kolektor DN100',
      client: 'Zakład Chemiczny SA',
      material: QuoteMaterial.stainless,
      purge: true,
      site: QuoteSite.field,
      rates: QuoteRates.defaultsFor(QuoteMaterial.stainless).copyWith(
        ndt: {NdtMethod.rt: const NdtRate(percent: 10, pricePerJoint: 150)},
      ),
      joints: const [
        QuoteJoint(
          id: 'j1',
          kind: JointKind.pipeButt,
          sizeLabel: 'DN100 Sch 10S',
          odMm: 114.3,
          wallMm: 3.05,
          count: 20,
          position: WeldPosition.pf,
        ),
        QuoteJoint(
          id: 'j2',
          kind: JointKind.pipeFillet,
          sizeLabel: 'DN25',
          odMm: 33.4,
          throatMm: 3,
          count: 8,
          scheme: WeldScheme.single(QuoteProcess.tig),
        ),
      ],
      extras: const [
        QuoteExtra(
            id: 'e1',
            description: 'Dojazd',
            quantity: 200,
            unit: 'km',
            unitPrice: 1.2),
      ],
      createdAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
    );

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('schemat v26: tabela weld_quotes istnieje', () async {
    final db = await AppDatabase.get();
    final cols = (await db.rawQuery('PRAGMA table_info(weld_quotes)'))
        .map((r) => r['name'])
        .toSet();
    expect(
        cols,
        containsAll(<String>[
          'id',
          'number',
          'title',
          'client',
          'status',
          'data_json',
          'net_grosze',
          'gross_grosze',
          'created_at',
          'updated_at',
          'deleted_at',
        ]));
    expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(26));
  });

  test('DAO: zapis z sumami, kosz, numeracja, duplikat', () async {
    final db = await AppDatabase.get();
    await db.delete('weld_quotes');
    var t = DateTime(2026, 6, 1).millisecondsSinceEpoch;
    final dao = WeldQuoteDao(clock: () => t++);
    final saved = await dao.save(_sample());
    final row = (await db.query('weld_quotes')).single;
    final r = computeQuote(saved);
    expect(row['net_grosze'], r.netGrosze);
    expect(row['gross_grosze'], r.grossGrosze);
    expect(r.netGrosze, greaterThan(0));

    final back = (await dao.listAll()).single;
    expect(back.joints, hasLength(2));
    expect(back.material, QuoteMaterial.stainless);
    expect(computeQuote(back).grossGrosze, r.grossGrosze);

    expect(await dao.nextNumber(DateTime(2026, 5)), 'WYC/2026/002');

    final copy = await dao.duplicate(back, titleSuffix: '(kopia)');
    expect(copy.number, 'WYC/2026/002');
    expect(copy.title, 'Kolektor DN100 (kopia)');
    expect(copy.status, QuoteStatus.draft);
    expect(copy.id, isNot(back.id));
    expect(await dao.listAll(), hasLength(2));

    await dao.softDelete(back.id);
    expect(await dao.listAll(), hasLength(1));
    expect(await dao.listAll(onlyDeleted: true), hasLength(1));
    // Numer usuniętej oferty nie wraca na nową.
    expect(await dao.nextNumber(DateTime(2026, 5)), 'WYC/2026/003');
    await dao.restore(back.id);
    expect(await dao.listAll(), hasLength(2));
  });

  test('PDF dla klienta i wewnętrzny renderują się (PL i EN)', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final q = _sample();
    for (final internal in [false, true]) {
      for (final en in [false, true]) {
        final doc = QuoteExport.buildPdfDocument(
          quote: q,
          result: computeQuote(q),
          settings: const QuoteSettings(
              company: QuoteCompany(name: 'Spaw-Mont Kowalski', taxId: '123')),
          internal: internal,
          en: en,
          font: font('Roboto-Regular.ttf'),
          boldFont: font('Roboto-Bold.ttf'),
          generatedAt: DateTime(2026, 10, 2),
        );
        expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
      }
    }
    expect(quoteFileName(q, internal: false, en: false),
        'Oferta_WYC-2026-001.pdf');
    expect(quoteFileName(q, internal: true, en: true),
        'Cost_estimate_WYC-2026-001.pdf');
  });

  test('tekst do wysłania: zakres, netto, VAT, brutto — bez narzutu', () {
    final q = _sample();
    final r = computeQuote(q);
    final text = buildQuoteShareText(
        quote: q,
        result: r,
        settings: const QuoteSettings(
            company: QuoteCompany(person: 'Jan', phone: '600 100 200')),
        en: false);
    expect(text, contains('Wycena WYC/2026/001'));
    expect(text, contains('20 × Spoina doczołowa rury DN100 Sch 10S'));
    expect(text, contains('Netto: ${formatPln(r.netGrosze)}'));
    expect(text, contains('Brutto: ${formatPln(r.grossGrosze)}'));
    expect(text, contains('Dojazd'));
    expect(text, isNot(contains('Zysk')));
    expect(text, contains('Jan, 600 100 200'));
  });

  test('moje stawki: zapis i odczyt, ceny spoiw per materiał', () async {
    const store = QuoteSettingsStore();
    final s = const QuoteSettings()
        .copyWith(
      baseRates: const QuoteRates(welderRate: 120, vat: QuoteVat.notApplicable),
      company: const QuoteCompany(name: 'Firma'),
      material: QuoteMaterial.duplex,
      terms: 'Płatność 14 dni',
    )
        .withFillerPrices(QuoteMaterial.duplex, {QuoteProcess.tig: 199});
    await store.save(s);
    final back = await store.load();
    expect(back.baseRates.welderRate, 120);
    expect(back.baseRates.vat, QuoteVat.notApplicable);
    expect(back.company.name, 'Firma');
    expect(back.material, QuoteMaterial.duplex);
    expect(back.terms, 'Płatność 14 dni');
    final rates = back.ratesFor(QuoteMaterial.duplex);
    expect(rates.fillerPriceOf(QuoteProcess.tig), 199);
    // Proces bez zapamiętanej ceny — cena domyślna materiału.
    expect(rates.fillerPriceOf(QuoteProcess.mma),
        kDefaultFillerPrices[QuoteMaterial.duplex]![QuoteProcess.mma]);
    expect(rates.welderRate, 120);
  });

  testWidgets('nowa wycena → spoina wpisana ręcznie → zapis i lista',
      (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('weld_quotes');
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: QuoteListPage()),
    ));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Ile kosztuje ta robota?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-quote')));
    await _settle(tester);
    await tester.pumpAndSettle();
    // Edytor otwiera się na zakładce „Spoiny".
    expect(find.byKey(const ValueKey('add-joint')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-joint')));
    await tester.pumpAndSettle();
    expect(find.byType(QuoteJointPage), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Średnica OD'), '114,3');
    await tester.enterText(find.widgetWithText(TextField, 'Ścianka t'), '6,02');
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('count-plus')));
      await tester.pump();
    }
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-joint')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pozycja netto (4 szt.)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-joint')));
    await tester.pumpAndSettle();

    // Pozycja na liście i suma na pasku.
    expect(find.text('4×'), findsOneWidget);
    expect(find.textContaining('Ø114,3 × 6,02'), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-total-bar')), findsOneWidget);

    // Autozapis po chwili.
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    final rows = (await tester.runAsync(() => WeldQuoteDao().listAll()))!;
    expect(rows, hasLength(1));
    expect(rows.single.joints.single.count, 4);
    expect(rows.single.number, startsWith('WYC/'));

    // Wynik: kwota brutto i przyciski wysyłki.
    await tester.tap(find.byKey(const ValueKey('quote-total-bar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-client')), findsOneWidget);

    // Powrót do listy — karta wyceny.
    await tester.pageBack();
    await _settle(tester);
    await tester.pumpAndSettle();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Wycena bez nazwy'), findsOneWidget);
    expect(find.textContaining('4 spoin'), findsOneWidget);
  });

  testWidgets('pusta wycena nie zapisuje się przy wyjściu', (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('weld_quotes');
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: QuoteListPage()),
    ));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-quote')));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await _settle(tester);
    await tester.pumpAndSettle();
    final rows = (await tester.runAsync(() => WeldQuoteDao().listAll()))!;
    expect(rows, isEmpty);
    expect(find.text('Ile kosztuje ta robota?'), findsOneWidget);
  });
}
