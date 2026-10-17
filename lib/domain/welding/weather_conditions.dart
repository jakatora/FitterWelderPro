// Warunki do spawania na otwartym terenie: mróz, wilgoć, punkt rosy, opad,
// wiatr. Czysta logika — bez Fluttera i bez internetu (dane wpisuje
// spawacz z termometru, higrometru i wiatromierza albo ze skali Beauforta).
//
// Wynik to werdykt („Można spawać” / „Można spawać po spełnieniu warunków”
// / „Nie spawać”), lista warunków do odhaczenia i zalecenia — każde
// z podstawą. Progi domyślne są konserwatywne i edytowalne (specyfikacja
// projektu może je zaostrzyć albo złagodzić).
//
// ŹRÓDŁA (sprawdzone 2026-10-17 przez WebSearch/WebFetch). Normy są płatne:
// NUMERY punktów potwierdzono w oficjalnych spisach/indeksach, BRZMIENIE
// i liczby — w cytatach źródeł wtórnych. Poziom pewności przy każdym.
//
// [A1] AWS D1.1/D1.1M:2020 — numeracja potwierdzona w oficjalnym indeksie
//      (https://pubs.aws.org/Download_PDFS/D1_1_D1_1M_2020_index_PV.pdf):
//      „wind velocity, 7.11.1”; „minimum ambient temperature, 7.11.2,
//      C-7.11.2”; Table 5.8 „Prequalified Minimum Preheat and Interpass
//      Temperature (see 5.7)”; „electrode atmospheric time periods, 7.3.2.3,
//      Table 7.1”. Clause 7 (Fabrication) w 2020 = dawny Clause 5: w 2010
//      te same wymagania to 5.12.1 / 5.12.2 i Table 3.2, w 2015 5.11.x.
//      Wydanie 2025: tabela podgrzewania = Table 5.11 (artykuł CEI,
//      https://info.thinkcei.com/think-tank/aws-d1.1-structural-code-requirements-2025-updates);
//      numeru punktu o warunkach otoczenia w 2025 NIE potwierdzono — ekran
//      cytuje wydanie 2020.
// [A2] Brzmienie [A1] — cytat D1.1 (wyd. 2010, 5.12.2) w PCI Journal, wiosna
//      2012, „Effect of environmental conditions on field welding of precast
//      concrete connections”, s. 2
//      (https://www.pci.org/PCI_Docs/Publications/PCI%20Journal/2012/Spring/Effect%20of%20environmental%20conditions%20on%20field%20welding%20of%20precast%20concrete%20connections.pdf):
//      nie spawać (1) gdy temperatura otoczenia (przy spoinie) < 0 °F,
//      (2) gdy powierzchnie są mokre lub wystawione na deszcz, śnieg,
//      (3) przy dużej prędkości wiatru, (4) gdy spawacz jest wystawiony na
//      niesprzyjające warunki. Wiatr 5 mph (8 km/h) dotyczy procesów
//      w osłonie gazowej (GMAW, GTAW, EGW, FCAW-G — indeks/TIF PAN); dla
//      SMAW AWS nie podaje liczby. Metal < 32 °F → podgrzać do ≥ 70 °F.
//      Ogrzewana obudowa przy mrozie — komentarz C-7.11.2 (źródła wtórne).
// [A3] Elektrody niskowodorowe, czasy ekspozycji wg D1.1 (Table 7.1 w 2020,
//      5.1 w 2010/2015): E70XX 4 h, E80XX 2 h, E90XX 1 h, E100XX/E110XX
//      0,5 h; piec do przetrzymywania ≥ 120 °C (250 °F) — LANL GWS 1-03
//      Att. 1 (https://engstandards.lanl.gov/esm/welding/vol1/GWS%201-03-Att-1-R1.pdf)
//      i [A2].
// [B1] ASME B31.3 Table 330.1.1 (wyd. ≥ 2014; tekst wydań 2020 i 2024
//      sprawdzony w preheat.dart): wymagana min. temperatura 10 °C (50 °F)
//      m.in. dla P-No 1 ≤ 25 mm i „all other materials”. B31.1-2022 131.4:
//      także 10 °C (50 °F) jako minimum ogólne (źródło wtórne).
// [B2] ASME B31.3 330.1.4 „Preheat Zone”: większa z 75 mm i 1,5 × grubości
//      (amarineblog.com/2019/10/24/preheating-temperature-distance-range;
//      źródło wtórne, wydanie niepodane). AWS D1.1: ≥ grubość najgrubszej
//      części, min. 75 mm (to samo źródło; punkt 7.6 w 2020 wg indeksu).
// [E1] EN 1090-2 (2008+A1:2011 i 2018) 7.5.3 „Ochrona przed warunkami
//      atmosferycznymi”: spawacz i stanowisko chronione przed wiatrem,
//      deszczem i śniegiem — bez liczb (numer punktu: SBE/TWI/Stahlbauverband;
//      treść: wytyczne BOC/Linde „EN 1090 Guideline” 2014 — źródło wtórne).
//      EN 1090-2:2018 7.5.2: tablicę suszenia spoiw usunięto, obowiązują
//      zalecenia producenta (Stahlbauverband,
//      https://www.stahlbauverband.at/download/362/EN_1090-2_2018_Aenderungen_7_Schwei__en.pdf).
// [E2] EN 1011-1:2009, 5.2 „Stanowisko pracy”: skutecznie chronione przed
//      szkodliwym wpływem pogody (wiatr, deszcz, śnieg, przeciąg) — bez liczb
//      (cytat z wyniku wyszukiwania pliku BS EN 1011-1:2009).
//      EN 1011-2 — zapisu o niskiej temperaturze otoczenia nie znaleziono.
// [S1] SCI GN 7.01 rev. 3 (https://steelconstruction.info/upload/Wiki-Files/b/bd/GN_7-01.pdf):
//      ogrzać złącze przed spawaniem, by usunąć wilgoć (np. po porannej
//      kondensacji) — bez liczby.
// [I1] ISO 8502-4:2017 — metoda: zmierzyć temperaturę i RH powietrza,
//      policzyć punkt rosy, zmierzyć temperaturę powierzchni. Kryterium
//      ΔT ≥ 3 K przypisują jej producenci przyrządów (np. beschicht.com
//      o Elcometer 319); tekstu normy NIE weryfikowano. To praktyka
//      malarska, nie wymóg norm spawalniczych — tak opisane na ekranie.
// [M1] M. G. Lawrence, „The relationship between relative humidity and the
//      dewpoint temperature in moist air”, BAMS 86(2):225–233, 2005,
//      DOI 10.1175/BAMS-86-2-225 — stałe Alduchov & Eskridge (1996):
//      17,625; 243,04 °C; 610,94 Pa. (Sonntag 1990: 17,62; 243,12 °C —
//      różnica < 0,01 K w zakresie aplikacji.)
// [M2] A. L. Buck, Buck Research CR-1A User’s Manual, 1996 — prężność nad
//      lodem (za https://en.wikipedia.org/wiki/Arden_Buck_equation).
// [B]  Skala Beauforta (ląd): https://en.wikipedia.org/wiki/Beaufort_scale
//      (za Met Office / RMetS).
//
// Liczby bez oparcia w normie są nazwane na ekranie „progiem praktycznym”:
// silny wiatr dla procesów bez gazu (D1.1, EN 1090-2, EN 1011-1 nie podają
// liczby) i limit wiatru dla spawania gazowego 311 (D1.1 go nie obejmuje).

import 'dart:convert';
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════
// Liczby
// ═══════════════════════════════════════════════════════════════════════════

/// Liczba do tekstu: przecinek w PL, kropka w EN; „-0,0” → „0,0”.
String weatherNum(double v, {int decimals = 1, bool english = false}) {
  var s = v.toStringAsFixed(decimals);
  if (s.startsWith('-') && double.parse(s) == 0) s = s.substring(1);
  return english ? s : s.replaceAll('.', ',');
}

/// Liczba do [maxDecimals] miejsc bez zbędnych zer: 2,50 → „2,5”,
/// 21,0 → „21”, -17,8 → „-17,8”. Do wartości wpisanych przez spawacza
/// i progów — pokazuje je z tą samą precyzją, z jaką są w polu.
String weatherNumAuto(double v, {int maxDecimals = 2, bool english = false}) {
  var s = weatherNum(v, decimals: maxDecimals, english: true);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') s = '0';
  return english ? s : s.replaceAll('.', ',');
}

double _pow10(int d) => math.pow(10, d).toDouble();

/// Zaokrąglenie w górę do [decimals] miejsc (tolerancja błędu binarnego:
/// 5 · 3,6 = 18,000000000000004 zostaje 18).
double ceilTo(double v, int decimals) {
  final f = _pow10(decimals);
  return (v * f - 1e-7).ceilToDouble() / f;
}

/// Zaokrąglenie w dół do [decimals] miejsc (z tą samą tolerancją).
double floorTo(double v, int decimals) {
  final f = _pow10(decimals);
  return (v * f + 1e-7).floorToDouble() / f;
}

/// Wymagane MINIMUM (temperatura do osiągnięcia) — w górę, do 2 miejsc:
/// pokazane minimum nigdy nie jest łagodniejsze od liczonego.
String weatherNumMin(double v, {bool english = false}) =>
    weatherNumAuto(ceilTo(v, 2), english: english);

/// Limit GÓRNY (np. wiatr) — w dół, do 2 miejsc.
String weatherNumMax(double v, {bool english = false}) =>
    weatherNumAuto(floorTo(v, 2), english: english);

/// Dwie liczby do porównania w tekście („a > b”, „a ≤ b”): tyle miejsc
/// (od [minDecimals] — domyślnie 2, czyli precyzja pól — do 4), żeby
/// zaokrąglenie nie odwróciło ani nie zrównało
/// relacji — nigdy „-17,9 jest poniżej -18” ani „2,2 > 2,2”.
(String, String) weatherPair(double a, double b,
    {int minDecimals = 2, bool english = false}) {
  for (var d = minDecimals; d <= 4; d++) {
    final f = _pow10(d);
    final ra = (a * f).roundToDouble();
    final rb = (b * f).roundToDouble();
    final same = (a < b && ra < rb) || (a > b && ra > rb) || (a == b);
    if (same) {
      return (
        weatherNumAuto(a, maxDecimals: d, english: english),
        weatherNumAuto(b, maxDecimals: d, english: english),
      );
    }
  }
  return (
    weatherNumAuto(a, maxDecimals: 4, english: english),
    weatherNumAuto(b, maxDecimals: 4, english: english),
  );
}

String _tr(bool en, String pl, String eng) => en ? eng : pl;

// ═══════════════════════════════════════════════════════════════════════════
// Wiatr: jednostki i skala Beauforta
// ═══════════════════════════════════════════════════════════════════════════

enum WindUnit { ms, kmh }

/// 1 m/s = 3,6 km/h (dokładnie).
const double kKmhPerMs = 3.6;

/// 1 mph = 0,44704 m/s (dokładnie, z definicji jarda międzynarodowego).
const double kMsPerMph = 0.44704;

double msToKmh(double ms) => ms * kKmhPerMs;
double kmhToMs(double kmh) => kmh / kKmhPerMs;
double mphToMs(double mph) => mph * kMsPerMph;

/// Prędkość w [unit] → m/s.
double windToMs(double value, WindUnit unit) =>
    unit == WindUnit.ms ? value : kmhToMs(value);

/// m/s → prędkość w [unit].
double windFromMs(double ms, WindUnit unit) =>
    unit == WindUnit.ms ? ms : msToKmh(ms);

String windUnitLabel(WindUnit u) => u == WindUnit.ms ? 'm/s' : 'km/h';

/// Stopień skali Beauforta z opisem objawów na lądzie.
class BeaufortLevel {
  const BeaufortLevel(this.force, this.minMs, this.maxMs, this.namePl,
      this.nameEn, this.signsPl, this.signsEn);

  final int force;
  final double minMs;

  /// Górna granica przedziału — tę wartość przyjmujemy, gdy spawacz wybiera
  /// stopień z opisu (strona bezpieczna).
  final double maxMs;
  final String namePl;
  final String nameEn;
  final String signsPl;
  final String signsEn;
}

/// Skala Beauforta 0–7 (przedziały m/s na 10 m nad gruntem i objawy na
/// lądzie; źródło [B]). Limit 2,2 m/s dla gazu wypada w stopniu 2.
const List<BeaufortLevel> kBeaufortScale = [
  BeaufortLevel(0, 0, 0.2, 'cisza', 'calm', 'dym unosi się pionowo',
      'smoke rises vertically'),
  BeaufortLevel(1, 0.3, 1.5, 'powiew', 'light air',
      'dym lekko znosi, chorągiewka stoi', 'smoke drifts, vanes do not move'),
  BeaufortLevel(
      2,
      1.6,
      3.3,
      'słaby wiatr',
      'light breeze',
      'czuć wiatr na twarzy, liście szeleszczą',
      'wind felt on face, leaves rustle'),
  BeaufortLevel(
      3,
      3.4,
      5.4,
      'łagodny wiatr',
      'gentle breeze',
      'liście i gałązki w ciągłym ruchu',
      'leaves and twigs in constant motion'),
  BeaufortLevel(
      4,
      5.5,
      7.9,
      'umiarkowany wiatr',
      'moderate breeze',
      'kurz i papier się unoszą, ruszają się małe gałęzie',
      'dust and loose paper raised, small branches move'),
  BeaufortLevel(5, 8.0, 10.7, 'dość silny wiatr', 'fresh breeze',
      'kołyszą się małe drzewa', 'small trees sway'),
  BeaufortLevel(
      6,
      10.8,
      13.8,
      'silny wiatr',
      'strong breeze',
      'ruszają się duże gałęzie, gwiżdżą przewody',
      'large branches move, wires whistle'),
  BeaufortLevel(
      7,
      13.9,
      17.1,
      'bardzo silny wiatr',
      'near gale',
      'kołyszą się całe drzewa, trudno iść pod wiatr',
      'whole trees move, hard to walk against the wind'),
];

/// Stopień Beauforta dla prędkości [ms] (powyżej 7 → ostatni wpis; do
/// opisu używaj [beaufortText], które nazywa to „8° i więcej”).
BeaufortLevel beaufortFor(double ms) {
  for (final l in kBeaufortScale) {
    if (ms < l.maxMs + 0.05) return l;
  }
  return kBeaufortScale.last;
}

/// Prędkość powyżej skali w aplikacji (7° B kończy się na 17,1 m/s).
bool beaufortAboveScale(double ms) => ms >= kBeaufortScale.last.maxMs + 0.05;

/// „3° Beaufort — łagodny wiatr”; powyżej 17,1 m/s „8°+ Beaufort — wichura
/// i silniej” (nie „7°”).
String beaufortText(double ms, {required bool english}) {
  if (beaufortAboveScale(ms)) {
    return english
        ? '8°+ Beaufort — gale or stronger'
        : '8°+ Beaufort — wichura i silniej';
  }
  final b = beaufortFor(ms);
  return '${b.force}° Beaufort — ${english ? b.nameEn : b.namePl}';
}

// ═══════════════════════════════════════════════════════════════════════════
// Punkt rosy (wzór Magnusa)
// ═══════════════════════════════════════════════════════════════════════════

/// Stałe Magnusa nad wodą wg Alduchov & Eskridge (1996), za Lawrence (2005)
/// [M1]: es = 6,1094·exp(17,625·T/(243,04 + T)) [hPa], błąd es < 0,4 %
/// w zakresie −40…50 °C.
const double kMagnusA = 17.625;
const double kMagnusB = 243.04;
const double _kMagnusC = 6.1094;

/// Ciśnienie pary nasyconej nad wodą [hPa].
double _esWater(double t) =>
    _kMagnusC * math.exp(kMagnusA * t / (kMagnusB + t));

/// Ciśnienie pary nasyconej nad lodem [hPa] — równanie Bucka (1996) [M2]:
/// es,i = 6,1115·exp((23,036 − T/333,7)·T/(279,82 + T)).
double _esIce(double t) =>
    6.1115 * math.exp((23.036 - t / 333.7) * (t / (279.82 + t)));

/// Punkt rosy [°C] nad wodą. RH względem wody (tak mierzą higrometry,
/// konwencja WMO). `null` dla RH spoza (0; 100] albo T spoza −60…60 °C.
///
///   γ  = ln(RH/100) + a·T/(b + T)
///   Td = b·γ / (a − γ)
double? dewPointC({required double airC, required double rhPct}) {
  if (!_validAir(airC) || !_validRh(rhPct)) return null;
  final g = math.log(rhPct / 100) + kMagnusA * airC / (kMagnusB + airC);
  return kMagnusB * g / (kMagnusA - g);
}

/// Punkt szronu [°C] — temperatura, w której para z powietrza osiada na
/// stali jako szron (nad lodem). Ma sens tylko, gdy punkt rosy < 0 °C;
/// wtedy jest wyższy od punktu rosy. `null` dla danych spoza zakresu.
///
/// Prężność pary e = RH/100 · es(T) [nad wodą, M1]; punkt szronu to T_f,
/// dla której es,i(T_f) = e [nad lodem, M2]. Równanie Bucka nie odwraca
/// się wprost — bisekcja w −100…0 °C (es,i rośnie tam monotonicznie).
double? frostPointC({required double airC, required double rhPct}) {
  if (!_validAir(airC) || !_validRh(rhPct)) return null;
  final e = rhPct / 100 * _esWater(airC);
  var lo = -100.0;
  var hi = 0.0;
  if (e <= _esIce(lo) || e >= _esIce(hi)) return null;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (_esIce(mid) < e) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Temperatura, poniżej której na stali pojawia się woda (rosa) albo szron:
/// punkt rosy, a gdy jest ujemny — wyższy z punktu rosy i punktu szronu.
double? condensationPointC({required double airC, required double rhPct}) {
  final d = dewPointC(airC: airC, rhPct: rhPct);
  if (d == null) return null;
  if (d >= 0) return d;
  final f = frostPointC(airC: airC, rhPct: rhPct);
  return f == null ? d : math.max(d, f);
}

bool _validAir(double t) => t.isFinite && t >= -60 && t <= 60;
bool _validRh(double rh) => rh.isFinite && rh > 0 && rh <= 100;

// ═══════════════════════════════════════════════════════════════════════════
// Wejście
// ═══════════════════════════════════════════════════════════════════════════

enum Precipitation { none, drizzle, rain, snow }

extension PrecipitationText on Precipitation {
  String label(bool en) => switch (this) {
        Precipitation.none => _tr(en, 'brak', 'none'),
        Precipitation.drizzle => _tr(en, 'mżawka', 'drizzle'),
        Precipitation.rain => _tr(en, 'deszcz', 'rain'),
        Precipitation.snow => _tr(en, 'śnieg', 'snow'),
      };
}

/// Jak proces chroni jeziorko.
enum ShieldKind {
  /// Gaz z butli — wrażliwy na wiatr (limit AWS D1.1).
  gas,

  /// Otulina elektrody (111).
  coating,

  /// Drut samoosłonowy (114).
  selfShielded,

  /// Łuk kryty topnikiem (121).
  flux,

  /// Płomień acetylenowo-tlenowy (311).
  flame,
}

/// Metoda spawania (numer wg EN ISO 4063).
enum WeatherProcess {
  mma111('111', 'MMA', 'SMAW', ShieldKind.coating),
  mag135('135/138', 'MAG', 'GMAW', ShieldKind.gas),
  fcawG136('136', 'FCAW-G', 'FCAW-G', ShieldKind.gas),
  fcawS114('114', 'FCAW-S', 'FCAW-S', ShieldKind.selfShielded),
  tig141('141', 'TIG', 'GTAW', ShieldKind.gas),
  mig131('131', 'MIG', 'GMAW', ShieldKind.gas),
  saw121('121', 'SAW', 'SAW', ShieldKind.flux),
  gas311('311', 'gazowe', 'OFW', ShieldKind.flame);

  const WeatherProcess(this.code, this.namePl, this.nameEn, this.shield);

  final String code;
  final String namePl;
  final String nameEn;
  final ShieldKind shield;

  String label(bool en) => '$code ${en ? nameEn : namePl}';

  /// Wiatr zdmuchuje osłonę gazową / płomień.
  bool get windSensitive =>
      shield == ShieldKind.gas || shield == ShieldKind.flame;
}

/// Osłona stanowiska.
enum WeatherShelter {
  /// Nic — otwarty teren.
  none,

  /// Parawan / ekran od wiatru — bez dachu.
  windbreak,

  /// Namiot / obudowa z dachem — chroni przed wiatrem i opadem, da się ją
  /// ogrzać.
  enclosure,
}

extension WeatherShelterText on WeatherShelter {
  String label(bool en) => switch (this) {
        WeatherShelter.none => _tr(en, 'brak', 'none'),
        WeatherShelter.windbreak => _tr(en, 'parawan od wiatru', 'windbreak'),
        WeatherShelter.enclosure =>
          _tr(en, 'namiot / obudowa', 'tent / enclosure'),
      };
}

/// Stan powierzchni złącza oceniony okiem / ręką (AWS D1.1 §7.11.2 zakazuje
/// spawania na mokrych powierzchniach — tego nie da się wyliczyć z pogody:
/// po deszczu, przy rosie albo z lodem na rurze opad może być „brak”).
enum SurfaceState {
  /// Nie sprawdzono — nigdy nie daje czystego „Można spawać”.
  unchecked,
  dry,
  wet,

  /// Szron, lód, śnieg na złączu.
  frozen,
}

extension SurfaceStateText on SurfaceState {
  String label(bool en) => switch (this) {
        SurfaceState.unchecked => _tr(en, 'nie sprawdzono', 'not checked'),
        SurfaceState.dry => _tr(en, 'sucha', 'dry'),
        SurfaceState.wet => _tr(en, 'wilgotna / mokra', 'damp / wet'),
        SurfaceState.frozen => _tr(en, 'szron, lód, śnieg', 'frost, ice, snow'),
      };
}

enum WeatherMaterial { carbonSteel, stainless, aluminium }

extension WeatherMaterialText on WeatherMaterial {
  String label(bool en) => switch (this) {
        WeatherMaterial.carbonSteel =>
          _tr(en, 'stal węglowa / niskostopowa', 'carbon / low-alloy steel'),
        WeatherMaterial.stainless => _tr(en, 'stal nierdzewna', 'stainless'),
        WeatherMaterial.aluminium => _tr(en, 'aluminium', 'aluminium'),
      };
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

double? _numOrNull(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  return null;
}

double _numRequired(Object? v, String field) {
  final d = _numOrNull(v);
  if (d == null) throw FormatException('weather: brak liczby „$field”');
  return d;
}

/// Pomiar wpisany przez spawacza.
class WeatherInput {
  const WeatherInput({
    required this.ambientC,
    required this.rhPct,
    this.surfaceC,
    required this.windMs,
    this.windUnit = WindUnit.ms,
    this.precipitation = Precipitation.none,
    this.process = WeatherProcess.mma111,
    this.shelter = WeatherShelter.none,
    this.material = WeatherMaterial.carbonSteel,
    this.wpsPreheatC,
    this.surfaceState = SurfaceState.unchecked,
  });

  /// Temperatura powietrza [°C].
  final double ambientC;

  /// Wilgotność względna [%].
  final double rhPct;

  /// Temperatura powierzchni materiału z termometru kontaktowego [°C];
  /// `null` → przyjmujemy temperaturę powietrza (założenie na ekranie).
  final double? surfaceC;

  /// Prędkość wiatru przy stanowisku [m/s].
  final double windMs;

  /// Jednostka, w której spawacz ją wpisał (tylko do wyświetlania).
  final WindUnit windUnit;
  final Precipitation precipitation;
  final WeatherProcess process;
  final WeatherShelter shelter;
  final WeatherMaterial material;

  /// Minimalne podgrzewanie z WPS [°C]; `null` = WPS nie wymaga / nie znam.
  final double? wpsPreheatC;

  /// Stan powierzchni złącza (sucha / mokra / oblodzona / nie sprawdzono).
  final SurfaceState surfaceState;

  Map<String, Object?> toJson() => {
        'ambientC': ambientC,
        'rhPct': rhPct,
        if (surfaceC != null) 'surfaceC': surfaceC,
        'windMs': windMs,
        'windUnit': windUnit.name,
        'precipitation': precipitation.name,
        'process': process.name,
        'shelter': shelter.name,
        'material': material.name,
        if (wpsPreheatC != null) 'wpsPreheatC': wpsPreheatC,
        'surfaceState': surfaceState.name,
      };

  /// Rzuca [FormatException], gdy brakuje wymaganej liczby.
  factory WeatherInput.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('weather: input nie mapą');
    return WeatherInput(
      ambientC: _numRequired(json['ambientC'], 'ambientC'),
      rhPct: _numRequired(json['rhPct'], 'rhPct'),
      surfaceC: _numOrNull(json['surfaceC']),
      windMs: _numRequired(json['windMs'], 'windMs'),
      windUnit: _enumByName(WindUnit.values, json['windUnit'], WindUnit.ms),
      precipitation: _enumByName(
          Precipitation.values, json['precipitation'], Precipitation.none),
      process: _enumByName(
          WeatherProcess.values, json['process'], WeatherProcess.mma111),
      shelter: _enumByName(
          WeatherShelter.values, json['shelter'], WeatherShelter.none),
      material: _enumByName(WeatherMaterial.values, json['material'],
          WeatherMaterial.carbonSteel),
      wpsPreheatC: _numOrNull(json['wpsPreheatC']),
      // Wpisy sprzed tego pola → „nie sprawdzono” (strona bezpieczna).
      surfaceState: _enumByName(
          SurfaceState.values, json['surfaceState'], SurfaceState.unchecked),
    );
  }
}

/// Błędy wejścia — kody do tłumaczenia na ekranie.
enum WeatherInputProblem {
  ambientMissing,
  ambientOutOfRange,
  rhMissing,
  rhOutOfRange,
  surfaceOutOfRange,
  windMissing,
  windOutOfRange,
  wpsPreheatOutOfRange,
}

/// Sprawdza liczby z pól (null = puste pole). Pusta lista → można liczyć.
List<WeatherInputProblem> validateWeatherFields({
  required double? ambientC,
  required double? rhPct,
  required double? surfaceC,
  required double? windMs,
  required double? wpsPreheatC,
}) =>
    [
      if (ambientC == null)
        WeatherInputProblem.ambientMissing
      else if (!_validAir(ambientC))
        WeatherInputProblem.ambientOutOfRange,
      if (rhPct == null)
        WeatherInputProblem.rhMissing
      else if (!_validRh(rhPct))
        WeatherInputProblem.rhOutOfRange,
      if (surfaceC != null && !(surfaceC >= -60 && surfaceC <= 400))
        WeatherInputProblem.surfaceOutOfRange,
      if (windMs == null)
        WeatherInputProblem.windMissing
      else if (!(windMs >= 0 && windMs <= 60))
        WeatherInputProblem.windOutOfRange,
      if (wpsPreheatC != null && !(wpsPreheatC >= -60 && wpsPreheatC <= 400))
        WeatherInputProblem.wpsPreheatOutOfRange,
    ];

// ═══════════════════════════════════════════════════════════════════════════
// Progi (edytowalne)
// ═══════════════════════════════════════════════════════════════════════════

/// Progi decyzji. Domyślne = najostrzejsze z norm opisanych w nagłówku.
class WeatherThresholds {
  const WeatherThresholds({
    this.minAmbientC = kDefaultMinAmbientC,
    this.coldBaseMetalC = kDefaultColdBaseMetalC,
    this.coldPreheatC = kDefaultColdPreheatC,
    this.minMaterialC = kDefaultMinMaterialC,
    this.dewMarginK = kDefaultDewMarginK,
    this.maxWindGasMs = kDefaultMaxWindGasMs,
    this.maxWindAnyMs = kDefaultMaxWindAnyMs,
  });

  /// Poniżej tej temperatury przy złączu nie spawa się wcale.
  final double minAmbientC;

  /// Stal węglowa/niskostopowa poniżej tej temperatury → podgrzać do
  /// [coldPreheatC].
  final double coldBaseMetalC;
  final double coldPreheatC;

  /// Minimalna temperatura materiału przy spawaniu (każdy materiał).
  final double minMaterialC;

  /// Wymagany zapas temperatury powierzchni nad punktem rosy [K].
  final double dewMarginK;

  /// Maks. wiatr przy spoinie dla procesów w osłonie gazowej [m/s].
  final double maxWindGasMs;

  /// „Silny wiatr” — powyżej nie spawa się bez zamkniętego namiotu [m/s].
  final double maxWindAnyMs;

  /// AWS D1.1:2020 7.11.2 [A1, A2]: 0 °F = −17,8 °C. Norma w jednostkach SI
  /// zaokrągla do −20 °C (źródła wtórne); przyjęto ostrzejsze −18 °C.
  static const double kDefaultMinAmbientC = -18;

  /// AWS D1.1:2020 Table 5.8 [A1, A2]: metal poniżej 32 °F = 0 °C …
  static const double kDefaultColdBaseMetalC = 0;

  /// … podgrzać do ≥ 70 °F = 21,1 °C (w SI spotykane 20 °C); przyjęto 21 °C.
  static const double kDefaultColdPreheatC = 21;

  /// ASME B31.3 Table 330.1.1 [B1]: 10 °C (50 °F).
  static const double kDefaultMinMaterialC = 10;

  /// ISO 8502-4 — praktyka malarska [I1].
  static const double kDefaultDewMarginK = 3;

  /// AWS D1.1:2020 7.11.1 [A1, A2]: 5 mph = 2,235 m/s ≈ 8 km/h (2,22 m/s);
  /// zaokrąglone w dół do 2,2 m/s.
  static const double kDefaultMaxWindGasMs = 2.2;

  /// Próg praktyczny — dolna granica 6° Beauforta („silny wiatr”). Normy
  /// mówią tylko „high wind” bez liczby [A2, E1, E2].
  static const double kDefaultMaxWindAnyMs = 10.8;

  static const WeatherThresholds defaults = WeatherThresholds();

  bool get isDefault =>
      minAmbientC == kDefaultMinAmbientC &&
      coldBaseMetalC == kDefaultColdBaseMetalC &&
      coldPreheatC == kDefaultColdPreheatC &&
      minMaterialC == kDefaultMinMaterialC &&
      dewMarginK == kDefaultDewMarginK &&
      maxWindGasMs == kDefaultMaxWindGasMs &&
      maxWindAnyMs == kDefaultMaxWindAnyMs;

  WeatherThresholds copyWith({
    double? minAmbientC,
    double? coldBaseMetalC,
    double? coldPreheatC,
    double? minMaterialC,
    double? dewMarginK,
    double? maxWindGasMs,
    double? maxWindAnyMs,
  }) =>
      WeatherThresholds(
        minAmbientC: minAmbientC ?? this.minAmbientC,
        coldBaseMetalC: coldBaseMetalC ?? this.coldBaseMetalC,
        coldPreheatC: coldPreheatC ?? this.coldPreheatC,
        minMaterialC: minMaterialC ?? this.minMaterialC,
        dewMarginK: dewMarginK ?? this.dewMarginK,
        maxWindGasMs: maxWindGasMs ?? this.maxWindGasMs,
        maxWindAnyMs: maxWindAnyMs ?? this.maxWindAnyMs,
      );

  Map<String, Object?> toJson() => {
        'minAmbientC': minAmbientC,
        'coldBaseMetalC': coldBaseMetalC,
        'coldPreheatC': coldPreheatC,
        'minMaterialC': minMaterialC,
        'dewMarginK': dewMarginK,
        'maxWindGasMs': maxWindGasMs,
        'maxWindAnyMs': maxWindAnyMs,
      };

  /// Odporne: brak pola, zły typ albo wartość spoza zakresu → wartość
  /// domyślna tego pola. Nigdy nie rzuca. Czy coś naprawiono — patrz
  /// [decodeWeatherThresholdsDetailed].
  factory WeatherThresholds.fromJson(Object? json) =>
      _thresholdsFromJson(json).thresholds;

  /// Wartość progu po kluczu z [ThresholdField].
  double valueOf(String field) => switch (field) {
        ThresholdField.minAmbientC => minAmbientC,
        ThresholdField.coldBaseMetalC => coldBaseMetalC,
        ThresholdField.coldPreheatC => coldPreheatC,
        ThresholdField.minMaterialC => minMaterialC,
        ThresholdField.dewMarginK => dewMarginK,
        ThresholdField.maxWindGasMs => maxWindGasMs,
        ThresholdField.maxWindAnyMs => maxWindAnyMs,
        _ => throw ArgumentError.value(field, 'field'),
      };

  /// Progi z mapy pole → wartość (brakujące pola — z [this]).
  WeatherThresholds withValues(Map<String, double> v) => WeatherThresholds(
        minAmbientC: v[ThresholdField.minAmbientC] ?? minAmbientC,
        coldBaseMetalC: v[ThresholdField.coldBaseMetalC] ?? coldBaseMetalC,
        coldPreheatC: v[ThresholdField.coldPreheatC] ?? coldPreheatC,
        minMaterialC: v[ThresholdField.minMaterialC] ?? minMaterialC,
        dewMarginK: v[ThresholdField.dewMarginK] ?? dewMarginK,
        maxWindGasMs: v[ThresholdField.maxWindGasMs] ?? maxWindGasMs,
        maxWindAnyMs: v[ThresholdField.maxWindAnyMs] ?? maxWindAnyMs,
      );
}

/// Klucze progów (JSON i pola ekranu ustawień).
abstract final class ThresholdField {
  static const minAmbientC = 'minAmbientC';
  static const coldBaseMetalC = 'coldBaseMetalC';
  static const coldPreheatC = 'coldPreheatC';
  static const minMaterialC = 'minMaterialC';
  static const dewMarginK = 'dewMarginK';
  static const maxWindGasMs = 'maxWindGasMs';
  static const maxWindAnyMs = 'maxWindAnyMs';

  static const all = [
    minAmbientC,
    coldBaseMetalC,
    coldPreheatC,
    minMaterialC,
    dewMarginK,
    maxWindGasMs,
    maxWindAnyMs,
  ];

  /// Limity górne (wiatr) — łagodniej = WIĘCEJ. Reszta to minima —
  /// łagodniej = MNIEJ.
  static const upperLimits = {maxWindGasMs, maxWindAnyMs};
}

/// Dopuszczalny zakres pojedynczego progu (ten sam przy odczycie JSON
/// i na ekranie ustawień).
bool thresholdInRange(String field, double v) {
  if (!v.isFinite) return false;
  return switch (field) {
    ThresholdField.dewMarginK => v >= 0 && v <= 30,
    ThresholdField.maxWindGasMs ||
    ThresholdField.maxWindAnyMs =>
      v > 0 && v <= 60,
    _ => v >= -60 && v <= 400,
  };
}

({WeatherThresholds thresholds, bool repaired}) _thresholdsFromJson(
    Object? json) {
  if (json is! Map) {
    return (thresholds: WeatherThresholds.defaults, repaired: true);
  }
  var repaired = false;
  final values = <String, double>{};
  for (final f in ThresholdField.all) {
    final v = _numOrNull(json[f]);
    if (v != null && thresholdInRange(f, v)) {
      values[f] = v;
    } else {
      repaired = true;
    }
  }
  return (
    thresholds: WeatherThresholds.defaults.withValues(values),
    repaired: repaired,
  );
}

/// Progi z zapisanego JSON-a. `repaired` — zapis był uszkodzony (zły JSON,
/// brak pola, wartość spoza zakresu) i część progów (albo wszystkie)
/// zastąpiono domyślnymi; ekran MUSI to pokazać — ostrzejsze progi projektu
/// nie mogą po cichu zamienić się w domyślne. Puste/brak zapisu → domyślne,
/// bez naprawy.
({WeatherThresholds thresholds, bool repaired}) decodeWeatherThresholdsDetailed(
    String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return (thresholds: WeatherThresholds.defaults, repaired: false);
  }
  try {
    return _thresholdsFromJson(jsonDecode(raw));
  } on FormatException {
    return (thresholds: WeatherThresholds.defaults, repaired: true);
  }
}

/// Progi z zapisanego JSON-a; uszkodzony / pusty → domyślne.
WeatherThresholds decodeWeatherThresholds(String? raw) =>
    decodeWeatherThresholdsDetailed(raw).thresholds;

/// Błędy krzyżowe progów (pole, przy którym pokazać błąd).
enum ThresholdIssue {
  /// Wartość spoza zakresu pola.
  outOfRange,

  /// Podgrzanie zimnej stali niżej niż próg „zimnej” stali.
  preheatBelowColdThreshold,

  /// Minimum materiału niższe niż minimum temperatury przy złączu.
  materialBelowAmbient,

  /// Próg silnego wiatru niższy niż limit dla procesów gazowych.
  strongWindBelowGas,
}

/// Walidacja progów: pole → problem. Pusta mapa → można zapisać.
Map<String, ThresholdIssue> validateWeatherThresholds(WeatherThresholds t) {
  final out = <String, ThresholdIssue>{};
  for (final f in ThresholdField.all) {
    if (!thresholdInRange(f, t.valueOf(f))) out[f] = ThresholdIssue.outOfRange;
  }
  if (!out.containsKey(ThresholdField.coldPreheatC) &&
      t.coldPreheatC < t.coldBaseMetalC) {
    out[ThresholdField.coldPreheatC] = ThresholdIssue.preheatBelowColdThreshold;
  }
  if (!out.containsKey(ThresholdField.minMaterialC) &&
      t.minMaterialC < t.minAmbientC) {
    out[ThresholdField.minMaterialC] = ThresholdIssue.materialBelowAmbient;
  }
  if (!out.containsKey(ThresholdField.maxWindAnyMs) &&
      t.maxWindAnyMs < t.maxWindGasMs) {
    out[ThresholdField.maxWindAnyMs] = ThresholdIssue.strongWindBelowGas;
  }
  return out;
}

/// Pola, w których próg jest ŁAGODNIEJSZY niż domyślny (wartości z norm):
/// minima niższe, limity wiatru wyższe. Werdykt z takimi progami dostaje
/// twarde ostrzeżenie (ekran, tekst, PDF).
List<String> looserThanDefaults(WeatherThresholds t) => [
      for (final f in ThresholdField.all)
        if (ThresholdField.upperLimits.contains(f)
            ? t.valueOf(f) > WeatherThresholds.defaults.valueOf(f)
            : t.valueOf(f) < WeatherThresholds.defaults.valueOf(f))
          f,
    ];

/// Nazwa progu do komunikatów (PL/EN).
String thresholdLabel(String field, {required bool english}) => switch (field) {
      ThresholdField.minAmbientC => _tr(english, 'min. temperatura przy złączu',
          'min. temperature at the joint'),
      ThresholdField.coldBaseMetalC => _tr(
          english, 'stal węglowa „zimna” poniżej', 'carbon steel “cold” below'),
      ThresholdField.coldPreheatC => _tr(english,
          'podgrzanie zimnej stali węglowej', 'preheat of cold carbon steel'),
      ThresholdField.minMaterialC => _tr(
          english, 'min. temperatura materiału', 'min. base metal temperature'),
      ThresholdField.dewMarginK =>
        _tr(english, 'zapas nad punktem rosy', 'margin above dew point'),
      ThresholdField.maxWindGasMs =>
        _tr(english, 'wiatr — procesy gazowe', 'wind — gas-shielded processes'),
      ThresholdField.maxWindAnyMs => _tr(english, 'silny wiatr', 'strong wind'),
      _ => field,
    };

/// Jednostka progu.
String thresholdUnit(String field) => switch (field) {
      ThresholdField.dewMarginK => 'K',
      ThresholdField.maxWindGasMs || ThresholdField.maxWindAnyMs => 'm/s',
      _ => '°C',
    };

String encodeWeatherThresholds(WeatherThresholds t) => jsonEncode(t.toJson());

// ═══════════════════════════════════════════════════════════════════════════
// Podstawy (teksty źródeł pokazywane przy każdym punkcie)
// ═══════════════════════════════════════════════════════════════════════════

/// Podstawa punktu: PL i EN.
class WeatherBasis {
  const WeatherBasis(this.pl, this.en);
  final String pl;
  final String en;
  String text(bool english) => english ? en : pl;
}

// Kody źródeł w nawiasach kwadratowych — nagłówek pliku.

/// [A1, A2]
const kBasisAwsAmbient = WeatherBasis(
    'AWS D1.1:2020 §7.11.2 — nie spawać poniżej 0 °F (−17,8 °C) przy '
        'spoinie; ogrzewana obudowa dopuszczalna (C-7.11.2)',
    'AWS D1.1:2020 §7.11.2 — no welding below 0 °F (−17.8 °C) at the weld; '
        'a heated enclosure is allowed (C-7.11.2)');

/// [A1, A2]
const kBasisAwsWet = WeatherBasis(
    'AWS D1.1:2020 §7.11.2 — nie spawać na powierzchniach mokrych ani '
        'wystawionych na deszcz lub śnieg',
    'AWS D1.1:2020 §7.11.2 — no welding on surfaces that are wet or exposed '
        'to rain or snow');

/// [A1, A2]
const kBasisAwsWelder = WeatherBasis(
    'AWS D1.1:2020 §7.11.2 — nie spawać, gdy spawacz jest wystawiony na '
        'niesprzyjające warunki',
    'AWS D1.1:2020 §7.11.2 — no welding when the welder is exposed to '
        'inclement conditions');

/// [A1, A2]
const kBasisAwsWindGas = WeatherBasis(
    'AWS D1.1:2020 §7.11.1 — GMAW, GTAW, EGW, FCAW-G: wiatr przy spoinie '
        'maks. 5 mph (2,24 m/s; w SI norma pisze 8 km/h), inaczej osłona. '
        'Domyślny próg aplikacji 2,2 m/s ≈ 7,9 km/h — wpisane 8 km/h '
        '(2,22 m/s) jest już powyżej',
    'AWS D1.1:2020 §7.11.1 — GMAW, GTAW, EGW, FCAW-G: wind at the weld max. '
        '5 mph (2.24 m/s; the SI text says 8 km/h), otherwise a shelter. The '
        'app default 2.2 m/s ≈ 7.9 km/h — an entered 8 km/h (2.22 m/s) is '
        'already above it');

/// Bez normy — opisane jako próg praktyczny.
const kBasisFlameWind = WeatherBasis(
    'Próg praktyczny — AWS D1.1 nie obejmuje spawania gazowego 311; płomień '
        'jest wrażliwy na przeciąg, przyjęto limit procesów w osłonie gazowej',
    'Practical threshold — AWS D1.1 does not cover oxy-fuel welding 311; the '
        'flame is draught-sensitive, the gas-shielded limit is used');

/// [A2, E1, E2] — liczba to próg praktyczny.
const kBasisHighWind = WeatherBasis(
    'AWS D1.1:2020 §7.11.2 zakazuje spawania przy „dużej prędkości wiatru”, '
        'EN 1090-2 §7.5.3 wymaga osłony — bez liczby; domyślne 10,8 m/s '
        '(6° Beauforta) to próg praktyczny aplikacji — ustaw wg specyfikacji',
    'AWS D1.1:2020 §7.11.2 forbids welding in “high wind”, EN 1090-2 §7.5.3 '
        'requires protection — no number; the default 10.8 m/s (Beaufort 6) '
        'is the app’s practical threshold — set it per specification');

/// [E1, E2]
const kBasisEn1090Weather = WeatherBasis(
    'EN 1090-2 §7.5.3, EN 1011-1:2009 §5.2 — spawacz i stanowisko chronione '
        'przed wiatrem, deszczem i śniegiem',
    'EN 1090-2 §7.5.3, EN 1011-1:2009 §5.2 — welder and workplace protected '
        'from wind, rain and snow');

/// [A1, A2]
const kBasisAwsColdPreheat = WeatherBasis(
    'AWS D1.1:2020 Tab. 5.8 (stal węglowa i niskostopowa) — metal poniżej '
        '32 °F (0 °C) podgrzać do ≥ 70 °F (21 °C) i utrzymać jako min. '
        'temperaturę międzyściegową',
    'AWS D1.1:2020 Table 5.8 (carbon and low-alloy steel) — base metal below '
        '32 °F (0 °C): preheat to ≥ 70 °F (21 °C) and hold as the min. '
        'interpass temperature');

/// [B1]
const kBasisB313MinTemp = WeatherBasis(
    'ASME B31.3 Tab. 330.1.1 (wyd. 2020/2024) — wymagana min. temperatura '
        '10 °C (50 °F) dla większości materiałów (B31.1 §131.4: też 10 °C)',
    'ASME B31.3 Table 330.1.1 (2020/2024 eds.) — required min. temperature '
        '10 °C (50 °F) for most materials (B31.1 §131.4: also 10 °C)');

const kBasisWps = WeatherBasis(
    'WPS — minimalne podgrzewanie z kwalifikowanej technologii',
    'WPS — minimum preheat of the qualified procedure');

/// [I1]
const kBasisIso8502 = WeatherBasis(
    'ISO 8502-4 — powierzchnia ≥ punkt rosy + 3 K: dobra praktyka z malowania '
        '(przeciw kondensacji), nie wymóg norm spawalniczych',
    'ISO 8502-4 — surface ≥ dew point + 3 K: coating good practice (against '
        'condensation), not a welding-code requirement');

/// [I1]
const kBasisIso8502Measure = WeatherBasis(
    'ISO 8502-4 — metoda: zmierzyć temperaturę i wilgotność powietrza oraz '
        'temperaturę powierzchni elementu',
    'ISO 8502-4 — method: measure air temperature and humidity and the '
        'surface temperature of the part');

/// [S1]
const kBasisDry = WeatherBasis(
    'SCI GN 7.01 — przed spawaniem ogrzać złącze, by usunąć wilgoć (np. '
        'poranną kondensację)',
    'SCI GN 7.01 — warm the joint before welding to drive off moisture (e.g. '
        'morning condensation)');

/// [B2]
const kBasisHeatZone = WeatherBasis(
    'ASME B31.3 §330.1.4 — strefa: większe z 75 mm i 1,5 × grubości; '
        'AWS D1.1 — ≥ grubość najgrubszej części, min. 75 mm',
    'ASME B31.3 §330.1.4 — zone: larger of 75 mm and 1.5 × thickness; '
        'AWS D1.1 — ≥ thickest part, min. 75 mm');

/// [A2] + praktyka.
const kBasisHotWeld = WeatherBasis(
    'Praktyka; AWS D1.1:2020 §7.11.2 — złącze nie może być mokre ani '
        'wystawione na deszcz lub śnieg',
    'Practice; AWS D1.1:2020 §7.11.2 — the joint must not be wet or exposed '
        'to rain or snow');

/// [A1, A3, E1]
const kBasisElectrodes = WeatherBasis(
    'AWS D1.1:2020 §7.3.2, Tab. 7.1 — ekspozycja elektrod niskowodorowych; '
        'EN 1090-2:2018 §7.5.2 — przechowywanie i suszenie wg producenta',
    'AWS D1.1:2020 §7.3.2, Table 7.1 — exposure of low-hydrogen electrodes; '
        'EN 1090-2:2018 §7.5.2 — storage and drying per manufacturer');

/// [E1]
const kBasisConsumables = WeatherBasis(
    'EN 1090-2:2018 §7.5.2 — przechowywanie i suszenie materiałów '
        'dodatkowych wg producenta',
    'EN 1090-2:2018 §7.5.2 — storage and drying of consumables per '
        'manufacturer');

/// Bez normy — dobra praktyka.
const kBasisAluminium = WeatherBasis(
    'Dobra praktyka (wilgoć to źródło wodoru i porowatości w Al); szczegóły '
        '— WPS i producent spoiwa',
    'Good practice (moisture is a hydrogen source and causes porosity in Al); '
        'details — WPS and filler manufacturer');

/// [A3]: czasy z D1.1 Tab. 7.1 (za LANL GWS 1-03), piec ≥ 120 °C (250 °F).
const _kRecElectrodesPl =
    'Elektrody zasadowe (niskowodorowe) trzymaj w piecyku / termosie '
    '(≥ 120 °C). Poza nim najdłużej: E70XX (np. E7018) 4 h, E80XX 2 h, '
    'E90XX 1 h, E100XX–E110XX 0,5 h — potem suszenie wg producenta albo '
    'odrzucenie.';
const _kRecElectrodesEn =
    'Keep basic (low-hydrogen) electrodes in a holding oven / quiver '
    '(≥ 120 °C). Out of it at most: E70XX (e.g. E7018) 4 h, E80XX 2 h, '
    'E90XX 1 h, E100XX–E110XX 0.5 h — then rebake per manufacturer or '
    'discard.';

// ═══════════════════════════════════════════════════════════════════════════
// Ocena
// ═══════════════════════════════════════════════════════════════════════════

enum FindingSeverity { ok, condition, stop }

enum WeatherVerdict { go, conditional, noGo }

/// Jeden punkt oceny: co sprawdzono, co z tego wynika, na jakiej podstawie.
class WeatherFinding {
  const WeatherFinding({
    required this.code,
    required this.severity,
    required this.textPl,
    required this.textEn,
    required this.basis,
  });

  /// Trwały kod (zapisywany w historii przy odhaczonych warunkach).
  final String code;
  final FindingSeverity severity;
  final String textPl;
  final String textEn;
  final List<WeatherBasis> basis;

  String text(bool english) => english ? textEn : textPl;
  String basisText(bool english) =>
      basis.map((b) => b.text(english)).join(' · ');
}

/// Kody punktów oceny.
abstract final class WeatherCode {
  static const ambient = 'ambient';
  static const precipitation = 'precipitation';
  static const surfaceState = 'surface_state';
  static const windHigh = 'wind_high';
  static const windGas = 'wind_gas';
  static const condensation = 'condensation';
  static const materialTemp = 'material_temp';
  static const recMeasureSurface = 'rec_measure_surface';
  static const recHeatZone = 'rec_heat_zone';
  static const recHotWeld = 'rec_hot_weld';
  static const recElectrodes = 'rec_electrodes';
  static const recFlux = 'rec_flux';
  static const recWire = 'rec_wire';
  static const recAluminium = 'rec_aluminium';
  static const recWelder = 'rec_welder';
}

/// Wersja reguł oceny. Podbij przy każdej zmianie progów, punktów albo
/// logiki werdyktu — wpis historii zapisany inną wersją jest oznaczany jako
/// „odtworzony inną wersją reguł”.
///   1 — pierwsze wydanie (2026-10-17),
///   2 — stan powierzchni złącza, precyzja liczb w tekstach (2026-10-17).
const int kWeatherRulesVersion = 2;

class WeatherAssessment {
  const WeatherAssessment({
    required this.input,
    required this.thresholds,
    required this.surfaceC,
    required this.surfaceAssumed,
    required this.dewPointC,
    required this.frostPointC,
    required this.condensationPointC,
    required this.requiredMaterialC,
    required this.findings,
    required this.recommendations,
  });

  final WeatherInput input;
  final WeatherThresholds thresholds;

  /// Temperatura powierzchni użyta w ocenie.
  final double surfaceC;

  /// true — brak pomiaru, przyjęto temperaturę powietrza.
  final bool surfaceAssumed;
  final double dewPointC;

  /// Punkt szronu — tylko gdy punkt rosy < 0 °C.
  final double? frostPointC;

  /// Rosa albo szron osiada poniżej tej temperatury.
  final double condensationPointC;

  /// Minimalna temperatura materiału przy spawaniu (materiał, mróz, WPS).
  final double requiredMaterialC;

  /// Sprawdzone warunki: OK, do spełnienia albo blokujące.
  final List<WeatherFinding> findings;

  /// Zalecenia praktyczne (nie wpływają na werdykt).
  final List<WeatherFinding> recommendations;

  /// Zapas temperatury powierzchni nad punktem rosy/szronu [K].
  double get marginK => surfaceC - condensationPointC;

  /// Temperatura, do której trzeba doprowadzić złącze: wymagania
  /// materiałowe i zapas nad punktem rosy.
  double get targetSurfaceC =>
      math.max(requiredMaterialC, condensationPointC + thresholds.dewMarginK);

  List<WeatherFinding> get stops =>
      findings.where((f) => f.severity == FindingSeverity.stop).toList();
  List<WeatherFinding> get conditions =>
      findings.where((f) => f.severity == FindingSeverity.condition).toList();
  List<WeatherFinding> get passed =>
      findings.where((f) => f.severity == FindingSeverity.ok).toList();

  List<String> get stopCodes => [for (final f in stops) f.code];
  List<String> get conditionCodes => [for (final f in conditions) f.code];

  /// Progi łagodniejsze od domyślnych (z norm) — werdykt dostaje twarde
  /// ostrzeżenie na ekranie, w tekście i w PDF.
  List<String> get looserThresholds => looserThanDefaults(thresholds);

  WeatherVerdict get verdict {
    if (findings.any((f) => f.severity == FindingSeverity.stop)) {
      return WeatherVerdict.noGo;
    }
    if (findings.any((f) => f.severity == FindingSeverity.condition)) {
      return WeatherVerdict.conditional;
    }
    return WeatherVerdict.go;
  }
}

String weatherVerdictText(WeatherVerdict v, {required bool english}) =>
    switch (v) {
      WeatherVerdict.go => _tr(english, 'Można spawać', 'OK to weld'),
      WeatherVerdict.conditional => _tr(
          english,
          'Można spawać po spełnieniu warunków',
          'Weld only once the conditions are met'),
      WeatherVerdict.noGo => _tr(english, 'Nie spawać', 'Do not weld'),
    };

/// Twarde ostrzeżenie przy progach łagodniejszych od norm (null — brak).
String? weatherLooserWarning(WeatherThresholds t, {required bool english}) {
  final fields = looserThanDefaults(t);
  if (fields.isEmpty) return null;
  final list = [
    for (final f in fields)
      '${thresholdLabel(f, english: english)} '
          '${weatherNumAuto(t.valueOf(f), english: english)} '
          '${thresholdUnit(f)} '
          '(${_tr(english, 'norma', 'code')} '
          '${weatherNumAuto(WeatherThresholds.defaults.valueOf(f), english: english)})',
  ].join('; ');
  return _tr(
      english,
      'UWAGA: progi łagodniejsze niż wartości z norm — $list. Werdykt '
          'obowiązuje tylko, jeśli tak dopuszcza specyfikacja projektu / WPS.',
      'WARNING: thresholds looser than the code values — $list. The verdict '
          'holds only if the project specification / WPS allows it.');
}

/// Ocena warunków. `null`, gdy temperatura powietrza / wilgotność są spoza
/// zakresu wzoru (−60…60 °C, 0 < RH ≤ 100 %).
///
/// Liczby w tekstach: wartości wpisane i progi — z precyzją pola (do 2
/// miejsc, bez zbędnych zer); porównania („a > b”) — tyle miejsc, żeby
/// relacja była widoczna ([weatherPair]); temperatury do osiągnięcia —
/// zaokrąglone w górę ([weatherNumMin]), limity wiatru — w dół
/// ([weatherNumMax]).
WeatherAssessment? assessWeather(WeatherInput input,
    [WeatherThresholds t = WeatherThresholds.defaults]) {
  final dew = dewPointC(airC: input.ambientC, rhPct: input.rhPct);
  final cond = condensationPointC(airC: input.ambientC, rhPct: input.rhPct);
  if (dew == null || cond == null) return null;
  final frost =
      dew < 0 ? frostPointC(airC: input.ambientC, rhPct: input.rhPct) : null;
  final surface = input.surfaceC ?? input.ambientC;
  final assumed = input.surfaceC == null;

  String v(double x, bool en) => weatherNumAuto(x, english: en);
  String kmh(double ms, bool en) =>
      weatherNumAuto(msToKmh(ms), maxDecimals: 1, english: en);
  final findings = <WeatherFinding>[];
  final recs = <WeatherFinding>[];
  final enclosure = input.shelter == WeatherShelter.enclosure;
  final w = input.windMs;

  // ── 1. Temperatura otoczenia ────────────────────────────────────────────
  final (ambPl, minPl) = weatherPair(input.ambientC, t.minAmbientC);
  final (ambEn, minEn) =
      weatherPair(input.ambientC, t.minAmbientC, english: true);
  if (input.ambientC < t.minAmbientC) {
    findings.add(enclosure
        ? WeatherFinding(
            code: WeatherCode.ambient,
            severity: FindingSeverity.condition,
            textPl: 'Mróz $ambPl °C (poniżej $minPl °C): spawaj tylko '
                'w ogrzewanym namiocie — przy złączu co najmniej $minPl °C.',
            textEn: 'Frost $ambEn °C (below $minEn °C): weld only in a heated '
                'enclosure — at least $minEn °C next to the joint.',
            basis: const [kBasisAwsAmbient],
          )
        : WeatherFinding(
            code: WeatherCode.ambient,
            severity: FindingSeverity.stop,
            textPl: 'Temperatura $ambPl °C jest poniżej $minPl °C — bez '
                'ogrzewanego namiotu nie spawać.',
            textEn: 'Temperature $ambEn °C is below $minEn °C — do not weld '
                'without a heated enclosure.',
            basis: const [kBasisAwsAmbient],
          ));
  } else {
    findings.add(WeatherFinding(
      code: WeatherCode.ambient,
      severity: FindingSeverity.ok,
      textPl: 'Temperatura powietrza $ambPl °C ≥ $minPl °C.',
      textEn: 'Air temperature $ambEn °C ≥ $minEn °C.',
      basis: const [kBasisAwsAmbient],
    ));
  }

  // ── 2. Opad ─────────────────────────────────────────────────────────────
  if (input.precipitation != Precipitation.none) {
    final pPl = input.precipitation.label(false);
    final pEn = input.precipitation.label(true);
    findings.add(enclosure
        ? WeatherFinding(
            code: WeatherCode.precipitation,
            severity: FindingSeverity.condition,
            textPl: 'Opad ($pPl): spawaj tylko pod dachem namiotu — złącze '
                'i spawacz osłonięci, brzegi suche, gorąca spoina osłonięta '
                'do ostygnięcia.',
            textEn: 'Precipitation ($pEn): weld only under the roof of the '
                'enclosure — joint and welder covered, edges dry, the hot '
                'weld covered until it cools.',
            basis: const [kBasisAwsWet, kBasisEn1090Weather],
          )
        : WeatherFinding(
            code: WeatherCode.precipitation,
            severity: FindingSeverity.stop,
            textPl: 'Opad ($pPl) — bez namiotu nie spawać: mokre brzegi, '
                'woda na gorącej spoinie.'
                '${input.shelter == WeatherShelter.windbreak ? ' Parawan nie chroni przed opadem.' : ''}',
            textEn: 'Precipitation ($pEn) — do not weld without an enclosure: '
                'wet edges, water on the hot weld.'
                '${input.shelter == WeatherShelter.windbreak ? ' A windbreak does not keep rain or snow off.' : ''}',
            basis: const [kBasisAwsWet, kBasisEn1090Weather],
          ));
  } else {
    findings.add(const WeatherFinding(
      code: WeatherCode.precipitation,
      severity: FindingSeverity.ok,
      textPl: 'Brak opadu.',
      textEn: 'No precipitation.',
      basis: [kBasisAwsWet],
    ));
  }

  // ── 3. Stan powierzchni złącza (ocena spawacza) ─────────────────────────
  final wetOrFrozen = input.surfaceState == SurfaceState.wet ||
      input.surfaceState == SurfaceState.frozen;
  final whatPl = input.surfaceState == SurfaceState.frozen
      ? 'pokryte szronem, lodem lub śniegiem'
      : 'wilgotne / mokre';
  final whatEn = input.surfaceState == SurfaceState.frozen
      ? 'covered with frost, ice or snow'
      : 'damp / wet';
  switch (input.surfaceState) {
    case SurfaceState.unchecked:
      findings.add(const WeatherFinding(
        code: WeatherCode.surfaceState,
        severity: FindingSeverity.condition,
        textPl: 'Złącze suche, bez wody, szronu, lodu i śniegu — sprawdź '
            '(stan powierzchni nie został wybrany).',
        textEn: 'Joint dry, free of water, frost, ice and snow — check it '
            '(surface condition not selected).',
        basis: [kBasisAwsWet],
      ));
    case SurfaceState.dry:
      findings.add(const WeatherFinding(
        code: WeatherCode.surfaceState,
        severity: FindingSeverity.ok,
        textPl: 'Złącze suche (ocena spawacza).',
        textEn: 'Joint dry (welder’s check).',
        basis: [kBasisAwsWet],
      ));
    case SurfaceState.wet || SurfaceState.frozen:
      findings.add(enclosure
          ? WeatherFinding(
              code: WeatherCode.surfaceState,
              severity: FindingSeverity.condition,
              textPl: 'Złącze $whatPl: osusz / ogrzej je w namiocie (usuń '
                  'wodę, szron, lód, śnieg) — spawaj dopiero na suchym.',
              textEn: 'Joint $whatEn: dry / warm it inside the enclosure '
                  '(remove water, frost, ice, snow) — weld only when dry.',
              basis: const [kBasisAwsWet, kBasisDry],
            )
          : WeatherFinding(
              code: WeatherCode.surfaceState,
              severity: FindingSeverity.stop,
              textPl: 'Złącze $whatPl — bez namiotu nie spawać. Postaw '
                  'namiot i osusz / ogrzej złącze.',
              textEn: 'Joint $whatEn — do not weld without an enclosure. Put '
                  'up an enclosure and dry / warm the joint.',
              basis: const [kBasisAwsWet, kBasisEn1090Weather],
            ));
  }

  // ── 4. Wiatr ────────────────────────────────────────────────────────────
  // Limit gazowy pokazywany zaokrąglony W DÓŁ (km/h też): 2,2 m/s ≈ 7,9 km/h.
  final gasPl = '${weatherNumMax(t.maxWindGasMs)} m/s '
      '(≈ ${weatherNumAuto(floorTo(msToKmh(t.maxWindGasMs), 1), maxDecimals: 1)} km/h)';
  final gasEn = '${weatherNumMax(t.maxWindGasMs, english: true)} m/s '
      '(≈ ${weatherNumAuto(floorTo(msToKmh(t.maxWindGasMs), 1), maxDecimals: 1, english: true)} km/h)';
  final procPl = input.process.label(false);
  final procEn = input.process.label(true);
  final gasBasis = input.process.shield == ShieldKind.flame
      ? kBasisFlameWind
      : kBasisAwsWindGas;
  if (w > t.maxWindAnyMs) {
    final (wPl, anyPl) = weatherPair(w, t.maxWindAnyMs);
    final (wEn, anyEn) = weatherPair(w, t.maxWindAnyMs, english: true);
    findings.add(enclosure
        ? WeatherFinding(
            code: WeatherCode.windHigh,
            severity: FindingSeverity.condition,
            textPl: 'Silny wiatr $wPl m/s (${kmh(w, false)} km/h; próg '
                '$anyPl m/s): tylko w zamkniętym, zabezpieczonym namiocie'
                '${input.process.windSensitive ? '; przy spoinie ≤ $gasPl' : ''}.',
            textEn: 'Strong wind $wEn m/s (${kmh(w, true)} km/h; threshold '
                '$anyEn m/s): only inside a closed, secured enclosure'
                '${input.process.windSensitive ? '; at the weld ≤ $gasEn' : ''}.',
            basis: [kBasisHighWind, if (input.process.windSensitive) gasBasis],
          )
        : WeatherFinding(
            code: WeatherCode.windHigh,
            severity: FindingSeverity.stop,
            textPl: 'Silny wiatr $wPl m/s (${kmh(w, false)} km/h) > $anyPl m/s '
                '— bez zamkniętego namiotu nie spawać.',
            textEn: 'Strong wind $wEn m/s (${kmh(w, true)} km/h) > $anyEn m/s '
                '— do not weld without a closed enclosure.',
            basis: [kBasisHighWind, if (input.process.windSensitive) gasBasis],
          ));
  } else if (input.process.windSensitive && w > t.maxWindGasMs) {
    final (wPl, limPl) = weatherPair(w, t.maxWindGasMs);
    final (wEn, limEn) = weatherPair(w, t.maxWindGasMs, english: true);
    findings.add(input.shelter == WeatherShelter.none
        ? WeatherFinding(
            code: WeatherCode.windGas,
            severity: FindingSeverity.stop,
            textPl: '$procPl: wiatr $wPl m/s (${kmh(w, false)} km/h) > '
                '$limPl m/s — bez osłony nie spawać. Postaw parawan/namiot '
                'albo spawaj metodą bez gazu (111, 114).',
            textEn: '$procEn: wind $wEn m/s (${kmh(w, true)} km/h) > '
                '$limEn m/s — do not weld without a shelter. Put up a '
                'windbreak/enclosure or use a process without shielding gas '
                '(111, 114).',
            basis: [gasBasis],
          )
        : WeatherFinding(
            code: WeatherCode.windGas,
            severity: FindingSeverity.condition,
            textPl: 'Osłona musi obniżyć wiatr przy spoinie do ≤ $gasPl '
                '(teraz $wPl m/s) — sprawdź przy jeziorku.',
            textEn: 'The shelter must bring the wind at the weld down to '
                '≤ $gasEn (now $wEn m/s) — check at the weld pool.',
            basis: [gasBasis],
          ));
  } else {
    final (wPl, limPl) = weatherPair(w, t.maxWindGasMs);
    final (wEn, limEn) = weatherPair(w, t.maxWindGasMs, english: true);
    findings.add(WeatherFinding(
      code: WeatherCode.windGas,
      severity: FindingSeverity.ok,
      textPl: input.process.windSensitive
          ? 'Wiatr $wPl m/s ≤ $limPl m/s dla $procPl.'
          : 'Wiatr ${v(w, false)} m/s — $procPl nie ma osłony gazowej, '
              'limit $gasPl go nie dotyczy (poniżej progu silnego wiatru '
              '${weatherNumMax(t.maxWindAnyMs)} m/s).',
      textEn: input.process.windSensitive
          ? 'Wind $wEn m/s ≤ $limEn m/s for $procEn.'
          : 'Wind ${v(w, true)} m/s — $procEn has no shielding gas, the '
              '$gasEn limit does not apply (below the strong-wind threshold '
              '${weatherNumMax(t.maxWindAnyMs, english: true)} m/s).',
      basis: [input.process.windSensitive ? gasBasis : kBasisAwsWindGas],
    ));
  }

  // ── 5. Wilgoć: punkt rosy / szronu ──────────────────────────────────────
  final margin = surface - cond;
  final target = cond + t.dewMarginK;
  final pointPl = frost != null ? 'punkt szronu' : 'punkt rosy';
  final pointEn = frost != null ? 'frost point' : 'dew point';
  final (mPl, needPl) = weatherPair(margin, t.dewMarginK);
  final (mEn, needEn) = weatherPair(margin, t.dewMarginK, english: true);
  if (margin <= 0) {
    final (sPl, cPl) = weatherPair(surface, cond);
    final (sEn, cEn) = weatherPair(surface, cond, english: true);
    findings.add(WeatherFinding(
      code: WeatherCode.condensation,
      severity: FindingSeverity.condition,
      textPl: 'Powierzchnia $sPl °C ≤ $pointPl $cPl °C — na stali jest albo '
          'zaraz będzie ${frost != null ? 'szron' : 'rosa'}. Osusz złącze '
          'grzaniem i utrzymuj ≥ ${weatherNumMin(target)} °C.',
      textEn: 'Surface $sEn °C ≤ $pointEn $cEn °C — '
          '${frost != null ? 'frost' : 'dew'} is or will soon be on the '
          'steel. Dry the joint by heating and keep it ≥ '
          '${weatherNumMin(target, english: true)} °C.',
      basis: const [kBasisAwsWet, kBasisDry, kBasisIso8502],
    ));
  } else if (margin < t.dewMarginK) {
    findings.add(WeatherFinding(
      code: WeatherCode.condensation,
      severity: FindingSeverity.condition,
      textPl: 'Zapas nad punktem ${frost != null ? 'szronu' : 'rosy'} tylko '
          '$mPl K (< $needPl K) — ryzyko kondensacji. Podgrzej złącze do ≥ '
          '${weatherNumMin(target)} °C.',
      textEn: 'Only $mEn K above the $pointEn (< $needEn K) — condensation '
          'risk. Warm the joint to ≥ ${weatherNumMin(target, english: true)} °C.',
      basis: const [kBasisIso8502, kBasisDry],
    ));
  } else {
    findings.add(WeatherFinding(
      code: WeatherCode.condensation,
      severity: FindingSeverity.ok,
      textPl: 'Zapas nad punktem ${frost != null ? 'szronu' : 'rosy'} $mPl K '
          '≥ $needPl K.',
      textEn: '$mEn K above the $pointEn ≥ $needEn K.',
      basis: const [kBasisIso8502],
    ));
  }

  // ── 6. Temperatura materiału (minimum, mróz, WPS) ───────────────────────
  var required = t.minMaterialC;
  final reqBasis = <WeatherBasis>[kBasisB313MinTemp];
  final carbon = input.material == WeatherMaterial.carbonSteel;
  if (carbon && surface < t.coldBaseMetalC) {
    required = math.max(required, t.coldPreheatC);
    reqBasis.add(kBasisAwsColdPreheat);
  }
  final wps = input.wpsPreheatC;
  if (wps != null) {
    required = math.max(required, wps);
    reqBasis.add(kBasisWps);
  }
  final (surPl, reqPl) = weatherPair(surface, required);
  final (surEn, reqEn) = weatherPair(surface, required, english: true);
  if (surface < required) {
    findings.add(WeatherFinding(
      code: WeatherCode.materialTemp,
      severity: FindingSeverity.condition,
      textPl: 'Podgrzej strefę złącza do ≥ ${weatherNumMin(required)} °C '
          'przed spawaniem i utrzymuj ją w trakcie (teraz $surPl °C).',
      textEn: 'Preheat the joint area to ≥ '
          '${weatherNumMin(required, english: true)} °C before welding and '
          'hold it while welding (now $surEn °C).',
      basis: reqBasis,
    ));
  } else {
    findings.add(WeatherFinding(
      code: WeatherCode.materialTemp,
      severity: FindingSeverity.ok,
      textPl: 'Materiał $surPl °C ≥ wymagane $reqPl °C.',
      textEn: 'Base metal $surEn °C ≥ required $reqEn °C.',
      basis: reqBasis,
    ));
  }

  // ── Zalecenia praktyczne ────────────────────────────────────────────────
  if (assumed) {
    recs.add(const WeatherFinding(
      code: WeatherCode.recMeasureSurface,
      severity: FindingSeverity.ok,
      textPl: 'Zmierz temperaturę stali termometrem kontaktowym. Rano i przy '
          'bezchmurnym niebie stal bywa zimniejsza od powietrza — zapas nad '
          'punktem rosy jest wtedy mniejszy, niż pokazuje ocena.',
      textEn: 'Measure the steel temperature with a contact thermometer. In '
          'the morning and under a clear sky steel is often colder than the '
          'air — the margin above the dew point is then smaller than shown.',
      basis: [kBasisIso8502Measure],
    ));
  }
  final heating = wetOrFrozen ||
      findings.any((f) =>
          f.severity == FindingSeverity.condition &&
          (f.code == WeatherCode.materialTemp ||
              f.code == WeatherCode.condensation));
  if (heating || wps != null) {
    recs.add(const WeatherFinding(
      code: WeatherCode.recHeatZone,
      severity: FindingSeverity.ok,
      textPl: 'Grzej i sprawdzaj temperaturę po obu stronach złącza w strefie '
          'co najmniej 75 mm (na grubych ściankach szerzej — patrz podstawa).',
      textEn: 'Heat and check the temperature on both sides of the joint over '
          'at least 75 mm (wider on thick walls — see basis).',
      basis: [kBasisHeatZone],
    ));
  }
  if (input.precipitation != Precipitation.none ||
      input.ambientC < 0 ||
      w > t.maxWindAnyMs) {
    recs.add(const WeatherFinding(
      code: WeatherCode.recHotWeld,
      severity: FindingSeverity.ok,
      textPl: 'Chroń gorącą spoinę przed deszczem, śniegiem i wiatrem aż '
          'ostygnie — gwałtowne chłodzenie sprzyja twardej SWC i pęknięciom. '
          'Przy mrozie przykryj złącze matą izolacyjną.',
      textEn: 'Keep rain, snow and wind off the hot weld until it cools — '
          'quenching promotes a hard HAZ and cracking. In frost cover the '
          'joint with an insulating blanket.',
      basis: [kBasisHotWeld],
    ));
    recs.add(const WeatherFinding(
      code: WeatherCode.recWelder,
      severity: FindingSeverity.ok,
      textPl: 'Spawacz osłonięty przed deszczem, wiatrem i mrozem — '
          'zmarznięty spawacz spawa gorzej.',
      textEn: 'Welder protected from rain, wind and frost — a frozen welder '
          'welds worse.',
      basis: [kBasisAwsWelder],
    ));
  }
  switch (input.process) {
    case WeatherProcess.mma111:
      recs.add(const WeatherFinding(
        code: WeatherCode.recElectrodes,
        severity: FindingSeverity.ok,
        textPl: _kRecElectrodesPl,
        textEn: _kRecElectrodesEn,
        basis: [kBasisElectrodes],
      ));
    case WeatherProcess.saw121:
      recs.add(const WeatherFinding(
        code: WeatherCode.recFlux,
        severity: FindingSeverity.ok,
        textPl: 'Topnik suchy — z suszarki albo nieotwartego worka; '
            'zawilgocony topnik daje wodór i porowatość.',
        textEn: 'Keep the flux dry — from the oven or an unopened bag; damp '
            'flux brings hydrogen and porosity.',
        basis: [kBasisConsumables],
      ));
    case WeatherProcess.fcawG136 || WeatherProcess.fcawS114:
      recs.add(const WeatherFinding(
        code: WeatherCode.recWire,
        severity: FindingSeverity.ok,
        textPl: 'Drut proszkowy chroń przed wilgocią — szpula w podajniku '
            'pod osłoną, na noc do zamkniętego opakowania.',
        textEn: 'Keep flux-cored wire dry — the spool covered in the feeder '
            'and back in a sealed pack overnight.',
        basis: [kBasisConsumables],
      ));
    default:
      break;
  }
  if (input.material == WeatherMaterial.aluminium) {
    recs.add(const WeatherFinding(
      code: WeatherCode.recAluminium,
      severity: FindingSeverity.ok,
      textPl: 'Aluminium: wilgoć i uwodniona warstwa tlenków dają '
          'porowatość wodorową. Odtłuść i oczyść szczotką ze stali '
          'nierdzewnej tuż przed spawaniem, złącze musi być suche.',
      textEn: 'Aluminium: moisture and hydrated oxide cause hydrogen '
          'porosity. Degrease and brush with a stainless brush just before '
          'welding; the joint must be dry.',
      basis: [kBasisAluminium],
    ));
  }

  return WeatherAssessment(
    input: input,
    thresholds: t,
    surfaceC: surface,
    surfaceAssumed: assumed,
    dewPointC: dew,
    frostPointC: frost,
    condensationPointC: cond,
    requiredMaterialC: required,
    findings: List.unmodifiable(findings),
    recommendations: List.unmodifiable(recs),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Historia
// ═══════════════════════════════════════════════════════════════════════════

/// Zapisany pomiar: wejście i progi z chwili zapisu, werdykt i kody STOP /
/// warunków ustalone WTEDY, wersja reguł i odhaczone warunki. Szczegóły na
/// ekranie i w raporcie są odtwarzane bieżącym kodem — gdy wersja reguł albo
/// wynik się różni, wpis jest oznaczany ([rulesMismatch]), a wiąże zapisany
/// werdykt.
class WeatherCheckRecord {
  const WeatherCheckRecord({
    required this.id,
    required this.takenAt,
    this.place = '',
    required this.input,
    this.thresholds = WeatherThresholds.defaults,
    required this.verdict,
    this.checked = const {},
    this.rulesVersion = kWeatherRulesVersion,
    this.stopCodes,
    this.conditionCodes,
  });

  /// Wpis z bieżącej oceny (kody i wersja reguł z chwili zapisu).
  factory WeatherCheckRecord.fromAssessment({
    required String id,
    required DateTime takenAt,
    String place = '',
    required WeatherAssessment assessment,
    Set<String> checked = const {},
  }) =>
      WeatherCheckRecord(
        id: id,
        takenAt: takenAt,
        place: place,
        input: assessment.input,
        thresholds: assessment.thresholds,
        verdict: assessment.verdict,
        checked: {
          for (final c in assessment.conditionCodes)
            if (checked.contains(c)) c,
        },
        stopCodes: assessment.stopCodes,
        conditionCodes: assessment.conditionCodes,
      );

  final String id;
  final DateTime takenAt;

  /// Miejsce / opis (np. „Estakada E-3, spoina 12”).
  final String place;
  final WeatherInput input;
  final WeatherThresholds thresholds;

  /// Werdykt z chwili zapisu — wiąże, nawet gdy reguły się zmieniły.
  final WeatherVerdict verdict;

  /// Kody warunków odhaczonych przez spawacza.
  final Set<String> checked;

  /// Wersja reguł, którą liczono werdykt (wpisy bez pola → 1).
  final int rulesVersion;

  /// Kody STOP i warunków z chwili zapisu (`null` — stary wpis bez nich).
  final List<String>? stopCodes;
  final List<String>? conditionCodes;

  /// Ocena odtworzona z zapisanych danych BIEŻĄCYMI regułami.
  WeatherAssessment? get assessment => assessWeather(input, thresholds);

  /// Szczegóły odtworzone inną wersją reguł albo z innym wynikiem niż
  /// zapisany — ekran, tekst i PDF muszą to powiedzieć.
  bool get rulesMismatch {
    if (rulesVersion != kWeatherRulesVersion) return true;
    final a = assessment;
    if (a == null || a.verdict != verdict) return true;
    bool same(List<String>? saved, List<String> now) =>
        saved == null ||
        ({...saved}.length == {...now}.length && {...saved}.containsAll(now));
    return !same(stopCodes, a.stopCodes) ||
        !same(conditionCodes, a.conditionCodes);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'takenAt': takenAt.toIso8601String(),
        'place': place,
        'input': input.toJson(),
        'thresholds': thresholds.toJson(),
        'verdict': verdict.name,
        'checked': checked.toList()..sort(),
        'rulesVersion': rulesVersion,
        if (stopCodes != null) 'stopCodes': stopCodes,
        if (conditionCodes != null) 'conditionCodes': conditionCodes,
      };

  factory WeatherCheckRecord.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('weather: wpis nie mapą');
    final id = json['id'];
    final takenAt = json['takenAt'];
    if (id is! String || id.isEmpty || takenAt is! String) {
      throw const FormatException('weather: wpis bez id/daty');
    }
    final date = DateTime.tryParse(takenAt);
    if (date == null) throw const FormatException('weather: zła data');
    final input = WeatherInput.fromJson(json['input']);
    WeatherVerdict? verdict;
    for (final v in WeatherVerdict.values) {
      if (v.name == json['verdict']) verdict = v;
    }
    final thresholds = WeatherThresholds.fromJson(json['thresholds']);
    List<String>? codes(Object? raw) => raw is List
        ? [
            for (final c in raw)
              if (c is String) c
          ]
        : null;
    final version = json['rulesVersion'];
    return WeatherCheckRecord(
      id: id,
      takenAt: date,
      place: json['place'] is String ? json['place'] as String : '',
      input: input,
      thresholds: thresholds,
      verdict: verdict ??
          assessWeather(input, thresholds)?.verdict ??
          WeatherVerdict.noGo,
      checked: {...?codes(json['checked'])},
      rulesVersion: version is int ? version : 1,
      stopCodes: codes(json['stopCodes']),
      conditionCodes: codes(json['conditionCodes']),
    );
  }
}

/// Opis rozbieżności reguł do raportu (null — brak).
String? weatherRulesMismatchText(WeatherCheckRecord r,
    {required bool english}) {
  if (!r.rulesMismatch) return null;
  final saved = weatherVerdictText(r.verdict, english: english);
  return _tr(
      english,
      'Szczegóły odtworzone inną wersją reguł (zapis: wersja '
          '${r.rulesVersion}, teraz $kWeatherRulesVersion) — wiąże zapisany '
          'werdykt: $saved.',
      'Details rebuilt with a different rules version (saved: version '
          '${r.rulesVersion}, now $kWeatherRulesVersion) — the saved verdict '
          'governs: $saved.');
}

String encodeWeatherHistory(List<WeatherCheckRecord> records) =>
    jsonEncode([for (final r in records) r.toJson()]);

/// Wynik odczytu historii.
class WeatherHistoryDecode {
  const WeatherHistoryDecode({
    this.records = const [],
    this.skipped = 0,
    this.unreadable = false,
  });

  /// Wpisy czytelne, najnowsze pierwsze.
  final List<WeatherCheckRecord> records;

  /// Wpisy pominięte, bo były uszkodzone.
  final int skipped;

  /// Cały zapis nieczytelny (zły JSON albo nie lista).
  final bool unreadable;

  /// Coś przepadłoby przy nadpisaniu — trzeba zachować kopię surowego tekstu.
  bool get damaged => unreadable || skipped > 0;
}

/// Historia z zapisu ([raw] — wartość prosto z SharedPreferences, dowolnego
/// typu). Nigdy nie rzuca: uszkodzony JSON → [WeatherHistoryDecode.unreadable],
/// uszkodzony pojedynczy wpis jest pomijany i liczony w
/// [WeatherHistoryDecode.skipped].
WeatherHistoryDecode decodeWeatherHistoryDetailed(Object? raw) {
  if (raw == null) return const WeatherHistoryDecode();
  if (raw is! String) return const WeatherHistoryDecode(unreadable: true);
  if (raw.trim().isEmpty) return const WeatherHistoryDecode();
  Object? data;
  try {
    data = jsonDecode(raw);
  } on FormatException {
    return const WeatherHistoryDecode(unreadable: true);
  }
  if (data is! List) return const WeatherHistoryDecode(unreadable: true);
  final out = <WeatherCheckRecord>[];
  var skipped = 0;
  for (final item in data) {
    try {
      out.add(WeatherCheckRecord.fromJson(item));
    } on FormatException {
      skipped++;
    } on TypeError {
      skipped++;
    }
  }
  out.sort((a, b) => b.takenAt.compareTo(a.takenAt));
  return WeatherHistoryDecode(records: out, skipped: skipped);
}

/// Historia z JSON-a (same czytelne wpisy). Nigdy nie rzuca.
List<WeatherCheckRecord> decodeWeatherHistory(String? raw) =>
    decodeWeatherHistoryDetailed(raw).records;
