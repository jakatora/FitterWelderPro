// Ocena stanowiska: brak danych ≠ OK, brak odciągu → nigdy zielono,
// niesprawdzony odciąg → P3/TH3, ŚOI poniżej minimum → STOP, otwarta lista
// → nie zielono.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fume/fume_assessment.dart';
import 'package:cut_list_app/domain/fume/fume_capture.dart';
import 'package:cut_list_app/domain/fume/fume_checklist.dart';
import 'package:cut_list_app/domain/fume/fume_hazards.dart';

/// Wszystkie punkty zaznaczone.
Map<String, FumeCheckState> get _allDone =>
    {for (final c in kFumeChecks) c.id: FumeCheckState.done};

/// Odciąg w zasięgu (Q 1200 m³/h, D 300 mm → 24 cm, granica 45 cm).
FumeCaptureResult get _goodCapture =>
    computeFumeCapture(const FumeCaptureInput(flow: 1200, diameter: 300))!;

FumeAssessment _assess({
  FumeMaterial? material = FumeMaterial.carbonSteel,
  FumeProcess? process = FumeProcess.migMag,
  FumeLevStatus? lev = FumeLevStatus.present,
  FumeCaptureResult? capture,
  bool noCapture = false,
  FumeRpe? rpe = FumeRpe.th2,
  Map<String, FumeCheckState>? checks,
}) =>
    assessFume(
      material: material,
      process: process,
      lev: lev,
      capture: noCapture ? null : (capture ?? _goodCapture),
      rpe: rpe,
      checks: checks ?? _allDone,
    );

void main() {
  test('komplet: stal węglowa, odciąg w zasięgu, TH2, lista pełna → OK', () {
    final a = _assess();
    expect(a.reasons, isEmpty);
    expect(a.levEffective, isTrue);
    expect(a.requirement, FumeRpeRequirement.apf20);
    expect(a.level, FumeLevel.ok);
  });

  test('brak danych to nie OK — każde puste pole to powód', () {
    final a = assessFume(
      material: null,
      process: null,
      lev: null,
      capture: null,
      rpe: null,
      checks: const {},
    );
    expect(a.level, FumeLevel.incomplete);
    for (final c in [
      FumeReasonCode.materialMissing,
      FumeReasonCode.processMissing,
      FumeReasonCode.levUnknown,
      FumeReasonCode.rpeMissing,
      FumeReasonCode.checklistOpen,
    ]) {
      expect(a.has(c), isTrue, reason: c.name);
    }
  });

  test('brak odciągu → nigdy zielono, nawet z TH3 i pełną listą', () {
    final a =
        _assess(lev: FumeLevStatus.absent, noCapture: true, rpe: FumeRpe.th3);
    expect(a.has(FumeReasonCode.levAbsent), isTrue);
    expect(a.level, FumeLevel.caution);
    expect(a.level, isNot(FumeLevel.ok));
    // Bez odciągu minimum rośnie do P3/TH3 — TH2 to już STOP.
    final th2 =
        _assess(lev: FumeLevStatus.absent, noCapture: true, rpe: FumeRpe.th2);
    expect(th2.requirement, FumeRpeRequirement.p3OrTh3);
    expect(th2.has(FumeReasonCode.rpeTooWeak), isTrue);
    expect(th2.level, FumeLevel.stop);
  });

  test('odciąg „jest”, ale niesprawdzony → nie zielono i minimum P3/TH3', () {
    final a = _assess(noCapture: true, rpe: FumeRpe.th2);
    expect(a.has(FumeReasonCode.captureUnverified), isTrue);
    expect(a.levEffective, isFalse);
    expect(a.requirement, FumeRpeRequirement.p3OrTh3);
    expect(a.has(FumeReasonCode.rpeTooWeak), isTrue);
    expect(a.level, FumeLevel.stop);
  });

  test('odciąg za słaby na wpisaną odległość → STOP', () {
    final weak = computeFumeCapture(const FumeCaptureInput(
        flow: 847, diameter: 30, distance: 20, lengthUnit: FumeLengthUnit.cm))!;
    final a = _assess(capture: weak, rpe: FumeRpe.th3);
    expect(a.has(FumeReasonCode.captureInsufficient), isTrue);
    expect(a.level, FumeLevel.stop);
  });

  test('wynik poza zakresem równania → OSTROŻNIE, nie zielono', () {
    final far =
        computeFumeCapture(const FumeCaptureInput(flow: 1000, diameter: 150))!;
    final a = _assess(capture: far, rpe: FumeRpe.th3);
    expect(a.has(FumeReasonCode.captureOutOfRange), isTrue);
    expect(a.level, FumeLevel.caution);
  });

  test('nierdzewka z dobrym odciągiem: TH2 za mało, P3 i TH3 wystarczają', () {
    final th2 = _assess(material: FumeMaterial.stainless, rpe: FumeRpe.th2);
    expect(th2.requirement, FumeRpeRequirement.p3OrTh3);
    expect(th2.level, FumeLevel.stop);
    for (final r in [FumeRpe.p3, FumeRpe.th3]) {
      expect(
          _assess(material: FumeMaterial.stainless, rpe: r).level, FumeLevel.ok,
          reason: r.name);
    }
  });

  test('FFP2 nigdy nie wystarcza, nawet na stali węglowej z odciągiem', () {
    final a = _assess(rpe: FumeRpe.p2);
    expect(a.has(FumeReasonCode.rpeTooWeak), isTrue);
    expect(a.level, FumeLevel.stop);
  });

  test('jeden otwarty punkt listy → nie zielono', () {
    final checks = _allDone..remove('lev-close');
    final a = _assess(checks: checks);
    expect(a.has(FumeReasonCode.checklistOpen), isTrue);
    expect(a.openChecks.map((c) => c.id), ['lev-close']);
    expect(a.level, isNot(FumeLevel.ok));
  });

  test('gorsza ocena wygrywa: stop > ostrożnie > uzupełnij > ok', () {
    expect(FumeLevel.ok.worse(FumeLevel.incomplete), FumeLevel.incomplete);
    expect(FumeLevel.incomplete.worse(FumeLevel.caution), FumeLevel.caution);
    expect(FumeLevel.caution.worse(FumeLevel.stop), FumeLevel.stop);
    expect(FumeLevel.stop.worse(FumeLevel.ok), FumeLevel.stop);
  });
}
