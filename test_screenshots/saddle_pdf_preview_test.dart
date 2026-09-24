import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/saddle_template.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate real application PDFs for physical-scale and visual review',
      () async {
    final output = Directory(const String.fromEnvironment(
        'SADDLE_PDF_PREVIEW_DIR',
        defaultValue: 'test_screenshots/shots'));
    final qa = Directory(const String.fromEnvironment('SADDLE_PDF_QA_DIR',
        defaultValue: 'test_screenshots/shots'));
    await output.create(recursive: true);
    await qa.create(recursive: true);
    for (final sample in [
      (
        200.0,
        100.0,
        15.0,
        false,
        '${output.path}/szablon-siodla-przyklad-15-stopni.pdf',
        73
      ),
      (100.0, 60.0, 90.0, false, '${qa.path}/saddle-90-pl.pdf', 73),
      (200.0, 100.0, 75.0, true, '${qa.path}/saddle-75-en.pdf', 26),
    ]) {
      final template = SaddleTemplate(
          headerOdMm: sample.$1,
          branchOdMm: sample.$2,
          angleDeg: sample.$3,
          pointsCount: sample.$6);
      final bytes = await template.buildPdf(
          projectName: sample.$4
              ? 'TEST EXAMPLE - verify dimensions before use'
              : 'PRZYKŁAD TESTOWY - sprawdź wymiary przed użyciem',
          isEnglish: sample.$4);
      await File(sample.$5).writeAsBytes(bytes);
      expect(bytes, isNotEmpty);
    }
  });
}
