/// Lista kontrolna wejścia i spawania w przestrzeni zamkniętej (zbiornik,
/// aparat, rurociąg dużej średnicy, kanał, studzienka) — jako dane (PL/EN),
/// w fazach: przed wejściem, w trakcie, po zakończeniu.
///
/// MODUŁ BEZPIECZEŃSTWA. Każdy punkt ma źródło (pełne opisy:
/// confined_space_sources.dart). Przepisy PL: rozporządzenie MPiPS
/// z 26.09.1997 w sprawie ogólnych przepisów BHP (§§ 85–90) i rozporządzenie
/// MG z 27.04.2000 w sprawie BHP przy pracach spawalniczych. Dobra praktyka
/// (OSHA 1910.146 / 1910.252, HSE L101) jest podpisana „praktyka”.
/// Przepis PL nie podaje wartości „bezpiecznego napięcia” — punkt mówi
/// „wg instrukcji zakładu”, bez liczb.
///
/// Identyfikatory punktów są zapisywane w historii — NIGDY ich nie zmieniaj.
///
/// Czysty Dart.
library;

enum ConfinedSpacePhase {
  before('Przed wejściem', 'Before entry'),
  during('W trakcie pracy', 'During work'),
  after('Po zakończeniu', 'After work ends');

  const ConfinedSpacePhase(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

enum ConfinedSpaceGroup {
  permit(ConfinedSpacePhase.before, 'Pozwolenie i organizacja',
      'Permit and organisation'),
  isolation(ConfinedSpacePhase.before, 'Odcięcie mediów i energii (LOTO)',
      'Isolation and lock-out (LOTO)'),
  cleaning(ConfinedSpacePhase.before, 'Opróżnienie i przewietrzenie',
      'Emptying and purging'),
  atmosphere(ConfinedSpacePhase.before, 'Pomiar atmosfery', 'Gas testing'),
  ventilation(ConfinedSpacePhase.before, 'Wentylacja', 'Ventilation'),
  rescue(ConfinedSpacePhase.before, 'Asekuracja i ratunek',
      'Attendant and rescue'),
  ppe(ConfinedSpacePhase.before, 'Środki ochrony indywidualnej',
      'Personal protective equipment'),
  electrical(ConfinedSpacePhase.before, 'Prąd i oświetlenie',
      'Electrical and lighting'),
  gases(ConfinedSpacePhase.before, 'Butle i gazy', 'Cylinders and gases'),
  watchDuring(ConfinedSpacePhase.during, 'Kontrola w trakcie',
      'Checks during work'),
  closeOut(ConfinedSpacePhase.after, 'Wyjście i zamknięcie',
      'Exit and close-out');

  const ConfinedSpaceGroup(this.phase, this.labelPl, this.labelEn);
  final ConfinedSpacePhase phase;
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

class ConfinedSpaceCheck {
  /// Trwały identyfikator (zapis w historii) — nie zmieniać.
  final String id;
  final ConfinedSpaceGroup group;
  final String pl;
  final String en;

  /// Wolno oznaczyć „nie dotyczy” (np. butle przy spawaniu MMA). Punkty
  /// podstawowe (pozwolenie, odcięcie, pomiar, asekuracja, szelki, zakaz
  /// tlenu) nie mają tej opcji.
  final bool naAllowed;

  /// Krótkie odwołanie do źródła pokazywane pod punktem.
  final String source;

  const ConfinedSpaceCheck(
    this.id,
    this.group,
    this.pl,
    this.en, {
    this.naAllowed = false,
    required this.source,
  });

  ConfinedSpacePhase get phase => group.phase;
  String label({required bool en}) => en ? this.en : pl;
}

// Krótkie odwołania do źródeł (pełne opisy: confined_space_sources.dart).

/// Rozporządzenie MPiPS z 26.09.1997 w sprawie ogólnych przepisów BHP
/// (t.j. Dz.U. 2003 nr 169 poz. 1650 ze zm.).
const String kSrcBhp = 'rozp. MPiPS 26.09.1997';

/// Rozporządzenie MG z 27.04.2000 w sprawie BHP przy pracach spawalniczych
/// (Dz.U. 2000 nr 40 poz. 470).
const String kSrcWeld = 'rozp. MG 27.04.2000';

/// Lista kontrolna — w kolejności wyświetlania.
final List<ConfinedSpaceCheck> kConfinedSpaceChecks = List.unmodifiable([
  // ── Przed wejściem · pozwolenie ──────────────────────────────────────────
  // § 86 ust. 1: praca w zbiorniku tylko na podstawie pisemnego pozwolenia
  // wydanego w trybie ustalonym przez pracodawcę.
  const ConfinedSpaceCheck(
    'perm-written',
    ConfinedSpaceGroup.permit,
    'Pisemne pozwolenie na pracę w zbiorniku wydane w trybie ustalonym przez '
        'pracodawcę — na to miejsce, zakres i godziny',
    'Written permit for work in the space issued under the employer’s '
        'procedure — for this location, scope and hours',
    source: '§ 86 ust. 1 $kSrcBhp',
  ),
  // § 86 ust. 2: stały nadzór; wydający polecenie sprawdza przygotowanie.
  // § 81 pkt 1: bezpośredni nadzór nad pracami szczególnie niebezpiecznymi.
  const ConfinedSpaceCheck(
    'perm-supervision',
    ConfinedSpaceGroup.permit,
    'Stały nadzór wyznaczony; wydający polecenie sprawdził przygotowanie '
        'organizacyjne i techniczne',
    'Constant supervision assigned; the person ordering the work has checked '
        'the organisational and technical preparation',
    source: '§ 86 ust. 2 $kSrcBhp; § 81',
  ),
  // § 88: przed wejściem kierujący informuje o zakresie pracy, zagrożeniach,
  // środkach ochrony, sygnalizacji i postępowaniu w razie zagrożenia.
  const ConfinedSpaceCheck(
    'perm-briefing',
    ConfinedSpaceGroup.permit,
    'Instruktaż bezpośrednio przed wejściem: zakres pracy, zagrożenia, środki '
        'ochrony, sygnały z asekurującym, co robić w razie zagrożenia',
    'Briefing right before entry: scope of work, hazards, protective '
        'measures, signals with the attendant, what to do in an emergency',
    source: '§ 88 $kSrcBhp',
  ),
  // § 87 ust. 1 pkt 2: przy zagrożeniu pożarowym — środki ochrony ppoż.;
  // spawanie to praca pożarowo niebezpieczna (rozp. MSWiA § 36).
  const ConfinedSpaceCheck(
    'perm-hotwork',
    ConfinedSpaceGroup.permit,
    'Spawanie / cięcie: zezwolenie na prace pożarowo niebezpieczne (osobny '
        'protokół) i sprzęt gaśniczy przy włazie',
    'Welding / cutting: hot work permit (separate record) and fire-fighting '
        'equipment at the manhole',
    naAllowed: true,
    source: '§ 87 ust. 1 pkt 2 $kSrcBhp; § 36 rozp. MSWiA 7.06.2010',
  ),

  // ── Przed wejściem · odcięcie ────────────────────────────────────────────
  // § 87 ust. 1 pkt 3: odłączyć dopływ materiałów i czynników z innych
  // zbiorników, przewodów, aparatury. Praktyka OSHA 1910.146(b)
  // „isolation”: zaślepienie, rozłączenie, podwójne odcięcie z upustem.
  const ConfinedSpaceCheck(
    'iso-blind',
    ConfinedSpaceGroup.isolation,
    'Dopływ mediów z innych zbiorników, rurociągów i aparatury odłączony — '
        'zaślepki lub rozłączenie (sam zamknięty zawór to za mało)',
    'Inflow from other vessels, pipes and equipment disconnected — blinds or '
        'removed spools (a closed valve alone is not enough)',
    source: '§ 87 ust. 1 pkt 3 $kSrcBhp; praktyka OSHA 1910.146(b)',
  ),
  // § 87 ust. 1 pkt 4: grzejniki, urządzenia ruchome i inne wewnątrz
  // odłączyć od źródeł zasilania.
  const ConfinedSpaceCheck(
    'iso-energy',
    ConfinedSpaceGroup.isolation,
    'Mieszadła, grzejniki i inne urządzenia wewnątrz odłączone od zasilania '
        'i zabezpieczone przed załączeniem (kłódka i zawieszka)',
    'Agitators, heaters and other equipment inside disconnected from power '
        'and locked against restart (lock and tag)',
    source: '§ 87 ust. 1 pkt 4 $kSrcBhp',
  ),
  // § 87 ust. 1 pkt 5: wyłączyć / unieruchomić przenośniki, zsypy, tory
  // nad zbiornikiem.
  const ConfinedSpaceCheck(
    'iso-above',
    ConfinedSpaceGroup.isolation,
    'Przenośniki, zsypy, tory i podobne nad zbiornikiem wyłączone lub '
        'unieruchomione',
    'Conveyors, chutes, rails and the like above the space stopped or '
        'immobilised',
    naAllowed: true,
    source: '§ 87 ust. 1 pkt 5 $kSrcBhp',
  ),

  // ── Przed wejściem · opróżnienie ─────────────────────────────────────────
  // § 87 ust. 1 pkt 1: opróżnić, wstępnie oczyścić (przemycie, para, gaz
  // obojętny, potem powietrze); tlenem niedopuszczalne. § 34 ust. 1 rozp.
  // MG: spawanie zbiorników po substancjach niebezpiecznych dopiero po
  // dokładnym oczyszczeniu.
  const ConfinedSpaceCheck(
    'clean-empty',
    ConfinedSpaceGroup.cleaning,
    'Zbiornik opróżniony i oczyszczony (przemycie, przedmuchanie parą lub '
        'gazem obojętnym, potem powietrzem); po substancjach niebezpiecznych '
        '— dokładnie oczyszczony przed spawaniem',
    'Space emptied and cleaned (washed, purged with steam or inert gas, then '
        'with air); after hazardous substances — thoroughly cleaned before '
        'welding',
    naAllowed: true,
    source: '§ 87 ust. 1 pkt 1 $kSrcBhp; § 34 ust. 1 $kSrcWeld',
  ),
  // § 87 ust. 2: kanał / studzienka — przewietrzyć odcinek przy otwartych
  // włazach, wyłączyć odcinek albo ograniczyć spływ ścieków.
  const ConfinedSpaceCheck(
    'clean-sewer',
    ConfinedSpaceGroup.cleaning,
    'Kanał / studzienka: odcinek przewietrzony przy otwartych włazach, '
        'wyłączony albo spływ ścieków maksymalnie ograniczony',
    'Sewer / manhole: section ventilated with manholes open, taken out of '
        'service or the flow reduced as far as possible',
    naAllowed: true,
    source: '§ 87 ust. 2 $kSrcBhp',
  ),
  // § 87 ust. 1 pkt 1: przedmuchiwanie zbiornika tlenem jest niedopuszczalne.
  const ConfinedSpaceCheck(
    'clean-no-oxygen',
    ConfinedSpaceGroup.cleaning,
    'Do przedmuchania i przewietrzenia NIE użyto tlenu',
    'Oxygen was NOT used for purging or ventilating',
    source: '§ 87 ust. 1 pkt 1 $kSrcBhp',
  ),
  // § 87 ust. 1 pkt 7: temperatura powietrza w zbiorniku nie różni się od
  // otoczenia o więcej niż 5 °C (5 K).
  const ConfinedSpaceCheck(
    'clean-temp',
    ConfinedSpaceGroup.cleaning,
    'Temperatura powietrza w zbiorniku różni się od otoczenia nie więcej niż '
        'o 5 °C (5 K)',
    'Air temperature inside differs from the surroundings by no more than '
        '5 °C (5 K)',
    source: '§ 87 ust. 1 pkt 7 $kSrcBhp',
  ),

  // ── Przed wejściem · atmosfera ───────────────────────────────────────────
  // Praktyka: sprawny detektor (test funkcjonalny / kalibracja).
  const ConfinedSpaceCheck(
    'atm-meter',
    ConfinedSpaceGroup.atmosphere,
    'Detektor wielogazowy sprawny — test funkcjonalny (bump test) '
        'i kalibracja wg producenta i instrukcji zakładu',
    'Multi-gas detector working — bump test and calibration per the maker '
        'and the site procedure',
    source: 'praktyka: instrukcja producenta detektora; OSHA 1910.146(d)(5)',
  ),
  // § 87 ust. 1 pkt 6 (brzmienie z Dz.U. 2007 nr 49 poz. 330): bezpośrednio
  // przed wejściem zbadać powietrze na zawartość tlenu oraz gazów i par
  // substancji niebezpiecznych. Kolejność i warstwy — OSHA 1910.146(d)(5).
  const ConfinedSpaceCheck(
    'atm-measure',
    ConfinedSpaceGroup.atmosphere,
    'Bezpośrednio przed wejściem zmierzono tlen, potem gazy palne, potem '
        'toksyczne — przy włazie, w środku i przy dnie (argon, CO₂ i propan '
        'zbierają się nisko); wyniki wpisane w „Pomiarach atmosfery”',
    'Right before entry oxygen was tested, then flammables, then toxics — at '
        'the manhole, in the middle and at the bottom (argon, CO₂ and propane '
        'collect low); results entered under “Gas readings”',
    source: '§ 87 ust. 1 pkt 6 $kSrcBhp; praktyka OSHA 1910.146(d)(5)',
  ),

  // ── Przed wejściem · wentylacja ──────────────────────────────────────────
  // § 90 ust. 1: włazy otwarte; gdy to nie wystarcza — stały nadmuch.
  const ConfinedSpaceCheck(
    'vent-hatches',
    ConfinedSpaceGroup.ventilation,
    'Wszystkie włazy otwarte przez cały pobyt ludzi w środku; gdy to nie '
        'wystarcza — stały nadmuch powietrza',
    'All manholes open while anyone is inside; if that is not enough — '
        'continuous forced air supply',
    source: '§ 90 ust. 1 $kSrcBhp',
  ),
  // § 87 ust. 1 pkt 1 (tlen niedopuszczalny); OSHA 1910.252(c)(4)(v):
  // tlenu nigdy nie używać do wentylacji.
  const ConfinedSpaceCheck(
    'vent-air-only',
    ConfinedSpaceGroup.ventilation,
    'Nawiew czystym powietrzem — nigdy tlenem; czerpnia z dala od spalin, '
        'wydechu agregatu i butli',
    'Ventilation with clean air — never oxygen; air intake away from '
        'exhausts, generator fumes and cylinders',
    source: '§ 87 ust. 1 pkt 1 $kSrcBhp; praktyka OSHA '
        '1910.252(c)(4)(v)',
  ),
  // § 90 ust. 1 (parametry powietrza); OSHA 1910.252(c)(4)(i).
  const ConfinedSpaceCheck(
    'vent-fume',
    ConfinedSpaceGroup.ventilation,
    'Odciąg dymów spawalniczych przy łuku / palniku, wywiew na zewnątrz',
    'Welding fume extraction at the arc / torch, exhaust led outside',
    naAllowed: true,
    source: '§ 90 ust. 1 $kSrcBhp; praktyka OSHA 1910.252(c)(4)(i)',
  ),

  // ── Przed wejściem · asekuracja ──────────────────────────────────────────
  // § 89 ust. 1: co najmniej jedna osoba asekurująca na zewnątrz, w stałym
  // kontakcie, z możliwością wezwania pomocy. OSHA 1910.146(i)(4):
  // asekurujący zostaje na zewnątrz, dopóki ktoś go nie zmieni.
  const ConfinedSpaceCheck(
    'res-attendant',
    ConfinedSpaceGroup.rescue,
    'Co najmniej jedna osoba asekurująca stale na zewnątrz, w stałym '
        'kontakcie z pracującymi, może od razu wezwać pomoc; nie wchodzi do '
        'środka',
    'At least one attendant permanently outside, in constant contact with '
        'the entrants, able to call help at once; does not go inside',
    source: '§ 89 ust. 1 $kSrcBhp; praktyka OSHA 1910.146(i)(4)',
  ),
  // § 88 pkt 4: sposób sygnalizacji między pracującymi a asekurującymi.
  const ConfinedSpaceCheck(
    'res-signals',
    ConfinedSpaceGroup.rescue,
    'Ustalony sposób sygnalizacji / łączności wnętrze — asekurujący (głos, '
        'linka, radio)',
    'Agreed signals / communication between the inside and the attendant '
        '(voice, line, radio)',
    source: '§ 88 pkt 4 $kSrcBhp',
  ),
  // § 89 ust. 2 pkt 1: szelki bezpieczeństwa z linką umocowaną do
  // wytrzymałego elementu konstrukcji zewnętrznej.
  const ConfinedSpaceCheck(
    'res-harness',
    ConfinedSpaceGroup.rescue,
    'Szelki bezpieczeństwa z linką zamocowaną do wytrzymałego elementu '
        'konstrukcji na zewnątrz',
    'Safety harness with a line anchored to a strong structure outside',
    source: '§ 89 ust. 2 pkt 1 $kSrcBhp',
  ),
  // § 86 ust. 3: natychmiastowa pierwsza pomoc; § 14 ust. 3 rozp. MG —
  // możliwość szybkiego opuszczenia stanowiska; HSE reg. 5 — plan
  // ratunkowy (praktyka).
  const ConfinedSpaceCheck(
    'res-plan',
    ConfinedSpaceGroup.rescue,
    'Plan ratunkowy: sprzęt do wyciągnięcia przez właz (np. trójnóg '
        'z wciągarką) na miejscu, pierwsza pomoc od razu dostępna, numer '
        'alarmowy (112 / służby zakładu) znany; nikt nie ratuje bez sprzętu '
        'izolującego',
    'Rescue plan: equipment to lift a person out through the manhole (e.g. '
        'tripod with winch) on site, first aid available at once, emergency '
        'number (112 / site services) known; nobody goes in to rescue '
        'without supplied-air breathing apparatus',
    source: '§ 86 ust. 3 $kSrcBhp; § 14 ust. 3 $kSrcWeld; '
        'praktyka HSE CSR 1997 reg. 5',
  ),
  // § 89 ust. 3: asekurujący wyposażony jak wchodzący.
  const ConfinedSpaceCheck(
    'res-attendant-ppe',
    ConfinedSpaceGroup.rescue,
    'Asekurujący ma takie same środki ochrony jak wchodzący',
    'The attendant has the same protective equipment as the entrants',
    source: '§ 89 ust. 3 $kSrcBhp',
  ),

  // ── Przed wejściem · ŚOI ─────────────────────────────────────────────────
  // § 89 ust. 2 pkt 2: hełm ochronny i odzież ochronna.
  const ConfinedSpaceCheck(
    'ppe-basic',
    ConfinedSpaceGroup.ppe,
    'Hełm ochronny i odzież ochronna — przy spawaniu trudnopalna, bez śladów '
        'oleju',
    'Safety helmet and protective clothing — flame-resistant and free of oil '
        'when welding',
    source: '§ 89 ust. 2 pkt 2 $kSrcBhp',
  ),
  // § 89 ust. 2 pkt 3, ust. 4–5: sprzęt izolujący; bez ochron dróg
  // oddechowych tylko przy O₂ ≥ 18 % i bez przekroczenia NDS — decyzja
  // osoby kierującej.
  const ConfinedSpaceCheck(
    'ppe-respirator',
    ConfinedSpaceGroup.ppe,
    'Sprzęt izolujący dróg oddechowych — chyba że kierujący zdecydował inaczej '
        'przy tlenie co najmniej 18 % i bez przekroczenia NDS (próg tlenu '
        'w aplikacji jest ostrzejszy)',
    'Supplied-air respiratory equipment — unless the supervisor decided '
        'otherwise with oxygen at least 18 % and nothing above the Polish OEL '
        '(the app’s oxygen limit is stricter)',
    source: '§ 89 ust. 2 pkt 3, ust. 4–5 $kSrcBhp',
  ),
  // Praktyka: osobisty detektor przez cały pobyt (OSHA 1910.146(d)(5)(ii)
  // — monitorowanie warunków w trakcie).
  const ConfinedSpaceCheck(
    'ppe-monitor',
    ConfinedSpaceGroup.ppe,
    'Osobisty detektor gazów (co najmniej O₂) na pracującym przez cały pobyt '
        'w środku',
    'Personal gas monitor (at least O₂) worn by the entrant the whole time '
        'inside',
    source: 'praktyka: OSHA 1910.146(d)(5)',
  ),

  // ── Przed wejściem · prąd ────────────────────────────────────────────────
  // § 90 ust. 2: oświetlenie elektryczne o bezpiecznym napięciu (bez
  // liczby w przepisie). § 90 ust. 4: środki zapobiegające wybuchowi.
  const ConfinedSpaceCheck(
    'el-light',
    ConfinedSpaceGroup.electrical,
    'Oświetlenie o bezpiecznym napięciu (wartość wg instrukcji zakładu), '
        'transformator / zasilacz poza zbiornikiem; tam, gdzie możliwy wybuch '
        '— w wykonaniu przeciwwybuchowym',
    'Lighting at a safe voltage (value per the site procedure), transformer / '
        'power supply outside the space; explosion-proof where an explosive '
        'atmosphere is possible',
    source: '§ 90 ust. 2 i 4 $kSrcBhp',
  ),
  // § 30 pkt 5 rozp. MG: źródła energii z dopuszczalnym napięciem bez
  // obciążenia, oznakowane, NA ZEWNĄTRZ; trudno zapalne maty izolacyjne.
  const ConfinedSpaceCheck(
    'el-welder',
    ConfinedSpaceGroup.electrical,
    'Spawanie łukowe: źródło prądu przeznaczone do pracy przy zwiększonym '
        'zagrożeniu porażeniem (oznakowanie producenta, np. symbol S), '
        'ustawione na zewnątrz; maty / chodniki izolacyjne trudnopalne',
    'Arc welding: power source rated for increased electric shock hazard '
        '(maker’s marking, e.g. the S symbol), placed outside; flame-retardant '
        'insulating mats',
    naAllowed: true,
    source: '§ 30 pkt 5 $kSrcWeld',
  ),

  // ── Przed wejściem · butle ───────────────────────────────────────────────
  // § 34 ust. 3 rozp. MG: urządzenia zasilające, w tym butle, na zewnątrz;
  // OSHA 1910.252(b)(4)(iii).
  const ConfinedSpaceCheck(
    'gas-cyl-outside',
    ConfinedSpaceGroup.gases,
    'Butle (argon, mieszanki, tlen, acetylen, propan) i urządzenia zasilające '
        'POZA zbiornikiem',
    'Cylinders (argon, mixes, oxygen, acetylene, propane) and supply '
        'equipment OUTSIDE the space',
    naAllowed: true,
    source: '§ 34 ust. 3 $kSrcWeld; praktyka OSHA 1910.252(b)(4)(iii)',
  ),
  // § 32 pkt 5 rozp. MG: butle z gazem palnym cięższym od powietrza nie
  // poniżej poziomu terenu, zwłaszcza przy kanałach i studzienkach.
  const ConfinedSpaceCheck(
    'gas-heavy',
    ConfinedSpaceGroup.gases,
    'Propan i inne gazy palne cięższe od powietrza: butle nie poniżej poziomu '
        'terenu, nie przy kanałach i studzienkach',
    'Propane and other fuel gases heavier than air: cylinders not below '
        'ground level, not near sewers and manholes',
    naAllowed: true,
    source: '§ 32 pkt 5 $kSrcWeld',
  ),
  // § 22 ust. 4 rozp. MG: kontrola szczelności węży (co najmniej raz na
  // kwartał); na miejscu — próba środkiem pianotwórczym przed wejściem.
  const ConfinedSpaceCheck(
    'gas-hoses',
    ConfinedSpaceGroup.gases,
    'Węże, palnik / uchwyt i złączki szczelne — sprawdzone środkiem '
        'pianotwórczym przed wprowadzeniem do zbiornika',
    'Hoses, torch and fittings leak-tight — checked with leak-detection '
        'fluid before taking them inside',
    naAllowed: true,
    source: '§ 22 ust. 4 $kSrcWeld',
  ),

  // ── W trakcie ────────────────────────────────────────────────────────────
  const ConfinedSpaceCheck(
    'dur-attendant',
    ConfinedSpaceGroup.watchDuring,
    'Asekurujący na stanowisku przez cały czas pobytu ludzi w środku, stały '
        'kontakt',
    'Attendant at the post the whole time anyone is inside, constant contact',
    source: '§ 89 ust. 1 $kSrcBhp',
  ),
  // § 87 ust. 1 pkt 6 + praktyka OSHA 1910.146(d)(5): monitorowanie w trakcie
  // — przy osłonie gazowej i formowaniu zwłaszcza tlen.
  const ConfinedSpaceCheck(
    'dur-monitor',
    ConfinedSpaceGroup.watchDuring,
    'Pomiar ciągły lub powtarzany — przy TIG, MIG/MAG i formowaniu zwłaszcza '
        'tlen; wyniki dopisywane w „Pomiarach atmosfery”',
    'Continuous or repeated testing — with TIG, MIG/MAG and purging '
        'especially oxygen; readings added under “Gas readings”',
    source: '§ 87 ust. 1 pkt 6 $kSrcBhp; praktyka OSHA 1910.146(d)(5)',
  ),
  // OSHA 1910.252(b)(4)(v)–(vi): w przerwie elektrody z uchwytów, zawory
  // palnika zamknięte, gaz odcięty na zewnątrz, palnik i węże wyjęte.
  const ConfinedSpaceCheck(
    'dur-break',
    ConfinedSpaceGroup.watchDuring,
    'Każda przerwa: gaz osłonowy / formujący i zawory butli zamknięte na '
        'zewnątrz, palnik, uchwyt i węże wyjęte ze zbiornika, elektroda wyjęta '
        'z uchwytu; po przerwie pomiar przed ponownym wejściem',
    'Every break: shielding / purge gas and cylinder valves closed outside, '
        'torch, holder and hoses taken out of the space, electrode removed '
        'from the holder; test again before re-entry',
    naAllowed: true,
    source: 'praktyka: OSHA 1910.252(b)(4)(v)–(vi)',
  ),
  // § 88 pkt 5: postępowanie w razie zagrożenia.
  const ConfinedSpaceCheck(
    'dur-evacuate',
    ConfinedSpaceGroup.watchDuring,
    'Alarm detektora, zapach, zawroty głowy, zmiana warunków — wszyscy '
        'natychmiast wychodzą; powrót dopiero po wyjaśnieniu i nowym pomiarze',
    'Detector alarm, odour, dizziness, any change — everyone gets out at '
        'once; re-entry only after the cause is found and a new test',
    source: '§ 88 pkt 5 $kSrcBhp',
  ),

  // ── Po zakończeniu ───────────────────────────────────────────────────────
  const ConfinedSpaceCheck(
    'aft-headcount',
    ConfinedSpaceGroup.closeOut,
    'Wszyscy wyszli — stan osób sprawdzony; narzędzia, materiały, węże '
        'i przewody wyjęte',
    'Everyone is out — headcount checked; tools, materials, hoses and cables '
        'taken out',
    source: 'praktyka: HSE CSR 1997 reg. 4; § 86 ust. 2 $kSrcBhp',
  ),
  const ConfinedSpaceCheck(
    'aft-gas-off',
    ConfinedSpaceGroup.closeOut,
    'Zawory butli zamknięte, węże odpowietrzone, spawarka odłączona',
    'Cylinder valves closed, hoses bled, welding machine disconnected',
    naAllowed: true,
    source: 'praktyka: OSHA 1910.252(b)(4)(v)–(vi)',
  ),
  // § 36 ust. 2 rozp. MSWiA: kontrola miejsca po pracach pożarowych.
  const ConfinedSpaceCheck(
    'aft-inspect',
    ConfinedSpaceGroup.closeOut,
    'Po spawaniu wnętrze i otoczenie skontrolowane (tlące się resztki, '
        'nagrzane elementy, izolacja)',
    'After welding the inside and surroundings inspected (smouldering '
        'residue, hot parts, insulation)',
    naAllowed: true,
    source: '§ 36 ust. 2 rozp. MSWiA 7.06.2010',
  ),
  const ConfinedSpaceCheck(
    'aft-close',
    ConfinedSpaceGroup.closeOut,
    'Zakończenie zgłoszone wydającemu pozwolenie, pozwolenie zamknięte; '
        'włazy zamykane dopiero po upewnieniu się, że nikogo nie ma w środku',
    'Completion reported to the permit issuer, permit closed; manholes closed '
        'only after making sure nobody is inside',
    source: '§ 86 ust. 1–2 $kSrcBhp',
  ),
]);

final Map<String, ConfinedSpaceCheck> _byId = {
  for (final c in kConfinedSpaceChecks) c.id: c,
};

ConfinedSpaceCheck? confinedSpaceCheckById(String id) => _byId[id];

List<ConfinedSpaceCheck> confinedSpaceChecksIn(ConfinedSpacePhase phase) =>
    [for (final c in kConfinedSpaceChecks) if (c.phase == phase) c];

List<ConfinedSpaceCheck> confinedSpaceChecksInGroup(ConfinedSpaceGroup g) =>
    [for (final c in kConfinedSpaceChecks) if (c.group == g) c];

List<ConfinedSpaceGroup> confinedSpaceGroupsIn(ConfinedSpacePhase phase) =>
    [for (final g in ConfinedSpaceGroup.values) if (g.phase == phase) g];
