import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/qualification/certificate_status.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/services/qualification_export.dart';

/// Eksport rejestru uprawnień i logu ciągłości (P2 G5).
void main() {
  final cert = WelderCertificate(
    id: 'c1',
    standard: QualificationStandard.iso9606_1,
    welderStamp: 'JK-12',
    certNo: 'PL-001',
    examiner: 'UDT',
    testDate: DateTime(2026, 1, 10),
    lastConfirmedDate: DateTime(2026, 7, 1),
    confirmations: [
      CertificateConfirmation(
          id: 'k1',
          certificateId: 'c1',
          date: DateTime(2026, 7, 1),
          confirmedBy: 'J. Koordynator',
          createdAt: 0),
    ],
    processes: '141',
    thicknessMinMm: 1.5,
    thicknessMaxMm: 6,
    createdAt: 0,
    updatedAt: 0,
  );
  final e = evaluateCertificate(cert,
      asOf: DateTime(2026, 9, 26), journalWelds: [DateTime(2026, 9, 1)]);

  test('CSV: rejestr ze statusem i terminem', () {
    final csv = buildQualificationCsv([e]);
    final row = csv.split('\r\n')[1];
    expect(row.split(';').length, qualificationCsvHeaders.length);
    expect(row, contains('PL-001'));
    expect(row, contains('2027-01-01'));
    expect(row, contains('ważny / valid'));
    expect(row, contains('1.5–6'));
  });

  test('log ciągłości: egzamin, potwierdzenie z autorem, ostatnia spoina', () {
    final rows = continuityLogRows(e);
    expect(rows.map((r) => r.$1), ['2026-01-10', '2026-07-01', '2026-09-01']);
    expect(rows[1].$3, 'J. Koordynator');
  });

  test('PDF się renderuje', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final doc = await QualificationExport.buildPdfDocument(
      evaluations: [e],
      font: font('Roboto-Regular.ttf'),
      boldFont: font('Roboto-Bold.ttf'),
      generatedAt: DateTime(2026, 9, 26),
    );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });
}
