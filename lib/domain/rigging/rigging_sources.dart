/// Źródła i wartości odniesienia modułu „Zawiesia i podwieszanie”.
///
/// Tekstów norm EN 1492-1, EN 1492-2, EN 818-4/-6 i EN 13414-1/-2 nie ma
/// w wolnym dostępie. Wartości sprawdzono (2026-10-18) w publikacjach, które
/// je przedrukowują albo na nich się opierają, każdą w co najmniej jednym
/// źródle urzędowym lub branżowym:
///
/// * [DGUV 209-021] DGUV Information 209-021 „Belastungstabellen für
///   Anschlagmittel”, wyd. 08/2021 (niemieckie ubezpieczenie wypadkowe),
///   https://publikationen.dguv.de/widgets/pdf/download/article/377 :
///   - pasy płaskie z pętlami „in Anlehnung an DIN EN 1492 Teil 1:2009-05”
///     i pasy okrągłe / bez końca „DIN EN 1492:2009-05 Teile 1 und 2”:
///     jeden pas — prosto 1, zadusznik („geschnürt”) 0,8, koszowe
///     („umgelegt”) 0° = 2 (przypis: odchyłka od pionu do 6° z tolerancji
///     manipulacji), do 45° = 1,4, ponad 45–60° = 1; dwa pasy — prosto 1,4
///     / 1, na zadusznik 1,12 / 0,8 (np. fioletowy 1000 kg: 800, 2000, 1400,
///     1000; 1400, 1120, 1000, 800);
///   - kod kolorów: fioletowy 1000 kg, zielony 2000, żółty 3000, szary 4000,
///     czerwony 5000, brązowy 6000, niebieski 8000, pomarańczowy 10 000;
///     wartości pośrednie (500, 1500, 2500 kg) BEZ koloru („–”);
///   - łańcuchy kl. 8 „in Anlehnung an DIN EN 818-4:1996+A1:2008”: jedno
///     cięgno 1, dwa 1,4 / 1, trzy i cztery 2,1 / 1,5 (np. 8 mm: 2000, 2800,
///     2000, 4250, 3000 kg); zadusznik: jedno 0,8, dwa 1,12 / 0,8 (1600,
///     2240, 1600 kg); kolumny „koszowe” dla łańcucha w tablicy NIE MA;
///   - liny stalowe „in Anlehnung an DIN EN 13414-1”: 1 / 1,4 / 1 / 2,1 /
///     1,5 (wartości tablicowe zaokrąglone, np. 10 mm: 1050, 1500, 1050,
///     2250, 1600 kg), zadusznik 0,8 (jedno i dwa cięgna);
///   - „Größer als 60° darf der Neigungswinkel nicht sein!” (kątomierz
///     na karcie); krawędź: promień r zawsze większy niż d (ogniwo, lina,
///     grubość pasa); przy wielu cięgnach tylko DWA uważa się za nośne,
///     chyba że zapewniono równy rozkład;
///   - odrzucenie łańcucha: wydłużenie wewnętrzne ≥ 5 % albo średnia
///     grubość ogniwa mniejsza o ponad 10 % od nominalnej (DIN 685);
///     liny: widoczne pęknięte druty — lina splotkowa 6 na długości 6d
///     albo 14 na 30d, pęknięta splotka, zgniecenia, załamania i kinki,
///     wżery korozyjne, uszkodzone zakończenia (EN 13414-2);
///   - temperatury: pasy PES/PA do 100 °C, PP do 80 °C, poniżej −40 °C
///     nie; łańcuch kl. 8 powyżej 200 °C nośność 90 %, powyżej 300 °C 75 %.
/// * [DGUV 109-005] DGUV Regel 109-005 (BGR 151) „Gebrauch von
///   Anschlag-Drahtseilen”, tab. 5 (zawiesia linowe bez końca, EN 13414-3):
///   koszowe do 7° = 2 × prosto, 0–45° = 1,4 ×, ponad 45–60° = 1 ×
///   (przedruk: umwelt-online.de, bgr/151b.htm).
/// * [LEEA] LEEA COPSULE (Code of Practice for the Safe Use of Lifting
///   Equipment), copsule.leeaint.com: 16.5.2 (pasy płaskie) i 17.5.2 (pasy
///   okrągłe) — prosto 1, zadusznik 0,8, koszowe równoległe 2, koszowe
///   0–45° 1,4, dwa cięgna 0–45° 1,4, cztery 2,1; 14.5.2 (łańcuchy) —
///   zadusznik 0,8 × także dla wielocięgnowych; łańcuch jednocięgnowy
///   w koszu zaczepiony z powrotem o ogniwo zawieszenia: najwyżej WLL
///   z oznaczenia („the full load is taken by the master link”), oba końce
///   na haku: 1,4 × przy 0–45°; 15.5.2 (liny) — to samo dla lin.
/// * [RUD] RUD Ketten, „Benutzerinformation für VIP-Anschlagketten”
///   (EN 818-6): zadusznik −20 %; „bei unsymmetrischer Belastung eines
///   Mehrstrang-Gehänges gilt laut EN 818-6 (Abschnitt A.1.3.5) die
///   1-Strang-Tragfähigkeit”; przy 4 cięgnach mogą nieść tylko 2 po
///   przekątnej; kąt 15–60°; ostre krawędzie — ochraniacz albo −20 %;
///   odrzucenie: brak/nieczytelna zawieszka, odkształcenie, wydłużenie
///   > 5 %, zużycie > 10 %, nacięcia, karby, pęknięcia, korozja, przebarwienia
///   od ciepła, rozwarcie gardzieli haka > 10 %, zapadka nie zamyka.
/// * [Dolezych] Dolezych, „Betriebsanleitung Rundschlingen und Hebebänder”
///   BA-001 (11/2014), DIN EN 1492-1/-2: „Neigungswinkel über 60° sind nicht
///   zulässig!”; dwa cięgna pod różnymi kątami — nośność JEDNEGO cięgna;
///   3–4 cięgna przy nierównym obciążeniu — nośność dwóch cięgien przy
///   największym kącie; zadusznik 80 %; na zadusznik tylko pasy ze
///   wzmocnionymi pętlami; ostra krawędź, gdy promień r < grubość d;
///   nie wiązać, nie skręcać, chronić przed iskrami przy spawaniu
///   i szlifowaniu; odrzucenie (Ablegereife): uszkodzenia brzegów i tkaniny,
///   pęknięcia przędzy ponad 10 % w przekroju, uszkodzone szwy nośne lub
///   osłona, odkształcenie od ciepła (tarcie, promieniowanie), działanie
///   substancji agresywnych, uszkodzone okucia, brak lub nieczytelna
///   etykieta.
/// * [Katalog] CERTEX / Mennens — tablice WLL wg EN 818-4 i EN 13414-1
///   z wierszem współczynników 1 · 0,8 · 2 · 1,4 · 1 · 2,1 · 1,5;
///   „multi-leg sling in a choker hitch — reduce the values by 20 %”; kod
///   kolorów: pomarańczowy = 10 t i więcej (certex.dk, mennens.nl).
///
/// Czysty Dart.
library;

class RiggingSource {
  final String pl;
  final String en;
  const RiggingSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

/// Lista na ekranie „Źródła”.
const List<RiggingSource> kRiggingSources = [
  RiggingSource(
    'DGUV Information 209-021 „Belastungstabellen für Anschlagmittel” '
        '(08/2021): pasy wg EN 1492-1/-2 — prosto ×1, zadusznik ×0,8, '
        'koszowe pionowe ×2 (odchyłka do 6°), do 45° ×1,4, 45–60° ×1; dwa '
        'pasy ×1,4 / ×1, na zadusznik ×1,12 / ×0,8; kod kolorów 1–10 t; '
        'łańcuchy kl. 8 wg EN 818-4 i liny wg EN 13414-1 — ×1, ×1,4 / ×1, '
        '×2,1 / ×1,5, zadusznik ×0,8; kąt od pionu nie większy niż 60°; '
        'kryteria odrzucenia łańcuchów i lin.',
    'DGUV Information 209-021 “Load tables for slings” (08/2021): slings to '
        'EN 1492-1/-2 — straight ×1, choke ×0.8, vertical basket ×2 (up to '
        '6° off vertical), up to 45° ×1.4, 45–60° ×1; two slings ×1.4 / ×1, '
        'choked ×1.12 / ×0.8; colour code 1–10 t; grade 8 chain to EN 818-4 '
        'and wire rope to EN 13414-1 — ×1, ×1.4 / ×1, ×2.1 / ×1.5, choke '
        '×0.8; angle to the vertical not above 60°; discard criteria for '
        'chain and rope.',
  ),
  RiggingSource(
    'DGUV Regel 109-005 „Gebrauch von Anschlag-Drahtseilen”, tab. 5: lina '
        'w koszowym do 7° ×2, 0–45° ×1,4, 45–60° ×1.',
    'DGUV Rule 109-005 “Use of wire rope slings”, Table 5: rope in basket '
        'hitch up to 7° ×2, 0–45° ×1.4, 45–60° ×1.',
  ),
  RiggingSource(
    'LEEA COPSULE 14.5.2, 15.5.2, 16.5.2, 17.5.2: współczynniki trybu dla '
        'łańcuchów, lin, pasów płaskich i okrągłych; łańcuch lub lina '
        'jednocięgnowa w koszowym zaczepiona z powrotem o ogniwo zawieszenia '
        '— najwyżej WLL z oznaczenia.',
    'LEEA COPSULE 14.5.2, 15.5.2, 16.5.2, 17.5.2: mode factors for chain, '
        'wire rope, webbing and roundslings; a single-leg chain or rope '
        'sling in basket hitch hooked back to its master link — no more '
        'than the marked WLL.',
  ),
  RiggingSource(
    'EN 818-6 (wg instrukcji RUD): przy niesymetrycznym obciążeniu zawiesia '
        'wielocięgnowego obowiązuje nośność jednego cięgna (A.1.3.5); '
        'zadusznik −20 %; kryteria odrzucenia łańcucha: wydłużenie > 5 %, '
        'zużycie > 10 %, rozwarcie haka > 10 %.',
    'EN 818-6 (per RUD user information): asymmetric load on a multi-leg '
        'sling — rate it as a single leg (A.1.3.5); choke −20 %; chain '
        'discard: elongation > 5 %, wear > 10 %, hook opening > 10 %.',
  ),
  RiggingSource(
    'Instrukcja Dolezych BA-001 (EN 1492-1/-2): kąt ponad 60° niedozwolony; '
        'dwa cięgna pod różnymi kątami — nośność jednego cięgna; ostra '
        'krawędź, gdy promień < grubość pasa; kryteria odrzucenia pasów; '
        'temperatura PES/PA do 100 °C, PP do 80 °C.',
    'Dolezych manual BA-001 (EN 1492-1/-2): angle above 60° not allowed; '
        'two legs at different angles — rate as one leg; sharp edge when the '
        'radius is below the sling thickness; webbing discard criteria; '
        'temperature PES/PA up to 100 °C, PP up to 80 °C.',
  ),
  RiggingSource(
    'Katalogi CERTEX / Mennens (EN 818-4, EN 13414-1, EN 1492-1): wiersz '
        'współczynników 1 · 0,8 · 2 · 1,4 · 1 · 2,1 · 1,5; zawiesie '
        'wielocięgnowe na zadusznik −20 %; pomarańczowy = 10 t i więcej.',
    'CERTEX / Mennens catalogues (EN 818-4, EN 13414-1, EN 1492-1): factor '
        'row 1 · 0.8 · 2 · 1.4 · 1 · 2.1 · 1.5; multi-leg sling choked '
        '−20 %; orange = 10 t and above.',
  ),
  RiggingSource(
    'Siła w cięgnie T = W / (n · cos β) — fizyka, tylko informacyjnie. '
        'Werdykt liczy się z tabeli współczynników (metoda obciążenia '
        'jednorodnego), nie z tego wzoru.',
    'Leg force T = W / (n · cos β) — physics, for information only. The '
        'verdict uses the mode factor table (uniform load method), not this '
        'formula.',
  ),
];

/// Co aplikacja przyjęła sama (brak wprost potwierdzonej wartości w źródle
/// albo rozstrzygnięcie w stronę bezpieczeństwa) — lista na ekranie.
const List<RiggingSource> kRiggingAdopted = [
  RiggingSource(
    'Kąt dokładnie 45° liczony w przedziale 45–60° (×1,0 / ×1,5) — tablice '
        'podają „0–45°” i „45–60°”, granica idzie w stronę bezpieczeństwa.',
    'An angle of exactly 45° falls into the 45–60° band (×1.0 / ×1.5) — '
        'the tables say “0–45°” and “45–60°”; the boundary goes the safe '
        'way.',
  ),
  RiggingSource(
    'Łańcuch w koszowym: ×1,0 przy każdym dozwolonym kącie (równoległym '
        'też). Tablica DGUV 209-021 nie ma dla łańcucha kolumny „koszowe”, '
        'LEEA 14.5.2 daje ×1,0 przy zaczepieniu z powrotem o ogniwo, a ×1,4 '
        'tylko przy obu końcach na haku; katalogi podają ×2 — aplikacja '
        'tego nie przyjmuje.',
    'Chain in basket hitch: ×1.0 at any allowed angle (vertical too). The '
        'DGUV 209-021 table has no basket column for chain, LEEA 14.5.2 '
        'gives ×1.0 when hooked back to the master link and ×1.4 only with '
        'both ends on the hook; catalogues show ×2 — the app does not use '
        'it.',
  ),
  RiggingSource(
    'Ładunek niesymetryczny: dla każdego rodzaju zawiesia i każdej '
        'konfiguracji (koszowe, 2 cięgna, 3–4 cięgna) liczone jak jedno '
        'cięgno (×1,0, na zadusznik ×0,8). Źródła mówią to wprost dla '
        'łańcucha (EN 818-6) i dla dwóch pasów; dla pozostałych przypadków '
        'przyjęto to samo.',
    'Asymmetric load: for every sling type and configuration (basket, 2 '
        'legs, 3–4 legs) rated as one leg (×1.0, choked ×0.8). The sources '
        'say so for chain (EN 818-6) and for two webbing slings; the app '
        'applies the same to the rest.',
  ),
  RiggingSource(
    '3–4 cięgna pasów lub lin na zadusznik: ×2,1 · 0,8 = ×1,68 i ×1,5 · 0,8 '
        '= ×1,2 — przez analogię do łańcuchów (LEEA 14.5.2: zadusznik ×0,8 '
        'także dla wielocięgnowych).',
    '3–4 legs of webbing or rope choked: ×2.1 · 0.8 = ×1.68 and ×1.5 · 0.8 '
        '= ×1.2 — by analogy with chain (LEEA 14.5.2: choke ×0.8 for '
        'multi-leg slings too).',
  ),
  RiggingSource(
    'Typoszereg pasów powyżej 10 t (12, 15, 20, 25, 30, 40, 50 t) — typowe '
        'pasy okrągłe producentów; norma ma dla nich jeden kolor '
        '(pomarańczowy).',
    'Sling series above 10 t (12, 15, 20, 25, 30, 40, 50 t) — typical '
        'manufacturer roundslings; the standard gives them one colour '
        '(orange).',
  ),
  RiggingSource(
    'Zaokrąglenia: masa w górę do 1 kg, nośność w dół do 1 kg; werdykt '
        'liczony w kilogramach, niezależnie od jednostki na ekranie.',
    'Rounding: mass up to 1 kg, capacity down to 1 kg; the verdict is '
        'computed in kilograms, whatever unit is shown.',
  ),
];
