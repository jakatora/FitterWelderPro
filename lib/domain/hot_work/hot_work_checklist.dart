/// Lista kontrolna przygotowania stanowiska do prac niebezpiecznych pod
/// względem pożarowym — jako dane (PL/EN), pogrupowana w fazy: przed
/// rozpoczęciem, w trakcie, po zakończeniu.
///
/// MODUŁ BEZPIECZEŃSTWA. Każda liczba w treści punktów ma komentarz ze
/// źródłem (pełne opisy źródeł: hot_work_sources.dart). Przepisy PL
/// (rozp. MSWiA z 7.06.2010, § 36) NIE podają odległości w metrach ani
/// czasu dozoru po pracy — tam punkt mówi „wg zezwolenia”, a liczby
/// z dobrej praktyki (FM Global, OSHA, NFPA 51B) są podpisane jako praktyka,
/// nie przepis.
///
/// Identyfikatory punktów są zapisywane w historii — NIGDY ich nie zmieniaj
/// (zapisane zaznaczenia przypięłyby się do innego punktu albo zniknęły).
///
/// Czysty Dart.
library;

enum HotWorkPhase {
  before('Przed rozpoczęciem', 'Before work starts'),
  during('W trakcie pracy', 'During work'),
  after('Po zakończeniu', 'After work ends');

  const HotWorkPhase(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

enum HotWorkGroup {
  permit(HotWorkPhase.before, 'Zezwolenie i organizacja',
      'Permit and organisation'),
  combustibles(HotWorkPhase.before, 'Materiały palne', 'Combustibles'),
  openings(HotWorkPhase.before, 'Otwory, kanały, studzienki',
      'Openings, ducts, drains'),
  atmosphere(HotWorkPhase.before, 'Pomiar atmosfery', 'Gas testing'),
  extinguishing(HotWorkPhase.before, 'Sprzęt gaśniczy',
      'Fire-fighting equipment'),
  shields(HotWorkPhase.before, 'Osłony iskier', 'Spark containment'),
  ventilation(HotWorkPhase.before, 'Wentylacja', 'Ventilation'),
  cylinders(HotWorkPhase.before, 'Butle i osprzęt gazowy',
      'Gas cylinders and hoses'),
  equipment(HotWorkPhase.before, 'Sprzęt spawalniczy', 'Welding equipment'),
  ppe(HotWorkPhase.before, 'Środki ochrony indywidualnej',
      'Personal protective equipment'),
  watchDuring(HotWorkPhase.during, 'Dozór i kontrola w trakcie',
      'Watch and checks during work'),
  closeOut(HotWorkPhase.after, 'Zakończenie i dozór po pracy',
      'Close-out and post-work watch');

  const HotWorkGroup(this.phase, this.labelPl, this.labelEn);
  final HotWorkPhase phase;
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

class HotWorkCheck {
  /// Trwały identyfikator (zapis w historii) — nie zmieniać.
  final String id;
  final HotWorkGroup group;
  final String pl;
  final String en;

  /// Wolno oznaczyć „nie dotyczy” (np. brak butli przy spawaniu MMA).
  /// Punkty podstawowe (zezwolenie, materiały palne, sprzęt gaśniczy,
  /// pomiar, dozór, kontrola po pracy) nie mają tej opcji.
  final bool naAllowed;

  /// Krótkie odwołanie do źródła pokazywane pod punktem (albo `null`).
  final String? source;

  const HotWorkCheck(
    this.id,
    this.group,
    this.pl,
    this.en, {
    this.naAllowed = false,
    this.source,
  });

  HotWorkPhase get phase => group.phase;
  String label({required bool en}) => en ? this.en : pl;
}

// Krótkie odwołania do źródeł (pełne opisy: hot_work_sources.dart).

/// Rozporządzenie MSWiA z 7.06.2010 w sprawie ochrony przeciwpożarowej
/// budynków, innych obiektów budowlanych i terenów (t.j. Dz.U. 2023
/// poz. 822), Rozdział 8 § 36.
const String kSrcMswia36u1 = 'Rozp. MSWiA 7.06.2010, § 36 ust. 1';
const String kSrcMswia36u2 = 'Rozp. MSWiA 7.06.2010, § 36 ust. 2';

// „rozp. MG 27.04.2000” = rozporządzenie Ministra Gospodarki z 27.04.2000
// w sprawie bezpieczeństwa i higieny pracy przy pracach spawalniczych
// (Dz.U. 2000 nr 40 poz. 470).

/// Dobra praktyka — nie przepis PL.
const String kSrcPractice = 'praktyka: FM Global, OSHA 1910.252, NFPA 51B';

/// Lista kontrolna — w kolejności wyświetlania.
final List<HotWorkCheck> kHotWorkChecks = List.unmodifiable([
  // ── Przed rozpoczęciem · zezwolenie ──────────────────────────────────────
  // Rozp. MSWiA § 36 ust. 1: ocena zagrożenia i ustalenie przedsięwzięć
  // przed pracami. Słowa „pisemne zezwolenie” w § 36 nie ma — wymaga go
  // instrukcja zakładu, więc punkt mówi o zezwoleniu zakładu.
  const HotWorkCheck(
    'perm-written',
    HotWorkGroup.permit,
    'Zezwolenie zakładu wystawione na to miejsce, zakres i godziny; '
        'zagrożenie ocenione i sposób zabezpieczenia ustalony',
    'Site permit issued for this location, scope and hours; hazards '
        'assessed and precautions agreed',
    source: kSrcMswia36u1,
  ),
  // § 36 ust. 1: wskazanie osób odpowiedzialnych za przygotowanie miejsca,
  // przebieg prac i zabezpieczenie miejsca po pracy.
  const HotWorkCheck(
    'perm-persons',
    HotWorkGroup.permit,
    'Wskazane osoby odpowiedzialne: za przygotowanie miejsca pracy, za '
        'przebieg pracy i za zabezpieczenie miejsca po jej zakończeniu',
    'Named persons responsible for preparing the area, for the work itself '
        'and for securing the area after the work',
    source: kSrcMswia36u1,
  ),
  // § 36 ust. 1: tylko osoby upoważnione, z kwalifikacjami; zapoznanie
  // wykonawców z zagrożeniami.
  const HotWorkCheck(
    'perm-briefing',
    HotWorkGroup.permit,
    'Pracę wykonują osoby upoważnione, z kwalifikacjami; wykonawcy '
        'i dozorujący zapoznani z zagrożeniami pożarowymi w rejonie pracy',
    'Work done only by authorised, qualified persons; workers and fire '
        'watch briefed on the fire hazards in the area',
    source: kSrcMswia36u1,
  ),
  const HotWorkCheck(
    'perm-alarm',
    HotWorkGroup.permit,
    'Wiadomo, jak alarmować (numer straży zakładowej / 112, najbliższy '
        'ręczny ostrzegacz pożarowy) i którędy ewakuacja',
    'Everyone knows how to raise the alarm (site fire brigade number / 112, '
        'nearest manual call point) and the escape route',
  ),

  // ── Przed rozpoczęciem · materiały palne ─────────────────────────────────
  // § 36 ust. 2 rozp. MSWiA: zabezpieczyć materiały palne w miejscu prac
  // i w rejonach przyległych (bez odległości w metrach).
  // § 14 ust. 1 rozp. MG: nie przechowywać materiałów łatwo palnych na
  // stanowisku spawalniczym.
  // Liczby z praktyki (NIE z przepisu PL): FM Global, Kieszonkowy
  // przewodnik P9602_POL wyd. 6 (2017) — 11 m w poziomie i co najmniej 5 m
  // w pionie; OSHA 29 CFR 1910.252(a)(2) — 35 ft (10,7 m).
  const HotWorkCheck(
    'comb-remove',
    HotWorkGroup.combustibles,
    'Materiały palne usunięte z miejsca pracy i rejonów przyległych — '
        'promień wg zezwolenia (praktyka: 11 m w poziomie, FM Global; '
        '35 ft ≈ 10,7 m, OSHA)',
    'Combustibles removed from the work point and adjacent areas — radius '
        'per the permit (practice: 11 m horizontally, FM Global; '
        '35 ft ≈ 10.7 m, OSHA)',
    source: '$kSrcMswia36u2; § 14 ust. 1 rozp. MG 27.04.2000',
  ),
  // § 36 ust. 2 rozp. MSWiA: zabezpieczenie materiałów palnych, także
  // konstrukcji i instalacji, których nie da się usunąć.
  const HotWorkCheck(
    'comb-cover',
    HotWorkGroup.combustibles,
    'Materiały, konstrukcje i instalacje palne, których nie da się usunąć, '
        'osłonięte niepalnymi osłonami / kocami',
    'Combustible materials, structures and services that cannot be moved '
        'covered with non-combustible covers / blankets',
    naAllowed: true,
    source: kSrcMswia36u2,
  ),
  const HotWorkCheck(
    'comb-floor',
    HotWorkGroup.combustibles,
    'Podłoże oczyszczone z palnych resztek (szmaty, wióry, olej, smary)',
    'Floor swept clear of combustible debris (rags, shavings, oil, grease)',
  ),
  // § 36 ust. 2 rozp. MSWiA: „rejony przyległe” — także druga strona
  // przegród, do której ciepło przechodzi przez rury i konstrukcję.
  const HotWorkCheck(
    'comb-walls',
    HotWorkGroup.combustibles,
    'Sprawdzona druga strona ścian, stropów i przegród oraz izolacje — '
        'ciepło przewodzone przez rury i konstrukcję nie zapali niczego '
        'po drugiej stronie',
    'Other side of walls, ceilings and partitions and any insulation '
        'checked — heat conducted through pipes and steel cannot ignite '
        'anything there',
    naAllowed: true,
    source: kSrcMswia36u2,
  ),
  // § 34 ust. 1 rozp. MG: zbiorniki i rurociągi po substancjach
  // chemicznych spawać dopiero po dokładnym oczyszczeniu.
  const HotWorkCheck(
    'comb-process',
    HotWorkGroup.combustibles,
    'Aparat / rurociąg / zbiornik, na którym się pracuje, odcięty '
        '(zaślepki), opróżniony i dokładnie oczyszczony lub przedmuchany',
    'Vessel / pipe / tank being worked on isolated (blinds), drained and '
        'thoroughly cleaned or purged',
    naAllowed: true,
    source: '§ 34 ust. 1 rozp. MG 27.04.2000',
  ),

  // ── Przed rozpoczęciem · otwory ──────────────────────────────────────────
  // Praktyka (FM Global P9602_POL, NFPA 51B) — bez liczb.
  const HotWorkCheck(
    'open-cover',
    HotWorkGroup.openings,
    'Otwory w podłogach, ścianach i stropach, szczeliny, kanały, '
        'studzienki i wpusty kanalizacyjne w zasięgu iskier zakryte lub '
        'uszczelnione niepalnym materiałem',
    'Floor, wall and ceiling openings, cracks, trenches, manholes and drains '
        'within spark reach covered or sealed with non-combustible material',
    naAllowed: true,
    source: kSrcPractice,
  ),
  const HotWorkCheck(
    'open-ducts',
    HotWorkGroup.openings,
    'Kanały wentylacyjne, przenośniki i rynny, które mogą przenieść iskry '
        'lub ciepło, wyłączone lub zabezpieczone',
    'Ducts, conveyors and chutes that could carry sparks or heat shut down '
        'or protected',
    naAllowed: true,
    source: kSrcPractice,
  ),

  // ── Przed rozpoczęciem · atmosfera ───────────────────────────────────────
  // § 36 ust. 2 rozp. MSWiA: w pomieszczeniach / przy urządzeniach
  // zagrożonych wybuchem i tam, gdzie były łatwo palne ciecze lub palne
  // gazy — prace tylko przy stężeniu nieprzekraczającym 10 % DGW. Zakłady
  // często wymagają mniej (0–5 % DGW) — próg wpisuje się z zezwolenia.
  const HotWorkCheck(
    'atm-meter',
    HotWorkGroup.atmosphere,
    'Eksplozymetr sprawny — test / kalibracja wg producenta i instrukcji '
        'zakładu',
    'Gas detector working — bump test / calibration per the maker and '
        'the site procedure',
  ),
  const HotWorkCheck(
    'atm-measure',
    HotWorkGroup.atmosphere,
    'Pomiar stężenia gazów i par palnych w miejscu pracy oraz w punktach '
        'niskich i zamkniętych (studzienki, kanały, wnętrze aparatu) — '
        'wynik wpisany w sekcji „Pomiar atmosfery”',
    'Flammable gas / vapour reading taken at the work point and in low and '
        'enclosed spots (drains, trenches, inside the equipment) — result '
        'entered under “Gas test”',
    source: kSrcMswia36u2,
  ),

  // ── Przed rozpoczęciem · sprzęt gaśniczy ─────────────────────────────────
  // § 36 ust. 2 rozp. MSWiA: sprzęt umożliwiający likwidację wszelkich
  // źródeł pożaru na miejscu prac; tylko sprzęt sprawny technicznie.
  const HotWorkCheck(
    'ext-ready',
    HotWorkGroup.extinguishing,
    'Sprzęt gaśniczy na miejscu pracy, sprawny i dobrany do zagrożenia '
        '(rodzaj i liczba wg zezwolenia): gaśnice, koc, wąż hydrantowy',
    'Fire-fighting equipment at the work point, serviceable and suited to '
        'the hazard (type and number per the permit): extinguishers, blanket, '
        'hose',
    source: kSrcMswia36u2,
  ),

  // ── Przed rozpoczęciem · osłony iskier ───────────────────────────────────
  // § 14 ust. 2 rozp. MG: zabezpieczenie strefy rozprysku z uwzględnieniem
  // przestrzeni poniżej stanowiska.
  const HotWorkCheck(
    'shield-screens',
    HotWorkGroup.shields,
    'Strefa rozprysku zabezpieczona ekranami / kurtynami i kocami — także '
        'przestrzeń poniżej stanowiska (przy pracy na wysokości iskry lecą '
        'dalej)',
    'Spatter zone protected with screens / curtains and blankets — '
        'including the space below the work point (sparks travel further '
        'when working at height)',
    naAllowed: true,
    source: '§ 14 ust. 2 rozp. MG 27.04.2000',
  ),

  // ── Przed rozpoczęciem · wentylacja ──────────────────────────────────────
  const HotWorkCheck(
    'vent-ok',
    HotWorkGroup.ventilation,
    'Wentylacja / odciąg dymów działa; nigdy nie przewietrzać tlenem',
    'Ventilation / fume extraction running; never ventilate with oxygen',
    naAllowed: true,
  ),

  // ── Przed rozpoczęciem · butle ───────────────────────────────────────────
  // § 32 pkt 4 rozp. MG: butle chronione przed nagrzaniem powyżej 35 °C.
  const HotWorkCheck(
    'cyl-secured',
    HotWorkGroup.cylinders,
    'Butle pionowo, zabezpieczone przed przewróceniem i nagrzaniem '
        '(powyżej 35 °C), z dala od iskier; poza zbiornikiem / przestrzenią '
        'zamkniętą',
    'Cylinders upright, secured against falling and heating (above 35 °C), '
        'away from sparks; kept outside the vessel / confined space',
    naAllowed: true,
    source: '§ 32 pkt 4 rozp. MG 27.04.2000',
  ),
  // § 22 rozp. MG: węże — kontrola szczelności co najmniej raz na kwartał
  // (długość węży 5–20 m). Na stanowisku: oględziny i próba szczelności.
  const HotWorkCheck(
    'cyl-hoses',
    HotWorkGroup.cylinders,
    'Zawory, reduktory, węże i złączki szczelne i nieuszkodzone '
        '(szczelność sprawdzana środkiem pianotwórczym, nie płomieniem)',
    'Valves, regulators, hoses and fittings tight and undamaged (leak test '
        'with leak-detection fluid, never a flame)',
    naAllowed: true,
    source: '§ 22 rozp. MG 27.04.2000',
  ),
  // § 23 ust. 1–2 rozp. MG: bezpiecznik w każdym punkcie poboru gazu
  // palnego; przy palnikach zasilanych z butli — bezpieczniki na wlocie
  // lub wewnątrz palnika. § 31 pkt 5: poziom cieczy w bezpieczniku wodnym
  // przed pracą i po każdym cofnięciu płomienia.
  const HotWorkCheck(
    'cyl-flashback',
    HotWorkGroup.cylinders,
    'Gazy palne (acetylen, propan…): bezpiecznik przy każdym punkcie poboru '
        'gazu i bezpieczniki na wlocie / w palniku; bezpiecznik wodny — '
        'poziom cieczy sprawdzony przed pracą',
    'Fuel gases (acetylene, propane…): flashback arrestor at every gas '
        'take-off point and arrestors at the torch inlet / inside the torch; '
        'water seal — liquid level checked before work',
    naAllowed: true,
    source: '§ 23 ust. 1–2, § 31 pkt 5 rozp. MG 27.04.2000',
  ),

  // ── Przed rozpoczęciem · sprzęt spawalniczy ──────────────────────────────
  // § 30 pkt 3–4 rozp. MG: przewody połączone bezpośrednio z przedmiotem
  // spawanym jak najbliżej miejsca spawania (prądy błądzące).
  const HotWorkCheck(
    'weq-return',
    HotWorkGroup.equipment,
    'Przewód powrotny (masa) połączony bezpośrednio ze spawanym '
        'przedmiotem jak najbliżej miejsca spawania — nie przez obce '
        'rurociągi, konstrukcje, szyny ani łańcuchy (prądy błądzące)',
    'Welding return lead connected directly to the workpiece as close to '
        'the weld as possible — never through other pipes, steelwork, rails '
        'or chains (stray currents)',
    naAllowed: true,
    source: '§ 30 pkt 3–4 rozp. MG 27.04.2000',
  ),
  // § 36 ust. 2 rozp. MSWiA: tylko sprzęt sprawny technicznie.
  const HotWorkCheck(
    'weq-cables',
    HotWorkGroup.equipment,
    'Sprzęt sprawny technicznie: przewody spawalnicze i zasilające bez '
        'uszkodzeń izolacji, złącza dokręcone; uchwyt / palnik odkładany na '
        'izolowane, niepalne miejsce',
    'Equipment in good working order: welding and power cables with intact '
        'insulation, connections tight; holder / torch laid down on an '
        'insulated, non-combustible spot',
    source: kSrcMswia36u2,
  ),

  // ── Przed rozpoczęciem · ŚOI ─────────────────────────────────────────────
  const HotWorkCheck(
    'ppe-basic',
    HotWorkGroup.ppe,
    'Odzież trudnopalna bez śladów oleju, przyłbica / okulary z filtrem, '
        'rękawice spawalnicze, obuwie ochronne',
    'Flame-resistant clothing free of oil, helmet / goggles with the right '
        'filter, welding gloves, safety footwear',
  ),
  const HotWorkCheck(
    'ppe-extra',
    HotWorkGroup.ppe,
    'Ochrona dróg oddechowych, osobisty detektor gazów, szelki — jeśli '
        'wymaga zezwolenie',
    'Respiratory protection, personal gas monitor, harness — if the permit '
        'requires them',
    naAllowed: true,
  ),

  // ── W trakcie ────────────────────────────────────────────────────────────
  // Dozór w trakcie: praktyka (FM Global, NFPA 51B, OSHA 1910.252) — przepis
  // PL nie określa dozoru w trakcie, więc „wg zezwolenia”.
  const HotWorkCheck(
    'dur-watch',
    HotWorkGroup.watchDuring,
    'Dozór wg zezwolenia przez cały czas pracy: dozorujący z gaśnicą '
        'obserwuje również miejsca, gdzie spadają iskry, i może przerwać pracę',
    'Fire watch per the permit for the whole job: watcher with an '
        'extinguisher also watches where sparks land and can stop the work',
    source: kSrcPractice,
  ),
  // FM Global P9602_POL: pomiar gazów palnych przed pracą i w razie
  // potrzeby w trakcie.
  const HotWorkCheck(
    'dur-gas',
    HotWorkGroup.watchDuring,
    'Pomiar ciągły lub powtarzany, jeśli wymaga zezwolenie — wyniki '
        'dopisane w sekcji „Pomiar atmosfery”',
    'Continuous or repeated gas testing if the permit requires it — '
        'readings added under “Gas test”',
    naAllowed: true,
  ),
  const HotWorkCheck(
    'dur-stop',
    HotWorkGroup.watchDuring,
    'Przy zmianie warunków (alarm, zapach gazu, wzrost wskazań, przerwa '
        'w pracy) praca wstrzymana, a zezwolenie sprawdzone ponownie',
    'Work stopped and the permit re-checked whenever conditions change '
        '(alarm, gas smell, rising readings, break in the work)',
  ),

  // ── Po zakończeniu ───────────────────────────────────────────────────────
  // § 36 ust. 2 rozp. MSWiA: po zakończeniu kontrola miejsca prac
  // i rejonów przyległych (przepis nie podaje czasu).
  const HotWorkCheck(
    'aft-inspect',
    HotWorkGroup.closeOut,
    'Miejsce pracy i rejony przyległe skontrolowane po zakończeniu '
        '(tlące się materiały, nagrzane elementy, druga strona przegród)',
    'Work area and adjacent areas inspected after the work (smouldering '
        'material, hot parts, the other side of partitions)',
    source: kSrcMswia36u2,
  ),
  // Czas dozoru — przepis PL go NIE podaje → „wg zezwolenia”. Praktyka:
  // NFPA 51B-2019 § 5.6.1.1 — co najmniej 1 h (wcześniejsze wydania
  // 30 min); OSHA 29 CFR 1910.252(a)(2)(iii) — co najmniej 30 min; FM
  // Global P9602_POL — 30 albo 60 min wg kategorii.
  const HotWorkCheck(
    'aft-watch',
    HotWorkGroup.closeOut,
    'Dozór po zakończeniu pracy przez czas wskazany w zezwoleniu '
        '(praktyka: NFPA 51B:2019 — co najmniej 1 h)',
    'Post-work fire watch kept for the time stated in the permit '
        '(practice: NFPA 51B:2019 — at least 1 h)',
    source: 'NFPA 51B:2019 § 5.6.1.1 (praktyka)',
  ),
  const HotWorkCheck(
    'aft-gas-off',
    HotWorkGroup.closeOut,
    'Zawory butli zamknięte, węże odpowietrzone, sprzęt odłączony od '
        'zasilania i usunięty',
    'Cylinder valves closed, hoses bled, equipment disconnected and removed',
    naAllowed: true,
  ),
  const HotWorkCheck(
    'aft-handover',
    HotWorkGroup.closeOut,
    'Zakończenie pracy zgłoszone wystawiającemu, zezwolenie zamknięte',
    'Completion reported to the permit issuer, permit closed',
  ),
]);

final Map<String, HotWorkCheck> _byId = {
  for (final c in kHotWorkChecks) c.id: c,
};

HotWorkCheck? hotWorkCheckById(String id) => _byId[id];

List<HotWorkCheck> hotWorkChecksIn(HotWorkPhase phase) =>
    [for (final c in kHotWorkChecks) if (c.phase == phase) c];

List<HotWorkCheck> hotWorkChecksInGroup(HotWorkGroup group) =>
    [for (final c in kHotWorkChecks) if (c.group == group) c];

List<HotWorkGroup> hotWorkGroupsIn(HotWorkPhase phase) =>
    [for (final g in HotWorkGroup.values) if (g.phase == phase) g];
