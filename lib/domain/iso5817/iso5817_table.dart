// Odbiór wizualny spoin — dane z EN ISO 5817:2014, tablica 1.
//
// Czysty Dart (bez Fluttera). Tablica niezgodności to DANE: każda pozycja
// ma numer z tablicy 1, referencję ISO 6520-1 i reguły dla poziomów D / C / B,
// osobno dla 0,5 ≤ t ≤ 3 mm i t > 3 mm (tam, gdzie norma je rozróżnia).
// Obliczenia i ocena pomiaru: iso5817_limits.dart.
//
// ŹRÓDŁO KAŻDEJ WARTOŚCI: EN ISO 5817:2014 (identyczna z ISO 5817:2014,
// 3. wydanie), tablica 1 „Limits for imperfections”, kolumny D, C, B.
// Weryfikacja 2026-10-17:
//   • tekst BS EN ISO 5817:2014, tablica 1 (poz. 1.1–1.24 i 3.1–3.2),
//     symbole (rozdz. 4), definicje „short imperfections” (3.3, 3.4),
//     zakres (rozdz. 1: t ≥ 0,5 mm, metalurgia nieobjęta);
//   • porównanie z ISO 5817:2023 (4. wydanie, które ZASTĄPIŁO 2014) — różnice
//     dotyczące tych pozycji są opisane w polach `note2023*`;
//   • streszczenia tablicy (spawacz.waw.pl, welding.org.au, Ingenieurbüro
//     H. Schulz „Die neue DIN EN ISO 5817”) — zgodne z tekstem normy.
// Pominięte celowo: 1.5 „micro lack of fusion” (tylko badanie mikroskopowe,
// nie VT), niezgodności wewnętrzne (grupa 2 — RT/UT, nie VT), 3.3 (tylko
// zał. C — zmęczenie), 4.1 (niezgodności wielokrotne — przekrój).
//
// Symbole (EN ISO 5817:2014, rozdz. 4):
//   t — nominalna grubość ścianki / blachy; a — nominalna grubość spoiny
//   pachwinowej; s — nominalna grubość spoiny czołowej; b — szerokość nadlewu
//   (w poz. 1.11 — szerokość grani); h — wysokość / szerokość niezgodności;
//   d — średnica pora; α — kąt przejścia lica.
//
// „Short imperfections” = niezgodności krótkie (rozdz. 3.3 i 3.4): w spoinie
// ≥ 100 mm suma długości niezgodności ≤ 25 mm na odcinku 100 mm, który
// zawiera ich najwięcej; w spoinie < 100 mm — ≤ 25 % długości spoiny.

/// Poziom jakości wg EN ISO 5817. B — najostrzejszy, D — najłagodniejszy.
enum Iso5817Level { b, c, d }

extension Iso5817LevelX on Iso5817Level {
  String get letter => switch (this) {
        Iso5817Level.b => 'B',
        Iso5817Level.c => 'C',
        Iso5817Level.d => 'D',
      };

  /// 0 = najostrzejszy (B), 2 = najłagodniejszy (D).
  int get strictness => index;
}

/// Rodzaj spoiny.
enum Iso5817WeldKind { butt, fillet }

/// Wymiar, od którego zależy limit.
enum Iso5817Dim {
  /// Grubość ścianki / blachy t (przy różnych grubościach — cieńsza).
  t,

  /// Nominalna grubość spoiny czołowej s. Norma obejmuje spoiny czołowe
  /// z pełnym przetopem (rozdz. 1), dla nich s = t — tak liczymy.
  s,

  /// Szerokość lica (nadlewu) b.
  b,

  /// Szerokość grani b (poz. 1.11 — nadmierny nadlew grani).
  bRoot,

  /// Nominalna grubość spoiny pachwinowej a.
  a,
}

/// Co mierzy kontroler w danej pozycji.
enum Iso5817Measure {
  /// Wymiar w mm (h, d).
  lengthMm,

  /// Kąt w stopniach (α, poz. 1.12).
  angleDeg,

  /// Sama obecność — niezgodność albo jest, albo jej nie ma.
  presence,
}

enum Iso5817RuleKind {
  /// h ≤ stała + współczynnik · wymiar, opcjonalnie „but max.”.
  formula,

  /// „Not permitted”.
  notPermitted,

  /// „Permitted” bez limitu wymiarowego (1.21 dla D).
  unlimited,

  /// Opis słowny („acceptance depends on application” itp.).
  qualitative,

  /// α ≥ kąt (1.12).
  minAngle,
}

/// Reguła jednej komórki tablicy 1 (pozycja × poziom × zakres t).
class Iso5817Rule {
  final Iso5817RuleKind kind;

  /// Stała w mm (np. „1 mm + …”).
  final double constantMm;

  /// Współczynnik przy wymiarze [dim] (np. 0,1 w „0,1 · t”).
  final double factor;
  final Iso5817Dim? dim;

  /// „but max. X mm”.
  final double? maxMm;

  /// Kąt minimalny dla [Iso5817RuleKind.minAngle].
  final double minAngleDeg;

  /// „Short imperfections: …” — limit dotyczy tylko niezgodności krótkich.
  final bool shortOnly;

  /// Treść reguły słownej ([Iso5817RuleKind.qualitative]).
  final String textPl;
  final String textEn;

  const Iso5817Rule.formula({
    this.constantMm = 0,
    this.factor = 0,
    this.dim,
    this.maxMm,
    this.shortOnly = false,
  })  : assert(factor == 0 || dim != null),
        kind = Iso5817RuleKind.formula,
        minAngleDeg = 0,
        textPl = '',
        textEn = '';

  const Iso5817Rule.notPermitted()
      : kind = Iso5817RuleKind.notPermitted,
        constantMm = 0,
        factor = 0,
        dim = null,
        maxMm = null,
        minAngleDeg = 0,
        shortOnly = false,
        textPl = '',
        textEn = '';

  const Iso5817Rule.unlimited()
      : kind = Iso5817RuleKind.unlimited,
        constantMm = 0,
        factor = 0,
        dim = null,
        maxMm = null,
        minAngleDeg = 0,
        shortOnly = false,
        textPl = '',
        textEn = '';

  const Iso5817Rule.qualitative(this.textPl, this.textEn)
      : kind = Iso5817RuleKind.qualitative,
        constantMm = 0,
        factor = 0,
        dim = null,
        maxMm = null,
        minAngleDeg = 0,
        shortOnly = false;

  const Iso5817Rule.minAngle(this.minAngleDeg)
      : kind = Iso5817RuleKind.minAngle,
        constantMm = 0,
        factor = 0,
        dim = null,
        maxMm = null,
        shortOnly = false,
        textPl = '',
        textEn = '';
}

/// Jedna pozycja tablicy 1 (ew. jej część — np. 1.12 osobno dla spoin
/// czołowych i pachwinowych, 3.1 osobno 5071 i 5072).
class Iso5817Item {
  /// Unikalny identyfikator w aplikacji (np. „1.12-fillet”).
  final String id;

  /// Numer pozycji w tablicy 1 (np. „1.12”).
  final String no;

  /// Referencje ISO 6520-1.
  final List<int> codes;
  final String namePl;
  final String nameEn;

  /// Rodzaje spoin, których pozycja dotyczy.
  final Set<Iso5817WeldKind> kinds;
  final Iso5817Measure measure;

  /// Symbol mierzonej wielkości: h, d, α.
  final String symbol;

  /// Co zmierzyć (podpowiedź przy polu pomiaru).
  final String measurePl;
  final String measureEn;

  /// Reguły dla 0,5 ≤ t ≤ 3 mm.
  final Map<Iso5817Level, Iso5817Rule> thin;

  /// Reguły dla t > 3 mm. Gdy norma nie rozróżnia — ta sama mapa co [thin].
  final Map<Iso5817Level, Iso5817Rule> thick;

  /// Uwagi z kolumny „Remarks” tablicy 1 (skrót).
  final String remarkPl;
  final String remarkEn;

  /// Czym ISO 5817:2023 różni się w tej pozycji (pusty — bez zmian).
  final String note2023Pl;
  final String note2023En;

  const Iso5817Item({
    required this.id,
    required this.no,
    required this.codes,
    required this.namePl,
    required this.nameEn,
    required this.kinds,
    required this.measure,
    required this.thin,
    required this.thick,
    this.symbol = 'h',
    this.measurePl = '',
    this.measureEn = '',
    this.remarkPl = '',
    this.remarkEn = '',
    this.note2023Pl = '',
    this.note2023En = '',
  });

  bool appliesTo(Iso5817WeldKind kind) => kinds.contains(kind);

  /// Czy norma rozróżnia tu 0,5–3 mm i > 3 mm.
  bool get splitsThickness => !identical(thin, thick);
}

// ── Reguły wspólne ──────────────────────────────────────────────────────────

const _np = Iso5817Rule.notPermitted();

const Map<Iso5817Level, Iso5817Rule> _notPermittedAll = {
  Iso5817Level.d: _np,
  Iso5817Level.c: _np,
  Iso5817Level.b: _np,
};

// „Acceptance depends on application, e.g. material, corrosion protection”
// (EN ISO 5817:2014, tablica 1, poz. 1.23 i 1.24, wszystkie poziomy).
const _byApplication = Iso5817Rule.qualitative(
  'Akceptacja zależy od zastosowania (np. materiał, ochrona przed korozją)',
  'Acceptance depends on application (e.g. material, corrosion protection)',
);

const _butt = {Iso5817WeldKind.butt};
const _fillet = {Iso5817WeldKind.fillet};
const _both = {Iso5817WeldKind.butt, Iso5817WeldKind.fillet};

// ── Tablica ─────────────────────────────────────────────────────────────────

/// Pozycje tablicy 1 EN ISO 5817:2014 przydatne przy odbiorze wizualnym (VT),
/// w kolejności numeracji normy.
const List<Iso5817Item> kIso5817Items = [
  // 1.1 · ISO 6520-1: 100 · Crack. t ≥ 0,5: D, C, B — not permitted.
  Iso5817Item(
    id: '1.1',
    no: '1.1',
    codes: [100],
    namePl: 'Pęknięcie',
    nameEn: 'Crack',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _notPermittedAll,
    thick: _notPermittedAll,
  ),

  // 1.2 · 104 · Crater crack. t ≥ 0,5: D, C, B — not permitted.
  Iso5817Item(
    id: '1.2',
    no: '1.2',
    codes: [104],
    namePl: 'Pęknięcie w kraterze',
    nameEn: 'Crater crack',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _notPermittedAll,
    thick: _notPermittedAll,
  ),

  // 1.3 · 2017 · Surface pore — butt welds (maximum dimension of a single
  // pore). 0,5–3: D d ≤ 0,3 s; C, B not permitted.
  // > 3: D d ≤ 0,3 s, max 3 mm; C d ≤ 0,2 s, max 2 mm; B not permitted.
  Iso5817Item(
    id: '1.3-butt',
    no: '1.3',
    codes: [2017],
    namePl: 'Por powierzchniowy',
    nameEn: 'Surface pore',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    symbol: 'd',
    measurePl: 'Największy wymiar pojedynczego pora',
    measureEn: 'Maximum dimension of a single pore',
    thin: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.3, dim: Iso5817Dim.s),
      Iso5817Level.c: _np,
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.3, dim: Iso5817Dim.s, maxMm: 3),
      Iso5817Level.c:
          Iso5817Rule.formula(factor: 0.2, dim: Iso5817Dim.s, maxMm: 2),
      Iso5817Level.b: _np,
    },
    remarkPl: 's — nominalna grubość spoiny czołowej; przy pełnym przetopie '
        'przyjęto s = t.',
    remarkEn: 's — nominal butt weld thickness; for full penetration '
        's = t is used.',
    note2023Pl: 'ISO 5817:2023: dotyczy pora na licu lub w grani.',
    note2023En: 'ISO 5817:2023: applies to a pore on the weld face or root.',
  ),

  // 1.3 · 2017 · Surface pore — fillet welds.
  // 0,5–3: D d ≤ 0,3 a; C, B not permitted.
  // > 3: D d ≤ 0,3 a, max 3 mm; C d ≤ 0,2 a, max 2 mm; B not permitted.
  Iso5817Item(
    id: '1.3-fillet',
    no: '1.3',
    codes: [2017],
    namePl: 'Por powierzchniowy',
    nameEn: 'Surface pore',
    kinds: _fillet,
    measure: Iso5817Measure.lengthMm,
    symbol: 'd',
    measurePl: 'Największy wymiar pojedynczego pora',
    measureEn: 'Maximum dimension of a single pore',
    thin: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.3, dim: Iso5817Dim.a),
      Iso5817Level.c: _np,
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.3, dim: Iso5817Dim.a, maxMm: 3),
      Iso5817Level.c:
          Iso5817Rule.formula(factor: 0.2, dim: Iso5817Dim.a, maxMm: 2),
      Iso5817Level.b: _np,
    },
    note2023Pl: 'ISO 5817:2023: liczone od rzeczywistej grubości spoiny aA.',
    note2023En: 'ISO 5817:2023: based on the actual throat thickness aA.',
  ),

  // 1.4 · 2025 · End crater pipe.
  // 0,5–3: D h ≤ 0,2 t; C, B not permitted.
  // > 3: D h ≤ 0,2 t, max 2 mm; C h ≤ 0,1 t, max 1 mm; B not permitted.
  Iso5817Item(
    id: '1.4',
    no: '1.4',
    codes: [2025],
    namePl: 'Otwarta jama skurczowa w kraterze',
    nameEn: 'End crater pipe',
    kinds: _both,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Głębokość jamy kraterowej',
    measureEn: 'Depth of the crater pipe',
    thin: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.2, dim: Iso5817Dim.t),
      Iso5817Level.c: _np,
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.2, dim: Iso5817Dim.t, maxMm: 2),
      Iso5817Level.c:
          Iso5817Rule.formula(factor: 0.1, dim: Iso5817Dim.t, maxMm: 1),
      Iso5817Level.b: _np,
    },
    note2023Pl: 'ISO 5817:2023 zmieniła tę pozycję: limity liczone od s '
        '(czołowe) / aA (pachwinowe) i dodatkowo średnica d.',
    note2023En: 'ISO 5817:2023 changed this item: limits based on s (butt) / '
        'aA (fillet) plus a diameter d limit.',
  ),

  // 1.5 · 401 · Lack of fusion (incomplete fusion). t ≥ 0,5: D, C, B — not
  // permitted. („Micro lack of fusion” — tylko badanie mikroskopowe, pominięte.)
  Iso5817Item(
    id: '1.5',
    no: '1.5',
    codes: [401],
    namePl: 'Przyklejenie (brak wtopienia)',
    nameEn: 'Lack of fusion (incomplete fusion)',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _notPermittedAll,
    thick: _notPermittedAll,
  ),

  // 1.6 · 4021 · Incomplete root penetration — only for single side butt
  // welds. t ≥ 0,5: D short imperfections h ≤ 0,2 t, max 2 mm; C, B not
  // permitted.
  Iso5817Item(
    id: '1.6',
    no: '1.6',
    codes: [4021],
    namePl: 'Niepełne przetopienie grani',
    nameEn: 'Incomplete root penetration',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Wysokość braku przetopu',
    measureEn: 'Height of the unpenetrated root',
    thin: _incompleteRoot,
    thick: _incompleteRoot,
    remarkPl: 'Tylko spoiny czołowe spawane jednostronnie.',
    remarkEn: 'Single side butt welds only.',
  ),

  // 1.7 · 5011 Continuous undercut, 5012 Intermittent undercut.
  // „Smooth transition is required. This is not regarded as a systematic
  // imperfection.”
  // 0,5–3: D short h ≤ 0,2 t; C short h ≤ 0,1 t; B not permitted.
  // > 3: D h ≤ 0,2 t, max 1 mm; C h ≤ 0,1 t, max 0,5 mm;
  //      B h ≤ 0,05 t, max 0,5 mm.
  Iso5817Item(
    id: '1.7',
    no: '1.7',
    codes: [5011, 5012],
    namePl: 'Podtopienie ciągłe / przerywane',
    nameEn: 'Continuous / intermittent undercut',
    kinds: _both,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Głębokość podtopienia',
    measureEn: 'Depth of the undercut',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          factor: 0.2, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.2, dim: Iso5817Dim.t, maxMm: 1),
      Iso5817Level.c:
          Iso5817Rule.formula(factor: 0.1, dim: Iso5817Dim.t, maxMm: 0.5),
      Iso5817Level.b:
          Iso5817Rule.formula(factor: 0.05, dim: Iso5817Dim.t, maxMm: 0.5),
    },
    remarkPl: 'Wymagane łagodne przejście. Nie jest traktowane jako '
        'niezgodność systematyczna.',
    remarkEn: 'Smooth transition is required. Not regarded as a systematic '
        'imperfection.',
  ),

  // 1.8 · 5013 · Shrinkage groove. „Smooth transition is required.”
  // 0,5–3: D short h ≤ 0,2 mm + 0,1 t; C short h ≤ 0,1 t; B not permitted.
  // > 3: D short h ≤ 0,2 t, max 2 mm; C short h ≤ 0,1 t, max 1 mm;
  //      B short h ≤ 0,05 t, max 0,5 mm.
  Iso5817Item(
    id: '1.8',
    no: '1.8',
    codes: [5013],
    namePl: 'Podtopienie grani (rowek skurczowy)',
    nameEn: 'Shrinkage groove',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Głębokość rowka',
    measureEn: 'Depth of the groove',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.1, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d: Iso5817Rule.formula(
          factor: 0.2, dim: Iso5817Dim.t, maxMm: 2, shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, maxMm: 1, shortOnly: true),
      Iso5817Level.b: Iso5817Rule.formula(
          factor: 0.05, dim: Iso5817Dim.t, maxMm: 0.5, shortOnly: true),
    },
    remarkPl: 'Wymagane łagodne przejście.',
    remarkEn: 'Smooth transition is required.',
  ),

  // 1.9 · 502 · Excess weld metal (butt weld). „Smooth transition is
  // required.” t ≥ 0,5: D h ≤ 1 mm + 0,25 b, max 10 mm;
  // C h ≤ 1 mm + 0,15 b, max 7 mm; B h ≤ 1 mm + 0,1 b, max 5 mm.
  Iso5817Item(
    id: '1.9',
    no: '1.9',
    codes: [502],
    namePl: 'Nadmierny nadlew lica spoiny czołowej',
    nameEn: 'Excess weld metal (butt weld)',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Wysokość nadlewu lica nad powierzchnią materiału',
    measureEn: 'Height of the cap above the plate surface',
    thin: _excessWeldMetal,
    thick: _excessWeldMetal,
    remarkPl: 'b — szerokość lica. Wymagane łagodne przejście.',
    remarkEn: 'b — width of the weld face. Smooth transition is required.',
  ),

  // 1.10 · 503 · Excessive convexity (fillet weld). t ≥ 0,5:
  // D h ≤ 1 mm + 0,25 b, max 5 mm; C h ≤ 1 mm + 0,15 b, max 4 mm;
  // B h ≤ 1 mm + 0,1 b, max 3 mm.
  Iso5817Item(
    id: '1.10',
    no: '1.10',
    codes: [503],
    namePl: 'Nadmierna wypukłość spoiny pachwinowej',
    nameEn: 'Excessive convexity (fillet weld)',
    kinds: _fillet,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Wypukłość lica ponad linię prostą lica',
    measureEn: 'Convexity above the straight face line',
    thin: _convexity,
    thick: _convexity,
    remarkPl: 'b — szerokość lica spoiny pachwinowej.',
    remarkEn: 'b — width of the fillet weld face.',
  ),

  // 1.11 · 504 · Excess penetration.
  // 0,5–3: D h ≤ 1 mm + 0,6 b; C h ≤ 1 mm + 0,3 b; B h ≤ 1 mm + 0,1 b.
  // > 3: D h ≤ 1 mm + 1,0 b, max 5 mm; C h ≤ 1 mm + 0,6 b, max 4 mm;
  //      B h ≤ 1 mm + 0,2 b, max 3 mm.
  // ISO 5817:2023 zaostrzyła C dla t > 3: h ≤ 0,45 b + 1 mm, max 4 mm.
  Iso5817Item(
    id: '1.11',
    no: '1.11',
    codes: [504],
    namePl: 'Nadmierny przetop (wyciek grani)',
    nameEn: 'Excess penetration',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Wysokość nadlewu grani',
    measureEn: 'Height of the root bead',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 1, factor: 0.6, dim: Iso5817Dim.bRoot),
      Iso5817Level.c: Iso5817Rule.formula(
          constantMm: 1, factor: 0.3, dim: Iso5817Dim.bRoot),
      Iso5817Level.b: Iso5817Rule.formula(
          constantMm: 1, factor: 0.1, dim: Iso5817Dim.bRoot),
    },
    thick: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 1, factor: 1.0, dim: Iso5817Dim.bRoot, maxMm: 5),
      Iso5817Level.c: Iso5817Rule.formula(
          constantMm: 1, factor: 0.6, dim: Iso5817Dim.bRoot, maxMm: 4),
      Iso5817Level.b: Iso5817Rule.formula(
          constantMm: 1, factor: 0.2, dim: Iso5817Dim.bRoot, maxMm: 3),
    },
    remarkPl: 'b — szerokość grani.',
    remarkEn: 'b — width of the root bead.',
    note2023Pl: 'ISO 5817:2023: dla C przy t > 3 mm h ≤ 1 mm + 0,45·b, '
        'maks. 4 mm (ostrzej niż 2014).',
    note2023En: 'ISO 5817:2023: for C at t > 3 mm h ≤ 1 mm + 0.45·b, '
        'max. 4 mm (stricter than 2014).',
  ),

  // 1.12 · 505 · Incorrect weld toe — butt welds. t ≥ 0,5:
  // D α ≥ 90°; C α ≥ 110°; B α ≥ 150°. „α1 ≥ α and α2 ≥ α”.
  Iso5817Item(
    id: '1.12-butt',
    no: '1.12',
    codes: [505],
    namePl: 'Nieprawidłowy kąt przejścia lica',
    nameEn: 'Incorrect weld toe',
    kinds: _butt,
    measure: Iso5817Measure.angleDeg,
    symbol: 'α',
    measurePl: 'Kąt przejścia lica w materiał (mniejszy z obu brzegów)',
    measureEn: 'Weld toe angle (the smaller of both toes)',
    thin: _toeButt,
    thick: _toeButt,
    remarkPl: 'Warunek dla obu brzegów: α1 ≥ α i α2 ≥ α.',
    remarkEn: 'Both toes: α1 ≥ α and α2 ≥ α.',
    note2023Pl: 'ISO 5817:2023: nie dotyczy grani.',
    note2023En: 'ISO 5817:2023: not applicable to the root.',
  ),

  // 1.12 · 505 · Incorrect weld toe — fillet welds. t ≥ 0,5:
  // D α ≥ 90°; C α ≥ 100°; B α ≥ 110°.
  Iso5817Item(
    id: '1.12-fillet',
    no: '1.12',
    codes: [505],
    namePl: 'Nieprawidłowy kąt przejścia lica',
    nameEn: 'Incorrect weld toe',
    kinds: _fillet,
    measure: Iso5817Measure.angleDeg,
    symbol: 'α',
    measurePl: 'Kąt przejścia lica w materiał (mniejszy z obu brzegów)',
    measureEn: 'Weld toe angle (the smaller of both toes)',
    thin: _toeFillet,
    thick: _toeFillet,
    remarkPl: 'Warunek dla obu brzegów: α1 ≥ α i α2 ≥ α.',
    remarkEn: 'Both toes: α1 ≥ α and α2 ≥ α.',
  ),

  // 1.13 · 506 · Overlap. t ≥ 0,5: D h ≤ 0,2 b; C, B not permitted.
  Iso5817Item(
    id: '1.13',
    no: '1.13',
    codes: [506],
    namePl: 'Nawis',
    nameEn: 'Overlap',
    kinds: _both,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Szerokość nawisu',
    measureEn: 'Width of the overlap',
    thin: _overlap,
    thick: _overlap,
    remarkPl: 'b — szerokość lica.',
    remarkEn: 'b — width of the weld face.',
  ),

  // 1.14 · 509 Sagging, 511 Incompletely filled groove. „Smooth transition
  // is required.” 0,5–3: D short h ≤ 0,25 t; C short h ≤ 0,1 t;
  // B not permitted. > 3: D short h ≤ 0,25 t, max 2 mm;
  // C short h ≤ 0,1 t, max 1 mm; B short h ≤ 0,05 t, max 0,5 mm.
  Iso5817Item(
    id: '1.14',
    no: '1.14',
    codes: [509, 511],
    // PN-EN ISO 6520-1: 509 „zwis”; „wyciek (grani)” to potocznie 504.
    namePl: 'Zwis / niecałkowite wypełnienie rowka',
    nameEn: 'Sagging / incompletely filled groove',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Głębokość poniżej powierzchni materiału',
    measureEn: 'Depth below the plate surface',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          factor: 0.25, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d: Iso5817Rule.formula(
          factor: 0.25, dim: Iso5817Dim.t, maxMm: 2, shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, maxMm: 1, shortOnly: true),
      Iso5817Level.b: Iso5817Rule.formula(
          factor: 0.05, dim: Iso5817Dim.t, maxMm: 0.5, shortOnly: true),
    },
    remarkPl: 'Wymagane łagodne przejście.',
    remarkEn: 'Smooth transition is required.',
  ),

  // 1.15 · 510 · Burn through. t ≥ 0,5: D, C, B — not permitted.
  Iso5817Item(
    id: '1.15',
    no: '1.15',
    codes: [510],
    namePl: 'Przepalenie',
    nameEn: 'Burn through',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _notPermittedAll,
    thick: _notPermittedAll,
  ),

  // 1.16 · 512 · Excessive asymmetry of fillet weld (excessive unequal leg
  // length). „In cases where an asymmetric fillet weld has not been
  // prescribed.” t ≥ 0,5: D h ≤ 2 mm + 0,2 a; C h ≤ 2 mm + 0,15 a;
  // B h ≤ 1,5 mm + 0,15 a.
  Iso5817Item(
    id: '1.16',
    no: '1.16',
    codes: [512],
    namePl: 'Nadmierna asymetria spoiny pachwinowej',
    nameEn: 'Excessive asymmetry of fillet weld',
    kinds: _fillet,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Różnica długości ramion h = |z1 − z2|',
    measureEn: 'Leg length difference h = |z1 − z2|',
    thin: _asymmetry,
    thick: _asymmetry,
    remarkPl: 'Gdy spoina asymetryczna nie była zaprojektowana.',
    remarkEn: 'Where an asymmetric fillet weld has not been prescribed.',
    note2023Pl: 'ISO 5817:2023: liczone od rzeczywistej grubości spoiny aA.',
    note2023En: 'ISO 5817:2023: based on the actual throat thickness aA.',
  ),

  // 1.17 · 515 · Root concavity. „Smooth transition is required.”
  // 0,5–3: D h ≤ 0,2 mm + 0,1 t; C short h ≤ 0,1 t; B not permitted.
  // > 3: D short h ≤ 0,2 t, max 2 mm; C short h ≤ 0,1 t, max 1 mm;
  //      B short h ≤ 0,05 t, max 0,5 mm.
  Iso5817Item(
    id: '1.17',
    no: '1.17',
    codes: [515],
    namePl: 'Wklęśnięcie grani',
    nameEn: 'Root concavity',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Głębokość wklęśnięcia grani',
    measureEn: 'Depth of the root concavity',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.1, dim: Iso5817Dim.t),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, shortOnly: true),
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d: Iso5817Rule.formula(
          factor: 0.2, dim: Iso5817Dim.t, maxMm: 2, shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          factor: 0.1, dim: Iso5817Dim.t, maxMm: 1, shortOnly: true),
      Iso5817Level.b: Iso5817Rule.formula(
          factor: 0.05, dim: Iso5817Dim.t, maxMm: 0.5, shortOnly: true),
    },
    remarkPl: 'Wymagane łagodne przejście.',
    remarkEn: 'Smooth transition is required.',
  ),

  // 1.18 · 516 · Root porosity. t ≥ 0,5: D locally permitted; C, B not
  // permitted. (ISO 5817:2023, D: „acceptance depends on application”.)
  Iso5817Item(
    id: '1.18',
    no: '1.18',
    codes: [516],
    namePl: 'Porowatość grani',
    nameEn: 'Root porosity',
    kinds: _butt,
    measure: Iso5817Measure.presence,
    thin: _rootPorosity,
    thick: _rootPorosity,
    remarkPl: 'Gąbczasta grań, zwykle brak gazu formującego.',
    remarkEn: 'Spongy root, typically lack of gas backing.',
    note2023Pl: 'ISO 5817:2023: dla D akceptacja zależy od zastosowania.',
    note2023En: 'ISO 5817:2023: for D acceptance depends on application.',
  ),

  // 1.19 · 517 · Poor restart. t ≥ 0,5: D permitted — the limit depends on
  // the type of imperfection occurred due to restart; C, B not permitted.
  Iso5817Item(
    id: '1.19',
    no: '1.19',
    codes: [517],
    namePl: 'Wadliwe wznowienie',
    nameEn: 'Poor restart',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _poorRestart,
    thick: _poorRestart,
  ),

  // 1.20 · 5213 · Insufficient throat thickness. „Not applicable to
  // processes with proof of greater depth of penetration.”
  // 0,5–3: D short h ≤ 0,2 mm + 0,1 a; C short h ≤ 0,2 mm; B not permitted.
  // > 3: D short h ≤ 0,3 mm + 0,1 a, max 2 mm;
  //      C short h ≤ 0,3 mm + 0,1 a, max 1 mm; B not permitted.
  Iso5817Item(
    id: '1.20',
    no: '1.20',
    codes: [5213],
    namePl: 'Za mała grubość spoiny pachwinowej',
    nameEn: 'Insufficient throat thickness',
    kinds: _fillet,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Niedobór grubości: a nominalne − a zmierzone',
    measureEn: 'Shortfall: nominal a − measured a',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.1, dim: Iso5817Dim.a, shortOnly: true),
      Iso5817Level.c:
          Iso5817Rule.formula(constantMm: 0.2, shortOnly: true),
      Iso5817Level.b: _np,
    },
    thick: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 0.3,
          factor: 0.1,
          dim: Iso5817Dim.a,
          maxMm: 2,
          shortOnly: true),
      Iso5817Level.c: Iso5817Rule.formula(
          constantMm: 0.3,
          factor: 0.1,
          dim: Iso5817Dim.a,
          maxMm: 1,
          shortOnly: true),
      Iso5817Level.b: _np,
    },
    remarkPl: 'Nie dotyczy procesów z udokumentowanym głębszym wtopieniem.',
    remarkEn: 'Not applicable to processes with proof of greater depth of '
        'penetration.',
  ),

  // 1.21 · 5214 · Excessive throat thickness („the actual throat thickness
  // of the fillet weld is too large”). t ≥ 0,5: D permitted;
  // C h ≤ 1 mm + 0,2 a, max 4 mm; B h ≤ 1 mm + 0,15 a, max 3 mm.
  Iso5817Item(
    id: '1.21',
    no: '1.21',
    codes: [5214],
    namePl: 'Za duża grubość spoiny pachwinowej',
    nameEn: 'Excessive throat thickness',
    kinds: _fillet,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Nadmiar grubości: a zmierzone − a nominalne',
    measureEn: 'Excess: measured a − nominal a',
    thin: _excessThroat,
    thick: _excessThroat,
  ),

  // 1.22 · 601 · Stray arc. t ≥ 0,5: D permitted, if the properties of the
  // parent metal are not affected; C, B not permitted.
  Iso5817Item(
    id: '1.22',
    no: '1.22',
    codes: [601],
    namePl: 'Przypadkowe zajarzenie łuku',
    nameEn: 'Stray arc',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _strayArc,
    thick: _strayArc,
  ),

  // 1.23 · 602 · Spatter. t ≥ 0,5: D, C, B — acceptance depends on
  // application, e.g. material, corrosion protection.
  Iso5817Item(
    id: '1.23',
    no: '1.23',
    codes: [602],
    namePl: 'Rozprysk',
    nameEn: 'Spatter',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _byApplicationAll,
    thick: _byApplicationAll,
  ),

  // 1.24 · 610 · Temper colour (discolouration). t ≥ 0,5: D, C, B —
  // acceptance depends on application, e.g. material, corrosion protection.
  Iso5817Item(
    id: '1.24',
    no: '1.24',
    codes: [610],
    namePl: 'Barwy nalotowe (przebarwienia)',
    nameEn: 'Temper colour (discolouration)',
    kinds: _both,
    measure: Iso5817Measure.presence,
    thin: _byApplicationAll,
    thick: _byApplicationAll,
  ),

  // 3.1 · 507 / 5071 · Linear misalignment between plates — plates and
  // longitudinal welds. „t refers to the smaller thickness”; correct
  // position = centrelines coincide.
  // 0,5–3: D h ≤ 0,2 mm + 0,25 t; C h ≤ 0,2 mm + 0,15 t;
  //        B h ≤ 0,2 mm + 0,1 t.
  // > 3: D h ≤ 0,25 t, max 5 mm; C h ≤ 0,15 t, max 4 mm;
  //      B h ≤ 0,1 t, max 3 mm.
  Iso5817Item(
    id: '3.1-5071',
    no: '3.1',
    codes: [507, 5071],
    namePl: 'Przesunięcie liniowe — blachy i spoiny wzdłużne',
    nameEn: 'Linear misalignment — plates and longitudinal welds',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Przesunięcie krawędzi',
    measureEn: 'Edge offset',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.25, dim: Iso5817Dim.t),
      Iso5817Level.c: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.15, dim: Iso5817Dim.t),
      Iso5817Level.b: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.1, dim: Iso5817Dim.t),
    },
    thick: {
      Iso5817Level.d:
          Iso5817Rule.formula(factor: 0.25, dim: Iso5817Dim.t, maxMm: 5),
      Iso5817Level.c:
          Iso5817Rule.formula(factor: 0.15, dim: Iso5817Dim.t, maxMm: 4),
      Iso5817Level.b:
          Iso5817Rule.formula(factor: 0.1, dim: Iso5817Dim.t, maxMm: 3),
    },
    remarkPl: 't — grubość cieńszego elementu. Odchyłka od położenia, '
        'w którym osie się pokrywają.',
    remarkEn: 't — the smaller thickness. Deviation from the position where '
        'the centrelines coincide.',
  ),

  // 3.1 · 507 / 5072 · Linear misalignment — circumferential welds
  // (transversely circular welds at cylindrical hollow sections).
  // t ≥ 0,5: D h ≤ 0,5 t, max 4 mm; C h ≤ 0,5 t, max 3 mm;
  //          B h ≤ 0,5 t, max 2 mm.
  Iso5817Item(
    id: '3.1-5072',
    no: '3.1',
    codes: [507, 5072],
    namePl: 'Przesunięcie liniowe — spoiny obwodowe rur',
    nameEn: 'Linear misalignment — circumferential welds',
    kinds: _butt,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Przesunięcie krawędzi',
    measureEn: 'Edge offset',
    thin: _misalignmentCircumferential,
    thick: _misalignmentCircumferential,
    remarkPl: 't — grubość cieńszego elementu.',
    remarkEn: 't — the smaller thickness.',
  ),

  // 3.2 · 617 · Incorrect root gap for fillet welds. „Gaps exceeding the
  // appropriate limit may, in certain cases, be compensated for by a
  // corresponding increase in the throat thickness.”
  // 0,5–3: D h ≤ 0,5 mm + 0,1 a; C h ≤ 0,3 mm + 0,1 a; B h ≤ 0,2 mm + 0,1 a.
  // > 3: D h ≤ 1 mm + 0,3 a, max 4 mm; C h ≤ 0,5 mm + 0,2 a, max 3 mm;
  //      B h ≤ 0,5 mm + 0,1 a, max 2 mm.
  Iso5817Item(
    id: '3.2',
    no: '3.2',
    codes: [617],
    namePl: 'Nieprawidłowa szczelina w spoinie pachwinowej',
    nameEn: 'Incorrect root gap for fillet welds',
    kinds: _fillet,
    measure: Iso5817Measure.lengthMm,
    measurePl: 'Szczelina między łączonymi częściami',
    measureEn: 'Gap between the parts to be joined',
    thin: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 0.5, factor: 0.1, dim: Iso5817Dim.a),
      Iso5817Level.c: Iso5817Rule.formula(
          constantMm: 0.3, factor: 0.1, dim: Iso5817Dim.a),
      Iso5817Level.b: Iso5817Rule.formula(
          constantMm: 0.2, factor: 0.1, dim: Iso5817Dim.a),
    },
    thick: {
      Iso5817Level.d: Iso5817Rule.formula(
          constantMm: 1, factor: 0.3, dim: Iso5817Dim.a, maxMm: 4),
      Iso5817Level.c: Iso5817Rule.formula(
          constantMm: 0.5, factor: 0.2, dim: Iso5817Dim.a, maxMm: 3),
      Iso5817Level.b: Iso5817Rule.formula(
          constantMm: 0.5, factor: 0.1, dim: Iso5817Dim.a, maxMm: 2),
    },
    remarkPl: 'Większą szczelinę można czasem skompensować większą '
        'grubością spoiny.',
    remarkEn: 'A larger gap may in certain cases be compensated by a larger '
        'throat thickness.',
    note2023Pl: 'ISO 5817:2023: liczone od rzeczywistej grubości spoiny aA.',
    note2023En: 'ISO 5817:2023: based on the actual throat thickness aA.',
  ),
];

// ── Mapy reguł pozycji bez podziału grubości ────────────────────────────────

// 1.6 (4021), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _incompleteRoot = {
  Iso5817Level.d: Iso5817Rule.formula(
      factor: 0.2, dim: Iso5817Dim.t, maxMm: 2, shortOnly: true),
  Iso5817Level.c: _np,
  Iso5817Level.b: _np,
};

// 1.9 (502), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _excessWeldMetal = {
  Iso5817Level.d: Iso5817Rule.formula(
      constantMm: 1, factor: 0.25, dim: Iso5817Dim.b, maxMm: 10),
  Iso5817Level.c: Iso5817Rule.formula(
      constantMm: 1, factor: 0.15, dim: Iso5817Dim.b, maxMm: 7),
  Iso5817Level.b: Iso5817Rule.formula(
      constantMm: 1, factor: 0.1, dim: Iso5817Dim.b, maxMm: 5),
};

// 1.10 (503), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _convexity = {
  Iso5817Level.d: Iso5817Rule.formula(
      constantMm: 1, factor: 0.25, dim: Iso5817Dim.b, maxMm: 5),
  Iso5817Level.c: Iso5817Rule.formula(
      constantMm: 1, factor: 0.15, dim: Iso5817Dim.b, maxMm: 4),
  Iso5817Level.b: Iso5817Rule.formula(
      constantMm: 1, factor: 0.1, dim: Iso5817Dim.b, maxMm: 3),
};

// 1.12 (505) spoiny czołowe, t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _toeButt = {
  Iso5817Level.d: Iso5817Rule.minAngle(90),
  Iso5817Level.c: Iso5817Rule.minAngle(110),
  Iso5817Level.b: Iso5817Rule.minAngle(150),
};

// 1.12 (505) spoiny pachwinowe, t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _toeFillet = {
  Iso5817Level.d: Iso5817Rule.minAngle(90),
  Iso5817Level.c: Iso5817Rule.minAngle(100),
  Iso5817Level.b: Iso5817Rule.minAngle(110),
};

// 1.13 (506), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _overlap = {
  Iso5817Level.d: Iso5817Rule.formula(factor: 0.2, dim: Iso5817Dim.b),
  Iso5817Level.c: _np,
  Iso5817Level.b: _np,
};

// 1.16 (512), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _asymmetry = {
  Iso5817Level.d:
      Iso5817Rule.formula(constantMm: 2, factor: 0.2, dim: Iso5817Dim.a),
  Iso5817Level.c:
      Iso5817Rule.formula(constantMm: 2, factor: 0.15, dim: Iso5817Dim.a),
  Iso5817Level.b:
      Iso5817Rule.formula(constantMm: 1.5, factor: 0.15, dim: Iso5817Dim.a),
};

// 1.18 (516), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _rootPorosity = {
  Iso5817Level.d: Iso5817Rule.qualitative(
    'Dopuszczalna miejscowo',
    'Locally permitted',
  ),
  Iso5817Level.c: _np,
  Iso5817Level.b: _np,
};

// 1.19 (517), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _poorRestart = {
  Iso5817Level.d: Iso5817Rule.qualitative(
    'Dopuszczalne; limit zależy od rodzaju niezgodności powstałej przy '
        'wznowieniu',
    'Permitted; the limit depends on the type of imperfection caused by '
        'the restart',
  ),
  Iso5817Level.c: _np,
  Iso5817Level.b: _np,
};

// 1.21 (5214), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _excessThroat = {
  Iso5817Level.d: Iso5817Rule.unlimited(),
  Iso5817Level.c: Iso5817Rule.formula(
      constantMm: 1, factor: 0.2, dim: Iso5817Dim.a, maxMm: 4),
  Iso5817Level.b: Iso5817Rule.formula(
      constantMm: 1, factor: 0.15, dim: Iso5817Dim.a, maxMm: 3),
};

// 1.22 (601), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _strayArc = {
  Iso5817Level.d: Iso5817Rule.qualitative(
    'Dopuszczalne, jeśli nie zmienia własności materiału rodzimego',
    'Permitted if the properties of the parent metal are not affected',
  ),
  Iso5817Level.c: _np,
  Iso5817Level.b: _np,
};

// 1.23 (602), 1.24 (610), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _byApplicationAll = {
  Iso5817Level.d: _byApplication,
  Iso5817Level.c: _byApplication,
  Iso5817Level.b: _byApplication,
};

// 3.1 (5072), t ≥ 0,5.
const Map<Iso5817Level, Iso5817Rule> _misalignmentCircumferential = {
  Iso5817Level.d:
      Iso5817Rule.formula(factor: 0.5, dim: Iso5817Dim.t, maxMm: 4),
  Iso5817Level.c:
      Iso5817Rule.formula(factor: 0.5, dim: Iso5817Dim.t, maxMm: 3),
  Iso5817Level.b:
      Iso5817Rule.formula(factor: 0.5, dim: Iso5817Dim.t, maxMm: 2),
};

/// Pozycja po [Iso5817Item.id] (null, gdy nie ma).
Iso5817Item? iso5817ItemById(String id) {
  for (final item in kIso5817Items) {
    if (item.id == id) return item;
  }
  return null;
}

/// Pozycje dotyczące danego rodzaju spoiny, w kolejności tablicy 1.
List<Iso5817Item> iso5817ItemsFor(Iso5817WeldKind kind) =>
    [for (final item in kIso5817Items) if (item.appliesTo(kind)) item];
