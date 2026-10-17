import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/qualification/iso9606_range.dart';
import 'package:cut_list_app/services/qualification_range_export.dart';

/// PDF „Zakres uprawnień z próbki”.
void main() {
  pw.Font font(String f) =>
      pw.Font.ttf(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

  // 141 grań + 111 wypełnienie na rurze, z dodatkową próbką pachwinową —
  // wszystkie rodzaje linii i uwag (także indeksy s₁ / s₂).
  final range = evaluateIso9606(const Iso9606Sample(
    product: Iso9606Product.pipe,
    first: Iso9606ProcessInput(
        process: Iso9606Process.p141,
        filler: Iso9606Filler.solid,
        thicknessMm: 3),
    second: Iso9606ProcessInput(
        process: Iso9606Process.p111,
        filler: Iso9606Filler.coveringBasic,
        thicknessMm: 9),
    fm: Iso9606FmGroup.fm1,
    diameterMm: 168.3,
    position: Iso6947Position.hL045,
    backing: Iso9606Backing.ssNb,
    layers: Iso9606Layers.threeOrMore,
    supplementaryFillet: true,
  )).range!;

  test('PDF się renderuje (PL i EN)', () async {
    for (final en in [false, true]) {
      final doc = QualificationRangeExport.buildPdfDocument(
        range: range,
        en: en,
        font: font('Roboto-Regular.ttf'),
        boldFont: font('Roboto-Bold.ttf'),
        generatedAt: DateTime(2026, 10, 17),
      );
      expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
    }
  });

  test('nazwa pliku z datą', () {
    expect(qualificationRangeFileName(DateTime(2026, 10, 17)),
        'Zakres_uprawnien_2026-10-17.pdf');
  });
}
