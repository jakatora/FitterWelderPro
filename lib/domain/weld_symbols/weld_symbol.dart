// Model symbolu spoiny wg EN ISO 2553:2019 — to, co kreator w aplikacji
// pozwala złożyć, i to, gdzie każdy element ląduje na linii odniesienia.
//
// Czysty Dart (bez Fluttera): rysuje to `features/weld_symbols`, opis po
// ludzku buduje `weld_symbol_description.dart`.
//
// Układ linii odniesienia (EN ISO 2553:2019):
//
//   System A — linia ciągła + równoległa linia przerywana (identyfikacyjna).
//     Symbol na linii CIĄGŁEJ = spoina po stronie strzałki,
//     symbol na linii PRZERYWANEJ = spoina po stronie przeciwnej.
//     Spoiny symetryczne (po obu stronach) — linii przerywanej się nie rysuje.
//   System B — tylko linia ciągła (jak AWS A2.4).
//     Symbol POD linią = strona strzałki, NAD linią = strona przeciwna.
//
// W aplikacji linia przerywana w systemie A leży zawsze POD linią ciągłą,
// jak na rysunkach EN ISO 2553:2013/2019 (starsze wydania dopuszczały obie
// strony; o stronie spoiny decyduje linia, na której stoi symbol). Symbol po
// stronie przeciwnej wisi pod linią przerywaną — po jej stronie odległej od
// linii ciągłej.

/// Symbol podstawowy (rodzaj spoiny).
enum WeldKind {
  /// Spoina pachwinowa — trójkąt.
  fillet,

  /// Spoina czołowa na I (bez ukosowania brzegów) — dwie pionowe kreski.
  squareButt,

  /// Spoina czołowa na V.
  singleV,

  /// Spoina czołowa na ½V (jeden brzeg ukosowany).
  singleBevel,

  /// Spoina czołowa na Y (V z grubym progiem / niezukosowaną częścią).
  singleVRootFace,

  /// Spoina czołowa na ½Y.
  singleBevelRootFace,

  /// Spoina czołowa na U.
  singleU,

  /// Spoina czołowa na ½U (J).
  singleJ,

  /// Ścieg od strony grani (back run / backing weld). W EN ISO 2553:2019
  /// to symbol UZUPEŁNIAJĄCY (półkole po przeciwnej stronie linii niż symbol
  /// spoiny głównej), nie podstawowy — w aplikacji tylko w ściądze.
  backingRun,

  /// Spoina otworowa (w otworze okrągłym lub podłużnym).
  plug,

  /// Spoina punktowa.
  spot,

  /// Spoina liniowa (ciągła seria punktów).
  seam,

  /// Napawanie.
  surfacing,

  /// Spoina brzeżna (EN ISO 2553:2019: prostokąt przedzielony kreską).
  edge;

  /// Spoina czołowa z rowkiem (I, V, ½V, Y, ½Y, U, J) — wymiar to s.
  bool get isGrooveButt => switch (this) {
        squareButt ||
        singleV ||
        singleBevel ||
        singleVRootFace ||
        singleBevelRootFace ||
        singleU ||
        singleJ =>
          true,
        _ => false,
      };

  /// Rodzaje, które da się złożyć w kreatorze. Pozostałe są tylko w ściądze
  /// (inne wymiary: średnica, szerokość, rozstaw — poza zakresem kreatora).
  bool get inBuilder => this == fillet || isGrooveButt;

  /// Kolejność w kreatorze.
  static const List<WeldKind> builderKinds = [
    fillet,
    squareButt,
    singleV,
    singleBevel,
    singleVRootFace,
    singleBevelRootFace,
    singleU,
    singleJ,
  ];
}

/// Strona złącza, po której ma być spoina.
enum WeldSide {
  /// Po stronie strzałki — ta strona złącza, którą wskazuje grot strzałki.
  arrow,

  /// Po stronie przeciwnej.
  other,

  /// Po obu stronach (symetrycznie: ten sam symbol i wymiary).
  both,
}

/// Sposób rysowania linii odniesienia wg EN ISO 2553.
enum SymbolSystem {
  /// Linia ciągła + przerywana (tradycja ISO / EN).
  a,

  /// Tylko linia ciągła; pod linią = strona strzałki (jak AWS A2.4).
  b,
}

/// Wymiar przekroju spoiny pachwinowej.
enum FilletSize {
  /// Grubość obliczeniowa a.
  throat,

  /// Długość boku z.
  leg,
}

/// Kształt lica (symbol uzupełniający).
enum WeldContour { none, flat, convex, concave }

/// Podkładka pod grań (symbol uzupełniający w prostokącie).
enum BackingStrip {
  none,

  /// M — podkładka trwała (zostaje w złączu).
  permanent,

  /// MR — podkładka usuwalna (zdejmowana po spawaniu).
  removable,
}

/// Na której linii stoi symbol.
enum RefLine { continuous, dashed }

/// Po której stronie tej linii (na rysunku: nad / pod).
enum RefPosition { above, below }

/// Miejsce jednego symbolu na linii odniesienia.
class SymbolPlacement {
  const SymbolPlacement(this.line, this.position, this.side);

  final RefLine line;
  final RefPosition position;

  /// Którą stronę złącza oznacza ten symbol (strzałki albo przeciwną).
  final WeldSide side;

  @override
  bool operator ==(Object other) =>
      other is SymbolPlacement &&
      other.line == line &&
      other.position == position &&
      other.side == side;

  @override
  int get hashCode => Object.hash(line, position, side);

  @override
  String toString() => 'SymbolPlacement($line, $position, $side)';
}

/// Układ linii odniesienia dla danej strony i systemu.
class ReferenceLayout {
  const ReferenceLayout({required this.dashedLine, required this.placements});

  /// Czy rysować linię przerywaną (tylko system A, spoina jednostronna).
  final bool dashedLine;

  /// Symbole do narysowania (jeden albo dwa przy spoinie dwustronnej).
  final List<SymbolPlacement> placements;
}

/// Gdzie stoją symbole dla strony [side] w systemie [system].
///
/// System A: linia przerywana pod linią ciągłą. Strona strzałki — symbol nad
/// linią ciągłą; strona przeciwna — symbol pod linią przerywaną (po jej
/// zewnętrznej stronie); obie strony — symbol nad i pod linią ciągłą, bez
/// linii przerywanej.
///
/// System B: strona strzałki — pod linią, przeciwna — nad linią.
ReferenceLayout referenceLayout(SymbolSystem system, WeldSide side) {
  switch (system) {
    case SymbolSystem.a:
      return switch (side) {
        WeldSide.arrow => const ReferenceLayout(dashedLine: true, placements: [
            SymbolPlacement(
                RefLine.continuous, RefPosition.above, WeldSide.arrow),
          ]),
        WeldSide.other => const ReferenceLayout(dashedLine: true, placements: [
            SymbolPlacement(RefLine.dashed, RefPosition.below, WeldSide.other),
          ]),
        WeldSide.both => const ReferenceLayout(dashedLine: false, placements: [
            SymbolPlacement(
                RefLine.continuous, RefPosition.above, WeldSide.arrow),
            SymbolPlacement(
                RefLine.continuous, RefPosition.below, WeldSide.other),
          ]),
      };
    case SymbolSystem.b:
      return switch (side) {
        WeldSide.arrow => const ReferenceLayout(dashedLine: false, placements: [
            SymbolPlacement(
                RefLine.continuous, RefPosition.below, WeldSide.arrow),
          ]),
        WeldSide.other => const ReferenceLayout(dashedLine: false, placements: [
            SymbolPlacement(
                RefLine.continuous, RefPosition.above, WeldSide.other),
          ]),
        WeldSide.both => const ReferenceLayout(dashedLine: false, placements: [
            SymbolPlacement(
                RefLine.continuous, RefPosition.below, WeldSide.arrow),
            SymbolPlacement(
                RefLine.continuous, RefPosition.above, WeldSide.other),
          ]),
      };
  }
}

/// Wszystko, co kreator wie o jednym symbolu spoiny.
///
/// Wymiary są `null`, gdy pole jest puste — wtedy w opisie i na rysunku ich
/// nie ma (nie zgadujemy).
class WeldSymbolSpec {
  const WeldSymbolSpec({
    this.kind = WeldKind.fillet,
    this.side = WeldSide.arrow,
    this.system = SymbolSystem.a,
    this.filletSize = FilletSize.throat,
    this.size,
    this.length,
    this.intermittent = false,
    this.count,
    this.elementLength,
    this.gap,
    this.staggered = false,
    this.allAround = false,
    this.fieldWeld = false,
    this.contour = WeldContour.none,
    this.backing = BackingStrip.none,
    this.process = '',
    this.reference = '',
  });

  final WeldKind kind;
  final WeldSide side;
  final SymbolSystem system;

  /// Pachwina: a czy z. Dla spoin czołowych bez znaczenia (wymiar to s).
  final FilletSize filletSize;

  /// a / z (pachwina) albo głębokość wtopienia (czołowa) [mm]. Przy spoinie
  /// czołowej `null` = pełny przetop (EN ISO 2553:2019, tabl. 1, przypis b).
  final double? size;

  /// Długość spoiny ciągłej [mm]; `null` = bez wymiaru długości.
  final double? length;

  /// Spoina przerywana n × l (e). n może nie być podane — wtedy układ
  /// l (e) biegnie przez całą długość złącza.
  final bool intermittent;
  final int? count;
  final double? elementLength;
  final double? gap;

  /// Przerywana dwustronna pachwina z odcinkami przestawionymi.
  final bool staggered;

  final bool allAround;
  final bool fieldWeld;
  final WeldContour contour;
  final BackingStrip backing;

  /// Numer procesu wg EN ISO 4063 w ogonie, np. „111”.
  final String process;

  /// Inne odwołanie w ogonie, np. „WPS-01”.
  final String reference;

  /// Przestawienie ma sens tylko dla przerywanej pachwiny po obu stronach.
  bool get staggerApplies =>
      kind == WeldKind.fillet && side == WeldSide.both && intermittent;

  /// Podkładka dotyczy spoin czołowych wykonywanych z jednej strony.
  bool get backingApplies => kind.isGrooveButt && side != WeldSide.both;

  /// Litera przed wymiarem przekroju: a albo z przy pachwinie. Przy spoinie
  /// czołowej sama liczba (np. „8” przed V) — w EN ISO 2553:2013/2019 „s”
  /// to tylko oznaczenie wymiaru, nie pisze się go na rysunku (zapis „s8”
  /// pochodzi z wydania 1992).
  String get sizePrefix => kind == WeldKind.fillet
      ? (filletSize == FilletSize.throat ? 'a' : 'z')
      : '';

  /// Ukosowany tylko jeden brzeg — strzałka (łamana) wskazuje element do
  /// ukosowania (½V, ½Y, J).
  bool get oneMemberPrepared =>
      kind == WeldKind.singleBevel ||
      kind == WeldKind.singleBevelRootFace ||
      kind == WeldKind.singleJ;

  /// l i e dodatnie (n opcjonalne, ale jeśli jest — dodatnie) — dopiero
  /// wtedy przerywana ma zapis.
  bool get intermittentComplete =>
      intermittent &&
      (count == null || count! > 0) &&
      (elementLength ?? 0) > 0 &&
      (gap ?? 0) > 0;

  ReferenceLayout get layout => referenceLayout(system, side);

  WeldSymbolSpec copyWith({
    WeldKind? kind,
    WeldSide? side,
    SymbolSystem? system,
    FilletSize? filletSize,
    double? Function()? size,
    double? Function()? length,
    bool? intermittent,
    int? Function()? count,
    double? Function()? elementLength,
    double? Function()? gap,
    bool? staggered,
    bool? allAround,
    bool? fieldWeld,
    WeldContour? contour,
    BackingStrip? backing,
    String? process,
    String? reference,
  }) =>
      WeldSymbolSpec(
        kind: kind ?? this.kind,
        side: side ?? this.side,
        system: system ?? this.system,
        filletSize: filletSize ?? this.filletSize,
        size: size != null ? size() : this.size,
        length: length != null ? length() : this.length,
        intermittent: intermittent ?? this.intermittent,
        count: count != null ? count() : this.count,
        elementLength:
            elementLength != null ? elementLength() : this.elementLength,
        gap: gap != null ? gap() : this.gap,
        staggered: staggered ?? this.staggered,
        allAround: allAround ?? this.allAround,
        fieldWeld: fieldWeld ?? this.fieldWeld,
        contour: contour ?? this.contour,
        backing: backing ?? this.backing,
        process: process ?? this.process,
        reference: reference ?? this.reference,
      );
}
