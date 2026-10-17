/// Źródła, progi i wartości odniesienia modułu „Dymy spawalnicze
/// i odciąg”.
///
/// Ustalenia sprawdzone w tekstach źródeł (2026-10-18):
///
/// * [IARC] Monografia IARC t. 118 (2018; posiedzenie 21–28.03.2017):
///   dym spawalniczy i UV ze spawania — grupa 1, „rakotwórcze dla ludzi”
///   (wystarczające dowody — rak płuc; ograniczone — rak nerki); wcześniej
///   2B (1989). https://publications.iarc.who.int/569
/// * [HSE19] HSE STSU1 – 2019 „Change in HSE enforcement expectations for
///   mild steel welding fume”: każdy dym spawalniczy, także ze stali
///   węglowej, może powodować raka płuc; HSE nie akceptuje spawania bez
///   środków kontroli narażenia; w pomieszczeniach — środki techniczne
///   (zwykle odciąg miejscowy, LEV); gdy nie wystarczają — odpowiednie ŚOI na
///   dym resztkowy; ŚOI także przy spawaniu na zewnątrz.
///   https://www.hse.gov.uk/safetybulletins/mild-steel-welding-fume.htm
/// * [HSEW] HSE „Welding fume” (aktualizacja 2025-01-09): FFP3 albo
///   półmaska z P3 — do ok. godziny pracy; dłużej — sprzęt z nawiewem
///   o APF co najmniej 20; dla spawacza łukowego najlepszy sprzęt z nawiewem
///   lub doprowadzeniem powietrza „with an APF of at least 20”; FFP3/P3 nie
///   chroni przed gazami z dymu; test dopasowania, gładkie golenie;
///   na zewnątrz odciąg miejscowy nie działa.
///   https://www.hse.gov.uk/welding/protect-your-workers/avoid-reduce-exposure.htm
///   https://www.hse.gov.uk/welding/welding-controls.htm
/// * [HSG53] HSE HSG53 „Respiratory protective equipment at work” (wyd. 4,
///   2013), przypisane współczynniki ochrony (APF): FFP2 10, FFP3 20,
///   półmaska + P2 10, + P3 20, TH1 10, TH2 20, TH3 40; z zarostem sprzęt
///   szczelnie przylegający nie nadaje się (pkt 82).
///   https://www.hse.gov.uk/pubns/priced/hsg53.pdf
/// * [DGUV] DGUV Regel 112-190 „Benutzung von Atemschutzgeräten” (2021.11),
///   tabela 2 „Schutzniveau”: FFP2 / półmaska P2 10, FFP3 / P3 30, przyłbica
///   lub kaptur z nawiewem TH1 5, TH2 20, TH3 100; TH1 nie przeciw
///   substancjom CMR. https://publikationen.dguv.de/regelwerk/dguv-regeln/1011/benutzung-von-atemschutzgeraeten
/// * [EN529] EN 529:2005 — dobór i użytkowanie sprzętu ochrony układu
///   oddechowego; współczynniki przypisane różnią się w krajach UE (za 3M
///   „Protection Factors for Respirators (EMEA)”, 2024 — źródło producenta).
/// * [INDG479] HSE INDG479 rev2 (10/2025) — test dopasowania sprzętu
///   szczelnie przylegającego; nie testuje się przy zaroście w strefie
///   uszczelnienia. https://www.hse.gov.uk/pubns/indg479.pdf
/// * [NDS] Rozporządzenie MRPiPS z 12.06.2018 w sprawie NDS i NDN
///   (Dz.U. 2018 poz. 1286), załącznik nr 1 w brzmieniu Dz.U. 2026 poz. 447
///   (w mocy od 2.04.2026; późniejsza zmiana Dz.U. 2026 poz. 1211 dotyczy
///   tylko § 4 — tlenek azotu w górnictwie). Wartości przepisane z tekstu
///   aktów (ELI API Sejmu):
///   - mangan i związki nieorganiczne (Mn): 0,2 wdychalna, 0,05 respirabilna;
///   - związki chromu(VI) (Cr(VI)): 0,005;
///   - związki niklu (Ni): 0,05 wdychalna, 0,01 respirabilna;
///   - tlenek cynku (Zn), frakcja wdychalna: NDS 5, NDSCh 10;
///   - ołów i związki nieorganiczne (Pb), frakcja wdychalna: 0,03 (do
///     8.04.2026 — 0,05, § 2 ust. 1 pkt 3 Dz.U. 2026 poz. 447);
///   - ozon: 0,15;
///   - kadm i związki nieorganiczne (Cd), frakcja wdychalna: 0,001
///     w załączniku; przepis przejściowy Dz.U. 2020 poz. 61 § 2 ust. 4 —
///     0,004 od 11.07.2021 do 11.07.2027 (aplikacja pokazuje ostrzejsze
///     0,001 i wspomina o przejściowym);
///   - ditlenek azotu: NDS 0,7, NDSCh 1,5; tlenek azotu: NDS 2,5;
///   - tlenek węgla: NDS 23 (20 ppm), NDSCh 117 (100 ppm);
///   - fluorki (F): 2;
///   - tlenki żelaza (Fe): 5 wdychalna (NDSCh 10), 2,5 respirabilna (NDSCh 5).
///   Wszystko w mg/m³. Glinu i miedzi nie potwierdzano — bez liczby.
/// * [CMD] Dyrektywa 2004/37/WE, zał. III w brzmieniu dyrektywy (UE)
///   2017/2398: związki Cr(VI) 0,005 mg/m³; środki przejściowe: 0,010 mg/m³
///   do 17.01.2025, a dla spawania, cięcia plazmowego i podobnych procesów
///   wytwarzających dym 0,025 mg/m³ do 17.01.2025. W Polsce rozp. Dz.U. 2020
///   poz. 61 § 2 ust. 6 dało przejściowo 0,01 mg/m³ także dla spawania (do
///   17.01.2025); od 18.01.2025 — 0,005 bez wyjątku dla spawania.
///   https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32017L2398
/// * [OSHA-Cr] OSHA 3373 „Hexavalent Chromium”: narażenie przy spawaniu
///   nierdzewki, stopów wysokochromowych i metalu chromowanego;
///   OSHA FS-3647 (2013): chrom przechodzi w Cr(VI) w procesie spawania.
/// * [NIOSH-Zn] NIOSH Pocket Guide — tlenek cynku: gorączka metaliczna
///   (dreszcze, bóle mięśni, nudności, gorączka, suche gardło, kaszel).
/// * [ACGIH] ACGIH „Industrial Ventilation — A Manual of Recommended
///   Practice”, 23. wyd. (1998; kopia: archive.org gov.law.acgih.manual.1998):
///   - rys. 3-11: otwór swobodny Q = V(10X² + A), z kołnierzem
///     Q = 0,75V(10X² + A) — dla otworów okrągłych i W/L ≥ 0,2; poniżej
///     0,2 szczelina (Q = 3,7·L·V·X — w aplikacji nie liczymy);
///   - równ. 3.3: „accurate only for limited distance of X, where X is
///     within 1.5 D” — D: średnica albo bok otworu zbliżonego do kwadratu;
///     dla prostokąta aplikacja bierze KRÓTSZY bok (ostrzej);
///   - 3.4.3: kołnierz zmniejsza potrzebny przepływ o ok. 25 %; szerokość
///     kołnierza zwykle ≈ √A;
///   - tab. 3-1: spawanie — „released at low velocity into moderately
///     still air”, 100–200 fpm (0,5–1,0 m/s); szlifowanie — 500–2000 fpm
///     (2,5–10 m/s); górny koniec przy przeciągach, dużej toksyczności,
///     małym okapie;
///   - VS-90-02, uwaga 4: prędkości ponad 100–200 fpm mogą zakłócić osłonę
///     gazową. Bieżące wydania mają inną numerację.
/// * [OSHA-TM] OSHA Technical Manual, sekcja III, rozdz. 3 „Ventilation”:
///   odległość od źródła nie powinna przekraczać 1,5 średnicy (bez równania
///   DallaValle). https://www.osha.gov/otm/section-3-health-hazards/chapter-3
/// * [OSHA252] 29 CFR 1910.252(c)(3)(i): ruchome okapy „as near as
///   practicable”, prędkość 100 ft/min (≈ 0,5 m/s) w strefie spawania.
/// * [HSG258] HSE HSG258 „Controlling airborne contaminants at work”
///   (wyd. 3, 2017): tab. 9 — spawanie 0,5–1,0 m/s; tab. 10 i WL3 — okap
///   zwykle nie dalej niż jedna średnica okapu; pkt 232–233 — recyrkulacja
///   tylko z dokładnym oczyszczeniem i kontrolą filtra.
///   https://www.hse.gov.uk/pubns/priced/hsg258.pdf
/// * [DGUV-LEV] DGUV Regel 109-002 (2020), tab. 6 (za VDI 2262-4): dym
///   spawalniczy 0,3–0,5 m/s — łagodniej niż ACGIH/HSE; aplikacja przyjmuje
///   ostrzejsze minimum 0,5 m/s.
/// * [RR683] HSE RR683 (HSL/TWI, 2009): przy najgorszych parametrach MIG
///   porowatość od ok. 1 m/s przepływu poprzecznego; okap 300 mm przy
///   800 m³/h w odległości do jednej średnicy — wychwyt bliski 100 % bez
///   porowatości.
/// * [TRGS528] TRGS 528 „Schweißtechnische Arbeiten” (02/2020): 4.4.2 —
///   odciąg punktowy niskopodciśnieniowy łapie dobrze do 30–40 cm, za duży
///   przepływ w palniku wysysa gaz osłonowy; 4.5(4) — przy materiałach
///   z Cr i Ni powietrza zasadniczo nie zawraca się, a jeśli — tylko przez
///   urządzenie badane wg EN ISO 21904-1 i -2 i oznaczone W3.
/// * [W] Klasy skuteczności W1 95 %, W2 98 %, W3 99 % (IFA, projekt BIA
///   3064; EN ISO 15012-1:2013 zastąpiona przez EN ISO 21904-2:2020 —
///   czy W1/W2 pozostały w nowej normie, nie potwierdzono).
///
/// Czysty Dart.
library;

import 'fume_hazards.dart';

// ── Odciąg ─────────────────────────────────────────────────────────────────

/// Domyślna i minimalna prędkość uchwycenia dla spawania [m/s] — dolny
/// koniec przedziału ACGIH (zob. [kFumeWeldingRangeMs]). Próg tylko
/// zaostrzalny.
const double kFumeCaptureDefaultMs = 0.5;
const double kFumeCaptureMinMs = 0.5;

/// Przedział prędkości uchwycenia dla spawania [m/s] (ACGIH).
const (double, double) kFumeWeldingRangeMs = (0.5, 1.0);

/// Szlifowanie — cząstki wyrzucane z dużą prędkością: przedział ACGIH
/// [m/s]; minimum = dolny koniec.
const (double, double) kFumeGrindingRangeMs = (2.5, 10.0);
const double kFumeCaptureGrindingMinMs = 2.5;

/// Współczynnik równania dla otworu z kołnierzem (Q = 0,75·V·(10X² + A)).
const double kFumeFlangeFactor = 0.75;

/// Granica ważności równania DallaValle: X ≤ 1,5·D.
const double kFumeDallaValleMaxXOverD = 1.5;

/// Najmniejszy stosunek boków otworu prostokątnego, dla którego równanie
/// obowiązuje; poniżej — szczelina.
const double kFumeMinAspectRatio = 0.2;

/// Prędkość powietrza przy łuku, powyżej której ostrzegamy o zdmuchnięciu
/// osłony gazowej [m/s]: ACGIH VS-90-02 — ponad 100–200 fpm (0,5–1,0 m/s)
/// może zakłócać osłonę; HSE RR683 — porowatość od ok. 1 m/s przy
/// najgorszych parametrach. Górny koniec, bo 0,5 m/s to zarazem minimum
/// uchwycenia.
const double kFumeShieldDraughtMs = 1.0;

// ── Ochrona dróg oddechowych ───────────────────────────────────────────────

/// Wiersz tabeli współczynników ochrony.
class FumeApfRow {
  const FumeApfRow(this.rpe, {this.hse, this.dguv});
  final FumeRpe rpe;

  /// HSE HSG53 — assigned protection factor.
  final int? hse;

  /// DGUV Regel 112-190 — Schutzniveau.
  final int? dguv;
}

const List<FumeApfRow> kFumeApf = [
  FumeApfRow(FumeRpe.p2, hse: 10, dguv: 10),
  FumeApfRow(FumeRpe.p3, hse: 20, dguv: 30),
  FumeApfRow(FumeRpe.th1, hse: 10, dguv: 5),
  FumeApfRow(FumeRpe.th2, hse: 20, dguv: 20),
  FumeApfRow(FumeRpe.th3, hse: 40, dguv: 100),
];

const String kFumeApfNotePl =
    'Współczynniki przypisane (ile razy mniej dymu pod maską przy dobrym '
    'dopasowaniu i prawidłowym użyciu): HSE HSG53 i DGUV 112-190 — różnią się '
    'między krajami (EN 529). Półmaska i FFP działają tylko szczelnie '
    'dopasowane: test dopasowania i gładko ogolona strefa uszczelnienia '
    '(HSE INDG479); z zarostem — sprzęt z nawiewem. HSE: FFP3/P3 do ok. '
    'godziny pracy, dłużej — nawiew z APF co najmniej 20.';
const String kFumeApfNoteEn =
    'Assigned protection factors (how many times less fume inside, with a '
    'good fit and correct use): HSE HSG53 and DGUV 112-190 — they differ '
    'between countries (EN 529). Half masks and FFPs only work with a tight '
    'fit: fit test and a clean-shaven seal area (HSE INDG479); with facial '
    'hair — powered equipment. HSE: FFP3/P3 for up to about an hour, longer '
    '— powered, APF at least 20.';

/// Hierarchia środków ochrony (kolejność). (PL, EN)
const List<(String, String)> kFumeHierarchy = [
  (
    'Eliminacja i zmiana: usuń powłoki ze strefy spawania, wybierz proces '
        'mniej dymiący (np. MIG/TIG zamiast MMA, gdy się da), mniejszy prąd.',
    'Eliminate and substitute: remove coatings from the weld area, choose a '
        'lower-fume process (e.g. MIG/TIG instead of MMA where possible), '
        'lower current.'
  ),
  (
    'Odciąg u źródła: ssawka blisko łuku, uchwyt z odciągiem, stół z '
        'odciągiem — wymagany przy każdym spawaniu w pomieszczeniu (HSE 2019).',
    'Extraction at source: hood close to the arc, on-torch extraction, '
        'downdraft table — needed for all indoor welding (HSE 2019).'
  ),
  (
    'Wentylacja ogólna: wymiana powietrza w hali — uzupełnia odciąg, nie '
        'zastępuje go.',
    'General ventilation: air change in the workshop — adds to extraction, '
        'never replaces it.'
  ),
  (
    'Ochrona dróg oddechowych (ŚOI): na dym, którego odciąg nie złapał, '
        'i tam, gdzie odciągu nie da się użyć (np. na zewnątrz).',
    'Respiratory protective equipment (RPE): for the fume the extraction '
        'misses and where extraction cannot be used (e.g. outdoors).'
  ),
];

// ── NDS ────────────────────────────────────────────────────────────────────

/// Stan prawny NDS pokazywany na ekranie.
const String kFumeNdsLegalPl =
    'NDS (mg/m³, średnia na 8 h): rozp. MRPiPS z 12.06.2018 (Dz.U. 2018 poz. '
    '1286), załącznik w brzmieniu Dz.U. 2026 poz. 447 — stan prawny na '
    '18.10.2026. NDSCh — wartość chwilowa (15 min).';
const String kFumeNdsLegalEn =
    'Polish OELs (NDS, mg/m³, 8-h average): regulation of 12.06.2018 (Dz.U. '
    '2018 item 1286), annex as of Dz.U. 2026 item 447 — law as at '
    '18.10.2026. STEL (NDSCh) — 15-minute value.';

const String kFumeCrViNotePl =
    'Cr(VI): dyrektywa 2004/37/WE (zmiana 2017/2398) dopuszczała dla '
    'spawania i cięcia plazmowego przejściowo 0,025 mg/m³ — tylko do '
    '17.01.2025. W Polsce przejściowo 0,01 mg/m³ (Dz.U. 2020 poz. 61). Od '
    '18.01.2025 obowiązuje 0,005 mg/m³, także przy spawaniu.';
const String kFumeCrViNoteEn =
    'Cr(VI): Directive 2004/37/EC (as amended by 2017/2398) allowed '
    '0.025 mg/m³ for welding and plasma cutting as a transitional value — '
    'only until 17.01.2025. Poland had 0.01 mg/m³ in the meantime (Dz.U. '
    '2020 item 61). Since 18.01.2025 the limit is 0.005 mg/m³, welding '
    'included.';

const String kFumeCdNotePl =
    'Kadm: załącznik podaje 0,001 mg/m³; przepis przejściowy (Dz.U. 2020 '
    'poz. 61 § 2 ust. 4) — 0,004 mg/m³ do 11.07.2027. Aplikacja pokazuje '
    'ostrzejszą wartość.';
const String kFumeCdNoteEn =
    'Cadmium: the annex gives 0.001 mg/m³; a transitional rule (Dz.U. 2020 '
    'item 61 § 2(4)) — 0.004 mg/m³ until 11.07.2027. The app shows the '
    'stricter value.';

const String kFumePbNotePl =
    'Ołów: 0,03 mg/m³ od 9.04.2026 (wcześniej 0,05; dyrektywa (UE) 2024/869).';
const String kFumePbNoteEn =
    'Lead: 0.03 mg/m³ since 9.04.2026 (previously 0.05; Directive (EU) '
    '2024/869).';

// ── Recyrkulacja ───────────────────────────────────────────────────────────

const String kFumeRecircNotePl =
    'Urządzenia filtrujące dym spawalniczy mają klasy skuteczności W1 '
    '(95 %), W2 (98 %), W3 (99 %). Przy nierdzewce i stopach niklu (Cr, Ni) '
    'powietrza zasadniczo nie zawraca się do hali — wywiew na zewnątrz; '
    'wyjątkowo tylko urządzenie badane wg EN ISO 21904-1/-2 i oznaczone W3 '
    '(TRGS 528). HSE: recyrkulacja tylko z dokładnym oczyszczeniem '
    'i sygnalizacją zapchanego lub uszkodzonego filtra. Zapchany filtr to '
    'mniejsza wydajność — zasięg z kalkulatora maleje.';
const String kFumeRecircNoteEn =
    'Welding fume filter units have efficiency classes W1 (95 %), W2 (98 %), '
    'W3 (99 %). With stainless and nickel alloys (Cr, Ni) air is in '
    'principle not returned to the workshop — exhaust it outside; '
    'exceptionally only through a unit tested to EN ISO 21904-1/-2 and '
    'marked W3 (TRGS 528). HSE: recirculate only with thorough cleaning and '
    'a blocked or damaged filter alarm. A clogged filter means less airflow '
    '— the reach from the calculator shrinks.';

// ── Lista źródeł na ekranie ────────────────────────────────────────────────

class FumeSource {
  const FumeSource(this.pl, this.en);
  final String pl;
  final String en;
  String label({required bool en}) => en ? this.en : pl;
}

const List<FumeSource> kFumeSources = [
  FumeSource(
    'IARC, Monografie t. 118 (2018; posiedzenie 03.2017): dym spawalniczy '
        'i UV ze spawania — grupa 1, rakotwórcze dla ludzi.',
    'IARC Monographs vol. 118 (2018; meeting 03.2017): welding fume and UV '
        'from welding — group 1, carcinogenic to humans.',
  ),
  FumeSource(
    'HSE STSU1 – 2019: każdy dym spawalniczy, także ze stali węglowej, może '
        'powodować raka płuc; w pomieszczeniach środki techniczne (odciąg), '
        'ŚOI na dym resztkowy i przy spawaniu na zewnątrz. HSE „Welding '
        'fume”: dla spawacza APF co najmniej 20; FFP3/P3 do ok. godziny, nie '
        'chroni przed gazami.',
    'HSE STSU1 – 2019: all welding fume, mild steel included, can cause lung '
        'cancer; indoors engineering control (extraction), RPE for residual '
        'fume and for welding outdoors. HSE “Welding fume”: APF at least 20 '
        'for welders; FFP3/P3 for up to about an hour, no protection from '
        'gases.',
  ),
  FumeSource(
    'Równanie DallaValle i granice: ACGIH „Industrial Ventilation” (wyd. 23, '
        'rys. 3-11, równ. 3.3) — X ≤ 1,5·D, otwór okrągły lub W/L ≥ 0,2, '
        'kołnierz ok. −25 % przepływu; OSHA Technical Manual III:3 — nie '
        'dalej niż 1,5 średnicy.',
    'DallaValle equation and limits: ACGIH “Industrial Ventilation” (23rd '
        'ed., fig. 3-11, eq. 3.3) — X ≤ 1.5·D, round or W/L ≥ 0.2, flange '
        'about −25 % airflow; OSHA Technical Manual III:3 — no further than '
        '1.5 diameters.',
  ),
  FumeSource(
    'Prędkość uchwycenia: ACGIH tab. 3-1 i HSE HSG258 tab. 9 — spawanie '
        '0,5–1,0 m/s; ACGIH — szlifowanie 2,5–10 m/s; OSHA 29 CFR '
        '1910.252(c)(3)(i) — 100 ft/min (≈ 0,5 m/s) w strefie spawania. '
        'DGUV 109-002 / VDI 2262-4 podaje 0,3–0,5 m/s — aplikacja przyjmuje '
        'ostrzejsze 0,5. HSE HSG258 i WL3: okap zwykle do jednej średnicy od '
        'spoiny.',
    'Capture velocity: ACGIH table 3-1 and HSE HSG258 table 9 — welding '
        '0.5–1.0 m/s; ACGIH — grinding 2.5–10 m/s; OSHA 29 CFR '
        '1910.252(c)(3)(i) — 100 ft/min (≈ 0.5 m/s) in the welding zone. '
        'DGUV 109-002 / VDI 2262-4 gives 0.3–0.5 m/s — the app takes the '
        'stricter 0.5. HSE HSG258 and WL3: hood normally within one hood '
        'diameter of the weld.',
  ),
  FumeSource(
    'NDS — rozp. MRPiPS z 12.06.2018 (Dz.U. 2018 poz. 1286), załącznik '
        'w brzmieniu Dz.U. 2026 poz. 447; przepisy przejściowe Dz.U. 2020 '
        'poz. 61. Cr(VI) — dyrektywa 2004/37/WE zmieniona 2017/2398.',
    'Polish OELs — regulation of 12.06.2018 (Dz.U. 2018 item 1286), annex '
        'as of Dz.U. 2026 item 447; transitional rules Dz.U. 2020 item 61. '
        'Cr(VI) — Directive 2004/37/EC as amended by 2017/2398.',
  ),
  FumeSource(
    'ŚOI: HSE HSG53 (2013) — APF; DGUV Regel 112-190 (2021) — Schutzniveau; '
        'EN 529 — dobór; EN 149 (FFP), EN 143 (filtry P), EN 12941 (TH); HSE '
        'INDG479 — test dopasowania.',
    'RPE: HSE HSG53 (2013) — APF; DGUV Regel 112-190 (2021) — Schutzniveau; '
        'EN 529 — selection; EN 149 (FFP), EN 143 (P filters), EN 12941 (TH); '
        'HSE INDG479 — fit testing.',
  ),
  FumeSource(
    'Recyrkulacja: TRGS 528 pkt 4.5 (Cr, Ni — zasadniczo bez recyrkulacji, '
        'wyjątkowo urządzenie W3 wg EN ISO 21904-1/-2); klasy W1 95 %, W2 '
        '98 %, W3 99 % (IFA; EN ISO 15012-1 zastąpiona przez EN ISO '
        '21904-2:2020); HSE HSG258 pkt 232–233.',
    'Recirculation: TRGS 528 section 4.5 (Cr, Ni — in principle no '
        'recirculation, exceptionally a W3 unit per EN ISO 21904-1/-2); '
        'classes W1 95 %, W2 98 %, W3 99 % (IFA; EN ISO 15012-1 replaced by '
        'EN ISO 21904-2:2020); HSE HSG258 para 232–233.',
  ),
  FumeSource(
    'Osłona gazowa: ACGIH VS-90-02 — ponad 0,5–1,0 m/s przy łuku może '
        'zakłócać osłonę; HSE RR683 (2009) — porowatość od ok. 1 m/s przy '
        'najgorszych parametrach. TRGS 528: za duży przepływ w palniku '
        'wysysa gaz osłonowy.',
    'Gas shield: ACGIH VS-90-02 — over 0.5–1.0 m/s at the arc may disturb '
        'the shield; HSE RR683 (2009) — porosity from about 1 m/s with the '
        'worst settings. TRGS 528: too much on-torch extraction sucks the '
        'shielding gas away.',
  ),
  FumeSource(
    'Cr(VI): OSHA 3373, OSHA FS-3647 (2013). Tlenek cynku: NIOSH Pocket '
        'Guide.',
    'Cr(VI): OSHA 3373, OSHA FS-3647 (2013). Zinc oxide: NIOSH Pocket '
        'Guide.',
  ),
  FumeSource(
    'Progi w aplikacji: prędkość uchwycenia co najmniej 0,5 m/s (szlifowanie '
        '2,5 m/s) — można ją tylko podnieść; zasięg w dół do 1 cm, wymagana '
        'wydajność w górę; poza X ≤ 1,5·D wynik nie jest zielony; bez '
        'odciągu — nigdy zielono.',
    'Limits in the app: capture velocity at least 0.5 m/s (grinding '
        '2.5 m/s) — it can only be raised; reach rounded down to 1 cm, '
        'airflow needed rounded up; beyond X ≤ 1.5·D the result is never '
        'green; without extraction — never green.',
  ),
];
