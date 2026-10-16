// Treści ściągi symboli spawalniczych (PL / EN) — czysty Dart.
//
// Źródła: EN ISO 2553:2019 (tabl. 1 — symbole podstawowe; wymiary, systemy
// A i B), EN ISO 2553:2013 dla symboli uzupełniających (tabl. 3 wydania 2019
// nie była dostępna w podglądzie, zmiany 2013 → 2019 są głównie redakcyjne),
// AWS A2.4 dla porównania. Nazwy polskie wg materiałów dydaktycznych do
// PN-EN ISO 2553. Czego nie dało się potwierdzić w źródłach, tego tu nie ma
// (np. symbol łagodnego przejścia lica).
//
// Ścieg od strony grani (back run / backing weld) jest w EN ISO 2553:2019
// symbolem UZUPEŁNIAJĄCYM — opisuje go zakładka symboli uzupełniających.

import 'weld_symbol.dart';

/// Wpis ściągi dla symbolu podstawowego.
class BasicSymbolInfo {
  const BasicSymbolInfo({
    required this.kind,
    required this.bodyPl,
    required this.bodyEn,
    required this.awsPl,
    required this.awsEn,
  });

  final WeldKind kind;

  /// Jak wygląda symbol i kiedy się go spotyka.
  final String bodyPl;
  final String bodyEn;

  /// Odpowiednik w AWS A2.4.
  final String awsPl;
  final String awsEn;
}

const List<BasicSymbolInfo> basicSymbolCatalog = [
  BasicSymbolInfo(
    kind: WeldKind.fillet,
    bodyPl: 'Trójkąt prostokątny, pionowy bok zawsze po lewej. Złącza '
        'teowe, narożne i zakładkowe. Przed symbolem a (grubość obliczeniowa) '
        'albo z (długość boku), np. a5 lub z7.',
    bodyEn: 'Right triangle, vertical leg always on the left. T-, corner and '
        'lap joints. Before the symbol: a (throat thickness) or z (leg '
        'length), e.g. a5 or z7.',
    awsPl: 'AWS: ten sam trójkąt; liczba przed symbolem to długość boku '
        '(bez litery).',
    awsEn: 'AWS: same triangle; the number before it is the leg size (no '
        'letter).',
  ),
  BasicSymbolInfo(
    kind: WeldKind.squareButt,
    bodyPl: 'Dwie równoległe kreski. Spoina czołowa bez ukosowania brzegów '
        '— zwykle cienkie blachy.',
    bodyEn: 'Two parallel lines. Butt weld without edge preparation (square '
        'edges) — usually thin plate.',
    awsPl: 'AWS: square-groove weld, ten sam znak.',
    awsEn: 'AWS: square-groove weld, same sign.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.singleV,
    bodyPl: 'Litera V. Oba brzegi ukosowane. Ten sam symbol po obu stronach '
        'linii = spoina dwustronna na X.',
    bodyEn: 'Letter V. Both edges bevelled. The same symbol on both sides of '
        'the line = double-V (X) weld.',
    awsPl: 'AWS: V-groove weld.',
    awsEn: 'AWS: V-groove weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.singleBevel,
    bodyPl: 'Kreska pionowa i ukośna. Ukosowany tylko jeden brzeg; pionowa '
        'kreska zawsze po lewej. Strzałka (łamana) wskazuje element do '
        'ukosowania. Po obu stronach linii = spoina na K.',
    bodyEn: 'A vertical and a sloping line. Only one edge is bevelled; the '
        'vertical line is always on the left. The arrow (with a break) '
        'points to the member to be bevelled. On both sides = double-bevel '
        '(K) weld.',
    awsPl: 'AWS: bevel-groove weld.',
    awsEn: 'AWS: bevel-groove weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.singleVRootFace,
    bodyPl: 'V na pionowej nóżce. Ukosowanie z szerokim progiem — dolna część '
        'brzegów (przy grani) zostaje nieukosowana.',
    bodyEn: 'A V on a vertical stem. Bevel with a broad root face — the lower '
        'part of the edges (at the root) is left square.',
    awsPl: 'AWS: brak osobnego znaku (rowek V, próg wynika z wymiarów).',
    awsEn: 'AWS: no separate sign (V-groove, root face from the '
        'dimensions).',
  ),
  BasicSymbolInfo(
    kind: WeldKind.singleBevelRootFace,
    bodyPl: '½V z nóżką: jeden brzeg ukosowany, z szerokim progiem przy '
        'grani. Strzałka (łamana) wskazuje element do ukosowania.',
    bodyEn: 'A bevel with a stem: one edge bevelled, with a broad root face. '
        'The arrow (with a break) points to the member to be bevelled.',
    awsPl: 'AWS: brak osobnego znaku (rowek bevel, próg wynika '
        'z wymiarów).',
    awsEn: 'AWS: no separate sign (bevel-groove, root face from the '
        'dimensions).',
  ),
  BasicSymbolInfo(
    kind: WeldKind.singleU,
    bodyPl: 'Litera U na nóżce. Oba brzegi z zaokrąglonym (tulipanowym) '
        'ukosowaniem — grube ścianki, mniej spoiwa niż przy V.',
    bodyEn: 'Letter U on a stem. Both edges with a rounded (tulip) '
        'preparation — thick walls, less filler than a V.',
    awsPl: 'AWS: U-groove weld.',
    awsEn: 'AWS: U-groove weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.singleJ,
    bodyPl: 'Połowa U: pionowa kreska po lewej i łuk. Zaokrąglone ukosowanie '
        'tylko jednego brzegu, drugi bez ukosowania. Strzałka (łamana) '
        'wskazuje element do ukosowania.',
    bodyEn: 'Half a U: vertical line on the left and an arc. Rounded '
        'preparation on one edge only, the other one square. The arrow '
        '(with a break) points to the member to be prepared.',
    awsPl: 'AWS: J-groove weld.',
    awsEn: 'AWS: J-groove weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.plug,
    bodyPl: 'Prostokąt. Spoina w otworze lub szczelinie wyciętej w jednej '
        'z blach ułożonych na zakładkę.',
    bodyEn: 'Rectangle. Weld in a hole or slot cut in one of two lapped '
        'plates.',
    awsPl: 'AWS: plug or slot weld.',
    awsEn: 'AWS: plug or slot weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.spot,
    bodyPl: 'Kółko. Punkty łączące blachy na zakładkę. Kółko na środku '
        'linii — zgrzeina punktowa (oporowa); kółko stojące na linii — '
        'spoina punktowa przetopowa (np. łukowa) od wskazanej strony.',
    bodyEn: 'Circle. Spots joining lapped sheets. Circle centred on the line '
        '— resistance spot weld; circle standing on the line — fusion spot '
        'weld (e.g. arc) made from the side shown.',
    awsPl: 'AWS: spot weld.',
    awsEn: 'AWS: spot weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.seam,
    bodyPl: 'Kółko przecięte dwiema poziomymi kreskami. Ciągła spoina '
        'liniowa z zachodzących na siebie punktów. Na środku linii — '
        'zgrzeina liniowa (oporowa); stojące na linii — spoina przetopowa.',
    bodyEn: 'Circle crossed by two horizontal lines. A continuous seam of '
        'overlapping spots. Centred on the line — resistance seam weld; '
        'standing on the line — fusion seam weld.',
    awsPl: 'AWS: seam weld.',
    awsEn: 'AWS: seam weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.surfacing,
    bodyPl: 'Dwa łuki obok siebie. Napawanie warstwy na powierzchni (np. '
        'utwardzanie, warstwa odporna na korozję) — nie łączy dwóch części.',
    bodyEn: 'Two arcs side by side. A layer deposited on a surface (e.g. '
        'hardfacing, corrosion-resistant overlay) — it does not join two '
        'parts.',
    awsPl: 'AWS: surfacing weld.',
    awsEn: 'AWS: surfacing weld.',
  ),
  BasicSymbolInfo(
    kind: WeldKind.edge,
    bodyPl: 'Prostokąt przedzielony pionową kreską. Spoina na czołach '
        '(krawędziach) dwóch blach ułożonych równolegle. Na starszych '
        'rysunkach (ISO 2553:1992) — trzy pionowe kreski.',
    bodyEn: 'A rectangle split by a vertical line. Weld on the edges of two '
        'plates lying parallel. Older drawings (ISO 2553:1992) show three '
        'vertical lines.',
    awsPl: 'AWS: edge weld — ten sam kształt.',
    awsEn: 'AWS: edge weld — same shape.',
  ),
];
