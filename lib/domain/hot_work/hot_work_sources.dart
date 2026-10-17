/// Źródła i wartości odniesienia modułu „Prace pożarowo niebezpieczne”.
///
/// Ustalenia sprawdzone w tekstach źródeł (2026-10-17):
/// * PL, przepis: rozporządzenie MSWiA z 7 czerwca 2010 r. w sprawie
///   ochrony przeciwpożarowej budynków, innych obiektów budowlanych
///   i terenów — t.j. Dz.U. 2023 poz. 822 (zmiany Dz.U. 2024 poz. 1716
///   i Dz.U. 2026 poz. 1276 nie dotyczą prac niebezpiecznych). § 2 ust. 1
///   pkt 4 — definicja prac niebezpiecznych pod względem pożarowym;
///   Rozdział 8 § 36 — obowiązki przed pracami (ust. 1) i przy pracach
///   (ust. 2), w tym próg 10 % DGW. § 36 NIE podaje odległości w metrach,
///   czasu kontroli / dozoru po pracy ani słowa „pisemne zezwolenie”.
/// * PL, przepis: rozporządzenie Ministra Gospodarki z 27 kwietnia 2000 r.
///   w sprawie bezpieczeństwa i higieny pracy przy pracach spawalniczych
///   (Dz.U. 2000 nr 40 poz. 470) — §§ 14, 22, 23, 30, 31, 32, 34.
/// * Praktyka (NIE przepis PL): FM Global „Kieszonkowy przewodnik”
///   P9602_POL wyd. 6 (2017); NFPA 51B-2019 § 5.6.1.1; OSHA 29 CFR
///   1910.252(a)(2).
/// * Progi DGW w instrukcjach zakładów: 0 %, 5 % albo 10 % — dlatego próg
///   w aplikacji wpisuje się z zezwolenia (domyślnie 10 % z § 36 ust. 2).
///
/// Numery norm bezpieczników przypalnikowych (EN ISO 5175) i instalacji
/// sprzętu spawalniczego (EN IEC 60974-9) nie zostały potwierdzone —
/// celowo ich tu nie ma.
///
/// Czysty Dart.
library;

/// Domyślny dopuszczalny % DGW w nowym protokole.
///
/// Źródło: rozp. MSWiA z 7.06.2010, § 36 ust. 2 — w pomieszczeniach
/// i przy urządzeniach zagrożonych wybuchem oraz tam, gdzie były łatwo
/// palne ciecze lub palne gazy, prace tylko przy stężeniu
/// NIEPRZEKRACZAJĄCYM 10 % DGW. To górna granica z przepisu — zakład może
/// wymagać mniej (spotykane 0–5 % DGW), więc pole jest edytowalne.
const double kHotWorkDefaultDgwLimitPct = 10;

class HotWorkSource {
  final String pl;
  final String en;
  const HotWorkSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

/// Lista na ekranie „Źródła i wartości odniesienia”.
const List<HotWorkSource> kHotWorkSources = [
  HotWorkSource(
    'Rozp. MSWiA z 7.06.2010 (t.j. Dz.U. 2023 poz. 822), § 36: przed pracami '
        '— ocena zagrożenia, przedsięwzięcia, osoby odpowiedzialne, tylko '
        'osoby upoważnione, zapoznanie z zagrożeniami; przy pracach — '
        'zabezpieczenie materiałów palnych w miejscu prac i rejonach '
        'przyległych, w strefach zagrożonych wybuchem stężenie nie większe '
        'niż 10 % DGW, sprzęt gaśniczy na miejscu, kontrola po zakończeniu, '
        'sprawny sprzęt. Przepis nie podaje odległości ani czasu dozoru.',
    'Polish Regulation of the Minister of the Interior of 7 June 2010 '
        '(consolidated Dz.U. 2023 item 822), § 36: before work — hazard '
        'assessment, precautions, responsible persons, authorised workers '
        'only, briefing; during work — combustibles protected at the work '
        'point and adjacent areas, in explosion-hazard areas gas level not '
        'above 10 % LEL, fire-fighting equipment on site, inspection after '
        'the work, equipment in good order. No distances or watch times '
        'are given.',
  ),
  HotWorkSource(
    'Rozp. MG z 27.04.2000 w sprawie BHP przy pracach spawalniczych '
        '(Dz.U. 2000 nr 40 poz. 470): § 14 (materiały łatwo palne, strefa '
        'rozprysku także poniżej stanowiska), § 22 (węże), § 23 i § 31 '
        '(bezpieczniki), § 30 (przewód powrotny przy miejscu spawania), '
        '§ 32 (butle — nagrzanie powyżej 35 °C), § 34 (oczyszczenie '
        'zbiorników i rurociągów).',
    'Polish Regulation of the Minister of Economy of 27 April 2000 on '
        'health and safety in welding (Dz.U. 2000 No 40 item 470): § 14 '
        '(combustibles, spatter zone incl. below the work point), § 22 '
        '(hoses), §§ 23 and 31 (flashback arrestors), § 30 (return lead '
        'close to the weld), § 32 (cylinders — heating above 35 °C), § 34 '
        '(cleaning of tanks and pipes).',
  ),
  HotWorkSource(
    'Praktyka — FM Global, Kieszonkowy przewodnik P9602_POL wyd. 6 '
        '(2017): materiały palne usunięte w promieniu 11 m w poziomie '
        'i co najmniej 5 m w pionie; nadzór po pracy 30 albo 60 min '
        'i monitoring do 5 h — wg kategorii pracy.',
    'Practice — FM Global hot work pocket guide P9602 (6th ed., 2017): '
        'combustibles cleared for 11 m horizontally and at least 5 m '
        'vertically; post-work watch 30 or 60 min and monitoring up to '
        '5 h — by work category.',
  ),
  HotWorkSource(
    'Praktyka — NFPA 51B:2019 § 5.6.1.1: dozór (fire watch) co najmniej '
        '1 h po pracy (wcześniejsze wydania: 30 min) i monitorowanie do '
        'kolejnych 3 h. OSHA 29 CFR 1910.252(a)(2): dozór co najmniej '
        '30 min, materiały palne w promieniu 35 ft (10,7 m).',
    'Practice — NFPA 51B:2019 § 5.6.1.1: fire watch at least 1 h after the '
        'work (earlier editions: 30 min) and monitoring for up to 3 more '
        'hours. OSHA 29 CFR 1910.252(a)(2): fire watch at least 30 min, '
        'combustibles within 35 ft (10.7 m).',
  ),
  HotWorkSource(
    'Progi w instrukcjach zakładów bywają ostrzejsze niż przepis: 0 %, '
        '5 % albo 10 % DGW. Obowiązuje wartość z zezwolenia.',
    'Site procedures are often stricter than the regulation: 0 %, 5 % or '
        '10 % LEL. The permit value applies.',
  ),
];
