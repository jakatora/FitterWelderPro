/// Kolano segmentowe (lobster back / mitred bend) — geometria cięcia.
///
/// Kolano o całkowitym kącie zmiany kierunku Θ złożone z W spoin
/// (cięć ukośnych): każda spoina zmienia kierunek o α = Θ / W, więc każdy
/// koniec segmentu jest ścięty pod kątem β = α / 2 względem płaszczyzny
/// prostopadłej do osi rury. Segmenty: W − 1 pełnych (oba końce ścięte)
/// i dwa końcowe „pół-segmenty” (jedno cięcie, drugi koniec prosty).
///
/// Dla promienia gięcia R (po osi, mierzony do środka łuku):
///   pełny segment po osi        Lc = 2·R·tg β
///   od wewnątrz łuku (gardło)   Lt = 2·(R − D/2)·tg β
///   od zewnątrz łuku (grzbiet)  Lh = 2·(R + D/2)·tg β
///   pół-segment                 połowy powyższych + prosty odcinek T.
/// Spoina W = 1 (jedno cięcie, dwa pół-segmenty): R nie gra roli, kolano
/// jest ostre (oś łamie się w punkcie).
///
/// Szablon cięcia na zewnętrznej powierzchni rury (D = OD): odległość
/// linii cięcia od linii odniesienia przechodzącej przez gardło, w funkcji
/// kąta φ po obwodzie liczonego od gardła:
///   y(φ) = (D/2)·(1 − cos φ)·tg β,   0 ≤ y ≤ D·tg β,
/// a położenie po obwodzie x = π·D·φ / 360 (łuk, nie cięciwa).
///
/// Spoina ukośna jest elipsą o półosiach D/2 i D/(2·cos β) — długość
/// z przybliżenia Ramanujana.
///
/// Geometria zewnętrznej powierzchni, bez ukosowania, szczeliny i ścianki.
/// W rurociągach ciśnieniowych kolano segmentowe tylko wtedy, gdy dopuszcza
/// je projekt (ASME B31.3 §304.2.3 — obliczenie i ograniczenia kąta).
///
/// Czysty Dart.
library;

import 'dart:math' as math;

enum MitreProblem {
  od,
  angle,
  welds,
  radius,

  /// R ≤ D/2 — od strony gardła segmenty nachodzą na siebie.
  radiusTooSmall,
  tangent,

  /// Jedno cięcie, a prosty odcinek krótszy niż (D/2)·tg β.
  tangentTooShort,
}

class MitreBendInput {
  /// Średnica zewnętrzna, mm.
  final double odMm;

  /// Całkowity kąt zmiany kierunku, ° (np. 90).
  final double bendAngleDeg;

  /// Liczba spoin (cięć ukośnych), 1–12.
  final int welds;

  /// Promień gięcia po osi, mm (pomijany przy jednej spoinie).
  final double radiusMm;

  /// Prosty odcinek doklejony do każdego pół-segmentu, mm.
  final double tangentMm;

  const MitreBendInput({
    required this.odMm,
    required this.bendAngleDeg,
    required this.welds,
    required this.radiusMm,
    this.tangentMm = 0,
  });

  List<MitreProblem> get problems {
    final out = <MitreProblem>[];
    if (!(odMm > 0) || odMm > 3000) out.add(MitreProblem.od);
    if (!(bendAngleDeg > 0) || bendAngleDeg > 180) {
      out.add(MitreProblem.angle);
    }
    if (welds < 1 || welds > 12) out.add(MitreProblem.welds);
    if (welds > 1) {
      if (!(radiusMm > 0)) {
        out.add(MitreProblem.radius);
      } else if (odMm > 0 && radiusMm <= odMm / 2) {
        out.add(MitreProblem.radiusTooSmall);
      }
    }
    if (tangentMm < 0 || !tangentMm.isFinite) out.add(MitreProblem.tangent);
    // Cięcie pod kątem ≥ 90° (β ≥ 90°) nie istnieje.
    if (welds >= 1 && bendAngleDeg / welds >= 180) {
      out.add(MitreProblem.angle);
    }
    // Jedno cięcie: odcinek prosty musi pomieścić skos od strony gardła,
    // inaczej linia cięcia „wychodzi” poza koniec rury.
    if (welds == 1 &&
        odMm > 0 &&
        bendAngleDeg > 0 &&
        bendAngleDeg < 180 &&
        tangentMm >= 0 &&
        tangentMm < odMm / 2 * math.tan(bendAngleDeg / 2 * math.pi / 180)) {
      out.add(MitreProblem.tangentTooShort);
    }
    return out;
  }
}

/// Wymiary jednego elementu kolana.
class MitrePiece {
  /// Po osi rury, mm.
  final double centreMm;

  /// Po wewnętrznej stronie łuku (gardło), mm.
  final double throatMm;

  /// Po zewnętrznej stronie łuku (grzbiet), mm.
  final double heelMm;

  const MitrePiece({
    required this.centreMm,
    required this.throatMm,
    required this.heelMm,
  });
}

class MitreTemplatePoint {
  /// Kąt po obwodzie od gardła, °.
  final double phiDeg;

  /// Łuk po obwodzie od gardła, mm.
  final double arcMm;

  /// Odsunięcie linii cięcia od linii odniesienia przez gardło, mm.
  final double offsetMm;

  const MitreTemplatePoint(this.phiDeg, this.arcMm, this.offsetMm);
}

class MitreBendResult {
  final MitreBendInput input;

  /// Zmiana kierunku na jednej spoinie, °.
  final double jointDeflectionDeg;

  /// Kąt cięcia końca segmentu względem prostopadłej, °.
  final double cutAngleDeg;

  /// Pełny segment (null przy jednej spoinie).
  final MitrePiece? fullSegment;
  final int fullSegments;

  /// Pół-segment końcowy (z odcinkiem prostym).
  final MitrePiece endPiece;

  /// Różnica długości grzbiet − gardło na jednym cięciu = D·tg β, mm.
  final double cutDropMm;

  /// Obwód rury (długość szablonu), mm.
  final double circumferenceMm;

  /// Długość jednej spoiny ukośnej (elipsa), mm.
  final double weldLengthMm;

  /// Rura potrzebna po osi (segmenty kolejno z jednego odcinka, obracane
  /// o 180°), bez rzazów, mm.
  final double pipeNeededMm;

  const MitreBendResult({
    required this.input,
    required this.jointDeflectionDeg,
    required this.cutAngleDeg,
    required this.fullSegment,
    required this.fullSegments,
    required this.endPiece,
    required this.cutDropMm,
    required this.circumferenceMm,
    required this.weldLengthMm,
    required this.pipeNeededMm,
  });

  double get _tanBeta => math.tan(cutAngleDeg * math.pi / 180);

  /// Odsunięcie linii cięcia na kącie [phiDeg] od gardła.
  MitreTemplatePoint pointAt(double phiDeg) {
    final phi = phiDeg * math.pi / 180;
    final r = input.odMm / 2;
    return MitreTemplatePoint(
      phiDeg,
      circumferenceMm * phiDeg / 360,
      r * (1 - math.cos(phi)) * _tanBeta,
    );
  }

  /// Punkty szablonu co 360/[divisions] stopni, od 0° do 360° włącznie.
  List<MitreTemplatePoint> templatePoints(int divisions) => [
        for (var i = 0; i <= divisions; i++) pointAt(360.0 * i / divisions),
      ];
}

/// Obwód elipsy (Ramanujan II), mm.
double ellipsePerimeter(double a, double b) {
  final h = math.pow(a - b, 2) / math.pow(a + b, 2);
  return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h)));
}

/// Liczy kolano; `null`, gdy dane są błędne (patrz [MitreBendInput.problems]).
MitreBendResult? computeMitreBend(MitreBendInput i) {
  if (i.problems.isNotEmpty) return null;
  final alpha = i.bendAngleDeg / i.welds;
  final beta = alpha / 2;
  final tb = math.tan(beta * math.pi / 180);
  final d = i.odMm;
  final r = i.welds == 1 ? 0.0 : i.radiusMm;

  MitrePiece piece(double factor) => MitrePiece(
        centreMm: factor * r * tb,
        throatMm: factor * (r - d / 2) * tb,
        heelMm: factor * (r + d / 2) * tb,
      );

  MitrePiece? full;
  if (i.welds > 1) full = piece(2);
  final halfRaw = piece(1);
  // Pół-segment: przy jednej spoinie ma długość zero po osi w punkcie
  // złamania — od strony gardła cięcie „wchodzi” o D/2·tg β, a grzbiet
  // wystaje o tyle samo; liczymy to od prostego końca przez T.
  final end = i.welds == 1
      ? MitrePiece(
          centreMm: i.tangentMm,
          throatMm: i.tangentMm - d / 2 * tb,
          heelMm: i.tangentMm + d / 2 * tb,
        )
      : MitrePiece(
          centreMm: halfRaw.centreMm + i.tangentMm,
          throatMm: halfRaw.throatMm + i.tangentMm,
          heelMm: halfRaw.heelMm + i.tangentMm,
        );
  final fullCount = i.welds - 1;
  return MitreBendResult(
    input: i,
    jointDeflectionDeg: alpha,
    cutAngleDeg: beta,
    fullSegment: full,
    fullSegments: fullCount,
    endPiece: end,
    cutDropMm: d * tb,
    circumferenceMm: math.pi * d,
    weldLengthMm:
        ellipsePerimeter(d / 2, d / (2 * math.cos(beta * math.pi / 180))),
    pipeNeededMm: fullCount * (full?.centreMm ?? 0) + 2 * end.centreMm,
  );
}
