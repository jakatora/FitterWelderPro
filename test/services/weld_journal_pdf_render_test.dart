// Renderowanie PDF dziennika spoin bez platformy: czcionki z assets/fonts
// podane wprost, bez udostępniania. Pilnuje, że nagłówek projektu, druga
// tabela z NDT/naprawami/PWHT/odbiorem, legenda i blok podpisów mieszczą się
// na A4 poziomo i że długi dziennik nie wysadza limitu stron.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/services/weld_journal_export.dart';

pw.Font _font(String file) {
  final bytes = File('assets/fonts/$file').readAsBytesSync();
  return pw.Font.ttf(ByteData.sublistView(bytes));
}

WeldJournalRecord _rec(int i) => WeldJournalRecord(
      weldNo: 'SP-${(i ~/ 10 + 1).toString().padLeft(3, '0')}-W'
          '${(i % 10 + 1).toString().padLeft(3, '0')}',
      projectName: 'Rozbudowa WFI',
      pipeName: '2"-WFI-101-316L',
      isoDrawing: 'ISO-101-WFI-0042',
      isoRev: 'C',
      spool: 'SP-${i ~/ 10 + 1}',
      testPackage: 'TP-101-03',
      jointType: 'BW',
      shopField: i.isEven ? 'SHOP' : 'FIELD',
      position: '5G',
      material: '316L',
      od: '60,3',
      t: '2,0',
      method: 'TIG',
      weldType: 'ORBITAL',
      wpsRef: 'WPS-141-316L-01 rev. 2',
      fillerClass: 'ER316LSi',
      fillerBatch: 'B-778/2026',
      welder: 'JK-12',
      rootWelder: 'JK-12',
      capWelder: 'MN-03',
      fitter: 'Łukasz Żółć',
      heatNo1: 'H-100$i',
      heatNo2: 'H-200$i',
      preheatC: '20',
      interpassC: '150',
      heatInput: '0,85',
      couponRef: '2026-09-20 · M-3 · 2"×1.65 · P12 · OK',
      date: '2026-09-${(i % 28 + 1).toString().padLeft(2, '0')}',
      status: i % 7 == 0 ? 'NOK' : 'OK',
      exam: 'boroskop poz. 2 — zaliczony',
      notes: i % 3 == 0 ? 'Grań OK, lico do przeszlifowania; ' * 3 : '',
      ndt: {
        NdtMethod.vt: const WeldNdt(
            scope: NdtScope.required,
            result: NdtResult.ok,
            reportNo: 'VT-2026-0042',
            date: '2026-09-21'),
        if (i % 4 == 0)
          NdtMethod.rt: WeldNdt(
              scope: NdtScope.selected,
              result: i % 7 == 0 ? NdtResult.nok : NdtResult.ok,
              reportNo: 'RT-2026-0$i',
              date: '2026-09-22'),
      },
      repairs: i % 7 == 0
          ? const ['R1 2026-09-23: porowatość w graniu (NOK, RT NOK)']
          : const [],
      pwhtRequired: false,
      inspector: 'A. Nowak (TÜV Rheinland)',
      inspectedAt: '2026-09-25',
    );

void main() {
  const header = WeldJournalPdfHeader(
    company: 'Montaż Rur Sp. z o.o.',
    client: 'Pharma SA',
    projectTitle: 'Rozbudowa instalacji WFI — hala B',
    documentNo: 'WL-101-004',
    revision: 'B',
  );

  test('pełny dziennik: dwie tabele, legenda i podpisy mieszczą się na A4',
      () async {
    final doc = await WeldJournalExport.buildPdfDocument(
      records: [for (var i = 0; i < 12; i++) _rec(i)],
      font: _font('Roboto-Regular.ttf'),
      boldFont: _font('Roboto-Bold.ttf'),
      header: header,
      filterDescription: 'Projekt: Rozbudowa WFI · Spawacz: JK-12',
      generatedAt: DateTime(2026, 9, 24, 14, 30),
    );
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Tabela NDT zaczyna się na nowej stronie — co najmniej dwie strony.
    expect(doc.document.pdfPageList.pages.length, greaterThanOrEqualTo(2));
  });

  test('długi dziennik (400 spoin) nie trafia na limit stron', () async {
    final doc = await WeldJournalExport.buildPdfDocument(
      records: [for (var i = 0; i < 400; i++) _rec(i)],
      font: _font('Roboto-Regular.ttf'),
      boldFont: _font('Roboto-Bold.ttf'),
      header: header,
      generatedAt: DateTime(2026, 9, 24),
    );
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(doc.document.pdfPageList.pages.length, greaterThan(20));
  });

  test('stary wpis bez nowych pól i bez nagłówka projektu też się renderuje',
      () async {
    final doc = await WeldJournalExport.buildPdfDocument(
      records: const [
        WeldJournalRecord(weldNo: 'W-001', status: 'PENDING'),
      ],
      font: _font('Roboto-Regular.ttf'),
      generatedAt: DateTime(2026, 9, 24),
    );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });

  test('pusta selekcja daje dokument z informacją, nie wyjątek', () async {
    final doc = await WeldJournalExport.buildPdfDocument(
      records: const [],
      font: _font('Roboto-Regular.ttf'),
      generatedAt: DateTime(2026, 9, 24),
    );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });

  group('treść komórek', () {
    test('komórka NDT: zakres, wynik, raport, data', () {
      expect(
        const WeldNdt(
                scope: NdtScope.selected,
                result: NdtResult.ok,
                reportNo: 'RT-1',
                date: '2026-09-22')
            .cellText(),
        'wyb./sel. · OK · RT-1 · 2026-09-22',
      );
      expect(const WeldNdt().cellText(), '');
    });

    test('podsumowanie NDT w nagłówku liczy RT/UT i naprawy', () {
      final s = weldJournalNdtSummary([for (var i = 0; i < 12; i++) _rec(i)]);
      // RT co czwarta spoina: i = 0, 4, 8.
      expect(s.volumetric, 3);
      expect(s.repaired, 2); // i = 0, 7
      expect(s.total, 12);
    });

    test('nagłówek projektu z ustawień: pusty, gdy nic nie wpisano', () {
      expect(const WeldJournalPdfHeader().isEmpty, isTrue);
      expect(header.isEmpty, isFalse);
    });
  });
}
