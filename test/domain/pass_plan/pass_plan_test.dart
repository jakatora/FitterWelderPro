// Plan ściegów i elektrod — reguły domeny, każda z testem.
//
// Przykład warsztatowy (domyślne wejście): 8 złączy 168,3 × 7,11, rowek V
// 60°, szczelina 2,5, próg 1,5; grań TIG Ø2,4, ścieg gorący Ø2,5 × 350,
// lico Ø3,2 × 350; elektrody EN ISO 2560-A … B z piecyka.
//  • pola (tg 30° = 0,57735): grań do 3 mm = 2,5·3 + 1,5²·tg 30° + ⅔·4,5·1
//    = 11,799 mm²; lico = rowek 5,11…7,11 (5 + (5,61² − 3,61²)·tg 30° =
//    15,646) + nadlew ⅔·11,978·1,5 = 11,978 → 27,624 mm²; między nimi
//    11,500 mm² — mniej niż ścieg Ø2,5 (12 mm²), więc całe idzie w ścieg
//    gorący, bez wypełnienia; lico 27,624 / 18 = 1,53 → 2 ściegi;
//  • karta ESAB OK 48.00: Ø2,5 × 350 — 65 el./kg (15,38 g), 57 s;
//    Ø3,2 × 350 — 42 el./kg (23,81 g), 68 s;
//  • na złącze: TIG 1,348 pręta (→ 2), Ø2,5 3,067 (→ 4), Ø3,2 4,761 (→ 5);
//    na 8 złączy z dokładnych: 10,79 → 11, 24,54 → 25, 38,09 → 39; z zapasem
//    10 %: 12, 27, 42; czas złącza 43,3 → 44 min, całość 346,4 → 347 min;
//  • grań TIG: 11,799 / 12 mm² → 1 ścieg;
//  • ekspozycja: 240 min − 30 min = 210 min; tempo do „ile naraz” z dolnej
//    granicy TWI (TIG 25 %, MMA 15 %): czas złącza 5,458/0,25 +
//    8,310/0,15 = 77,23 min → 3,067/1,2872 h = 2,383 i 4,761/1,2872 =
//    3,699 el./h → 8,34 → 8 i 12,9 → 12 naraz (w dół); porcje z tempa wg
//    planu (4,251 i 6,598 el./h, cała robota 5,77 h): 25/8 → 4, 39/12 → 4.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/pass_plan/pass_plan.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_form.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_sources.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_text.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/quotes/quote_process.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';

const _example = PassPlanInput();
final _tan30 = math.tan(math.pi / 6);

PassPlanResult _plan(PassPlanInput i) {
  final r = planPasses(i);
  expect(r, isNotNull, reason: passPlanProblems(i).toString());
  return r!;
}

PassSupply _supply(PassPlanResult r, PassConsumable c) =>
    r.supplies.singleWhere((s) => s.consumable == c);

ExposureTake _take(PassPlanResult r, double d) =>
    r.exposure!.takes.singleWhere((t) => t.electrode.diameterMm == d);

void main() {
  group('przekrój i warstwy', () {
    test('przykład 168,3 × 7,11 V60: grań, ścieg gorący, 2 ściegi lica', () {
      final a = passLayerAreas(_example);
      final root = 2.5 * 3 + 1.5 * 1.5 * _tan30 + 2 / 3 * 4.5 * 1.0;
      final capGroove = 2.5 * 2 + (5.61 * 5.61 - 3.61 * 3.61) * _tan30;
      final capW = 2.5 + 2 * 5.61 * _tan30 + 3;
      final cap = capGroove + 2 / 3 * capW * 1.5;
      expect(a.root, closeTo(root, 1e-9));
      expect(a.root, closeTo(11.799, 0.001));
      expect(a.cap, closeTo(cap, 1e-9));
      expect(a.cap, closeTo(27.624, 0.001));
      expect(a.hot, closeTo(11.500, 0.001));
      expect(a.fill, 0);

      final r = _plan(_example);
      expect([for (final l in r.layers) l.layer],
          [PassLayer.root, PassLayer.hot, PassLayer.cap]);
      expect([for (final l in r.layers) l.passes], [1, 1, 2]);
      expect(r.passesPerJoint, 4);
    });

    test('suma warstw = przekrój i objętość z geometrii wyceny', () {
      for (final i in [
        _example,
        _example.copyWith(odMm: 219.1, wallMm: 12.7),
        _example.copyWith(odMm: 60.3, wallMm: 3.91),
        _example.copyWith(
            kind: JointKind.plateButt, wallMm: 20, groove: GrooveType.x),
        _example.copyWith(
            kind: JointKind.plateButt, wallMm: 4, groove: GrooveType.square),
        _example.copyWith(kind: JointKind.plateFillet, throatMm: 8),
        _example.copyWith(kind: JointKind.pipeFillet, throatMm: 5),
      ]) {
        final r = _plan(i);
        final vol = volumesOf(quoteJointOf(i));
        final sumV = r.layers.fold(0.0, (s, l) => s + l.volumeMm3);
        expect(sumV, closeTo(vol.totalMm3, 1e-6), reason: '${i.kind}');
        final sumA = r.layers.fold(0.0, (s, l) => s + l.areaMm2);
        final total = i.kind.isFillet
            ? plateFilletVolumes(throat: i.throatMm, lengthMm: 1).totalMm3
            : plateButtVolumes(
                    t: i.wallMm,
                    lengthMm: 1,
                    groove: i.groove,
                    gap: i.gapMm,
                    rootFace: i.groove == GrooveType.square ? 0 : i.rootFaceMm,
                    includedAngleDeg:
                        i.groove == GrooveType.square ? 0 : i.angleDeg)
                .totalMm3;
        expect(sumA, closeTo(total, 1e-6), reason: '${i.kind} ${i.groove}');
      }
    });

    test('blacha: objętość warstwy = pole × długość', () {
      final i = _example.copyWith(
          kind: JointKind.plateButt, wallMm: 12, lengthM: 1.5, count: 1);
      for (final l in _plan(i).layers) {
        expect(l.volumeMm3, closeTo(l.areaMm2 * 1500, 1e-6));
      }
    });

    test('liczba ściegów W GÓRĘ, dokładna wielokrotność bez dodatku', () {
      final cap = passLayerAreas(_example).cap;
      PassLayerPlan capOf(double bead) =>
          _plan(_example.copyWith(beadAreasMm2: {PassConsumable.mma32: bead}))
              .layer(PassLayer.cap)!;
      expect(capOf(cap).passes, 1);
      expect(capOf(cap - 0.01).passes, 2);
      expect(capOf(cap / 3).passes, 3);
      expect(capOf(cap / 3 - 0.01).passes, 4);
    });

    test('resztka wypełnienia < ½ ściegu idzie do lica, większa — ścieg', () {
      // Ścieg gorący 10 mm² → zostaje 1,5 mm² < 9 mm² (½ z 18) → do lica.
      final merged =
          _plan(_example.copyWith(beadAreasMm2: {PassConsumable.mma25: 10}));
      expect(merged.fillMerged, isTrue);
      expect(merged.layer(PassLayer.fill), isNull);
      expect(
          merged.layer(PassLayer.cap)!.areaMm2, closeTo(27.624 + 1.5, 0.001));
      // Bez ściegu gorącego → 11,5 mm² ≥ 9 → osobny ścieg wypełnienia.
      final fill = _plan(_example.copyWith(hot: () => null));
      expect(fill.fillMerged, isFalse);
      expect(fill.layer(PassLayer.fill)!.passes, 1);
      expect(fill.layer(PassLayer.fill)!.areaMm2, closeTo(11.5, 0.001));
    });

    test('cienka ścianka 60,3 × 3,91: bez miejsca na ścieg gorący', () {
      final r = _plan(_example.copyWith(odMm: 60.3, wallMm: 3.91));
      expect(r.hotNoRoom, isTrue);
      expect(
          [for (final l in r.layers) l.layer], [PassLayer.root, PassLayer.cap]);
    });

    test('rowek X: grań i lico po 2 ściegi, bez ściegu gorącego', () {
      final r = _plan(_example.copyWith(
          kind: JointKind.plateButt,
          wallMm: 20,
          groove: GrooveType.x,
          gapMm: 2,
          rootFaceMm: 2,
          count: 1));
      expect(r.hotNotApplicable, isTrue);
      expect(r.layer(PassLayer.hot), isNull);
      expect(r.layer(PassLayer.root)!.passes, 2);
      expect(r.layer(PassLayer.cap)!.passes, greaterThanOrEqualTo(2));
    });

    test('grań: ściegi z przekroju ściegu spoiwa grani — szczelina 6 mm → 3',
        () {
      // Szczelina 6: 6·3 + 1,5²·tg 30° + ⅔·8·1 = 24,632 mm² / 12 → 3 ściegi.
      final wide = _plan(_example.copyWith(gapMm: 6));
      final root = wide.layer(PassLayer.root)!;
      expect(root.areaMm2,
          closeTo(6 * 3 + 1.5 * 1.5 * _tan30 + 2 / 3 * 8 * 1.0, 1e-9));
      expect(root.passes, 3);
      // Przekrój ściegu grani z pola: 25 mm² → 1 ścieg; zawsze co najmniej 1.
      final big = _plan(
          _example.copyWith(gapMm: 6, beadAreasMm2: {PassConsumable.tig: 25}));
      expect(big.layer(PassLayer.root)!.passes, 1);
      // Przykład 2,5 mm: 11,799 / 12 → 1.
      expect(_plan(_example).layer(PassLayer.root)!.passes, 1);
      // Przekrój ściegu spoiwa grani jest sprawdzany jak pozostałe.
      expect(_example.beadConsumables, contains(PassConsumable.tig));
      expect(
          passPlanProblems(
              _example.copyWith(beadAreasMm2: {PassConsumable.tig: 0})),
          contains(const PassPlanProblem(PassPlanProblemKind.beadArea,
              consumable: PassConsumable.tig)));
    });

    test('pachwina: a ≤ 3 mm — jeden ścieg; a = 6 — grań i lico', () {
      final single = _plan(_example.copyWith(
          kind: JointKind.plateFillet, throatMm: 3, count: 1));
      expect(single.layers.single.layer, PassLayer.root);
      expect(single.passesPerJoint, 1);
      final six = _plan(_example.copyWith(
          kind: JointKind.plateFillet, throatMm: 6, count: 1));
      expect([for (final l in six.layers) l.layer],
          [PassLayer.root, PassLayer.cap]);
      // Lico: 1,1·(6² − 4²) = 22 + resztka 1,1·(4² − 3²) = 7,7 < 9 → 29,7.
      expect(six.layer(PassLayer.cap)!.areaMm2, closeTo(29.7, 1e-9));
      expect(six.fillMerged, isTrue);
    });
  });

  group('elektrody, pręty, drut', () {
    test('karta ESAB OK 48.00: masa z elektrod/kg zgodna z wydajnością·czasem',
        () {
      for (final row in kOk4800Card) {
        final fromRate = row.depositionKgH * 1000 * row.fusionTimeS / 3600;
        expect(row.depositG, closeTo(fromRate, row.depositG * 0.03),
            reason: '${row.diameterMm} × ${row.lengthMm}');
      }
      final r32 = electrodeRowFor(PassConsumable.mma32, long: false);
      expect(r32.depositG, closeTo(23.81, 0.01));
      expect(electrodeRowFor(PassConsumable.mma32, long: true).lengthMm, 450);
      // Ø2,5 nie ma 450 mm w karcie → 350 mm.
      expect(electrodeRowFor(PassConsumable.mma25, long: true).lengthMm, 350);
    });

    test('ogarek: masa stopiwa z elektrody proporcjonalna do zużytej długości',
        () {
      final row = electrodeRowFor(PassConsumable.mma32, long: false);
      expect(
          depositPerElectrodeG(row, kCardStubMm), closeTo(row.depositG, 1e-9));
      expect(depositPerElectrodeG(row, 80),
          closeTo(row.depositG * 270 / 300, 1e-9));
      final base = _plan(_example).layer(PassLayer.cap)!;
      final longStub =
          _plan(_example.copyWith(stubMm: 80)).layer(PassLayer.cap)!;
      expect(longStub.units, closeTo(base.units * 300 / 270, 1e-9));
      expect(longStub.unitsCeil, 6);
      // Czas łuku zależy od masy stopiwa, nie od ogarka.
      expect(longStub.arcMin, closeTo(base.arcMin, 1e-9));
    });

    test('przykład: sztuki na złącze i na 8 złączy W GÓRĘ z dokładnych', () {
      final r = _plan(_example);
      final tig = _supply(r, PassConsumable.tig);
      final e25 = _supply(r, PassConsumable.mma25);
      final e32 = _supply(r, PassConsumable.mma32);
      expect(tig.unitsPerJoint, closeTo(1.348, 0.001));
      expect(e25.unitsPerJoint, closeTo(3.067, 0.001));
      expect(e32.unitsPerJoint, closeTo(4.761, 0.001));
      expect(
          [tig.unitsPerJointCeil, e25.unitsPerJointCeil, e32.unitsPerJointCeil],
          [2, 4, 5]);
      expect([tig.unitsJob, e25.unitsJob, e32.unitsJob], [11, 25, 39]);
      expect([
        tig.unitsJobWithReserve,
        e25.unitsJobWithReserve,
        e32.unitsJobWithReserve
      ], [
        12,
        27,
        42
      ]);
      // Z dokładnych, nie z zaokrągleń złącza: 8 × 4 = 32 > 25.
      expect(e25.unitsJob, lessThan(8 * e25.unitsPerJointCeil));
    });

    test('zapas: 0 % = bez dodatku, nigdy ujemny', () {
      final r0 = _plan(_example.copyWith(reservePct: 0));
      final e32 = _supply(r0, PassConsumable.mma32);
      expect(e32.unitsJobWithReserve, e32.unitsJob);
      expect(passPlanProblems(_example.copyWith(reservePct: -5)),
          contains(const PassPlanProblem(PassPlanProblemKind.reserve)));
      final r50 = _plan(_example.copyWith(reservePct: 50));
      // 38,09 × 1,5 = 57,1 → 58.
      expect(_supply(r50, PassConsumable.mma32).unitsJobWithReserve, 58);
    });

    test('pręt TIG: masa / uzysk profilu / masa pręta 1000 mm', () {
      final p = kDefaultProcessProfiles[QuoteProcess.tig]!;
      final root = _plan(_example).layer(PassLayer.root)!;
      final rod = 7.85e-3 * math.pi / 4 * 2.4 * 2.4 * 1000;
      expect(tigRodMassG(2.4), closeTo(rod, 1e-9));
      expect(rod, closeTo(35.5, 0.1));
      expect(root.fillerG, closeTo(root.depositG / p.efficiency, 1e-9));
      expect(root.units, closeTo(root.fillerG / rod, 1e-9));
      expect(root.arcMin,
          closeTo(root.depositG / 1000 / p.depositionKgH * 60, 1e-9));
      // Grubszy pręt — mniej sztuk.
      final thick =
          _plan(_example.copyWith(tigRodMm: 3.2)).layer(PassLayer.root)!;
      expect(thick.units, lessThan(root.units));
    });

    test('drut MAG w kg W GÓRĘ do 0,01; same procesy drutowe — bez ekspozycji',
        () {
      final i = _example.copyWith(
          kind: JointKind.plateButt,
          wallMm: 10,
          lengthM: 1,
          count: 3,
          root: PassConsumable.mag,
          hot: () => null,
          fill: PassConsumable.mag,
          cap: PassConsumable.mag);
      final r = _plan(i);
      final p = kDefaultProcessProfiles[QuoteProcess.mag]!;
      final mag = _supply(r, PassConsumable.mag);
      final exactKg = r.depositGPerJoint / p.efficiency * 3 / 1000;
      expect(mag.fillerKgJob, greaterThanOrEqualTo(exactKg));
      expect(mag.fillerKgJob - exactKg, lessThan(0.01));
      expect(r.arcMinPerJoint,
          closeTo(r.depositGPerJoint / 1000 / p.depositionKgH * 60, 1e-9));
      expect(r.exposure, isNull);
    });
  });

  group('czas', () {
    test('czas pracy = łuk / współczynnik jarzenia łuku (profil wyceny)', () {
      final r = _plan(_example);
      for (final l in r.layers) {
        final f = kDefaultProcessProfiles[l.consumable.process]!.dutyCycle;
        expect(l.workMin, closeTo(l.arcMin / f, 1e-9));
      }
      expect(r.workMinPerJoint, closeTo(43.30, 0.01));
      expect(minutesText(r.workMinPerJoint), '44 min');
      expect(minutesText(r.workMinJob), '5 h 47 min');
      // MMA 25 % zamiast 30 % — elektrody trwają dłużej.
      final slow = _plan(_example.copyWith(arcOnPct: {QuoteProcess.mma: 25}));
      final cap = slow.layer(PassLayer.cap)!;
      expect(cap.workMin, closeTo(cap.arcMin / 0.25, 1e-9));
      expect(slow.workMinPerJoint, greaterThan(r.workMinPerJoint));
    });

    test('czas złącza: wpisany współczynnik, najwyżej górna granica TWI', () {
      final base = _plan(_example);
      // MMA 100 % → czas liczony z 30 % (górna granica TWI) — jak domyślnie.
      final fast = _plan(_example.copyWith(arcOnPct: {QuoteProcess.mma: 100}));
      expect(
          _example.copyWith(arcOnPct: {
            QuoteProcess.mma: 100
          }).arcOnCappedForTime(QuoteProcess.mma),
          isTrue);
      expect(fast.workMinPerJoint, closeTo(base.workMinPerJoint, 1e-9));
      // TIG 100 % → 40 % zamiast 35 % — krócej, ale nie krócej niż z 40 %.
      final tig = _plan(_example.copyWith(arcOnPct: {QuoteProcess.tig: 100}));
      final root = tig.layer(PassLayer.root)!;
      expect(root.workMin, closeTo(root.arcMin / 0.40, 1e-9));
      expect(arcOnUpperBoundPct(QuoteProcess.mma), 30);
      expect(arcOnUpperBoundPct(QuoteProcess.tig), 40);
      expect(arcOnUpperBoundPct(QuoteProcess.mag), 45);
    });

    test('czas łuku elektrody z czasu stapiania karty', () {
      final cap = _plan(_example).layer(PassLayer.cap)!;
      final row = electrodeRowFor(PassConsumable.mma32, long: false);
      expect(cap.arcMin * 60, closeTo(cap.units * row.fusionTimeS, 1e-6));
    });
  });

  group('ekspozycja', () {
    test(
        'przykład: limit 4 h − 30 min, łuk z dolnej granicy TWI → najwyżej '
        '8 Ø2,5 i 12 Ø3,2 (w dół), 4 porcje', () {
      final e = _plan(_example).exposure!;
      expect(e.limitMinutes,
          defaultLimitMinutes(ElectrodeClass.enIso2560B, ElectrodeSource.oven));
      expect(e.limitMinutes, 240);
      expect(e.leadMinutes, warnLeadMinutes(240));
      expect(e.windowMinutes, 210);
      expect(e.arcOnPctUsed, {QuoteProcess.tig: 25.0, QuoteProcess.mma: 15.0});
      expect(e.workMinPerJoint, closeTo(77.23, 0.01));
      final r = _plan(_example);
      expect(_take(r, 2.5).ratePerH, closeTo(2.383, 0.001));
      expect(_take(r, 3.2).ratePerH, closeTo(3.699, 0.001));
      expect(_take(r, 2.5).plannedRatePerH, closeTo(4.251, 0.001));
      expect(_take(r, 3.2).plannedRatePerH, closeTo(6.598, 0.001));
      expect(_take(r, 2.5).maxAtOnce, 8);
      expect(_take(r, 3.2).maxAtOnce, 12);
      for (final t in e.takes) {
        final exact = e.windowMinutes / 60 * t.ratePerH;
        expect(t.maxAtOnce!, lessThanOrEqualTo(exact));
        expect(t.maxAtOnce! + 1, greaterThan(exact));
      }
      // Porcje z tempa wg planu: 25 / 8 → 4, 39 / 12 → 4.
      expect(e.portions, 4);
      expect(e.wholeJobInShift, isTrue);
    });

    test('współczynnik jarzenia łuku 100 % nie zwiększa „ile naraz”', () {
      final base = _plan(_example);
      final fast = _plan(_example
          .copyWith(arcOnPct: {QuoteProcess.mma: 100, QuoteProcess.tig: 100}));
      for (final d in [2.5, 3.2]) {
        expect(_take(fast, d).maxAtOnce, _take(base, d).maxAtOnce);
        expect(_take(fast, d).ratePerH, closeTo(_take(base, d).ratePerH, 1e-9));
      }
      // Niżej niż dolna granica (MMA 10 %) — wolniej, mniej naraz.
      final slow = _plan(_example.copyWith(arcOnPct: {QuoteProcess.mma: 10}));
      expect(_take(slow, 2.5).maxAtOnce, 6);
      expect(_take(slow, 3.2).maxAtOnce, 9);
      // Przegląd całego zakresu pola: nigdy więcej niż przy dolnej granicy.
      for (var pct = 5.0; pct <= 100; pct += 5) {
        final r = _plan(_example.copyWith(arcOnPct: {QuoteProcess.mma: pct}));
        for (final d in [2.5, 3.2]) {
          expect(_take(r, d).maxAtOnce!,
              lessThanOrEqualTo(_take(base, d).maxAtOnce!),
              reason: '$pct % Ø$d');
        }
      }
    });

    test('limit dłuższy niż tabela: bez potwierdzenia z tabeli, z — przyjęty',
        () {
      // Literówka „2400” zamiast „240” — bez potwierdzenia liczymy z tabeli.
      final typo = _plan(_example.copyWith(limitMinutes: () => 2400)).exposure!;
      expect(typo.limitMinutes, 240);
      expect(typo.tableLimitMinutes, 240);
      expect(typo.typedLimitMinutes, 2400);
      expect(typo.limitRaiseIgnored, isTrue);
      expect(typo.limitFromTable, isTrue);
      expect(typo.takes.map((t) => t.maxAtOnce), [8, 12]);
      expect(exposureLimitNoteText(typo, en: false),
          contains('Wpisany limit 40 h 00 min jest dłuższy niż z tabeli'));
      // Z potwierdzeniem „WPS / karta producenta pozwala na dłużej”.
      final ok = _plan(_example.copyWith(
              limitMinutes: () => 2400, limitAboveTableConfirmed: true))
          .exposure!;
      expect(ok.limitMinutes, 2400);
      expect(ok.limitRaiseConfirmed, isTrue);
      expect(ok.limitRaiseIgnored, isFalse);
      // Krótszy (ostrzejszy) zawsze przyjęty, także bez potwierdzenia.
      final strict =
          _plan(_example.copyWith(limitMinutes: () => 120)).exposure!;
      expect(strict.limitMinutes, 120);
      expect(strict.limitRaiseIgnored, isFalse);
      expect(exposureLimitNoteText(strict, en: false), isNull);
      // Potwierdzenie nie zmienia krótszego limitu.
      final strictOk = _plan(_example.copyWith(
              limitMinutes: () => 120, limitAboveTableConfirmed: true))
          .exposure!;
      expect(strictOk.limitMinutes, 120);
      expect(strictOk.limitRaiseConfirmed, isFalse);
    });

    test('limit z tabeli modułu ekspozycji: H4R 9 h, opakowanie próżniowe 8 h',
        () {
      final r =
          _plan(_example.copyWith(electrodeClass: () => ElectrodeClass.e7018R));
      expect(r.exposure!.limitMinutes, 540);
      final pack =
          _plan(_example.copyWith(source: ElectrodeSource.hermeticPack));
      expect(pack.exposure!.limitMinutes, 480);
      expect(pack.exposure!.windowMinutes, 450);
    });

    test('limit z WPS w dół do minuty, zapas jak w module ekspozycji', () {
      final e = _plan(_example.copyWith(limitMinutes: () => 59.9)).exposure!;
      expect(e.limitMinutes, 59);
      expect(e.limitFromTable, isFalse);
      expect(e.leadMinutes, warnLeadMinutes(59));
      expect(e.windowMinutes, 49);
    });

    test('okno krótsze niż jedna elektroda: 0 naraz, bez liczby porcji', () {
      final e = _plan(_example.copyWith(limitMinutes: () => 12)).exposure!;
      expect(e.windowMinutes, 2);
      expect(e.takes.every((t) => t.maxAtOnce == 0), isTrue);
      expect(e.someBelowOne, isTrue);
      expect(e.portions, isNull);
    });

    test(
        'częściowe zero „ile naraz”: przypis „po jednej” w tekście, porcje '
        'tylko dla reszty', () {
      // E10018-X: 30 min − 10 min = 20 min; Ø2,5 2,383 × ⅓ = 0,79 → 0,
      // Ø3,2 3,699 × ⅓ = 1,23 → 1.
      final r = _plan(
          _example.copyWith(electrodeClass: () => ElectrodeClass.e10018X));
      final e = r.exposure!;
      expect(e.windowMinutes, 20);
      expect(_take(r, 2.5).maxAtOnce, 0);
      expect(_take(r, 3.2).maxAtOnce, 1);
      expect(e.someBelowOne, isTrue);
      expect(e.belowOneTakes.single.electrode.diameterMm, 2.5);
      // Porcje tylko dla Ø3,2: 39 / 1 = 39 — i opis, że Ø2,5 po jednej.
      expect(e.portions, 39);
      final portions = exposurePortionsText(e, en: false);
      expect(portions, contains('39 porcji'));
      expect(portions, contains('tylko Ø3,2; Ø2,5 po jednej'));
      final note = exposureBelowOneText(e, en: false)!;
      expect(note, startsWith('Ø2,5: okno krótsze niż zużycie jednej'));
      final share = passPlanShareText(r, en: false);
      expect(share, contains('! $note'));
      expect(share, contains(portions));
      final en = passPlanShareText(r, en: true);
      expect(en, contains('! ${exposureBelowOneText(e, en: true)}'));
      expect(en, contains('only Ø3.2; Ø2.5 one at a time'));
      // Bez częściowego zera — bez przypisu.
      expect(
          exposureBelowOneText(_plan(_example).exposure!, en: false), isNull);
    });

    test('elektroda nie zasadowa: bez limitu — całość z zapasem, 1 porcja', () {
      final r = _plan(_example.copyWith(electrodeClass: () => null));
      final e = r.exposure!;
      expect(e.hasLimit, isFalse);
      expect(_take(r, 2.5).maxAtOnce, isNull);
      expect(_take(r, 2.5).takeNow, 27);
      expect(_take(r, 3.2).takeNow, 42);
      expect(e.portions, 1);
    });

    test('najpierw granie: tempo bez grani TIG — więcej naraz', () {
      final r = _plan(_example.copyWith(order: WorkOrder.rootsFirst));
      expect(r.exposure!.order, WorkOrder.rootsFirst);
      // Bez grani: 8,310 / 0,15 = 55,4 min → 3,322 i 5,156 el./h × 3,5 h.
      expect(_take(r, 2.5).maxAtOnce, 11);
      expect(_take(r, 3.2).maxAtOnce, 18);
      // Grań elektrodą — kolejność nie ma znaczenia, liczymy złącze po złączu.
      final mmaRoot = _plan(_example.copyWith(
          root: PassConsumable.mma25, order: WorkOrder.rootsFirst));
      expect(mmaRoot.exposure!.order, WorkOrder.jointByJoint);
    });

    test('porcje na zmianę: potrzebne w zmianie / najwięcej naraz, W GÓRĘ', () {
      final r = _plan(_example.copyWith(count: 20));
      final e = r.exposure!;
      expect(e.wholeJobInShift, isFalse);
      expect(e.hoursInShift, 8);
      // Tempo wg planu: Ø2,5 4,251 × 8 = 34,01 → 35, / 8 → 5; Ø3,2 52,8 →
      // 53, / 12 → 5.
      expect(_take(r, 2.5).neededInShift, 35);
      expect(_take(r, 3.2).neededInShift, 53);
      expect(e.portions, 5);
      // Krótsza zmiana — mniej porcji: 9 / 8 → 2, 14 / 12 → 2.
      final short = _plan(_example.copyWith(count: 20, shiftH: 2)).exposure!;
      expect(short.portions, 2);
    });
  });

  group('brak danych = brak wyniku', () {
    test('puste / nieczytelne pole → problem i null, nie zero', () {
      final cases = <PassPlanInput, PassPlanProblem>{
        _example.copyWith(odMm: double.nan): const PassPlanProblem(
            PassPlanProblemKind.joint,
            joint: JointProblem.od),
        _example.copyWith(wallMm: double.nan): const PassPlanProblem(
            PassPlanProblemKind.joint,
            joint: JointProblem.wall),
        _example.copyWith(gapMm: double.nan):
            const PassPlanProblem(PassPlanProblemKind.gapMissing),
        _example.copyWith(rootFaceMm: double.nan):
            const PassPlanProblem(PassPlanProblemKind.rootFaceMissing),
        _example.copyWith(angleDeg: double.nan):
            const PassPlanProblem(PassPlanProblemKind.angleMissing),
        _example.copyWith(count: 8.5):
            const PassPlanProblem(PassPlanProblemKind.count),
        _example.copyWith(count: 0):
            const PassPlanProblem(PassPlanProblemKind.count),
        _example.copyWith(groove: GrooveType.x):
            const PassPlanProblem(PassPlanProblemKind.grooveXOnPipe),
        _example.copyWith(stubMm: 10):
            const PassPlanProblem(PassPlanProblemKind.stub),
        _example.copyWith(beadAreasMm2: {PassConsumable.mma32: 0}):
            const PassPlanProblem(PassPlanProblemKind.beadArea,
                consumable: PassConsumable.mma32),
        _example.copyWith(arcOnPct: {QuoteProcess.mma: 0}):
            const PassPlanProblem(PassPlanProblemKind.arcOn,
                process: QuoteProcess.mma),
        _example.copyWith(shiftH: 0):
            const PassPlanProblem(PassPlanProblemKind.shift),
        _example.copyWith(limitMinutes: () => 0):
            const PassPlanProblem(PassPlanProblemKind.limit),
        _example.copyWith(limitMinutes: () => double.nan):
            const PassPlanProblem(PassPlanProblemKind.limit),
        _example.copyWith(wallMm: 90): const PassPlanProblem(
            PassPlanProblemKind.joint,
            joint: JointProblem.wallVsOd),
        _example.copyWith(kind: JointKind.branch):
            const PassPlanProblem(PassPlanProblemKind.kind),
      };
      for (final e in cases.entries) {
        expect(passPlanProblems(e.key), contains(e.value),
            reason: e.value.toString());
        expect(planPasses(e.key), isNull, reason: e.value.toString());
        expect(passPlanProblemText(e.value, en: false), isNotEmpty);
        expect(passPlanProblemText(e.value, en: true), isNotEmpty);
      }
    });

    test('rowek I nie wymaga progu ani kąta', () {
      final i = _example.copyWith(
          kind: JointKind.plateButt,
          wallMm: 4,
          groove: GrooveType.square,
          rootFaceMm: double.nan,
          angleDeg: double.nan);
      expect(passPlanProblems(i), isEmpty);
      expect(planPasses(i), isNotNull);
    });
  });

  group('formularz: format i zapis', () {
    Map<String, String> form(Map<String, String> over) =>
        {...passPlanDefaultForm(), ...over};

    test('przecinek, kropka i spacje dają ten sam plan', () {
      final a = _plan(passPlanInputFromForm(
          form({'od': '168,3', 'wall': '7,11', 'gap': '2,5'})));
      final b = _plan(passPlanInputFromForm(
          form({'od': '168.3', 'wall': '7.11', 'gap': '2.5'})));
      final c = _plan(passPlanInputFromForm(
          form({'od': ' 168,3 ', 'wall': '7.11', 'gap': '2,5'})));
      for (final x in [b, c]) {
        expect(x.passesPerJoint, a.passesPerJoint);
        expect(x.depositGPerJoint, a.depositGPerJoint);
        expect(x.workMinJob, a.workMinJob);
        expect(x.exposure!.totalTakeNow, a.exposure!.totalTakeNow);
      }
      expect(passPlanShareText(a, en: false), passPlanShareText(b, en: false));
    });

    test('formularz domyślny = przykład; pusty limit → z tabeli', () {
      final i = passPlanInputFromForm(passPlanDefaultForm());
      final r = _plan(i);
      expect(r.passesPerJoint, 4);
      expect(r.exposure!.limitFromTable, isTrue);
      final empty = passPlanInputFromForm(form({'od': ''}));
      expect(empty.odMm.isNaN, isTrue);
      expect(planPasses(empty), isNull);
    });

    test('zapis i odczyt bez strat', () {
      final f = form({
        'od': '114,3',
        'wall': '6,02',
        'class': 'none',
        'limit': '600',
        'limitUp': '1'
      });
      final d = decodePassPlanFormDetailed(encodePassPlanForm(f));
      expect(d.lossy, isFalse);
      expect(d.form, f);
      final i = passPlanInputFromForm(d.form);
      expect(i.limitMinutes, 600);
      expect(i.limitAboveTableConfirmed, isTrue);
      expect(
          passPlanInputFromForm(passPlanDefaultForm()).limitAboveTableConfirmed,
          isFalse);
      expect(decodePassPlanFormDetailed('{"v":1,"f":{"limitUp":"tak"}}').lossy,
          isTrue);
    });

    test('uszkodzony zapis → domyślne i flaga straty', () {
      for (final raw in [
        '{"v":1,"f":{"od":',
        'zepsute',
        '{"v":2,"f":{}}',
        '[1,2]',
      ]) {
        final d = decodePassPlanFormDetailed(raw);
        expect(d.lossy, isTrue, reason: raw);
        expect(d.form, passPlanDefaultForm(), reason: raw);
      }
      // Złe pole → tylko ono domyślne.
      final bad = decodePassPlanFormDetailed(
          '{"v":1,"f":{"od":"abc","wall":"6,02","root":"saw","count":5}}');
      expect(bad.lossy, isTrue);
      expect(bad.form['od'], passPlanDefaultForm()['od']);
      expect(bad.form['root'], passPlanDefaultForm()['root']);
      expect(bad.form['count'], passPlanDefaultForm()['count']);
      expect(bad.form['wall'], '6,02');
      // Brak pola (starszy zapis) i nieznany klucz — bez straty.
      final old = decodePassPlanFormDetailed('{"v":1,"f":{"x":"1"}}');
      expect(old.lossy, isFalse);
      expect(old.form, passPlanDefaultForm());
    });
  });

  group('tekst', () {
    test('odmiana: 1 ścieg, 2 ściegi, 5 ściegów, 12 ściegów, 22 ściegi', () {
      expect(passesText(1, en: false), '1 ścieg');
      expect(passesText(2, en: false), '2 ściegi');
      expect(passesText(5, en: false), '5 ściegów');
      expect(passesText(12, en: false), '12 ściegów');
      expect(passesText(22, en: false), '22 ściegi');
      expect(passesText(1, en: true), '1 pass');
      expect(rodsText(11, en: false), '11 prętów');
      expect(portionsText(2, en: false), '2 porcje');
    });

    test('tekst planu PL i EN: warstwy, całość, weź z suszarki, źródła', () {
      final r = _plan(_example);
      final pl = passPlanShareText(r, en: false);
      expect(pl, contains('Plan ściegów i elektrod'));
      expect(pl, contains('Doczołowa rury Ø168,3 × 7,11, rowek V 60°'));
      expect(pl, contains('• Lico — elektroda Ø3,2 × 350 mm: 2 ściegi'));
      expect(pl, contains('Elektroda Ø2,5 × 350 mm: 25 szt. (z zapasem 27)'));
      expect(pl, contains('Weź z suszarki: Ø2,5 × 8 szt. · Ø3,2 × 12 szt.'));
      expect(pl, contains('łuk TIG 25 %, MMA 15 % — dolna granica TWI'));
      expect(pl, contains('4 porcje na całą robotę (5 h 47 min pracy)'));
      expect(pl, isNot(contains('! ')));
      expect(pl, contains('Limit 4 h 00 min − 30 min zapasu = 3 h 30 min'));
      expect(pl, contains('ESAB OK 48.00'));
      expect(pl, contains(passPlanDisclaimer(en: false)));
      expect(pl, isNot(contains('NaN')));
      final en = passPlanShareText(r, en: true);
      expect(en, contains('Pass and electrode plan'));
      expect(en, contains('Electrode Ø3.2 × 350 mm: 39 pcs (with reserve 42)'));
      expect(en, contains('Take from the oven: Ø2.5 × 8 pcs · Ø3.2 × 12 pcs'));
      // Limit 2400 bez potwierdzenia — ostrzeżenie także w tekście.
      final typo = _plan(_example.copyWith(limitMinutes: () => 2400));
      expect(passPlanShareText(typo, en: false),
          contains('! Wpisany limit 40 h 00 min jest dłuższy niż z tabeli'));
    });
  });
}
