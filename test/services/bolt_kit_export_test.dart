// Zamówienie śrub do kołnierzy do udostępnienia: tekst i PDF.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/bolting/bolt_kit.dart';
import 'package:cut_list_app/services/bolt_kit_export.dart';

BoltKitOrder _order({int spare = 10}) => buildBoltKitOrder([
      const BoltKitJoint(
        id: 'a',
        dn: 150,
        cls: 300,
        facing: FlangeFacing.rf,
        material: BoltMaterial.b7,
        count: 4,
      ),
      const BoltKitJoint(
        id: 'b',
        dn: 80,
        cls: 600,
        facing: FlangeFacing.rtj,
        material: BoltMaterial.b8m,
        count: 2,
      ),
    ], sparePercent: spare);

ByteData _font(String f) =>
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());

void main() {
  test('tekst PL: połączenia, szpilki, nakrętki, uszczelki z zapasem', () {
    final t = buildBoltKitText(_order(), en: false);
    expect(t, contains('ZAMÓWIENIE ŚRUB DO KOŁNIERZY'));
    expect(t, contains('Połączenia (6):'));
    expect(
        t,
        contains('• 4 × DN150 (6") · Class 300 · RF — A193 B7 / A194 2H, '
            'spiralna (ASME B16.20), 12 × 3/4" × 4-3/4"'));
    expect(
        t,
        contains('• 2 × DN80 (3") · Class 600 · RTJ — A193 B8M / A194 8M, '
            'pierścień R31, 8 × 3/4" × 5"'));
    expect(
        t,
        contains('• 3/4" × 4-3/4" (120,65 mm) A193 B7 — 48 szt. + zapas 10 % '
            '= 53 szt.'));
    expect(
        t,
        contains(
            '• 3/4" × 5" (127 mm) A193 B8M — 16 szt. + zapas 10 % = 18 szt.'));
    expect(t,
        contains('• 3/4" heavy hex A194 2H — 96 szt. + zapas 10 % = 106 szt.'));
    expect(t,
        contains('• 3/4" heavy hex A194 8M — 32 szt. + zapas 10 % = 36 szt.'));
    expect(
        t,
        contains(
            '• spiralna (ASME B16.20), NPS 6 Class 300 — 4 szt. + zapas 10 % '
            '= 5 szt.'));
    expect(
        t,
        contains(
            '• pierścień R31 (ASME B16.20), NPS 3 Class 600 — 2 szt. + zapas 10 % = 3 szt.'));
    expect(t, contains('Zapas: 10 % (zaokrąglony w górę).'));
    expect(t, contains('ASME B16.5'));
  });

  test('tekst EN: kropka dziesiętna, bez zapasu — same ilości', () {
    final t = buildBoltKitText(_order(spare: 0), en: true);
    expect(t, contains('FLANGE BOLTING ORDER'));
    expect(t, contains('3/4" × 4-3/4" (120.65 mm) A193 B7 — 48 pcs'));
    expect(t, isNot(contains('120,65')));
    expect(t, isNot(contains('spare')));
  });

  test('nazwa pliku z datą', () {
    expect(boltKitFileName(DateTime(2026, 10, 7), extension: 'pdf'),
        'Sruby_kolnierze_2026-10-07.pdf');
  });

  test('Roboto ma każdy znak zamówienia (PL i EN)', () {
    final regular = TtfParser(_font('Roboto-Regular.ttf'));
    final text = [
      buildBoltKitText(_order(), en: false),
      buildBoltKitText(_order(), en: true),
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
      final doc = buildBoltKitPdf(
        _order(),
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

  test('PDF z długą listą (60 połączeń) — kilka stron, bez wyjątku', () async {
    final joints = [
      for (var i = 0; i < 60; i++)
        BoltKitJoint(
          id: 'j$i',
          dn: const [15, 50, 100, 150, 300][i % 5],
          cls: const [150, 300, 600, 900, 1500][(i ~/ 5) % 5],
          facing: FlangeFacing.rf,
          material: BoltMaterial.values[i % BoltMaterial.values.length],
          count: i + 1,
        ),
    ];
    final doc = buildBoltKitPdf(
      buildBoltKitOrder(joints, sparePercent: 20),
      font: pw.Font.ttf(_font('Roboto-Regular.ttf')),
      en: false,
      generatedAt: DateTime(2026, 10, 17),
    );
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(doc.document.pdfPageList.pages.length, greaterThan(1));
  });
}
