import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/saddle_template.dart';
import 'package:cut_list_app/services/saddle_print_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final angle in [15.0, 45.0, 90.0]) {
    test('real PDF renders all physical tiles at angle $angle', () async {
      final t =
          SaddleTemplate(headerOdMm: 200, branchOdMm: 100, angleDeg: angle);
      final bytes = await t.buildPdf(
          projectName: 'Próba: Łączenie rur / TEST', isEnglish: false);
      final pdf = latin1.decode(bytes);
      expect(pdf, startsWith('%PDF-'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length,
          SaddlePrintLayout(t).tiles.length + 2);
    });
  }
  test('PDF table supports non-default preview sampling', () async {
    final t = SaddleTemplate(
        headerOdMm: 200, branchOdMm: 100, angleDeg: 75, pointsCount: 26);
    expect(await t.buildPdf(isEnglish: true), isNotEmpty);
  });
  test('oversized print fails before allocating the PDF', () {
    final t = SaddleTemplate(headerOdMm: 2000, branchOdMm: 2000, angleDeg: 15);
    expect(t.buildPdf(), throwsA(isA<SaddlePrintTooLarge>()));
  });
  test('unbounded project metadata is rejected', () {
    final t = SaddleTemplate(headerOdMm: 100, branchOdMm: 60, angleDeg: 90);
    expect(t.buildPdf(projectName: 'a' * 161), throwsArgumentError);
  });
}
