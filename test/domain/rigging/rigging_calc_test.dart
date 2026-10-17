// Kalkulator zawiesi: współczynniki trybu (EN 1492-1/-2, EN 818-4/-6,
// EN 13414-1), granice kątów, niesymetria, werdykt, zaokrąglenia,
// niezależność od jednostki, typoszereg, siła w cięgnie, masa z rury,
// WLL cięgna / zespołu z zawieszki, niejednoznaczny zapis „12,500”,
// limit 1000 t.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/fitter_calcs.dart';
import 'package:cut_list_app/domain/rigging/rigging_calc.dart';

/// Domyślnie 2 cięgna z WLL JEDNEGO cięgna (pas 2 t), β 30°.
RiggingInput _in({
  double? massKg = 1600,
  bool massAmbiguous = false,
  SlingType sling = SlingType.webbing,
  HitchMode mode = HitchMode.twoLeg,
  bool chokedLegs = false,
  double? angle = 30,
  AngleKind kind = AngleKind.fromVertical,
  bool asymmetric = false,
  double? wllKg = 2000,
  bool wllAmbiguous = false,
  WllBasis? basis = WllBasis.perLeg,
  TagAngleRange? range,
  LabelState label = LabelState.readable,
}) =>
    RiggingInput(
      massKg: massKg,
      massAmbiguous: massAmbiguous,
      sling: sling,
      mode: mode,
      chokedLegs: chokedLegs,
      angleValue: angle,
      angleKind: kind,
      asymmetric: asymmetric,
      wllKg: wllKg,
      wllAmbiguous: wllAmbiguous,
      wllBasis: basis,
      tagRange: range,
      label: label,
    );

double _f(SlingType s, HitchMode m, {double beta = 30, bool choked = false}) =>
    modeFactor(s, m, band: angleBand(beta), chokedLegs: choked)!.value;

void main() {
  group('współczynniki trybu', () {
    test(
        'pasy płaskie i okrągłe: 1,0 · 0,8 · 2,0 · 1,4/1,0 · 1,4/1,0 · '
        '2,1/1,5', () {
      for (final s in [SlingType.webbing, SlingType.roundsling]) {
        expect(_f(s, HitchMode.straight), 1.0);
        expect(_f(s, HitchMode.choke), 0.8);
        expect(_f(s, HitchMode.basketParallel), 2.0);
        expect(_f(s, HitchMode.basketAngled, beta: 30), 1.4);
        expect(_f(s, HitchMode.basketAngled, beta: 50), 1.0);
        expect(_f(s, HitchMode.twoLeg, beta: 30), 1.4);
        expect(_f(s, HitchMode.twoLeg, beta: 50), 1.0);
        expect(_f(s, HitchMode.multiLeg, beta: 30), 2.1);
        expect(_f(s, HitchMode.multiLeg, beta: 50), 1.5);
      }
    });

    test('liny stalowe: koszowe jak pasy (2,0 / 1,4 / 1,0)', () {
      const s = SlingType.wireRope;
      expect(_f(s, HitchMode.basketParallel), 2.0);
      expect(_f(s, HitchMode.basketAngled, beta: 10), 1.4);
      expect(_f(s, HitchMode.basketAngled, beta: 55), 1.0);
      expect(_f(s, HitchMode.choke), 0.8);
      expect(_f(s, HitchMode.multiLeg, beta: 55), 1.5);
    });

    test('łańcuch w koszowym ×1,0 przy każdym kącie — przyjęte w aplikacji',
        () {
      const s = SlingType.chain;
      for (final m in [HitchMode.basketParallel, HitchMode.basketAngled]) {
        for (final beta in [0.0, 10.0, 44.9, 45.0, 60.0]) {
          final f = modeFactor(s, m, band: angleBand(beta))!;
          expect(f.value, 1.0, reason: '$m β=$beta');
          expect(f.adopted, isTrue);
        }
      }
      // Reszta łańcucha jak w EN 818-4 — potwierdzona, nie „przyjęta”.
      expect(modeFactor(s, HitchMode.twoLeg, band: AngleBand.upTo45),
          const ModeFactor(1.4));
      expect(modeFactor(s, HitchMode.multiLeg, band: AngleBand.from45to60),
          const ModeFactor(1.5));
      expect(modeFactor(s, HitchMode.choke), const ModeFactor(0.8));
    });

    test('cięgna na zadusznik: 2 cięgna 1,12 / 0,8; 3–4 cięgna 1,68 / 1,2', () {
      expect(_f(SlingType.webbing, HitchMode.twoLeg, beta: 30, choked: true),
          1.12);
      expect(
          _f(SlingType.webbing, HitchMode.twoLeg, beta: 50, choked: true), 0.8);
      expect(_f(SlingType.chain, HitchMode.multiLeg, beta: 30, choked: true),
          1.68);
      expect(
          _f(SlingType.chain, HitchMode.multiLeg, beta: 50, choked: true), 1.2);
      // 3–4 cięgna pasów / lin na zadusznik — przez analogię (przyjęte).
      expect(
          modeFactor(SlingType.webbing, HitchMode.multiLeg,
                  band: AngleBand.upTo45, chokedLegs: true)!
              .adopted,
          isTrue);
      expect(
          modeFactor(SlingType.chain, HitchMode.multiLeg,
                  band: AngleBand.upTo45, chokedLegs: true)!
              .adopted,
          isFalse);
      // Dla trybów jednocięgnowych przełącznik nic nie zmienia.
      expect(_f(SlingType.webbing, HitchMode.straight, choked: true), 1.0);
    });

    test('tryb z kątem bez kąta albo ponad 60° → brak współczynnika', () {
      for (final m in [
        HitchMode.basketAngled,
        HitchMode.twoLeg,
        HitchMode.multiLeg
      ]) {
        expect(modeFactor(SlingType.webbing, m), isNull);
        expect(
            modeFactor(SlingType.webbing, m, band: AngleBand.over60), isNull);
      }
    });
  });

  group('kąty', () {
    test('dokładnie 45° → przedział niekorzystny (×1,0 / ×1,5)', () {
      expect(angleBand(44.999), AngleBand.upTo45);
      expect(angleBand(45), AngleBand.from45to60);
      expect(_f(SlingType.webbing, HitchMode.twoLeg, beta: 45), 1.0);
      expect(_f(SlingType.webbing, HitchMode.multiLeg, beta: 45), 1.5);
      expect(_f(SlingType.webbing, HitchMode.basketAngled, beta: 45), 1.0);
    });

    test('60° jeszcze dozwolone, ponad 60° → STOP „niedozwolone”', () {
      expect(angleBand(60), AngleBand.from45to60);
      expect(angleBand(60.01), AngleBand.over60);
      final ok = evaluateRigging(_in(angle: 60));
      expect(ok.verdict, RiggingVerdict.ok);
      final stop = evaluateRigging(_in(angle: 60.01, massKg: 10));
      expect(stop.verdict, RiggingVerdict.angleNotAllowed);
      expect(stop.verdict.isStop, isTrue);
      expect(stop.capacityKg, isNull);
    });

    test('kąt nieznany albo nieczytelny → brak werdyktu, nie OK', () {
      for (final a in [null, double.nan, -5.0, 90.0, 120.0]) {
        final r = evaluateRigging(_in(angle: a, massKg: 1));
        expect(r.verdict, RiggingVerdict.incomplete, reason: '$a');
        expect(
            r.issues,
            contains(a == null
                ? RiggingIssue.angleMissing
                : RiggingIssue.angleInvalid));
      }
      // Proste i koszowe równoległe nie potrzebują kąta.
      expect(
          evaluateRigging(_in(mode: HitchMode.straight, angle: null)).verdict,
          RiggingVerdict.ok);
    });

    test('kąt wierzchołkowy α = 2β: 90° → β 45°, 120° → 60°, 121° → STOP', () {
      expect(betaFromInput(90, AngleKind.included), 45);
      expect(betaFromInput(45, AngleKind.fromVertical), 45);
      expect(convertAngle(30, from: AngleKind.fromVertical), 60);
      expect(convertAngle(60, from: AngleKind.included), 30);
      final r90 = evaluateRigging(_in(angle: 90, kind: AngleKind.included));
      expect(r90.betaDeg, 45);
      expect(r90.factor!.value, 1.0);
      expect(evaluateRigging(_in(angle: 120, kind: AngleKind.included)).verdict,
          RiggingVerdict.ok);
      expect(evaluateRigging(_in(angle: 121, kind: AngleKind.included)).verdict,
          RiggingVerdict.angleNotAllowed);
      expect(betaFromInput(180, AngleKind.included), isNull);
    });

    test('ten sam wpis 60°: od pionu ×1,0, między cięgnami (β 30°) ×1,4', () {
      final vertical = evaluateRigging(_in(angle: 60));
      final included =
          evaluateRigging(_in(angle: 60, kind: AngleKind.included));
      expect(vertical.factor!.value, 1.0);
      expect(vertical.capacityKg, 2000);
      expect(included.factor!.value, 1.4);
      expect(included.capacityKg, 2800);
    });
  });

  group('werdykt', () {
    test('zielony 2 t, spool 1,6 t, 2 cięgna 60° od pionu → OK (2000 kg)', () {
      final r = evaluateRigging(_in(massKg: 1600, wllKg: 2000, angle: 60));
      expect(r.verdict, RiggingVerdict.ok);
      expect(r.capacityKg, 2000);
      expect(r.massKg, 1600);
    });

    test('zadusznik: 2 t → 1600 kg; równo z masą OK, 1 kg więcej STOP', () {
      final eq = evaluateRigging(
          _in(mode: HitchMode.choke, massKg: 1600, angle: null));
      expect(eq.capacityKg, 1600);
      expect(eq.verdict, RiggingVerdict.ok);
      final over = evaluateRigging(
          _in(mode: HitchMode.choke, massKg: 1601, angle: null));
      expect(over.verdict, RiggingVerdict.overload);
      expect(over.requiredWllKg, 2002);
      expect(over.suggestedSeriesT, 3);
    });

    test('STOP podaje potrzebne WLL zaokrąglone w górę do typoszeregu pasów',
        () {
      final r = evaluateRigging(_in(massKg: 4100, wllKg: 2000, angle: 30));
      expect(r.verdict, RiggingVerdict.overload);
      expect(r.capacityKg, 2800);
      // 4100 / 1,4 = 2928,6 → 2929 kg; z typoszeregu: 3 t.
      expect(r.requiredWllKg, 2929);
      expect(r.suggestedSeriesT, 3);
      expect(suggestedSeriesT(9000, const ModeFactor(1.0)), 10);
      expect(suggestedSeriesT(10001, const ModeFactor(1.0)), 12);
      expect(suggestedSeriesT(50001, const ModeFactor(1.0)), isNull);
      expect(kSlingWllSeriesT.take(8), [1, 2, 3, 4, 5, 6, 8, 10]);
    });

    test('typoszereg tylko dla pasów; łańcuch i lina — samo WLL w kg', () {
      final chain = evaluateRigging(
          _in(sling: SlingType.chain, massKg: 4100, wllKg: 2000));
      expect(chain.suggestedSeriesT, isNull);
      expect(chain.requiredWllKg, 2929);
    });

    test('potrzebne WLL jest najmniejsze i zgodne z werdyktem', () {
      for (final f in [0.8, 1.0, 1.12, 1.2, 1.4, 1.5, 1.68, 2.0, 2.1]) {
        for (final m in [1, 7, 999, 1000, 1601, 2800, 4321, 12345]) {
          final w = requiredWllKg(m, ModeFactor(f));
          expect(
              capacityKg(w.toDouble(), ModeFactor(f)), greaterThanOrEqualTo(m),
              reason: 'f=$f m=$m');
          if (w > 1) {
            expect(capacityKg((w - 1).toDouble(), ModeFactor(f)), lessThan(m),
                reason: 'f=$f m=$m');
          }
        }
      }
    });

    test('brak albo nieczytelna etykieta → STOP bez względu na nośność', () {
      final r = evaluateRigging(
          _in(massKg: 100, wllKg: 10000, label: LabelState.missing));
      expect(r.verdict, RiggingVerdict.noLabel);
      expect(r.verdict.isStop, isTrue);
    });

    test('etykieta niepotwierdzona → brak werdyktu; przeciążenie i tak STOP',
        () {
      final unknown = evaluateRigging(_in(label: LabelState.unknown));
      expect(unknown.verdict, RiggingVerdict.incomplete);
      expect(unknown.issues, contains(RiggingIssue.labelUnconfirmed));
      final over =
          evaluateRigging(_in(label: LabelState.unknown, massKg: 9000));
      expect(over.verdict, RiggingVerdict.overload);
    });

    test('brak lub błędna masa / WLL → brak werdyktu, nigdy OK', () {
      expect(evaluateRigging(_in(massKg: null)).issues,
          contains(RiggingIssue.massMissing));
      expect(evaluateRigging(_in(wllKg: null)).issues,
          contains(RiggingIssue.wllMissing));
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final m = evaluateRigging(_in(massKg: bad));
        expect(m.verdict, RiggingVerdict.incomplete, reason: 'masa $bad');
        expect(m.issues, contains(RiggingIssue.massInvalid));
        final w = evaluateRigging(_in(wllKg: bad));
        expect(w.verdict, RiggingVerdict.incomplete, reason: 'WLL $bad');
        expect(w.issues, contains(RiggingIssue.wllInvalid));
      }
    });
  });

  group('niesymetria', () {
    test('ładunek niesymetryczny → jak jedno cięgno', () {
      final sym = evaluateRigging(_in(massKg: 2500, angle: 30));
      expect(sym.verdict, RiggingVerdict.ok);
      expect(sym.capacityKg, 2800);
      final asym =
          evaluateRigging(_in(massKg: 2500, angle: 30, asymmetric: true));
      expect(asym.factor!.value, 1.0);
      expect(asym.symmetricFactor!.value, 1.4);
      expect(asym.asymmetryReduced, isTrue);
      expect(asym.capacityKg, 2000);
      expect(asym.verdict, RiggingVerdict.overload);
      expect(asym.tension, isNull, reason: 'rozkład nieznany — bez fizyki');
    });

    test('3–4 cięgna, koszowe → 1,0; na zadusznik → 0,8; proste bez zmian', () {
      ModeFactor eff(HitchMode m, {bool choked = false}) => applyAsymmetry(
          modeFactor(SlingType.chain, m,
              band: AngleBand.upTo45, chokedLegs: choked)!,
          SlingType.chain,
          m,
          chokedLegs: choked);
      expect(eff(HitchMode.multiLeg).value, 1.0);
      expect(eff(HitchMode.multiLeg).adopted, isFalse, reason: 'EN 818-6');
      expect(eff(HitchMode.multiLeg, choked: true).value, 0.8);
      expect(eff(HitchMode.straight).value, 1.0);
      expect(eff(HitchMode.choke).value, 0.8);
      final basket = applyAsymmetry(
          const ModeFactor(2.0), SlingType.webbing, HitchMode.basketParallel,
          chokedLegs: false);
      expect(basket, const ModeFactor(1.0, adopted: true));
    });

    test('niesymetria nie zwalnia z limitu 60°', () {
      final r = evaluateRigging(_in(angle: 65, asymmetric: true, massKg: 1));
      expect(r.verdict, RiggingVerdict.angleNotAllowed);
    });
  });

  group('zaokrąglenia i jednostki', () {
    test('masa w górę, nośność w dół — także przy szumie double', () {
      expect(ceilKg(1600.2), 1601);
      expect(ceilKg(1600.0000000002), 1600);
      expect(floorKg(2000 * 1.4), 2800);
      expect(floorKg(999.9), 999);
      expect(toKg(2.8, MassUnit.t), closeTo(2800, 1e-9));
      final r = evaluateRigging(
          _in(mode: HitchMode.straight, massKg: 999.5, wllKg: 999.9));
      expect(r.massKg, 1000);
      expect(r.capacityKg, 999);
      expect(r.verdict, RiggingVerdict.overload);
    });

    test('ta sama masa w kg i w t daje ten sam werdykt', () {
      final cases = <(double, double, HitchMode, double?)>[
        (1600, 2000, HitchMode.choke, null),
        (1601, 2000, HitchMode.choke, null),
        (2800, 2000, HitchMode.twoLeg, 30),
        (2800.4, 2000, HitchMode.twoLeg, 30),
        (4199, 2000, HitchMode.multiLeg, 10),
        (6000, 3000, HitchMode.basketParallel, null),
        (1234.5, 1000, HitchMode.basketAngled, 45),
      ];
      for (final (massKg, wllKg, mode, angle) in cases) {
        RiggingResult evaluateIn(MassUnit u) => evaluateRigging(_in(
              mode: mode,
              angle: angle,
              massKg: toKg(fromKg(massKg, u), u),
              wllKg: toKg(fromKg(wllKg, u), u),
            ));
        final kg = evaluateIn(MassUnit.kg);
        final t = evaluateIn(MassUnit.t);
        expect(t.verdict, kg.verdict, reason: '$massKg kg $mode');
        expect(t.massKg, kg.massKg);
        expect(t.capacityKg, kg.capacityKg);
        // Wpis „z klawiatury” w tonach (1,6 t) = 1600 kg.
        expect(toKg(massKg / 1000, MassUnit.t), closeTo(massKg, 1e-6));
      }
      // Konkretnie: 2,8 t i 2800 kg przy nośności 2800 kg — oba OK.
      expect(
          evaluateRigging(_in(massKg: toKg(2.8, MassUnit.t), angle: 30))
              .verdict,
          RiggingVerdict.ok);
    });
  });

  group('siła w cięgnie (informacyjnie)', () {
    test('T = W / (n · cos β)', () {
      final two = evaluateRigging(_in(massKg: 1600, angle: 60));
      expect(two.tension!.legs, 2);
      expect(two.tension!.perLegKg, 1600);
      final straight =
          evaluateRigging(_in(mode: HitchMode.straight, massKg: 1600));
      expect(straight.tension!.perLegKg, 1600);
      final basket =
          evaluateRigging(_in(mode: HitchMode.basketParallel, massKg: 1600));
      expect(basket.tension!.perLegKg, 800);
      final multi = evaluateRigging(
          _in(mode: HitchMode.multiLeg, massKg: 3000, wllKg: 2000, angle: 30));
      expect(multi.tension!.legs, 3);
      expect(multi.tension!.perLegKg, 1155); // 3000 / (3 · 0,866)
      expect(multi.tension!.perLegIfTwoCarryKg, 1733);
    });

    test('werdykt z tabeli, nie z fizyki: 45° liczone ×1,0, choć T < WLL', () {
      // 2 cięgna, β 45°, 2600 kg: T = 2600 / (2 · 0,707) = 1839 kg na
      // cięgno (< 2000), ale tabela daje 2000 × 1,0 = 2000 < 2600 → STOP.
      final r = evaluateRigging(_in(massKg: 2600, angle: 45));
      expect(r.tension!.perLegKg, lessThan(2000));
      expect(r.verdict, RiggingVerdict.overload);
    });
  });

  group('masa z rury', () {
    test('DN150 (168,3 × 7,11), 6 m, stal węglowa + 50 kg dodatków', () {
      final r = pipeLoadMass(
          odMm: 168.3,
          wallMm: 7.11,
          lengthM: 6,
          material: PipeMaterial.cs,
          extraKg: 50);
      final kgm = pipeMassKgPerM(168.3, 7.11, 7850);
      expect(r.problem, isNull);
      expect(r.mass!.kgPerM, kgm);
      expect(kgm, closeTo(28.26, 0.01));
      expect(r.mass!.totalKg, ceilKg(kgm * 6 + 50));
      expect(r.mass!.totalKg, 220);
    });

    test('masa zaokrąglona w górę; nierdzewna 316 cięższa niż węglowa', () {
      final cs = pipeLoadMass(
          odMm: 60.3, wallMm: 2, lengthM: 1, material: PipeMaterial.cs);
      final ss = pipeLoadMass(
          odMm: 60.3, wallMm: 2, lengthM: 1, material: PipeMaterial.ss316);
      expect(cs.mass!.totalKg, 3); // 2,876 kg → 3
      expect(ss.mass!.pipeKg, greaterThan(cs.mass!.pipeKg));
    });

    test('brak albo błędne dane → problem, nigdy cicha zero', () {
      PipeLoadProblem? p(double? od, double? t, double? l, [double? x = 0]) =>
          pipeLoadMass(
                  odMm: od,
                  wallMm: t,
                  lengthM: l,
                  material: PipeMaterial.cs,
                  extraKg: x)
              .problem;
      expect(p(null, 2, 1), PipeLoadProblem.od);
      expect(p(0, 2, 1), PipeLoadProblem.od);
      expect(p(60.3, null, 1), PipeLoadProblem.wall);
      expect(p(60.3, 30.15, 1), PipeLoadProblem.wall);
      expect(p(60.3, 2, 0), PipeLoadProblem.length);
      expect(p(60.3, 2, double.nan), PipeLoadProblem.length);
      expect(p(60.3, 2, 1, -1), PipeLoadProblem.extra);
      expect(p(60.3, 2, 1, null), PipeLoadProblem.extra);
    });
  });

  group('WLL cięgna czy zespołu (2 / 3–4 cięgna)', () {
    test('zawieszka 2,8 t zespołu, 2 cięgna β 30° → 2800 kg, nie 3920 kg', () {
      final asm = evaluateRigging(_in(
          sling: SlingType.chain,
          massKg: 2900,
          wllKg: 2800,
          basis: WllBasis.assembly,
          range: TagAngleRange.upTo45));
      expect(asm.factor, const ModeFactor(1.0));
      expect(asm.capacityKg, 2800);
      expect(asm.verdict, RiggingVerdict.overload);
      expect(asm.wllBasis, WllBasis.assembly);
      expect(asm.suggestedSeriesT, isNull);
      // Ta sama liczba jako WLL jednego cięgna — mnożona (2800 × 1,4).
      final leg = evaluateRigging(_in(
          sling: SlingType.chain,
          massKg: 2900,
          wllKg: 2800,
          basis: WllBasis.perLeg));
      expect(leg.capacityKg, 3920);
      expect(leg.verdict, RiggingVerdict.ok);
      expect(
          evaluateRigging(_in(
                  sling: SlingType.chain,
                  massKg: 2800,
                  wllKg: 2800,
                  basis: WllBasis.assembly,
                  range: TagAngleRange.upTo45))
              .verdict,
          RiggingVerdict.ok);
    });

    test('bez wyboru, co podaje zawieszka → brak werdyktu, nie OK', () {
      for (final mode in [HitchMode.twoLeg, HitchMode.multiLeg]) {
        final r = evaluateRigging(_in(mode: mode, basis: null, massKg: 10));
        expect(r.verdict, RiggingVerdict.incomplete, reason: '$mode');
        expect(r.issues, contains(RiggingIssue.wllBasisMissing));
        expect(r.capacityKg, isNull);
      }
      // Tryby jednocięgnowe wyboru nie potrzebują (i go nie używają).
      final straight = evaluateRigging(_in(
          mode: HitchMode.straight,
          basis: WllBasis.assembly,
          range: TagAngleRange.upTo45));
      expect(straight.verdict, RiggingVerdict.ok);
      expect(straight.wllBasis, isNull);
    });

    test('WLL zespołu tylko w zakresie kąta z zawieszki', () {
      RiggingResult asm(double beta, TagAngleRange? range) =>
          evaluateRigging(_in(
              sling: SlingType.chain,
              massKg: 100,
              wllKg: 2800,
              angle: beta,
              basis: WllBasis.assembly,
              range: range));
      expect(asm(30, null).issues, contains(RiggingIssue.tagRangeMissing));
      expect(asm(30, null).verdict, RiggingVerdict.incomplete);
      // 0–45° z zawieszki nie obowiązuje przy 45° i więcej.
      for (final beta in [45.0, 50.0, 60.0]) {
        final r = asm(beta, TagAngleRange.upTo45);
        expect(r.verdict, RiggingVerdict.incomplete, reason: 'β=$beta');
        expect(r.issues, contains(RiggingIssue.angleOutsideTagRange));
      }
      // Wartość 45–60° (niższa) obowiązuje dla każdego β do 60°.
      expect(asm(30, TagAngleRange.upTo60).verdict, RiggingVerdict.ok);
      expect(asm(60, TagAngleRange.upTo60).verdict, RiggingVerdict.ok);
      expect(asm(61, TagAngleRange.upTo60).verdict,
          RiggingVerdict.angleNotAllowed);
      expect(asm(44.9, TagAngleRange.upTo45).verdict, RiggingVerdict.ok);
    });

    test('WLL zespołu: zadusznik ×0,8; niesymetria = jedno cięgno', () {
      RiggingResult asm({
        HitchMode mode = HitchMode.twoLeg,
        double wll = 2800,
        bool choked = false,
        bool asym = false,
      }) =>
          evaluateRigging(_in(
              sling: SlingType.chain,
              mode: mode,
              massKg: 100,
              wllKg: wll,
              chokedLegs: choked,
              asymmetric: asym,
              basis: WllBasis.assembly,
              range: TagAngleRange.upTo45));
      expect(asm(choked: true).capacityKg, 2240);
      expect(asm(asym: true).capacityKg, 2000); // 2800 / 1,4
      expect(asm(asym: true, choked: true).capacityKg, 1600);
      expect(asm(mode: HitchMode.multiLeg, wll: 4200, asym: true).capacityKg,
          2000); // 4200 / 2,1
      expect(asm(asym: true).asymmetryReduced, isTrue);
    });
  });

  group('niejednoznaczny zapis i limit 1000 t', () {
    test('„12,500” / „12.500” w kg — separator tysięcy czy ułamek?', () {
      for (final s in ['12,500', '12.500', '1,250', '100,000', ' 12,500 ']) {
        expect(isAmbiguousThousands(s), isTrue, reason: s);
      }
      for (final s in [
        '12,5',
        '12500',
        '0,125',
        '1234,500',
        '12,5000',
        '1.234.567',
        '',
      ]) {
        expect(isAmbiguousThousands(s), isFalse, reason: s);
      }
    });

    test('niejednoznaczna masa albo WLL → brak werdyktu, liczba pominięta', () {
      // 12,5 kg zmieściłoby się — ale to może być 12 500 kg.
      final m = evaluateRigging(_in(massKg: 12.5, massAmbiguous: true));
      expect(m.verdict, RiggingVerdict.incomplete);
      expect(m.issues, contains(RiggingIssue.massAmbiguous));
      expect(m.massKg, isNull);
      final w = evaluateRigging(_in(wllKg: 2, wllAmbiguous: true));
      expect(w.verdict, RiggingVerdict.incomplete);
      expect(w.issues, contains(RiggingIssue.wllAmbiguous));
    });

    test('masa lub WLL ponad 1000 t → nieczytelne, bez zawieszenia', () {
      expect(
          evaluateRigging(
                  _in(massKg: 1e6, wllKg: 1e6, mode: HitchMode.straight))
              .verdict,
          RiggingVerdict.ok);
      for (final big in [1e6 + 1, 1e12, 1e300]) {
        final m = evaluateRigging(_in(massKg: big));
        expect(m.issues, contains(RiggingIssue.massInvalid), reason: '$big');
        expect(m.verdict, RiggingVerdict.incomplete);
        final w = evaluateRigging(_in(wllKg: big));
        expect(w.issues, contains(RiggingIssue.wllInvalid), reason: '$big');
      }
      PipeLoadProblem? pipe({double length = 6, double extra = 0}) =>
          pipeLoadMass(
                  odMm: 168.3,
                  wallMm: 7.11,
                  lengthM: length,
                  material: PipeMaterial.cs,
                  extraKg: extra)
              .problem;
      expect(pipe(length: 1e9), PipeLoadProblem.tooHeavy);
      expect(pipe(extra: 2e6), PipeLoadProblem.extra);
    });

    test('potrzebne WLL wprost: ⌈m / f⌉ z jedną korektą', () {
      expect(requiredWllKg(1000000, const ModeFactor(0.8)), 1250000);
      expect(requiredWllKg(2800, const ModeFactor(1.4)), 2000);
      expect(requiredWllKg(1601, const ModeFactor(0.8)), 2002);
      // Duża liczba — wynik natychmiast i poprawny.
      const m = 1 << 40;
      final w = requiredWllKg(m, const ModeFactor(1.12));
      expect(capacityKg(w.toDouble(), const ModeFactor(1.12)),
          greaterThanOrEqualTo(m));
    });
  });
}
