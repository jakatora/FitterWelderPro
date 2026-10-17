// Filtr przyłbicy: stopień zaciemnienia (numer skali) dla procesu i prądu.
// Czyste funkcje i tabele, bez Fluttera.
//
// Dwa źródła obok siebie — europejskie EN 169 i amerykańskie ANSI Z49.1 /
// OSHA. Gdy się różnią, ekran pokazuje oba, a „bezpiecznie” bierze CIEMNIEJ:
// zacznij od wyższego stopnia i rozjaśniaj do dobrej widoczności, ale nie
// poniżej minimum (zalecenie OSHA 1910.133(a)(5), przypis *).
//
// __ŹRÓDŁA__
//  [EN]   EN 169:2002 „Ochrona indywidualna oczu — Filtry spawalnicze
//         i filtry do technik pokrewnych” — wykres zalecanych numerów skali
//         dla spawania łukowego, żłobienia i cięcia plazmowego. Norma
//         wycofana 30.05.2022 (zastąpiona przez EN ISO 16321-1:2022
//         i -2:2021 — online.standard.no), a ISO 4850:1979 w 2021 r.
//         (ISO 16321-2). Tekst płatny; wykres odczytany z dwóch niezależnych
//         przedruków (zgodnych co do komórki poza jedną granicą — MAG, niżej):
//    [D1] DGUV Regel 112-192 „Benutzung von Augen- und Gesichtsschutz”,
//         Anhang 2, „Schweißerschutzfilter beim Lichtbogenschweißen”
//         (obraz z siatką) — granice pasków na kresce wartości prądu,
//         https://vorschriften.bgn-branchenwissen.de/daten/dguv/112_192/anh2_2.htm
//    [D2] DGUV Information 209-010 „Lichtbogenschweißen” (marzec 2017),
//         tabela 3 „aus DIN EN 169 wiedergegeben”, s. 23 — granice odczytane
//         z wektorowych linii podziału tabeli,
//         https://publikationen.dguv.de/widgets/pdf/download/article/318
//         Przypis tabeli: „metale ciężkie” = stale, stale stopowe, miedź
//         i jej stopy itd.
//  [ENG]  EN 169 — spawanie gazowe (przepływ acetylenu, l/h) i cięcie tlenowe
//         (przepływ tlenu, l/h): ulotka RS Components (gogle spawalnicze,
//         tabele i uwagi „następny wyższy lub niższy numer”),
//         https://static.chipdip.ru/lib/508/DOC027508612.pdf ; ta sama tabela
//         acetylenu w DGUV Regel 112-192 zał. 2 p. 1, która dla cięcia
//         tlenowego dopisuje „über 8000 l/h — Schutzstufe 8” (sprawdzone
//         w tekście strony 2026-10-18),
//         https://vorschriften.bgn-branchenwissen.de/daten/dguv/112_192/anh2_1.htm
//  [OSHA] 29 CFR 1910.133(a)(5) — „Filter Lenses for Protection Against
//         Radiant Energy”, minimalne stopnie (Minimum Protective Shade),
//         https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.133
//  [ANSI] ANSI Z49.1:2005 / AWS F2.2 — stopnie zalecane („suggested”),
//         za OSHA Fact Sheet FS-3499 (1/2012) „Eye Protection against Radiant
//         Energy during Welding and Cutting in Shipyard Employment”,
//         https://www.osha.gov/Publications/OSHAfactsheet-eyeprotection-during-welding.pdf
//         i UNL EHS „Lens Shade Selector Guide” (AWS F2.2),
//         https://ehs.unl.edu/sites/unl.edu.business-and-finance.university-operations.ehs/files/media/file/s-welding_lens_and_ppe.pdf
//
// __GRANICE PRZEDZIAŁÓW__
//  • Wykres EN 169 nie mówi, do którego paska należy wartość na kresce, a
//    [OSHA] pisze „60-160” i „160-250” (160 w obu). Zasada: NA GRANICY
//    WYŻSZY STOPIEŃ ([ShadeBoundary.higherShade]). FS-3499 przypisuje 160 A
//    do niższego przedziału („more than 160-250”) — tu celowo ciemniej.
//  • Tabele gazowe EN 169 definiują granice jawnie („q ≤ 70”, „70 < q ≤ 200”,
//    „900 ≤ q ≤ 2000”) — stosujemy je dosłownie
//    ([ShadeBoundary.upperInclusive]): wartość na granicy należy do
//    przedziału NIŻSZEGO, a [formatBand] zapisuje to wprost („70 < q ≤ 200”).
//
// __ROZBIEŻNOŚCI I WYBORY__
//  • MAG 13 → 14: [D1] na 600 A, [D2] między kreskami 500 i 600 (≈ 550 A).
//    Przyjęto ciemniej: 14 od 550 A.
//  • Mikroplazma: oba przedruki kończą pasek 12 między 300 a 350 A —
//    tabela kończy się tu na 300 A, wyżej komunikat „co najmniej 12”.
//  • MMA, MAG, żłobienie: pasek sięga krawędzi wykresu za kreską 600 A —
//    zakres do 600 A, wyżej komunikat „co najmniej”.
//  • ANSI GMAW: [OSHA] i FS-3499 do 500 A (UNL: 550) — przyjęto 500.
//  • ANSI PAC < 300 A: [OSHA]/FS-3499 min 8, zalecany 9. AWS F2.2 (UNL) ma
//    jaśniejsze stopnie dla małych przecinarek (< 20 A: 4, 20–40: 5,
//    40–60: 6, 60–80: 8) — pominięte, bo minimum OSHA (8) jest ciemniejsze.
//  • Cięcie tlenowe EN 169: 900–8000 l/h. DGUV 112-192 dopisuje „do 900 — 4”
//    i „ponad 8000 — 8”. Ponad 8000 l/h → 8 za DGUV (ciemniej niż „co
//    najmniej 7”). Poniżej 900 l/h — najbliższy stopień z tabeli EN (5)
//    z ostrzeżeniem, ciemniej niż 4 z DGUV.
//
// __LIMITY WEJŚCIA__ (sensowność, nie tabela): prąd ≤ [kShadeMaxCurrentA],
// przepływ ≤ [kShadeMaxFlowLh], grubość ≤ [kShadeMaxThicknessMm]. Wyżej —
// błąd pola zamiast wyniku (np. „1e+308 A”).
//
// Poza tabelą: NIE zgadujemy w dół. Za mały prąd → stopień z najniższego
// przedziału tabeli (dla tak małego prądu tabela nie podaje jaśniejszego),
// za duży → „co najmniej” stopień z najwyższego przedziału. Oba z
// ostrzeżeniem.

import 'dart:math' as math;

/// Wielkość, po której dobiera się stopień.
enum ShadeUnit {
  /// Prąd spawania / cięcia [A].
  amp('A'),

  /// Przepływ gazu [l/h] — acetylen (spawanie) albo tlen tnący (cięcie).
  litresPerHour('l/h'),

  /// Grubość materiału [mm].
  mm('mm');

  const ShadeUnit(this.symbol);
  final String symbol;
}

/// Która strona granicy przedziału bierze wartość równą granicy.
enum ShadeBoundary {
  /// Wartość na granicy → przedział WYŻSZY (ciemniejszy filtr). Dla tabel,
  /// które tego nie definiują (wykres EN 169, ANSI/OSHA).
  higherShade,

  /// Wartość na granicy → przedział, który się nią kończy („q ≤ 70 → 4”).
  /// Dla tabel, które to definiują jawnie (gazowe EN 169).
  upperInclusive,
}

/// Jeden przedział tabeli: od końca poprzedniego (albo [ShadeTable.from])
/// do [upTo].
class ShadeBand {
  const ShadeBand(this.upTo, this.shade,
      [this.suggestedLow, this.suggestedHigh]);

  /// Górna granica przedziału (w jednostce tabeli); [double.infinity] —
  /// bez górnej granicy.
  final double upTo;

  /// EN 169: zalecany numer skali. ANSI: minimum ochronne wg OSHA.
  final int shade;

  /// ANSI Z49.1: zalecany stopień — od (null: tabela go nie podaje).
  final int? suggestedLow;

  /// ANSI Z49.1: zalecany stopień — do (np. „6 to 8”, „4 or 5”).
  final int? suggestedHigh;
}

/// Wynik wyszukania w tabeli.
enum ShadeRange {
  /// Wartość w zakresie tabeli.
  within,

  /// Poniżej tabeli — pokazany stopień z NAJNIŻSZEGO przedziału.
  below,

  /// Powyżej tabeli — pokazany stopień to MINIMUM („co najmniej”).
  above,
}

class ShadeLookup {
  const ShadeLookup({
    required this.table,
    required this.band,
    required this.from,
    required this.range,
    required this.value,
  });

  final ShadeTable table;
  final ShadeBand band;

  /// Dolna granica przedziału [band].
  final double from;
  final ShadeRange range;

  /// Wartość, dla której szukano.
  final double value;

  double get to => band.upTo;
  int get shade => band.shade;
  bool get isFirstBand => band.upTo == table.bands.first.upTo;
}

/// Tabela jednego procesu w jednym źródle.
class ShadeTable {
  const ShadeTable({
    required this.unit,
    required this.from,
    required this.bands,
    this.boundary = ShadeBoundary.higherShade,
  });

  final ShadeUnit unit;

  /// Dolny koniec tabeli (włącznie). 0 — tabela obejmuje każdą wartość > 0
  /// (pasek wykresu zaczyna się od krawędzi).
  final double from;

  /// Przedziały rosnąco; stopnie nie maleją.
  final List<ShadeBand> bands;
  final ShadeBoundary boundary;

  /// Górny koniec tabeli (włącznie).
  double get to => bands.last.upTo;

  /// Przedział dla [value] (> 0, skończonej — sprawdza [shadeProblems]).
  ShadeLookup lookup(double value) {
    if (value < from) {
      return ShadeLookup(
          table: this,
          band: bands.first,
          from: from,
          range: ShadeRange.below,
          value: value);
    }
    if (value > to) {
      return ShadeLookup(
          table: this,
          band: bands.last,
          from: bands.length > 1 ? bands[bands.length - 2].upTo : from,
          range: ShadeRange.above,
          value: value);
    }
    var lower = from;
    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      final last = i == bands.length - 1;
      final hit = switch (boundary) {
        ShadeBoundary.upperInclusive => value <= b.upTo,
        // Na granicy — następny (wyższy) przedział; ostatni bierze swój
        // górny koniec, bo wyżej tabeli już nie ma.
        ShadeBoundary.higherShade =>
          value < b.upTo || (last && value == b.upTo),
      };
      if (hit) {
        return ShadeLookup(
            table: this,
            band: b,
            from: lower,
            range: ShadeRange.within,
            value: value);
      }
      lower = b.upTo;
    }
    // Nieosiągalne: value ≤ to.
    throw StateError('lookup($value) poza tabelą $from–$to');
  }
}

// ── Procesy ───────────────────────────────────────────────────────────────

/// Proces — wiersz tabeli EN 169 i odpowiadający mu wiersz ANSI/OSHA.
enum ShadeProcess {
  /// 111 — elektroda otulona. EN: „elektrody otulone”; ANSI: SMAW.
  mma('111 MMA', '111 MMA', 'SMAW'),

  /// 135/136/138 — MAG drutem litym i proszkowym. EN: „MAG”;
  /// ANSI: GMAW i FCAW.
  mag('135/136 MAG', '135/136 MAG', 'GMAW / FCAW'),

  /// 131 — MIG na metalach ciężkich (stal, stal stopowa, miedź).
  /// EN: „MIG na metalach ciężkich”; ANSI: GMAW (bez rozróżnienia metalu).
  migHeavy('131 MIG — stal, miedź', '131 MIG — steel, copper', 'GMAW'),

  /// 131 — MIG na stopach lekkich (aluminium). EN: „MIG na stopach
  /// lekkich”; ANSI: GMAW.
  migLight('131 MIG — aluminium', '131 MIG — aluminium', 'GMAW'),

  /// 141 — TIG. EN: „TIG”; ANSI: GTAW.
  tig('141 TIG', '141 TIG', 'GTAW'),

  /// Żłobienie łukowo-powietrzne (elektroda węglowa + sprężone powietrze).
  /// EN: „żłobienie łukowo-powietrzne”; ANSI: CAC-A.
  arcGouging('Żłobienie łukowo-powietrzne', 'Air carbon arc gouging', 'CAC-A'),

  /// 83 — cięcie plazmowe. EN: „cięcie strumieniem plazmy”; ANSI: PAC.
  plasmaCutting('83 Cięcie plazmowe', '83 Plasma cutting', 'PAC'),

  /// 15 — spawanie plazmowe. EN: „spawanie mikroplazmowe” (wiersz do ok.
  /// 300 A); ANSI: PAW.
  plasmaWelding('15 Spawanie plazmowe', '15 Plasma welding', 'PAW'),

  /// 311 — spawanie acetylenowo-tlenowe. EN: po przepływie acetylenu
  /// [l/h]; ANSI: po grubości [mm].
  gasWelding('311 Spawanie gazowe', '311 Gas welding', 'OFW'),

  /// 81 — cięcie tlenowe. EN: po przepływie tlenu tnącego [l/h];
  /// ANSI: po grubości [mm].
  oxyCutting('81 Cięcie tlenowe', '81 Oxy-fuel cutting', 'OC');

  const ShadeProcess(this.labelPl, this.labelEn, this.ansiCode);

  final String labelPl;
  final String labelEn;

  /// Skrót procesu w tabeli ANSI/AWS.
  final String ansiCode;

  String label({required bool en}) => en ? labelEn : labelPl;

  /// Proces gazowy: EN 169 po przepływie, ANSI po grubości.
  bool get isGas => this == gasWelding || this == oxyCutting;
}

// ── Tabele EN 169 ─────────────────────────────────────────────────────────
// Wykres [D1]/[D2]: kreski skali 1,5 6 10 15 30 40 60 70 100 125 150 175 200
// 225 250 300 350 400 450 500 600 A.

/// Elektrody otulone: 8 do 60 A … 14 od 450 A.
const kEn169Mma = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(60, 8),
  ShadeBand(100, 9),
  ShadeBand(150, 10),
  ShadeBand(200, 11),
  ShadeBand(300, 12),
  ShadeBand(450, 13),
  ShadeBand(600, 14),
]);

/// MAG: 8 do 70 A … 13 od 400 A, 14 od 550 A (patrz „rozbieżności”).
const kEn169Mag = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(70, 8),
  ShadeBand(100, 9),
  ShadeBand(150, 10),
  ShadeBand(225, 11),
  ShadeBand(400, 12),
  ShadeBand(550, 13),
  ShadeBand(600, 14),
]);

/// TIG: od 10 A (poniżej — puste pole wykresu) do 350 A.
const kEn169Tig = ShadeTable(unit: ShadeUnit.amp, from: 10, bands: [
  ShadeBand(30, 8),
  ShadeBand(70, 9),
  ShadeBand(125, 10),
  ShadeBand(200, 11),
  ShadeBand(300, 12),
  ShadeBand(350, 13),
]);

/// MIG na metalach ciężkich: 70–500 A.
const kEn169MigHeavy = ShadeTable(unit: ShadeUnit.amp, from: 70, bands: [
  ShadeBand(125, 9),
  ShadeBand(175, 10),
  ShadeBand(250, 11),
  ShadeBand(350, 12),
  ShadeBand(450, 13),
  ShadeBand(500, 14),
]);

/// MIG na stopach lekkich: 125–500 A.
const kEn169MigLight = ShadeTable(unit: ShadeUnit.amp, from: 125, bands: [
  ShadeBand(175, 10),
  ShadeBand(225, 11),
  ShadeBand(300, 12),
  ShadeBand(400, 13),
  ShadeBand(500, 14),
]);

/// Żłobienie łukowo-powietrzne: 10 do 175 A … 15 od 450 A.
const kEn169ArcGouging = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(175, 10),
  ShadeBand(200, 11),
  ShadeBand(250, 12),
  ShadeBand(350, 13),
  ShadeBand(450, 14),
  ShadeBand(600, 15),
]);

/// Cięcie strumieniem plazmy: 100–400 A.
const kEn169PlasmaCutting = ShadeTable(unit: ShadeUnit.amp, from: 100, bands: [
  ShadeBand(125, 9),
  ShadeBand(150, 10),
  ShadeBand(175, 11),
  ShadeBand(250, 12),
  ShadeBand(400, 13),
]);

/// Spawanie mikroplazmowe: 1,5–300 A (patrz „rozbieżności”).
const kEn169Microplasma = ShadeTable(unit: ShadeUnit.amp, from: 1.5, bands: [
  ShadeBand(6, 4),
  ShadeBand(15, 5),
  ShadeBand(40, 6),
  ShadeBand(60, 7),
  ShadeBand(100, 8),
  ShadeBand(125, 9),
  ShadeBand(175, 10),
  ShadeBand(225, 11),
  ShadeBand(300, 12),
]);

/// Spawanie i lutospawanie gazowe metali ciężkich, przepływ acetylenu q
/// [l/h]: q ≤ 70 → 4; 70 < q ≤ 200 → 5; 200 < q ≤ 800 → 6; q > 800 → 7.
const kEn169GasWelding = ShadeTable(
  unit: ShadeUnit.litresPerHour,
  from: 0,
  boundary: ShadeBoundary.upperInclusive,
  bands: [
    ShadeBand(70, 4),
    ShadeBand(200, 5),
    ShadeBand(800, 6),
    ShadeBand(double.infinity, 7),
  ],
);

/// Cięcie tlenowe, przepływ tlenu q [l/h]: 900 ≤ q ≤ 2000 → 5;
/// 2000 < q ≤ 4000 → 6; 4000 < q ≤ 8000 → 7 (EN 169, [ENG]);
/// q > 8000 → 8 (DGUV Regel 112-192 zał. 2 p. 1: „über 8000 — 8”).
const kEn169OxyCutting = ShadeTable(
  unit: ShadeUnit.litresPerHour,
  from: 900,
  boundary: ShadeBoundary.upperInclusive,
  bands: [
    ShadeBand(2000, 5),
    ShadeBand(4000, 6),
    ShadeBand(8000, 7),
    ShadeBand(double.infinity, 8),
  ],
);

// ── Tabele ANSI Z49.1 / OSHA ──────────────────────────────────────────────
// ShadeBand(górna granica, minimum OSHA, zalecany od, zalecany do).

/// SMAW: < 60 A min 7 (bez zalecenia); 60–160: 8 / 10; 160–250: 10 / 12;
/// 250–550: 11 / 14.
const kAnsiSmaw = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(60, 7),
  ShadeBand(160, 8, 10, 10),
  ShadeBand(250, 10, 12, 12),
  ShadeBand(550, 11, 14, 14),
]);

/// GMAW i FCAW: < 60 A min 7; 60–160: 10 / 11; 160–250: 10 / 12;
/// 250–500: 10 / 14.
const kAnsiGmaw = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(60, 7),
  ShadeBand(160, 10, 11, 11),
  ShadeBand(250, 10, 12, 12),
  ShadeBand(500, 10, 14, 14),
]);

/// GTAW: < 50 A 8 / 10; 50–150: 8 / 12; 150–500: 10 / 14.
const kAnsiGtaw = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(50, 8, 10, 10),
  ShadeBand(150, 8, 12, 12),
  ShadeBand(500, 10, 14, 14),
]);

/// CAC-A: lekkie < 500 A 10 / 12; ciężkie 500–1000: 11 / 14.
const kAnsiCac = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(500, 10, 12, 12),
  ShadeBand(1000, 11, 14, 14),
]);

/// PAW: < 20 A 6 / 6–8; 20–100: 8 / 10; 100–400: 10 / 12; 400–800: 11 / 14.
const kAnsiPaw = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(20, 6, 6, 8),
  ShadeBand(100, 8, 10, 10),
  ShadeBand(400, 10, 12, 12),
  ShadeBand(800, 11, 14, 14),
]);

/// PAC: < 300 A 8 / 9; 300–400: 9 / 12; 400–800: 10 / 14. Dla łuku
/// widocznego wprost; gdy łuk zasłania materiał, można jaśniej (przypis **).
const kAnsiPac = ShadeTable(unit: ShadeUnit.amp, from: 0, bands: [
  ShadeBand(300, 8, 9, 9),
  ShadeBand(400, 9, 12, 12),
  ShadeBand(800, 10, 14, 14),
]);

/// Spawanie gazowe po grubości [mm]: < 3,2 min 4 / 4–5; 3,2–12,7: 5 / 5–6;
/// > 12,7: 6 / 6–8.
const kAnsiGasWelding = ShadeTable(unit: ShadeUnit.mm, from: 0, bands: [
  ShadeBand(3.2, 4, 4, 5),
  ShadeBand(12.7, 5, 5, 6),
  ShadeBand(double.infinity, 6, 6, 8),
]);

/// Cięcie tlenowe po grubości [mm]: < 25 min 3 / 3–4; 25–150: 4 / 4–5;
/// > 150: 5 / 5–6.
const kAnsiOxyCutting = ShadeTable(unit: ShadeUnit.mm, from: 0, bands: [
  ShadeBand(25, 3, 3, 4),
  ShadeBand(150, 4, 4, 5),
  ShadeBand(double.infinity, 5, 5, 6),
]);

/// Tabela EN 169 procesu.
ShadeTable en169Table(ShadeProcess p) => switch (p) {
      ShadeProcess.mma => kEn169Mma,
      ShadeProcess.mag => kEn169Mag,
      ShadeProcess.migHeavy => kEn169MigHeavy,
      ShadeProcess.migLight => kEn169MigLight,
      ShadeProcess.tig => kEn169Tig,
      ShadeProcess.arcGouging => kEn169ArcGouging,
      ShadeProcess.plasmaCutting => kEn169PlasmaCutting,
      ShadeProcess.plasmaWelding => kEn169Microplasma,
      ShadeProcess.gasWelding => kEn169GasWelding,
      ShadeProcess.oxyCutting => kEn169OxyCutting,
    };

/// Tabela ANSI Z49.1 / OSHA procesu.
ShadeTable ansiTable(ShadeProcess p) => switch (p) {
      ShadeProcess.mma => kAnsiSmaw,
      ShadeProcess.mag ||
      ShadeProcess.migHeavy ||
      ShadeProcess.migLight =>
        kAnsiGmaw,
      ShadeProcess.tig => kAnsiGtaw,
      ShadeProcess.arcGouging => kAnsiCac,
      ShadeProcess.plasmaCutting => kAnsiPac,
      ShadeProcess.plasmaWelding => kAnsiPaw,
      ShadeProcess.gasWelding => kAnsiGasWelding,
      ShadeProcess.oxyCutting => kAnsiOxyCutting,
    };

// ── Wejście, walidacja, wynik ─────────────────────────────────────────────

/// Dane z ekranu. `null` — pole puste; [double.nan] — pole nieczytelne.
class ShadeInput {
  const ShadeInput({
    required this.process,
    this.currentA,
    this.gasFlowLh,
    this.thicknessMm,
  });

  final ShadeProcess process;

  /// Prąd [A] — procesy łukowe (EN i ANSI).
  final double? currentA;

  /// Przepływ acetylenu / tlenu tnącego [l/h] — procesy gazowe, EN 169.
  final double? gasFlowLh;

  /// Grubość materiału [mm] — procesy gazowe, ANSI/OSHA.
  final double? thicknessMm;
}

enum ShadeProblem {
  /// Proces łukowy, puste pole prądu.
  currentMissing,

  /// Prąd nieczytelny albo ≤ 0.
  currentInvalid,

  /// Proces gazowy, oba pola puste.
  gasInputMissing,

  /// Przepływ nieczytelny albo ≤ 0.
  flowInvalid,

  /// Grubość nieczytelna albo ≤ 0.
  thicknessInvalid,

  /// Prąd ponad [kShadeMaxCurrentA].
  currentTooHigh,

  /// Przepływ ponad [kShadeMaxFlowLh].
  flowTooHigh,

  /// Grubość ponad [kShadeMaxThicknessMm].
  thicknessTooHigh,
}

/// Górny limit pola prądu [A] — ponad tym to pomyłka w polu, nie proces
/// (żłobienie łukowo-powietrzne w tabeli ANSI kończy się na 1000 A).
const double kShadeMaxCurrentA = 2000;

/// Górny limit pola przepływu gazu [l/h].
const double kShadeMaxFlowLh = 100000;

/// Górny limit pola grubości [mm].
const double kShadeMaxThicknessMm = 2000;

bool _valid(double? v, double max) =>
    v != null && v.isFinite && v > 0 && v <= max;

/// Problem pola: null — puste albo poprawne.
ShadeProblem? _fieldProblem(
    double? v, double max, ShadeProblem invalid, ShadeProblem tooHigh) {
  if (v == null || _valid(v, max)) return null;
  return v.isFinite && v > max ? tooHigh : invalid;
}

/// Co nie pozwala policzyć (albo psuje część wyniku). Puste pole ≠ wynik.
List<ShadeProblem> shadeProblems(ShadeInput i) {
  if (!i.process.isGas) {
    if (i.currentA == null) return const [ShadeProblem.currentMissing];
    final p = _fieldProblem(i.currentA, kShadeMaxCurrentA,
        ShadeProblem.currentInvalid, ShadeProblem.currentTooHigh);
    return p == null ? const [] : [p];
  }
  if (i.gasFlowLh == null && i.thicknessMm == null) {
    return const [ShadeProblem.gasInputMissing];
  }
  final flow = _fieldProblem(i.gasFlowLh, kShadeMaxFlowLh,
      ShadeProblem.flowInvalid, ShadeProblem.flowTooHigh);
  final thickness = _fieldProblem(i.thicknessMm, kShadeMaxThicknessMm,
      ShadeProblem.thicknessInvalid, ShadeProblem.thicknessTooHigh);
  return [
    if (flow != null) flow,
    if (thickness != null) thickness,
  ];
}

/// Zalecenie z obu źródeł.
class ShadeAdvice {
  const ShadeAdvice({required this.process, this.en, this.ansi});

  final ShadeProcess process;

  /// EN 169 (null — brak danych do tej tabeli, np. pusty przepływ).
  final ShadeLookup? en;

  /// ANSI Z49.1 / OSHA (null — brak danych, np. pusta grubość).
  final ShadeLookup? ansi;

  /// ANSI: minimum ochronne OSHA.
  int? get oshaMinimum => ansi?.band.shade;

  /// ANSI: zalecany stopień — do (ciemniejszy koniec), a bez zalecenia
  /// w tabeli — minimum.
  int? get ansiSuggestedHigh =>
      ansi == null ? null : (ansi!.band.suggestedHigh ?? ansi!.band.shade);

  /// Od czego zacząć: CIEMNIEJSZY z EN 169 i zalecanego ANSI.
  int get startShade => math.max(en?.shade ?? 0, ansiSuggestedHigh ?? 0);

  /// Najjaśniej, jak wolno rozjaśnić: nie poniżej minimum OSHA i nie
  /// poniżej EN 169 − 1 (EN dopuszcza ±1 zależnie od warunków; poza
  /// tabelą — bez −1).
  int get floorShade {
    final e = en;
    final enFloor =
        e == null ? 0 : (e.range == ShadeRange.within ? e.shade - 1 : e.shade);
    return math.max(oshaMinimum ?? 0, enFloor);
  }

  /// Któraś wartość leży poza tabelą.
  bool get outsideTable =>
      (en != null && en!.range != ShadeRange.within) ||
      (ansi != null && ansi!.range != ShadeRange.within);
}

/// Zalecenie albo `null`, gdy nie ma z czego liczyć (patrz [shadeProblems]).
/// Przy procesie gazowym liczy z tego pola, które jest poprawne.
ShadeAdvice? computeShade(ShadeInput i) {
  final p = i.process;
  if (!p.isGas) {
    final a = i.currentA;
    if (!_valid(a, kShadeMaxCurrentA)) return null;
    return ShadeAdvice(
      process: p,
      en: en169Table(p).lookup(a!),
      ansi: ansiTable(p).lookup(a),
    );
  }
  final q = i.gasFlowLh;
  final t = i.thicknessMm;
  final qOk = _valid(q, kShadeMaxFlowLh);
  final tOk = _valid(t, kShadeMaxThicknessMm);
  if (!qOk && !tOk) return null;
  return ShadeAdvice(
    process: p,
    en: qOk ? en169Table(p).lookup(q!) : null,
    ansi: tOk ? ansiTable(p).lookup(t!) : null,
  );
}

// ── Formatowanie ──────────────────────────────────────────────────────────

/// Liczba bez zbędnych zer, dokładnie taka, jak wpisana (najkrótszy zapis
/// dający tę samą wartość) — „100”, „87,5”, „1,5”. Przecinek po polsku.
String formatShadeValue(double v, {required bool en}) {
  var s = v.toString();
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return en ? s : s.replaceAll('.', ',');
}

/// Przedział [l] słownie. Tabele z granicą wspólną (wykres EN 169, ANSI):
/// „60–160 A”, „< 60 A”, „≥ 12,7 mm”. Tabele gazowe EN 169
/// ([ShadeBoundary.upperInclusive]) — z nierównościami, żeby było widać,
/// do którego przedziału należy granica: „q ≤ 70 l/h”, „70 < q ≤ 200 l/h”,
/// „900 ≤ q ≤ 2000 l/h”, „q > 800 l/h”. Poza tabelą — gdzie leży wartość:
/// „< 10 A”, „> 350 A”, „q < 900 l/h”.
String formatBand(ShadeLookup l, {required bool en}) {
  final u = l.table.unit.symbol;
  String n(double v) => formatShadeValue(v, en: en);
  if (l.table.boundary == ShadeBoundary.upperInclusive) {
    if (l.range == ShadeRange.below) return 'q < ${n(l.table.from)} $u';
    if (l.range == ShadeRange.above) return 'q > ${n(l.table.to)} $u';
    if (l.to.isInfinite) return 'q > ${n(l.from)} $u';
    if (l.isFirstBand) {
      return l.from == 0
          ? 'q ≤ ${n(l.to)} $u'
          : '${n(l.from)} ≤ q ≤ ${n(l.to)} $u';
    }
    return '${n(l.from)} < q ≤ ${n(l.to)} $u';
  }
  if (l.range == ShadeRange.below) return '< ${n(l.table.from)} $u';
  if (l.range == ShadeRange.above) return '> ${n(l.table.to)} $u';
  if (l.to.isInfinite) return '≥ ${n(l.from)} $u';
  if (l.from == 0 && l.isFirstBand) return '< ${n(l.to)} $u';
  return '${n(l.from)}–${n(l.to)} $u';
}

/// Zakres całej tabeli słownie: „10–350 A”, „≤ 600 A”, a dla tabel gazowych
/// EN 169 „q ≥ 900 l/h”.
String formatTableRange(ShadeTable t, {required bool en}) {
  final u = t.unit.symbol;
  String n(double v) => formatShadeValue(v, en: en);
  final q = t.boundary == ShadeBoundary.upperInclusive ? 'q ' : '';
  if (t.to.isInfinite) {
    return t.from == 0 ? '$q> 0 $u' : '$q≥ ${n(t.from)} $u';
  }
  if (t.from == 0) return '$q≤ ${n(t.to)} $u';
  return q.isEmpty
      ? '${n(t.from)}–${n(t.to)} $u'
      : '${n(t.from)} ≤ q ≤ ${n(t.to)} $u';
}

/// Jak tabela traktuje wartość równą granicy — zdanie do ekranu.
/// Wykres EN 169 i ANSI/OSHA: wyższy stopień. Tabele gazowe EN 169: granica
/// należy do przedziału niższego, z przykładem z tabeli („q ≤ 70 → 4”).
String shadeBoundaryRule(ShadeTable t, {required bool en}) {
  if (t.boundary == ShadeBoundary.higherShade) {
    return en
        ? 'On a band boundary — the higher shade.'
        : 'Na granicy przedziału — wyższy stopień.';
  }
  final b = t.bands.first;
  final ex = 'q ≤ ${formatShadeValue(b.upTo, en: en)} ${t.unit.symbol} → '
      '${b.shade}';
  return en
      ? 'Gas flow per EN 169: a boundary value belongs to the lower band '
          '($ex).'
      : 'Przepływ gazu wg EN 169: granica należy do przedziału niższego '
          '($ex).';
}

/// Stopień do pokazania: „11”, a powyżej tabeli „≥ 13”.
String formatShade(ShadeLookup l) =>
    l.range == ShadeRange.above ? '≥ ${l.shade}' : '${l.shade}';

/// Zalecany ANSI do pokazania: „12”, „6–8”, „≥ 14”, a bez zalecenia „—”.
String formatAnsiSuggested(ShadeLookup l) {
  final lo = l.band.suggestedLow;
  final hi = l.band.suggestedHigh;
  if (lo == null || hi == null) return '—';
  final s = lo == hi ? '$lo' : '$lo–$hi';
  return l.range == ShadeRange.above ? '≥ $s' : s;
}

/// Wiele filtrów samościemniających kończy się na 13 (np. 3M Speedglas
/// 9100: 5, 8, 9–13 — karta techniczna 2015).
const int kTypicalAutoDarkeningMax = 13;

/// Tekst do udostępnienia — te same liczby co na ekranie.
String shadeShareText(ShadeAdvice a, {required bool en}) {
  // Tekst PL albo EN — liczby te same.
  String t(String pl, String english) => en ? english : pl;
  final b = StringBuffer()
    ..writeln(t('Filtr przyłbicy — stopień zaciemnienia',
        'Welding filter — shade number'))
    ..writeln('${t('Proces', 'Process')}: ${a.process.label(en: en)}');
  final e = a.en;
  final s = a.ansi;
  if (e != null) {
    b.writeln('${shadeQuantityName(a.process, e.table.unit, en: en)}: '
        '${formatShadeValue(e.value, en: en)} ${e.table.unit.symbol}');
  }
  if (s != null && (e == null || s.table.unit != e.table.unit)) {
    b.writeln('${shadeQuantityName(a.process, s.table.unit, en: en)}: '
        '${formatShadeValue(s.value, en: en)} ${s.table.unit.symbol}');
  }
  if (e != null) {
    final note = switch (e.range) {
      ShadeRange.within =>
        t('±1 zależnie od warunków', '±1 depending on conditions'),
      ShadeRange.below => t('poniżej tabeli — najniższy przedział',
          'below the table — lowest band'),
      ShadeRange.above =>
        t('powyżej tabeli — co najmniej', 'above the table — at least'),
    };
    b.writeln('EN 169: ${formatShade(e)} (${formatBand(e, en: en)}; $note)');
  }
  if (s != null) {
    b.writeln('ANSI Z49.1 (${a.process.ansiCode}): '
        '${t('zalecany', 'suggested')} ${formatAnsiSuggested(s)} · '
        '${t('minimum OSHA', 'OSHA minimum')} ${formatShade(s)} '
        '(${formatBand(s, en: en)})');
  }
  final start = a.startShade;
  final floor = a.floorShade;
  b.writeln(start == floor
      ? t('Bezpiecznie: stopień $start — nie jaśniej.',
          'Safe choice: shade $start — not lighter.')
      : t(
          'Bezpiecznie: zacznij od $start i rozjaśniaj do dobrej '
              'widoczności — nie jaśniej niż $floor.',
          'Safe choice: start at $start and go lighter until you see the '
              'weld zone well — not lighter than $floor.'));
  if (a.outsideTable) {
    b.writeln(t('Uwaga: wartość poza tabelą — sprawdź instrukcję przyłbicy.',
        'Note: value outside the table — check the helmet manual.'));
  }
  b.write(t(
      'Źródła: EN 169:2002 (za DGUV), OSHA 29 CFR 1910.133(a)(5), '
          'ANSI Z49.1:2005 (za OSHA FS-3499). Orientacyjnie — decyduje '
          'instrukcja przyłbicy.',
      'Sources: EN 169:2002 (via DGUV), OSHA 29 CFR 1910.133(a)(5), '
          'ANSI Z49.1:2005 (via OSHA FS-3499). Guidance only — the helmet '
          'manual governs.'));
  return b.toString();
}

/// Nazwa wielkości wejściowej: „Prąd”, „Przepływ acetylenu”, „Przepływ
/// tlenu”, „Grubość”.
String shadeQuantityName(ShadeProcess p, ShadeUnit u, {required bool en}) =>
    switch (u) {
      ShadeUnit.amp => en ? 'Current' : 'Prąd',
      ShadeUnit.litresPerHour => p == ShadeProcess.oxyCutting
          ? (en ? 'Oxygen flow' : 'Przepływ tlenu')
          : (en ? 'Acetylene flow' : 'Przepływ acetylenu'),
      ShadeUnit.mm => en ? 'Thickness' : 'Grubość',
    };
