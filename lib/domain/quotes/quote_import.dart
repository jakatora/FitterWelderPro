/// Import spoin do wyceny: spoiny, które monter ma już w aplikacji (mapa
/// spoin zapisanego odczytu skanera izometryku, dziennik spoin), zamieniane
/// na pozycje wyceny — zgrupowane po rodzaju złącza, wymiarze i pozycji
/// („12 × doczołowa DN100 Sch 40 (Ø114,3 × 6,02), PF / 5G").
///
/// Zasady:
///  * wymiarów NIE zgadujemy — spoina bez OD albo ścianki nie trafia do
///    żadnej grupy, tylko do [QuoteImportPlan.skipped] (powód
///    [ImportSkipReason.noSize]); wymiar, z którym pozycja wyceny byłaby
///    błędna (ścianka ≥ promień, literówka „114300"), też — z powodem
///    [ImportSkipReason.badSize];
///  * rodzaj złącza ([quoteKindForJointType]): BW → doczołowa rury,
///    SW (mufa) i FW (pachwina) → pachwina na rurze z a =
///    [socketWeldThroatMm] ścianki (ta sama reguła co w oknie pozycji),
///    BR → króciec nasadzany (OD/ścianka odgałęzienia, OD rury głównej gdy
///    znane); brak oznaczenia → doczołowa — najczęstsza spoina rurociągu,
///    pokazywana w podglądzie jako założenie;
///  * pozycja ([quotePositionForCode]): kod ISO 6947 / ASME IX z danych →
///    [WeldPosition]; brak albo kod nieznany → domyślna pozycja wyceny
///    ([defaultImportPosition]: warsztat PA, obiekt PF) — też jako założenie;
///  * warsztat / obiekt nie dzieli grup — to informacja przy grupie.
///
/// Czysty Dart (bez bazy i widżetów) — źródła podają [ImportWeld]:
/// dziennik przez [importWeldFromJournal], skan przez
/// `services/scan_quote_import.dart`.
library;

import '../../data/pipe_schedules.dart';
import '../../utils/decimal_parse.dart';
import '../weld_journal/weld_entry.dart';
import 'weld_geometry.dart';
import 'weld_quote.dart';

/// Warsztat (prefabrykacja) / obiekt (montaż) — informacja przy grupie.
enum ImportLocation { shop, field, unknown }

/// Jedna spoina ze źródła, w postaci niezależnej od źródła.
class ImportWeld {
  /// Numer spoiny ze źródła (do podglądu).
  final String ref;

  /// Kod rodzaju złącza jak w źródle (`BW`, `SW`, `BR`, `FW`) albo pusty.
  final String jointType;

  /// Średnica zewnętrzna rury (dla BR — odgałęzienia), mm; null = brak.
  final double? odMm;

  /// Ścianka rury (dla BR — odgałęzienia), mm; null = brak.
  final double? wallMm;

  /// Średnica rury głównej przy odgałęzieniu (BR), mm; null = nieznana.
  final double? headerOdMm;

  /// Kod pozycji jak w źródle (`PA`, `5G`, `H-L045`…) albo pusty.
  final String position;

  final ImportLocation location;

  const ImportWeld({
    this.ref = '',
    this.jointType = '',
    this.odMm,
    this.wallMm,
    this.headerOdMm,
    this.position = '',
    this.location = ImportLocation.unknown,
  });
}

/// Dlaczego spoina nie weszła do wyceny.
enum ImportSkipReason {
  /// Brak OD albo ścianki (dla BR: rozmiaru odgałęzienia) — nie zgadujemy.
  noSize,

  /// Wymiar jest, ale pozycja wyceny byłaby błędna (ścianka ≥ promień,
  /// wartość daleko poza zakresem — literówka?).
  badSize,
}

class ImportSkipped {
  final ImportWeld weld;
  final ImportSkipReason reason;
  const ImportSkipped(this.weld, this.reason);
}

/// Rodzaj złącza wyceny dla kodu ze źródła; `assumed` — kod pusty albo
/// nieznany, przyjęto doczołową.
({JointKind kind, bool assumed}) quoteKindForJointType(String code) =>
    switch (code.trim().toUpperCase()) {
      WeldJointType.butt => (kind: JointKind.pipeButt, assumed: false),
      WeldJointType.socket ||
      WeldJointType.fillet =>
        (kind: JointKind.pipeFillet, assumed: false),
      WeldJointType.branch => (kind: JointKind.branch, assumed: false),
      _ => (kind: JointKind.pipeButt, assumed: true),
    };

/// Pozycja wyceny dla kodu ISO 6947 / ASME IX ze źródła albo null (brak,
/// kod nieznany). Pozycje, których wycena nie ma osobno, idą do najbliższej
/// wolniejszej: PB/2F → PC, PG/PH/3G → PF, PD/4F → PE, J-L045 → H-L045.
WeldPosition? quotePositionForCode(String code) {
  final c = code.toUpperCase().replaceAll(RegExp(r'[\s_]'), '');
  return switch (c) {
    'PA' || '1G' || '1F' => WeldPosition.pa,
    'PB' || '2F' || 'PC' || '2G' => WeldPosition.pc,
    'PF' || 'PG' || 'PH' || '5G' || '5F' || '3G' || '3F' => WeldPosition.pf,
    'H-L045' || 'HL045' || 'J-L045' || 'JL045' || '6G' || '6GR' =>
      WeldPosition.hl045,
    'PE' || 'PD' || '4G' || '4F' => WeldPosition.pe,
    _ => null,
  };
}

/// Pozycja dla spoiny bez pozycji w danych — jak nowa pozycja wyceny:
/// warsztat PA (rura obracana), obiekt / trudny dostęp PF (rura stała).
WeldPosition defaultImportPosition(QuoteSite site) =>
    site == QuoteSite.shop ? WeldPosition.pa : WeldPosition.pf;

/// Kolejność szukania schedule do etykiety (wiele schedule ma tę samą
/// ściankę — 40 = STD = 40S do DN250): najpierw typowe dla materiału.
const List<String> _kCarbonLabelOrder = [
  '40', '80', '160', 'STD', 'XS', 'XXS', '10S', '5S', '40S', '80S',
];
const List<String> _kStainlessLabelOrder = [
  '10S', '40S', '80S', '5S', '40', '80', '160', 'STD', 'XS', 'XXS',
];

/// Etykieta rozmiaru jak w oknie pozycji: „DN100 Sch 40", „DN100" (OD
/// z tabeli, ścianka spoza niej) albo pusta (OD spoza tabeli).
String pipeSizeLabel(double odMm, double wallMm, {bool stainless = false}) {
  PipeRow? row;
  for (final r in kPipeWalls) {
    if ((r.od - odMm).abs() <= 0.05) {
      row = r;
      break;
    }
  }
  if (row == null) return '';
  for (final s in stainless ? _kStainlessLabelOrder : _kCarbonLabelOrder) {
    final w = row.walls[s];
    if (w != null && (w - wallMm).abs() < 0.005) return 'DN${row.dn} Sch $s';
  }
  return 'DN${row.dn}';
}

/// Grupa takich samych spoin — jedna przyszła pozycja wyceny.
class QuoteImportGroup {
  /// Klucz grupy (rodzaj, OD, ścianka, rura główna, pozycja).
  final String key;
  final JointKind kind;
  final double odMm;
  final double wallMm;

  /// Grubość a pachwiny (SW/FW), mm; 0 dla doczołowych i króćców.
  final double throatMm;

  /// Rura główna przy króćcu, mm; 0 = nieznana.
  final double headerOdMm;
  final String sizeLabel;
  final WeldPosition position;

  final int count;
  final int shopCount;
  final int fieldCount;

  /// Ile spoin grupy nie miało rodzaju w danych (przyjęto doczołową).
  final int kindAssumedCount;

  /// Ile spoin grupy nie miało (znanej) pozycji w danych.
  final int positionAssumedCount;

  /// Numery spoin ze źródła, w kolejności źródła.
  final List<String> refs;

  const QuoteImportGroup({
    required this.key,
    required this.kind,
    required this.odMm,
    required this.wallMm,
    required this.throatMm,
    required this.headerOdMm,
    required this.sizeLabel,
    required this.position,
    required this.count,
    required this.shopCount,
    required this.fieldCount,
    required this.kindAssumedCount,
    required this.positionAssumedCount,
    required this.refs,
  });

  int get unknownLocationCount => count - shopCount - fieldCount;

  /// Pozycja wyceny z tej grupy. [position] — zmiana pozycji w podglądzie.
  QuoteJoint toJoint({
    required String id,
    String label = '',
    WeldPosition? position,
  }) =>
      _joint(
        id: id,
        kind: kind,
        od: odMm,
        wall: wallMm,
        throat: throatMm,
        header: headerOdMm,
        sizeLabel: sizeLabel,
        label: label,
        count: count,
        position: position ?? this.position,
      );
}

/// Domyślny rowek jak w oknie pozycji: rura — faza 30° (α = 60°), króciec —
/// faza 45°; próg 1,5, szczelina 2,5.
QuoteJoint _joint({
  required String id,
  required JointKind kind,
  required double od,
  required double wall,
  required double throat,
  required double header,
  String sizeLabel = '',
  String label = '',
  int count = 1,
  WeldPosition position = WeldPosition.pa,
}) =>
    QuoteJoint(
      id: id,
      kind: kind,
      label: label,
      sizeLabel: sizeLabel,
      odMm: od,
      wallMm: wall,
      throatMm: throat,
      count: count,
      angleDeg: kind == JointKind.branch ? 45 : 60,
      rootFaceMm: 1.5,
      gapMm: 2.5,
      headerOdMm: header,
      position: position,
    );

/// Podgląd importu: grupy i spoiny pominięte.
class QuoteImportPlan {
  final List<QuoteImportGroup> groups;
  final List<ImportSkipped> skipped;

  const QuoteImportPlan({required this.groups, required this.skipped});

  /// Spoiny w grupach.
  int get weldCount => groups.fold(0, (a, g) => a + g.count);

  int get skippedCount => skipped.length;

  /// Wszystkie spoiny źródła.
  int get totalCount => weldCount + skippedCount;

  int skippedFor(ImportSkipReason r) =>
      skipped.where((s) => s.reason == r).length;

  bool get isEmpty => totalCount == 0;
}

double? _positive(double? v) => v != null && v.isFinite && v > 0 ? v : null;

String _k(double v) => v.toStringAsFixed(2);

class _GroupBuilder {
  final JointKind kind;
  final double od;
  final double wall;
  final double throat;
  final double header;
  final WeldPosition position;
  final String key;
  int count = 0, shop = 0, field = 0, kindAssumed = 0, positionAssumed = 0;
  final List<String> refs = [];

  _GroupBuilder(this.key, this.kind, this.od, this.wall, this.throat,
      this.header, this.position);
}

/// Grupuje spoiny [welds] w pozycje wyceny. [defaultPosition] — dla spoin
/// bez pozycji w danych ([defaultImportPosition] wyceny); [stainless] tylko
/// wybiera schedule w etykiecie rozmiaru (10S/40S zamiast 40/STD).
QuoteImportPlan planQuoteImport(
  Iterable<ImportWeld> welds, {
  required WeldPosition defaultPosition,
  bool stainless = false,
}) {
  final groups = <String, _GroupBuilder>{};
  final skipped = <ImportSkipped>[];
  for (final w in welds) {
    final (:kind, :assumed) = quoteKindForJointType(w.jointType);
    final od = _positive(w.odMm);
    final wall = _positive(w.wallMm);
    if (od == null || wall == null) {
      skipped.add(ImportSkipped(w, ImportSkipReason.noSize));
      continue;
    }
    final header =
        kind == JointKind.branch ? (_positive(w.headerOdMm) ?? 0.0) : 0.0;
    final throat = kind.isFillet ? socketWeldThroatMm(wall) : 0.0;
    // Ta sama kontrola co przy zapisie pozycji — import nie może wnieść
    // pozycji, której wycena nie policzy.
    final probe = _joint(
        id: '', kind: kind, od: od, wall: wall, throat: throat, header: header);
    if (!probe.isValid) {
      skipped.add(ImportSkipped(w, ImportSkipReason.badSize));
      continue;
    }
    final mapped = quotePositionForCode(w.position);
    final position = mapped ?? defaultPosition;
    final key = [
      kind.code,
      _k(od),
      _k(wall),
      _k(header),
      position.code,
    ].join('|');
    final g = groups[key] ??=
        _GroupBuilder(key, kind, od, wall, throat, header, position);
    g.count++;
    if (w.location == ImportLocation.shop) g.shop++;
    if (w.location == ImportLocation.field) g.field++;
    if (assumed) g.kindAssumed++;
    if (mapped == null) g.positionAssumed++;
    final ref = w.ref.trim();
    if (ref.isNotEmpty) g.refs.add(ref);
  }
  final list = groups.values.toList()
    ..sort((a, b) {
      var c = a.kind.index.compareTo(b.kind.index);
      if (c != 0) return c;
      c = a.od.compareTo(b.od);
      if (c != 0) return c;
      c = a.wall.compareTo(b.wall);
      if (c != 0) return c;
      c = a.header.compareTo(b.header);
      if (c != 0) return c;
      return a.position.index.compareTo(b.position.index);
    });
  return QuoteImportPlan(
    groups: [
      for (final g in list)
        QuoteImportGroup(
          key: g.key,
          kind: g.kind,
          odMm: g.od,
          wallMm: g.wall,
          throatMm: g.throat,
          headerOdMm: g.header,
          sizeLabel: pipeSizeLabel(g.od, g.wall, stainless: stainless),
          position: g.position,
          count: g.count,
          shopCount: g.shop,
          fieldCount: g.field,
          kindAssumedCount: g.kindAssumed,
          positionAssumedCount: g.positionAssumed,
          refs: List.unmodifiable(g.refs),
        ),
    ],
    skipped: List.unmodifiable(skipped),
  );
}

/// Najdłuższy opis pozycji (jak pole „Opis" w oknie pozycji).
const int kImportLabelMaxLength = 80;

/// Pozycje wyceny z zaznaczonych grup ([selected] — klucze), w kolejności
/// podglądu. [positions] — pozycje zmienione w podglądzie (klucz grupy →
/// pozycja); [label] — źródło („ISO 12-345 rev B", „TP-03").
List<QuoteJoint> quoteJointsFromImport(
  QuoteImportPlan plan, {
  required Set<String> selected,
  Map<String, WeldPosition> positions = const {},
  String label = '',
  required String Function() newId,
}) {
  var l = label.trim();
  if (l.length > kImportLabelMaxLength) {
    l = l.substring(0, kImportLabelMaxLength).trimRight();
  }
  return [
    for (final g in plan.groups)
      if (selected.contains(g.key))
        g.toJoint(id: newId(), label: l, position: positions[g.key]),
  ];
}

// ─── Dziennik spoin ─────────────────────────────────────────────────────────

/// Wymiar wpisany w dzienniku: liczba (przecinek albo kropka), dopuszczalne
/// „Ø" z przodu i „mm" na końcu. Wszystko inne (np. „DN100" — DN nie jest
/// średnicą, a DN100 rury higienicznej to Ø104, nie Ø114,3) = brak.
double? parseJournalDimensionMm(String raw) {
  var t = raw.trim().toLowerCase();
  t = t.replaceFirst(RegExp(r'^(ø|⌀|φ|fi)\s*'), '');
  t = t.replaceFirst(RegExp(r'\s*mm$'), '');
  return _positive(parseDecimal(t));
}

/// Spoina dziennika jako [ImportWeld]. Dziennik ma jedno OD — dla BR to OD
/// odgałęzienia; rura główna nieznana (do uzupełnienia w pozycji).
ImportWeld importWeldFromJournal(WeldEntry e) => ImportWeld(
      ref: e.weldNo,
      jointType: e.jointType,
      odMm: parseJournalDimensionMm(e.od),
      wallMm: parseJournalDimensionMm(e.t),
      position: e.position,
      location: switch (e.shopField.trim().toUpperCase()) {
        WeldLocation.shop => ImportLocation.shop,
        WeldLocation.field => ImportLocation.field,
        _ => ImportLocation.unknown,
      },
    );

/// Spoina jeszcze niewykonana: bez daty spawania i bez stempla spawacza
/// (np. wpis zaplanowany z mapy spoin skanu).
bool isJournalWeldOpen(WeldEntry e) =>
    e.date.trim().isEmpty && e.stamps.isEmpty;

/// Zakres dziennika do importu.
class JournalImportFilter {
  /// Projekt (nazwa jak w dzienniku, przycięta; '' = wpisy bez projektu);
  /// null = wszystkie.
  final String? project;

  /// Pakiet testowy ('' = bez pakietu); null = wszystkie.
  final String? testPackage;

  /// Tylko spoiny niewykonane ([isJournalWeldOpen]).
  final bool onlyOpen;

  const JournalImportFilter({
    this.project,
    this.testPackage,
    this.onlyOpen = false,
  });
}

/// Nieusunięte wpisy dziennika w zakresie [f], w kolejności dziennika.
List<WeldEntry> journalEntriesForImport(
        Iterable<WeldEntry> entries, JournalImportFilter f) =>
    [
      for (final e in entries)
        if (!e.isDeleted &&
            (f.project == null || e.projectName.trim() == f.project) &&
            (f.testPackage == null || e.testPackage.trim() == f.testPackage) &&
            (!f.onlyOpen || isJournalWeldOpen(e)))
          e,
    ];

List<String> _distinctSorted(Iterable<String> values) {
  final set = values.toSet();
  final named = set.where((v) => v.isNotEmpty).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [...named, if (set.contains('')) ''];
}

/// Projekty nieusuniętych wpisów ('' — wpisy bez projektu — na końcu).
List<String> journalImportProjects(Iterable<WeldEntry> entries) =>
    _distinctSorted([
      for (final e in entries)
        if (!e.isDeleted) e.projectName.trim(),
    ]);

/// Pakiety testowe nieusuniętych wpisów projektu [project] (null = każdego);
/// '' — wpisy bez pakietu — na końcu.
List<String> journalImportPackages(Iterable<WeldEntry> entries,
        {String? project}) =>
    _distinctSorted([
      for (final e in entries)
        if (!e.isDeleted && (project == null || e.projectName.trim() == project))
          e.testPackage.trim(),
    ]);

/// Etykieta pozycji z dziennika: pakiet („TP-03"), inaczej projekt; pusta,
/// gdy żadnego nie ma.
String journalImportLabel(JournalImportFilter f) {
  final pkg = f.testPackage?.trim() ?? '';
  if (pkg.isNotEmpty) return pkg;
  return f.project?.trim() ?? '';
}
