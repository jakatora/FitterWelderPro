/// Źródła i wartości odniesienia modułu „Przestrzeń zamknięta: wejście
/// i spawanie”.
///
/// Ustalenia sprawdzone w tekstach źródeł (2026-10-17/18, ISAP / API Sejmu):
/// * PL, przepis: rozporządzenie Ministra Pracy i Polityki Socjalnej
///   z 26 września 1997 r. w sprawie ogólnych przepisów bezpieczeństwa
///   i higieny pracy — t.j. Dz.U. 2003 nr 169 poz. 1650 ze zm. (Dz.U. 2007
///   nr 49 poz. 330 nadało brzmienie § 87 ust. 1 pkt 6; zmiany 2008, 2011
///   i Dz.U. 2021 poz. 2088 nie dotyczą §§ 85–90). Rozdział 6 „Prace
///   szczególnie niebezpieczne”: §§ 80–81 (wykaz, nadzór, instruktaż),
///   część C §§ 85–90 — prace w zbiornikach, kanałach, studzienkach,
///   wnętrzach urządzeń i innych przestrzeniach zamkniętych:
///   - § 86: pisemne pozwolenie, stały nadzór, natychmiastowa pierwsza pomoc;
///   - § 87 ust. 1: opróżnienie i przedmuchanie (TLENEM NIEDOPUSZCZALNE),
///     ochrona ppoż., odcięcie dopływu mediów, odłączenie urządzeń od
///     zasilania, unieruchomienie przenośników nad zbiornikiem, badanie
///     powietrza na tlen oraz gazy i pary substancji niebezpiecznych
///     BEZPOŚREDNIO przed wejściem, różnica temperatur do 5 °C (5 K);
///     ust. 2 — kanały i studzienki: przewietrzenie przy otwartych włazach;
///   - § 88: informacja przed wejściem (zakres, zagrożenia, środki ochrony,
///     sygnalizacja z asekurującym, postępowanie w razie zagrożenia);
///   - § 89: asekuracja co najmniej jednej osoby na zewnątrz w stałym
///     kontakcie; szelki z linką, hełm, odzież, sprzęt izolujący; ten sam
///     sprzęt dla asekurującego; bez ochron dróg oddechowych TYLKO przy O₂
///     co najmniej 18 % i bez przekroczenia NDS (decyzja kierującego);
///   - § 90: włazy otwarte, a w razie potrzeby stały nadmuch powietrza;
///     oświetlenie elektryczne o bezpiecznym napięciu (przepis NIE podaje
///     liczby — wartości 12 V / 24 V nie zostały potwierdzone w obecnych
///     przepisach PL, dlatego w aplikacji ich nie ma); środki zapobiegające
///     wybuchowi.
/// * PL, przepis: rozporządzenie Ministra Gospodarki z 27 kwietnia 2000 r.
///   w sprawie BHP przy pracach spawalniczych (Dz.U. 2000 nr 40 poz. 470):
///   § 14 ust. 3 (szybkie opuszczenie stanowiska), § 30 pkt 5 (źródła
///   energii do pomieszczeń z zagrożeniem porażeniem — oznakowane,
///   ustawione NA ZEWNĄTRZ, maty izolacyjne), § 32 pkt 5 (butle z gazem
///   palnym cięższym od powietrza nie poniżej terenu, nie przy kanałach
///   i studzienkach), § 34 ust. 1 (oczyszczenie zbiorników), ust. 3 (butle
///   i urządzenia zasilające na zewnątrz).
/// * PL, przepis: rozporządzenie MRPiPS z 12 czerwca 2018 r. w sprawie
///   NDS (Dz.U. 2018 poz. 1286), załącznik w brzmieniu Dz.U. 2026 poz. 447:
///   tlenek węgla [630-08-0] NDS 23 mg/m³ / 20 ppm, NDSCh 117 mg/m³ /
///   100 ppm; siarkowodór [7783-06-4] NDS 7 mg/m³, NDSCh 14 mg/m³ (ppm nie
///   podano). mg/m³ odnoszą się do 293 K (20 °C) i 101,3 kPa.
/// * PL, przepis (prace pożarowe): rozp. MSWiA z 7.06.2010, § 36 ust. 2 —
///   prace pożarowe tylko przy stężeniu nieprzekraczającym 10 % DGW
///   (zob. hot_work_sources.dart).
/// * Praktyka (NIE przepis PL): OSHA 29 CFR 1910.146 — (b) definicje:
///   atmosfera uboga w tlen poniżej 19,5 %, wzbogacona powyżej 23,5 %,
///   niebezpieczna — gaz palny ponad 10 % LFL; (d)(5) pomiar przed wejściem
///   i w trakcie, kolejność: tlen → palne → toksyczne; (i)(4) asekurujący
///   pozostaje na zewnątrz. OSHA 1910.252 — (b)(4)(iii) butle i spawarki na
///   zewnątrz, (b)(4)(v)–(vi) przerwy, (c)(4)(i) wentylacja, (c)(4)(v)
///   „tlenu nigdy nie używać do wentylacji”. HSE (Wielka Brytania):
///   Confined Spaces Regulations 1997, reg. 4–5; kodeks L101.
///
/// Czysty Dart.
library;

/// Dolna granica tlenu (% obj.) przyjęta w aplikacji.
///
/// Źródło: OSHA 29 CFR 1910.146(b) — „oxygen deficient atmosphere” to
/// mniej niż 19,5 % (praktyka). Przepis PL (rozp. MPiPS 26.09.1997, § 89
/// ust. 4) podaje 18 % — ale tylko jako warunek pracy BEZ ochron dróg
/// oddechowych. Aplikacja przyjmuje ostrzejsze 19,5 % i pozwala je tylko
/// podnieść.
const double kCsO2MinPct = 19.5;

/// Górna granica tlenu (% obj.). Źródło: OSHA 29 CFR 1910.146(b) —
/// „oxygen enriched atmosphere” to więcej niż 23,5 % (praktyka; przepis PL
/// nie podaje). Wolno ją tylko obniżyć.
const double kCsO2MaxPct = 23.5;

/// Tlen w czystym powietrzu atmosferycznym (% obj., zaokr.). Granice tlenu
/// muszą go obejmować — próg powyżej (dolny) albo poniżej (górny) to
/// literówka, przy której nawet czyste powietrze dawałoby STOP.
const double kCsO2AirPct = 20.9;

/// Przepis PL: minimum tlenu przy pracy bez ochron dróg oddechowych
/// (rozp. MPiPS 26.09.1997, § 89 ust. 4) — tylko do tekstów.
const double kCsO2NoRespiratorPlPct = 18;

/// Dopuszczalne % DGW (dolnej granicy wybuchowości, ang. LEL).
///
/// Źródła: rozp. MSWiA z 7.06.2010, § 36 ust. 2 — prace pożarowe (spawanie)
/// tylko przy stężeniu nieprzekraczającym 10 % DGW (przepis PL); OSHA
/// 1910.146(b) — atmosfera niebezpieczna powyżej 10 % LFL (praktyka).
/// Zakład może wymagać mniej (często 0–5 %) — wolno tylko obniżyć.
const double kCsLelMaxPct = 10;

/// Tlenek węgla — NDS z rozporządzenia MRPiPS w sprawie NDS (załącznik,
/// Dz.U. 2026 poz. 447): 20 ppm (przepis podaje też 23 mg/m³).
const double kCsCoNdsPpm = 20;
const double kCsCoNdsMgM3 = 23;

/// Siarkowodór — NDS 7 mg/m³ (ten sam załącznik; ppm nie podano).
const double kCsH2sNdsMgM3 = 7;

/// Masy molowe (g/mol) do przeliczenia mg/m³ ↔ ppm.
const double kCsCoMolarMass = 28.01;
const double kCsH2sMolarMass = 34.08;

/// Objętość molowa gazu (dm³/mol) w warunkach odniesienia NDS: 293 K
/// (20 °C) i 101,3 kPa — 8,314 · 293 / 101,3 ≈ 24,05.
///
/// ppm = mg/m³ · 24,05 / M; np. H₂S: 7 mg/m³ · 24,05 / 34,08 ≈ 4,94 ppm;
/// CO: 23 mg/m³ · 24,05 / 28,01 ≈ 19,75 ppm (przepis podaje 20 ppm — oba
/// wpisy ze zaokrągleń; aplikacja liczy CO w ppm i przyjmuje 20 ppm).
const double kCsMolarVolume = 24.05;

class ConfinedSpaceSource {
  final String pl;
  final String en;
  const ConfinedSpaceSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

/// Lista na ekranie „Źródła i wartości odniesienia”.
const List<ConfinedSpaceSource> kConfinedSpaceSources = [
  ConfinedSpaceSource(
    'Rozp. MPiPS z 26.09.1997 w sprawie ogólnych przepisów BHP (t.j. Dz.U. '
        '2003 nr 169 poz. 1650 ze zm.), §§ 85–90 — prace w zbiornikach, '
        'kanałach, studzienkach i innych przestrzeniach zamkniętych: pisemne '
        'pozwolenie i stały nadzór (§ 86), opróżnienie, odcięcie mediów, '
        'przedmuchanie — nigdy tlenem — i pomiar tlenu oraz gazów '
        'bezpośrednio przed wejściem (§ 87), instruktaż i sygnalizacja '
        '(§ 88), asekuracja na zewnątrz, szelki z linką, sprzęt izolujący — '
        'bez niego tylko przy tlenie co najmniej 18 % i bez przekroczenia NDS '
        '(§ 89), otwarte włazy lub stały nadmuch, oświetlenie o bezpiecznym '
        'napięciu (§ 90).',
    'Polish general OHS regulation of 26.09.1997 (consolidated Dz.U. 2003 '
        'No 169 item 1650 as amended), §§ 85–90 — work in tanks, sewers, '
        'manholes and other confined spaces: written permit and constant '
        'supervision (§ 86), emptying, isolation, purging — never with '
        'oxygen — and testing for oxygen and gases right before entry '
        '(§ 87), briefing and signals (§ 88), attendant outside, harness '
        'with line, supplied-air respirator — without it only with oxygen at '
        'least 18 % and nothing above the Polish OEL (§ 89), open manholes or '
        'continuous air supply, lighting at a safe voltage (§ 90).',
  ),
  ConfinedSpaceSource(
    'Rozp. MG z 27.04.2000 w sprawie BHP przy pracach spawalniczych '
        '(Dz.U. 2000 nr 40 poz. 470): § 30 pkt 5 (spawanie łukowe tam, gdzie '
        'grozi porażenie — źródło prądu do takich warunków, ustawione na '
        'zewnątrz, maty izolacyjne), § 32 pkt 5 (butle z gazem palnym '
        'cięższym od powietrza nie poniżej terenu ani przy studzienkach), '
        '§ 34 (oczyszczenie zbiorników; butle i zasilanie na zewnątrz).',
    'Polish welding OHS regulation of 27.04.2000 (Dz.U. 2000 No 40 item '
        '470): § 30(5) (arc welding where there is an electric shock hazard '
        '— power source rated for it, placed outside, insulating mats), '
        '§ 32(5) (fuel gas heavier than air not below ground or near '
        'manholes), § 34 (tanks cleaned; cylinders and supply outside).',
  ),
  ConfinedSpaceSource(
    'NDS — rozp. MRPiPS z 12.06.2018 (Dz.U. 2018 poz. 1286; załącznik '
        'w brzmieniu Dz.U. 2026 poz. 447): tlenek węgla 23 mg/m³ = 20 ppm '
        '(NDSCh 117 mg/m³ = 100 ppm), siarkowodór 7 mg/m³ (NDSCh 14 mg/m³). '
        'mg/m³ przy 20 °C i 101,3 kPa; ppm = mg/m³ · 24,05 / M — H₂S: '
        '7 mg/m³ ≈ 4,94 ppm, więc odczyt 5 ppm przekracza NDS.',
    'Polish OELs (NDS regulation of 12.06.2018, Dz.U. 2018 item 1286; '
        'annex as of Dz.U. 2026 item 447): carbon monoxide 23 mg/m³ = 20 ppm '
        '(STEL 117 mg/m³ = 100 ppm), hydrogen sulphide 7 mg/m³ (STEL '
        '14 mg/m³). mg/m³ at 20 °C and 101.3 kPa; ppm = mg/m³ · 24.05 / M — '
        'H₂S: 7 mg/m³ ≈ 4.94 ppm, so a 5 ppm reading is above the OEL.',
  ),
  ConfinedSpaceSource(
    'Praktyka — OSHA 29 CFR 1910.146: tlen poniżej 19,5 % = niedobór, '
        'powyżej 23,5 % = wzbogacenie (pożar), gaz palny ponad 10 % DGW = '
        'atmosfera niebezpieczna; pomiar w kolejności tlen, palne, toksyczne; '
        'asekurujący nie wchodzi do środka. OSHA 1910.252: butle i spawarki '
        'na zewnątrz, w przerwie gaz zamknięty, palnik wyjęty, tlenu nigdy '
        'do wentylacji. HSE: Confined Spaces Regulations 1997, kodeks L101.',
    'Practice — OSHA 29 CFR 1910.146: oxygen below 19.5 % = deficient, '
        'above 23.5 % = enriched (fire), flammable gas over 10 % LEL = '
        'hazardous atmosphere; test oxygen, then flammables, then toxics; '
        'the attendant stays outside. OSHA 1910.252: cylinders and welding '
        'machines outside, gas shut off and torch removed during breaks, '
        'never ventilate with oxygen. HSE: Confined Spaces Regulations 1997, '
        'ACOP L101.',
  ),
  ConfinedSpaceSource(
    'Progi w aplikacji to górne granice z przepisu albo przyjętej praktyki: '
        'tlen 19,5–23,5 %, do 10 % DGW, CO do 20 ppm, H₂S do 7 mg/m³. Można '
        'je tylko zaostrzyć — obowiązują wartości z pozwolenia.',
    'Limits in the app are the upper bounds from the regulation or the '
        'adopted practice: oxygen 19.5–23.5 %, up to 10 % LEL, CO up to '
        '20 ppm, H₂S up to 7 mg/m³. They can only be made stricter — the '
        'permit values apply.',
  ),
];
