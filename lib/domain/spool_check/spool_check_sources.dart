/// Źródła i wartości odniesienia modułu „Tolerancje spoola”.
///
/// Ustalenia sprawdzone 2026-10-18:
///
/// * PFI ES-3 „Fabricating Tolerances” (Pipe Fabrication Institute) — tekst
///   wydania poprawionego w marcu 2004 r. (kopie udostępniane w sieci; ten
///   sam opis zakresu w wydaniu z marca 2009 r.). AKTUALNE wydanie to
///   PFI ES-03 R24 (2024; Intertek: poprzednie zastąpione 31.08.2024) — jego
///   treści NIE sprawdzono. Ustalone w kopiach wyd. 2004:
///   - p. 2, tolerancje liniowe „A” (rys. 1: środek–czoło, czoło–czoło,
///     środek–koniec króćców i innych przyłączy): ±1/8″ (3,0 mm) dla
///     średnic do 10″ włącznie, ±3/16″ (5,0 mm) dla 12″–24″, ±1/4″ (6,0 mm)
///     powyżej 24″ do 36″. Tolerancje nie sumują się. Reguła dla > 36″ jest
///     w kopiach nieczytelna — aplikacja jej nie podaje.
///   - wyrównanie czół lub końców („alignment of facings or ends”):
///     odchyłka od położenia wskazanego, mierzona na dowolnej średnicy, nie
///     większa niż 3/64″ na stopę (1,0 mm na 25,0 cm) lub 1/32″ (1,0 mm) —
///     co większe. Na której średnicy (przylgi czy zewnętrznej) mierzyć,
///     tekst nie rozstrzyga — aplikacja liczy granicę dla średnicy, na
///     której zmierzono.
///   - obrót kołnierza („rotation of flanges”, rys. 1): 1/16″; ekwiwalent
///     metryczny w kopiach niejednoznaczny (1,6 / 2,0 mm), oba łagodniejsze
///     od 1/16″ = 1,5875 mm. Sposób pomiaru pokazuje rysunek normy —
///     aplikacja porównuje przesunięcie otworu po obwodzie (interpretacja).
///   - p. 4: ściślejsze tolerancje — przez uzgodnienie zamawiającego
///     z wytwórcą. Norma nie dotyczy rurociągów montowanych na budowie.
///   - przesunięcia bocznego odgałęzień i prostoliniowości w kopiach ES-3
///     NIE znaleziono — aplikacja nie podaje dla nich wartości normowej.
///   Wartości 1,5 mm (obrót, przesunięcie boczne kołnierza) i 0,75 mm
///   (wyrównanie) z zestawień w sieci pochodzą ze specyfikacji firm, nie
///   z ES-3 — celowo ich tu nie ma.
///
/// * EN 13480-4:2017 (SIST EN 13480-4:2018), p. 5.6: tolerancje wg
///   EN ISO 13920 klasa C i G, chyba że norma albo projekt podaje inne;
///   tolerancje wymiarowe prefabrykowanych spooli — zał. B (normatywny).
///   Interpretacja CEN/TC 267 WG8 (odpowiedź MHD z 29.11.2022): zał. B
///   podaje 3 klasy (grades), jedną z nich uzgadnia się przed rozpoczęciem
///   prefabrykacji; zał. B nie podaje tolerancji kątowych. Wartości zał. B
///   NIE zostały potwierdzone — aplikacja ich nie podaje, monter wpisuje je
///   z egzemplarza normy dla uzgodnionej klasy.
///
/// Zasada aplikacji: gdy norma podaje dwie wartości (calową i metryczną),
/// które nie są dokładnym przeliczeniem, bierzemy OSTRZEJSZĄ.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import 'spool_units.dart';

/// Pasmo tolerancji liniowej PFI ES-3 (p. 2, wyd. 2004).
class Es3LinearBand {
  /// Największe DN w paśmie (włącznie) — DN pośrednie między pasmami
  /// trafiają do pasma niższego (ostrzejszego).
  final int maxDn;

  /// Opis pasma w calach, jak w normie.
  final String sizePl;
  final String sizeEn;

  /// Wartość calowa normy.
  final double inch;

  /// Ekwiwalent metryczny podany w normie.
  final double metricMm;

  const Es3LinearBand({
    required this.maxDn,
    required this.sizePl,
    required this.sizeEn,
    required this.inch,
    required this.metricMm,
  });

  /// Tolerancja ± w mm: ostrzejsza z wartości calowej (w dół do siatki)
  /// i metrycznej normy.
  double get mm => math.min(metricMm, spoolToleranceFromInch(inch));

  String sizeLabel({required bool en}) => en ? sizeEn : sizePl;
}

/// Pasma ES-3: DN < 300 (NPS ≤ 10), DN < 650 (NPS 12–24), DN ≤ 900
/// (NPS > 24 do 36). Powyżej DN 900 — brak wartości (kopie nieczytelne).
const List<Es3LinearBand> kEs3LinearBands = [
  Es3LinearBand(
    maxDn: 299,
    sizePl: 'do 10″ (DN ≤ 250)',
    sizeEn: 'up to 10″ (DN ≤ 250)',
    inch: 1 / 8,
    metricMm: 3.0,
  ),
  Es3LinearBand(
    maxDn: 649,
    sizePl: '12″–24″ (DN 300–600)',
    sizeEn: '12″–24″ (DN 300–600)',
    inch: 3 / 16,
    metricMm: 5.0,
  ),
  Es3LinearBand(
    maxDn: 900,
    sizePl: 'ponad 24″ do 36″ (DN 650–900)',
    sizeEn: 'over 24″ to 36″ (DN 650–900)',
    inch: 1 / 4,
    metricMm: 6.0,
  ),
];

/// Pasmo ES-3 dla [dn] albo `null` (DN > 900 lub niepoprawne).
Es3LinearBand? es3LinearBandFor(int dn) {
  if (dn <= 0) return null;
  for (final b in kEs3LinearBands) {
    if (dn <= b.maxDn) return b;
  }
  return null;
}

/// Obrót kołnierza wg ES-3 rys. 1: 1/16″ (ekwiwalenty metryczne z kopii,
/// 1,6 i 2,0 mm, są łagodniejsze — obowiązuje wartość calowa).
const double kEs3RotationInch = 1 / 16;

/// Wyrównanie czoła wg ES-3: 3/64″ na stopę (12″) …
const double kEs3AlignPerFootInch = 3 / 64;

/// … ekwiwalent metryczny normy: 1,0 mm na 250 mm …
const double kEs3AlignMetricPerMm = 1.0 / 250;

/// … albo co najmniej 1/32″ (metrycznie w normie 1,0 mm) — co większe.
const double kEs3AlignMinInch = 1 / 32;
const double kEs3AlignMinMetricMm = 1.0;

/// Tolerancja obrotu kołnierza ES-3, mm.
double get kEs3RotationMm => spoolToleranceFromInch(kEs3RotationInch);

/// Granica wyrównania czoła ES-3 dla odchyłki mierzonej na średnicy
/// [diameterMm]: max(3/64″/stopę × D, 1/32″) w wersji calowej, bo obie jej
/// składowe są ostrzejsze od metrycznych (3,906 < 4,0 mm/m; 0,794 <
/// 1,0 mm). W dół do siatki.
double es3FaceAlignmentLimitMm(double diameterMm) {
  final perMm = kEs3AlignPerFootInch / 12; // cal na cal = mm na mm
  final perMmStrict = math.min(perMm, kEs3AlignMetricPerMm);
  final minStrict = math.min(
      kEs3AlignMinInch * kSpoolMmPerInch, kEs3AlignMinMetricMm);
  return spoolFloorMm(math.max(perMmStrict * diameterMm, minStrict));
}

/// Największa własna tolerancja, jaką aplikacja przyjmuje (mm) — wartość
/// PRZYJĘTA W APLIKACJI: powyżej to literówka („30” zamiast „3,0”), nie
/// tolerancja prefabrykacji.
const double kSpoolMaxToleranceMm = 50;

/// Największe DN przyjmowane w polu (literówka powyżej).
const int kSpoolMaxDn = 4000;

class SpoolSource {
  final String pl;
  final String en;
  const SpoolSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

/// Lista „Źródła i wartości odniesienia” na ekranie i w tekście protokołu.
const List<SpoolSource> kSpoolCheckSources = [
  SpoolSource(
    'PFI ES-3 „Fabricating Tolerances”, wyd. poprawione III 2004 (kopie): '
        'tolerancje liniowe (czoło–czoło, środek–czoło, położenie króćców '
        'i przyłączy) ±1/8″ (3,0 mm) do 10″, ±3/16″ (5,0 mm) dla 12″–24″, '
        '±1/4″ (6,0 mm) ponad 24″ do 36″; nie sumują się. Wyrównanie czoła: '
        'nie więcej niż 3/64″ na stopę (1,0 mm na 25 cm) lub 1/32″ (1,0 mm) — '
        'co większe, na dowolnej średnicy. Obrót kołnierza: 1/16″.',
    'PFI ES-3 “Fabricating Tolerances”, revised March 2004 (copies): linear '
        'tolerances (face-to-face, center-to-face, location of nozzles and '
        'attachments) ±1/8″ (3.0 mm) up to 10″, ±3/16″ (5.0 mm) for 12″–24″, '
        '±1/4″ (6.0 mm) over 24″ to 36″; not accumulative. Alignment of '
        'facings: not more than 3/64″ per foot (1.0 mm per 25 cm) or 1/32″ '
        '(1.0 mm), whichever is greater, across any diameter. Flange '
        'rotation: 1/16″.',
  ),
  SpoolSource(
    'Aktualne wydanie PFI ES-03 R24 (2024) nie zostało sprawdzone — przy '
        'odbiorze wg nowego wydania porównaj wartości z egzemplarzem normy. '
        'Ściślejsze tolerancje uzgadnia zamawiający z wytwórcą (p. 4).',
    'The current edition PFI ES-03 R24 (2024) has not been checked — for '
        'acceptance to the new edition compare the values with your copy. '
        'Closer tolerances are agreed between purchaser and fabricator (§ 4).',
  ),
  SpoolSource(
    'EN 13480-4:2017, p. 5.6: tolerancje wg EN ISO 13920 klasa C i G, chyba '
        'że norma lub projekt podaje inne; tolerancje wymiarowe spooli — '
        'zał. B (normatywny), 3 klasy, jedną uzgadnia się przed '
        'prefabrykacją (interpretacja CEN/TC 267 WG8, 29.11.2022). Wartości '
        'zał. B nie są wbudowane — wpisz je z normy.',
    'EN 13480-4:2017, cl. 5.6: tolerances to EN ISO 13920 class C and G '
        'unless the standard or the design states otherwise; dimensional '
        'tolerances of spools — Annex B (normative), 3 grades, one agreed '
        'before fabrication (CEN/TC 267 WG8 interpretation, 29 Nov 2022). '
        'Annex B values are not built in — enter them from the standard.',
  ),
  SpoolSource(
    'Zasady aplikacji: gdy norma podaje wartość calową i metryczną, która '
        'nie jest jej dokładnym przeliczeniem, obowiązuje ostrzejsza. '
        'Werdykt liczony w mm (rozdzielczość 0,000001 mm, ułamki do 1/64″ '
        'dokładnie): tolerancję '
        'z cali zaokrąglamy w dół, odchyłkę w górę; odchyłka równa '
        'tolerancji — w tolerancji. Przesunięcie boczne odgałęzienia '
        'i prostoliniowość — tylko z projektu (ES-3 w sprawdzonych kopiach '
        'ich nie podaje).',
    'App rules: when a standard gives an inch and a metric value that is not '
        'its exact conversion, the stricter one applies. The verdict is '
        'computed in mm (0.000001 mm resolution, fractions to 1/64″ exact): '
        'inch tolerances are rounded '
        'down, deviations up; a deviation equal to the tolerance is within '
        'tolerance. Branch lateral offset and straightness — from the '
        'design only (not found in the checked ES-3 copies).',
  ),
];

/// Ściąga „jak mierzyć” — PRAKTYKA WARSZTATOWA (nie z normy).
const List<SpoolSource> kSpoolHowToMeasure = [
  SpoolSource(
    'Mierz spool ostygnięty, podparty bez naprężeń, na równym podłożu. '
        'Taśmę zaczepiaj zawsze tak samo i odczytuj prostopadle.',
    'Measure the spool cooled down, supported without strain, on a level '
        'surface. Hook the tape the same way every time and read it square.',
  ),
  SpoolSource(
    'Czoło–czoło / środek–czoło: od powierzchni przylgi kołnierza (czoła '
        'RF), nie od tylnej strony kołnierza. Środek kolana / trójnika: '
        'przecięcie osi ramion — wyznacz kątownikiem i pionem na obu '
        'ramionach albo dodaj do pomiaru do czoła kształtki jej wymiar '
        'środek–koniec z katalogu.',
    'Face-to-face / center-to-face: from the gasket face (RF), not from the '
        'back of the flange. Elbow / tee center: where the leg axes cross — '
        'find it with a square and a plumb line on both legs, or add the '
        'fitting center-to-end from the catalogue to the reading to its end.',
  ),
  SpoolSource(
    'Skręt otworów (dwuotworowanie): otwory symetrycznie do osi pionowej '
        'albo poziomej. Poziomica na sworzniach w dwóch górnych otworach — '
        'pęcherzyk na środku; przesunięcie środka otworu odczytaj po '
        'obwodzie średnicy podziałowej (albo kąt — kalkulator przelicza).',
    'Bolt-hole rotation (two-holing): holes straddle the vertical or '
        'horizontal centerline. A level on pins in the two top holes — '
        'bubble centered; read the hole-center offset along the bolt circle '
        '(or the angle — the calculator converts).',
  ),
  SpoolSource(
    'Nachylenie czoła: kątownik przyłożony do tworzącej rury i do czoła '
        'kołnierza; szczelinomierzem zmierz szczelinę w dwóch przeciwległych '
        'punktach. Odchyłka = różnica szczelin, na średnicy = rozstawie '
        'punktów pomiaru. Powtórz w drugiej osi (obrót o 90°).',
    'Face tilt: a square against the pipe and the flange face; with feeler '
        'gauges read the gap at two opposite points. Deviation = gap '
        'difference, over the diameter = spacing of the points. Repeat at '
        '90°.',
  ),
  SpoolSource(
    'Prostoliniowość: żyłka napięta wzdłuż rury na dwóch jednakowych '
        'przekładkach na końcach; mierz odstęp od żyłki w kilku miejscach. '
        'Łuk = największa różnica względem przekładki. Sprawdź w dwóch '
        'płaszczyznach.',
    'Straightness: a string line along the pipe on two equal spacer blocks '
        'at the ends; measure the gap to the line at several points. Bow = '
        'largest difference from the block height. Check in two planes.',
  ),
];
