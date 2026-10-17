// PDF protokołu temperatur renderuje się z Roboto (polskie znaki) —
// wypełniony i pusty, PL i EN, °C i °F; nazwa pliku z numerem spoiny
// i datą pierwszego pomiaru.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/services/interpass_export.dart';

pw.Font _font(String f) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

Future<List<int>> _render(InterpassWeld w,
    {required bool english, InterpassUnit unit = InterpassUnit.c}) async {
  final doc = await InterpassExport.buildPdfDocument(
    weld: w,
    english: english,
    unit: unit,
    font: _font('Roboto-Regular.ttf'),
    boldFont: _font('Roboto-Bold.ttf'),
    generatedAt: DateTime(2026, 10, 17, 9, 30),
  );
  return doc.save();
}

int _ms(int h, int m) => DateTime(2026, 10, 17, h, m).millisecondsSinceEpoch;

final _filled = InterpassWeld(
  id: 'w',
  weldNo: 'S-12 / ISO-0042',
  description: 'Linia 100-P-12, P91, rura Ø168,3 × 18,26 — żółta strefa',
  wpsRef: 'WPS-091 rev B',
  limits: const InterpassLimits(
      preheatMinC: 200, interpassMaxC: 300, interpassMinC: 200),
  method: InterpassMethod.crayon,
  passCount: 3,
  readings: [
    InterpassReading(
        pass: 1,
        tempC: 200,
        bound: InterpassBound.atLeast,
        method: InterpassMethod.crayon,
        at: _ms(7, 10),
        recordedAt: _ms(7, 10)),
    InterpassReading(
        pass: 2,
        tempC: 320,
        at: _ms(8, 0),
        recordedAt: _ms(8, 0),
        note: 'za gorąco — odczekano'),
    InterpassReading(
        pass: 2, tempC: 280, at: _ms(8, 15), recordedAt: _ms(9, 0)),
    InterpassReading(
        pass: 3,
        tempC: 300,
        bound: InterpassBound.below,
        method: InterpassMethod.crayon,
        at: _ms(8, 50),
        recordedAt: _ms(8, 50)),
  ],
  createdAt: _ms(7, 0),
  updatedAt: _ms(9, 0),
);

void main() {
  test('wypełniony protokół — PL i EN, °C i °F', () async {
    for (final en in [false, true]) {
      for (final unit in InterpassUnit.values) {
        final bytes = await _render(_filled, english: en, unit: unit);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    }
  });

  test('pusta spoina (bez limitów i pomiarów) też się renderuje', () async {
    final bytes = await _render(
        InterpassWeld.blank(id: 'b', now: DateTime(2026, 10, 17)),
        english: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('nazwa pliku: nr spoiny bez znaków specjalnych, data pomiaru', () {
    expect(interpassFileName(_filled, english: false),
        'Temperatura_miedzysciegowa_S-12_ISO-0042_2026-10-17.pdf');
    expect(interpassFileName(_filled, english: true),
        'Interpass_record_S-12_ISO-0042_2026-10-17.pdf');
    expect(
        interpassFileName(InterpassWeld(id: 'x', createdAt: 0, updatedAt: 0),
            english: false),
        'Temperatura_miedzysciegowa.pdf');
  });
}
