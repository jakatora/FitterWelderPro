/// Wartości z ASME PCC-1-2019 „Guidelines for Pressure Boundary Bolted Flange
/// Joint Assembly” użyte w module odbioru połączenia kołnierzowego.
///
/// ŹRÓDŁA (sprawdzone 2026-10-17):
///  * Tekst normy ASME PCC-1-2019, zał. E „Flange Joint Alignment
///    Guidelines”, para. E-2.4 i rys. E-1…E-4; zał. D tab. D-1/D-2;
///    para. 8.2, 11.3; tab. 1 (Legacy). „Summary of Changes” wydania 2019
///    nie wymienia zmian w zał. E — wartości jak w PCC-1-2013.
///  * Watercare (NZ), Guidance Note ESF-600-GDN-702 „Steel bolted flanged
///    joint assemblies” (2025, powołuje PCC-1:2022) — 1,5 mm, 2 × grubość
///    uszczelki, 0,8 mm, 3 mm, rundy Legacy.
///  * Slideshare „Flanged Joint Alignment” (cytuje zał. E, w tym 10 % siły):
///    https://www.slideshare.net/slideshow/flanged-joint-alignment/249511443
///  * Pumps & Systems „Best practices: gasket installation” (zał. E — dwie
///    grubości uszczelki) i „Manage & understand flange face damage”
///    (zał. D — 0,050 / 0,030 in.): https://pumpsandsystems.com
///  * D. Lay, ASCE Pipelines 2014 „Flange installation” (rundy Legacy
///    z PCC-1-2013 tab. 2): https://www.nwpipe.com/app/uploads/2020/08/Flange-installation-D.Lay_.pdf
///  * PVP 2025 (PCC-1-2022 zał. E, 1/32 in.).
///
/// NIEPEWNE / RÓŻNICE MIĘDZY WYDANIAMI:
///  * PCC-1-2022 przebudował zał. E (E-2, rys. E-2-3), ale źródła wtórne
///    podają te same liczby (1,5 mm / 0,8 mm / 3 mm / 2 × uszczelka). Nie
///    potwierdzono, czy zmieniło się brzmienie limitów siły (10 % / 20 %) —
///    dlatego moduł trzyma się PCC-1-2019 i mówi to w UI.
///  * Liczba punktów pomiaru szczeliny: zał. E jej nie podaje (osiowość
///    sprawdza się w 4 punktach co ~90°); para. 11.3 każe mierzyć szczelinę
///    w ≥ 8 równo rozłożonych miejscach w czasie dokręcania.
///  * Wystawanie gwintu: PCC-1 NIE podaje liczby zwojów poza nakrętką.
///    Wymaga pełnego zaangażowania gwintu na całej wysokości nakrętki
///    (para. 8.2; ASME B31.3 335.2.3); „1–3 zwoje” to praktyka zakładowa.
///  * Artykuły producentów podające np. „0,15 mm na 100 mm OD” dla
///    równoległości NIE pochodzą z PCC-1 — pominięte.
library;

import 'flange_check.dart' show DualLimit;

/// Wydanie normy, z którego są wartości domyślne.
const String kPcc1Edition = 'ASME PCC-1-2019';

/// E-2.4 (a) Centerline high/low: osie kołnierzy w granicy 1,5 mm (1/16 in.)
/// w każdym punkcie (liniał na OD jednego kołnierza, 4 punkty co ~90°).
const DualLimit kPcc1Centerline = DualLimit(1.5, 1 / 16);

/// E-2.4 (b) Równoległość: różnica między najmniejszą a największą
/// szczeliną ≤ 0,8 mm (1/32 in.), mierzona na zewnętrznej średnicy
/// powierzchni uszczelniającej.
const DualLimit kPcc1Parallelism = DualLimit(0.8, 1 / 32);

/// E-2.4 (c) Rotational two-hole: śruba przechodzi przez otwory pod kątem
/// prostym albo otwory w granicy 3 mm (1/8 in.) od idealnego ustawienia.
const DualLimit kPcc1Rotation = DualLimit(3.0, 1 / 8);

/// E-2.4 (d) Excessive spacing: kołnierze „w spoczynku” rozsunięte bardziej
/// niż na dwie grubości uszczelki — niedopuszczalne.
const double kPcc1GapFactor = 2.0;

/// E-2.4 Siła zestawienia bez urządzeń zewnętrznych: < 10 % całkowitego
/// docelowego obciążenia śrub, żadna śruba > 20 % swojego momentu/siły.
const int kPcc1ForceTotalPct = 10;
const int kPcc1ForceSingleBoltPct = 20;

/// Zał. D tab. D-2: dopuszczalna głębokość rysy/wżera w zależności od tego,
/// jak daleko sięga w poprzek szerokości osadzenia uszczelki w (rd — rzut
/// promieniowy uszkodzenia). [hardMm] — uszczelki twarde (spiralne,
/// kammprofile, metalowe), [softMm] — miękkie (płaskie niemetalowe, PTFE).
/// `null` = niedopuszczalne.
class Pcc1DefectLimit {
  final String reach;
  final double? hardMm;
  final double? softMm;
  const Pcc1DefectLimit(this.reach, this.hardMm, this.softMm);
}

const List<Pcc1DefectLimit> kPcc1DefectDepth = [
  Pcc1DefectLimit('rd < w/4', 0.76, 1.27),
  Pcc1DefectLimit('w/4 ≤ rd < w/2', 0.25, 0.76),
  Pcc1DefectLimit('w/2 ≤ rd < 3w/4', null, 0.13),
  Pcc1DefectLimit('rd ≥ 3w/4', null, null),
];

/// Zał. D tab. D-1: płaskość powierzchni (obwodowo i promieniowo), mm:
/// uszczelki twarde < 0,15, miękkie < 0,25.
const double kPcc1FlatnessHardMm = 0.15;
const double kPcc1FlatnessSoftMm = 0.25;

// Tab. 1 (Legacy, jedno narzędzie) — podpowiedź w punkcie listy „kolejność
// dokręcania” (flange_labels.dart): dociągnięcie 15–30 N·m (≤ 20 %),
// R1 20–30 %, R2 50–70 %, R3 100 % — po każdej sprawdź równomierność
// szczeliny; R4 okrężnie aż nakrętki przestaną się obracać; R5 po ≥ 4 h
// powtórz R4.
