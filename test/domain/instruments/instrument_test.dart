// Rejestr przyrządów: terminy, statusy, sortowanie, przypomnienia, eksport.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/instruments/instrument.dart';
import 'package:cut_list_app/services/instrument_export.dart';

Instrument _i(String id,
        {String last = '',
        int months = 12,
        String due = '',
        InstrumentKind kind = InstrumentKind.pressureGauge,
        String name = ''}) =>
    Instrument(
      id: id,
      kind: kind,
      name: name,
      lastCalibration: last,
      intervalMonths: months,
      dueOverride: due,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  final today = DateTime(2026, 10, 17);

  test('termin = ostatnia + interwał, z przycięciem końca miesiąca', () {
    expect(_i('a', last: '2026-01-31', months: 1).dueDate, DateTime(2026, 2, 28));
    expect(_i('a', last: '2025-10-17').dueDate, DateTime(2026, 10, 17));
  });

  test('termin ze świadectwa ma pierwszeństwo', () {
    expect(_i('a', last: '2026-01-01', due: '2026-03-15').dueDate,
        DateTime(2026, 3, 15));
  });

  test('status: po terminie, ≤ 30 dni, OK, brak daty', () {
    expect(_i('a', last: '2025-10-16').statusOn(today), InstrumentStatus.overdue);
    expect(_i('a', last: '2025-10-17').statusOn(today), InstrumentStatus.dueSoon);
    expect(_i('a', last: '2025-11-16').statusOn(today), InstrumentStatus.dueSoon);
    expect(_i('a', last: '2025-11-17').statusOn(today), InstrumentStatus.ok);
    expect(_i('a').statusOn(today), InstrumentStatus.unknown);
    expect(_i('a', last: '2025-10-16').daysLeft(today), -1);
  });

  test('„skalibrowane dziś” kasuje termin ręczny i liczy nowy z interwału', () {
    final c = _i('a', last: '2024-01-01', due: '2025-01-01', months: 6)
        .calibratedOn(today, certificateNo: 'ŚW-77');
    expect(c.lastCalibration, '2026-10-17');
    expect(c.dueOverride, '');
    expect(c.dueDate, DateTime(2027, 4, 17));
    expect(c.certificateNo, 'ŚW-77');
  });

  test('kolejność: po terminie, wkrótce, brak daty, OK', () {
    final sorted = sortForRegister([
      _i('ok', last: '2026-09-01'),
      _i('none'),
      _i('soon', last: '2025-11-01'),
      _i('late', last: '2025-01-01'),
    ], today);
    expect(sorted.map((e) => e.id), ['late', 'soon', 'none', 'ok']);
  });

  test('plan przypomnień: 30 i 7 dni przed, tylko przyszłe, unikalne id', () {
    final plan = planInstrumentReminders([
      _i('a', last: '2025-12-01'), // termin 2026-12-01
      _i('b', last: '2025-10-20'), // termin 2026-10-20 — 30 dni już minęło
      _i('c'), // brak terminu
    ], now: DateTime(2026, 10, 17, 12), english: false);
    expect(plan.map((p) => (p.certificateId, p.daysBefore)), [
      ('a', 30),
      ('a', 7),
    ]);
    expect(plan.first.fireAt, DateTime(2026, 11, 1, 9));
    expect(plan.map((p) => p.id).toSet(), hasLength(2));
    expect(plan.first.title, 'Kalibracja za 30 dni');
  });

  test('wiersz bazy tam i z powrotem; nieznany rodzaj → inny', () {
    final i = _i('x',
        last: '2026-05-05',
        months: 6,
        kind: InstrumentKind.torqueWrench,
        name: 'Stahlwille 730N');
    final back = Instrument.fromRow(i.toRow());
    expect(back.kind, InstrumentKind.torqueWrench);
    expect(back.intervalMonths, 6);
    expect(back.dueDate, DateTime(2026, 11, 5));
    expect(Instrument.fromRow({...i.toRow(), 'kind': 'XYZ'}).kind,
        InstrumentKind.other);
  });

  test('CSV i PDF rejestru', () async {
    final list = [
      _i('late', last: '2025-01-01', name: 'Manometr 0–40 bar'),
      _i('ok', last: '2026-09-01', name: 'Termometr'),
    ];
    final csv = buildInstrumentCsv(list, today);
    expect(csv, contains('PO TERMINIE / OVERDUE'));
    expect(csv.indexOf('Manometr'), lessThan(csv.indexOf('Termometr')));
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final doc = InstrumentExport.buildPdf(
        list: list,
        font: font('Roboto-Regular.ttf'),
        bold: font('Roboto-Bold.ttf'),
        generatedAt: today);
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });
}
