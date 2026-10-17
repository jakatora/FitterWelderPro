/// Twardość: przelicznik HV ↔ HB ↔ HRC ↔ HRB (i Rm orientacyjnie) dla stali
/// niestopowych i niskostopowych oraz ocena serii pomiarów względem limitu
/// maksymalnego (NACE MR0175/ISO 15156-2, EN ISO 15614-1, ASME B31.3,
/// własny limit).
///
/// Zasady bezpieczeństwa werdyktu (sprawdzane testami):
///   • przeliczenie tylko INTERPOLACJĄ LINIOWĄ między wierszami tablicy —
///     bez ekstrapolacji; poza tablicą wynik `null`, a pomiar dostaje status
///     [ReadingStatus.outOfRange] (≠ OK);
///   • werdykt liczony na pełnej precyzji (double), nigdy na tekście
///     z ekranu; równość z limitem (max) = OK;
///   • pusty, nieczytelny albo niefizyczny pomiar ≠ OK;
///   • limit ≤ 0, NaN albo spoza skali → brak werdyktu (nie zielony);
///   • stal nierdzewna/austenityczna: tablica nie obowiązuje — pomiar w innej
///     skali niż limit dostaje [ReadingStatus.notConvertible] (≠ OK);
///   • liczba pokazywana obok werdyktu jest zaokrąglana w stronę werdyktu
///     ([formatAgainstLimit]) — 250,04 HV przy limicie 250 nie wygląda jak
///     „250,0”.
///
/// Czysty Dart (bez Fluttera).
library;

// ═══════════════════════════════════════════════════════════════════════════
// SKALE
// ═══════════════════════════════════════════════════════════════════════════

enum HardnessScale { hv, hb, hrc, hrb }

extension HardnessScaleInfo on HardnessScale {
  /// Symbol skali na ekranie i w protokole.
  String get label => switch (this) {
        HardnessScale.hv => 'HV',
        HardnessScale.hb => 'HB',
        HardnessScale.hrc => 'HRC',
        HardnessScale.hrb => 'HRB',
      };

  /// Górna granica wartości, którą w ogóle da się odczytać w tej skali.
  /// Powyżej — wpis traktowany jako błąd (np. wartość HV wpisana jako HRC),
  /// a nie jako pomiar. To NIE jest zakres tablicy przeliczeń.
  double get maxPlausible => switch (this) {
        HardnessScale.hv => 3000,
        HardnessScale.hb => 1000,
        HardnessScale.hrc => 100,
        HardnessScale.hrb => 130,
      };
}

/// Grupa materiałowa — decyduje, czy wolno przeliczać skale.
enum HardnessMaterial {
  /// Stale niestopowe i niskostopowe, staliwo — ISO 18265 tab. A.1.
  carbonLowAlloy,

  /// Stale nierdzewne / austenityczne — tablica A.1 nie obowiązuje;
  /// porównanie tylko w tej samej skali co limit.
  stainless,
}

// ═══════════════════════════════════════════════════════════════════════════
// TABLICA ISO 18265:2013 (EN ISO 18265:2013, DIN EN ISO 18265:2014-02)
// ═══════════════════════════════════════════════════════════════════════════

/// Jeden wiersz tablicy. `null` = w tablicy kreska (skala nie obowiązuje
/// przy tej twardości).
class HardnessRow {
  final double hv;
  final double? hb;
  final double? hrc;
  final double? hrb;

  /// Wytrzymałość na rozciąganie Rm [MPa] — najmniej pewna wielkość tablicy,
  /// tylko orientacyjnie.
  final double? rm;

  const HardnessRow(this.hv, {this.hb, this.hrc, this.hrb, this.rm});

  double? value(HardnessScale s) => switch (s) {
        HardnessScale.hv => hv,
        HardnessScale.hb => hb,
        HardnessScale.hrc => hrc,
        HardnessScale.hrb => hrb,
      };
}

/// Źródło tablicy — do ekranu i protokołu.
const String kHardnessTableSourcePl =
    'ISO 18265:2013 (EN ISO 18265), tab. A.1 — stale niestopowe '
    'i niskostopowe, staliwo';
const String kHardnessTableSourceEn =
    'ISO 18265:2013 (EN ISO 18265), Table A.1 — unalloyed and low-alloy '
    'steels, cast steel';

/// ISO 18265:2013, tablica A.1 „Umwertung für Härte in Härte und Härte
/// in Zugfestigkeit für unlegierte und niedriglegierte Stähle und Stahlguss”.
///
/// Kolumny: HV (HV10), HB (HBW 10/3000; do 450 HB kulka stalowa, wyżej
/// z węglików spiekanych — przypis tablicy), HRC, HRB, Rm [MPa].
///
/// Źródła (normy nie ma w wolnym dostępie — przepisano z dwóch niezależnych
/// przedruków i porównano wiersz po wierszu, stan 2026-10-17):
///  [W] Westfälische Stahlgesellschaft, „Härtevergleichstabelle” — „Die
///      Tabellenwerte entsprechen der Norm DIN EN ISO 18265, Tabelle A.1
///      (Ausgabe Februar 2014)”, HV 80–940, wszystkie kolumny:
///      https://ws-stahl.de/wp-content/uploads/2020/12/Haertevergleichstabelle-DE.pdf
///  [S] Studer-Biennaform (Notz Metall), „Vergleichstabelle Zugfestigkeit
///      Härte”, JAS-003 wyd. 2025/10, HV 80–650 (Rm, HV, HB, HRB, HRC):
///      https://www.studersa.com/file/1855/
///  [P] spawacz.waw.pl, „Hardness converter HV, HB, HRC: full ISO 18265
///      table” — kontrola kolumny HRC 700–900 HV.
///
/// Rozbieżności i decyzje:
///  • HRB 150–170 HV: [W] ma kolumnę przesuniętą o wiersz (81,7 przy 155,
///    85 przy 165); przyjęto [S]: 160 → 81,7, 170 → 85,0 (zgodne z resztą
///    kolumny, co 10 HV).
///  • HRC 720 HV: [W] podaje 61,5 (przyrost 1,4 i potem 0,3 — literówka);
///    przyjęto 61,0 jak [P] i ASTM E140 (HRC 61 ≈ 720 HV).
///  • HRB w nawiasach w [W] (101–105 przy 265–295 HV) pominięto — przypis
///    tablicy: poza zakresem definicji metody. Zakres HRB: 41,0–99,5.
///  • HB powyżej 470 HV (447 HB) i do 650 HV (618 HB) tylko z [W]
///    (kulka z węglików).
const List<HardnessRow> kIso18265TableA1 = [
  HardnessRow(80, hb: 76.0, rm: 255),
  HardnessRow(85, hb: 80.7, hrb: 41.0, rm: 270),
  HardnessRow(90, hb: 85.5, hrb: 48.0, rm: 285),
  HardnessRow(95, hb: 90.2, hrb: 52.0, rm: 305),
  HardnessRow(100, hb: 95.0, hrb: 56.2, rm: 320),
  HardnessRow(105, hb: 99.8, rm: 335),
  HardnessRow(110, hb: 105, hrb: 62.3, rm: 350),
  HardnessRow(115, hb: 109, rm: 370),
  HardnessRow(120, hb: 114, hrb: 66.7, rm: 385),
  HardnessRow(125, hb: 119, rm: 400),
  HardnessRow(130, hb: 124, hrb: 71.2, rm: 415),
  HardnessRow(135, hb: 128, rm: 430),
  HardnessRow(140, hb: 133, hrb: 75.0, rm: 450),
  HardnessRow(145, hb: 138, rm: 465),
  HardnessRow(150, hb: 143, hrb: 78.7, rm: 480),
  HardnessRow(155, hb: 147, rm: 495),
  HardnessRow(160, hb: 152, hrb: 81.7, rm: 510),
  HardnessRow(165, hb: 156, rm: 530),
  HardnessRow(170, hb: 162, hrb: 85.0, rm: 545),
  HardnessRow(175, hb: 166, rm: 560),
  HardnessRow(180, hb: 171, hrb: 87.1, rm: 575),
  HardnessRow(185, hb: 176, rm: 595),
  HardnessRow(190, hb: 181, hrb: 89.5, rm: 610),
  HardnessRow(195, hb: 185, rm: 625),
  HardnessRow(200, hb: 190, hrb: 91.5, rm: 640),
  HardnessRow(205, hb: 195, hrb: 92.5, rm: 660),
  HardnessRow(210, hb: 199, hrb: 93.5, rm: 675),
  HardnessRow(215, hb: 204, hrb: 94.0, rm: 690),
  HardnessRow(220, hb: 209, hrb: 95.0, rm: 705),
  HardnessRow(225, hb: 214, hrb: 96.0, rm: 720),
  HardnessRow(230, hb: 219, hrb: 96.7, rm: 740),
  HardnessRow(235, hb: 223, rm: 755),
  HardnessRow(240, hb: 228, hrc: 20.3, hrb: 98.1, rm: 770),
  HardnessRow(245, hb: 233, hrc: 21.3, rm: 785),
  HardnessRow(250, hb: 238, hrc: 22.2, hrb: 99.5, rm: 800),
  HardnessRow(255, hb: 242, hrc: 23.1, rm: 820),
  HardnessRow(260, hb: 247, hrc: 24.0, rm: 835),
  HardnessRow(265, hb: 252, hrc: 24.8, rm: 850),
  HardnessRow(270, hb: 257, hrc: 25.6, rm: 865),
  HardnessRow(275, hb: 261, hrc: 26.4, rm: 880),
  HardnessRow(280, hb: 266, hrc: 27.1, rm: 900),
  HardnessRow(285, hb: 271, hrc: 27.8, rm: 915),
  HardnessRow(290, hb: 276, hrc: 28.5, rm: 930),
  HardnessRow(295, hb: 280, hrc: 29.2, rm: 950),
  HardnessRow(300, hb: 285, hrc: 29.8, rm: 965),
  HardnessRow(310, hb: 295, hrc: 31.0, rm: 995),
  HardnessRow(320, hb: 304, hrc: 32.2, rm: 1030),
  HardnessRow(330, hb: 314, hrc: 33.3, rm: 1060),
  HardnessRow(340, hb: 323, hrc: 34.4, rm: 1095),
  HardnessRow(350, hb: 333, hrc: 35.5, rm: 1125),
  HardnessRow(360, hb: 342, hrc: 36.6, rm: 1155),
  HardnessRow(370, hb: 352, hrc: 37.7, rm: 1190),
  HardnessRow(380, hb: 361, hrc: 38.8, rm: 1220),
  HardnessRow(390, hb: 371, hrc: 39.8, rm: 1255),
  HardnessRow(400, hb: 380, hrc: 40.8, rm: 1290),
  HardnessRow(410, hb: 390, hrc: 41.8, rm: 1320),
  HardnessRow(420, hb: 399, hrc: 42.7, rm: 1350),
  HardnessRow(430, hb: 409, hrc: 43.6, rm: 1385),
  HardnessRow(440, hb: 418, hrc: 44.5, rm: 1420),
  HardnessRow(450, hb: 428, hrc: 45.3, rm: 1455),
  HardnessRow(460, hb: 437, hrc: 46.1, rm: 1485),
  HardnessRow(470, hb: 447, hrc: 46.9, rm: 1520),
  HardnessRow(480, hb: 456, hrc: 47.7, rm: 1555),
  HardnessRow(490, hb: 466, hrc: 48.4, rm: 1595),
  HardnessRow(500, hb: 475, hrc: 49.1, rm: 1630),
  HardnessRow(510, hb: 485, hrc: 49.8, rm: 1665),
  HardnessRow(520, hb: 494, hrc: 50.5, rm: 1700),
  HardnessRow(530, hb: 504, hrc: 51.1, rm: 1740),
  HardnessRow(540, hb: 513, hrc: 51.7, rm: 1775),
  HardnessRow(550, hb: 523, hrc: 52.3, rm: 1810),
  HardnessRow(560, hb: 532, hrc: 53.0, rm: 1845),
  HardnessRow(570, hb: 542, hrc: 53.6, rm: 1880),
  HardnessRow(580, hb: 551, hrc: 54.1, rm: 1920),
  HardnessRow(590, hb: 561, hrc: 54.7, rm: 1955),
  HardnessRow(600, hb: 570, hrc: 55.2, rm: 1995),
  HardnessRow(610, hb: 580, hrc: 55.7, rm: 2030),
  HardnessRow(620, hb: 589, hrc: 56.3, rm: 2070),
  HardnessRow(630, hb: 599, hrc: 56.8, rm: 2105),
  HardnessRow(640, hb: 608, hrc: 57.3, rm: 2145),
  HardnessRow(650, hb: 618, hrc: 57.8, rm: 2180),
  HardnessRow(660, hrc: 58.3),
  HardnessRow(670, hrc: 58.8),
  HardnessRow(680, hrc: 59.2),
  HardnessRow(690, hrc: 59.7),
  HardnessRow(700, hrc: 60.1),
  HardnessRow(720, hrc: 61.0),
  HardnessRow(740, hrc: 61.8),
  HardnessRow(760, hrc: 62.5),
  HardnessRow(780, hrc: 63.3),
  HardnessRow(800, hrc: 64.0),
  HardnessRow(820, hrc: 64.7),
  HardnessRow(840, hrc: 65.3),
  HardnessRow(860, hrc: 65.9),
  HardnessRow(880, hrc: 66.4),
  HardnessRow(900, hrc: 67.0),
  HardnessRow(920, hrc: 67.5),
  HardnessRow(940, hrc: 68.0),
];

// ═══════════════════════════════════════════════════════════════════════════
// PRZELICZANIE
// ═══════════════════════════════════════════════════════════════════════════

/// Pary (a, b) z wierszy, w których obie kolumny mają wartość; rosnąco po a.
/// Wszystkie kolumny tablicy rosną razem z HV, więc pary są monotoniczne.
List<(double, double)> _pairs(
  double? Function(HardnessRow) a,
  double? Function(HardnessRow) b,
) =>
    [
      for (final r in kIso18265TableA1)
        if (a(r) != null && b(r) != null) (a(r)!, b(r)!),
    ];

/// Wynik interpolacji ucięty do siatki 1e-9: szum zmiennoprzecinkowy
/// (250,00000000000003 zamiast 250) nie może zamienić „równo z limitem”
/// w „przekroczony”. Tablica ma dokładność 0,1 — 1e-9 nic nie zmienia,
/// a porównanie z limitem może być ścisłe (bez tolerancji).
double _snap(double x) => (x * 1e9).roundToDouble() / 1e9;

/// Interpolacja liniowa po parach; `null` poza zakresem (bez ekstrapolacji).
double? _interpolate(List<(double, double)> pairs, double x) {
  if (!x.isFinite || pairs.length < 2) return null;
  if (x < pairs.first.$1 || x > pairs.last.$1) return null;
  for (var i = 0; i < pairs.length; i++) {
    final (a0, b0) = pairs[i];
    if (x == a0) return b0;
    if (i + 1 < pairs.length) {
      final (a1, b1) = pairs[i + 1];
      if (x < a1) return _snap(b0 + (x - a0) / (a1 - a0) * (b1 - b0));
    }
  }
  return null;
}

/// Zakres tablicy w danej skali (najmniejsza i największa wartość kolumny).
({double min, double max}) hardnessTableRange(HardnessScale s) {
  final v = [
    for (final r in kIso18265TableA1)
      if (r.value(s) != null) r.value(s)!,
  ];
  return (min: v.first, max: v.last);
}

/// Czy [value] mieści się w kolumnie [s] tablicy (krańce włącznie).
bool isInHardnessTable(double value, HardnessScale s) {
  if (!value.isFinite) return false;
  final r = hardnessTableRange(s);
  return value >= r.min && value <= r.max;
}

/// Przelicza twardość ze skali [from] na [to] wg ISO 18265 tab. A.1.
///
/// `null`, gdy wartość leży poza zakresem tablicy dla tej pary skal (np.
/// HRC poniżej 20,3 albo HRB przy twardości, przy której tablica podaje
/// kreskę). Ta sama skala → wartość bez zmian (o ile skończona).
double? convertHardness(
  double value, {
  required HardnessScale from,
  required HardnessScale to,
}) {
  if (!value.isFinite) return null;
  if (from == to) return value;
  return _interpolate(_pairs((r) => r.value(from), (r) => r.value(to)), value);
}

/// Orientacyjna wytrzymałość Rm [MPa] z twardości; `null` poza zakresem
/// (Rm tablica podaje dla 80–650 HV).
double? estimateTensileStrengthMpa(double value, HardnessScale from) =>
    _interpolate(_pairs((r) => r.value(from), (r) => r.rm), value);

// ═══════════════════════════════════════════════════════════════════════════
// LIMITY
// ═══════════════════════════════════════════════════════════════════════════

/// Limit maksymalnej twardości w jednej skali.
class HardnessLimit {
  final HardnessScale scale;
  final double value;

  const HardnessLimit(this.scale, this.value);

  /// Limit, z którym da się porównywać: liczba skończona, > 0, nie większa
  /// niż maksimum odczytu skali. Inaczej brak werdyktu (nigdy fałszywe OK).
  bool get isValid =>
      value.isFinite && value > 0 && value <= scale.maxPlausible;
}

/// Rodzina norm — do grupowania listy presetów.
enum HardnessStandard { iso15156, iso15614, asmeB313 }

/// Gotowy limit z dokładnym źródłem.
class HardnessLimitPreset {
  final String id;
  final HardnessStandard standard;
  final HardnessLimit limit;
  final String titlePl;
  final String titleEn;

  /// Norma, wydanie, tabela / punkt.
  final String sourcePl;
  final String sourceEn;

  /// Warunki stosowania, zastrzeżenia.
  final String notePl;
  final String noteEn;

  const HardnessLimitPreset({
    required this.id,
    required this.standard,
    required this.limit,
    required this.titlePl,
    required this.titleEn,
    required this.sourcePl,
    required this.sourceEn,
    this.notePl = '',
    this.noteEn = '',
  });
}

/// Identyfikator „własnego limitu” (nie jest presetem).
const String kHardnessCustomLimitId = 'custom';

const String _iso15156 = 'NACE MR0175/ISO 15156-2:2020';
const String _iso15614Pl =
    'EN ISO 15614-1:2017, tabela maks. twardości HV10 (w wyd. 2004+A2:2012 '
    '— tab. 2)';
const String _iso15614En =
    'EN ISO 15614-1:2017, maximum hardness HV10 table (Table 2 in the '
    '2004+A2:2012 edition)';
const String _b313Pl =
    'ASME B31.3-2008…2012, tab. 331.1.1, kol. „Brinell Hardness, Max.”';
const String _b313En =
    'ASME B31.3-2008…2012, Table 331.1.1, column “Brinell Hardness, Max.”';
const String _b313NotePl =
    'Wydania 2014 i nowsze (w tym 2020 i 2022) nie mają tej kolumny ani '
    'wymogu 331.1.7 — twardość po PWHT ocenia się wtedy wg specyfikacji '
    'projektu. Używaj, gdy projekt przywołuje to wydanie albo te wartości.';
const String _b313NoteEn =
    'The 2014 and later editions (incl. 2020 and 2022) have neither this '
    'column nor the 331.1.7 requirement — post-PWHT hardness is then judged '
    'to the project specification. Use when the project invokes that edition '
    'or these values.';
const String _iso15614NotePl =
    'Grupy wg ISO/TR 15608. Wartość jak w wyd. 2004+A2:2012 — sprawdź '
    'w swoim egzemplarzu wyd. 2017 i w specyfikacji projektu.';
const String _iso15614NoteEn =
    'Groups per ISO/TR 15608. Value as in the 2004+A2:2012 edition — check '
    'your copy of the 2017 edition and the project specification.';

/// Presety limitów (wszystkie: wartość MAKSYMALNA). Weryfikacja 2026-10-17:
///  • ISO 15156-2:2020 — tekst normy (wyd. 4, 2020-11): tab. A.1, A.2.1.2,
///    A.2.1.3, 7.3.2, 7.3.3.2;
///  • EN ISO 15614-1 — tab. 2 wyd. 2004+A2:2012 (BS EN ISO 15614-1:2004
///    +A2:2012); zmiana gr. 4–5 po obróbce 320 → 350 HV10 w wyd. 2017 wg
///    weldnote.com („ISO 15614-1 (2017) is out: Changes and Updates”);
///  • ASME B31.3 — tab. 331.1.1 wyd. 2008 (przedruk), usunięcie w wyd. 2014
///    wg komentarza D. Frikkena (Becht, „ASME B31.3 — Substantive Changes
///    to 2014 Edition”).
const List<HardnessLimitPreset> kHardnessLimitPresets = [
  HardnessLimitPreset(
    id: 'iso15156_weld',
    standard: HardnessStandard.iso15156,
    limit: HardnessLimit(HardnessScale.hv, 250),
    titlePl: 'Środowisko H2S — spoina od grani, SWC, materiał rodzimy',
    titleEn: 'Sour service H2S — weld root side, HAZ, base metal',
    sourcePl: '$_iso15156, tab. A.1 (HV10 lub HV5)',
    sourceEn: '$_iso15156, Table A.1 (HV10 or HV5)',
    notePl: 'Stal węglowa, C-Mn i niskostopowa. Równoważnie 70,6 HR15N. '
        '„248 HV” to przeliczenie 22 HRC wg ASTM E140 — dla spoin norma '
        'podaje 250 HV.',
    noteEn: 'Carbon, C-Mn and low-alloy steel. Equivalent 70.6 HR15N. '
        '“248 HV” is 22 HRC converted per ASTM E140 — for welds the '
        'standard gives 250 HV.',
  ),
  HardnessLimitPreset(
    id: 'iso15156_cap',
    standard: HardnessStandard.iso15156,
    limit: HardnessLimit(HardnessScale.hv, 275),
    titlePl: 'Środowisko H2S — lico nieeksponowane',
    titleEn: 'Sour service H2S — unexposed weld cap',
    sourcePl: '$_iso15156, tab. A.1, przypis a',
    sourceEn: '$_iso15156, Table A.1, footnote a',
    notePl: 'Tylko gdy spełnione wszystkie trzy: zgoda użytkownika '
        'urządzenia, materiał rodzimy grubszy niż 9 mm, lico nie styka się '
        'ze środowiskiem kwaśnym. Inaczej 250 HV.',
    noteEn: 'Only when all three apply: the equipment user agrees, parent '
        'material over 9 mm thick, the cap is not exposed to the sour '
        'environment. Otherwise 250 HV.',
  ),
  HardnessLimitPreset(
    id: 'iso15156_hrc',
    standard: HardnessStandard.iso15156,
    limit: HardnessLimit(HardnessScale.hrc, 22),
    titlePl: 'Środowisko H2S — pomiar HRC (spoina, materiał rodzimy)',
    titleEn: 'Sour service H2S — HRC test (weld, base metal)',
    sourcePl: '$_iso15156, tab. A.1 (metoda HRC) i A.2.1.2',
    sourceEn: '$_iso15156, Table A.1 (HRC method) and A.2.1.2',
    notePl: 'HRC dla spoin tylko na warunkach 7.3.3.2 (m.in. PWHT w WPS). '
        'Dla materiału rodzimego 7.3.2 dopuszcza pojedynczy odczyt do '
        '+2 HRC, gdy średnia pobliskich ≤ 22 HRC — tu każdy odczyt jest '
        'oceniany osobno (ostrzej).',
    noteEn: 'HRC on welds only under 7.3.3.2 (e.g. PWHT in the WPS). For '
        'base metal 7.3.2 allows a single reading up to +2 HRC when the '
        'average of nearby readings is ≤ 22 HRC — here every reading is '
        'judged on its own (stricter).',
  ),
  HardnessLimitPreset(
    id: 'iso15156_a105',
    standard: HardnessStandard.iso15156,
    limit: HardnessLimit(HardnessScale.hb, 187),
    titlePl: 'Środowisko H2S — odkuwki ASTM A105',
    titleEn: 'Sour service H2S — ASTM A105 forgings',
    sourcePl: '$_iso15156, A.2.1.3 a)',
    sourceEn: '$_iso15156, A.2.1.3 a)',
    notePl: 'HBW.',
    noteEn: 'HBW.',
  ),
  HardnessLimitPreset(
    id: 'iso15156_a234',
    standard: HardnessStandard.iso15156,
    limit: HardnessLimit(HardnessScale.hb, 197),
    titlePl: 'Środowisko H2S — kształtki ASTM A234 WPB/WPC',
    titleEn: 'Sour service H2S — ASTM A234 WPB/WPC fittings',
    sourcePl: '$_iso15156, A.2.1.3 b)',
    sourceEn: '$_iso15156, A.2.1.3 b)',
    notePl: 'HBW.',
    noteEn: 'HBW.',
  ),
  HardnessLimitPreset(
    id: 'iso15614_g12_aw',
    standard: HardnessStandard.iso15614,
    limit: HardnessLimit(HardnessScale.hv, 380),
    titlePl: 'WPQR — grupy 1 i 2, bez obróbki cieplnej',
    titleEn: 'WPQR — groups 1 and 2, not heat-treated',
    sourcePl: _iso15614Pl,
    sourceEn: _iso15614En,
    notePl: _iso15614NotePl,
    noteEn: _iso15614NoteEn,
  ),
  HardnessLimitPreset(
    id: 'iso15614_g12_ht',
    standard: HardnessStandard.iso15614,
    limit: HardnessLimit(HardnessScale.hv, 320),
    titlePl: 'WPQR — grupy 1 i 2, po obróbce cieplnej',
    titleEn: 'WPQR — groups 1 and 2, heat-treated',
    sourcePl: _iso15614Pl,
    sourceEn: _iso15614En,
    notePl: _iso15614NotePl,
    noteEn: _iso15614NoteEn,
  ),
  HardnessLimitPreset(
    id: 'iso15614_g3_aw',
    standard: HardnessStandard.iso15614,
    limit: HardnessLimit(HardnessScale.hv, 450),
    titlePl: 'WPQR — grupa 3, bez obróbki cieplnej',
    titleEn: 'WPQR — group 3, not heat-treated',
    sourcePl: _iso15614Pl,
    sourceEn: _iso15614En,
    notePl: 'Dla stali o min. Re > 890 MPa wartości ustala się osobno. '
        '$_iso15614NotePl',
    noteEn: 'For steels with min. yield > 890 MPa special values apply. '
        '$_iso15614NoteEn',
  ),
  HardnessLimitPreset(
    id: 'iso15614_g3_ht',
    standard: HardnessStandard.iso15614,
    limit: HardnessLimit(HardnessScale.hv, 380),
    titlePl: 'WPQR — grupa 3, po obróbce cieplnej',
    titleEn: 'WPQR — group 3, heat-treated',
    sourcePl: _iso15614Pl,
    sourceEn: _iso15614En,
    notePl: 'Dla stali o min. Re > 890 MPa wartości ustala się osobno. '
        '$_iso15614NotePl',
    noteEn: 'For steels with min. yield > 890 MPa special values apply. '
        '$_iso15614NoteEn',
  ),
  HardnessLimitPreset(
    id: 'iso15614_g45_aw',
    standard: HardnessStandard.iso15614,
    limit: HardnessLimit(HardnessScale.hv, 380),
    titlePl: 'WPQR — grupy 4 i 5, bez obróbki cieplnej',
    titleEn: 'WPQR — groups 4 and 5, not heat-treated',
    sourcePl: _iso15614Pl,
    sourceEn: _iso15614En,
    notePl: _iso15614NotePl,
    noteEn: _iso15614NoteEn,
  ),
  HardnessLimitPreset(
    id: 'iso15614_g45_ht',
    standard: HardnessStandard.iso15614,
    limit: HardnessLimit(HardnessScale.hv, 350),
    titlePl: 'WPQR — grupy 4 i 5, po obróbce cieplnej',
    titleEn: 'WPQR — groups 4 and 5, heat-treated',
    sourcePl: 'EN ISO 15614-1:2017, tabela maks. twardości HV10',
    sourceEn: 'EN ISO 15614-1:2017, maximum hardness HV10 table',
    notePl: 'Wyd. 2017 podniosło limit z 320 HV10 (wyd. 2004) do 350 HV10; '
        'wyższe wartości dopuszczalne, jeśli ustalono je przed próbą. '
        'Grupy wg ISO/TR 15608.',
    noteEn: 'The 2017 edition raised the limit from 320 HV10 (2004 edition) '
        'to 350 HV10; higher values are acceptable if specified before the '
        'test. Groups per ISO/TR 15608.',
  ),
  HardnessLimitPreset(
    id: 'b313_p3_p4',
    standard: HardnessStandard.asmeB313,
    limit: HardnessLimit(HardnessScale.hb, 225),
    titlePl: 'ASME B31.3 po PWHT — P-No 3 i 4',
    titleEn: 'ASME B31.3 after PWHT — P-No 3 and 4',
    sourcePl: _b313Pl,
    sourceEn: _b313En,
    notePl: _b313NotePl,
    noteEn: _b313NoteEn,
  ),
  HardnessLimitPreset(
    id: 'b313_p5_p6',
    standard: HardnessStandard.asmeB313,
    limit: HardnessLimit(HardnessScale.hb, 241),
    titlePl: 'ASME B31.3 po PWHT — P-No 5A, 5B, 5C i 6',
    titleEn: 'ASME B31.3 after PWHT — P-No 5A, 5B, 5C and 6',
    sourcePl: _b313Pl,
    sourceEn: _b313En,
    notePl: _b313NotePl,
    noteEn: _b313NoteEn,
  ),
];

HardnessLimitPreset? hardnessPresetById(String id) {
  for (final p in kHardnessLimitPresets) {
    if (p.id == id) return p;
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// OCENA POMIARÓW
// ═══════════════════════════════════════════════════════════════════════════

/// Jeden pomiar z serii. [value] `null` + [blank] — pole puste; `null` bez
/// [blank] — wpis nieczytelny.
class HardnessReading {
  final String location;
  final double? value;
  final HardnessScale scale;
  final bool blank;

  const HardnessReading({
    required this.location,
    required this.value,
    required this.scale,
    this.blank = false,
  });
}

enum ReadingStatus {
  /// ≤ limit (równość = OK).
  ok,

  /// > limit.
  exceeded,

  /// Poza zakresem tablicy przeliczeń — brak oceny (≠ OK).
  outOfRange,

  /// Stal nierdzewna, inna skala niż limit — nie przeliczamy (≠ OK).
  notConvertible,

  /// Wpis nieczytelny, ≤ 0 albo niefizyczny dla skali (≠ OK).
  invalid,

  /// Pole puste (≠ OK).
  blank,

  /// Limit nieprawidłowy — nie ma z czym porównać.
  noLimit,
}

/// `v` ≤ `limit` — ściśle, bez tolerancji (limit = wartość maksymalna,
/// równość = OK). Szum interpolacji usuwa wcześniej [_snap].
bool hardnessWithinLimit(double v, double limit) => v <= limit;

class ReadingCheck {
  final HardnessReading reading;
  final ReadingStatus status;

  /// Wartość w skali limitu (ta sama skala — wartość pomiaru; inna —
  /// przeliczona). `null`, gdy porównano w skali pomiaru albo brak oceny.
  final double? inLimitScale;

  /// Limit przeliczony na skalę pomiaru — gdy przeliczenie pomiaru na skalę
  /// limitu wypada poza tablicą (np. 200 HV przy limicie 22 HRC: HRC
  /// zaczyna się od 240 HV, ale 22 HRC = 248,9 HV da się porównać).
  final double? limitInReadingScale;

  /// Ocena wymagała przeliczenia skali (wynik przybliżony).
  final bool converted;

  const ReadingCheck({
    required this.reading,
    required this.status,
    this.inLimitScale,
    this.limitInReadingScale,
    this.converted = false,
  });

  bool get isOk => status == ReadingStatus.ok;
  bool get isExceeded => status == ReadingStatus.exceeded;
}

/// Ocena jednego pomiaru względem limitu (max).
ReadingCheck checkHardnessReading(
  HardnessReading reading,
  HardnessLimit limit, {
  HardnessMaterial material = HardnessMaterial.carbonLowAlloy,
}) {
  ReadingCheck result(ReadingStatus s, {double? inLimit, double? limitHere}) =>
      ReadingCheck(
          reading: reading,
          status: s,
          inLimitScale: inLimit,
          limitInReadingScale: limitHere,
          converted: (s == ReadingStatus.ok || s == ReadingStatus.exceeded) &&
              reading.scale != limit.scale);

  if (reading.blank) return result(ReadingStatus.blank);
  final v = reading.value;
  if (v == null || !v.isFinite || v <= 0 || v > reading.scale.maxPlausible) {
    return result(ReadingStatus.invalid);
  }
  if (!limit.isValid) return result(ReadingStatus.noLimit);

  if (reading.scale == limit.scale) {
    return result(
        hardnessWithinLimit(v, limit.value)
            ? ReadingStatus.ok
            : ReadingStatus.exceeded,
        inLimit: v);
  }
  if (material == HardnessMaterial.stainless) {
    return result(ReadingStatus.notConvertible);
  }
  // Pomiar musi leżeć w tablicy swojej skali — inaczej brak oceny, nawet
  // jeśli „na oko” jest daleko od limitu.
  if (!isInHardnessTable(v, reading.scale)) {
    return result(ReadingStatus.outOfRange);
  }
  final x = convertHardness(v, from: reading.scale, to: limit.scale);
  if (x != null) {
    return result(
        hardnessWithinLimit(x, limit.value)
            ? ReadingStatus.ok
            : ReadingStatus.exceeded,
        inLimit: x);
  }
  // Tablica jest monotoniczna: porównanie w skali pomiaru z limitem
  // przeliczonym na tę skalę jest równoważne — o ile limit leży w tablicy.
  final lm = convertHardness(limit.value, from: limit.scale, to: reading.scale);
  if (lm != null) {
    return result(
        hardnessWithinLimit(v, lm) ? ReadingStatus.ok : ReadingStatus.exceeded,
        limitHere: lm);
  }
  return result(ReadingStatus.outOfRange);
}

enum SeriesVerdict {
  /// Brak wpisanych pomiarów.
  empty,

  /// Limit ≤ 0, NaN albo spoza skali.
  invalidLimit,

  /// Wszystkie pomiary ocenione i ≤ limit — jedyny zielony stan.
  pass,

  /// Co najmniej jeden pomiar > limit.
  fail,

  /// Bez przekroczeń, ale nie wszystko ocenione (puste, nieczytelne, poza
  /// tablicą, nierdzewna w innej skali).
  incomplete,
}

class HardnessSeriesResult {
  final HardnessLimit limit;
  final List<ReadingCheck> checks;
  final SeriesVerdict verdict;

  /// Największa wartość w skali limitu spośród pomiarów, które dało się
  /// wyrazić w tej skali.
  final double? max;

  /// Średnia w skali limitu z tych samych pomiarów co [max].
  final double? mean;

  /// Ile pomiarów weszło do [max] / [mean].
  final int statsCount;

  /// Przekroczony pomiar, którego nie da się wyrazić w skali limitu —
  /// prawdziwe maksimum jest wtedy > limit, a [max] by to zaniżało.
  final bool maxAboveLimitUnknown;

  const HardnessSeriesResult({
    required this.limit,
    required this.checks,
    required this.verdict,
    required this.max,
    required this.mean,
    required this.statsCount,
    required this.maxAboveLimitUnknown,
  });

  int count(ReadingStatus s) => checks.where((c) => c.status == s).length;
  int get exceededCount => count(ReadingStatus.exceeded);
  int get okCount => count(ReadingStatus.ok);
  int get convertedCount => checks.where((c) => c.converted).length;

  /// Pomiary bez oceny (puste, nieczytelne, poza tablicą, bez przeliczenia).
  int get unratedCount => checks.length - okCount - exceededCount;
}

HardnessSeriesResult evaluateHardnessSeries(
  List<HardnessReading> readings,
  HardnessLimit limit, {
  HardnessMaterial material = HardnessMaterial.carbonLowAlloy,
}) {
  final checks = [
    for (final r in readings)
      checkHardnessReading(r, limit, material: material),
  ];
  final stats = [
    for (final c in checks)
      if (c.inLimitScale != null) c.inLimitScale!,
  ];
  double? max;
  double? mean;
  if (stats.isNotEmpty) {
    max = stats.reduce((a, b) => a > b ? a : b);
    mean = stats.reduce((a, b) => a + b) / stats.length;
  }
  final hiddenExceeded =
      checks.any((c) => c.isExceeded && c.inLimitScale == null);

  final SeriesVerdict verdict;
  if (!limit.isValid) {
    verdict = SeriesVerdict.invalidLimit;
  } else if (checks.every((c) => c.status == ReadingStatus.blank)) {
    verdict = SeriesVerdict.empty;
  } else if (checks.any((c) => c.isExceeded)) {
    verdict = SeriesVerdict.fail;
  } else if (checks.every((c) => c.isOk)) {
    verdict = SeriesVerdict.pass;
  } else {
    verdict = SeriesVerdict.incomplete;
  }
  return HardnessSeriesResult(
    limit: limit,
    checks: checks,
    verdict: verdict,
    max: max,
    mean: mean,
    statsCount: stats.length,
    maxAboveLimitUnknown: hiddenExceeded,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE (wspólne dla ekranu i protokołu)
// ═══════════════════════════════════════════════════════════════════════════

enum RoundDir { nearest, down, up }

/// [v] zaokrąglone do [decimals] miejsc w wybraną stronę. Mnożenie przez
/// 10ⁿ ma błąd rzędu 1e-12 — korekta ±1e-9, żeby 2,3 nie dało „2,29”.
double roundHardness(double v, int decimals, RoundDir dir) {
  var f = 1.0;
  for (var i = 0; i < decimals; i++) {
    f *= 10;
  }
  final s = v * f;
  final r = switch (dir) {
    RoundDir.nearest => s.roundToDouble(),
    RoundDir.down => (s + 1e-9).floorToDouble(),
    RoundDir.up => (s - 1e-9).ceilToDouble(),
  };
  return r / f;
}

String _sep(String s, bool en) => en ? s : s.replaceAll('.', ',');

/// Liczba ze stałą liczbą miejsc (przecinek w PL).
String formatHardnessNumber(double v,
        {int decimals = 1, RoundDir dir = RoundDir.nearest, bool en = false}) =>
    _sep(roundHardness(v, decimals, dir).toStringAsFixed(decimals), en);

/// Wartość „tak jak wpisana” — najkrótszy zapis tej liczby, bez zbędnych
/// zer i BEZ zaokrąglania (limit, odczyt). 250,00001 zostaje 250,00001, nie
/// „250” obok werdyktu „przekroczony”.
String formatHardnessExact(double v, {bool en = false}) {
  if (!v.isFinite) return '—';
  var s = v.toString();
  if (s.contains('e') || s.contains('E')) {
    // Wykładnik (absurdalnie mała/duża wartość) — zapis dziesiętny.
    s = v.toStringAsFixed(12).replaceFirst(RegExp(r'\.?0+$'), '');
  } else if (s.endsWith('.0')) {
    s = s.substring(0, s.length - 2);
  }
  return _sep(s, en);
}

/// Wartość pokazywana obok werdyktu: 1 miejsce, zaokrąglone W STRONĘ
/// werdyktu — powyżej limitu w górę, w limicie w dół. Dzięki temu
/// 250,04 HV przy limicie 250 to „250,1”, a nie „250,0”, a 249,96 to
/// „249,9”, a nie „250,0”. Gdyby jedno miejsce nie wystarczyło (wartość
/// o włos ponad limit), miejsc przybywa, aż relacja jest widoczna.
String formatAgainstLimit(double v, double limit, {bool en = false}) {
  final within = hardnessWithinLimit(v, limit);
  for (var d = 1; d <= 9; d++) {
    final shown = roundHardness(v, d, within ? RoundDir.down : RoundDir.up);
    if (within ? shown <= limit : shown > limit) {
      return formatHardnessNumber(v,
          decimals: d, dir: within ? RoundDir.down : RoundDir.up, en: en);
    }
  }
  return formatHardnessExact(v, en: en);
}

/// Limit przeliczony na skalę pomiaru, pokazywany obok werdyktu pomiaru
/// [measured]: przy OK w górę (pomiar ≤ pokazany limit), przy przekroczeniu
/// w dół (pomiar > pokazany limit).
String formatLimitEquivalent(double limitHere, double measured,
    {bool en = false}) {
  final within = hardnessWithinLimit(measured, limitHere);
  for (var d = 1; d <= 9; d++) {
    final shown =
        roundHardness(limitHere, d, within ? RoundDir.up : RoundDir.down);
    if (within ? measured <= shown : measured > shown) {
      return formatHardnessNumber(limitHere,
          decimals: d, dir: within ? RoundDir.up : RoundDir.down, en: en);
    }
  }
  return formatHardnessExact(limitHere, en: en);
}
