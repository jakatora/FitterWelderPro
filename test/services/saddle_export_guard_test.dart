import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/saddle_template.dart';

class PendingTemplate extends SaddleTemplate {
  PendingTemplate() : super(headerOdMm: 100, branchOdMm: 60, angleDeg: 90);
  final pending = Completer<Uint8List>();
  @override
  Future<Uint8List> buildPdf({String? projectName, bool isEnglish = false}) =>
      pending.future;
}

void main() {
  test(
      'cancel stale snapshot after asynchronous PDF generation and before file/share APIs',
      () async {
    final template = PendingTemplate();
    var current = true;
    final saving = template.exportPdf(canShare: () => current);
    final cancelled =
        expectLater(saving, throwsA(isA<SaddleExportCancelled>()));
    current = false;
    template.pending.complete(Uint8List(0));
    await cancelled;
  });
  test('cancel export if requesting screen was disposed during PDF generation',
      () async {
    final template = PendingTemplate();
    var mounted = true;
    final saving = template.exportPdf(canShare: () => mounted);
    final cancelled =
        expectLater(saving, throwsA(isA<SaddleExportCancelled>()));
    mounted = false;
    template.pending.complete(Uint8List(0));
    await cancelled;
  });
}
