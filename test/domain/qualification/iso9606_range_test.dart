// Zakres uprawnień z próbki — EN ISO 9606-1:2017 (ISO 9606-1:2012 + Cor 1).
// Wiersze kontrolne każdej tabeli, granice (s = 3, s = 12, D = 25, t = 3),
// rura / blacha, BW / FW, pozycje, procesy łączone, braki danych i szkic do
// rejestru sprawdzony prawdziwą kontrolą spoiny (weld_range_check.dart).
//
// Liczby kontrolne z arkuszy interpretacyjnych ISO/TC 44/SC 11:
//  • 138 s = 3 → 3–6 mm, 136 s = 9 → 3–18 mm, razem 6 + 18 mm (2015-04-23);
//  • FW t 1,4 → 1,4–3,0; t 2,9 → 2,9–5,8; t 2 → 2–4; t 20 → ≥ 3;
//  • H-L045 obejmuje PH, J-L045 obejmuje PJ (2014-04-08);
//  • BW PE + dodatkowa FW PB → FW PA, PB, PC, PD, PE (2015-04-23).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/iso9606_range.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/wps/weld_range_check.dart';

const _p = Iso9606Process.values;

Iso9606ProcessInput _proc(Iso9606Process p, double? t,
        {Iso9606Filler? filler, Iso9606Transfer? transfer}) =>
    Iso9606ProcessInput(
      process: p,
      filler: filler ?? p.fillers.first,
      transfer: transfer ??
          (p.hasTransferMode ? Iso9606Transfer.dip : null),
      thicknessMm: t,
    );

/// Kompletna próbka BW na blasze 141 — do modyfikowania w testach.
Iso9606Sample _bw({
  Iso9606Product product = Iso9606Product.plate,
  Iso9606ProcessInput? first,
  Iso9606ProcessInput? second,
  Iso9606FmGroup fm = Iso9606FmGroup.fm1,
  double? d,
  Iso6947Position position = Iso6947Position.pa,
  Iso9606Backing backing = Iso9606Backing.ssNb,
  Iso9606Layers? layers = Iso9606Layers.threeOrMore,
  bool supplementary = false,
  bool companion = false,
  Iso9606GasDirection? gas,
  String parent = '',
}) =>
    Iso9606Sample(
      product: product,
      weldType: Iso9606WeldType.bw,
      first: first ?? _proc(Iso9606Process.p141, 3),
      second: second,
      fm: fm,
      diameterMm: d,
      position: position,
      backing: backing,
      layers: layers,
      supplementaryFillet: supplementary,
      pcCompanion: companion,
      gasDirection: gas,
      parentGroup: parent,
    );

Iso9606Sample _fw({
  Iso9606Product product = Iso9606Product.plate,
  Iso9606ProcessInput? first,
  double? d,
  Iso6947Position position = Iso6947Position.pb,
  Iso9606FilletLayers layers = Iso9606FilletLayers.sl,
}) =>
    Iso9606Sample(
      product: product,
      weldType: Iso9606WeldType.fw,
      first: first ?? _proc(Iso9606Process.p135, 10),
      fm: Iso9606FmGroup.fm1,
      diameterMm: d,
      position: position,
      filletLayers: layers,
    );

Iso9606Range _range(Iso9606Sample s) {
  final e = evaluateIso9606(s);
  expect(e.problems, isEmpty, reason: 'problemy: ${e.problems}');
  return e.range!;
}

List<String> _pos(List<Iso6947Position> p) => p.map((e) => e.code).toList();

String _line(Iso9606Range r, String key, {bool en = false}) =>
    iso9606Lines(r, en: en).firstWhere((l) => l.key == key).value;

void main() {
  group('tab. 6 — grubość stopiwa BW', () {
    test('s < 3: s do 3 albo s do 2s, co większe', () {
      expect(iso9606ButtThickness(1), const MmRange(1, 3));
      expect(iso9606ButtThickness(1.4), const MmRange(1.4, 3));
      expect(iso9606ButtThickness(1.5), const MmRange(1.5, 3));
      expect(iso9606ButtThickness(2), const MmRange(2, 4));
      expect(iso9606ButtThickness(2.9), const MmRange(2.9, 5.8));
    });

    test('granica s = 3: wiersz 3 ≤ s < 12 → 3–6', () {
      expect(iso9606ButtThickness(2.99), const MmRange(2.99, 5.98));
      expect(iso9606ButtThickness(3), const MmRange(3, 6));
      expect(iso9606ButtThickness(9), const MmRange(3, 18));
    });

    test('granica s = 12: 11,99 → 3–23,98; 12 → ≥ 3 bez górnej granicy', () {
      expect(iso9606ButtThickness(11.99), const MmRange(3, 23.98));
      expect(iso9606ButtThickness(12), const MmRange(3));
      expect(iso9606ButtThickness(40), const MmRange(3));
    });

    test('311 (przypisy c, d): s do 1,5s; 3 do 1,5s', () {
      expect(iso9606ButtThickness(2, oxyacetylene: true),
          const MmRange(2, 3));
      expect(iso9606ButtThickness(4, oxyacetylene: true),
          const MmRange(3, 6));
      expect(iso9606ButtThickness(12, oxyacetylene: true), const MmRange(3));
    });

    test('s ≥ 12 wymaga min. 3 warstw (przypis e) — inaczej brak wyniku', () {
      final none = evaluateIso9606(
          _bw(first: _proc(Iso9606Process.p135, 15), layers: null));
      expect(none.range, isNull);
      expect(none.problems, contains(Iso9606Problem.layersNeeded));
      final two = evaluateIso9606(
          _bw(first: _proc(Iso9606Process.p135, 15), layers: Iso9606Layers.two));
      expect(two.range, isNull);
      expect(two.problems, contains(Iso9606Problem.tooFewLayers));
      final ok = _range(_bw(first: _proc(Iso9606Process.p135, 15)));
      expect(_line(ok, 'thickness'), '≥ 3 mm');
      // Notka o rozbieżności ze starą EN 287-1 (≥ 5).
      expect(ok.notes.where((n) => n.check && n.pl.contains('EN 287-1')),
          hasLength(1));
      // Cienka próbka nie potrzebuje liczby warstw.
      expect(evaluateIso9606(_bw(layers: null)).problems, isEmpty);
    });
  });

  group('tab. 7 — średnica', () {
    test('D ≤ 25 → D do 2D; granica D = 25 → 25–50', () {
      expect(iso9606Diameter(10), const MmRange(10, 20));
      expect(iso9606Diameter(21.3), const MmRange(21.3, 42.6));
      expect(iso9606Diameter(25), const MmRange(25, 50));
    });

    test('D > 25 → ≥ 0,5D, nie mniej niż 25', () {
      expect(iso9606Diameter(25.1), const MmRange(25));
      expect(iso9606Diameter(48.3), const MmRange(25));
      expect(iso9606Diameter(50), const MmRange(25));
      expect(iso9606Diameter(60.3), const MmRange(30.15));
      expect(iso9606Diameter(168.3), const MmRange(84.15));
    });

    test('dolna granica zaokrąglana W GÓRĘ, górna W DÓŁ', () {
      expect(iso9606RangeText(iso9606Diameter(60.33), en: false), '≥ 30,17 mm');
      expect(iso9606RangeText(iso9606Diameter(60.3), en: false), '≥ 30,15 mm');
      expect(iso9606RoundMax(5.999), 5.99);
      expect(iso9606RoundMin(30.151), 30.16);
      expect(iso9606RoundMin(30.15), 30.15);
    });
  });

  group('tab. 8 — grubość FW', () {
    test('t < 3 → t do 2t lub 3 (co większe); t ≥ 3 → ≥ 3', () {
      expect(iso9606FilletThickness(1), const MmRange(1, 3));
      expect(iso9606FilletThickness(1.4), const MmRange(1.4, 3));
      expect(iso9606FilletThickness(2), const MmRange(2, 4));
      expect(iso9606FilletThickness(2.9), const MmRange(2.9, 5.8));
      expect(iso9606FilletThickness(3), const MmRange(3));
      expect(iso9606FilletThickness(20), const MmRange(3));
    });

    test('próbka FW na blasze PB, 10 mm, sl: ≥ 3, PA, PB, tylko sl', () {
      final r = _range(_fw());
      expect(_line(r, 'thickness'), '≥ 3 mm');
      expect(_pos(r.positions), ['PA', 'PB']);
      expect(_line(r, 'layers'), 'sl');
      expect(r.weldTypes, [Iso9606WeldType.fw]);
      expect(r.notes.any((n) => n.pl.contains('NIE obejmuje czołowych')),
          isTrue);
    });
  });

  group('tab. 3 — grupy spoiw', () {
    test('wiersze tabeli', () {
      Set<String> fm(Iso9606FmGroup g) =>
          kIso9606FmRange[g]!.map((e) => e.code).toSet();
      expect(fm(Iso9606FmGroup.fm1), {'FM1', 'FM2'});
      expect(fm(Iso9606FmGroup.fm2), {'FM1', 'FM2'});
      expect(fm(Iso9606FmGroup.fm3), {'FM1', 'FM2', 'FM3'});
      expect(fm(Iso9606FmGroup.fm4), {'FM1', 'FM2', 'FM3', 'FM4'});
      expect(fm(Iso9606FmGroup.fm5), {'FM5'});
      expect(fm(Iso9606FmGroup.fm6), {'FM5', 'FM6'});
    });

    test('FM5 w wyniku i szkicu', () {
      final r = _range(_bw(fm: Iso9606FmGroup.fm6));
      expect(_line(r, 'fm'), 'FM5, FM6');
    });
  });

  group('tab. 4 i 5 — typ spoiwa, §5.2 — procesy', () {
    test('111: B obejmuje A…R i B; A…R tylko A…R; C tylko C', () {
      String fill(Iso9606Filler f) => _line(
          _range(_bw(first: _proc(Iso9606Process.p111, 10, filler: f))),
          'filler-0');
      expect(fill(Iso9606Filler.coveringBasic), 'A, RA, RB, RC, RR, R, B');
      expect(fill(Iso9606Filler.coveringRutile), 'A, RA, RB, RC, RR, R');
      expect(fill(Iso9606Filler.coveringCellulosic), 'C');
    });

    test('druty: S ↔ M; B obejmuje R, P, V, W, Y, Z; R… tylko R…', () {
      Set<Iso9606Filler> q(Iso9606Filler f) => kIso9606FillerRange[f]!;
      expect(q(Iso9606Filler.solid),
          containsAll([Iso9606Filler.solid, Iso9606Filler.metalCored]));
      expect(q(Iso9606Filler.metalCored), contains(Iso9606Filler.solid));
      expect(q(Iso9606Filler.basicCored),
          containsAll([Iso9606Filler.basicCored, Iso9606Filler.otherCored]));
      expect(q(Iso9606Filler.otherCored),
          isNot(contains(Iso9606Filler.basicCored)));
      // §5.6: bez spoiwa nie obejmuje spawania ze spoiwem.
      expect(q(Iso9606Filler.none), {Iso9606Filler.none});
    });

    test('141 S → 141, 142, 143 (tylko M), 145; 142 → tylko 142', () {
      final r = _range(_bw());
      expect(r.processes.single.processes.keys.map((p) => p.code),
          ['141', '142', '143', '145']);
      expect(r.processes.single.processes[Iso9606Process.p143],
          [Iso9606Filler.metalCored]);
      expect(_line(r, 'filler-0'), 'S, M, bez spoiwa (nm)');
      final auto = _range(_bw(
          first: _proc(Iso9606Process.p142, 2), parent: '8.1'));
      expect(auto.processes.single.processes.keys, [Iso9606Process.p142]);
      expect(auto.parentGroup, '8.1');
      expect(auto.fmGroups, isEmpty);
    });

    test('135 ↔ 138; 121 S → 121, 125; 125 B → bez 121; 136, 111 osobno', () {
      List<String> procs(Iso9606ProcessInput p) =>
          _range(_bw(first: p)).processes.single.processes.keys
              .map((e) => e.code)
              .toList();
      expect(procs(_proc(Iso9606Process.p135, 8)), ['135', '138']);
      expect(procs(_proc(Iso9606Process.p138, 8)), ['135', '138']);
      expect(procs(_proc(Iso9606Process.p121, 8)), ['121', '125']);
      expect(
          procs(_proc(Iso9606Process.p125, 8, filler: Iso9606Filler.basicCored)),
          ['125']);
      expect(
          procs(_proc(Iso9606Process.p136, 8, filler: Iso9606Filler.basicCored)),
          ['136']);
      expect(procs(_proc(Iso9606Process.p111, 8)), ['111']);
    });

    test('przenoszenie metalu: zwarciowe obejmuje wszystkie, inne — nie zwarciowe',
        () {
      final dip = _range(_bw(first: _proc(Iso9606Process.p135, 8)));
      expect(_line(dip, 'transfer-0'), 'wszystkie rodzaje (próba zwarciowa)');
      final spray = _range(_bw(
          first: _proc(Iso9606Process.p135, 8,
              transfer: Iso9606Transfer.other)));
      expect(_line(spray, 'transfer-0'), 'wszystkie oprócz zwarciowego');
      expect(spray.notes.any((n) => n.pl.contains('NIE obejmuje zwarciowego')),
          isTrue);
      // Bez wyboru — komunikat, nie wynik.
      final missing = evaluateIso9606(_bw(
          first: const Iso9606ProcessInput(
              process: Iso9606Process.p135,
              filler: Iso9606Filler.solid,
              thicknessMm: 8)));
      expect(missing.problems, [Iso9606Problem.transfer]);
    });

    test('ISO 9606-1 §4.2 — 14 procesów', () {
      expect(_p.map((p) => p.code), [
        '111', '114', '121', '125', '131', '135', '136', '138', '141', //
        '142', '143', '145', '15', '311',
      ]);
    });
  });

  group('tab. 9 — pozycje BW', () {
    List<String> bw(Iso6947Position p,
            {Iso9606Product product = Iso9606Product.plate,
            bool companion = false}) =>
        _pos(_range(_bw(
          product: product,
          position: p,
          d: product == Iso9606Product.pipe ? 168.3 : null,
          companion: companion,
        )).positions);

    test('wiersze blachy: PA, PC, PE, PF, PG', () {
      expect(bw(Iso6947Position.pa), ['PA']);
      expect(bw(Iso6947Position.pc), ['PA', 'PC']);
      expect(bw(Iso6947Position.pe), ['PA', 'PC', 'PE']);
      expect(bw(Iso6947Position.pf), ['PA', 'PF']);
      expect(bw(Iso6947Position.pg), ['PG']);
    });

    test('rura PH obejmuje PA, PE, PF (+ PH), PJ — PA, PE, PG (+ PJ)', () {
      const t = Iso9606Product.pipe;
      expect(bw(Iso6947Position.ph, product: t), ['PA', 'PE', 'PF', 'PH']);
      expect(bw(Iso6947Position.pj, product: t), ['PA', 'PE', 'PG', 'PJ']);
      expect(bw(Iso6947Position.pa, product: t), ['PA']);
      expect(bw(Iso6947Position.pc, product: t), ['PA', 'PC']);
    });

    test('H-L045 obejmuje PA, PC, PE, PF + PH (interpretacja 2014); J-L045 → PG, PJ',
        () {
      const t = Iso9606Product.pipe;
      expect(bw(Iso6947Position.hL045, product: t),
          ['PA', 'PC', 'PE', 'PF', 'PH', 'H-L045']);
      expect(bw(Iso6947Position.jL045, product: t),
          ['PA', 'PC', 'PE', 'PG', 'PJ', 'J-L045']);
      // Ani PG, ani PJ z H-L045 (kierunek z dołu do góry).
      expect(bw(Iso6947Position.hL045, product: t), isNot(contains('PJ')));
    });

    test('PH + PC (dwie rury tej samej D) = zakres H-L045 (§5.8)', () {
      const t = Iso9606Product.pipe;
      expect(bw(Iso6947Position.ph, product: t, companion: true),
          ['PA', 'PC', 'PE', 'PF', 'PH', 'H-L045']);
      expect(bw(Iso6947Position.pj, product: t, companion: true),
          ['PA', 'PC', 'PE', 'PG', 'PJ', 'J-L045']);
      // Przełącznik działa tylko dla PH / PJ.
      expect(bw(Iso6947Position.pa, product: t, companion: true), ['PA']);
    });

    test('pozycje spoza tabeli dla próbki → komunikat', () {
      final pb = evaluateIso9606(_bw(position: Iso6947Position.pb));
      expect(pb.problems, [Iso9606Problem.positionNotForSample]);
      final phPlate = evaluateIso9606(_bw(position: Iso6947Position.ph));
      expect(phPlate.problems, [Iso9606Problem.positionNotForSample]);
      final pePipe = evaluateIso9606(_bw(
          product: Iso9606Product.pipe, d: 60.3, position: Iso6947Position.pe));
      expect(pePipe.problems, [Iso9606Problem.positionNotForSample]);
    });
  });

  group('tab. 10 — pozycje FW', () {
    List<String> fw(Iso6947Position p,
            {Iso9606Product product = Iso9606Product.plate}) =>
        _pos(_range(_fw(
          product: product,
          position: p,
          d: product == Iso9606Product.pipe ? 168.3 : null,
        )).positions);

    test('wiersze blachy', () {
      expect(fw(Iso6947Position.pa), ['PA']);
      expect(fw(Iso6947Position.pb), ['PA', 'PB']);
      expect(fw(Iso6947Position.pc), ['PA', 'PB', 'PC']);
      expect(fw(Iso6947Position.pd), ['PA', 'PB', 'PC', 'PD', 'PE']);
      expect(fw(Iso6947Position.pe), ['PA', 'PB', 'PC', 'PD', 'PE']);
      expect(fw(Iso6947Position.pf), ['PA', 'PB', 'PF']);
      expect(fw(Iso6947Position.pg), ['PG']);
    });

    test('rura PH → PA–PF + PH; PJ → PA, PB, PD, PE, PG + PJ', () {
      const t = Iso9606Product.pipe;
      expect(fw(Iso6947Position.ph, product: t),
          ['PA', 'PB', 'PC', 'PD', 'PE', 'PF', 'PH']);
      expect(fw(Iso6947Position.pj, product: t),
          ['PA', 'PB', 'PD', 'PE', 'PG', 'PJ']);
    });

    test('H-L045 nie ma wiersza w tab. 10 → komunikat', () {
      final e = evaluateIso9606(_fw(
          product: Iso9606Product.pipe,
          d: 60.3,
          position: Iso6947Position.hL045));
      expect(e.problems, [Iso9606Problem.positionNotForSample]);
    });

    test('tab. 12: sl → sl; ml → sl, ml; bez wyboru — komunikat', () {
      expect(_line(_range(_fw(layers: Iso9606FilletLayers.ml)), 'layers'),
          'sl, ml');
      final e = evaluateIso9606(const Iso9606Sample(
        weldType: Iso9606WeldType.fw,
        first: Iso9606ProcessInput(
            process: Iso9606Process.p141,
            filler: Iso9606Filler.solid,
            thicknessMm: 3),
        fm: Iso9606FmGroup.fm1,
        position: Iso6947Position.pb,
      ));
      expect(e.problems, [Iso9606Problem.filletLayers]);
    });
  });

  group('§5.4 e — dodatkowa próbka pachwinowa', () {
    test('BW PE + FW PB → FW PA, PB, PC, PD, PE (interpretacja 2015)', () {
      final r = _range(_bw(
          first: _proc(Iso9606Process.p135, 10),
          position: Iso6947Position.pe,
          supplementary: true));
      expect(r.weldTypes, [Iso9606WeldType.bw, Iso9606WeldType.fw]);
      expect(_pos(r.filletPositions!), ['PA', 'PB', 'PC', 'PD', 'PE']);
      expect(_line(r, 'fillet-thickness'), '≥ 3 mm');
      // Wielowarstwowa czołowa + dodatkowa → sl i ml (tab. 12 przypis b).
      expect(_line(r, 'layers'), 'sl, ml');
    });

    test('jednowarstwowa czołowa → tylko sl; bez liczby warstw → komunikat', () {
      final one = _range(_bw(
          first: _proc(Iso9606Process.p141, 2),
          layers: Iso9606Layers.one,
          supplementary: true));
      expect(_line(one, 'layers'), 'sl');
      // t 2 → FW 2–4.
      expect(_line(one, 'fillet-thickness'), '2–4 mm');
      final missing = evaluateIso9606(_bw(layers: null, supplementary: true));
      expect(missing.problems, [Iso9606Problem.layersNeeded]);
    });

    test('H-L045 (brak wiersza w tab. 10) → FW tylko PA, PB + notka „sprawdź”',
        () {
      final r = _range(_bw(
          product: Iso9606Product.pipe,
          d: 60.3,
          position: Iso6947Position.hL045,
          supplementary: true));
      expect(_pos(r.filletPositions!), ['PA', 'PB']);
      expect(r.notes.where((n) => n.check && n.pl.contains('H-L045')),
          isNotEmpty);
    });

    test('bez dodatkowej próbki BW nie obejmuje FW (§5.4 b)', () {
      final r = _range(_bw());
      expect(r.weldTypes, [Iso9606WeldType.bw]);
      expect(r.filletPositions, isNull);
      expect(r.notes.any((n) => n.pl.contains('NIE obejmuje pachwinowych')),
          isTrue);
    });
  });

  group('tab. 11 — prowadzenie grani', () {
    String back(Iso9606Process p, Iso9606Backing b) =>
        _line(_range(_bw(first: _proc(p, 8), backing: b)), 'backing-0');

    test('ss nb obejmuje nb, mb, bs (+ gb, fb tam, gdzie dotyczą procesu)', () {
      expect(back(Iso9606Process.p111, Iso9606Backing.ssNb), 'ss nb, ss mb, bs');
      expect(back(Iso9606Process.p141, Iso9606Backing.ssNb),
          'ss nb, ss mb, bs, ss gb, ss fb');
      expect(back(Iso9606Process.p121, Iso9606Backing.ssNb),
          'ss nb, ss mb, bs, ss fb');
    });

    test('ss mb i bs → ss mb, bs; gb → + gb; ci → + ci; fb → + fb', () {
      expect(back(Iso9606Process.p135, Iso9606Backing.ssMb), 'ss mb, bs');
      expect(back(Iso9606Process.p135, Iso9606Backing.bs), 'ss mb, bs');
      expect(back(Iso9606Process.p141, Iso9606Backing.ssGb), 'ss mb, bs, ss gb');
      expect(back(Iso9606Process.p141, Iso9606Backing.ci), 'ss mb, bs, ci');
      expect(back(Iso9606Process.p121, Iso9606Backing.ssFb), 'ss mb, bs, ss fb');
    });

    test('gb / ci / fb przy procesie, którego nie dotyczą → komunikat', () {
      Iso9606Evaluation e(Iso9606Process p, Iso9606Backing b) =>
          evaluateIso9606(_bw(first: _proc(p, 8), backing: b));
      expect(e(Iso9606Process.p111, Iso9606Backing.ssGb).problems,
          [Iso9606Problem.backingNotForProcess]);
      expect(e(Iso9606Process.p135, Iso9606Backing.ci).problems,
          [Iso9606Problem.backingNotForProcess]);
      expect(e(Iso9606Process.p111, Iso9606Backing.ssFb).problems,
          [Iso9606Problem.backingNotForProcess]);
    });

    test('grań bez podkładki otuliną B → notka „tylko typ z próby”', () {
      final r = _range(_bw(
          first: _proc(Iso9606Process.p111, 10,
              filler: Iso9606Filler.coveringBasic)));
      expect(r.notes.any((n) => n.pl.contains('tab. 4 i 5, przypis b')),
          isTrue);
      expect(_range(_bw()).notes.any((n) => n.pl.contains('przypis b')),
          isFalse);
    });
  });

  group('§5.3 — rura / blacha', () {
    test('rura D ≤ 25 nie obejmuje blach; D > 25 obejmuje', () {
      final small = _range(_bw(
          product: Iso9606Product.pipe, d: 25, position: Iso6947Position.pa,
          first: _proc(Iso9606Process.p141, 2)));
      expect(small.coversPlates, isFalse);
      expect(_line(small, 'product'), contains('blachy — NIE'));
      expect(_line(small, 'diameter'), '25–50 mm');
      final big = _range(_bw(
          product: Iso9606Product.pipe, d: 25.1, position: Iso6947Position.pa,
          first: _proc(Iso9606Process.p141, 2)));
      expect(big.coversPlates, isTrue);
      expect(_line(big, 'diameter'), '≥ 25 mm');
    });

    test('blacha → rury nieruchome D ≥ 500, obracane D ≥ 75 tylko PA/PB/PC/PD',
        () {
      final pc = _range(_bw(position: Iso6947Position.pc));
      expect(_pos(pc.rotatingPipePositions!), ['PA', 'PC']);
      expect(_line(pc, 'product'),
          'blachy (P); rury nieruchome D ≥ 500 mm; rury obracane D ≥ 75 mm (PA, PC)');
      final pf = _range(_bw(position: Iso6947Position.pf));
      expect(_pos(pf.rotatingPipePositions!), ['PA']);
      final pg = _range(_bw(position: Iso6947Position.pg));
      expect(pg.rotatingPipePositions, isEmpty);
      expect(_line(pg, 'product'), isNot(contains('obracane')));
    });

    test('rura bez średnicy, z nieczytelną albo za cienką ścianką → komunikat',
        () {
      Iso9606Evaluation e(double? d, double t) => evaluateIso9606(_bw(
          product: Iso9606Product.pipe,
          d: d,
          position: Iso6947Position.pa,
          first: _proc(Iso9606Process.p141, t)));
      expect(e(null, 3).problems, [Iso9606Problem.diameter]);
      expect(e(double.nan, 3).problems, [Iso9606Problem.diameterInvalid]);
      expect(e(0, 3).problems, [Iso9606Problem.diameterInvalid]);
      expect(e(20, 11).problems, [Iso9606Problem.wallTooThick]);
      expect(e(22, 11).problems, isEmpty);
    });
  });

  group('tab. 1 — dwa procesy (141 grań + 111 wypełnienie)', () {
    Iso9606Sample multi(double s1, double s2,
            {Iso9606Layers layers = Iso9606Layers.threeOrMore}) =>
        _bw(
          product: Iso9606Product.pipe,
          d: 168.3,
          position: Iso6947Position.ph,
          first: _proc(Iso9606Process.p141, s1),
          second: _proc(Iso9606Process.p111, s2,
              filler: Iso9606Filler.coveringBasic),
          layers: layers,
        );

    test('każdy proces z własnym s; złącze ograniczone sumą (3 + 9 → 3–24)', () {
      final r = _range(multi(3, 9));
      expect(_line(r, 'thickness-0'), '3–6 mm');
      expect(_line(r, 'thickness-1'), '3–18 mm');
      expect(_line(r, 'thickness'), '3–24 mm');
      // Proces 2 spawał na grani — sam tylko ss mb / bs.
      expect(_line(r, 'backing-0'), 'ss nb, ss mb, bs, ss gb, ss fb');
      expect(_line(r, 'backing-1'), 'ss mb, bs');
      expect(r.processes.first.root, isTrue);
      expect(r.notes.any((n) => n.pl.contains('tylko w strefie grani')), isTrue);
    });

    test('interpretacja 2015: 138 s 3 + 136 s 9 → 3–6, 3–18, razem do 24', () {
      final r = _range(_bw(
        first: _proc(Iso9606Process.p138, 3),
        second: _proc(Iso9606Process.p136, 9,
            filler: Iso9606Filler.basicCored),
      ));
      expect(r.processes[0].thickness, const MmRange(3, 6));
      expect(r.processes[1].thickness, const MmRange(3, 18));
      expect(r.jointThickness, const MmRange(3, 24));
    });

    test('cienka grań: 2 + 8 → 2–4, 3–16, złącze 3–20', () {
      final r = _range(multi(2, 8));
      expect(_line(r, 'thickness-0'), '2–4 mm');
      expect(_line(r, 'thickness-1'), '3–16 mm');
      expect(_line(r, 'thickness'), '3–20 mm');
    });

    test('wypełnienie s₂ ≥ 12 → złącze bez górnej granicy, ale min. 3 warstwy',
        () {
      expect(_line(_range(multi(3, 15)), 'thickness'), '≥ 3 mm');
      expect(evaluateIso9606(multi(3, 15, layers: Iso9606Layers.two)).problems,
          [Iso9606Problem.tooFewLayers]);
      // Złącze ≥ 12 przy obu s < 12 — ograniczone sumą, warstwy niepotrzebne.
      expect(evaluateIso9606(multi(3, 9, layers: Iso9606Layers.two)).problems,
          isEmpty);
    });

    test('ten sam proces i spoiwo dwa razy → komunikat; brak danych procesu 2',
        () {
      final same = evaluateIso9606(_bw(
          first: _proc(Iso9606Process.p141, 3),
          second: _proc(Iso9606Process.p141, 5)));
      expect(same.problems, [Iso9606Problem.sameProcessTwice]);
      final empty = evaluateIso9606(_bw(second: const Iso9606ProcessInput()));
      expect(empty.problems, [
        Iso9606Problem.process2,
        Iso9606Problem.thickness2,
      ]);
      // Drugi proces nie dotyczy FW.
      expect(
          evaluateIso9606(Iso9606Sample(
            weldType: Iso9606WeldType.fw,
            first: _proc(Iso9606Process.p135, 10),
            second: const Iso9606ProcessInput(),
            fm: Iso9606FmGroup.fm1,
            position: Iso6947Position.pb,
            filletLayers: Iso9606FilletLayers.sl,
          )).problems,
          isEmpty);
    });
  });

  group('braki danych → komunikat, nie wynik', () {
    test('pusta próbka: czego brakuje', () {
      final e = evaluateIso9606(const Iso9606Sample());
      expect(e.range, isNull);
      expect(e.problems, [
        Iso9606Problem.process,
        Iso9606Problem.thickness,
        Iso9606Problem.position,
        Iso9606Problem.fm,
        Iso9606Problem.backing,
      ]);
      for (final p in Iso9606Problem.values) {
        expect(iso9606ProblemText(p, en: false), isNotEmpty);
        expect(iso9606ProblemText(p, en: true), isNotEmpty);
      }
    });

    test('grubość NaN, 0, ujemna, absurdalna → „nieczytelne”', () {
      for (final t in [double.nan, double.infinity, 0.0, -2.0, 5000.0]) {
        expect(evaluateIso9606(_bw(first: _proc(Iso9606Process.p141, t)))
                .problems,
            [Iso9606Problem.thicknessInvalid],
            reason: '$t');
      }
    });

    test('spoiwo spoza procesu, bez spoiwa bez grupy materiału, 311 bez kierunku',
        () {
      expect(
          evaluateIso9606(_bw(
                  first: _proc(Iso9606Process.p141, 3,
                      filler: Iso9606Filler.coveringBasic)))
              .problems,
          [Iso9606Problem.filler]);
      expect(
          evaluateIso9606(_bw(first: _proc(Iso9606Process.p142, 2))).problems,
          [Iso9606Problem.parentGroup]);
      expect(
          evaluateIso9606(
                  _bw(first: _proc(Iso9606Process.p142, 2), parent: 'stal'))
              .problems,
          [Iso9606Problem.parentGroupInvalid]);
      expect(
          evaluateIso9606(_bw(first: _proc(Iso9606Process.p311, 2))).problems,
          [Iso9606Problem.gasDirection]);
      final gas = _range(_bw(
          first: _proc(Iso9606Process.p311, 2),
          gas: Iso9606GasDirection.leftward));
      expect(_line(gas, 'thickness'), '2–3 mm');
      expect(_line(gas, 'direction'), 'tylko lw');
    });
  });

  group('tekst i oznaczenie', () {
    Iso9606Sample pipe141() => _bw(
          product: Iso9606Product.pipe,
          d: 60.3,
          position: Iso6947Position.ph,
        );

    test('oznaczenie wg rozdz. 11; PL przecinek, EN kropka', () {
      expect(iso9606Designation(pipe141(), en: false),
          'EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb');
      expect(iso9606Designation(pipe141(), en: true),
          'EN ISO 9606-1 141 T BW FM1 S s3 D60.3 PH ss nb');
    });

    test('wynik nie zależy od języka — te same granice', () {
      final r = _range(pipe141());
      expect(_line(r, 'diameter'), '≥ 30,15 mm');
      expect(_line(r, 'diameter', en: true), '≥ 30.15 mm');
      expect(iso9606Lines(r, en: false).map((l) => l.key),
          iso9606Lines(r, en: true).map((l) => l.key));
    });

    test('tekst do udostępnienia: oznaczenie, linie z punktami normy, zastrzeżenie',
        () {
      final r = _range(pipe141());
      final pl = iso9606ShareText(r, en: false);
      expect(pl, contains('EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb'));
      expect(pl, contains('• Pozycje (BW): PA, PE, PF, PH [§5.8, tab. 9]'));
      expect(pl, contains('• Grubość stopiwa s (BW): 3–6 mm [§5.7, tab. 6]'));
      expect(pl, contains(iso9606Disclaimer(en: false)));
      final en = iso9606ShareText(r, en: true);
      expect(en, contains('• Positions (BW): PA, PE, PF, PH [cl. 5.8, Table 9]'));
      expect(en, contains(iso9606Disclaimer(en: true)));
    });
  });

  group('szkic certyfikatu do rejestru', () {
    List<WeldCheckField> scopeIssues(
            WelderCoverage c) =>
        c.certificates.single.issues
            .where((i) => i.field != WeldCheckField.validity &&
                i.field != WeldCheckField.continuity)
            .map((i) => i.field)
            .toList();

    test('141 T BW PH: pola i kontrola spoiny z rejestru', () {
      final r = _range(_bw(
          product: Iso9606Product.pipe, d: 60.3, position: Iso6947Position.ph));
      final c = iso9606CertificateDraft(r, en: false).certificate!;
      expect(c.processes, '141, 142, 143, 145');
      expect(c.thicknessMinMm, 3);
      expect(c.thicknessMaxMm, 6);
      expect(c.diameterMinMm, 30.15);
      expect(c.diameterMaxMm, isNull);
      expect(c.positions, 'PA, PE, PF, PH');
      expect(c.jointKinds, {WeldJointKind.bw});
      expect(c.materialGroup, '');
      expect(c.filler, 'FM1, FM2 · 141: S, M, bez spoiwa (nm)');
      expect(c.notes, contains('EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb'));

      WelderCoverage check(WeldParameters w) => checkWelderCoverage(
          weld: w, weldDate: DateTime(2026, 10, 17), certificates: [c]);
      // W zakresie.
      expect(
          scopeIssues(check(const WeldParameters(
              process: '141',
              thicknessMm: 5,
              outsideDiameterMm: 60.3,
              position: 'PH',
              jointKind: WeldJointKind.bw))),
          isEmpty);
      // Poza: proces, grubość, średnica, pozycja, FW.
      expect(scopeIssues(check(const WeldParameters(process: '135'))),
          [WeldCheckField.process]);
      expect(scopeIssues(check(const WeldParameters(thicknessMm: 6.5))),
          [WeldCheckField.thickness]);
      expect(scopeIssues(check(const WeldParameters(outsideDiameterMm: 30))),
          [WeldCheckField.diameter]);
      expect(scopeIssues(check(const WeldParameters(position: 'PC'))),
          [WeldCheckField.position]);
      expect(
          scopeIssues(
              check(const WeldParameters(jointKind: WeldJointKind.fw))),
          [WeldCheckField.jointKind]);
    });

    test('dwa procesy → grubość jako część wspólna (3–6), oba procesy', () {
      final r = _range(_bw(
        product: Iso9606Product.pipe,
        d: 168.3,
        position: Iso6947Position.ph,
        first: _proc(Iso9606Process.p141, 3),
        second: _proc(Iso9606Process.p111, 9,
            filler: Iso9606Filler.coveringBasic),
      ));
      final c = iso9606CertificateDraft(r, en: false).certificate!;
      expect(c.thicknessMinMm, 3);
      expect(c.thicknessMaxMm, 6);
      expect(c.processes, '111, 141, 142, 143, 145');
      expect(c.notes, contains('część wspólna'));
    });

    test('brak części wspólnej → nie zapisuje (komunikat)', () {
      // 141 s 1 → 1–3; 111 s 20 → ≥ 3: część wspólna to tylko 3 mm (OK);
      // 311 s 1 → 1–1,5; 111 s 20 → ≥ 3: pusto.
      final r = _range(_bw(
        first: _proc(Iso9606Process.p311, 1),
        second: _proc(Iso9606Process.p111, 20,
            filler: Iso9606Filler.coveringBasic),
        gas: Iso9606GasDirection.rightward,
      ));
      final d = iso9606CertificateDraft(r, en: false);
      expect(d.certificate, isNull);
      expect(d.problem, Iso9606DraftProblem.thicknessNoOverlap);
      expect(iso9606DraftProblemText(d.problem!, en: false), isNotEmpty);
    });

    test('BW + dodatkowa FW: pozycje i grubość — część wspólna, BW+FW', () {
      final r = _range(_bw(
          first: _proc(Iso9606Process.p135, 10),
          position: Iso6947Position.pe,
          supplementary: true));
      final c = iso9606CertificateDraft(r, en: false).certificate!;
      expect(c.positions, 'PA, PC, PE');
      expect(c.jointKinds, {WeldJointKind.bw, WeldJointKind.fw});
      expect(c.thicknessMinMm, 3);
      expect(c.thicknessMaxMm, 20);
    });

    test('blacha → rury tylko D ≥ 500 w rejestrze; 15 → „15 PAW”', () {
      final r = _range(_bw(first: _proc(Iso9606Process.p15, 4)));
      final c = iso9606CertificateDraft(r, en: true).certificate!;
      expect(c.diameterMinMm, 500);
      expect(c.diameterMaxMm, isNull);
      expect(c.processes, '15 PAW');
      expect(processFamiliesIn(c.processes), {WeldProcessFamily.paw});
      expect(c.notes, contains('D ≥ 500 mm'));
    });

    test('bez spoiwa → grupa materiału z próby, bez FM', () {
      final r = _range(_bw(first: _proc(Iso9606Process.p142, 2), parent: '8.1'));
      final c = iso9606CertificateDraft(r, en: false).certificate!;
      expect(c.materialGroup, '8.1');
      expect(c.filler, '142: bez spoiwa (nm)');
    });
  });
}
