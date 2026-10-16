/// Tabele kształtowników stalowych: masa 1 m, wymiary przekroju,
/// powierzchnia malowania. Czysty Dart.
///
/// Liczby w tabelach przepisane MASZYNOWO ze źródła (skrypt czytał tabele
/// HTML / JSON i wypisywał wiersze — bez ręcznego przepisywania) i
/// porównane z drugim, niezależnym źródłem; wiersze, które ma tylko jedno
/// źródło (np. grubości kątowników tylko z programu ArcelorMittal), są
/// sprawdzone wzorem pola przekroju z normy (test spójności z geometrią).
/// Źródło każdej serii — w komentarzu nad tabelą. Masy nominalne dla
/// gęstości 7850 kg/m³ (podstawa tablic EN 10365 / EN 10056-1 /
/// EN 10219-2); rzeczywista masa wyrobu mieści się w tolerancji normy.
///
/// POMINIĘTE: teowniki T (EN 10055) — brak drugiego źródła; HEAA / IPE A /
/// IPE O / HL / HD — poza zakresem modułu; kątowniki 250×250 (poza ×28 i
/// ×35) i 300×300 — rzadkie, tylko jedno źródło; profile zamknięte
/// gorącowalcowane EN 10210 (wybrano zimnogięte EN 10219, które dominują
/// w hurtowniach; własny wymiar liczy wzór EN 10219-2).
library;

import 'dart:math' as math;

/// Rodzaj wyrobu wybierany w module.
enum SteelShape {
  ipe,
  hea,
  heb,
  hem,
  upn,
  upe,
  angleEqual,
  angleUnequal,
  hollow,
  flat,
  roundBar,
  squareBar,
  plate;

  /// Masa z tabeli kształtowników walcowanych (a nie z geometrii).
  bool get tabulated => index <= angleUnequal.index;

  /// Profil, dla którego podaje się długość pręta (blacha ma wymiary arkusza).
  bool get hasLength => this != plate;
}

/// Rodzina przekroju — decyduje o znaczeniu wymiarów.
enum SectionFamily { iBeam, channel, angle }

/// Skąd pochodzi powierzchnia malowania.
enum PaintSource {
  /// Z tabeli (obwód P / AL ze źródła serii).
  table,

  /// Obliczona z geometrii przekroju (krawędzie zewnętrzne ostre, promienie
  /// r1/r2 jak w normie) — UPE, kątowniki, profile zamknięte.
  geometry,

  /// Brak pewnej wartości — nie pokazujemy.
  none,
}

/// Jeden wiersz tabeli kształtownika walcowanego.
///
/// Wymiary w mm: dwuteownik / ceownik — h wysokość, b szerokość stopki,
/// tw grubość środnika, tf grubość stopki, r1 promień wyokrąglenia;
/// kątownik — h ramię a, b ramię b, tw = tf = t grubość, r1 promień
/// wewnętrzny (przy grani), r2 promień końca ramienia.
class SteelSection {
  final String name;
  final SectionFamily family;

  /// Masa 1 m [kg/m] z tabeli (stal 7850 kg/m³).
  final double kgPerM;
  final double h;
  final double b;
  final double tw;
  final double tf;
  final double r1;
  final double? r2;
  final double? _paintTable;
  final PaintSource paintSource;

  /// Dwuteownik IPE / HE: powierzchnia malowania z tabeli.
  const SteelSection.beam(this.name, this.kgPerM, this.h, this.b, this.tw,
      this.tf, this.r1, double paintM2PerM)
      : family = SectionFamily.iBeam,
        r2 = null,
        _paintTable = paintM2PerM,
        paintSource = PaintSource.table;

  /// Ceownik UPN (półki zbieżne): powierzchnia z tabeli albo brak.
  const SteelSection.channel(this.name, this.kgPerM, this.h, this.b, this.tw,
      this.tf, this.r1, double? paintM2PerM)
      : family = SectionFamily.channel,
        r2 = null,
        _paintTable = paintM2PerM,
        paintSource =
            paintM2PerM == null ? PaintSource.none : PaintSource.table;

  /// Ceownik UPE (półki równoległe): powierzchnia z geometrii.
  const SteelSection.upe(
      this.name, this.kgPerM, this.h, this.b, this.tw, this.tf, this.r1)
      : family = SectionFamily.channel,
        r2 = null,
        _paintTable = null,
        paintSource = PaintSource.geometry;

  /// Kątownik równo- lub nierównoramienny (EN 10056-1).
  const SteelSection.angle(
      this.name, this.kgPerM, this.h, this.b, double t, this.r1, double this.r2)
      : family = SectionFamily.angle,
        tw = t,
        tf = t,
        _paintTable = null,
        paintSource = PaintSource.geometry;

  /// Grubość kątownika.
  double get t => tw;

  /// Powierzchnia malowania [m²/m] albo null, gdy brak pewnej wartości.
  double? get paintM2PerM {
    switch (paintSource) {
      case PaintSource.table:
        return _paintTable;
      case PaintSource.none:
        return null;
      case PaintSource.geometry:
        const fillet = 2 - math.pi / 2; // ćwiartka: 2r prostych → πr/2 łuku
        if (family == SectionFamily.angle) {
          // Obrys kątownika 2(a + b), minus zaokrąglenie przy grani (r1)
          // i dwa na końcach ramion (r2).
          return (2 * (h + b) - fillet * (r1 + 2 * r2!)) / 1000;
        }
        // Ceownik z półkami równoległymi: 2h + 4b − 2tw, dwa promienie r1.
        return (2 * h + 4 * b - 2 * tw - 2 * fillet * r1) / 1000;
    }
  }
}

// ─── Dwuteowniki IPE, HEA, HEB, HEM ─────────────────────────────────────────
//
// Norma: EN 10365:2017 (wymiary i masy), dawniej Euronorm 19-57 / 53-62.
// Źródło 1 (przepisane): eurocodeapplied.com — „IPE, HEA, HEB, HEM design
//   properties", kolumny h, b, tw, tf, r, m [kg/m], P [m] (obwód = m²/m
//   malowania), https://eurocodeapplied.com/design/en1993/ipe-hea-heb-hem-design-properties
//   (pobrane 2026-10-17).
// Źródło 2 (sprawdzenie): ArcelorMittal Sections — dane BIM (h, b, tw, tf,
//   r1, G, A; pole „manufacturer: ArcelorMittal", odnośnik
//   https://sections.arcelormittal.com/design_aid/BIM/EN). Eksport JSON
//   generatora tabel BIM ArcelorMittal, pobrany z jego serwera testowego
//   https://test.hybrid.pl/arcelormittal/orangebook_gen/ (tabele ipe, he,
//   upn, upe, eq_leg, uneq_leg; 2026-10-17) — dalej „dane BIM AM".
//   Wszystkie 90 wierszy zgodne co do h, b, tw, tf, r, masy i pola
//   przekroju. Dodatkowo test: masa = A(geometria)·7850 w ±0,5 %.
// Kolumny: nazwa, kg/m, h, b, tw, tf, r, powierzchnia m²/m.

const List<SteelSection> kIpe = [
  SteelSection.beam('IPE 80', 6.0, 80.0, 46.0, 3.8, 5.2, 5.0, 0.328),
  SteelSection.beam('IPE 100', 8.1, 100.0, 55.0, 4.1, 5.7, 7.0, 0.4),
  SteelSection.beam('IPE 120', 10.4, 120.0, 64.0, 4.4, 6.3, 7.0, 0.475),
  SteelSection.beam('IPE 140', 12.9, 140.0, 73.0, 4.7, 6.9, 7.0, 0.551),
  SteelSection.beam('IPE 160', 15.8, 160.0, 82.0, 5.0, 7.4, 9.0, 0.623),
  SteelSection.beam('IPE 180', 18.8, 180.0, 91.0, 5.3, 8.0, 9.0, 0.698),
  SteelSection.beam('IPE 200', 22.4, 200.0, 100.0, 5.6, 8.5, 12.0, 0.768),
  SteelSection.beam('IPE 220', 26.2, 220.0, 110.0, 5.9, 9.2, 12.0, 0.848),
  SteelSection.beam('IPE 240', 30.7, 240.0, 120.0, 6.2, 9.8, 15.0, 0.922),
  SteelSection.beam('IPE 270', 36.1, 270.0, 135.0, 6.6, 10.2, 15.0, 1.041),
  SteelSection.beam('IPE 300', 42.2, 300.0, 150.0, 7.1, 10.7, 15.0, 1.16),
  SteelSection.beam('IPE 330', 49.1, 330.0, 160.0, 7.5, 11.5, 18.0, 1.254),
  SteelSection.beam('IPE 360', 57.1, 360.0, 170.0, 8.0, 12.7, 18.0, 1.353),
  SteelSection.beam('IPE 400', 66.3, 400.0, 180.0, 8.6, 13.5, 21.0, 1.467),
  SteelSection.beam('IPE 450', 77.6, 450.0, 190.0, 9.4, 14.6, 21.0, 1.605),
  SteelSection.beam('IPE 500', 90.7, 500.0, 200.0, 10.2, 16.0, 21.0, 1.744),
  SteelSection.beam('IPE 550', 105.5, 550.0, 210.0, 11.1, 17.2, 24.0, 1.877),
  SteelSection.beam('IPE 600', 122.4, 600.0, 220.0, 12.0, 19.0, 24.0, 2.015),
];

const List<SteelSection> kHea = [
  SteelSection.beam('HEA 100', 16.7, 96.0, 100.0, 5.0, 8.0, 12.0, 0.561),
  SteelSection.beam('HEA 120', 19.9, 114.0, 120.0, 5.0, 8.0, 12.0, 0.677),
  SteelSection.beam('HEA 140', 24.7, 133.0, 140.0, 5.5, 8.5, 12.0, 0.794),
  SteelSection.beam('HEA 160', 30.4, 152.0, 160.0, 6.0, 9.0, 15.0, 0.906),
  SteelSection.beam('HEA 180', 35.5, 171.0, 180.0, 6.0, 9.5, 15.0, 1.024),
  SteelSection.beam('HEA 200', 42.3, 190.0, 200.0, 6.5, 10.0, 18.0, 1.136),
  SteelSection.beam('HEA 220', 50.5, 210.0, 220.0, 7.0, 11.0, 18.0, 1.255),
  SteelSection.beam('HEA 240', 60.3, 230.0, 240.0, 7.5, 12.0, 21.0, 1.369),
  SteelSection.beam('HEA 260', 68.2, 250.0, 260.0, 7.5, 12.5, 24.0, 1.484),
  SteelSection.beam('HEA 280', 76.4, 270.0, 280.0, 8.0, 13.0, 24.0, 1.603),
  SteelSection.beam('HEA 300', 88.3, 290.0, 300.0, 8.5, 14.0, 27.0, 1.717),
  SteelSection.beam('HEA 320', 97.6, 310.0, 300.0, 9.0, 15.5, 27.0, 1.756),
  SteelSection.beam('HEA 340', 104.8, 330.0, 300.0, 9.5, 16.5, 27.0, 1.795),
  SteelSection.beam('HEA 360', 112.1, 350.0, 300.0, 10.0, 17.5, 27.0, 1.834),
  SteelSection.beam('HEA 400', 124.8, 390.0, 300.0, 11.0, 19.0, 27.0, 1.912),
  SteelSection.beam('HEA 450', 139.8, 440.0, 300.0, 11.5, 21.0, 27.0, 2.011),
  SteelSection.beam('HEA 500', 155.1, 490.0, 300.0, 12.0, 23.0, 27.0, 2.11),
  SteelSection.beam('HEA 550', 166.2, 540.0, 300.0, 12.5, 24.0, 27.0, 2.209),
  SteelSection.beam('HEA 600', 177.8, 590.0, 300.0, 13.0, 25.0, 27.0, 2.308),
  SteelSection.beam('HEA 650', 189.7, 640.0, 300.0, 13.5, 26.0, 27.0, 2.407),
  SteelSection.beam('HEA 700', 204.5, 690.0, 300.0, 14.5, 27.0, 27.0, 2.505),
  SteelSection.beam('HEA 800', 224.4, 790.0, 300.0, 15.0, 28.0, 30.0, 2.698),
  SteelSection.beam('HEA 900', 251.6, 890.0, 300.0, 16.0, 30.0, 30.0, 2.896),
  SteelSection.beam('HEA 1000', 272.3, 990.0, 300.0, 16.5, 31.0, 30.0, 3.095),
];

const List<SteelSection> kHeb = [
  SteelSection.beam('HEB 100', 20.4, 100.0, 100.0, 6.0, 10.0, 12.0, 0.567),
  SteelSection.beam('HEB 120', 26.7, 120.0, 120.0, 6.5, 11.0, 12.0, 0.686),
  SteelSection.beam('HEB 140', 33.7, 140.0, 140.0, 7.0, 12.0, 12.0, 0.805),
  SteelSection.beam('HEB 160', 42.6, 160.0, 160.0, 8.0, 13.0, 15.0, 0.918),
  SteelSection.beam('HEB 180', 51.2, 180.0, 180.0, 8.5, 14.0, 15.0, 1.037),
  SteelSection.beam('HEB 200', 61.3, 200.0, 200.0, 9.0, 15.0, 18.0, 1.151),
  SteelSection.beam('HEB 220', 71.5, 220.0, 220.0, 9.5, 16.0, 18.0, 1.27),
  SteelSection.beam('HEB 240', 83.2, 240.0, 240.0, 10.0, 17.0, 21.0, 1.384),
  SteelSection.beam('HEB 260', 93.0, 260.0, 260.0, 10.0, 17.5, 24.0, 1.499),
  SteelSection.beam('HEB 280', 103.1, 280.0, 280.0, 10.5, 18.0, 24.0, 1.618),
  SteelSection.beam('HEB 300', 117.0, 300.0, 300.0, 11.0, 19.0, 27.0, 1.732),
  SteelSection.beam('HEB 320', 126.7, 320.0, 300.0, 11.5, 20.5, 27.0, 1.771),
  SteelSection.beam('HEB 340', 134.2, 340.0, 300.0, 12.0, 21.5, 27.0, 1.81),
  SteelSection.beam('HEB 360', 141.8, 360.0, 300.0, 12.5, 22.5, 27.0, 1.849),
  SteelSection.beam('HEB 400', 155.3, 400.0, 300.0, 13.5, 24.0, 27.0, 1.927),
  SteelSection.beam('HEB 450', 171.1, 450.0, 300.0, 14.0, 26.0, 27.0, 2.026),
  SteelSection.beam('HEB 500', 187.3, 500.0, 300.0, 14.5, 28.0, 27.0, 2.125),
  SteelSection.beam('HEB 550', 199.4, 550.0, 300.0, 15.0, 29.0, 27.0, 2.224),
  SteelSection.beam('HEB 600', 211.9, 600.0, 300.0, 15.5, 30.0, 27.0, 2.323),
  SteelSection.beam('HEB 650', 224.8, 650.0, 300.0, 16.0, 31.0, 27.0, 2.422),
  SteelSection.beam('HEB 700', 240.5, 700.0, 300.0, 17.0, 32.0, 27.0, 2.52),
  SteelSection.beam('HEB 800', 262.3, 800.0, 300.0, 17.5, 33.0, 30.0, 2.713),
  SteelSection.beam('HEB 900', 291.5, 900.0, 300.0, 18.5, 35.0, 30.0, 2.911),
  SteelSection.beam('HEB 1000', 314.0, 1000.0, 300.0, 19.0, 36.0, 30.0, 3.11),
];

const List<SteelSection> kHem = [
  SteelSection.beam('HEM 100', 41.8, 120.0, 106.0, 12.0, 20.0, 12.0, 0.619),
  SteelSection.beam('HEM 120', 52.1, 140.0, 126.0, 12.5, 21.0, 12.0, 0.738),
  SteelSection.beam('HEM 140', 63.2, 160.0, 146.0, 13.0, 22.0, 12.0, 0.857),
  SteelSection.beam('HEM 160', 76.2, 180.0, 166.0, 14.0, 23.0, 15.0, 0.97),
  SteelSection.beam('HEM 180', 88.9, 200.0, 186.0, 14.5, 24.0, 15.0, 1.089),
  SteelSection.beam('HEM 200', 103.1, 220.0, 206.0, 15.0, 25.0, 18.0, 1.203),
  SteelSection.beam('HEM 220', 117.3, 240.0, 226.0, 15.5, 26.0, 18.0, 1.322),
  SteelSection.beam('HEM 240', 156.7, 270.0, 248.0, 18.0, 32.0, 21.0, 1.46),
  SteelSection.beam('HEM 260', 172.4, 290.0, 268.0, 18.0, 32.5, 24.0, 1.575),
  SteelSection.beam('HEM 280', 188.5, 310.0, 288.0, 18.5, 33.0, 24.0, 1.694),
  SteelSection.beam('HEM 300', 237.9, 340.0, 310.0, 21.0, 39.0, 27.0, 1.832),
  SteelSection.beam('HEM 320', 245.0, 359.0, 309.0, 21.0, 40.0, 27.0, 1.866),
  SteelSection.beam('HEM 340', 247.9, 377.0, 309.0, 21.0, 40.0, 27.0, 1.902),
  SteelSection.beam('HEM 360', 250.3, 395.0, 308.0, 21.0, 40.0, 27.0, 1.934),
  SteelSection.beam('HEM 400', 255.7, 432.0, 307.0, 21.0, 40.0, 27.0, 2.004),
  SteelSection.beam('HEM 450', 263.3, 478.0, 307.0, 21.0, 40.0, 27.0, 2.096),
  SteelSection.beam('HEM 500', 270.3, 524.0, 306.0, 21.0, 40.0, 27.0, 2.184),
  SteelSection.beam('HEM 550', 278.2, 572.0, 306.0, 21.0, 40.0, 27.0, 2.28),
  SteelSection.beam('HEM 600', 285.5, 620.0, 305.0, 21.0, 40.0, 27.0, 2.372),
  SteelSection.beam('HEM 650', 293.4, 668.0, 305.0, 21.0, 40.0, 27.0, 2.468),
  SteelSection.beam('HEM 700', 300.7, 716.0, 304.0, 21.0, 40.0, 27.0, 2.56),
  SteelSection.beam('HEM 800', 317.3, 814.0, 303.0, 21.0, 40.0, 30.0, 2.746),
  SteelSection.beam('HEM 900', 332.5, 910.0, 302.0, 21.0, 40.0, 30.0, 2.934),
  SteelSection.beam('HEM 1000', 348.7, 1008.0, 302.0, 21.0, 40.0, 30.0, 3.13),
];

// ─── Ceowniki UPN (półki zbieżne) ───────────────────────────────────────────
//
// Norma: EN 10365:2017 (wymiary DIN 1026-1, tolerancje EN 10279).
// Masy i wymiary: dane BIM AM (jw.);
//   sprawdzone z: STAD „Technical data of sections UPN"
//   (https://www.stad.fr/downloads/pdf/stad-technical-data-of-sections-upn.pdf)
//   i Kocaer Steel „UPN Channel" (DIN 1026-1). UPN 80: 8,65 kg/m wg katalogu
//   ArcelorMittal (A = 11,02 cm²; BIM zaokrągla do 8,6). r1 = tf (DIN 1026-1).
// Powierzchnia AL [m²/m]: katalog ArcelorMittal „Fers U normaux européens /
//   European standard channels" (Sales programme, kolumny AL i AG, UPN
//   80–400), kopia: https://fr.slideshare.net/slideshow/euro-upn/8056906 —
//   AL/G ≈ AG w każdym wierszu. Zgodne z obwodem z geometrii w ±2,5 %
//   (przybliżenie bez zbieżności półek). Dla UPN 50 i 65 źródło nie
//   podaje — pole puste.
//   UWAGA: ArcelorMittal Orange Book (wersja UK) podaje dla UPN mniejsze
//   „surface area" (np. UPN 200: 0,599) — niezgodne z obwodem przekroju
//   (≈ 0,66 m²/m z geometrii), więc NIE użyte.

const List<SteelSection> kUpn = [
  SteelSection.channel('UPN 50', 5.6, 50.0, 38.0, 5.0, 7.0, 7.0, null),
  SteelSection.channel('UPN 65', 7.1, 65.0, 42.0, 5.5, 7.5, 7.5, null),
  SteelSection.channel('UPN 80', 8.65, 80.0, 45.0, 6.0, 8.0, 8.0, 0.321),
  SteelSection.channel('UPN 100', 10.6, 100.0, 50.0, 6.0, 8.5, 8.5, 0.372),
  SteelSection.channel('UPN 120', 13.4, 120.0, 55.0, 7.0, 9.0, 9.0, 0.434),
  SteelSection.channel('UPN 140', 16.0, 140.0, 60.0, 7.0, 10.0, 10.0, 0.489),
  SteelSection.channel('UPN 160', 18.8, 160.0, 65.0, 7.5, 10.5, 10.5, 0.546),
  SteelSection.channel('UPN 180', 22.0, 180.0, 70.0, 8.0, 11.0, 11.0, 0.611),
  SteelSection.channel('UPN 200', 25.3, 200.0, 75.0, 8.5, 11.5, 11.5, 0.661),
  SteelSection.channel('UPN 220', 29.4, 220.0, 80.0, 9.0, 12.5, 12.5, 0.718),
  SteelSection.channel('UPN 240', 33.2, 240.0, 85.0, 9.5, 13.0, 13.0, 0.775),
  SteelSection.channel('UPN 260', 37.9, 260.0, 90.0, 10.0, 14.0, 14.0, 0.834),
  SteelSection.channel('UPN 280', 41.8, 280.0, 95.0, 10.0, 15.0, 15.0, 0.89),
  SteelSection.channel('UPN 300', 46.2, 300.0, 100.0, 10.0, 16.0, 16.0, 0.95),
  SteelSection.channel('UPN 320', 59.5, 320.0, 100.0, 14.0, 17.5, 17.5, 0.982),
  SteelSection.channel('UPN 350', 60.6, 350.0, 100.0, 14.0, 16.0, 16.0, 1.047),
  SteelSection.channel('UPN 380', 63.1, 380.0, 102.0, 13.5, 16.0, 16.0, 1.11),
  SteelSection.channel('UPN 400', 71.8, 400.0, 110.0, 14.0, 18.0, 18.0, 1.182),
];

// ─── Ceowniki UPE (półki równoległe) ────────────────────────────────────────
//
// Norma: EN 10365:2017 (dawniej DIN 1026-2).
// Masy i wymiary: dane BIM AM (jw., przy IPE/HE);
//   sprawdzone z: STAD „Technical data of sections UPE"
//   (https://www.stad.fr/downloads/pdf/stad-technical-data-of-sections-upe.pdf)
//   — zgodne, poza zaokrągleniem UPE 140 (14,4) i UPE 400 (72,1).
// Powierzchnia malowania: z geometrii (2h + 4b − 2tw − 2 wyokrąglenia r1).

const List<SteelSection> kUpe = [
  SteelSection.upe('UPE 80', 7.9, 80.0, 50.0, 4.0, 7.0, 10.0),
  SteelSection.upe('UPE 100', 9.8, 100.0, 55.0, 4.5, 7.5, 10.0),
  SteelSection.upe('UPE 120', 12.1, 120.0, 60.0, 5.0, 8.0, 12.0),
  SteelSection.upe('UPE 140', 14.5, 140.0, 65.0, 5.0, 9.0, 12.0),
  SteelSection.upe('UPE 160', 17.0, 160.0, 70.0, 5.5, 9.5, 12.0),
  SteelSection.upe('UPE 180', 19.7, 180.0, 75.0, 5.5, 10.5, 12.0),
  SteelSection.upe('UPE 200', 22.8, 200.0, 80.0, 6.0, 11.0, 13.0),
  SteelSection.upe('UPE 220', 26.6, 220.0, 85.0, 6.5, 12.0, 13.0),
  SteelSection.upe('UPE 240', 30.2, 240.0, 90.0, 7.0, 12.5, 15.0),
  SteelSection.upe('UPE 270', 35.2, 270.0, 95.0, 7.5, 13.5, 15.0),
  SteelSection.upe('UPE 300', 44.4, 300.0, 100.0, 9.5, 15.0, 15.0),
  SteelSection.upe('UPE 330', 53.2, 330.0, 105.0, 11.0, 16.0, 18.0),
  SteelSection.upe('UPE 360', 61.2, 360.0, 110.0, 12.0, 17.0, 18.0),
  SteelSection.upe('UPE 400', 72.2, 400.0, 115.0, 13.5, 18.0, 18.0),
];

// ─── Kątowniki równoramienne L (EN 10056-1) ─────────────────────────────────
//
// Źródło 1: SCI / Steel for Life „Blue Book" — Equal leg angles (L),
//   BS EN 10056-1:2017, masa [kg/m], r1, r2,
//   https://www.steelforlifebluebook.co.uk/l-equal/ec3-ukna/section-properties-dimensions-properties
//   (oznaczone w komentarzu BB).
// Źródło 2: dane BIM AM (jw., przy IPE/HE; oznaczone AM). Wiersze w obu źródłach
//   (BB+AM) zgodne (L 200×200×18: BB 54,3 / AM 54,2 — przyjęto BB).
//   Wiersze tylko AM (grubości z programu ArcelorMittal): r2 = r1/2 jak
//   we wszystkich wierszach EN 10056-1 w Blue Book.
// Dodatkowo test: masa = A(geometria z r1, r2)·7850 w ±1 %.
// Powierzchnia malowania: z geometrii.

const List<SteelSection> kAngleEqual = [
  SteelSection.angle('L 20×20×3', 0.88, 20.0, 20.0, 3.0, 3.5, 1.75), // BB
  SteelSection.angle('L 25×25×3', 1.12, 25.0, 25.0, 3.0, 3.5, 1.75), // BB
  SteelSection.angle('L 25×25×4', 1.45, 25.0, 25.0, 4.0, 3.5, 1.75), // BB
  SteelSection.angle('L 30×30×3', 1.36, 30.0, 30.0, 3.0, 5.0, 2.5), // BB
  SteelSection.angle('L 30×30×4', 1.78, 30.0, 30.0, 4.0, 5.0, 2.5), // BB
  SteelSection.angle('L 35×35×4', 2.09, 35.0, 35.0, 4.0, 5.0, 2.5), // BB
  SteelSection.angle('L 40×40×4', 2.42, 40.0, 40.0, 4.0, 6.0, 3.0), // BB
  SteelSection.angle('L 40×40×5', 2.97, 40.0, 40.0, 5.0, 6.0, 3.0), // BB
  SteelSection.angle('L 45×45×4', 2.74, 45.0, 45.0, 4.0, 7.0, 3.5), // AM
  SteelSection.angle('L 45×45×4,5', 3.06, 45.0, 45.0, 4.5, 7.0, 3.5), // BB
  SteelSection.angle('L 50×50×4', 3.06, 50.0, 50.0, 4.0, 7.0, 3.5), // BB+AM
  SteelSection.angle('L 50×50×5', 3.77, 50.0, 50.0, 5.0, 7.0, 3.5), // BB+AM
  SteelSection.angle('L 50×50×6', 4.47, 50.0, 50.0, 6.0, 7.0, 3.5), // BB+AM
  SteelSection.angle('L 60×60×4', 3.7, 60.0, 60.0, 4.0, 8.0, 4.0), // AM
  SteelSection.angle('L 60×60×5', 4.57, 60.0, 60.0, 5.0, 8.0, 4.0), // BB+AM
  SteelSection.angle('L 60×60×6', 5.42, 60.0, 60.0, 6.0, 8.0, 4.0), // BB+AM
  SteelSection.angle('L 60×60×8', 7.09, 60.0, 60.0, 8.0, 8.0, 4.0), // BB+AM
  SteelSection.angle('L 65×65×7', 6.83, 65.0, 65.0, 7.0, 9.0, 4.5), // BB
  SteelSection.angle('L 70×70×6', 6.38, 70.0, 70.0, 6.0, 9.0, 4.5), // BB
  SteelSection.angle('L 70×70×7', 7.38, 70.0, 70.0, 7.0, 9.0, 4.5), // BB
  SteelSection.angle('L 75×75×4', 4.65, 75.0, 75.0, 4.0, 9.0, 4.5), // AM
  SteelSection.angle('L 75×75×5', 5.76, 75.0, 75.0, 5.0, 9.0, 4.5), // AM
  SteelSection.angle('L 75×75×6', 6.85, 75.0, 75.0, 6.0, 9.0, 4.5), // BB+AM
  SteelSection.angle('L 75×75×7', 7.93, 75.0, 75.0, 7.0, 9.0, 4.5), // AM
  SteelSection.angle('L 75×75×8', 8.99, 75.0, 75.0, 8.0, 9.0, 4.5), // BB+AM
  SteelSection.angle('L 75×75×10', 11.1, 75.0, 75.0, 10.0, 9.0, 4.5), // AM
  SteelSection.angle('L 80×80×5', 6.17, 80.0, 80.0, 5.0, 10.0, 5.0), // AM
  SteelSection.angle('L 80×80×6', 7.34, 80.0, 80.0, 6.0, 10.0, 5.0), // AM
  SteelSection.angle('L 80×80×7', 8.49, 80.0, 80.0, 7.0, 10.0, 5.0), // AM
  SteelSection.angle('L 80×80×8', 9.63, 80.0, 80.0, 8.0, 10.0, 5.0), // BB+AM
  SteelSection.angle('L 80×80×10', 11.9, 80.0, 80.0, 10.0, 10.0, 5.0), // BB+AM
  SteelSection.angle('L 90×90×6', 8.3, 90.0, 90.0, 6.0, 11.0, 5.5), // AM
  SteelSection.angle('L 90×90×7', 9.61, 90.0, 90.0, 7.0, 11.0, 5.5), // BB+AM
  SteelSection.angle('L 90×90×8', 10.9, 90.0, 90.0, 8.0, 11.0, 5.5), // BB+AM
  SteelSection.angle('L 90×90×9', 12.2, 90.0, 90.0, 9.0, 11.0, 5.5), // AM
  SteelSection.angle('L 90×90×10', 13.4, 90.0, 90.0, 10.0, 11.0, 5.5), // BB+AM
  SteelSection.angle('L 90×90×11', 14.7, 90.0, 90.0, 11.0, 11.0, 5.5), // AM
  SteelSection.angle('L 90×90×12', 15.9, 90.0, 90.0, 12.0, 11.0, 5.5), // BB
  SteelSection.angle('L 100×100×7', 10.7, 100.0, 100.0, 7.0, 12.0, 6.0), // AM
  SteelSection.angle(
      'L 100×100×8', 12.2, 100.0, 100.0, 8.0, 12.0, 6.0), // BB+AM
  SteelSection.angle(
      'L 100×100×10', 15.0, 100.0, 100.0, 10.0, 12.0, 6.0), // BB+AM
  SteelSection.angle(
      'L 100×100×12', 17.8, 100.0, 100.0, 12.0, 12.0, 6.0), // BB+AM
  SteelSection.angle('L 100×100×15', 21.9, 100.0, 100.0, 15.0, 12.0, 6.0), // BB
  SteelSection.angle(
      'L 120×120×8', 14.7, 120.0, 120.0, 8.0, 13.0, 6.5), // BB+AM
  SteelSection.angle(
      'L 120×120×10', 18.2, 120.0, 120.0, 10.0, 13.0, 6.5), // BB+AM
  SteelSection.angle('L 120×120×11', 19.9, 120.0, 120.0, 11.0, 13.0, 6.5), // AM
  SteelSection.angle(
      'L 120×120×12', 21.6, 120.0, 120.0, 12.0, 13.0, 6.5), // BB+AM
  SteelSection.angle('L 120×120×13', 23.3, 120.0, 120.0, 13.0, 13.0, 6.5), // AM
  SteelSection.angle(
      'L 120×120×15', 26.6, 120.0, 120.0, 15.0, 13.0, 6.5), // BB+AM
  SteelSection.angle('L 130×130×10', 19.8, 130.0, 130.0, 10.0, 14.0, 7.0), // AM
  SteelSection.angle('L 130×130×11', 21.7, 130.0, 130.0, 11.0, 14.0, 7.0), // AM
  SteelSection.angle('L 130×130×12', 23.6, 130.0, 130.0, 12.0, 14.0, 7.0), // AM
  SteelSection.angle('L 130×130×13', 25.4, 130.0, 130.0, 13.0, 14.0, 7.0), // AM
  SteelSection.angle('L 130×130×14', 27.2, 130.0, 130.0, 14.0, 14.0, 7.0), // AM
  SteelSection.angle('L 130×130×15', 29.0, 130.0, 130.0, 15.0, 14.0, 7.0), // AM
  SteelSection.angle('L 130×130×16', 30.8, 130.0, 130.0, 16.0, 14.0, 7.0), // AM
  SteelSection.angle('L 140×140×9', 19.3, 140.0, 140.0, 9.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×10', 21.4, 140.0, 140.0, 10.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×11', 23.4, 140.0, 140.0, 11.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×12', 25.4, 140.0, 140.0, 12.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×13', 27.5, 140.0, 140.0, 13.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×14', 29.4, 140.0, 140.0, 14.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×15', 31.4, 140.0, 140.0, 15.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×16', 33.3, 140.0, 140.0, 16.0, 15.0, 7.5), // AM
  SteelSection.angle('L 140×140×18', 37.2, 140.0, 140.0, 18.0, 15.0, 7.5), // AM
  SteelSection.angle(
      'L 150×150×10', 23.0, 150.0, 150.0, 10.0, 16.0, 8.0), // BB+AM
  SteelSection.angle(
      'L 150×150×12', 27.3, 150.0, 150.0, 12.0, 16.0, 8.0), // BB+AM
  SteelSection.angle('L 150×150×13', 29.5, 150.0, 150.0, 13.0, 16.0, 8.0), // AM
  SteelSection.angle('L 150×150×14', 31.6, 150.0, 150.0, 14.0, 16.0, 8.0), // AM
  SteelSection.angle(
      'L 150×150×15', 33.8, 150.0, 150.0, 15.0, 16.0, 8.0), // BB+AM
  SteelSection.angle('L 150×150×16', 35.9, 150.0, 150.0, 16.0, 16.0, 8.0), // AM
  SteelSection.angle(
      'L 150×150×18', 40.1, 150.0, 150.0, 18.0, 16.0, 8.0), // BB+AM
  SteelSection.angle('L 150×150×20', 44.2, 150.0, 150.0, 20.0, 16.0, 8.0), // AM
  SteelSection.angle('L 160×160×12', 29.3, 160.0, 160.0, 12.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×14', 33.9, 160.0, 160.0, 14.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×15', 36.2, 160.0, 160.0, 15.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×16', 38.4, 160.0, 160.0, 16.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×17', 40.7, 160.0, 160.0, 17.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×18', 42.9, 160.0, 160.0, 18.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×19', 45.1, 160.0, 160.0, 19.0, 17.0, 8.5), // AM
  SteelSection.angle('L 160×160×20', 47.3, 160.0, 160.0, 20.0, 17.0, 8.5), // AM
  SteelSection.angle('L 180×180×13', 35.7, 180.0, 180.0, 13.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×14', 38.3, 180.0, 180.0, 14.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×15', 40.9, 180.0, 180.0, 15.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×16', 43.5, 180.0, 180.0, 16.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×17', 46.0, 180.0, 180.0, 17.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×18', 48.6, 180.0, 180.0, 18.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×19', 51.1, 180.0, 180.0, 19.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×20', 53.7, 180.0, 180.0, 20.0, 18.0, 9.0), // AM
  SteelSection.angle('L 180×180×22', 58.6, 180.0, 180.0, 22.0, 18.0, 9.0), // AM
  SteelSection.angle('L 200×200×13', 39.8, 200.0, 200.0, 13.0, 18.0, 9.0), // AM
  SteelSection.angle('L 200×200×15', 45.6, 200.0, 200.0, 15.0, 18.0, 9.0), // AM
  SteelSection.angle(
      'L 200×200×16', 48.5, 200.0, 200.0, 16.0, 18.0, 9.0), // BB+AM
  SteelSection.angle('L 200×200×17', 51.4, 200.0, 200.0, 17.0, 18.0, 9.0), // AM
  SteelSection.angle(
      'L 200×200×18', 54.3, 200.0, 200.0, 18.0, 18.0, 9.0), // BB+AM
  SteelSection.angle('L 200×200×19', 57.1, 200.0, 200.0, 19.0, 18.0, 9.0), // AM
  SteelSection.angle(
      'L 200×200×20', 59.9, 200.0, 200.0, 20.0, 18.0, 9.0), // BB+AM
  SteelSection.angle('L 200×200×21', 62.8, 200.0, 200.0, 21.0, 18.0, 9.0), // AM
  SteelSection.angle('L 200×200×22', 65.6, 200.0, 200.0, 22.0, 18.0, 9.0), // AM
  SteelSection.angle('L 200×200×23', 68.3, 200.0, 200.0, 23.0, 18.0, 9.0), // AM
  SteelSection.angle(
      'L 200×200×24', 71.1, 200.0, 200.0, 24.0, 18.0, 9.0), // BB+AM
  SteelSection.angle('L 200×200×25', 73.9, 200.0, 200.0, 25.0, 18.0, 9.0), // AM
  SteelSection.angle('L 200×200×26', 76.6, 200.0, 200.0, 26.0, 18.0, 9.0), // AM
  SteelSection.angle('L 200×200×28', 82.0, 200.0, 200.0, 28.0, 18.0, 9.0), // AM
  SteelSection.angle(
      'L 250×250×28', 104.0, 250.0, 250.0, 28.0, 18.0, 9.0), // AM
  SteelSection.angle(
      'L 250×250×35', 128.0, 250.0, 250.0, 35.0, 18.0, 9.0), // AM
];

// ─── Kątowniki nierównoramienne L (EN 10056-1) ──────────────────────────────
//
// Źródło 1: SCI / Steel for Life „Blue Book" — Unequal leg angles (L),
//   BS EN 10056-1:2017,
//   https://www.steelforlifebluebook.co.uk/l-unequal/ec3-ukna/section-properties-dimensions-properties
// Źródło 2: dane BIM AM (L 120×80, 200×100, 250×90);
//   wspólne wiersze zgodne (L 200×100×15: BB 33,8 / AM 33,7 — przyjęto BB).
// Dodatkowo test: masa = A(geometria)·7850 w ±1 %.

const List<SteelSection> kAngleUnequal = [
  SteelSection.angle('L 30×20×3', 1.12, 30.0, 20.0, 3.0, 4.0, 2.0), // BB
  SteelSection.angle('L 30×20×4', 1.46, 30.0, 20.0, 4.0, 4.0, 2.0), // BB
  SteelSection.angle('L 40×20×4', 1.77, 40.0, 20.0, 4.0, 4.0, 2.0), // BB
  SteelSection.angle('L 40×25×4', 1.93, 40.0, 25.0, 4.0, 4.0, 2.0), // BB
  SteelSection.angle('L 45×30×4', 2.25, 45.0, 30.0, 4.0, 4.5, 2.25), // BB
  SteelSection.angle('L 50×30×5', 2.96, 50.0, 30.0, 5.0, 5.0, 2.5), // BB
  SteelSection.angle('L 60×30×5', 3.36, 60.0, 30.0, 5.0, 5.0, 2.5), // BB
  SteelSection.angle('L 60×40×5', 3.76, 60.0, 40.0, 5.0, 6.0, 3.0), // BB
  SteelSection.angle('L 60×40×6', 4.46, 60.0, 40.0, 6.0, 6.0, 3.0), // BB
  SteelSection.angle('L 65×50×5', 4.35, 65.0, 50.0, 5.0, 6.0, 3.0), // BB
  SteelSection.angle('L 70×50×6', 5.41, 70.0, 50.0, 6.0, 7.0, 3.5), // BB
  SteelSection.angle('L 75×50×6', 5.65, 75.0, 50.0, 6.0, 7.0, 3.5), // BB
  SteelSection.angle('L 75×50×8', 7.39, 75.0, 50.0, 8.0, 7.0, 3.5), // BB
  SteelSection.angle('L 80×40×6', 5.41, 80.0, 40.0, 6.0, 7.0, 3.5), // BB
  SteelSection.angle('L 80×40×8', 7.07, 80.0, 40.0, 8.0, 7.0, 3.5), // BB
  SteelSection.angle('L 80×60×7', 7.36, 80.0, 60.0, 7.0, 8.0, 4.0), // BB
  SteelSection.angle('L 100×50×6', 6.84, 100.0, 50.0, 6.0, 8.0, 4.0), // BB
  SteelSection.angle('L 100×50×8', 8.97, 100.0, 50.0, 8.0, 8.0, 4.0), // BB
  SteelSection.angle('L 100×65×7', 8.77, 100.0, 65.0, 7.0, 10.0, 5.0), // BB
  SteelSection.angle('L 100×65×8', 9.94, 100.0, 65.0, 8.0, 10.0, 5.0), // BB
  SteelSection.angle('L 100×65×10', 12.3, 100.0, 65.0, 10.0, 10.0, 5.0), // BB
  SteelSection.angle('L 100×75×8', 10.6, 100.0, 75.0, 8.0, 10.0, 5.0), // BB
  SteelSection.angle('L 100×75×10', 13.0, 100.0, 75.0, 10.0, 10.0, 5.0), // BB
  SteelSection.angle('L 100×75×12', 15.4, 100.0, 75.0, 12.0, 10.0, 5.0), // BB
  SteelSection.angle('L 120×80×8', 12.2, 120.0, 80.0, 8.0, 11.0, 5.5), // AM
  SteelSection.angle('L 120×80×10', 15.0, 120.0, 80.0, 10.0, 11.0, 5.5), // AM
  SteelSection.angle('L 120×80×12', 17.8, 120.0, 80.0, 12.0, 11.0, 5.5), // AM
  SteelSection.angle('L 125×75×8', 12.2, 125.0, 75.0, 8.0, 11.0, 5.5), // BB
  SteelSection.angle('L 125×75×10', 15.0, 125.0, 75.0, 10.0, 11.0, 5.5), // BB
  SteelSection.angle('L 125×75×12', 17.8, 125.0, 75.0, 12.0, 11.0, 5.5), // BB
  SteelSection.angle('L 150×75×10', 17.0, 150.0, 75.0, 10.0, 12.0, 6.0), // BB
  SteelSection.angle('L 150×75×12', 20.2, 150.0, 75.0, 12.0, 12.0, 6.0), // BB
  SteelSection.angle('L 150×75×15', 24.8, 150.0, 75.0, 15.0, 12.0, 6.0), // BB
  SteelSection.angle('L 150×90×10', 18.2, 150.0, 90.0, 10.0, 12.0, 6.0), // BB
  SteelSection.angle('L 150×90×12', 21.6, 150.0, 90.0, 12.0, 12.0, 6.0), // BB
  SteelSection.angle('L 150×90×15', 26.6, 150.0, 90.0, 15.0, 12.0, 6.0), // BB
  SteelSection.angle(
      'L 200×100×10', 23.0, 200.0, 100.0, 10.0, 15.0, 7.5), // BB+AM
  SteelSection.angle(
      'L 200×100×12', 27.3, 200.0, 100.0, 12.0, 15.0, 7.5), // BB+AM
  SteelSection.angle('L 200×100×14', 31.6, 200.0, 100.0, 14.0, 15.0, 7.5), // AM
  SteelSection.angle(
      'L 200×100×15', 33.8, 200.0, 100.0, 15.0, 15.0, 7.5), // BB+AM
  SteelSection.angle('L 200×100×16', 35.9, 200.0, 100.0, 16.0, 15.0, 7.5), // AM
  SteelSection.angle('L 200×150×12', 32.0, 200.0, 150.0, 12.0, 15.0, 7.5), // BB
  SteelSection.angle('L 200×150×15', 39.6, 200.0, 150.0, 15.0, 15.0, 7.5), // BB
  SteelSection.angle('L 200×150×18', 47.1, 200.0, 150.0, 18.0, 15.0, 7.5), // BB
  SteelSection.angle('L 250×90×12', 31.2, 250.0, 90.0, 12.0, 18.0, 9.0), // AM
  SteelSection.angle('L 250×90×14', 36.1, 250.0, 90.0, 14.0, 18.0, 9.0), // AM
  SteelSection.angle('L 250×90×16', 40.9, 250.0, 90.0, 16.0, 18.0, 9.0), // AM
];

// ─── Profile zamknięte zimnogięte SHS / RHS (EN 10219-2) ────────────────────
//
// METODA: masa i obwód LICZONE wzorem z EN 10219-2 (pole przekroju z
// naroży zaokrąglonych), z promieniami naroży przyjmowanymi do obliczeń
// w EN 10219-2:
//   t ≤ 6 mm:      ro = 2,0·t,  ri = 1,0·t
//   6 < t ≤ 10 mm: ro = 2,5·t,  ri = 1,5·t
//   t > 10 mm:     ro = 3,0·t,  ri = 2,0·t
//   A = 2t(H + B − 2t) − (4 − π)(ro² − ri²),  masa = A·ρ,
//   obwód zewn. = 2(H + B) − (8 − 2π)·ro.
// Lista wymiarów: suma tabel EN 10219-2 z eurocodeapplied.com
//   (https://eurocodeapplied.com/design/en1993/shs-design-properties i
//   /rhs-design-properties, „Cold formed") oraz SCI „Blue Book" (CFSHS,
//   CFRHS). Wzór odtwarza masy obu tabel w ±0,4 % (sprawdzone dla 179
//   wymiarów wspólnych), obwód zgodny z kolumną P eurocodeapplied.
// Krotki: (H, B, t) w mm; H = B → SHS.

/// Promienie naroży [mm] do obliczeń wg EN 10219-2.
({double ro, double ri}) en10219Radii(double t) {
  if (t <= 6) return (ro: 2.0 * t, ri: 1.0 * t);
  if (t <= 10) return (ro: 2.5 * t, ri: 1.5 * t);
  return (ro: 3.0 * t, ri: 2.0 * t);
}

/// Pole przekroju profilu zamkniętego [mm²] (EN 10219-2).
double hollowAreaMm2(double h, double b, double t) {
  final r = en10219Radii(t);
  return 2 * t * (h + b - 2 * t) - (4 - math.pi) * (r.ro * r.ro - r.ri * r.ri);
}

/// Obwód zewnętrzny profilu zamkniętego [mm] = powierzchnia malowania
/// na 1 m (w mm²/mm).
double hollowPerimeterMm(double h, double b, double t) {
  final r = en10219Radii(t);
  return 2 * (h + b) - (8 - 2 * math.pi) * r.ro;
}

/// Czy ścianka mieści się w przekroju (naroża zewnętrzne nie zachodzą na
/// siebie i zostaje światło w środku).
bool hollowGeometryOk(double h, double b, double t) {
  if (!(h > 0 && b > 0 && t > 0)) return false;
  final small = math.min(h, b);
  return 2 * t < small && 2 * en10219Radii(t).ro <= small;
}

const List<(double, double, double)> kHollowSizes = [
  (20.0, 20.0, 2.0),
  (25.0, 25.0, 2.0),
  (25.0, 25.0, 2.5),
  (25.0, 25.0, 3.0),
  (30.0, 30.0, 2.0),
  (30.0, 30.0, 2.5),
  (30.0, 30.0, 3.0),
  (40.0, 40.0, 2.0),
  (40.0, 40.0, 2.5),
  (40.0, 40.0, 3.0),
  (40.0, 40.0, 4.0),
  (50.0, 50.0, 2.0),
  (50.0, 50.0, 2.5),
  (50.0, 50.0, 3.0),
  (50.0, 50.0, 4.0),
  (50.0, 50.0, 5.0),
  (60.0, 60.0, 2.0),
  (60.0, 60.0, 2.5),
  (60.0, 60.0, 3.0),
  (60.0, 60.0, 4.0),
  (60.0, 60.0, 5.0),
  (60.0, 60.0, 6.0),
  (60.0, 60.0, 6.3),
  (70.0, 70.0, 2.5),
  (70.0, 70.0, 3.0),
  (70.0, 70.0, 3.5),
  (70.0, 70.0, 4.0),
  (70.0, 70.0, 5.0),
  (70.0, 70.0, 6.0),
  (70.0, 70.0, 6.3),
  (80.0, 80.0, 3.0),
  (80.0, 80.0, 3.5),
  (80.0, 80.0, 4.0),
  (80.0, 80.0, 5.0),
  (80.0, 80.0, 6.0),
  (80.0, 80.0, 6.3),
  (80.0, 80.0, 8.0),
  (90.0, 90.0, 3.0),
  (90.0, 90.0, 3.5),
  (90.0, 90.0, 4.0),
  (90.0, 90.0, 5.0),
  (90.0, 90.0, 6.0),
  (90.0, 90.0, 6.3),
  (90.0, 90.0, 8.0),
  (100.0, 100.0, 3.0),
  (100.0, 100.0, 4.0),
  (100.0, 100.0, 5.0),
  (100.0, 100.0, 6.0),
  (100.0, 100.0, 6.3),
  (100.0, 100.0, 8.0),
  (100.0, 100.0, 10.0),
  (100.0, 100.0, 12.0),
  (100.0, 100.0, 12.5),
  (120.0, 120.0, 3.0),
  (120.0, 120.0, 4.0),
  (120.0, 120.0, 5.0),
  (120.0, 120.0, 6.0),
  (120.0, 120.0, 6.3),
  (120.0, 120.0, 8.0),
  (120.0, 120.0, 10.0),
  (120.0, 120.0, 12.0),
  (120.0, 120.0, 12.5),
  (140.0, 140.0, 4.0),
  (140.0, 140.0, 5.0),
  (140.0, 140.0, 6.0),
  (140.0, 140.0, 6.3),
  (140.0, 140.0, 8.0),
  (140.0, 140.0, 10.0),
  (140.0, 140.0, 12.0),
  (140.0, 140.0, 12.5),
  (150.0, 150.0, 4.0),
  (150.0, 150.0, 5.0),
  (150.0, 150.0, 6.0),
  (150.0, 150.0, 6.3),
  (150.0, 150.0, 8.0),
  (150.0, 150.0, 10.0),
  (150.0, 150.0, 12.0),
  (150.0, 150.0, 12.5),
  (150.0, 150.0, 16.0),
  (160.0, 160.0, 4.0),
  (160.0, 160.0, 5.0),
  (160.0, 160.0, 6.0),
  (160.0, 160.0, 6.3),
  (160.0, 160.0, 8.0),
  (160.0, 160.0, 10.0),
  (160.0, 160.0, 12.0),
  (160.0, 160.0, 12.5),
  (160.0, 160.0, 16.0),
  (180.0, 180.0, 4.0),
  (180.0, 180.0, 5.0),
  (180.0, 180.0, 6.0),
  (180.0, 180.0, 6.3),
  (180.0, 180.0, 8.0),
  (180.0, 180.0, 10.0),
  (180.0, 180.0, 12.0),
  (180.0, 180.0, 12.5),
  (180.0, 180.0, 16.0),
  (200.0, 200.0, 4.0),
  (200.0, 200.0, 5.0),
  (200.0, 200.0, 6.0),
  (200.0, 200.0, 6.3),
  (200.0, 200.0, 8.0),
  (200.0, 200.0, 10.0),
  (200.0, 200.0, 12.0),
  (200.0, 200.0, 12.5),
  (200.0, 200.0, 16.0),
  (220.0, 220.0, 5.0),
  (220.0, 220.0, 6.0),
  (220.0, 220.0, 6.3),
  (220.0, 220.0, 8.0),
  (220.0, 220.0, 10.0),
  (220.0, 220.0, 12.0),
  (220.0, 220.0, 12.5),
  (220.0, 220.0, 16.0),
  (250.0, 250.0, 5.0),
  (250.0, 250.0, 6.0),
  (250.0, 250.0, 6.3),
  (250.0, 250.0, 8.0),
  (250.0, 250.0, 10.0),
  (250.0, 250.0, 12.0),
  (250.0, 250.0, 12.5),
  (250.0, 250.0, 16.0),
  (260.0, 260.0, 6.0),
  (260.0, 260.0, 6.3),
  (260.0, 260.0, 8.0),
  (260.0, 260.0, 10.0),
  (260.0, 260.0, 12.0),
  (260.0, 260.0, 12.5),
  (260.0, 260.0, 16.0),
  (300.0, 300.0, 6.0),
  (300.0, 300.0, 6.3),
  (300.0, 300.0, 8.0),
  (300.0, 300.0, 10.0),
  (300.0, 300.0, 12.0),
  (300.0, 300.0, 12.5),
  (300.0, 300.0, 16.0),
  (350.0, 350.0, 6.0),
  (350.0, 350.0, 6.3),
  (350.0, 350.0, 8.0),
  (350.0, 350.0, 10.0),
  (350.0, 350.0, 12.0),
  (350.0, 350.0, 12.5),
  (350.0, 350.0, 16.0),
  (400.0, 400.0, 6.0),
  (400.0, 400.0, 6.3),
  (400.0, 400.0, 8.0),
  (400.0, 400.0, 10.0),
  (400.0, 400.0, 12.0),
  (400.0, 400.0, 12.5),
  (400.0, 400.0, 16.0),
  (40.0, 20.0, 2.0),
  (40.0, 20.0, 2.5),
  (40.0, 20.0, 3.0),
  (50.0, 25.0, 2.0),
  (50.0, 25.0, 2.5),
  (50.0, 25.0, 3.0),
  (50.0, 30.0, 2.0),
  (50.0, 30.0, 2.5),
  (50.0, 30.0, 3.0),
  (50.0, 30.0, 4.0),
  (60.0, 40.0, 2.0),
  (60.0, 40.0, 2.5),
  (60.0, 40.0, 3.0),
  (60.0, 40.0, 4.0),
  (60.0, 40.0, 5.0),
  (70.0, 40.0, 3.0),
  (70.0, 40.0, 4.0),
  (70.0, 40.0, 5.0),
  (70.0, 50.0, 2.0),
  (70.0, 50.0, 2.5),
  (70.0, 50.0, 3.0),
  (70.0, 50.0, 4.0),
  (70.0, 50.0, 5.0),
  (80.0, 40.0, 2.0),
  (80.0, 40.0, 2.5),
  (80.0, 40.0, 3.0),
  (80.0, 40.0, 4.0),
  (80.0, 40.0, 5.0),
  (80.0, 50.0, 3.0),
  (80.0, 50.0, 4.0),
  (80.0, 50.0, 5.0),
  (80.0, 60.0, 2.0),
  (80.0, 60.0, 2.5),
  (80.0, 60.0, 3.0),
  (80.0, 60.0, 3.5),
  (80.0, 60.0, 4.0),
  (80.0, 60.0, 5.0),
  (90.0, 50.0, 2.0),
  (90.0, 50.0, 2.5),
  (90.0, 50.0, 3.0),
  (90.0, 50.0, 4.0),
  (90.0, 50.0, 5.0),
  (100.0, 40.0, 2.5),
  (100.0, 40.0, 3.0),
  (100.0, 40.0, 4.0),
  (100.0, 40.0, 5.0),
  (100.0, 50.0, 2.5),
  (100.0, 50.0, 3.0),
  (100.0, 50.0, 4.0),
  (100.0, 50.0, 5.0),
  (100.0, 50.0, 6.0),
  (100.0, 50.0, 6.3),
  (100.0, 60.0, 2.5),
  (100.0, 60.0, 3.0),
  (100.0, 60.0, 3.5),
  (100.0, 60.0, 4.0),
  (100.0, 60.0, 5.0),
  (100.0, 60.0, 6.0),
  (100.0, 60.0, 6.3),
  (100.0, 80.0, 2.5),
  (100.0, 80.0, 3.0),
  (100.0, 80.0, 4.0),
  (100.0, 80.0, 5.0),
  (100.0, 80.0, 6.0),
  (100.0, 80.0, 6.3),
  (120.0, 40.0, 3.0),
  (120.0, 40.0, 4.0),
  (120.0, 40.0, 5.0),
  (120.0, 60.0, 2.5),
  (120.0, 60.0, 3.0),
  (120.0, 60.0, 3.5),
  (120.0, 60.0, 4.0),
  (120.0, 60.0, 5.0),
  (120.0, 60.0, 6.0),
  (120.0, 60.0, 6.3),
  (120.0, 60.0, 8.0),
  (120.0, 80.0, 3.0),
  (120.0, 80.0, 4.0),
  (120.0, 80.0, 5.0),
  (120.0, 80.0, 6.0),
  (120.0, 80.0, 6.3),
  (120.0, 80.0, 8.0),
  (140.0, 80.0, 3.0),
  (140.0, 80.0, 4.0),
  (140.0, 80.0, 5.0),
  (140.0, 80.0, 6.0),
  (140.0, 80.0, 6.3),
  (140.0, 80.0, 8.0),
  (140.0, 80.0, 10.0),
  (150.0, 100.0, 3.0),
  (150.0, 100.0, 4.0),
  (150.0, 100.0, 5.0),
  (150.0, 100.0, 6.0),
  (150.0, 100.0, 6.3),
  (150.0, 100.0, 8.0),
  (150.0, 100.0, 10.0),
  (150.0, 100.0, 12.0),
  (150.0, 100.0, 12.5),
  (160.0, 80.0, 3.0),
  (160.0, 80.0, 4.0),
  (160.0, 80.0, 5.0),
  (160.0, 80.0, 6.0),
  (160.0, 80.0, 6.3),
  (160.0, 80.0, 8.0),
  (160.0, 80.0, 10.0),
  (160.0, 80.0, 12.0),
  (160.0, 80.0, 12.5),
  (180.0, 80.0, 3.0),
  (180.0, 80.0, 4.0),
  (180.0, 80.0, 5.0),
  (180.0, 80.0, 6.0),
  (180.0, 80.0, 8.0),
  (180.0, 80.0, 10.0),
  (180.0, 100.0, 4.0),
  (180.0, 100.0, 5.0),
  (180.0, 100.0, 6.0),
  (180.0, 100.0, 6.3),
  (180.0, 100.0, 8.0),
  (180.0, 100.0, 10.0),
  (180.0, 100.0, 12.0),
  (180.0, 100.0, 12.5),
  (200.0, 100.0, 4.0),
  (200.0, 100.0, 5.0),
  (200.0, 100.0, 6.0),
  (200.0, 100.0, 6.3),
  (200.0, 100.0, 8.0),
  (200.0, 100.0, 10.0),
  (200.0, 100.0, 12.0),
  (200.0, 100.0, 12.5),
  (200.0, 120.0, 4.0),
  (200.0, 120.0, 5.0),
  (200.0, 120.0, 6.0),
  (200.0, 120.0, 6.3),
  (200.0, 120.0, 8.0),
  (200.0, 120.0, 10.0),
  (200.0, 120.0, 12.0),
  (200.0, 120.0, 12.5),
  (200.0, 150.0, 4.0),
  (200.0, 150.0, 5.0),
  (200.0, 150.0, 6.0),
  (200.0, 150.0, 8.0),
  (200.0, 150.0, 10.0),
  (250.0, 150.0, 5.0),
  (250.0, 150.0, 6.0),
  (250.0, 150.0, 6.3),
  (250.0, 150.0, 8.0),
  (250.0, 150.0, 10.0),
  (250.0, 150.0, 12.0),
  (250.0, 150.0, 12.5),
  (250.0, 150.0, 16.0),
  (260.0, 180.0, 5.0),
  (260.0, 180.0, 6.3),
  (260.0, 180.0, 8.0),
  (260.0, 180.0, 10.0),
  (260.0, 180.0, 12.0),
  (260.0, 180.0, 12.5),
  (260.0, 180.0, 16.0),
  (300.0, 100.0, 6.0),
  (300.0, 100.0, 6.3),
  (300.0, 100.0, 8.0),
  (300.0, 100.0, 10.0),
  (300.0, 100.0, 12.0),
  (300.0, 100.0, 12.5),
  (300.0, 100.0, 16.0),
  (300.0, 150.0, 6.0),
  (300.0, 150.0, 6.3),
  (300.0, 150.0, 8.0),
  (300.0, 150.0, 10.0),
  (300.0, 150.0, 12.0),
  (300.0, 150.0, 12.5),
  (300.0, 150.0, 16.0),
  (300.0, 200.0, 6.0),
  (300.0, 200.0, 6.3),
  (300.0, 200.0, 8.0),
  (300.0, 200.0, 10.0),
  (300.0, 200.0, 12.0),
  (300.0, 200.0, 12.5),
  (300.0, 200.0, 16.0),
  (350.0, 250.0, 6.0),
  (350.0, 250.0, 6.3),
  (350.0, 250.0, 8.0),
  (350.0, 250.0, 10.0),
  (350.0, 250.0, 12.0),
  (350.0, 250.0, 12.5),
  (350.0, 250.0, 16.0),
  (400.0, 200.0, 6.0),
  (400.0, 200.0, 6.3),
  (400.0, 200.0, 8.0),
  (400.0, 200.0, 10.0),
  (400.0, 200.0, 12.0),
  (400.0, 200.0, 12.5),
  (400.0, 200.0, 16.0),
  (400.0, 300.0, 8.0),
  (400.0, 300.0, 10.0),
  (400.0, 300.0, 12.0),
  (400.0, 300.0, 12.5),
  (400.0, 300.0, 16.0),
];

// ─── Wyszukiwanie ───────────────────────────────────────────────────────────

/// Tabela serii (pusta dla wyrobów liczonych z geometrii).
List<SteelSection> sectionsOf(SteelShape shape) => switch (shape) {
      SteelShape.ipe => kIpe,
      SteelShape.hea => kHea,
      SteelShape.heb => kHeb,
      SteelShape.hem => kHem,
      SteelShape.upn => kUpn,
      SteelShape.upe => kUpe,
      SteelShape.angleEqual => kAngleEqual,
      SteelShape.angleUnequal => kAngleUnequal,
      _ => const [],
    };

/// Wiersz serii po nazwie („HEB 200", „L 50×50×5") albo null.
SteelSection? sectionByName(SteelShape shape, String? name) {
  if (name == null) return null;
  for (final s in sectionsOf(shape)) {
    if (s.name == name) return s;
  }
  return null;
}

/// Norma wymiarów / mas serii — do podpisu wyniku i tekstu zamówienia.
String standardOf(SteelShape shape) => switch (shape) {
      SteelShape.ipe ||
      SteelShape.hea ||
      SteelShape.heb ||
      SteelShape.hem ||
      SteelShape.upn ||
      SteelShape.upe =>
        'EN 10365',
      SteelShape.angleEqual || SteelShape.angleUnequal => 'EN 10056-1',
      SteelShape.hollow => 'EN 10219-2',
      SteelShape.flat => 'EN 10058',
      SteelShape.roundBar => 'EN 10060',
      SteelShape.squareBar => 'EN 10059',
      SteelShape.plate => 'EN 10029',
    };
