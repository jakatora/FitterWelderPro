// Ograniczenia zakresu z próby EN ISO 9606-1, zapisane w uwagach
// certyfikatu jedną linią CZYTELNĄ DLA PROGRAMU — bez zmiany schematu bazy.
// Pisze ją „Zakres uprawnień z próbki” (iso9606_range.dart), czyta kontrola
// spoiny (lib/domain/wps/weld_range_check.dart).
//
// __FORMAT (wersja 1)__ — jedna linia w uwagach:
//
//   [ISO9606 v1] root=nb,mb,bs,gb,fb; dip=0; plates=0; fm=FM1,FM2;
//                nofiller=1.1; proc2=111; branch=60; layers=sl; dir=lw
//
// (w uwagach to JEDNA linia; tu złamana dla czytelności).
//  • znacznik `[ISO9606 vN]` na początku linii (wielkość liter i spacje
//    wokół bez znaczenia); N — wersja formatu;
//  • pary `klucz=wartość` rozdzielone `;`, listy wartości po przecinku;
//    kolejność i puste odcinki bez znaczenia;
//  • klucz nieobecny = brak ograniczenia z tej strony.
//
// Klucze v1 (zbiory = co jest DOZWOLONE):
//  root     — prowadzenie grani BW (tab. 11): nb, mb, bs, gb, ci, fb;
//  dip      — przenoszenie zwarciowe 131/135/138 (§5.2): 1 tak, 0 nie;
//  plates   — blachy (§5.3): 1 tak, 0 nie (rury opisuje zakres D);
//  fm       — grupy spoiw (tab. 3): FM1…FM6;
//  nofiller — spawanie bez spoiwa tylko na tej grupie ISO/TR 15608 (§5.6);
//  proc2    — proces(y) wypełnienia złącza dwuprocesowego — tylko z granią
//             procesem z pola „Proces(y)” (tab. 1); poza procesami rejestru;
//  branch   — odgałęzienia (§5.4 c): 0 nie, 60 tylko ≥ 60°;
//  layers   — technika spoin pachwinowych (tab. 12): sl, ml;
//  dir      — kierunek spawania 311 (§5.9): lw albo rw.
//
// __ODPORNOŚĆ NA RĘCZNĄ EDYCJĘ__
//  • brak linii → brak ograniczeń (certyfikat wpisany ręcznie);
//  • nieznany klucz → pomijany (nowsze wersje mogą dopisywać klucze);
//  • zła wartość znanego klucza, powtórzony klucz, kilka linii ze
//    znacznikiem albo nowsza wersja → linia USZKODZONA: kontrola mówi
//    „nie da się porównać”, nigdy nie zgaduje.
//
// Czysty Dart, bez Fluttera.

/// Prowadzenie grani spoiny czołowej (ISO 9606-1 tab. 11, §4.3.3).
enum RootCondition {
  /// Jednostronnie bez podkładki (ss nb).
  nb,

  /// Jednostronnie na podkładce (ss mb).
  mb,

  /// Dwustronnie (bs).
  bs,

  /// Gaz formujący (ss gb).
  gb,

  /// Wkładka topliwa (ci).
  ci,

  /// Podkładka topnikowa (ss fb).
  fb;

  /// Kod w linii (`nb`).
  String get code => name;

  /// Oznaczenie jak na certyfikacie (`ss nb`, `bs`, `ci`).
  String get label => switch (this) {
        RootCondition.bs || RootCondition.ci => name,
        _ => 'ss $name',
      };

  /// `nb`, `ss nb`, `SS-NB` → [nb]; nieznane → `null`.
  static RootCondition? parse(String raw) {
    final t = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), ' ')
        .replaceFirst(RegExp(r'^ss '), '');
    for (final r in RootCondition.values) {
      if (r.name == t) return r;
    }
    return null;
  }
}

/// Wyrób spoiny / próby (§5.3): blacha P albo rura T.
enum WeldProductForm {
  plate('P'),
  pipe('T');

  const WeldProductForm(this.code);
  final String code;
}

/// Wersja formatu, którą ten kod zapisuje i rozumie.
const int kIso9606LimitsVersion = 1;

/// Znacznik linii w bieżącej wersji.
const String kIso9606LimitsTag = '[ISO9606 v$kIso9606LimitsVersion]';

final RegExp _kTagLine =
    RegExp(r'^\[\s*ISO\s*9606\s+v(\d+)\s*\](.*)$', caseSensitive: false);
/// Początek linii ze znacznikiem — także uszkodzonym („[ISO9606]”, „[iso
/// 9606 v1”), ale nie zwykła notatka „[ISO 9606-1 …]”.
final RegExp _kTagStart =
    RegExp(r'^\[\s*ISO\s*9606(?![-\d])', caseSensitive: false);
final RegExp _kPair = RegExp(r'^([A-Za-z0-9_]+)\s*=\s*(.*)$');
final RegExp _kFm = RegExp(r'^FM\s*([1-6])$', caseSensitive: false);
final RegExp _kGroup = RegExp(r'^\d{1,2}(\.\d{1,2})?$');
final RegExp _kProcess = RegExp(r'^\d{2,3}$');

/// Ograniczenia z próby. `null` w polu = brak ograniczenia z tej strony.
class Iso9606Limits {
  /// Dozwolone prowadzenie grani (BW).
  final Set<RootCondition>? root;

  /// `false` — przenoszenie zwarciowe NIE objęte; `true` — objęte.
  final bool? dip;

  /// `false` — blachy NIE objęte; `true` — objęte.
  final bool? plates;

  /// Dozwolone grupy spoiw („FM1”…).
  final Set<String>? fm;

  /// Spawanie bez spoiwa tylko na tej grupie ISO/TR 15608.
  final String? noFillerGroup;

  /// Procesy wypełnienia złącza dwuprocesowego (tylko z granią procesem 1).
  final List<String> proc2;

  /// 0 — bez odgałęzień, 60 — odgałęzienia tylko pod kątem ≥ 60°.
  final int? branch;

  /// Dozwolona technika spoin pachwinowych: `sl`, `ml`.
  final Set<String>? layers;

  /// Kierunek spawania 311: `lw` / `rw`.
  final String? direction;

  const Iso9606Limits({
    this.root,
    this.dip,
    this.plates,
    this.fm,
    this.noFillerGroup,
    this.proc2 = const <String>[],
    this.branch,
    this.layers,
    this.direction,
  });

  /// Linia do uwag certyfikatu (stała kolejność kluczy).
  String encode() {
    final parts = <String>[
      if (root != null)
        'root=${[
          for (final r in RootCondition.values)
            if (root!.contains(r)) r.code,
        ].join(',')}',
      if (dip != null) 'dip=${dip! ? 1 : 0}',
      if (plates != null) 'plates=${plates! ? 1 : 0}',
      if (fm != null) 'fm=${(fm!.toList()..sort()).join(',')}',
      if (noFillerGroup != null) 'nofiller=$noFillerGroup',
      if (proc2.isNotEmpty) 'proc2=${proc2.join(',')}',
      if (branch != null) 'branch=$branch',
      if (layers != null)
        'layers=${[
          for (final l in const ['sl', 'ml'])
            if (layers!.contains(l)) l,
        ].join(',')}',
      if (direction != null) 'dir=$direction',
    ];
    return '$kIso9606LimitsTag ${parts.join('; ')}'.trim();
  }
}

/// Stan odczytu linii z uwag.
enum Iso9606LimitsStatus {
  /// Brak linii — certyfikat bez ograniczeń z próby.
  absent,

  /// Linia odczytana.
  ok,

  /// Linia uszkodzona (zła wartość, powtórzony klucz, kilka linii) albo
  /// z nowszej wersji — nie da się porównać.
  damaged,
}

/// Wynik [parseIso9606Limits].
class Iso9606LimitsParse {
  final Iso9606LimitsStatus status;
  final Iso9606Limits? limits;

  /// Dlaczego uszkodzona (do testów i diagnostyki).
  final String? problem;

  const Iso9606LimitsParse._(this.status, this.limits, this.problem);

  static const Iso9606LimitsParse absent =
      Iso9606LimitsParse._(Iso9606LimitsStatus.absent, null, null);

  factory Iso9606LimitsParse._damaged(String problem) =>
      Iso9606LimitsParse._(Iso9606LimitsStatus.damaged, null, problem);
}

List<String> _items(String value) => value
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Odczytuje linię `[ISO9606 vN] …` z [notes]. Patrz komentarz pliku.
Iso9606LimitsParse parseIso9606Limits(String? notes) {
  if (notes == null || notes.isEmpty) return Iso9606LimitsParse.absent;
  final lines = notes
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where(_kTagStart.hasMatch)
      .toList();
  if (lines.isEmpty) return Iso9606LimitsParse.absent;
  if (lines.length > 1) {
    return Iso9606LimitsParse._damaged('kilka linii [ISO9606]');
  }
  final m = _kTagLine.firstMatch(lines.single);
  if (m == null) return Iso9606LimitsParse._damaged('zły znacznik');
  final version = int.tryParse(m.group(1)!);
  if (version != kIso9606LimitsVersion) {
    return Iso9606LimitsParse._damaged('wersja v${m.group(1)}');
  }

  Set<RootCondition>? root;
  bool? dip;
  bool? plates;
  Set<String>? fm;
  String? noFiller;
  var proc2 = const <String>[];
  int? branch;
  Set<String>? layers;
  String? direction;
  final seen = <String>{};

  bool? flag(String v) => switch (v.trim()) { '1' => true, '0' => false, _ => null };

  for (final raw in m.group(2)!.split(';')) {
    final segment = raw.trim();
    if (segment.isEmpty) continue;
    final pair = _kPair.firstMatch(segment);
    if (pair == null) return Iso9606LimitsParse._damaged('„$segment”');
    final key = pair.group(1)!.toLowerCase();
    final value = pair.group(2)!.trim();
    const known = {
      'root', 'dip', 'plates', 'fm', 'nofiller', 'proc2', 'branch', //
      'layers', 'dir',
    };
    if (!known.contains(key)) continue; // nieznany klucz — pomijamy
    if (!seen.add(key)) return Iso9606LimitsParse._damaged('powtórzony $key');
    switch (key) {
      case 'root':
        final items = _items(value).map(RootCondition.parse).toList();
        if (items.isEmpty || items.contains(null)) {
          return Iso9606LimitsParse._damaged('root=$value');
        }
        root = items.cast<RootCondition>().toSet();
      case 'dip':
        dip = flag(value);
        if (dip == null) return Iso9606LimitsParse._damaged('dip=$value');
      case 'plates':
        plates = flag(value);
        if (plates == null) {
          return Iso9606LimitsParse._damaged('plates=$value');
        }
      case 'fm':
        final items = _items(value);
        final out = <String>{};
        for (final i in items) {
          final g = _kFm.firstMatch(i);
          if (g == null) return Iso9606LimitsParse._damaged('fm=$value');
          out.add('FM${g.group(1)}');
        }
        if (out.isEmpty) return Iso9606LimitsParse._damaged('fm=$value');
        fm = out;
      case 'nofiller':
        if (!_kGroup.hasMatch(value)) {
          return Iso9606LimitsParse._damaged('nofiller=$value');
        }
        noFiller = value;
      case 'proc2':
        final items = _items(value);
        if (items.isEmpty || !items.every(_kProcess.hasMatch)) {
          return Iso9606LimitsParse._damaged('proc2=$value');
        }
        proc2 = items;
      case 'branch':
        branch = switch (value) { '0' => 0, '60' => 60, _ => null };
        if (branch == null) return Iso9606LimitsParse._damaged('branch=$value');
      case 'layers':
        final items = _items(value).map((s) => s.toLowerCase()).toSet();
        if (items.isEmpty || !items.every({'sl', 'ml'}.contains)) {
          return Iso9606LimitsParse._damaged('layers=$value');
        }
        layers = items;
      case 'dir':
        final d = value.toLowerCase();
        if (d != 'lw' && d != 'rw') {
          return Iso9606LimitsParse._damaged('dir=$value');
        }
        direction = d;
    }
  }
  return Iso9606LimitsParse._(
    Iso9606LimitsStatus.ok,
    Iso9606Limits(
      root: root,
      dip: dip,
      plates: plates,
      fm: fm,
      noFillerGroup: noFiller,
      proc2: proc2,
      branch: branch,
      layers: layers,
      direction: direction,
    ),
    null,
  );
}
