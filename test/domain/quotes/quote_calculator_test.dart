// Wycena spawalnicza: geometria rowka → stopiwo → czas, materiały, koszty.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/quotes/quote_process.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';

QuoteJoint _dn100({int count = 1, WeldPosition pos = WeldPosition.pa}) =>
    QuoteJoint(
      id: 'j1',
      kind: JointKind.pipeButt,
      sizeLabel: 'DN100 Sch 40',
      odMm: 114.3,
      wallMm: 6.02,
      count: count,
      angleDeg: 60,
      rootFaceMm: 1.5,
      gapMm: 2.5,
      position: pos,
    );

WeldQuote _quote({
  List<QuoteJoint>? joints,
  WeldScheme scheme =
      const WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
  QuoteRates? rates,
  QuoteMaterial material = QuoteMaterial.carbon,
  QuoteSite site = QuoteSite.shop,
  bool purge = false,
  List<QuoteExtra> extras = const [],
}) =>
    WeldQuote(
      id: 'q1',
      material: material,
      scheme: scheme,
      site: site,
      purge: purge,
      rates: rates ??
          QuoteRates.defaultsFor(material,
              base: const QuoteRates(overheadPct: 0, marginPct: 0)),
      joints: joints ?? [_dn100()],
      extras: extras,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('geometria rowka', () {
    test('rowek V: b·h + (h − c)²·tg(α/2)', () {
      final a =
          grooveAreaV(h: 6.02, gap: 2.5, rootFace: 1.5, includedAngleDeg: 60);
      final expected = 2.5 * 6.02 + 4.52 * 4.52 * math.tan(math.pi / 6);
      expect(a, closeTo(expected, 1e-9));
      expect(a, closeTo(26.85, 0.01));
    });

    test('poniżej progu rowek jest prostokątem b·h', () {
      expect(grooveAreaV(h: 1.0, gap: 3, rootFace: 1.5, includedAngleDeg: 60),
          closeTo(3.0, 1e-12));
    });

    test('rowek I (0°) = b·t', () {
      expect(grooveAreaV(h: 4, gap: 2, rootFace: 0, includedAngleDeg: 0),
          closeTo(8, 1e-12));
    });

    test('pachwina a = 5: pole 25 mm² + wypukłość', () {
      expect(filletArea(5), closeTo(25 * (1 + kFilletConvexity), 1e-12));
    });

    test(
        'linia przenikania króćca: mały króciec → 2πr, równe średnice → '
        '≈1,216·2πr', () {
      expect(
          saddlePerimeter(10, 1000) / (2 * math.pi * 10), closeTo(1.0, 0.001));
      expect(
          saddlePerimeter(50, 50) / (2 * math.pi * 50), closeTo(1.216, 0.005));
      // Nieznana rura główna → obwód króćca.
      expect(saddlePerimeter(30, 0), closeTo(2 * math.pi * 30, 1e-9));
    });

    test('DN100 Sch 40, V 60°: ~0,11 kg stopiwa stali węglowej na spoinę', () {
      final v = pipeButtVolumes(
          od: 114.3, t: 6.02, gap: 2.5, rootFace: 1.5, includedAngleDeg: 60);
      final kg = v.totalMm3 * 7.85e-6;
      expect(kg, closeTo(0.111, 0.005));
      expect(v.rootMm3, greaterThan(0));
      expect(v.fillMm3, greaterThan(v.rootMm3));
      expect(v.lengthMm, closeTo(math.pi * 114.3, 1e-9));
    });

    test('faza ASME 37,5° (α = 75°) daje więcej stopiwa niż 30°', () {
      double kg(double angle) => pipeButtVolumes(
              od: 168.3,
              t: 7.11,
              gap: 3,
              rootFace: 1.6,
              includedAngleDeg: angle)
          .totalMm3;
      expect(kg(75), greaterThan(kg(60)));
    });

    test('cienka ścianka (t ≤ wysokość grani) — całość w grani', () {
      final v = pipeButtVolumes(
          od: 33.4, t: 2.77, gap: 2, rootFace: 1, includedAngleDeg: 60);
      // Reszta rowka = 0; zostaje tylko lico.
      final capOnly = reinforcementArea(
              grooveTopWidthV(
                      t: 2.77, gap: 2, rootFace: 1, includedAngleDeg: 60) +
                  2 * kCapOverlapMm,
              kCapHeightMm) *
          math.pi *
          33.4;
      expect(v.fillMm3, closeTo(capOnly, 1e-6));
    });

    test('ścianka ≥ promienia — brak objętości (błędne dane)', () {
      expect(
          pipeButtVolumes(
                  od: 20, t: 10, gap: 2, rootFace: 1, includedAngleDeg: 60)
              .totalMm3,
          0);
    });

    test('blachy X: mniej stopiwa niż V przy tej samej grubości', () {
      double vol(GrooveType g) => plateButtVolumes(
              t: 20,
              lengthMm: 1000,
              groove: g,
              gap: 2,
              rootFace: 2,
              includedAngleDeg: 60)
          .totalMm3;
      expect(vol(GrooveType.x), lessThan(vol(GrooveType.v)));
    });
  });

  group('NPS i cale-średnice', () {
    test('parseNps', () {
      expect(parseNps('1 1/4'), 1.25);
      expect(parseNps('1/2'), 0.5);
      expect(parseNps('24'), 24);
      expect(parseNps('x'), isNull);
    });

    test('OD → NPS z tabeli, z tolerancją', () {
      expect(npsInchesForOd(114.3), 4);
      expect(npsInchesForOd(114.0), 4);
      expect(npsInchesForOd(60.3), 2);
      expect(npsInchesForOd(101.6), isNull);
    });

    test('DI = NPS × liczba spoin; nietypowe OD → przybliżenie OD/25,4', () {
      final r = computeQuote(_quote(joints: [
        _dn100(count: 10),
        const QuoteJoint(
            id: 'x',
            kind: JointKind.pipeButt,
            odMm: 101.6,
            wallMm: 3,
            count: 2),
      ]));
      expect(r.diameterInches, closeTo(40 + 2 * 101.6 / 25.4, 1e-9));
      expect(r.diApprox, isTrue);
    });
  });

  group('procesy i zużycie', () {
    test('TIG + MMA: grań TIG-iem, reszta MMA, suma = całe stopiwo', () {
      final r = computeQuote(_quote());
      final tig = r.byProcess[QuoteProcess.tig]!;
      final mma = r.byProcess[QuoteProcess.mma]!;
      final v = pipeButtVolumes(
          od: 114.3, t: 6.02, gap: 2.5, rootFace: 1.5, includedAngleDeg: 60);
      expect(tig.depositedKg, closeTo(v.rootMm3 * 7.85e-6, 1e-12));
      expect(mma.depositedKg, closeTo(v.fillMm3 * 7.85e-6, 1e-12));
      expect(r.depositedKg, closeTo(v.totalMm3 * 7.85e-6, 1e-12));
    });

    test('spoiwo = stopiwo / uzysk; czas łuku = stopiwo / wydajność', () {
      final r = computeQuote(
          _quote(scheme: const WeldScheme.single(QuoteProcess.mma)));
      final u = r.byProcess[QuoteProcess.mma]!;
      final p = kDefaultProcessProfiles[QuoteProcess.mma]!;
      expect(u.fillerKg, closeTo(u.depositedKg / p.efficiency, 1e-12));
      expect(u.arcHours, closeTo(u.depositedKg / p.depositionKgH, 1e-12));
      expect(u.shieldGasL, 0, reason: 'MMA bez gazu');
    });

    test('gaz TIG: przepływ · czas łuku · 1,15', () {
      final r = computeQuote(
          _quote(scheme: const WeldScheme.single(QuoteProcess.tig)));
      final u = r.byProcess[QuoteProcess.tig]!;
      expect(u.shieldGasL, closeTo(10 * 60 * u.arcHours * 1.15, 1e-9));
    });

    test('pozycja i warunki mnożą czas spawania; przygotowanie tylko warunki',
        () {
      final base = computeQuote(_quote());
      final hard = computeQuote(_quote(
          joints: [_dn100(pos: WeldPosition.hl045)], site: QuoteSite.field));
      expect(hard.weldHours, closeTo(base.weldHours * 1.5 * 1.3, 1e-9));
      expect(hard.prepHours, closeTo(base.prepHours * 1.3, 1e-9));
    });

    test('liczba spoin skaluje wszystko liniowo', () {
      final one = computeQuote(_quote());
      final ten = computeQuote(_quote(joints: [_dn100(count: 10)]));
      expect(ten.depositedKg, closeTo(one.depositedKg * 10, 1e-9));
      expect(ten.weldHours, closeTo(one.weldHours * 10, 1e-9));
      expect(ten.weldCount, 10);
    });

    test('przygotowanie automatyczne DN100 Sch 40 ≈ 30 min; ręczne wygrywa',
        () {
      expect(autoPrepMinutes(_dn100()), closeTo(30.2, 0.1));
      final r = computeQuote(
          _quote(joints: [_dn100().copyWith(prepMinutes: () => 60)]));
      expect(r.prepHours, closeTo(1.0, 1e-9));
    });

    test('formowanie tylko gdy włączone i tylko na rurach', () {
      final off = computeQuote(_quote());
      expect(off.purgeL, 0);
      final on = computeQuote(_quote(purge: true));
      expect(on.purgeL, greaterThan(0));
      final plate = computeQuote(_quote(purge: true, joints: const [
        QuoteJoint(
            id: 'p', kind: JointKind.plateFillet, throatMm: 4, lengthM: 2),
      ]));
      expect(plate.purgeL, 0);
    });

    test('nadpisany profil procesu zmienia wynik', () {
      final rates = QuoteRates.defaultsFor(QuoteMaterial.carbon).copyWith(
        profiles: {
          QuoteProcess.mma: kDefaultProcessProfiles[QuoteProcess.mma]!
              .copyWith(depositionKgH: 2.0),
        },
      );
      final fast = computeQuote(_quote(rates: rates));
      final normal = computeQuote(_quote());
      expect(fast.byProcess[QuoteProcess.mma]!.arcHours,
          closeTo(normal.byProcess[QuoteProcess.mma]!.arcHours / 2, 1e-12));
    });

    test('błędna pozycja nie liczy się do sum i jest policzona jako błędna',
        () {
      final r = computeQuote(_quote(joints: [
        _dn100(),
        const QuoteJoint(id: 'bad', kind: JointKind.pipeButt, odMm: 0),
      ]));
      expect(r.invalidJointCount, 1);
      expect(r.weldCount, 1);
      expect(r.joints[1].problems, contains(JointProblem.od));
    });

    test('aluminium lżejsze: ta sama spoina waży ~34 % stali', () {
      final al = computeQuote(_quote(
          material: QuoteMaterial.aluminium,
          scheme: const WeldScheme.single(QuoteProcess.tig)));
      final cs = computeQuote(
          _quote(scheme: const WeldScheme.single(QuoteProcess.tig)));
      expect(al.depositedKg / cs.depositedKg, closeTo(2.70 / 7.85, 1e-9));
    });
  });

  group('pieniądze (grosze)', () {
    test('składniki sumują się dokładnie do netto i brutto', () {
      final rates = QuoteRates.defaultsFor(QuoteMaterial.stainless).copyWith(
        overheadPct: 15,
        marginPct: 10,
        ndt: {
          NdtMethod.rt: const NdtRate(percent: 10, pricePerJoint: 120),
          NdtMethod.pt: const NdtRate(percent: 100, pricePerJoint: 35.5),
        },
      );
      final r = computeQuote(_quote(
        material: QuoteMaterial.stainless,
        rates: rates,
        purge: true,
        joints: [_dn100(count: 12)],
        extras: const [
          QuoteExtra(
              id: 'a',
              description: 'Dojazd',
              quantity: 120,
              unit: 'km',
              unitPrice: 1.15),
          QuoteExtra(
              id: 'b',
              description: 'Atest',
              quantity: 1,
              unitPrice: 99.99,
              withMarkup: false),
        ],
      ));
      final direct = r.costs.values.fold(0, (s, v) => s + v);
      expect(r.directGrosze, direct);
      expect(r.overheadGrosze, (direct * 0.15).round());
      expect(r.marginGrosze, ((direct + r.overheadGrosze) * 0.10).round());
      expect(r.passThroughGrosze, 9999);
      expect(r.netGrosze,
          direct + r.overheadGrosze + r.marginGrosze + r.passThroughGrosze);
      expect(r.vatGrosze, (r.netGrosze * 0.23).round());
      expect(r.grossGrosze, r.netGrosze + r.vatGrosze);
      expect(r.costOf(QuoteCostKind.extras), 13800); // 120 km × 1,15 zł
      // 10 % z 12 spoin → 2 badane (w górę), PT 100 % → 12.
      expect(r.ndtJoints[NdtMethod.rt], 2);
      expect(r.ndtJoints[NdtMethod.pt], 12);
      expect(r.ndtCosts[NdtMethod.rt], 24000);
      expect(r.ndtCosts[NdtMethod.pt], 42600);
      expect(r.costOf(QuoteCostKind.ndt), 66600);
      expect(r.fillerCosts.values.fold(0, (s, v) => s + v),
          r.costOf(QuoteCostKind.filler));
    });

    test('robocizna = godziny × stawka, w groszach', () {
      final r = computeQuote(_quote());
      expect(
          r.costOf(QuoteCostKind.weldLabour), (r.weldHours * 90 * 100).round());
      expect(
          r.costOf(QuoteCostKind.prepLabour), (r.prepHours * 75 * 100).round());
    });

    test('VAT „np." i „zw." — brutto = netto', () {
      for (final v in [QuoteVat.notApplicable, QuoteVat.exempt]) {
        final r = computeQuote(_quote(
            rates:
                QuoteRates.defaultsFor(QuoteMaterial.carbon).copyWith(vat: v)));
        expect(r.vatGrosze, 0);
        expect(r.grossGrosze, r.netGrosze);
      }
    });

    test('pusta wycena = 0 zł, bez dzielenia przez zero', () {
      final r = computeQuote(_quote(joints: const []));
      expect(r.netGrosze, 0);
      expect(r.netPerWeldGrosze, 0);
      expect(r.netPerDiGrosze, 0);
      expect(r.netPerMetreGrosze, 0);
      expect(r.workingDays, 0);
    });

    test('porównanie ze stawką rynkową za DI', () {
      final r = computeQuote(_quote(
          joints: [_dn100(count: 10)],
          rates: QuoteRates.defaultsFor(QuoteMaterial.carbon)
              .copyWith(marketDiRate: 45)));
      expect(r.marketNetGrosze, 40 * 45 * 100);
    });

    test('formatPln: spacje tysięcy, przecinek, minus', () {
      expect(formatPln(1234567), '12 345,67 zł');
      expect(formatPln(5), '0,05 zł');
      expect(formatPln(100000000, withUnit: false), '1 000 000,00');
      expect(formatPln(-150), '−1,50 zł');
    });

    test('formatQty', () {
      expect(formatQty(1.5), '1,5');
      expect(formatQty(2.0), '2');
      expect(formatQty(0.126, decimals: 2), '0,13');
    });
  });

  group('zapis', () {
    test('wycena przeżywa zapis do wiersza i odczyt — ten sam wynik', () {
      final q = _quote(
        material: QuoteMaterial.duplex,
        purge: true,
        site: QuoteSite.field,
        rates: QuoteRates.defaultsFor(QuoteMaterial.duplex).copyWith(
          overheadPct: 12.5,
          marginPct: 8,
          vat: QuoteVat.vat8,
          ndt: {NdtMethod.ut: const NdtRate(percent: 25, pricePerJoint: 80)},
          profiles: {
            QuoteProcess.tig: kDefaultProcessProfiles[QuoteProcess.tig]!
                .copyWith(dutyCycle: 0.5),
          },
          marketDiRate: 50,
        ),
        joints: [
          _dn100(count: 3, pos: WeldPosition.pf),
          const QuoteJoint(
              id: 'b',
              kind: JointKind.branch,
              odMm: 60.3,
              wallMm: 3.91,
              headerOdMm: 168.3,
              angleDeg: 45,
              count: 2,
              scheme: WeldScheme.single(QuoteProcess.tig),
              prepMinutes: 25),
          const QuoteJoint(
              id: 'p',
              kind: JointKind.plateButt,
              wallMm: 12,
              lengthM: 1.5,
              groove: GrooveType.x,
              count: 4),
        ],
        extras: const [
          QuoteExtra(
              id: 'e',
              description: 'Agregat',
              quantity: 2,
              unit: 'dzień',
              unitPrice: 250)
        ],
      ).copyWith(
          number: 'WYC/2026/007',
          title: 'Kolektor',
          client: 'ACME',
          notes: 'uwagi',
          status: QuoteStatus.sent,
          crew: 3);
      final before = computeQuote(q);
      final row =
          q.toRow(netGrosze: before.netGrosze, grossGrosze: before.grossGrosze);
      final back = WeldQuote.fromRow(row);
      final after = computeQuote(back);
      expect(back.number, 'WYC/2026/007');
      expect(back.status, QuoteStatus.sent);
      expect(back.crew, 3);
      expect(back.joints.length, 3);
      expect(back.joints[1].scheme, const WeldScheme.single(QuoteProcess.tig));
      expect(back.joints[2].groove, GrooveType.x);
      expect(after.netGrosze, before.netGrosze);
      expect(after.grossGrosze, before.grossGrosze);
      expect(after.vatGrosze, before.vatGrosze);
      expect(row['net_grosze'], before.netGrosze);
    });

    test('uszkodzony JSON nie wywraca odczytu', () {
      final q = WeldQuote.fromRow(const {
        'id': 'x',
        'number': 'WYC/2026/001',
        'title': 'T',
        'data_json': '{oops',
        'created_at': 1,
        'updated_at': 2,
      });
      expect(q.title, 'T');
      expect(q.joints, isEmpty);
    });

    test('numeracja ofert: max + 1 w roku, inne lata nie przeszkadzają', () {
      expect(nextQuoteNumber(const [], 2026), 'WYC/2026/001');
      expect(
          nextQuoteNumber(
              const ['WYC/2026/001', 'WYC/2026/009', 'WYC/2025/044', 'inny'],
              2026),
          'WYC/2026/010');
    });

    test('schemat procesów: kod tam i z powrotem', () {
      for (final s in kCommonSchemes) {
        expect(WeldScheme.fromCode(s.code), s);
      }
      expect(WeldScheme.fromCode('TIG+TIG'),
          const WeldScheme.single(QuoteProcess.tig));
      expect(WeldScheme.fromCode('XYZ'), isNull);
    });
  });
}
