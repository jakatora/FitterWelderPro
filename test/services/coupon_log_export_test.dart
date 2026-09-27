import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/weld_journal/coupon_entry.dart';
import 'package:cut_list_app/services/coupon_log_export.dart';
import 'package:cut_list_app/services/weld_journal_export.dart'
    show kUtf8Bom, kWeldJournalCsvEol;

/// Log kuponów nie miał eksportu — audytor dostawał telefon do ręki.
/// Teraz CSV (Excel, średnik, BOM) i PDF z parametrami programu, odczytem O₂
/// i poziomem przebarwień wg AWS D18.2.
const _coupon = CouponEntry(
  id: 'c1',
  date: '2026-09-20',
  welder: 'JK-12',
  machine: 'Orbitalna M-3',
  size: '2"×1.65',
  result: 'OK',
  notes: 'boroskop poz. 2; przetop OK',
  programNo: '12',
  programParams: '85/45 A, 2.1 rpm',
  o2Ppm: 18.5,
  heatTint: 2,
);

List<String> _rows(String csv) {
  final body = csv.startsWith(kUtf8Bom) ? csv.substring(1) : csv;
  final rows = body.split(kWeldJournalCsvEol);
  if (rows.isNotEmpty && rows.last.isEmpty) rows.removeLast();
  return rows;
}

void main() {
  test('nagłówki CSV są dwujęzyczne i w stałej kolejności', () {
    expect(couponLogCsvHeaders, [
      'Data / Date',
      'Spawacz / Welder',
      'Maszyna / Machine',
      'Wymiar / Size',
      'Program',
      'Parametry / Parameters',
      'O₂ (ppm)',
      'Przebarwienie AWS D18.2 / Heat tint',
      'Wynik / Result',
      'Uwagi / Notes',
      'Przyjął / Accepted by',
    ]);
  });

  test('wartości trafiają pod swoje nagłówki, średnik w uwagach jest ujęty',
      () {
    final csv = buildCouponLogCsv([_coupon]);
    expect(csv.codeUnitAt(0), 0xFEFF);
    final row = _rows(csv)[1];
    // Cudzysłów cala w wymiarze jest podwojony i pole ujęte (RFC 4180).
    expect(row,
        startsWith('2026-09-20;JK-12;Orbitalna M-3;"2""×1.65";12;'));
    // Przecinek dziesiętny: polski Excel czyta "18.5" jako datę 18 maja.
    expect(row, contains(';18,5;'));
    expect(row, contains(';2 — Słomkowy / Light straw;'));
    expect(row, endsWith(';OK;"boroskop poz. 2; przetop OK";'));
  });

  test('kupon bez nowych pól (sprzed v20) ma puste komórki', () {
    const legacy = CouponEntry(
        id: 'x', date: '2026-03-02', welder: 'JK-12', machine: 'M-3',
        size: '', result: 'NOK', notes: '');
    final row = _rows(buildCouponLogCsv([legacy]))[1];
    expect(row, '2026-03-02;JK-12;M-3;;;;;;NOK;;');
  });

  test('nazwa pliku z datą', () {
    expect(couponLogFileName(extension: 'pdf', generatedAt: DateTime(2026, 9, 24)),
        'Log_kuponow_2026-09-24.pdf');
  });

  test('PDF renderuje się także dla pustego logu', () async {
    final font = pw.Font.ttf(ByteData.sublistView(
        File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync()));
    for (final list in [
      const <CouponEntry>[],
      [for (var i = 0; i < 80; i++) _coupon],
    ]) {
      final doc = await CouponLogExport.buildPdfDocument(
        coupons: list,
        font: font,
        generatedAt: DateTime(2026, 9, 24, 8),
      );
      expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
    }
  });

  test('parsowanie odczytu O₂', () {
    expect(parseO2Ppm('12'), 12);
    expect(parseO2Ppm('12,5 ppm'), 12.5);
    expect(parseO2Ppm(''), isNull);
    expect(parseO2Ppm('-3'), isNull);
    expect(formatO2Ppm(12), '12');
    expect(formatO2Ppm(12.5), '12.5');
  });
}
