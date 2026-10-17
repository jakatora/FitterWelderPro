/// Źródła i wartości odniesienia modułu „Tarcze i szlifierki”.
///
/// MODUŁ BEZPIECZEŃSTWA. Ustalenia sprawdzone w tekstach źródeł
/// (2026-10-18):
/// * EN 12413:2019 „Safety requirements for bonded abrasive products”
///   (PN-EN 12413) — spis treści sprawdzony w podglądzie STN EN 12413:2020:
///   zał. A (normatywny) — oznakowanie, tab. A.2 — ograniczenia użycia,
///   zał. D (informacyjny) — kody barwne, zał. E (informacyjny) — tabela
///   przeliczenia prędkości. Norma NIE obejmuje narzędzi nasypowych
///   (listkowe, fibrowe — EN 13743) ani diamentowych.
/// * oSa „Product marking requirements for bonded abrasives”, Issue 2,
///   2020-04 (wg EN 12413:2019): tarcze typu 27, 28, 29, 41, 42 na
///   szlifierki ręczne mają m.in. wymiary (otwór H = 22,23 mm), maks.
///   prędkość roboczą [m/s], maks. obroty [1/min], ograniczenia użycia
///   i kod identyfikowalności; spoiwo B i BF na szlifierki ręczne — data
///   ważności najpóźniej 3 lata od produkcji, zapis miesiąc/rok
///   („04/2023”); ograniczenie „Not permitted for face grinding — only for
///   use on cutting-off” dla wyrobów na szlifierki ręczne.
/// * oSa FAQ: data ważności obowiązkowa dla narzędzi na spoiwie żywicznym
///   na szlifierki ręczne (tarcze cienkie, do cięcia, do szlifowania),
///   najwyżej 3 lata, zwykle miesiąc i rok na metalowym pierścieniu;
///   tarcze żywiczne przechowywać w suchym miejscu (wilgoć obniża
///   wytrzymałość). NIE podaje, czy data oznacza początek, czy koniec
///   miesiąca.
/// * Lukas (katalog) — przykład zapisu na pierścieniu „V07/2018”;
///   Saint-Gobain (karta NOVIPRO) — V = kwartał produkcji + 3 lata.
/// * IEC 62841-2-3:2020 (EN IEC 62841-2-3:2021) — zakres: szlifierki
///   ręczne do 230 mm, prędkość obwodowa przy znamionowej średnicy
///   ≤ 80 m/s; zał. AA — osłona typu A (do tarcz tnących), B (do
///   szlifowania), C (kombinowana). Ostrzeżenia bezpieczeństwa z tej normy
///   — w instrukcjach (Bosch, Makita): prędkość osprzętu ≥ prędkość na
///   tabliczce, średnica i grubość w zakresie szlifierki, gwint = gwint
///   wrzeciona, otwór pasuje do kołnierza, oględziny i bieg próbny
///   1 MINUTĘ na maks. obrotach bez obciążenia, poza płaszczyzną tarczy,
///   nie szlifować bokiem tarczy do cięcia, nie używać zużytych tarcz
///   z większych szlifierek, rękojeść dodatkowa, nie przy materiałach
///   palnych, po zaniku zasilania włącznik na „wyłączony”, podpierać
///   duże elementy.
/// * Bosch — wskazówki robocze w instrukcjach szlifierek: przy cięciu
///   metalu tarczami spojonymi zawsze osłona do cięcia albo osłona do
///   szlifowania z nakładką do cięcia; tarcz tnących nie używać do
///   szlifowania zgrubnego.
/// * Klingspor „Maximum operating speed”: kod barwny nie jest już
///   obowiązkowy, ale bywa stosowany: niebieski 50, żółty 63, czerwony 80,
///   zielony 100 m/s. Niebiesko-żółty 125 m/s — tylko poradniki szkoleniowe
///   (High Speed Training, Commodious; żółty podają tam jako 60 m/s).
/// * Flexovit / Saint-Gobain — tabela przeliczenia wg EN 12413: Ø125 mm
///   przy 80 m/s = 12 250 obr./min (ze wzoru 12 223) — nadruki obrotów są
///   zaokrąglone, czasem W GÓRĘ względem wzoru.
/// * INOX: deklaracje producentów — Metabo: Fe + S + Cl ≤ 0,1 % łącznie;
///   Klingspor, RECA: każdy ≤ 0,1 %. Brak normy z jednym progiem.
///
/// NIE potwierdzono (dlatego nie ma tego w regułach): bieg próbny „30 s”
/// (oSa) — nie znaleziony, aplikacja podaje 1 min z ostrzeżeń EN 62841-2-3;
/// pełna tabela zał. D EN 12413 (paski powyżej 125 m/s) — nieodczytana;
/// wymagania grubości osłony do cięcia — pominięte.
///
/// Czysty Dart.
library;

/// Krótkie odwołania do źródeł pokazywane pod wynikiem / punktem listy.
const String kSrcEn12413 = 'EN 12413:2019, zał. A (oSa 2020-04)';
const String kSrcEn12413Restriction =
    'EN 12413:2019 tab. A.2 — tarcze do cięcia: niedozwolone szlifowanie '
    'czołowe (bokiem)';
const String kSrcExpiry =
    'EN 12413 / oSa: spoiwo B, BF — maks. 3 lata od produkcji';
const String kSrcEn62841 =
    'EN 62841-2-3 — ostrzeżenia w instrukcjach szlifierek (Bosch, Makita)';
const String kSrcBoschCutGuard =
    'EN 62841-2-3 zał. AA (osłona typu A); instrukcje Bosch';
const String kSrcInox =
    'deklaracje producentów (Metabo, Klingspor, RECA): Fe, S, Cl ≤ 0,1 %';
const String kSrcColour =
    'EN 12413 zał. D (informacyjny); Klingspor — kod barwny nieobowiązkowy';
const String kSrcOsaStorage = 'oSa FAQ — przechowywanie tarcz żywicznych';

/// Oznaczenie wyniku opartego na regule przyjętej w aplikacji (nie
/// w normie) — pokazywane w UI zamiast źródła.
const String kSrcApp = 'przyjęte w aplikacji';
const String kSrcAppEn = 'app rule';

/// Ile miesięcy naprzód może sięgać data ważności. EN 12413 / oSa: data
/// ważności najpóźniej 3 lata od produkcji, więc data dalej niż 36 mies. od
/// dziś to najpewniej literówka (np. 2072 zamiast 2027) — brak werdyktu.
const int kMaxExpiryMonthsAhead = 36;

/// Próg rozbieżności między obrotami a prędkością z etykiety (3 %).
///
/// Przyjęte w aplikacji: nadruki obrotów są zaokrąglane (Flexovit, tabela
/// wg EN 12413: Ø125 / 80 m/s = 12 250 zamiast 12 223 obr./min, ok. 0,2 %).
/// Większa różnica to zwykle inna średnica wpisana niż na tarczy.
const double kLabelMismatchRatio = 0.03;

class GrindingSource {
  final String pl;
  final String en;
  const GrindingSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

/// Lista na zakładce „Źródła”.
const List<GrindingSource> kGrindingSources = [
  GrindingSource(
    'EN 12413:2019 (PN-EN 12413) — wymagania bezpieczeństwa dla ściernic '
        'spojonych. Zał. A: oznakowanie (wymiary, maks. prędkość robocza '
        'm/s, maks. obroty 1/min, ograniczenia użycia, kod '
        'identyfikowalności); tab. A.2: tarcze do cięcia na szlifierki '
        'ręczne — „niedozwolone do szlifowania czołowego”, tylko do cięcia; '
        'zał. D: kody barwne; zał. E: tabela przeliczenia prędkości. Norma '
        'nie obejmuje tarcz listkowych i fibrowych (EN 13743).',
    'EN 12413:2019 — safety requirements for bonded abrasive products. '
        'Annex A: marking (dimensions, max operating speed m/s, max speed '
        'of rotation 1/min, restrictions of use, traceability code); '
        'Table A.2: cut-off wheels for hand-held machines — "not permitted '
        'for face grinding", cutting-off only; Annex D: colour codes; '
        'Annex E: speed conversion table. Flap and fibre discs are not '
        'covered (EN 13743).',
  ),
  GrindingSource(
    'oSa — „Product marking requirements for bonded abrasives” (wyd. 2, '
        '2020-04) i FAQ: tarcze na spoiwie żywicznym (B, BF) na szlifierki '
        'ręczne mają datę ważności najpóźniej 3 lata od produkcji, jako '
        'miesiąc/rok na metalowym pierścieniu (np. V 07/2027). Tarcze '
        'żywiczne przechowuj w suchym miejscu — wilgoć obniża ich '
        'wytrzymałość.',
    'oSa — "Product marking requirements for bonded abrasives" (issue 2, '
        '2020-04) and FAQ: resin-bonded (B, BF) wheels for hand-held '
        'machines carry an expiry date at most 3 years after manufacture, '
        'as month/year on the metal ring (e.g. V 07/2027). Store resin '
        'wheels dry — moisture reduces their strength.',
  ),
  GrindingSource(
    'EN IEC 62841-2-3 (IEC 62841-2-3:2020) — szlifierki ręczne do 230 mm, '
        'prędkość obwodowa przy znamionowej średnicy do 80 m/s; osłona '
        'typu A — do tarcz tnących, B — do szlifowania, C — kombinowana. '
        'Ostrzeżenia z tej normy w instrukcjach (Bosch, Makita): prędkość '
        'osprzętu co najmniej równa obrotom z tabliczki; średnica i grubość '
        'w zakresie szlifierki; gwint osprzętu = gwint wrzeciona; po '
        'założeniu bieg próbny 1 min na maks. obrotach, poza płaszczyzną '
        'tarczy; nie szlifować bokiem tarczy do cięcia; nie używać '
        'zużytych tarcz z większych szlifierek.',
    'EN IEC 62841-2-3 (IEC 62841-2-3:2020) — hand-held grinders up to '
        '230 mm, peripheral speed at rated capacity up to 80 m/s; guard '
        'type A — cut-off, B — grinding, C — combination. Its warnings in '
        'the manuals (Bosch, Makita): accessory rated speed at least the '
        'nameplate speed; diameter and thickness within the tool rating; '
        'accessory thread = spindle thread; after fitting run 1 min at max '
        'no-load speed, out of the wheel plane; never grind with the side '
        'of a cut-off wheel; no worn-down wheels from larger tools.',
  ),
  GrindingSource(
    'Bosch — wskazówki robocze w instrukcjach szlifierek kątowych: przy '
        'cięciu metalu tarczami spojonymi zawsze osłona do cięcia albo '
        'osłona do szlifowania z nakładką do cięcia; tarcz tnących nie '
        'używać do szlifowania zgrubnego.',
    'Bosch — working advice in angle grinder manuals: when cutting metal '
        'with bonded wheels always use the cutting guard, or the grinding '
        'guard with the cutting cover fitted; never use cut-off wheels for '
        'rough grinding.',
  ),
  GrindingSource(
    'Paski barwne (EN 12413 zał. D, informacyjny): Klingspor — niebieski '
        '50, żółty 63, czerwony 80, zielony 100 m/s; kod nie jest już '
        'obowiązkowy. Niebiesko-żółty 125 m/s — wg poradników '
        'szkoleniowych. Decyduje nadruk na tarczy.',
    'Colour stripes (EN 12413 Annex D, informative): Klingspor — blue 50, '
        'yellow 63, red 80, green 100 m/s; the code is no longer mandatory. '
        'Blue + yellow 125 m/s — per training guides. The printed label '
        'decides.',
  ),
  GrindingSource(
    'Obroty dopuszczalne: n = v · 60 000 / (π · D) [obr./min; v w m/s, D '
        'w mm], liczone W DÓŁ. Tabela wg EN 12413 (Flexovit) i nadruki '
        'zaokrąglają: Ø125 mm przy 80 m/s = 12 250 obr./min, ze wzoru '
        '12 223. Gdy podasz obie wartości, liczy się mniejsza.',
    'Permitted speed: n = v · 60 000 / (π · D) [rpm; v in m/s, D in mm], '
        'rounded DOWN. The EN 12413 table (Flexovit) and labels round: '
        'Ø125 mm at 80 m/s = 12 250 rpm, by formula 12 223. When both are '
        'entered, the lower one counts.',
  ),
  GrindingSource(
    'INOX: producenci deklarują zawartość żelaza, siarki i chloru do '
        '0,1 % — Metabo jako sumę Fe + S + Cl, Klingspor i RECA dla '
        'każdego z osobna. Jednej normy nie ma — sprawdź kartę wyrobu.',
    'INOX: makers declare iron, sulphur and chlorine up to 0.1 % — Metabo '
        'as the sum Fe + S + Cl, Klingspor and RECA for each. There is no '
        'single standard — check the product sheet.',
  ),
];

/// Reguły przyjęte w aplikacji (źródła ich nie rozstrzygają).
const List<GrindingSource> kGrindingAppRules = [
  GrindingSource(
    'Data ważności: źródła nie mówią, czy „V 07/2027” to początek, czy '
        'koniec lipca — przyjęto wariant ostrzejszy: tarcza ważna do końca '
        'czerwca 2027 (do początku miesiąca z nadruku).',
    'Expiry date: the sources do not say whether "V 07/2027" means the '
        'start or the end of July — the stricter reading is used: valid '
        'until the end of June 2027 (until the start of the printed month).',
  ),
  GrindingSource(
    'Data dalej niż 36 miesięcy od dziś = podejrzana literówka (max 3 lata '
        'od produkcji) — brak werdyktu. Tarcza 41, 42 lub 27 bez daty — STOP.',
    'A date more than 36 months ahead = likely typo (max 3 years from '
        'manufacture) — no verdict. A type 41, 42 or 27 wheel without a '
        'date — STOP.',
  ),
  GrindingSource(
    'Cięcie tarczą listkową, fibrową lub szczotką — STOP; cięcie tarczą 27 '
        '— ostrzeżenie (tylko gdy producent dopuszcza, z osłoną do cięcia).',
    'Cutting with a flap disc, fibre disc or brush — STOP; cutting with '
        'a type 27 wheel — warning (only if the maker allows it, with the '
        'cutting guard).',
  ),
  GrindingSource(
    'Obroty i prędkość z etykiety różnią się o ponad 3 % — ostrzeżenie '
        '(zwykle wpisana inna średnica); liczy się mniejsza wartość.',
    'Label speed and rpm differ by more than 3 % — warning (usually '
        'a different diameter was entered); the lower value counts.',
  ),
  GrindingSource(
    'Aluminium: osobne tarcze (do aluminium / metali nieżelaznych), nie '
        'używane na stali — dobra praktyka. Nie blokuj włącznika w pozycji '
        '„włączony” — dobra praktyka.',
    'Aluminium: dedicated discs (for aluminium / non-ferrous), never used '
        'on steel — good practice. Do not lock the switch on — good practice.',
  ),
];
