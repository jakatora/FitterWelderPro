// Protokół odbioru kołnierza do udostępnienia: tekst i PDF.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/flange/flange_check.dart';
import 'package:cut_list_app/services/flange_check_export.dart';

FlangeCheck _protocol({LengthUnit unit = LengthUnit.mm}) => FlangeCheck(
      id: 'p1',
      joint: const FlangeJoint(
        tag: 'L-101/F1 (wlot)',
        dn: 150,
        rating: 'CL300',
        gasketType: 'Spiralna z pierścieniem',
        gasketThicknessMm: 4.5,
        boltGrade: 'A193 B7 / A194 2H',
        boltCount: 12,
        location: 'Płock — estakada 3',
        fitter: 'Łukasz Żółć',
        date: '2026-10-17',
      ),
      measurements: const FlangeMeasurements(
        centerlineMm: 1.2,
        rotationMm: 3.5,
        gapsMm: [3.0, 3.4, 3.2, 3.6],
        force: AlignmentForce.light,
      ),
      checked: {FlangeChecklistItem.faces, FlangeChecklistItem.gasket},
      unit: unit,
      notes: 'Dokręcać po próbie szczelności',
    );

ByteData _font(String f) =>
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());

void main() {
  test('tekst PL: werdykt, dane, kryteria z przecinkiem, lista', () {
    final t = buildFlangeCheckText(_protocol(), en: false);
    expect(t, contains('PROTOKÓŁ ODBIORU POŁĄCZENIA KOŁNIERZOWEGO'));
    expect(t, contains('Werdykt: Niezgodny — popraw osiowanie'));
    expect(t, contains('Oznaczenie: L-101/F1 (wlot)'));
    expect(t, contains('Średnica: DN150 / 6"'));
    expect(t, contains('Uszczelka: Spiralna z pierścieniem, 4,5 mm'));
    expect(t, contains('Śruby: 12 × A193 B7 / A194 2H'));
    expect(t,
        contains('Przesunięcie osi (high/low): 1,2 mm ≤ 1,5 mm (1/16") — OK'));
    expect(
        t,
        contains(
            'Przesunięcie obrotowe otworów: 3,5 mm ≤ 3 mm (1/8") — Poza tolerancją'));
    expect(t, contains('0,6 mm ≤ 0,8 mm (1/32") — OK'));
    expect(t, contains('3,6 mm ≤ 2 × 4,5 mm = 9 mm — OK'));
    expect(t, contains('0°: 3 · 90°: 3,4 · 180°: 3,2 · 270°: 3,6'));
    expect(t, contains('[x] Właściwa uszczelka, nowa'));
    expect(t, contains('[ ] Kolejność dokręcania i rundy'));
    expect(t, contains('Uwagi: Dokręcać po próbie szczelności'));
    expect(t, contains('Tolerancje: ASME PCC-1-2019 zał. E.'));
  });

  test('tekst EN w calach: kropka dziesiętna, granica calowa pierwsza', () {
    final t = buildFlangeCheckText(_protocol(unit: LengthUnit.inch), en: true);
    expect(t, contains('FLANGE JOINT ASSEMBLY CHECK'));
    expect(t, contains('1/16" (1.5 mm)'));
    expect(t, contains('Measured in inches.'));
    expect(t, isNot(contains('0,')));
  });

  test('niekompletny protokół mówi, czego brakuje', () {
    final t = buildFlangeCheckText(
        const FlangeCheck(id: 'e', joint: FlangeJoint(tag: 'X')),
        en: false);
    expect(t, contains('Werdykt: Niekompletny'));
    expect(t, contains('brak pomiarów: 5 · nieodhaczone punkty listy: 5'));
  });

  test('nazwa pliku bez znaków psujących ścieżkę', () {
    expect(flangeCheckFileName(_protocol(), extension: 'pdf'),
        'Kolnierz_L-101_F1_wlot_2026-10-17.pdf');
    expect(flangeCheckFileName(const FlangeCheck(id: 'z'), extension: 'pdf'),
        'Kolnierz_protokol.pdf');
    expect(
        flangeCheckFileName(
            const FlangeCheck(id: 'z', joint: FlangeJoint(tag: '///')),
            extension: 'txt'),
        'Kolnierz_protokol.txt');
  });

  test('Roboto ma każdy znak protokołu (PL i EN)', () {
    final regular = TtfParser(_font('Roboto-Regular.ttf'));
    final text = [
      buildFlangeCheckText(_protocol(), en: false),
      buildFlangeCheckText(_protocol(unit: LengthUnit.inch), en: true),
    ].join();
    final missing = {
      for (final r in text.runes)
        if (r > 32 && !regular.charToGlyphIndexMap.containsKey(r))
          String.fromCharCode(r)
    };
    expect(missing, isEmpty);
  });

  test('PDF renderuje się z polskimi fontami', () async {
    for (final en in [false, true]) {
      final doc = buildFlangeCheckPdf(
        _protocol(),
        font: pw.Font.ttf(_font('Roboto-Regular.ttf')),
        boldFont: pw.Font.ttf(_font('Roboto-Bold.ttf')),
        en: en,
        generatedAt: DateTime(2026, 10, 17, 9, 30),
      );
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    }
  });
}
