// PDF planu PWHT renderuje się z Roboto (polskie znaki) — z wykresem
// i bez (P-No 8).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/pwht/pwht_plan.dart';
import 'package:cut_list_app/services/pwht_plan_export.dart';

pw.Font _font(String f) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

Future<List<int>> _render(PwhtPlan plan, {required bool english}) async {
  final doc = await PwhtPlanExport.buildPdfDocument(
    plan: plan,
    english: english,
    font: _font('Roboto-Regular.ttf'),
    boldFont: _font('Roboto-Bold.ttf'),
    generatedAt: DateTime(2026, 10, 16, 9, 30),
  );
  return doc.save();
}

void main() {
  test('plan z cyklem (P91, 40 mm, OD 273) — PL i EN', () async {
    final plan = planPwht(const PwhtInput(
      code: PwhtCode.asmeB313,
      material: PwhtMaterial.p15e,
      thicknessMm: 40,
      outsideDiameterMm: 273,
      weldWidthMm: 30,
    ))!;
    for (final en in [false, true]) {
      final bytes = await _render(plan, english: en);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('plan bez cyklu (P-No 8) też się renderuje', () async {
    final plan = planPwht(const PwhtInput(
      code: PwhtCode.asmeB311,
      material: PwhtMaterial.p8,
      thicknessMm: 10,
    ))!;
    final bytes = await _render(plan, english: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('długi cykl (P-No 1, 150 mm) — oś czasu bez błędów', () async {
    final plan = planPwht(const PwhtInput(
      code: PwhtCode.asmeB313,
      material: PwhtMaterial.p1,
      thicknessMm: 150,
    ))!;
    final bytes = await _render(plan, english: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('nazwa pliku z datą', () {
    expect(pwhtPlanFileName(generatedAt: DateTime(2026, 1, 5)),
        'Plan_PWHT_2026-01-05.pdf');
  });
}
