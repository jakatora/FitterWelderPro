// Zakres uprawnień spawacza z parametrów próbki — EN ISO 9606-1:2017.
// Czyste funkcje, bez Fluttera i bez bazy.
//
// Spawacz po egzaminie (albo przed nim) pyta: „na co będę miał uprawnienia
// z tej próbki?”. Moduł przelicza parametry złącza próbnego na ZAKRES
// kwalifikacji wg tabel normy. Uzupełnia kontrolę spoiny względem
// certyfikatu (lib/domain/wps/weld_range_check.dart), która tych tabel nie
// odtwarza — tam wpisuje się gotowy zakres.
//
// __WYDANIE__
// EN ISO 9606-1:2017 = ISO 9606-1:2012 + Cor 1:2012 + Cor 2:2013. Treść
// techniczna tabel przepisana z tekstu ISO 9606-1:2012 z Cor 1:2012
// (BS EN ISO 9606-1:2013, rozdz. 4.2, 5.1–5.9, tab. 1–12). Wg BSI Cor 2:2013
// dotyczy tylko wersji francuskiej — nie zmienia tabel (informacja wtórna,
// niepotwierdzona w tekście Cor 2). Numeracja tabel jak w opublikowanym
// tekście: tab. 7 = średnica, tab. 8 = grubość spoin pachwinowych
// (część arkuszy interpretacyjnych ISO/TC 44 nazywa tablicę pachwinową
// „Table 7” — treść odpowiedzi zgadza się z tab. 8 poniżej).
//
// __ŹRÓDŁA__
//  [N]  ISO 9606-1:2012 + Cor 1:2012 (BS EN ISO 9606-1:2013), tekst normy:
//       §4.2 lista procesów, §5.2 procesy, tab. 1 procesy łączone, §5.3
//       wyrób, §5.4 rodzaj spoiny, tab. 2–3 grupy FM, §5.6 + tab. 4–5 typ
//       spoiwa, §5.7 + tab. 6–8 wymiary, §5.8 + tab. 9–10 pozycje, §5.9 +
//       tab. 11–12 szczegóły spoiny.
//  [I]  Arkusze interpretacyjne ISO/TC 44/SC 11 do ISO 9606-1:2012 + Cor 1
//       + Cor 2 (https://committee.iso.org/sites/tc44/home/interpretation/iso-9606-12012.html):
//       • 2014-04-08 tab. 9: H-L045 obejmuje PH, J-L045 obejmuje PJ —
//         kolumny tabeli to pozycje spawania w PRODUKCJI;
//       • 2012-07-18 tab. 6 przypis f: „s dla każdego procesu” także dla
//         cieńszych próbek wieloprocesowych;
//       • 2015-04-23 tab. 6: 138 s = 3 → 3–6 mm, 136 s = 9 → 3–18 mm;
//         razem w jednym złączu 6 + 18 mm — tak; 24 mm samym 136 — nie;
//         proces grani (bez podkładki) tylko w strefie grani;
//       • 2015-04-23 tab. 8 (w arkuszu „Table 7”): t 1,4 → 1,4–3,0;
//         t 2,9 → 2,9–5,8; blachy 2 + 20 mm → 2–4 i ≥ 3 osobno;
//       • 2015-04-23 §5.4 e: czołowa PE + dodatkowa pachwinowa PB →
//         pachwinowe PA, PB, PC, PD, PE;
//       • 2016-05-18 §5.3 b/c: blacha PA → rury obracane D ≥ 75;
//       • tab. 11: podkładka gazowa tylko 13x/14x/15 (2012-07-18), wkładka
//         topliwa tylko 14x/15 (2012-07-18), podkładka topnikowa 121, 125,
//         13x, 14x, 15 (2015-04-23); „nb” obejmuje też bez gazu (2015).
//  [W]  Weld Australia, „Using AS/NZS ISO 9606-1 with WeldQ” (2019) —
//       zgodne: D > 25 do 50 → ≥ 25, D ≥ 50 → ≥ 0,5D; PH + PC → H-L045:
//       https://awcr.org.au/wp-content/uploads/2017/08/WeldAustralia-Using-AS-NZS-ISO-9606-1-with-WeldQ.pdf
//
// __ROZBIEŻNOŚCI ŹRÓDEŁ__ (wybrano tekst normy, ostrożniej tam, gdzie
// norma milczy):
//  • część stron szkoleniowych podaje dla s ≥ 12 mm „≥ 5 mm” — to reguła
//    dawnej EN 287-1; ISO 9606-1 tab. 6 ma „≥ 3” (wynik pokazuje notkę);
//  • te same strony mieszają tab. 9 (BW) z tab. 10 (FW) i dla s < 3 podają
//    „t do 2t” bez „lub 3, co większe” — tu wiersz z normy;
//  • H-L045 / J-L045 nie mają wiersza w tab. 10 → dla dodatkowej próbki
//    pachwinowej tylko PA, PB (§5.4 e) + notka „sprawdź”.
//
// __BEZPIECZEŃSTWO WYNIKU__
//  • przy niepewności zakres WĘŻSZY, nigdy szerszy;
//  • puste / nieczytelne pole → problem (czego brakuje), nie wynik;
//  • granice dokładnie wg tabel (s = 3, s = 12, D = 25, t = 3);
//  • liczby do wyświetlenia: minimum W GÓRĘ, maksimum W DÓŁ do 0,01 mm;
//  • szkic certyfikatu do rejestru wpisuje tylko to, czego kontrola spoiny
//    nie poszerzy (proces 1 bez procesu 2, bez 142 z próby ze spoiwem;
//    część wspólna BW / FW); czego rejestr nie sprawdza (grań, przenoszenie,
//    blacha / rura, FM, otulina, proces 2…) — obowiązkowy dialog
//    i blok OGRANICZENIA na początku notatki ([iso9606RegisterLimits]).
//
// __ROZSTRZYGNIĘTE Z TEKSTU NORMY__
//  • §5.2 + §5.6: 141 / 143 / 145 obejmują 142, a spawanie ze spoiwem —
//    spawanie bez spoiwa; uwaga do §5.6: dla 142 i 311 bez spoiwa zakresem
//    jest grupa materiału rodzimego z próby → spawanie bez spoiwa objęte
//    tylko na tej grupie (wymagana przy próbie, która je obejmuje);
//  • tab. 6: 311 „s do 1,5s” i „3 do 1,5s” to przypisy c, d wierszy s < 3
//    i 3 ≤ s < 12; wiersz s ≥ 12 ma tylko przypisy e, f → „≥ 3” także 311;
//  • §5.3 c: blacha obejmuje rury obracane D ≥ 75 w PA, PB, PC i PD
//    „zgodnie z tab. 9 i 10” → część wspólna z zakresem pozycji.
//
// ASME IX (QW-451/452, QW-461.9) — świadomie poza modułem.

import 'iso9606_limits.dart';
import 'weld_process.dart';
import 'welder_certificate.dart';

// ─── Słowniki ───────────────────────────────────────────────────────────────

/// Rodzaj wyrobu (§5.3): blacha P albo rura T.
enum Iso9606Product {
  plate('P'),
  pipe('T');

  const Iso9606Product(this.code);
  final String code;
}

/// Rodzaj spoiny (§5.4): czołowa BW albo pachwinowa FW.
enum Iso9606WeldType {
  bw('BW'),
  fw('FW');

  const Iso9606WeldType(this.code);
  final String code;
}

/// Typ spoiwa (§4.3.2, tab. 4 i 5). Otuliny elektrod (111) i rdzenie / druty
/// (pozostałe procesy) to osobne rodziny — tabele się nie przenikają.
enum Iso9606Filler {
  /// Tab. 4: otuliny A, RA, RB, RC, RR, R (03, 13, 14, 19, 20, 24, 27).
  coveringRutile('A, RA, RB, RC, RR, R', '03, 13, 14, 19, 20, 24, 27'),

  /// Tab. 4: otulina zasadowa B (15, 16, 18, 28, 45, 48).
  coveringBasic('B', '15, 16, 18, 28, 45, 48'),

  /// Tab. 4: otulina celulozowa C (10, 11).
  coveringCellulosic('C', '10, 11'),

  /// Tab. 5: drut / pręt lity S.
  solid('S', ''),

  /// Tab. 5: drut / pręt z rdzeniem metalicznym M.
  metalCored('M', ''),

  /// Tab. 5: drut / pręt proszkowy zasadowy B.
  basicCored('B', ''),

  /// Tab. 5: drut / pręt proszkowy R, P, V, W, Y, Z.
  otherCored('R, P, V, W, Y, Z', ''),

  /// Bez spoiwa (nm) — 142, 311 i 15 bez dodatku.
  none('nm', '');

  const Iso9606Filler(this.code, this.isoNumbers);

  /// Oznaczenie wg §4.3.2.
  final String code;

  /// Numery otulin wg ISO 2560 itd. (tylko otuliny).
  final String isoNumbers;

  bool get isCovering =>
      this == coveringRutile || this == coveringBasic || this == coveringCellulosic;

  bool get isCored => this == basicCored || this == otherCored;
}

/// Procesy objęte ISO 9606-1 (§4.2). Inne procesy — poza normą.
enum Iso9606Process {
  p111(111, 'Elektroda otulona (MMA)', 'Manual metal arc (MMA)',
      [Iso9606Filler.coveringRutile, Iso9606Filler.coveringBasic,
        Iso9606Filler.coveringCellulosic]),
  p114(114, 'Samoosłonowy drut proszkowy', 'Self-shielded cored wire',
      [Iso9606Filler.basicCored, Iso9606Filler.otherCored]),
  p121(121, 'Łuk kryty, drut lity', 'Submerged arc, solid wire',
      [Iso9606Filler.solid]),
  p125(125, 'Łuk kryty, drut proszkowy', 'Submerged arc, cored wire',
      [Iso9606Filler.metalCored, Iso9606Filler.basicCored,
        Iso9606Filler.otherCored]),
  p131(131, 'MIG, drut lity', 'MIG, solid wire', [Iso9606Filler.solid]),
  p135(135, 'MAG, drut lity', 'MAG, solid wire', [Iso9606Filler.solid]),
  p136(136, 'MAG, drut proszkowy', 'MAG, flux-cored wire',
      [Iso9606Filler.basicCored, Iso9606Filler.otherCored]),
  p138(138, 'MAG, drut z rdzeniem metalicznym', 'MAG, metal-cored wire',
      [Iso9606Filler.metalCored]),
  p141(141, 'TIG, spoiwo lite', 'TIG, solid filler', [Iso9606Filler.solid]),
  p142(142, 'TIG bez spoiwa', 'Autogenous TIG', [Iso9606Filler.none]),
  p143(143, 'TIG, spoiwo proszkowe', 'TIG, cored filler',
      [Iso9606Filler.metalCored, Iso9606Filler.basicCored,
        Iso9606Filler.otherCored]),
  p145(145, 'TIG z gazem redukującym, spoiwo lite',
      'TIG with reducing gas, solid filler', [Iso9606Filler.solid]),
  p15(15, 'Plazma', 'Plasma arc', [Iso9606Filler.solid, Iso9606Filler.none]),
  p311(311, 'Gazowe acetylenowo-tlenowe', 'Oxyacetylene',
      [Iso9606Filler.solid, Iso9606Filler.none]);

  const Iso9606Process(this.number, this.namePl, this.nameEn, this.fillers);

  /// Numer wg EN ISO 4063.
  final int number;
  final String namePl;
  final String nameEn;

  /// Typy spoiwa, którymi da się spawać tym procesem.
  final List<Iso9606Filler> fillers;

  String get code => '$number';

  /// Zwarciowy rodzaj przenoszenia metalu dotyczy 131, 135 i 138 (§5.2).
  bool get hasTransferMode => this == p131 || this == p135 || this == p138;

  /// 13x (MIG/MAG) i 14x (TIG).
  bool get _is13x => this == p131 || this == p135 || this == p136 || this == p138;
  bool get _is14x => this == p141 || this == p142 || this == p143 || this == p145;
}

/// Rodzaj przenoszenia metalu dla 131 / 135 / 138 (§5.2).
enum Iso9606Transfer {
  /// Zwarciowy (dip, short-circuit) — obejmuje też pozostałe.
  dip,

  /// Natryskowy, pulsujący, kroplowy — NIE obejmuje zwarciowego.
  other,
}

/// Grupy spoiw (tab. 2).
enum Iso9606FmGroup {
  fm1('FM1', 'stale niestopowe i drobnoziarniste',
      'non-alloy and fine grain steels'),
  fm2('FM2', 'stale o wysokiej wytrzymałości', 'high-strength steels'),
  fm3('FM3', 'stale odporne na pełzanie, Cr < 3,75 %',
      'creep-resisting steels, Cr < 3.75 %'),
  fm4('FM4', 'stale odporne na pełzanie, 3,75 ≤ Cr ≤ 12 %',
      'creep-resisting steels, 3.75 ≤ Cr ≤ 12 %'),
  fm5('FM5', 'stale nierdzewne i żaroodporne',
      'stainless and heat-resisting steels'),
  fm6('FM6', 'nikiel i stopy niklu', 'nickel and nickel alloys');

  const Iso9606FmGroup(this.code, this.namePl, this.nameEn);
  final String code;
  final String namePl;
  final String nameEn;
}

/// Pozycje spawania wg ISO 6947 używane w ISO 9606-1.
enum Iso6947Position {
  pa('PA'),
  pb('PB'),
  pc('PC'),
  pd('PD'),
  pe('PE'),
  pf('PF'),
  pg('PG'),
  ph('PH'),
  pj('PJ'),
  hL045('H-L045'),
  jL045('J-L045');

  const Iso6947Position(this.code);
  final String code;
}

/// Prowadzenie grani (tab. 11) — tylko spoiny czołowe.
enum Iso9606Backing {
  /// Jednostronnie bez podkładki.
  ssNb('ss nb'),

  /// Jednostronnie na podkładce (materiałowej).
  ssMb('ss mb'),

  /// Dwustronnie (z podpawaniem / żłobieniem).
  bs('bs'),

  /// Jednostronnie z gazem formującym (13x, 14x, 15).
  ssGb('ss gb'),

  /// Wkładka topliwa (14x, 15).
  ci('ci'),

  /// Podkładka topnikowa (121, 125, 13x, 14x, 15).
  ssFb('ss fb');

  const Iso9606Backing(this.code);
  final String code;

  /// Czy ten sposób w ogóle dotyczy procesu (interpretacje ISO/TC 44 [I]).
  bool appliesTo(Iso9606Process p) => switch (this) {
        ssNb || ssMb || bs => true,
        ssGb => p._is13x || p._is14x || p == Iso9606Process.p15,
        ci => p._is14x || p == Iso9606Process.p15,
        ssFb => p == Iso9606Process.p121 ||
            p == Iso9606Process.p125 ||
            p._is13x ||
            p._is14x ||
            p == Iso9606Process.p15,
      };
}

/// Liczba warstw próbki czołowej (tab. 6 przypis e, tab. 12 przypis b).
enum Iso9606Layers { one, two, threeOrMore }

/// Technika spoiny pachwinowej (tab. 12): jedno- / wielowarstwowa.
enum Iso9606FilletLayers {
  sl('sl'),
  ml('ml');

  const Iso9606FilletLayers(this.code);
  final String code;
}

/// Kierunek spawania gazowego 311 (§5.9): w lewo / w prawo.
enum Iso9606GasDirection {
  leftward('lw'),
  rightward('rw');

  const Iso9606GasDirection(this.code);
  final String code;
}

// ─── Tabele (const, przepisane z [N]) ───────────────────────────────────────

/// Tab. 3 — zakres dla grupy spoiwa.
const Map<Iso9606FmGroup, Set<Iso9606FmGroup>> kIso9606FmRange = {
  Iso9606FmGroup.fm1: {Iso9606FmGroup.fm1, Iso9606FmGroup.fm2},
  Iso9606FmGroup.fm2: {Iso9606FmGroup.fm1, Iso9606FmGroup.fm2},
  Iso9606FmGroup.fm3: {
    Iso9606FmGroup.fm1,
    Iso9606FmGroup.fm2,
    Iso9606FmGroup.fm3,
  },
  Iso9606FmGroup.fm4: {
    Iso9606FmGroup.fm1,
    Iso9606FmGroup.fm2,
    Iso9606FmGroup.fm3,
    Iso9606FmGroup.fm4,
  },
  Iso9606FmGroup.fm5: {Iso9606FmGroup.fm5},
  Iso9606FmGroup.fm6: {Iso9606FmGroup.fm5, Iso9606FmGroup.fm6},
};

/// Tab. 4 (otuliny 111) i tab. 5 (druty / pręty) + §5.6 („ze spoiwem
/// obejmuje bez spoiwa, nie odwrotnie”).
const Map<Iso9606Filler, Set<Iso9606Filler>> kIso9606FillerRange = {
  Iso9606Filler.coveringRutile: {
    Iso9606Filler.coveringRutile,
    Iso9606Filler.none,
  },
  Iso9606Filler.coveringBasic: {
    Iso9606Filler.coveringRutile,
    Iso9606Filler.coveringBasic,
    Iso9606Filler.none,
  },
  Iso9606Filler.coveringCellulosic: {
    Iso9606Filler.coveringCellulosic,
    Iso9606Filler.none,
  },
  Iso9606Filler.solid: {
    Iso9606Filler.solid,
    Iso9606Filler.metalCored,
    Iso9606Filler.none,
  },
  Iso9606Filler.metalCored: {
    Iso9606Filler.solid,
    Iso9606Filler.metalCored,
    Iso9606Filler.none,
  },
  Iso9606Filler.basicCored: {
    Iso9606Filler.basicCored,
    Iso9606Filler.otherCored,
    Iso9606Filler.none,
  },
  Iso9606Filler.otherCored: {Iso9606Filler.otherCored, Iso9606Filler.none},
  Iso9606Filler.none: {Iso9606Filler.none},
};

/// §5.2 — procesy, które obejmuje próba danym procesem (przed filtrem typu
/// spoiwa z tab. 5). 135 ↔ 138, 121 ↔ 125, 141/143/145 → 141, 142, 143,
/// 145; 142 tylko 142; reszta — tylko ten sam proces.
Set<Iso9606Process> iso9606ProcessCandidates(Iso9606Process p) => switch (p) {
      Iso9606Process.p135 ||
      Iso9606Process.p138 =>
        {Iso9606Process.p135, Iso9606Process.p138},
      Iso9606Process.p121 ||
      Iso9606Process.p125 =>
        {Iso9606Process.p121, Iso9606Process.p125},
      Iso9606Process.p141 ||
      Iso9606Process.p143 ||
      Iso9606Process.p145 =>
        {
          Iso9606Process.p141,
          Iso9606Process.p142,
          Iso9606Process.p143,
          Iso9606Process.p145,
        },
      _ => {p},
    };

/// Tab. 9 — pozycje dla spoin CZOŁOWYCH. Kolumny normy: PA, PC, PE, PF, PG.
/// Pozycje rur (PH, PJ, H-L045, J-L045) dokłada [_pipeExtras].
const Map<Iso6947Position, Set<Iso6947Position>> kIso9606ButtPositions = {
  Iso6947Position.pa: {Iso6947Position.pa},
  Iso6947Position.pc: {Iso6947Position.pa, Iso6947Position.pc},
  // PE (blacha)
  Iso6947Position.pe: {
    Iso6947Position.pa,
    Iso6947Position.pc,
    Iso6947Position.pe,
  },
  // PF (blacha)
  Iso6947Position.pf: {Iso6947Position.pa, Iso6947Position.pf},
  // PH (rura)
  Iso6947Position.ph: {
    Iso6947Position.pa,
    Iso6947Position.pe,
    Iso6947Position.pf,
  },
  // PG (blacha)
  Iso6947Position.pg: {Iso6947Position.pg},
  // PJ (rura)
  Iso6947Position.pj: {
    Iso6947Position.pa,
    Iso6947Position.pe,
    Iso6947Position.pg,
  },
  Iso6947Position.hL045: {
    Iso6947Position.pa,
    Iso6947Position.pc,
    Iso6947Position.pe,
    Iso6947Position.pf,
  },
  Iso6947Position.jL045: {
    Iso6947Position.pa,
    Iso6947Position.pc,
    Iso6947Position.pe,
    Iso6947Position.pg,
  },
};

/// Tab. 10 — pozycje dla spoin PACHWINOWYCH. Kolumny: PA, PB, PC, PD, PE, PF,
/// PG. Brak wierszy H-L045 / J-L045.
const Map<Iso6947Position, Set<Iso6947Position>> kIso9606FilletPositions = {
  Iso6947Position.pa: {Iso6947Position.pa},
  Iso6947Position.pb: {Iso6947Position.pa, Iso6947Position.pb},
  Iso6947Position.pc: {
    Iso6947Position.pa,
    Iso6947Position.pb,
    Iso6947Position.pc,
  },
  Iso6947Position.pd: {
    Iso6947Position.pa,
    Iso6947Position.pb,
    Iso6947Position.pc,
    Iso6947Position.pd,
    Iso6947Position.pe,
  },
  // PE (blacha)
  Iso6947Position.pe: {
    Iso6947Position.pa,
    Iso6947Position.pb,
    Iso6947Position.pc,
    Iso6947Position.pd,
    Iso6947Position.pe,
  },
  // PF (blacha)
  Iso6947Position.pf: {
    Iso6947Position.pa,
    Iso6947Position.pb,
    Iso6947Position.pf,
  },
  // PH (rura)
  Iso6947Position.ph: {
    Iso6947Position.pa,
    Iso6947Position.pb,
    Iso6947Position.pc,
    Iso6947Position.pd,
    Iso6947Position.pe,
    Iso6947Position.pf,
  },
  // PG (blacha)
  Iso6947Position.pg: {Iso6947Position.pg},
  // PJ (rura)
  Iso6947Position.pj: {
    Iso6947Position.pa,
    Iso6947Position.pb,
    Iso6947Position.pd,
    Iso6947Position.pe,
    Iso6947Position.pg,
  },
};

/// Tab. 11 — prowadzenie grani (spoiny czołowe).
const Map<Iso9606Backing, Set<Iso9606Backing>> kIso9606BackingRange = {
  Iso9606Backing.ssNb: {
    Iso9606Backing.ssNb,
    Iso9606Backing.ssMb,
    Iso9606Backing.bs,
    Iso9606Backing.ssGb,
    Iso9606Backing.ssFb,
  },
  Iso9606Backing.ssMb: {Iso9606Backing.ssMb, Iso9606Backing.bs},
  Iso9606Backing.bs: {Iso9606Backing.ssMb, Iso9606Backing.bs},
  Iso9606Backing.ssGb: {
    Iso9606Backing.ssMb,
    Iso9606Backing.bs,
    Iso9606Backing.ssGb,
  },
  Iso9606Backing.ci: {
    Iso9606Backing.ssMb,
    Iso9606Backing.bs,
    Iso9606Backing.ci,
  },
  Iso9606Backing.ssFb: {
    Iso9606Backing.ssMb,
    Iso9606Backing.bs,
    Iso9606Backing.ssFb,
  },
};

/// Tab. 12 — technika spoiny pachwinowej.
const Map<Iso9606FilletLayers, Set<Iso9606FilletLayers>> kIso9606LayerRange = {
  Iso9606FilletLayers.sl: {Iso9606FilletLayers.sl},
  Iso9606FilletLayers.ml: {Iso9606FilletLayers.sl, Iso9606FilletLayers.ml},
};

/// Pozycje próby dozwolone dla rodzaju spoiny i wyrobu (wiersze tab. 9 / 10
/// z dopiskiem „blacha” / „rura”; H-L045 i J-L045 to rury z definicji).
List<Iso6947Position> iso9606TestPositions(
    Iso9606WeldType type, Iso9606Product product) {
  const pa = Iso6947Position.pa;
  const pb = Iso6947Position.pb;
  const pc = Iso6947Position.pc;
  const pd = Iso6947Position.pd;
  const pe = Iso6947Position.pe;
  const pf = Iso6947Position.pf;
  const pg = Iso6947Position.pg;
  const ph = Iso6947Position.ph;
  const pj = Iso6947Position.pj;
  if (type == Iso9606WeldType.bw) {
    return product == Iso9606Product.plate
        ? const [pa, pc, pe, pf, pg]
        : const [pa, pc, ph, pj, Iso6947Position.hL045, Iso6947Position.jL045];
  }
  return product == Iso9606Product.plate
      ? const [pa, pb, pc, pd, pe, pf, pg]
      : const [pa, pb, pc, pd, ph, pj];
}

/// Pozycje rur dokładane do wiersza tabeli: pozycja samej próby (PH, PJ,
/// H-L045, J-L045) oraz — wg interpretacji [I] z 2014-04-08 — PH z H-L045
/// i PJ z J-L045.
Set<Iso6947Position> _pipeExtras(Iso6947Position tested) => switch (tested) {
      Iso6947Position.ph => {Iso6947Position.ph},
      Iso6947Position.pj => {Iso6947Position.pj},
      Iso6947Position.hL045 => {Iso6947Position.ph, Iso6947Position.hL045},
      Iso6947Position.jL045 => {Iso6947Position.pj, Iso6947Position.jL045},
      _ => const {},
    };

// ─── Wymiary (tab. 6, 7, 8) ─────────────────────────────────────────────────

/// Zakres w mm; [max] `null` = bez górnej granicy.
class MmRange {
  final double min;
  final double? max;

  const MmRange(this.min, [this.max]);

  bool get isEmpty => max != null && max! < min - 1e-9;

  /// Część wspólna (może być pusta — patrz [isEmpty]).
  MmRange intersect(MmRange o) {
    final lo = min > o.min ? min : o.min;
    final double? hi = max == null
        ? o.max
        : (o.max == null ? max : (max! < o.max! ? max : o.max));
    return MmRange(lo, hi);
  }

  bool contains(double v) =>
      v >= min - 1e-9 && (max == null || v <= max! + 1e-9);

  @override
  bool operator ==(Object other) =>
      other is MmRange &&
      (other.min - min).abs() < 1e-9 &&
      ((other.max == null && max == null) ||
          (other.max != null &&
              max != null &&
              (other.max! - max!).abs() < 1e-9));

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'MmRange($min–${max ?? '∞'})';
}

/// Tab. 6 — zakres grubości stopiwa dla spoin czołowych.
///  • s < 3: s do 3 albo s do 2s — co większe (311: s do 1,5s);
///  • 3 ≤ s < 12: 3 do 2s (311: 3 do 1,5s);
///  • s ≥ 12: ≥ 3 (próbka co najmniej 3-warstwowa — przypis e;
///    sprawdza [evaluateIso9606]).
MmRange iso9606ButtThickness(double s, {bool oxyacetylene = false}) {
  if (s < 3) {
    if (oxyacetylene) return MmRange(s, 1.5 * s);
    return MmRange(s, 2 * s > 3 ? 2 * s : 3);
  }
  if (s < 12) return MmRange(3, (oxyacetylene ? 1.5 : 2) * s);
  return const MmRange(3);
}

/// Tab. 7 — średnica zewnętrzna rury: D ≤ 25 → D do 2D; D > 25 → ≥ 0,5D,
/// nie mniej niż 25 mm.
MmRange iso9606Diameter(double d) {
  if (d <= 25) return MmRange(d, 2 * d);
  final half = 0.5 * d;
  return MmRange(half > 25 ? half : 25);
}

/// Tab. 8 — grubość materiału dla spoin pachwinowych: t < 3 → t do 2t lub 3
/// (co większe); t ≥ 3 → ≥ 3.
MmRange iso9606FilletThickness(double t) {
  if (t < 3) return MmRange(t, 2 * t > 3 ? 2 * t : 3);
  return const MmRange(3);
}

// ─── Wejście ────────────────────────────────────────────────────────────────

/// Jeden proces próbki. Grubość: dla BW grubość stopiwa s tego procesu (przy
/// jednym procesie s = t próbki), dla FW grubość materiału t. `null` =
/// puste pole; NaN / ≤ 0 = nieczytelne.
class Iso9606ProcessInput {
  final Iso9606Process? process;
  final Iso9606Filler? filler;
  final Iso9606Transfer? transfer;
  final double? thicknessMm;

  const Iso9606ProcessInput({
    this.process,
    this.filler,
    this.transfer,
    this.thicknessMm,
  });
}

/// Parametry złącza próbnego.
class Iso9606Sample {
  final Iso9606Product product;
  final Iso9606WeldType weldType;

  /// Proces 1 — przy dwóch procesach: GRAŃ (tab. 1).
  final Iso9606ProcessInput first;

  /// Proces 2 — wypełnienie i lico (tylko BW); `null` = jeden proces.
  final Iso9606ProcessInput? second;

  final Iso9606FmGroup? fm;

  /// Grupa materiału rodzimego wg ISO/TR 15608 — potrzebna przy spawaniu bez
  /// spoiwa (§5.6 uwaga).
  final String parentGroup;

  /// Średnica zewnętrzna rury (tylko T).
  final double? diameterMm;

  final Iso6947Position? position;

  /// Rura BW w PH / PJ + druga rura tej samej średnicy w PC (albo jedna rura
  /// D ≥ 150: 2/3 obwodu PH/PJ + 1/3 PC) — §5.8.
  final bool pcCompanion;

  /// Prowadzenie grani procesu 1 (BW).
  final Iso9606Backing? backing;

  /// Liczba warstw próbki czołowej.
  final Iso9606Layers? layers;

  /// Dodatkowa próbka pachwinowa do spoiny czołowej (§5.4 e).
  final bool supplementaryFillet;

  /// Technika próbki pachwinowej (FW).
  final Iso9606FilletLayers? filletLayers;

  /// Kierunek spawania 311.
  final Iso9606GasDirection? gasDirection;

  const Iso9606Sample({
    this.product = Iso9606Product.plate,
    this.weldType = Iso9606WeldType.bw,
    this.first = const Iso9606ProcessInput(),
    this.second,
    this.fm,
    this.parentGroup = '',
    this.diameterMm,
    this.position,
    this.pcCompanion = false,
    this.backing,
    this.layers,
    this.supplementaryFillet = false,
    this.filletLayers,
    this.gasDirection,
  });

  bool get isPipe => product == Iso9606Product.pipe;
  bool get isButt => weldType == Iso9606WeldType.bw;

  /// Procesy próbki (1 albo 2).
  List<Iso9606ProcessInput> get processes => [
        first,
        if (isButt && second != null) second!,
      ];

  bool get multiProcess => processes.length == 2;
}

// ─── Problemy (czego brakuje) ───────────────────────────────────────────────

enum Iso9606Problem {
  process,
  filler,
  transfer,
  thickness,
  thicknessInvalid,
  process2,
  filler2,
  transfer2,
  thickness2,
  thickness2Invalid,
  sameProcessTwice,
  diameter,
  diameterInvalid,
  wallTooThick,
  position,
  positionNotForSample,
  fm,
  parentGroup,
  parentGroupInvalid,
  backing,
  backingNotForProcess,
  layersNeeded,
  tooFewLayers,
  filletLayers,
  gasDirection,
}

/// Komunikat problemu.
String iso9606ProblemText(Iso9606Problem p, {required bool en}) {
  String t(String pl, String e) => en ? e : pl;
  return switch (p) {
    Iso9606Problem.process => t('Wybierz proces spawania próbki.',
        'Choose the welding process of the test piece.'),
    Iso9606Problem.filler => t('Wybierz typ spoiwa (otulina / drut).',
        'Choose the filler type (covering / wire).'),
    Iso9606Problem.transfer => t(
        'Wybierz rodzaj przenoszenia metalu (zwarciowy albo inny) — §5.2.',
        'Choose the metal transfer mode (dip or other) — cl. 5.2.'),
    Iso9606Problem.thickness => t('Podaj grubość próbki (mm).',
        'Enter the test piece thickness (mm).'),
    Iso9606Problem.thicknessInvalid => t(
        'Grubość próbki: wpisz liczbę większą od 0.',
        'Test piece thickness: enter a number greater than 0.'),
    Iso9606Problem.process2 => t('Wybierz drugi proces (wypełnienie).',
        'Choose the second process (fill).'),
    Iso9606Problem.filler2 => t('Wybierz typ spoiwa drugiego procesu.',
        'Choose the filler type of the second process.'),
    Iso9606Problem.transfer2 => t(
        'Wybierz rodzaj przenoszenia metalu drugiego procesu — §5.2.',
        'Choose the metal transfer mode of the second process — cl. 5.2.'),
    Iso9606Problem.thickness2 => t(
        'Podaj grubość stopiwa s₂ drugiego procesu (mm).',
        'Enter the deposited thickness s₂ of the second process (mm).'),
    Iso9606Problem.thickness2Invalid => t(
        'Grubość stopiwa s₂: wpisz liczbę większą od 0.',
        'Deposited thickness s₂: enter a number greater than 0.'),
    Iso9606Problem.sameProcessTwice => t(
        'Oba procesy i spoiwa są takie same — to próbka jednym procesem: '
            'wyłącz drugi proces i wpisz całą grubość.',
        'Both processes and fillers are the same — this is a single-process '
            'test piece: switch off the second process and enter the total '
            'thickness.'),
    Iso9606Problem.diameter => t('Podaj średnicę zewnętrzną rury D (mm).',
        'Enter the pipe outside diameter D (mm).'),
    Iso9606Problem.diameterInvalid => t(
        'Średnica D: wpisz liczbę większą od 0.',
        'Diameter D: enter a number greater than 0.'),
    Iso9606Problem.wallTooThick => t(
        'Grubość większa niż połowa średnicy — sprawdź t / s i D.',
        'Thickness exceeds half the diameter — check t / s and D.'),
    Iso9606Problem.position => t('Wybierz pozycję spawania próbki.',
        'Choose the welding position of the test piece.'),
    Iso9606Problem.positionNotForSample => t(
        'Ta pozycja nie występuje w tabeli normy dla tej próbki (tab. 9 / 10).',
        'This position is not in the standard table for this test piece '
            '(Table 9 / 10).'),
    Iso9606Problem.fm => t('Wybierz grupę spoiwa FM (tab. 2).',
        'Choose the filler material group FM (Table 2).'),
    Iso9606Problem.parentGroup => t(
        'Podaj grupę materiału rodzimego próby (ISO/TR 15608, np. 1.1 albo '
            '8.1) — spawanie bez spoiwa (142, 311 / 15 bez spoiwa) jest '
            'objęte tylko na tej grupie (§5.6 uwaga).',
        'Enter the parent material group of the test piece (ISO/TR 15608, '
            'e.g. 1.1 or 8.1) — welding without filler (142, 311 / 15 '
            'without filler) is covered only on that group (cl. 5.6 note).'),
    Iso9606Problem.parentGroupInvalid => t(
        'Grupa materiału: format ISO/TR 15608, np. 1, 1.1, 8.1, 11.',
        'Parent material group: ISO/TR 15608 format, e.g. 1, 1.1, 8.1, 11.'),
    Iso9606Problem.backing => t(
        'Wybierz prowadzenie grani (ss nb, ss mb, bs…) — tab. 11.',
        'Choose the root condition (ss nb, ss mb, bs…) — Table 11.'),
    Iso9606Problem.backingNotForProcess => t(
        'Ten sposób prowadzenia grani nie dotyczy wybranego procesu (tab. 11).',
        'This root condition does not apply to the chosen process (Table 11).'),
    Iso9606Problem.layersNeeded => t(
        'Podaj liczbę warstw próbki czołowej (tab. 6 przypis e, tab. 12 '
            'przypis b).',
        'Enter the number of layers of the butt test piece (Table 6 note e, '
            'Table 12 note b).'),
    Iso9606Problem.tooFewLayers => t(
        'Próbka s ≥ 12 mm musi mieć co najmniej 3 warstwy (tab. 6 przypis e) '
            '— z mniejszej liczby norma nie daje zakresu „≥ 3 mm”. Zakres '
            'ustala egzaminator.',
        'A test piece with s ≥ 12 mm must have at least 3 layers (Table 6 '
            'note e) — with fewer the standard gives no "≥ 3 mm" range. Ask '
            'the examiner.'),
    Iso9606Problem.filletLayers => t(
        'Wybierz technikę spoiny pachwinowej: jedno- (sl) czy wielowarstwowa '
            '(ml) — tab. 12.',
        'Choose the fillet weld technique: single layer (sl) or multi-layer '
            '(ml) — Table 12.'),
    Iso9606Problem.gasDirection => t(
        'Dla 311 wybierz kierunek spawania: w lewo (lw) albo w prawo (rw) — '
            '§5.9.',
        'For 311 choose the welding direction: leftward (lw) or rightward '
            '(rw) — cl. 5.9.'),
  };
}

// ─── Wynik ──────────────────────────────────────────────────────────────────

/// Zakres jednego procesu próbki.
class Iso9606ProcessRange {
  final Iso9606Process tested;
  final Iso9606Filler filler;
  final Iso9606Transfer? transfer;

  /// Grubość z próby (s tego procesu albo t dla FW).
  final double thicknessMm;

  /// Objęte procesy z typami spoiwa (§5.2 ∩ tab. 4/5 ∩ spoiwa procesu).
  final Map<Iso9606Process, List<Iso9606Filler>> processes;

  /// Zakres grubości samym tym procesem (tab. 6 / tab. 8).
  final MmRange thickness;

  /// Prowadzenie grani (BW) — tab. 11, tylko sposoby dotyczące procesu.
  final List<Iso9606Backing> backings;

  /// Proces grani w próbce wieloprocesowej (tab. 1).
  final bool root;

  const Iso9606ProcessRange({
    required this.tested,
    required this.filler,
    required this.transfer,
    required this.thicknessMm,
    required this.processes,
    required this.thickness,
    required this.backings,
    required this.root,
  });
}

/// Uwaga do wyniku. [check] = „sprawdź w normie / u egzaminatora”.
class Iso9606Note {
  final String pl;
  final String en;
  final bool check;

  const Iso9606Note(this.pl, this.en, {this.check = false});

  String text({required bool en}) => en ? this.en : pl;
}

/// Zakres uprawnień z próbki.
class Iso9606Range {
  final Iso9606Sample sample;
  final List<Iso9606ProcessRange> processes;

  /// Złącze wieloprocesowe (tab. 1, s = s₁ + s₂, ograniczone sumą zakresów
  /// procesów — interpretacja [I] 2015-04-23); `null` przy jednym procesie.
  final MmRange? jointThickness;

  /// Zakres spoin czołowych (BW) albo pachwinowych z próby FW.
  final MmRange thickness;

  /// Średnica (tylko próba na rurze).
  final MmRange? diameter;

  /// Pozycje dla rodzaju spoiny próby (kolejność ISO 6947).
  final List<Iso6947Position> positions;

  /// Spoiny pachwinowe z dodatkowej próbki (§5.4 e) — `null`, gdy brak.
  final MmRange? filletThickness;
  final List<Iso6947Position>? filletPositions;

  /// Technika spoin pachwinowych (tab. 12) — dla FW i dodatkowej próbki.
  final List<Iso9606FilletLayers>? filletLayers;

  final List<Iso9606FmGroup> fmGroups;

  /// Grupa materiału rodzimego przy spawaniu bez spoiwa.
  final String? parentGroup;

  final List<Iso9606WeldType> weldTypes;

  /// Rury obracane z próby na blasze (§5.3 c): pozycje z zakresu ∩ {PA, PB,
  /// PC, PD}; `null` dla próby na rurze.
  final List<Iso6947Position>? rotatingPipePositions;

  final List<Iso9606Note> notes;

  const Iso9606Range({
    required this.sample,
    required this.processes,
    required this.jointThickness,
    required this.thickness,
    required this.diameter,
    required this.positions,
    required this.filletThickness,
    required this.filletPositions,
    required this.filletLayers,
    required this.fmGroups,
    required this.parentGroup,
    required this.weldTypes,
    required this.rotatingPipePositions,
    required this.notes,
  });

  /// Próba na rurze D > 25 obejmuje blachy (§5.3 a); próba na blasze —
  /// blachy.
  bool get coversPlates =>
      !sample.isPipe || (sample.diameterMm != null && sample.diameterMm! > 25);
}

/// Wynik oceny: problemy (czego brakuje) albo zakres.
class Iso9606Evaluation {
  final List<Iso9606Problem> problems;
  final Iso9606Range? range;

  const Iso9606Evaluation._(this.problems, this.range);

  bool get ok => range != null;
}

final RegExp _kParentGroup = RegExp(r'^\d{1,2}(\.\d{1,2})?$');

/// Czy proces próbki (z wybranym, pasującym spoiwem) obejmuje spawanie BEZ
/// spoiwa: próba bez spoiwa (142, 311 / 15 „nm”) albo ze spoiwem, gdy §5.2
/// obejmuje proces bez spoiwa (141 / 143 / 145 → 142) lub sam proces może
/// spawać bez spoiwa (311, 15) — §5.6: „ze spoiwem obejmuje bez spoiwa”.
bool _coversNoFiller(Iso9606ProcessInput p) {
  final proc = p.process;
  final f = p.filler;
  if (proc == null || f == null || !proc.fillers.contains(f)) return false;
  if (!kIso9606FillerRange[f]!.contains(Iso9606Filler.none)) return false;
  return iso9606ProcessCandidates(proc)
      .any((c) => c.fillers.contains(Iso9606Filler.none));
}

/// Czy potrzebna grupa materiału rodzimego próby (ISO/TR 15608).
///
/// EN ISO 9606-1 §5.6 UWAGA: „dla procesów 142 i 311 (bez spoiwa) grupa
/// materiału rodzimego użyta w próbie jest grupą, na którą spawacz ma
/// uprawnienie”. §5.2: 141 / 143 / 145 obejmują 142; §5.6: spawanie ze
/// spoiwem obejmuje spawanie bez spoiwa. Uwaga nie zastrzega, że dotyczy
/// tylko próby bez spoiwa — więc spawanie bez spoiwa (142, 311 / 15 „nm”)
/// objęte z próby ze spoiwem też liczymy tylko na grupie z próby, a bez
/// podanej grupy nie ma wyniku (nie zgadujemy szerzej).
bool iso9606NeedsParentGroup(Iso9606Sample s) =>
    s.processes.any(_coversNoFiller);

bool _bad(double? v) => v != null && (!v.isFinite || v <= 0 || v >= 1000);

List<T> _ordered<T extends Enum>(Iterable<T> items, List<T> order) =>
    [for (final o in order) if (items.contains(o)) o];

/// Przelicza próbkę na zakres uprawnień. Każde puste albo nieczytelne pole
/// to [Iso9606Problem] — wtedy bez zakresu.
Iso9606Evaluation evaluateIso9606(Iso9606Sample s) {
  final problems = <Iso9606Problem>[];

  void checkProcess(
    Iso9606ProcessInput p, {
    required Iso9606Problem noProcess,
    required Iso9606Problem noFiller,
    required Iso9606Problem noTransfer,
    required Iso9606Problem noThickness,
    required Iso9606Problem badThickness,
  }) {
    final proc = p.process;
    if (proc == null) {
      problems.add(noProcess);
    } else {
      final f = p.filler;
      if (f == null || !proc.fillers.contains(f)) problems.add(noFiller);
      if (proc.hasTransferMode && p.transfer == null) problems.add(noTransfer);
    }
    if (p.thicknessMm == null) {
      problems.add(noThickness);
    } else if (_bad(p.thicknessMm)) {
      problems.add(badThickness);
    }
  }

  checkProcess(
    s.first,
    noProcess: Iso9606Problem.process,
    noFiller: Iso9606Problem.filler,
    noTransfer: Iso9606Problem.transfer,
    noThickness: Iso9606Problem.thickness,
    badThickness: Iso9606Problem.thicknessInvalid,
  );
  final second = s.isButt ? s.second : null;
  if (second != null) {
    checkProcess(
      second,
      noProcess: Iso9606Problem.process2,
      noFiller: Iso9606Problem.filler2,
      noTransfer: Iso9606Problem.transfer2,
      noThickness: Iso9606Problem.thickness2,
      badThickness: Iso9606Problem.thickness2Invalid,
    );
    if (second.process != null &&
        second.process == s.first.process &&
        second.filler == s.first.filler) {
      problems.add(Iso9606Problem.sameProcessTwice);
    }
  }

  // Średnica i ścianka.
  final d = s.diameterMm;
  if (s.isPipe) {
    if (d == null) {
      problems.add(Iso9606Problem.diameter);
    } else if (_bad(d) || d >= 10000) {
      problems.add(Iso9606Problem.diameterInvalid);
    } else {
      final total = [
        for (final p in s.processes)
          if (p.thicknessMm != null && !_bad(p.thicknessMm)) p.thicknessMm!,
      ].fold<double>(0, (a, b) => a + b);
      if (total > d / 2 + 1e-9) problems.add(Iso9606Problem.wallTooThick);
    }
  }

  // Pozycja.
  final pos = s.position;
  if (pos == null) {
    problems.add(Iso9606Problem.position);
  } else if (!iso9606TestPositions(s.weldType, s.product).contains(pos)) {
    problems.add(Iso9606Problem.positionNotForSample);
  }

  // Spoiwo: FM, chyba że wszystkie procesy są bez spoiwa (także zanim
  // wybrano spoiwo — od razu widać, czego brakuje); grupa materiału, gdy
  // próba obejmuje spawanie bez spoiwa (§5.6 uwaga — patrz
  // [iso9606NeedsParentGroup]).
  final fillers = [for (final p in s.processes) p.filler];
  final allNone = fillers.every((f) => f == Iso9606Filler.none);
  if (!allNone && s.fm == null) problems.add(Iso9606Problem.fm);
  final parent = s.parentGroup.trim();
  if (iso9606NeedsParentGroup(s)) {
    if (parent.isEmpty) {
      problems.add(Iso9606Problem.parentGroup);
    } else if (!_kParentGroup.hasMatch(parent)) {
      problems.add(Iso9606Problem.parentGroupInvalid);
    }
  }

  // Szczegóły spoiny.
  if (s.isButt) {
    final b = s.backing;
    final p1 = s.first.process;
    if (b == null) {
      problems.add(Iso9606Problem.backing);
    } else if (p1 != null && !b.appliesTo(p1)) {
      problems.add(Iso9606Problem.backingNotForProcess);
    }
    // s ≥ 12 (dla każdego procesu osobno — przypis f) → min. 3 warstwy
    // (przypis e). Dodatkowa próbka pachwinowa → liczba warstw decyduje
    // o sl / ml (tab. 12 przypis b).
    final thick = s.processes.any((p) =>
        p.thicknessMm != null && !_bad(p.thicknessMm) && p.thicknessMm! >= 12);
    if (thick) {
      if (s.layers == null) {
        problems.add(Iso9606Problem.layersNeeded);
      } else if (s.layers != Iso9606Layers.threeOrMore) {
        problems.add(Iso9606Problem.tooFewLayers);
      }
    } else if (s.supplementaryFillet && s.layers == null) {
      problems.add(Iso9606Problem.layersNeeded);
    }
  } else if (s.filletLayers == null) {
    problems.add(Iso9606Problem.filletLayers);
  }
  final uses311 = s.processes.any((p) => p.process == Iso9606Process.p311);
  if (uses311 && s.gasDirection == null) {
    problems.add(Iso9606Problem.gasDirection);
  }

  if (problems.isNotEmpty) return Iso9606Evaluation._(problems, null);
  return Iso9606Evaluation._(const [], _compute(s));
}

Iso9606ProcessRange _processRange(
  Iso9606ProcessInput p, {
  required Iso9606Sample sample,
  required bool root,
  required bool fill,
}) {
  final tested = p.process!;
  final filler = p.filler!;
  final qualifiedFillers = kIso9606FillerRange[filler]!;
  final processes = <Iso9606Process, List<Iso9606Filler>>{};
  for (final candidate in Iso9606Process.values) {
    if (!iso9606ProcessCandidates(tested).contains(candidate)) continue;
    final types = [
      for (final f in candidate.fillers)
        if (qualifiedFillers.contains(f)) f,
    ];
    if (types.isNotEmpty) processes[candidate] = types;
  }
  final t = p.thicknessMm!;
  final thickness = sample.isButt
      ? iso9606ButtThickness(t,
          oxyacetylene: tested == Iso9606Process.p311)
      : iso9606FilletThickness(t);
  final backings = <Iso9606Backing>[];
  if (sample.isButt) {
    // Proces wypełnienia w złączu wieloprocesowym spawa na grani — jak na
    // podkładce (tab. 1: „ss mb”).
    final condition = fill ? Iso9606Backing.ssMb : sample.backing!;
    for (final b in Iso9606Backing.values) {
      if (kIso9606BackingRange[condition]!.contains(b) && b.appliesTo(tested)) {
        backings.add(b);
      }
    }
  }
  return Iso9606ProcessRange(
    tested: tested,
    filler: filler,
    transfer: tested.hasTransferMode ? p.transfer : null,
    thicknessMm: t,
    processes: processes,
    thickness: thickness,
    backings: backings,
    root: root,
  );
}

Iso9606Range _compute(Iso9606Sample s) {
  final notes = <Iso9606Note>[];
  final multi = s.multiProcess;
  final ranges = [
    _processRange(s.first, sample: s, root: multi, fill: false),
    if (multi) _processRange(s.second!, sample: s, root: false, fill: true),
  ];

  // ---- Grubość.
  MmRange? joint;
  late MmRange thickness;
  if (multi) {
    final s1 = ranges[0].thicknessMm;
    final s2 = ranges[1].thicknessMm;
    final total = s1 + s2;
    final table = iso9606ButtThickness(total,
        oxyacetylene: ranges.any((r) => r.tested == Iso9606Process.p311));
    final m1 = ranges[0].thickness.max;
    final m2 = ranges[1].thickness.max;
    // Każdy proces w swoim zakresie — razem nie więcej niż suma maksimów
    // ([I] 2015-04-23: 6 + 18 mm tak, 24 mm samym jednym procesem nie).
    final cap = (m1 == null || m2 == null) ? null : m1 + m2;
    final double? hi = table.max == null
        ? cap
        : (cap == null ? table.max : (table.max! < cap ? table.max : cap));
    joint = MmRange(table.min, hi);
    thickness = joint;
    notes.add(const Iso9606Note(
      'Złącze dwoma procesami (tab. 1): proces 1 tylko w strefie grani, '
          'każdy proces w swoim zakresie grubości stopiwa; łącznie nie '
          'więcej niż suma zakresów (interpretacja ISO/TC 44/SC 11, '
          '2015-04-23). Proces 2 sam — tylko na podkładce / grani (ss mb, bs).',
      'Two-process joint (Table 1): process 1 only in the root area, each '
          'process within its own deposited-thickness range; in total no '
          'more than the sum of the ranges (ISO/TC 44/SC 11 interpretation, '
          '2015-04-23). Process 2 alone — only on backing / root (ss mb, bs).',
    ));
  } else {
    thickness = ranges.single.thickness;
  }
  if (s.isButt &&
      s.processes.any((p) => p.thicknessMm! >= 12)) {
    notes.add(const Iso9606Note(
      's ≥ 12 mm → zakres ≥ 3 mm wg ISO 9606-1:2012 tab. 6 (próbka '
          'co najmniej 3-warstwowa). Dawna EN 287-1 dawała ≥ 5 mm i część '
          'materiałów szkoleniowych nadal tak podaje — wiążący jest '
          'certyfikat.',
      's ≥ 12 mm → range ≥ 3 mm per ISO 9606-1:2012 Table 6 (test piece of '
          'at least 3 layers). The old EN 287-1 gave ≥ 5 mm and some '
          'training material still says so — the certificate is binding.',
      check: true,
    ));
  }
  if (s.isButt &&
      s.processes.any((p) =>
          p.process == Iso9606Process.p311 && p.thicknessMm! >= 12)) {
    notes.add(const Iso9606Note(
      '311: tab. 6 ogranicza zakres do 1,5·s tylko przypisami c i d '
          '(wiersze s < 12). Wiersz s ≥ 12 ma tylko przypisy e, f — „≥ 3 mm” '
          'także dla 311.',
      '311: Table 6 limits the range to 1.5·s only by notes c and d (rows '
          's < 12). The s ≥ 12 row has only notes e, f — "≥ 3 mm" for 311 '
          'too.',
    ));
  }

  // ---- Średnica i wyrób.
  MmRange? diameter;
  List<Iso6947Position>? rotating;
  if (s.isPipe) {
    diameter = iso9606Diameter(s.diameterMm!);
    if (s.diameterMm! <= 25) {
      notes.add(const Iso9606Note(
        'Rura D ≤ 25 mm NIE obejmuje blach (§5.3 a). Rejestr uprawnień nie '
            'rozróżnia blach i rur — pilnuj tego sam.',
        'A pipe with D ≤ 25 mm does NOT cover plates (cl. 5.3 a). The '
            'qualification register does not tell plates from pipes — watch '
            'it yourself.',
      ));
    }
    if (!s.isButt) {
      notes.add(const Iso9606Note(
        'Średnica dla spoin pachwinowych liczona ostrożnie wg tab. 7 '
            '(§5.4 e odsyła do tab. 7 także dla pachwinowych).',
        'Diameter for fillet welds taken conservatively from Table 7 '
            '(cl. 5.4 e refers to Table 7 for fillet welds too).',
      ));
    }
  }

  // ---- Pozycje.
  final pos = s.position!;
  final tested = <Iso6947Position>{pos};
  final companion = s.isButt &&
      s.isPipe &&
      s.pcCompanion &&
      (pos == Iso6947Position.ph || pos == Iso6947Position.pj);
  final positions = <Iso6947Position>{};
  if (s.isButt) {
    if (companion) {
      // §5.8: PH + PC → zakres H-L045; PJ + PC → zakres J-L045.
      final inclined = pos == Iso6947Position.ph
          ? Iso6947Position.hL045
          : Iso6947Position.jL045;
      tested.add(Iso6947Position.pc);
      positions
        ..addAll(kIso9606ButtPositions[inclined]!)
        ..addAll(_pipeExtras(inclined))
        ..addAll(kIso9606ButtPositions[Iso6947Position.pc]!)
        ..addAll(kIso9606ButtPositions[pos]!)
        ..addAll(_pipeExtras(pos));
      notes.add(Iso9606Note(
        'Dwie rury tej samej średnicy: ${pos.code} + PC (albo D ≥ 150 mm: '
            '2/3 obwodu ${pos.code} + 1/3 PC) dają zakres ${inclined.code} '
            '(§5.8).',
        'Two pipes of the same diameter: ${pos.code} + PC (or D ≥ 150 mm: '
            '2/3 of the circumference ${pos.code} + 1/3 PC) give the '
            '${inclined.code} range (cl. 5.8).',
      ));
    } else {
      positions
        ..addAll(kIso9606ButtPositions[pos]!)
        ..addAll(_pipeExtras(pos));
    }
    if (pos == Iso6947Position.hL045 || pos == Iso6947Position.jL045 || companion) {
      notes.add(const Iso9606Note(
        'H-L045 obejmuje PH, J-L045 obejmuje PJ — kolumny tab. 9 to pozycje '
            'w produkcji (interpretacja ISO/TC 44/SC 11, 2014-04-08).',
        'H-L045 covers PH, J-L045 covers PJ — the columns of Table 9 are '
            'production positions (ISO/TC 44/SC 11 interpretation, '
            '2014-04-08).',
      ));
    }
  } else {
    positions
      ..addAll(kIso9606FilletPositions[pos]!)
      ..addAll(_pipeExtras(pos));
  }
  final orderedPositions = _ordered(positions, Iso6947Position.values);

  // ---- Spoiny pachwinowe z dodatkowej próbki (§5.4 e).
  MmRange? filletThickness;
  List<Iso6947Position>? filletPositions;
  List<Iso9606FilletLayers>? filletLayers;
  if (s.isButt && s.supplementaryFillet) {
    final total = s.processes.fold<double>(0, (a, p) => a + p.thicknessMm!);
    filletThickness = iso9606FilletThickness(total);
    final fp = <Iso6947Position>{Iso6947Position.pa, Iso6947Position.pb};
    var rowMissing = false;
    for (final t in tested) {
      final row = kIso9606FilletPositions[t];
      if (row == null) {
        rowMissing = true;
      } else {
        fp
          ..addAll(row)
          ..addAll(_pipeExtras(t));
      }
    }
    filletPositions = _ordered(fp, Iso6947Position.values);
    // Tab. 12 przypis b: wielowarstwowa czołowa + dodatkowa → sl i ml;
    // inaczej — jak sama próbka dodatkowa (jedna warstwa).
    filletLayers = s.layers == Iso9606Layers.one
        ? const [Iso9606FilletLayers.sl]
        : const [Iso9606FilletLayers.sl, Iso9606FilletLayers.ml];
    notes.add(const Iso9606Note(
      'Dodatkowa próbka pachwinowa (§5.4 e): min. 10 mm (albo grubość próbki '
          'czołowej, jeśli cieńsza), jedna warstwa w PB, każdym procesem, '
          'grupą FM i typem otuliny / rdzenia z próby. Pozycje pachwinowe '
          'wg tab. 10 dla pozycji próby czołowej + PA, PB (interpretacja '
          'ISO/TC 44/SC 11, 2015-04-23).',
      'Supplementary fillet test piece (cl. 5.4 e): min. 10 mm (or the butt '
          'test piece thickness if thinner), single layer in PB, with each '
          'process, FM group and covering / core type of the test. Fillet '
          'positions per Table 10 for the butt test position + PA, PB '
          '(ISO/TC 44/SC 11 interpretation, 2015-04-23).',
    ));
    if (rowMissing) {
      notes.add(const Iso9606Note(
        'Tab. 10 nie ma wiersza H-L045 / J-L045 — dla spoin pachwinowych '
            'przyjęto tylko PA, PB (§5.4 e). Szerszy zakres potwierdź '
            'u egzaminatora.',
        'Table 10 has no H-L045 / J-L045 row — for fillet welds only PA, PB '
            'are taken (cl. 5.4 e). Confirm a wider range with the examiner.',
        check: true,
      ));
    }
  } else if (!s.isButt) {
    filletLayers = _ordered(
        kIso9606LayerRange[s.filletLayers!]!, Iso9606FilletLayers.values);
  }

  if (!s.isPipe) {
    final rot = {
      for (final p in [...orderedPositions, ...?filletPositions])
        if (p == Iso6947Position.pa ||
            p == Iso6947Position.pb ||
            p == Iso6947Position.pc ||
            p == Iso6947Position.pd)
          p,
    };
    rotating = _ordered(rot, Iso6947Position.values);
  }

  // ---- Rodzaje spoin.
  final weldTypes = s.isButt
      ? [
          Iso9606WeldType.bw,
          if (s.supplementaryFillet) Iso9606WeldType.fw,
        ]
      : const [Iso9606WeldType.fw];
  if (s.isButt && !s.supplementaryFillet) {
    notes.add(const Iso9606Note(
      'Spoina czołowa NIE obejmuje pachwinowych (§5.4 b) — chyba że '
          'z dodatkową próbką pachwinową (§5.4 e).',
      'A butt weld does NOT cover fillet welds (cl. 5.4 b) — unless with a '
          'supplementary fillet test piece (cl. 5.4 e).',
    ));
  }
  if (!s.isButt) {
    notes.add(const Iso9606Note(
      'Spoina pachwinowa NIE obejmuje czołowych (§5.4 b). Przy blachach '
          'różnej grubości zakres liczy się dla każdej osobno (interpretacja '
          'ISO/TC 44/SC 11, 2015-04-23) — tu z jednej wpisanej t.',
      'A fillet weld does NOT cover butt welds (cl. 5.4 b). With plates of '
          'different thickness each gets its own range (ISO/TC 44/SC 11 '
          'interpretation, 2015-04-23) — here from the one t entered.',
    ));
  }
  if (s.isButt && s.isPipe) {
    notes.add(const Iso9606Note(
      'Czołowa na rurze obejmuje też odgałęzienia pod kątem ≥ 60° — zakres '
          'wg średnicy odgałęzienia (§5.4 c).',
      'A butt weld on pipe also covers branch joints at ≥ 60° — range based '
          'on the branch outside diameter (cl. 5.4 c).',
    ));
  }

  // ---- Spoiwo i materiał.
  final withFiller = s.processes.any((p) => p.filler != Iso9606Filler.none);
  final fms = s.fm == null || !withFiller
      ? const <Iso9606FmGroup>[]
      : _ordered(kIso9606FmRange[s.fm!]!, Iso9606FmGroup.values);
  final needsParent = iso9606NeedsParentGroup(s);
  final parent = needsParent ? s.parentGroup.trim() : null;
  if (needsParent && withFiller) {
    final noFiller = <String>{
      for (final r in ranges)
        for (final e in r.processes.entries)
          if (e.value.contains(Iso9606Filler.none)) e.key.code,
    }.join(', ');
    notes.add(Iso9606Note(
      'Spawanie bez spoiwa ($noFiller) — objęte (§5.2, §5.6), ale tylko na '
          'grupie materiału z próby: $parent (§5.6 uwaga).',
      'Welding without filler ($noFiller) — covered (cl. 5.2, 5.6), but only '
          'on the parent material group of the test: $parent (cl. 5.6 note).',
    ));
  }
  if (fms.isNotEmpty) {
    notes.add(const Iso9606Note(
      'Spoiwem z objętych grup FM — na materiałach rodzimych grup 1–11 '
          'wg ISO/TR 15608 (§5.5.2).',
      'With fillers of the covered FM groups — on parent materials of '
          'groups 1–11 per ISO/TR 15608 (cl. 5.5.2).',
    ));
  }
  // Grań spawa proces 1 (przy jednym procesie — jedyny).
  final rootFiller = ranges.first.filler;
  if (s.isButt &&
      s.backing == Iso9606Backing.ssNb &&
      (rootFiller.isCovering || rootFiller.isCored)) {
    notes.add(const Iso9606Note(
      'Grań bez podkładki (ss nb) w produkcji — tylko tym typem otuliny / '
          'rdzenia, którym spawano grań próby (tab. 4 i 5, przypis b).',
      'Root without backing (ss nb) in production — only with the covering / '
          'core type used for the root of the test (Tables 4 and 5, note b).',
    ));
  }
  if (ranges.any((r) => r.transfer == Iso9606Transfer.other)) {
    notes.add(const Iso9606Note(
      'Próba bez zwarciowego przenoszenia metalu NIE obejmuje zwarciowego '
          '(§5.2).',
      'A test without dip (short-circuit) transfer does NOT cover dip '
          'transfer (cl. 5.2).',
    ));
  }
  if (!s.isPipe) {
    notes.add(const Iso9606Note(
      'Blacha obejmuje rury nieruchome D ≥ 500 mm (§5.3 b) i obracane '
          'D ≥ 75 mm w PA, PB, PC, PD (§5.3 c) — w pozycjach z zakresu.',
      'Plate covers fixed pipes D ≥ 500 mm (cl. 5.3 b) and rotating pipes '
          'D ≥ 75 mm in PA, PB, PC, PD (cl. 5.3 c) — in the positions of the '
          'range.',
    ));
  }

  return Iso9606Range(
    sample: s,
    processes: ranges,
    jointThickness: joint,
    thickness: thickness,
    diameter: diameter,
    positions: orderedPositions,
    filletThickness: filletThickness,
    filletPositions: filletPositions,
    filletLayers: filletLayers,
    fmGroups: fms,
    parentGroup: parent,
    weldTypes: weldTypes,
    rotatingPipePositions: rotating,
    notes: notes,
  );
}

// ─── Tekst: liczby, linie wyniku, udostępnianie ─────────────────────────────

/// Dolna granica do wyświetlenia i zapisu — W GÓRĘ do 0,01 mm (nigdy niższa
/// niż wyliczona; 0,5 × 60,33 = 30,165 → 30,17).
double iso9606RoundMin(double v) => (v * 100 - 1e-6).ceilToDouble() / 100;

/// Górna granica do wyświetlenia i zapisu — W DÓŁ do 0,01 mm (nigdy wyższa).
double iso9606RoundMax(double v) => (v * 100 + 1e-6).floorToDouble() / 100;

/// Liczba mm: do 2 miejsc, bez zbędnych zer; przecinek po polsku.
String iso9606Mm(double v, {required bool en}) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return en ? s : s.replaceAll('.', ',');
}

/// „3–24 mm”, „≥ 30,15 mm” — granice zaokrąglone na bezpieczną stronę.
String iso9606RangeText(MmRange r, {required bool en}) {
  final lo = iso9606Mm(iso9606RoundMin(r.min), en: en);
  if (r.max == null) return '≥ $lo mm';
  return '$lo–${iso9606Mm(iso9606RoundMax(r.max!), en: en)} mm';
}

String _positionsText(List<Iso6947Position> p) =>
    p.map((e) => e.code).join(', ');

String _fillerText(Iso9606Filler f, {required bool en}) {
  if (f == Iso9606Filler.none) return en ? 'no filler (nm)' : 'bez spoiwa (nm)';
  return f.code;
}

/// Typy spoiwa objęte dla procesu próbki — tylko te, którymi da się spawać
/// którymś z objętych procesów (111 nie spawa „bez spoiwa”).
List<Iso9606Filler> iso9606QualifiedFillers(Iso9606ProcessRange p) {
  final used = {for (final l in p.processes.values) ...l};
  return _ordered(used, Iso9606Filler.values);
}

/// Jedna pozycja wyniku: klucz (do testów i UI), etykieta, wartość, punkt
/// normy.
class Iso9606Line {
  final String key;
  final String label;
  final String value;
  final String clause;

  const Iso9606Line(this.key, this.label, this.value, this.clause);
}

/// Linie wyniku — te same na ekranie, w tekście do udostępnienia i w PDF.
List<Iso9606Line> iso9606Lines(Iso9606Range r, {required bool en}) {
  final s = r.sample;
  final multi = r.processes.length > 1;
  final lines = <Iso9606Line>[];
  String t(String pl, String e) => en ? e : pl;

  /// Dopisek procesu przy dwóch procesach: „ — 141 (grań)”.
  String suffix(int i, Iso9606ProcessRange p) {
    if (!multi) return '';
    return i == 0
        ? t(' — ${p.tested.code} (grań)', ' — ${p.tested.code} (root)')
        : t(' — ${p.tested.code} (wypełnienie)', ' — ${p.tested.code} (fill)');
  }

  // Procesy i przenoszenie metalu.
  for (final (i, p) in r.processes.indexed) {
    lines.add(Iso9606Line(
      'process-$i',
      t('Procesy', 'Processes') + suffix(i, p),
      p.processes.entries
          .map((e) =>
              '${e.key.code} (${e.value.map((f) => f.code).join(' / ')})')
          .join(', '),
      t('§5.2, tab. 5', 'cl. 5.2, Table 5'),
    ));
    if (p.transfer != null) {
      lines.add(Iso9606Line(
        'transfer-$i',
        t('Przenoszenie metalu', 'Metal transfer') + suffix(i, p),
        p.transfer == Iso9606Transfer.dip
            ? t('wszystkie rodzaje (próba zwarciowa)',
                'all modes (dip transfer test)')
            : t('wszystkie oprócz zwarciowego',
                'all except dip (short-circuit)'),
        t('§5.2', 'cl. 5.2'),
      ));
    }
  }

  // Wyrób.
  final product = <String>[];
  if (s.isPipe) {
    product.add(t('rury (T) w zakresie średnic',
        'pipes (T) within the diameter range'));
    product.add(r.coversPlates
        ? t('blachy (P)', 'plates (P)')
        : t('blachy — NIE (D ≤ 25 mm)', 'plates — NO (D ≤ 25 mm)'));
  } else {
    product.add(t('blachy (P)', 'plates (P)'));
    product.add(t('rury nieruchome D ≥ 500 mm', 'fixed pipes D ≥ 500 mm'));
    final rot = r.rotatingPipePositions ?? const <Iso6947Position>[];
    if (rot.isNotEmpty) {
      product.add(t('rury obracane D ≥ 75 mm (${_positionsText(rot)})',
          'rotating pipes D ≥ 75 mm (${_positionsText(rot)})'));
    }
  }
  lines.add(Iso9606Line(
      'product', t('Wyrób', 'Product type'), product.join('; '),
      t('§5.3', 'cl. 5.3')));

  // Rodzaj spoiny.
  lines.add(Iso9606Line(
    'weld-type',
    t('Rodzaj spoiny', 'Type of weld'),
    r.weldTypes
        .map((w) => w == Iso9606WeldType.bw
            ? t('BW — czołowe', 'BW — butt')
            : t('FW — pachwinowe', 'FW — fillet'))
        .join(', '),
    t('§5.4', 'cl. 5.4'),
  ));

  // Spoiwo i materiał rodzimy.
  if (r.fmGroups.isNotEmpty) {
    lines.add(Iso9606Line(
      'fm',
      t('Grupy spoiw', 'Filler material groups'),
      r.fmGroups.map((g) => g.code).join(', '),
      t('§5.5, tab. 3', 'cl. 5.5, Table 3'),
    ));
  }
  if (r.fmGroups.isNotEmpty) {
    lines.add(Iso9606Line(
      'parent-filler',
      t('Materiał rodzimy (ze spoiwem)', 'Parent material (with filler)'),
      t('grupy 1–11 (ISO/TR 15608)', 'groups 1–11 (ISO/TR 15608)'),
      t('§5.5.2', 'cl. 5.5.2'),
    ));
  }
  if (r.parentGroup != null) {
    lines.add(Iso9606Line(
      'parent',
      t('Materiał rodzimy (bez spoiwa)', 'Parent material (no filler)'),
      t('tylko grupa ${r.parentGroup} (ISO/TR 15608)',
          'group ${r.parentGroup} only (ISO/TR 15608)'),
      t('§5.6 uwaga', 'cl. 5.6 note'),
    ));
  }
  for (final (i, p) in r.processes.indexed) {
    final covering = p.filler.isCovering;
    lines.add(Iso9606Line(
      'filler-$i',
      t('Typ spoiwa', 'Filler type') + suffix(i, p),
      iso9606QualifiedFillers(p).map((f) => _fillerText(f, en: en)).join(', '),
      covering ? t('§5.6, tab. 4', 'cl. 5.6, Table 4') : t('§5.6, tab. 5', 'cl. 5.6, Table 5'),
    ));
  }

  // Grubość.
  if (s.isButt) {
    if (!multi) {
      lines.add(Iso9606Line(
        'thickness',
        t('Grubość stopiwa s (BW)', 'Deposited thickness s (BW)'),
        iso9606RangeText(r.thickness, en: en),
        t('§5.7, tab. 6', 'cl. 5.7, Table 6'),
      ));
    } else {
      for (final (i, p) in r.processes.indexed) {
        lines.add(Iso9606Line(
          'thickness-$i',
          t('Grubość stopiwa s${i == 0 ? '₁' : '₂'} — sam ${p.tested.code}',
              'Deposited thickness s${i == 0 ? '₁' : '₂'} — ${p.tested.code} alone'),
          iso9606RangeText(p.thickness, en: en),
          t('tab. 1, tab. 6', 'Tables 1, 6'),
        ));
      }
      lines.add(Iso9606Line(
        'thickness',
        t('Grubość złącza s₁ + s₂', 'Joint thickness s₁ + s₂'),
        iso9606RangeText(r.jointThickness!, en: en),
        t('tab. 1, tab. 6', 'Tables 1, 6'),
      ));
    }
  } else {
    lines.add(Iso9606Line(
      'thickness',
      t('Grubość materiału t (FW)', 'Material thickness t (FW)'),
      iso9606RangeText(r.thickness, en: en),
      t('§5.7, tab. 8', 'cl. 5.7, Table 8'),
    ));
  }
  if (r.filletThickness != null) {
    lines.add(Iso9606Line(
      'fillet-thickness',
      t('Grubość materiału t (FW)', 'Material thickness t (FW)'),
      iso9606RangeText(r.filletThickness!, en: en),
      t('§5.4 e, tab. 8', 'cl. 5.4 e, Table 8'),
    ));
  }

  // Średnica.
  if (r.diameter != null) {
    lines.add(Iso9606Line(
      'diameter',
      t('Średnica zewnętrzna D', 'Outside diameter D'),
      iso9606RangeText(r.diameter!, en: en),
      t('§5.7, tab. 7', 'cl. 5.7, Table 7'),
    ));
  }

  // Pozycje.
  lines.add(Iso9606Line(
    'positions',
    s.isButt ? t('Pozycje (BW)', 'Positions (BW)') : t('Pozycje (FW)', 'Positions (FW)'),
    _positionsText(r.positions),
    s.isButt ? t('§5.8, tab. 9', 'cl. 5.8, Table 9') : t('§5.8, tab. 10', 'cl. 5.8, Table 10'),
  ));
  if (r.filletPositions != null) {
    lines.add(Iso9606Line(
      'fillet-positions',
      t('Pozycje (FW)', 'Positions (FW)'),
      _positionsText(r.filletPositions!),
      t('§5.4 e, tab. 10', 'cl. 5.4 e, Table 10'),
    ));
  }

  // Szczegóły spoiny.
  if (s.isButt) {
    for (final (i, p) in r.processes.indexed) {
      lines.add(Iso9606Line(
        'backing-$i',
        t('Prowadzenie grani', 'Root / backing') + suffix(i, p),
        p.backings.map((b) => b.code).join(', '),
        t('§5.9, tab. 11', 'cl. 5.9, Table 11'),
      ));
    }
  }
  if (r.filletLayers != null) {
    lines.add(Iso9606Line(
      'layers',
      t('Technika spoin pachwinowych', 'Fillet weld technique'),
      r.filletLayers!.map((l) => l.code).join(', '),
      t('§5.9, tab. 12', 'cl. 5.9, Table 12'),
    ));
  }
  final gas = s.gasDirection;
  if (gas != null && s.processes.any((p) => p.process == Iso9606Process.p311)) {
    lines.add(Iso9606Line(
      'direction',
      t('Kierunek spawania 311', 'Welding direction 311'),
      t('tylko ${gas.code}', '${gas.code} only'),
      t('§5.9', 'cl. 5.9'),
    ));
  }
  return lines;
}

/// Oznaczenie próbki wg rozdz. 11 normy, np.
/// „EN ISO 9606-1 141 T BW FM1 S s3 D60,3 PH ss nb”.
String iso9606Designation(Iso9606Sample s, {required bool en}) {
  final procs = s.processes;
  String mm(double? v) => v == null ? '?' : iso9606Mm(v, en: en);
  final withFiller =
      procs.any((p) => p.filler != null && p.filler != Iso9606Filler.none);
  final companion = s.isButt &&
      s.isPipe &&
      s.pcCompanion &&
      (s.position == Iso6947Position.ph || s.position == Iso6947Position.pj);
  final parts = <String>[
    'EN ISO 9606-1',
    procs.map((p) => p.process?.code ?? '?').join('/'),
    s.product.code,
    s.weldType.code,
    if (withFiller)
      s.fm?.code ?? '?'
    else
      (s.parentGroup.trim().isEmpty ? '?' : s.parentGroup.trim()),
    procs.map((p) => p.filler?.code ?? '?').join('/'),
    s.isButt
        ? procs.map((p) => 's${mm(p.thicknessMm)}').join('/')
        : 't${mm(s.first.thicknessMm)}',
    if (s.isPipe) 'D${mm(s.diameterMm)}',
    '${s.position?.code ?? '?'}${companion ? '+PC' : ''}',
    if (s.isButt) s.backing?.code ?? '?' else s.filletLayers?.code ?? '?',
    if (s.gasDirection != null &&
        procs.any((p) => p.process == Iso9606Process.p311))
      s.gasDirection!.code,
  ];
  return parts.join(' ');
}

/// Zastrzeżenie pod wynikiem.
String iso9606Disclaimer({required bool en}) => en
    ? 'Aid only, per the EN ISO 9606-1:2017 tables. The certificate issued by '
        'the examiner / examining body is binding.'
    : 'Pomoc wg tabel EN ISO 9606-1:2017. Wiążący jest certyfikat wydany '
        'przez egzaminatora / jednostkę egzaminującą.';

/// Tytuł (temat udostępnienia, nagłówek PDF).
String iso9606Title({required bool en}) => en
    ? 'Range of qualification from a test piece'
    : 'Zakres uprawnień z próbki';

/// Tekst do udostępnienia — te same linie co na ekranie.
String iso9606ShareText(Iso9606Range r, {required bool en}) {
  final b = StringBuffer()
    ..writeln('${iso9606Title(en: en)} — EN ISO 9606-1:2017')
    ..writeln('${en ? 'Test piece' : 'Próbka'}: '
        '${iso9606Designation(r.sample, en: en)}')
    ..writeln()
    ..writeln(en ? 'Range of qualification:' : 'Zakres uprawnienia:');
  for (final l in iso9606Lines(r, en: en)) {
    b.writeln('• ${l.label}: ${l.value} [${l.clause}]');
  }
  if (r.notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Notes:' : 'Uwagi:');
    for (final n in r.notes) {
      final mark = n.check ? (en ? '[check] ' : '[sprawdź] ') : '';
      b.writeln('• $mark${n.text(en: en)}');
    }
  }
  b
    ..writeln()
    ..write(iso9606Disclaimer(en: en));
  return b.toString();
}

// ─── Szkic certyfikatu do rejestru ──────────────────────────────────────────
//
// Rejestr uprawnień (WelderCertificate + kontrola spoiny w
// lib/domain/wps/weld_range_check.dart) sprawdza tylko: proces (numery ISO
// 4063), grupę materiałową (dosłownie), jeden zakres grubości, jeden zakres
// średnic, pozycje i BW/FW. NIE zna: prowadzenia grani (tab. 11), rodzaju
// przenoszenia metalu, blachy vs rury (spoina na blasze nie ma średnicy),
// grup FM i typu otuliny / rdzenia, techniki sl / ml, kierunku 311,
// odgałęzień ani złącza dwuprocesowego. Dlatego:
//  • do rejestru idzie tylko to, co nie POSZERZA kontroli — proces 1 (grań
//    albo jedyny) z kandydatami §5.2; proces 2 złącza dwuprocesowego NIE
//    (sam jest objęty tylko na grani / podkładce, a rejestr przepuściłby go
//    także w grani bez podkładki); 142 z próby ze spoiwem NIE (tylko na
//    grupie materiału z próby, a rejestr przy spoiwie grupy nie sprawdza);
//  • reszta to OGRANICZENIA — obowiązkowy dialog przed zapisem, wyraźny
//    blok na początku notatki certyfikatu ([iso9606RegisterLimits]) i pod
//    nim linia dla programu `[ISO9606 v1] …` ([iso9606TestLimits],
//    format w iso9606_limits.dart): kontrola spoiny porównuje z nią
//    prowadzenie grani, przenoszenie metalu, blachę / rurę, grupę FM
//    i odgałęzienia — tylko gdy spoina ma te dane.

/// Dlaczego szkicu nie da się zapisać do rejestru (jeden zakres na
/// certyfikat).
enum Iso9606DraftProblem {
  /// Zakresy grubości BW i FW nie mają części wspólnej.
  thicknessNoOverlap,

  /// Pozycje BW i FW nie mają części wspólnej.
  positionsNoOverlap,
}

String iso9606DraftProblemText(Iso9606DraftProblem p, {required bool en}) =>
    switch (p) {
      Iso9606DraftProblem.thicknessNoOverlap => en
          ? 'The butt and fillet thickness ranges do not overlap — the '
              'register keeps one range per certificate. Save the butt test '
              'without the supplementary fillet test.'
          : 'Zakresy grubości spoin czołowych i pachwinowych się nie '
              'pokrywają — rejestr trzyma jeden zakres na certyfikat. Zapisz '
              'próbkę czołową bez dodatkowej pachwinowej.',
      Iso9606DraftProblem.positionsNoOverlap => en
          ? 'The BW and FW positions do not overlap — save the butt test '
              'without the supplementary fillet test.'
          : 'Pozycje BW i FW się nie pokrywają — zapisz próbkę czołową bez '
              'dodatkowej pachwinowej.',
    };

/// Procesy wpisywane do rejestru: proces 1 próbki (grań albo jedyny) z
/// kandydatami §5.2 — bez procesów objętych WYŁĄCZNIE bez spoiwa, gdy próbę
/// spawano ze spoiwem (142 z próby 141: tylko na grupie materiału z próby,
/// której rejestr przy spoiwie nie sprawdza). Proces 2 złącza
/// dwuprocesowego — nigdy (patrz komentarz sekcji).
List<Iso9606Process> iso9606RegisterProcesses(Iso9606Range r) {
  final first = r.processes.first;
  final testNoFiller = first.filler == Iso9606Filler.none;
  return [
    for (final p in Iso9606Process.values)
      if (first.processes.containsKey(p) &&
          (testNoFiller ||
              first.processes[p]!.any((f) => f != Iso9606Filler.none)))
        p,
  ];
}

String _list(Iterable<String> items) => items.join(', ');

/// Ograniczenia tej próbki, których kontrola spoiny z rejestru NIE sprawdza.
/// Pokazywane w obowiązkowym dialogu przed zapisem i na początku notatki
/// certyfikatu. Kolejność: od tego, co najczęściej przepuściłaby kontrola.
List<Iso9606Note> iso9606RegisterLimits(Iso9606Range r) {
  final s = r.sample;
  final first = r.processes.first;
  final register = iso9606RegisterProcesses(r);
  final out = <Iso9606Note>[];

  // Prowadzenie grani (tab. 11) — rejestr nie wie, czy spoina ma podkładkę.
  if (s.isButt) {
    final applicable = [
      for (final b in Iso9606Backing.values)
        if (b.appliesTo(first.tested)) b,
    ];
    final missing = [
      for (final b in applicable)
        if (!first.backings.contains(b)) b.code,
    ];
    if (missing.isNotEmpty) {
      final ok = _list(first.backings.map((b) => b.code));
      out.add(Iso9606Note(
        'grań: tylko $ok (NIE ${_list(missing)}) — tab. 11',
        'root: only $ok (NOT ${_list(missing)}) — Table 11',
      ));
    }
    if (s.backing == Iso9606Backing.ssNb &&
        (first.filler.isCovering || first.filler.isCored)) {
      out.add(Iso9606Note(
        'grań bez podkładki (ss nb) tylko tym typem otuliny / rdzenia, '
            'którym spawano grań próby (${first.filler.code}) — tab. 4 / 5, '
            'przypis b',
        'root without backing (ss nb) only with the covering / core type '
            'used for the test root (${first.filler.code}) — Tables 4 / 5, '
            'note b',
      ));
    }
  }

  // Przenoszenie metalu (§5.2).
  if (first.transfer == Iso9606Transfer.other) {
    out.add(const Iso9606Note(
      'NIE zwarciowe przenoszenie metalu (dip) — próba bez zwarciowego, §5.2',
      'NOT dip (short-circuit) transfer — test without dip, cl. 5.2',
    ));
  }

  // Wyrób (§5.3 a) — spoina na blasze nie ma średnicy, więc rejestr jej nie
  // zatrzyma.
  if (s.isPipe && !r.coversPlates) {
    out.add(Iso9606Note(
      'tylko rury D ${iso9606RangeText(r.diameter!, en: false)} (NIE '
          'blachy) — §5.3 a',
      'pipes only D ${iso9606RangeText(r.diameter!, en: true)} (NOT plates) '
          '— cl. 5.3 a',
    ));
  }

  // Złącze dwuprocesowe (tab. 1).
  if (r.processes.length > 1) {
    final p1 = first.tested.code;
    final second = r.processes[1];
    final p2 = second.tested.code;
    out.add(Iso9606Note(
      '$p2: tylko jako wypełnienie na grani $p1 (złącze s₁ + s₂ '
          '${iso9606RangeText(r.jointThickness!, en: false)}, $p1 tylko '
          'w grani) albo sam na podkładce / dwustronnie (ss mb, bs; '
          '${iso9606RangeText(second.thickness, en: false)}) — NIE wpisany '
          'do procesów rejestru; spoiny $p1 + $p2 kontrola oznaczy jako '
          'proces spoza zakresu — tab. 1',
      '$p2: only as fill on a $p1 root (joint s₁ + s₂ '
          '${iso9606RangeText(r.jointThickness!, en: true)}, $p1 in the root '
          'only) or alone on backing / both sides (ss mb, bs; '
          '${iso9606RangeText(second.thickness, en: true)}) — NOT entered '
          'in the register processes; the check will flag $p1 + $p2 welds '
          'as out of range — Table 1',
    ));
  }

  // Grupy FM i materiał rodzimy (§5.5).
  if (r.fmGroups.isNotEmpty) {
    final fm = _list(r.fmGroups.map((g) => g.code));
    out.add(Iso9606Note(
      'spoiwo tylko z grup $fm (tab. 3), materiał rodzimy grup 1–11 '
          'ISO/TR 15608 (§5.5.2)',
      'filler only from groups $fm (Table 3), parent material of groups '
          '1–11 ISO/TR 15608 (cl. 5.5.2)',
    ));
  }

  // Typ otuliny / rdzenia (tab. 4 / 5).
  for (final p in register) {
    final types = first.processes[p]!;
    final excluded = [
      for (final f in p.fillers)
        if (!types.contains(f)) f,
    ];
    if (excluded.isEmpty) continue;
    String names(List<Iso9606Filler> l, bool en) => l
        .map((f) => f == Iso9606Filler.none
            ? (en ? 'no filler' : 'bez spoiwa')
            : f.code)
        .join(', ');
    out.add(Iso9606Note(
      '${p.code}: tylko ${names(types, false)} (NIE ${names(excluded, false)}) '
          '— ${types.first.isCovering ? 'tab. 4' : 'tab. 5'}',
      '${p.code}: only ${names(types, true)} (NOT ${names(excluded, true)}) '
          '— ${types.first.isCovering ? 'Table 4' : 'Table 5'}',
    ));
  }

  // Spawanie bez spoiwa — tylko grupa materiału z próby (§5.6 uwaga).
  if (r.parentGroup != null && first.filler != Iso9606Filler.none) {
    final g = r.parentGroup!;
    final noFiller = [
      for (final e in first.processes.entries)
        if (e.value.contains(Iso9606Filler.none)) e.key,
    ];
    final left = [
      for (final p in noFiller)
        if (!register.contains(p)) p.code,
    ];
    final kept = [
      for (final p in noFiller)
        if (register.contains(p)) p.code,
    ];
    if (left.isNotEmpty) {
      out.add(Iso9606Note(
        '${_list(left)} (bez spoiwa): tylko na grupie $g — NIE wpisany do '
            'procesów rejestru (rejestr nie sprawdzi grupy) — §5.6 uwaga',
        '${_list(left)} (no filler): only on group $g — NOT entered in the '
            'register processes (the register cannot check the group) — '
            'cl. 5.6 note',
      ));
    }
    if (kept.isNotEmpty) {
      out.add(Iso9606Note(
        '${_list(kept)} bez spoiwa: tylko na grupie $g — §5.6 uwaga',
        '${_list(kept)} without filler: only on group $g — cl. 5.6 note',
      ));
    }
  }

  // Odgałęzienia (§5.4 a, c).
  if (s.isButt) {
    out.add(s.isPipe
        ? const Iso9606Note(
            'odgałęzienia tylko pod kątem ≥ 60°, zakres wg średnicy '
                'odgałęzienia — §5.4 c',
            'branch joints only at ≥ 60°, range by the branch outside '
                'diameter — cl. 5.4 c',
          )
        : const Iso9606Note(
            'NIE odgałęzienia (tylko z próby czołowej na rurze) — §5.4 a, c',
            'NOT branch joints (only from a butt test on pipe) — cl. 5.4 a, '
                'c',
          ));
  }

  // Technika spoin pachwinowych (tab. 12).
  final layers = r.filletLayers;
  if (layers != null && !layers.contains(Iso9606FilletLayers.ml)) {
    out.add(const Iso9606Note(
      'spoiny pachwinowe tylko jednowarstwowe (sl), NIE wielowarstwowe (ml) '
          '— tab. 12',
      'fillet welds single layer only (sl), NOT multi-layer (ml) — Table 12',
    ));
  }

  // Kierunek spawania 311 (§5.9).
  final gas = s.gasDirection;
  if (gas != null && register.contains(Iso9606Process.p311)) {
    final other = gas == Iso9606GasDirection.leftward
        ? Iso9606GasDirection.rightward
        : Iso9606GasDirection.leftward;
    out.add(Iso9606Note(
      '311: tylko ${gas.code} (NIE ${other.code}) — §5.9',
      '311: ${gas.code} only (NOT ${other.code}) — cl. 5.9',
    ));
  }
  return out;
}

/// Nagłówek bloku ograniczeń w notatce certyfikatu.
String iso9606LimitsHeader({required bool en}) => en
    ? 'LIMITATIONS from the test — the weld check enforces them only when the '
        'weld has the data:'
    : 'OGRANICZENIA z próby — kontrola spoiny sprawdza je tylko, gdy spoina '
        'ma te dane:';

RootCondition _rootOf(Iso9606Backing b) => switch (b) {
      Iso9606Backing.ssNb => RootCondition.nb,
      Iso9606Backing.ssMb => RootCondition.mb,
      Iso9606Backing.bs => RootCondition.bs,
      Iso9606Backing.ssGb => RootCondition.gb,
      Iso9606Backing.ci => RootCondition.ci,
      Iso9606Backing.ssFb => RootCondition.fb,
    };

/// Ograniczenia z próby do linii `[ISO9606 v1]` w uwagach certyfikatu —
/// czyta je kontrola spoiny (weld_range_check.dart). Dotyczą procesu 1 (to
/// on jest w procesach rejestru).
Iso9606Limits iso9606TestLimits(Iso9606Range r) {
  final s = r.sample;
  final first = r.processes.first;
  final register = iso9606RegisterProcesses(r);
  return Iso9606Limits(
    root: s.isButt ? {for (final b in first.backings) _rootOf(b)} : null,
    dip: first.tested.hasTransferMode
        ? first.transfer == Iso9606Transfer.dip
        : null,
    plates: r.coversPlates,
    fm: r.fmGroups.isEmpty ? null : {for (final g in r.fmGroups) g.code},
    noFillerGroup: r.parentGroup,
    proc2: [
      for (final p in r.processes.skip(1)) p.tested.code,
    ],
    branch: s.isButt ? (s.isPipe ? 60 : 0) : null,
    layers: r.filletLayers == null
        ? null
        : {for (final l in r.filletLayers!) l.code},
    direction: s.gasDirection != null && register.contains(Iso9606Process.p311)
        ? s.gasDirection!.code
        : null,
  );
}

/// Szkic certyfikatu do rejestru albo powód, dla którego się nie da.
class Iso9606Draft {
  final WelderCertificate? certificate;
  final Iso9606DraftProblem? problem;

  /// Ograniczenia, których rejestr nie sprawdza — do obowiązkowego dialogu
  /// przed zapisem; te same stoją na początku notatki [certificate].
  final List<Iso9606Note> limits;

  const Iso9606Draft._(this.certificate, this.problem, this.limits);
}

/// Szkic certyfikatu. Do pól, które sprawdza kontrola spoiny, idzie tylko to,
/// czego nie da się poszerzyć: procesy z [iso9606RegisterProcesses], grubość
/// procesu 1 (część wspólna z FW przy dodatkowej próbce), pozycje (część
/// wspólna BW i FW), średnica z tab. 7 albo — przy próbie na blasze — tylko
/// rury D ≥ 500 mm (rejestr nie rozróżnia rur obracanych). Grupa
/// materiałowa: grupa z próby przy spawaniu bez spoiwa, pusta przy spoiwie
/// (FM obejmują grupy 1–11, rejestr porównuje grupy dosłownie — FM idą do
/// pola „spoiwo” i do ograniczeń). Notatka zaczyna się blokiem
/// OGRANICZENIA ([iso9606RegisterLimits]), potem pełny zakres.
Iso9606Draft iso9606CertificateDraft(Iso9606Range r, {required bool en}) {
  final s = r.sample;
  final first = r.processes.first;
  final limits = iso9606RegisterLimits(r);
  var thickness = first.thickness;
  var positions = r.positions;
  if (r.filletThickness != null) {
    thickness = thickness.intersect(r.filletThickness!);
    positions = [
      for (final p in positions)
        if (r.filletPositions!.contains(p)) p,
    ];
    if (positions.isEmpty) {
      return Iso9606Draft._(
          null, Iso9606DraftProblem.positionsNoOverlap, limits);
    }
  }
  final tMin = iso9606RoundMin(thickness.min);
  final tMax =
      thickness.max == null ? null : iso9606RoundMax(thickness.max!);
  if (tMax != null && tMax < tMin) {
    return Iso9606Draft._(null, Iso9606DraftProblem.thicknessNoOverlap, limits);
  }
  final double dMin;
  double? dMax;
  if (r.diameter != null) {
    dMin = iso9606RoundMin(r.diameter!.min);
    dMax = r.diameter!.max == null ? null : iso9606RoundMax(r.diameter!.max!);
  } else {
    dMin = 500;
  }
  final register = iso9606RegisterProcesses(r);
  // „15” nie jest trzycyfrowym numerem ISO 4063 — „PAW” pozwala rejestrowi
  // rozpoznać rodzinę procesu.
  final processText = _list(register
      .map((p) => p == Iso9606Process.p15 ? '15 PAW' : p.code));
  final fillerParts = <String>[
    if (r.fmGroups.isNotEmpty) _list(r.fmGroups.map((g) => g.code)),
    for (final p in register)
      '${p.code}: ${_list(first.processes[p]!.map((f) => _fillerText(f, en: en)))}',
  ];
  final notes = StringBuffer()..writeln(iso9606LimitsHeader(en: en));
  for (final l in limits) {
    notes.writeln('• ${l.text(en: en)}');
  }
  // Ta sama treść dla programu — kontrola spoiny (weld_range_check.dart).
  notes
    ..writeln(iso9606TestLimits(r).encode())
    ..writeln()
    ..writeln(en
        ? 'Range from the test piece (Fitter Welder Pro, EN ISO 9606-1:2017) '
            '— check against the certificate.'
        : 'Zakres z próbki (Fitter Welder Pro, EN ISO 9606-1:2017) — sprawdź '
            'z certyfikatem.')
    ..writeln(iso9606Designation(s, en: en));
  for (final l in iso9606Lines(r, en: en)) {
    notes.writeln('${l.label}: ${l.value} [${l.clause}]');
  }
  if (r.processes.length > 1) {
    notes.writeln(en
        ? 'Register: processes and thickness of process 1 '
            '(${first.tested.code}) only.'
        : 'Rejestr: procesy i grubość tylko procesu 1 '
            '(${first.tested.code}).');
  }
  if (r.filletThickness != null) {
    notes.writeln(en
        ? 'Register: thickness / positions as the common part of BW and FW '
            '(one range per certificate).'
        : 'Rejestr: grubość / pozycje jako część wspólna BW i FW (jeden '
            'zakres na certyfikat).');
  }
  if (r.diameter == null) {
    notes.writeln(en
        ? 'Register: pipes only D ≥ 500 mm (rotating D ≥ 75 mm in PA, PB, PC, '
            'PD — cl. 5.3 c — not stored).'
        : 'Rejestr: rury tylko D ≥ 500 mm (obracane D ≥ 75 mm w PA, PB, PC, '
            'PD — §5.3 c — nie zapisano).');
  }
  final certificate = WelderCertificate(
    id: '',
    standard: QualificationStandard.iso9606_1,
    processes: processText,
    materialGroup:
        first.filler == Iso9606Filler.none ? (r.parentGroup ?? '') : '',
    thicknessMinMm: tMin,
    thicknessMaxMm: tMax,
    diameterMinMm: dMin,
    diameterMaxMm: dMax,
    positions: _positionsText(positions),
    filler: fillerParts.join(' · '),
    jointKinds: {
      for (final w in r.weldTypes)
        w == Iso9606WeldType.bw ? WeldJointKind.bw : WeldJointKind.fw,
    },
    notes: notes.toString().trim(),
    createdAt: 0,
    updatedAt: 0,
  );
  return Iso9606Draft._(certificate, null, limits);
}
