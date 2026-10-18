// Plan ściegów i elektrod — dane wejściowe ze źródłami i wartości
// PRZYJĘTE W APLIKACJI (do korekty przez spawacza). Czysty Dart.
//
// __ŹRÓDŁA__
//  [K] ESAB OK 48.00 (SFA/AWS A5.1 E7018 H4 R, EN ISO 2560-A E 42 4 B 42
//      H5), karta produktu, tabela „Deposition Data”, wersja 2023-06-06
//      (stopka „OK_48.00 2023-06-06”) — liczba elektrod na kg stopiwa
//      i czas stapiania jednej elektrody przy 90 % Imax. Kopia karty:
//      https://bester.rapidwelding.com/files/48002530KX.pdf
//      (ta sama tabela bez kolumny „elektrod/kg” w karcie
//      https://roussakis.com.gr/wp-content/uploads/OK_48.00.pdf).
//      Sprawdzenie spójności: 1000/42 = 23,8 g na elektrodę 3,2 × 350
//      i 1,24 kg/h · 68 s = 23,4 g — kolumny się zgadzają.
//      Karta NIE podaje długości ogarka, przy której mierzono.
//  [G] Geometria rowka i lica: lib/domain/quotes/weld_geometry.dart
//      (EN ISO 9692-1, ASME B16.25, EN ISO 5817, ASME B31.3) — ten sam
//      przekrój co w wycenie; plan go tylko dzieli na warstwy.
//  [P] Profile procesów wyceny: kDefaultProcessProfiles
//      (lib/domain/quotes/quote_process.dart) — TIG 0,5 kg/h, uzysk 95 %;
//      MAG 2,5 kg/h, uzysk 92 %; współczynnik jarzenia łuku TIG 35 %,
//      MMA 30 %, MAG 40 %.
//  [T] TWI Job Knowledge 96 „Welding costs” (G. Mathers) — tabela 2:
//      współczynnik jarzenia łuku MMA 15–30 %, TIG 25–40 %, MIG/MAG
//      30–45 % (bez czasu ustawiania i montażu). Domyślne z [P] mieszczą się
//      w tych zakresach.
//      https://www.twi-global.com/technical-knowledge/job-knowledge/welding-costs-096
//      KIERUNEK OSTROŻNY ([kArcOnRangePct]):
//       • „ile naraz z suszarki” — współczynnik min(wpisany, DOLNA granica
//         TWI): niższy współczynnik = wolniejsze zużycie = mniej elektrod
//         naraz = krótsza ekspozycja. Wyższy wpisany współczynnik NIGDY nie
//         zwiększa „ile naraz”;
//       • czas złącza i całości — min(wpisany, GÓRNA granica TWI): wyższy
//         współczynnik skraca czas, więc nie liczymy krócej niż przy górnej
//         granicy źródła (plan zmiany nie wyjdzie zbyt optymistyczny); niższy
//         wpisany — dłuższy czas, przyjęty.
//  [E] Moduł „Elektrody zasadowe: czas i suszenie”
//      (lib/domain/welding/electrode_exposure.dart): limity AWS D1.1:2020
//      Tabela 7.1 i kart producentów (defaultLimitMinutes), zapas przed
//      końcem limitu (warnLeadMinutes).
//
// __PRZYJĘTE W APLIKACJI__ (brak źródła normowego — do korekty):
//  • przekroje ściegów (mm²) — [kDefaultBeadAreaMm2];
//  • ogarek 50 mm (ok. 2 cale) i założenie, że dane karty [K] odpowiadają
//    takiemu ogarkowi — [kCardStubMm];
//  • grubość warstwy lica w rowku 2 mm — [kCapLayerDepthMm];
//  • resztka wypełnienia mniejsza niż pół ściegu idzie do lica —
//    [kFillMergeFraction];
//  • pręt TIG 1000 mm — [kTigRodLengthMm];
//  • zapas 10 % i zmiana 8 h — wartości startowe pól.
library;

/// Wiersz tabeli „Deposition Data” z karty elektrody.
class ElectrodeCardRow {
  /// Średnica rdzenia, mm.
  final double diameterMm;

  /// Długość elektrody, mm.
  final int lengthMm;

  /// Zakres prądu z karty, A.
  final int minA;
  final int maxA;

  /// „Efficiency” z karty, % (masa stopiwa / masa elektrody).
  final int efficiencyPct;

  /// Liczba elektrod na 1 kg stopiwa.
  final double electrodesPerKg;

  /// Czas stapiania jednej elektrody przy 90 % Imax, s.
  final int fusionTimeS;

  /// Wydajność stapiania przy 90 % Imax, kg/h łuku.
  final double depositionKgH;

  const ElectrodeCardRow({
    required this.diameterMm,
    required this.lengthMm,
    required this.minA,
    required this.maxA,
    required this.efficiencyPct,
    required this.electrodesPerKg,
    required this.fusionTimeS,
    required this.depositionKgH,
  });

  /// Masa stopiwa z jednej elektrody wg karty, g.
  double get depositG => 1000 / electrodesPerKg;

  /// Sekundy łuku na gram stopiwa (czas stapiania / masa stopiwa
  /// elektrody) — nie zależy od długości ogarka.
  double get arcSecondsPerGram => fusionTimeS / depositG;
}

/// ESAB OK 48.00, karta 2023-06-06 — średnice używane na rurach i blachach
/// (Ø2,5–4,0, długości 350 / 450 mm) [K].
const List<ElectrodeCardRow> kOk4800Card = [
  ElectrodeCardRow(
      diameterMm: 2.5,
      lengthMm: 350,
      minA: 70,
      maxA: 110,
      efficiencyPct: 67,
      electrodesPerKg: 65,
      fusionTimeS: 57,
      depositionKgH: 0.96),
  ElectrodeCardRow(
      diameterMm: 3.2,
      lengthMm: 350,
      minA: 90,
      maxA: 140,
      efficiencyPct: 70,
      electrodesPerKg: 42,
      fusionTimeS: 68,
      depositionKgH: 1.24),
  ElectrodeCardRow(
      diameterMm: 3.2,
      lengthMm: 450,
      minA: 90,
      maxA: 140,
      efficiencyPct: 73,
      electrodesPerKg: 31,
      fusionTimeS: 85,
      depositionKgH: 1.33),
  ElectrodeCardRow(
      diameterMm: 4.0,
      lengthMm: 350,
      minA: 120,
      maxA: 190,
      efficiencyPct: 70,
      electrodesPerKg: 29,
      fusionTimeS: 75,
      depositionKgH: 1.63),
  ElectrodeCardRow(
      diameterMm: 4.0,
      lengthMm: 450,
      minA: 120,
      maxA: 190,
      efficiencyPct: 71,
      electrodesPerKg: 22,
      fusionTimeS: 92,
      depositionKgH: 1.76),
];

/// Nazwa elektrody, z której karty liczymy.
const String kCardElectrodeName = 'ESAB OK 48.00 (E7018 H4 R / E 42 4 B 42 H5)';

/// Ogarek, któremu przypisujemy dane karty [K], mm — PRZYJĘTE (karta go nie
/// podaje). Inny ogarek przelicza masę stopiwa elektrody proporcjonalnie
/// do zużytej długości: (L − ogarek) / (L − 50).
const double kCardStubMm = 50;

/// Domyślny ogarek, mm — PRZYJĘTE (ok. 2 cale).
const double kDefaultStubMm = 50;

/// Rozsądny zakres ogarka, mm.
const double kMinStubMm = 20;
const double kMaxStubMm = 150;

/// Przekroje ściegów, mm² — PRZYJĘTE W APLIKACJI (typowe ściegi
/// w pozycjach wymuszonych, do korekty). Sprawdzenie na stanowisku:
/// przekrój = objętość stopiwa z elektrody / długość ściegu z niej
/// (np. Ø3,2 × 350: 23,8 g = 3030 mm³; 18 mm² ↔ ok. 170 mm ściegu).
/// TIG: 0,5 kg/h ([P]) przy ok. 90 mm/min ≈ 12 mm² — ścieg graniowy
/// z przetopem na rowku 2,5 / 1,5 mieści się w jednym ściegu.
/// Służą też do liczby ściegów GRANI (szeroka szczelina = więcej ściegów).
/// Klucze: nazwy [PassConsumable] (tig, mma25, mma32, mma40, mag).
const Map<String, double> kDefaultBeadAreaMm2 = {
  'tig': 12,
  'mma25': 12,
  'mma32': 18,
  'mma40': 26,
  'mag': 25,
};

/// Zakres przekroju ściegu przyjmowany z pola, mm².
const double kMaxBeadAreaMm2 = 200;

/// Grubość warstwy lica w rowku (bez nadlewu), mm — PRZYJĘTE. Dla rowka X
/// lico jest z obu stron.
const double kCapLayerDepthMm = 2.0;

/// Resztka wypełnienia mniejsza niż ten ułamek ściegu wypełnienia nie jest
/// osobnym ściegiem — dochodzi do lica (lico wychodzi trochę grubsze) —
/// PRZYJĘTE.
const double kFillMergeFraction = 0.5;

/// Długość pręta TIG, mm — PRZYJĘTE (typowe opakowania prętów 1000 mm).
const double kTigRodLengthMm = 1000;

/// Średnice prętów TIG do wyboru, mm.
const List<double> kTigRodDiametersMm = [1.6, 2.0, 2.4, 3.2];
const double kDefaultTigRodMm = 2.4;

/// Zapas na całość (pęknięta otulina, sczepy, poprawki), % — wartość
/// startowa; pole przyjmuje 0–100 % (zapas nigdy ujemny).
const double kDefaultReservePct = 10;
const double kMaxReservePct = 100;

/// Długość zmiany, h — wartość startowa.
const double kDefaultShiftH = 8;
const double kMaxShiftH = 24;

/// Współczynnik jarzenia łuku przyjmowany z pola, %.
const double kMinArcOnPct = 5;
const double kMaxArcOnPct = 100;

/// Zakres współczynnika jarzenia łuku ręcznego spawania wg [T], % —
/// (dolna, górna) granica. Klucze: kody procesów wyceny (TIG, MMA, MAG).
/// Dolna — do „ile naraz z suszarki”, górna — ograniczenie czasu (patrz
/// KIERUNEK OSTROŻNY w nagłówku).
const Map<String, (double, double)> kArcOnRangePct = {
  'TIG': (25, 40),
  'MMA': (15, 30),
  'MAG': (30, 45),
};

/// Największa liczba złączy w jednym planie (literówka?).
const int kMaxJointCount = 100000;

/// Źródło na ekranie i w tekście do udostępnienia.
class PassPlanSource {
  final String id;
  final String pl;
  final String en;
  const PassPlanSource(this.id, this.pl, this.en);

  String text({required bool en}) => en ? this.en : pl;
}

const List<PassPlanSource> kPassPlanSources = [
  PassPlanSource(
    'card',
    'Elektrody: karta ESAB OK 48.00 (E7018 H4 R / EN ISO 2560-A E 42 4 B 42 '
        'H5), „Deposition Data”, 2023-06-06 — elektrod na kg stopiwa i czas '
        'stapiania jednej elektrody przy 90 % Imax. Inna elektroda — '
        'sprawdź te dwie kolumny w jej karcie.',
    'Electrodes: ESAB OK 48.00 data sheet (E7018 H4 R / EN ISO 2560-A '
        'E 42 4 B 42 H5), “Deposition Data”, 2023-06-06 — electrodes per kg '
        'of weld metal and fusion time per electrode at 90 % Imax. Another '
        'electrode — check these two columns in its data sheet.',
  ),
  PassPlanSource(
    'geometry',
    'Przekrój spoiny: ta sama geometria co w wycenie (rowki EN ISO 9692-1 / '
        'ASME B16.25, lico wg EN ISO 5817, grań 3 mm, pachwina — pierwszy '
        'ścieg a = 3 mm).',
    'Weld cross-section: the same geometry as in quotes (EN ISO 9692-1 / '
        'ASME B16.25 grooves, cap per EN ISO 5817, 3 mm root, fillet — first '
        'run a = 3 mm).',
  ),
  PassPlanSource(
    'profiles',
    'TIG i MAG: wydajność i uzysk z profili procesów wyceny (TIG 0,5 kg/h, '
        '95 %; MAG 2,5 kg/h, 92 %). Współczynnik jarzenia łuku: TIG 35 %, '
        'MMA 30 %, MAG 40 % — w zakresach TWI Job Knowledge 96 „Welding '
        'costs” (MMA 15–30 %, TIG 25–40 %, MAG 30–45 %).',
    'TIG and MAG: deposition rate and efficiency from the quote process '
        'profiles (TIG 0.5 kg/h, 95 %; MAG 2.5 kg/h, 92 %). Arc-on factor: '
        'TIG 35 %, MMA 30 %, MAG 40 % — within the TWI Job Knowledge 96 '
        '“Welding costs” ranges (MMA 15–30 %, TIG 25–40 %, MAG 30–45 %).',
  ),
  PassPlanSource(
    'arc-on-direction',
    'Kierunek ostrożny: „ile naraz z suszarki” liczone z dolnej granicy TWI '
        '(MMA 15 %, TIG 25 %, MAG 30 %) albo niższej wpisanej — wolniejsze '
        'zużycie to mniej elektrod naraz i krótsza ekspozycja, więc wyższy '
        'współczynnik nie zwiększa tej liczby. Czas złącza z wpisanego, ale '
        'nie wyższego niż górna granica TWI (MMA 30 %, TIG 40 %, MAG 45 %) — '
        'plan zmiany nie wyjdzie krótszy, niż pozwala źródło.',
    'Cautious direction: “how many at once from the oven” uses the TWI lower '
        'bound (MMA 15 %, TIG 25 %, MAG 30 %) or a lower typed value — slower '
        'use means fewer electrodes at once and shorter exposure, so a higher '
        'factor never raises that number. Joint time uses the typed factor, '
        'but not above the TWI upper bound (MMA 30 %, TIG 40 %, MAG 45 %) — '
        'the shift plan is never shorter than the source allows.',
  ),
  PassPlanSource(
    'exposure',
    'Limit czasu na powietrzu i zapas przed końcem — z modułu „Elektrody '
        'zasadowe: czas i suszenie” (AWS D1.1:2020 Tabela 7.1, karty '
        'producentów). Czas w kołczanie bez grzania liczy się do limitu.',
    'Exposure limit and the margin before its end — from the “Low-hydrogen '
        'electrodes: exposure” module (AWS D1.1:2020 Table 7.1, manufacturer '
        'data sheets). Time in an unheated quiver counts towards the limit.',
  ),
  PassPlanSource(
    'assumed',
    'Przyjęte w aplikacji (do korekty): przekroje ściegów TIG 12, Ø2,5 12, '
        'Ø3,2 18, Ø4,0 26, MAG 25 mm² (także liczba ściegów grani); ogarek '
        '50 mm (karta ESAB nie podaje '
        'ogarka — przyjęto, że jej dane odpowiadają 50 mm); warstwa lica 2 mm '
        'w rowku; resztka wypełnienia poniżej pół ściegu idzie do lica; '
        'pręt TIG 1000 mm.',
    'Assumed in the app (adjust as needed): bead areas TIG 12, Ø2.5 12, '
        'Ø3.2 18, Ø4.0 26, MAG 25 mm² (also the number of root passes); 50 mm '
        'stub (the ESAB sheet gives no '
        'stub length — its data are taken as for 50 mm); 2 mm cap layer in '
        'the groove; a fill remainder under half a bead goes into the cap; '
        '1000 mm TIG rod.',
  ),
];
