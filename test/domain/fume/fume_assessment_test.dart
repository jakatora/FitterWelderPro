// Ocena stanowiska: brak danych ≠ OK, brak odciągu → nigdy zielono,
// odciąg sprawdzony tylko z rzeczywistą odległością X, błędna X nie znika,
// niesprawdzony odciąg → P3/TH3, ŚOI poniżej minimum → STOP, gazy wymagają
// punktu listy, sprzeczne „nie dotyczy” = otwarte, maska przylegająca
// ponad 1 h → ostrożnie, otwarta lista → nie zielono.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fume/fume_assessment.dart';
import 'package:cut_list_app/domain/fume/fume_capture.dart';
import 'package:cut_list_app/domain/fume/fume_checklist.dart';
import 'package:cut_list_app/domain/fume/fume_hazards.dart';

/// Wszystkie punkty zaznaczone.
Map<String, FumeCheckState> get _allDone =>
    {for (final c in kFumeChecks) c.id: FumeCheckState.done};

/// Odciąg w zasięgu: Q 1200 m³/h, D 300 mm → 24 cm, ssawka 20 cm od łuku.
FumeCaptureResult get _goodCapture => computeFumeCapture(
    const FumeCaptureInput(flow: 1200, diameter: 300, distance: 200))!;

FumeCaptureResult _capture(
        {double? flow = 1200, double? diameter = 300, double? distance}) =>
    computeFumeCapture(
        FumeCaptureInput(flow: flow, diameter: diameter, distance: distance))!;

FumeAssessment _assess({
  FumeMaterial? material = FumeMaterial.carbonSteel,
  FumeProcess? process = FumeProcess.migMag,
  FumeLevStatus? lev = FumeLevStatus.present,
  FumeCaptureResult? capture,
  bool noCapture = false,
  FumeRpe? rpe = FumeRpe.th2,
  Map<String, FumeCheckState>? checks,
  bool? longWear = false,
}) =>
    assessFume(
      material: material,
      process: process,
      lev: lev,
      capture: noCapture ? null : (capture ?? _goodCapture),
      rpe: rpe,
      checks: checks ?? _allDone,
      longWear: longWear,
    );

void main() {
  test('komplet: stal węglowa, ssawka 20 cm (zasięg 24), TH2, lista pełna → OK',
      () {
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

  test(
      'samo Q bez odległości X → „podaj odległość”, odciąg niesprawdzony, '
      'minimum P3/TH3', () {
    final qOnly = _capture();
    final a = _assess(capture: qOnly, rpe: FumeRpe.th2);
    expect(a.has(FumeReasonCode.captureDistanceMissing), isTrue);
    expect(a.levEffective, isFalse);
    expect(a.requirement, FumeRpeRequirement.p3OrTh3);
    expect(a.has(FumeReasonCode.rpeTooWeak), isTrue);
    expect(a.level, FumeLevel.stop);
    // Nawet z TH3 bez X nie ma zieleni.
    final th3 = _assess(capture: qOnly, rpe: FumeRpe.th3);
    expect(th3.level, FumeLevel.incomplete);
  });

  test(
      'błędna odległość X przy dobrej Q i Ø → nigdy zielono (5000 mm → STOP, '
      '„abc” i 0 → UZUPEŁNIJ)', () {
    final far = _assess(capture: _capture(distance: 5000), rpe: FumeRpe.th3);
    expect(far.has(FumeReasonCode.captureDistanceTooFar), isTrue);
    expect(far.levEffective, isFalse);
    expect(far.level, FumeLevel.stop);
    for (final bad in [double.nan, 0.0]) {
      final a = _assess(capture: _capture(distance: bad), rpe: FumeRpe.th3);
      expect(a.has(FumeReasonCode.captureDistanceInvalid), isTrue,
          reason: '$bad');
      expect(a.levEffective, isFalse, reason: '$bad');
      expect(a.level, FumeLevel.incomplete, reason: '$bad');
    }
  });

  test('odciąg za słaby na wpisaną odległość → STOP', () {
    final weak = computeFumeCapture(const FumeCaptureInput(
        flow: 847, diameter: 30, distance: 20, lengthUnit: FumeLengthUnit.cm))!;
    final a = _assess(capture: weak, rpe: FumeRpe.th3);
    expect(a.has(FumeReasonCode.captureInsufficient), isTrue);
    expect(a.level, FumeLevel.stop);
  });

  test('odległość poza zakresem równania → OSTROŻNIE, nie zielono', () {
    final far = _capture(flow: 2000, diameter: 150, distance: 250);
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

  group('gazy — filtr P ich nie zatrzymuje', () {
    for (final (m, p) in [
      (FumeMaterial.aluminium, FumeProcess.tig),
      (FumeMaterial.carbonSteel, FumeProcess.cutting),
    ]) {
      test(
          '${m.name} + ${p.name}: zielone dopiero po punkcie o gazach, '
          '„nie dotyczy” go nie zamyka', () {
        final open = {..._allDone}..remove(kFumeCheckGasId);
        final a =
            _assess(material: m, process: p, rpe: FumeRpe.th3, checks: open);
        expect(a.gasHazard, isTrue);
        expect(a.has(FumeReasonCode.gasHazard), isTrue);
        expect(a.level, isNot(FumeLevel.ok));
        final na = {..._allDone, kFumeCheckGasId: FumeCheckState.notApplicable};
        final b =
            _assess(material: m, process: p, rpe: FumeRpe.th3, checks: na);
        expect(b.has(FumeReasonCode.gasHazard), isTrue);
        expect(b.openChecks.map((c) => c.id), contains(kFumeCheckGasId));
        expect(b.level, isNot(FumeLevel.ok));
        final done = _assess(material: m, process: p, rpe: FumeRpe.th3);
        expect(done.has(FumeReasonCode.gasHazard), isFalse);
        expect(done.level, FumeLevel.ok);
      });
    }

    test('MMA na stali węglowej: bez gazów — punkt o gazach może być „n/d”',
        () {
      final na = {..._allDone, kFumeCheckGasId: FumeCheckState.notApplicable};
      final a = _assess(process: FumeProcess.mma, rpe: FumeRpe.th3, checks: na);
      expect(a.gasHazard, isFalse);
      expect(a.level, FumeLevel.ok);
    });
  });

  group('sprzeczne „nie dotyczy” liczy się jako otwarte', () {
    test('powłoka / ocynk / nieznany + „nie dotyczy: goły materiał”', () {
      final na = {
        ..._allDone,
        kFumeCheckCoatingsId: FumeCheckState.notApplicable,
      };
      for (final m in [
        FumeMaterial.coated,
        FumeMaterial.galvanised,
        FumeMaterial.other,
      ]) {
        final a = _assess(material: m, rpe: FumeRpe.th3, checks: na);
        expect(a.openChecks.map((c) => c.id), contains(kFumeCheckCoatingsId),
            reason: m.name);
        expect(a.has(FumeReasonCode.checklistOpen), isTrue, reason: m.name);
        expect(a.level, isNot(FumeLevel.ok), reason: m.name);
      }
      // Goła stal węglowa — „nie dotyczy” w porządku.
      expect(_assess(rpe: FumeRpe.th3, checks: na).level, FumeLevel.ok);
    });

    test('FFP3 + „nie dotyczy: przyłbica z nawiewem” przy dopasowaniu', () {
      final na = {..._allDone, kFumeCheckFitId: FumeCheckState.notApplicable};
      final a = _assess(rpe: FumeRpe.p3, checks: na);
      expect(a.openChecks.map((c) => c.id), contains(kFumeCheckFitId));
      expect(a.level, isNot(FumeLevel.ok));
      // Z nawiewem „nie dotyczy” w porządku.
      expect(_assess(rpe: FumeRpe.th3, checks: na).level, FumeLevel.ok);
    });
  });

  group('maska przylegająca a czas noszenia (HSE: FFP3/P3 do ok. 1 h)', () {
    test('brak odpowiedzi → brak zieleni; > 1 h → OSTROŻNIE; ≤ 1 h → OK', () {
      final unknown = _assess(rpe: FumeRpe.p3, longWear: null);
      expect(unknown.has(FumeReasonCode.wearTimeUnknown), isTrue);
      expect(unknown.level, FumeLevel.incomplete);
      final long = _assess(rpe: FumeRpe.p3, longWear: true);
      expect(long.has(FumeReasonCode.wearTooLong), isTrue);
      expect(long.level, FumeLevel.caution);
      expect(_assess(rpe: FumeRpe.p3, longWear: false).level, FumeLevel.ok);
    });

    test('nawiew TH2/TH3 — pytanie o czas nie dotyczy', () {
      for (final r in [FumeRpe.th2, FumeRpe.th3]) {
        for (final w in [null, true]) {
          final a = _assess(rpe: r, longWear: w);
          expect(a.has(FumeReasonCode.wearTimeUnknown), isFalse);
          expect(a.has(FumeReasonCode.wearTooLong), isFalse);
          expect(a.level, FumeLevel.ok, reason: '${r.name} $w');
        }
      }
    });
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
