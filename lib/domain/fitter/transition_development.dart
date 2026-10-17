/// Przejście prostokąt (kwadrat) → koło: rozwinięcie metodą triangulacji.
///
/// Prostokąt A × B (środek 0,0,0; bok A wzdłuż X), koło D w płaszczyźnie
/// z = H, środek przesunięty o (ex, ey). Powierzchnia składa się z:
///   • 4 trójkątów płaskich — bok prostokąta + punkt koła, w którym styczna
///     do koła jest równoległa do tego boku (φ = 0°, 90°, 180°, 270° —
///     niezależnie od przesunięcia), oraz
///   • 4 wycinków stożków ukośnych z wierzchołkami w narożach, każdy nad
///     ćwiartką koła (naroże A = (+A/2, +B/2) nad φ 0–90° itd.).
/// Linie prawdziwe = odległości 3D naroże → punkt koła (tworzące stożków)
/// i wysokości trójkątów. Rozwinięcie składane kolejno: trójkąt z trzech
/// boków, wachlarz stożka z dokładnym kątem rozwinięcia (całka — patrz
/// [developedFanAngle]), więc cięciwy NA BLASZE w tabeli są dokładne.
///
/// Naroża: A (+X+Y), B (−X+Y), C (−X−Y), D (+X−Y) — przeciwnie do zegara.
/// Punkty koła 1…N od φ = 0 (kierunek +X), przeciwnie do zegara.
/// Boki: D–A (x = +A/2, długość B), A–B (y = +B/2, długość A), B–C, C–D.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import 'cone_development.dart';

enum TransitionSeam {
  /// Szew w połowie boku o długości A.
  sideA,

  /// Szew w połowie boku o długości B.
  sideB,

  /// Szew w narożu (po środkowej tworzącej wachlarza).
  corner,
}

enum TransitionProblem {
  sideA,
  sideB,
  diameter,
  height,
  offset,
  thickness,
  divisions,
  parts,
}

class TransitionInput {
  final double sideAMm;
  final double sideBMm;
  final double diameterMm;
  final double heightMm;
  final double offsetXMm;
  final double offsetYMm;
  final double thicknessMm;

  /// Wymiary prostokąta i koła: zewnętrzne / wewnętrzne / średnie.
  final DiameterRef ref;
  final int divisions;

  /// Części: 1, 2 albo 4.
  final int parts;
  final TransitionSeam seam;

  const TransitionInput({
    required this.sideAMm,
    required this.sideBMm,
    required this.diameterMm,
    required this.heightMm,
    this.offsetXMm = 0,
    this.offsetYMm = 0,
    this.thicknessMm = 0,
    this.ref = DiameterRef.mean,
    this.divisions = 16,
    this.parts = 1,
    this.seam = TransitionSeam.sideB,
  });

  double get meanAMm => neutralDim(sideAMm, thicknessMm, ref);
  double get meanBMm => neutralDim(sideBMm, thicknessMm, ref);
  double get meanDMm => neutralDim(diameterMm, thicknessMm, ref);

  bool _len(double v) => v.isFinite && v > 0 && v <= 50000;

  List<TransitionProblem> get problems {
    final out = <TransitionProblem>[];
    if (!_len(sideAMm)) out.add(TransitionProblem.sideA);
    if (!_len(sideBMm)) out.add(TransitionProblem.sideB);
    if (!_len(diameterMm)) out.add(TransitionProblem.diameter);
    if (!(heightMm.isFinite && heightMm > 0 && heightMm <= 100000)) {
      out.add(TransitionProblem.height);
    }
    if (!(offsetXMm.isFinite &&
        offsetYMm.isFinite &&
        offsetXMm.abs() <= 100000 &&
        offsetYMm.abs() <= 100000)) {
      out.add(TransitionProblem.offset);
    }
    final minDim = [sideAMm, sideBMm, diameterMm]
        .where((v) => v.isFinite && v > 0)
        .fold<double>(double.infinity, math.min);
    if (!(thicknessMm.isFinite &&
        thicknessMm >= 0 &&
        (minDim == double.infinity || thicknessMm < minDim / 2))) {
      out.add(TransitionProblem.thickness);
    }
    if (!kConeDivisions.contains(divisions)) {
      out.add(TransitionProblem.divisions);
    }
    if (!const [1, 2, 4].contains(parts)) out.add(TransitionProblem.parts);
    return out;
  }

  /// Koło w rzucie wystaje poza prostokąt (kształt nietypowy — sprawdź).
  bool get circleOverhangs =>
      offsetXMm.abs() + meanDMm / 2 > meanAMm / 2 + 1e-9 ||
      offsetYMm.abs() + meanDMm / 2 > meanBMm / 2 + 1e-9;
}

/// Linia z długością (linia prawdziwa, cięciwa na blasze, bok).
class TransitionLine {
  final String label;
  final double lengthMm;
  const TransitionLine(this.label, this.lengthMm);
}

class TransitionPart {
  final FlatPatternPart pattern;

  /// Linie prawdziwe (naroże/punkt boku → punkt koła), kolejno od szwu.
  final List<TransitionLine> trueLines;

  /// Cięciwy krawędzi kołowej NA BLASZE, kolejno.
  final List<TransitionLine> topChords;

  /// Odcinki krawędzi prostokąta (boki, połówki boków przy szwie).
  final List<TransitionLine> bottomEdges;

  /// Długość krawędzi kołowej na blasze (gęsto), mm.
  final double topEdgeMm;

  /// Długość krawędzi prostokąta, mm.
  final double bottomEdgeMm;

  /// Numer części identycznej wcześniej (0-based) albo null.
  final int? sameAs;

  /// [sameAs] w odbiciu lustrzanym (odwróć szablon).
  final bool mirrored;

  const TransitionPart({
    required this.pattern,
    required this.trueLines,
    required this.topChords,
    required this.bottomEdges,
    required this.topEdgeMm,
    required this.bottomEdgeMm,
    this.sameAs,
    this.mirrored = false,
  });

  TransitionPart _withSame(int idx, bool mirror) => TransitionPart(
        pattern: pattern,
        trueLines: trueLines,
        topChords: topChords,
        bottomEdges: bottomEdges,
        topEdgeMm: topEdgeMm,
        bottomEdgeMm: bottomEdgeMm,
        sameAs: idx,
        mirrored: mirror,
      );
}

/// Trójkąt płaski na boku: etykieta boku i wysokość (prawdziwa).
class TransitionSide {
  final String label;
  final double lengthMm;
  final double heightMm;
  const TransitionSide(this.label, this.lengthMm, this.heightMm);
}

class TransitionResult {
  final TransitionInput input;
  final double meanAMm;
  final double meanBMm;
  final double meanDMm;
  final List<TransitionPart> parts;
  final List<TransitionSide> sides;

  const TransitionResult({
    required this.input,
    required this.meanAMm,
    required this.meanBMm,
    required this.meanDMm,
    required this.parts,
    required this.sides,
  });

  double get bottomEdgeMm => parts.fold(0.0, (s, p) => s + p.bottomEdgeMm);
  double get topEdgeMm => parts.fold(0.0, (s, p) => s + p.topEdgeMm);

  /// Cięciwa podziału koła w rzucie (stała) — klasyczna triangulacja.
  double get planChordMm => meanDMm * math.sin(math.pi / input.divisions);
}

class _Rung {
  final String bottomLabel;
  final V3 bottom;
  final String topLabel;
  final V3 top;
  final double phi;
  final bool seam;
  const _Rung(this.bottomLabel, this.bottom, this.topLabel, this.top, this.phi,
      this.seam);
}

const _corners = ['A', 'B', 'C', 'D'];

/// Liczy przejście; `null`, gdy dane są błędne.
TransitionResult? computeTransition(TransitionInput i) {
  if (i.problems.isNotEmpty) return null;
  final densify = densifyFor(i.divisions);
  final a = i.meanAMm / 2, b = i.meanBMm / 2, rc = i.meanDMm / 2;
  final ex = i.offsetXMm, ey = i.offsetYMm, h = i.heightMm;
  final n = i.divisions;
  final q = n ~/ 4;
  final k = [V3(a, b, 0), V3(-a, b, 0), V3(-a, -b, 0), V3(a, -b, 0)];
  final mids = [V3(a, 0, 0), V3(0, b, 0), V3(-a, 0, 0), V3(0, -b, 0)];
  V3 circle(double phi) =>
      V3(ex + rc * math.cos(phi), ey + rc * math.sin(phi), h);
  V3 dCircle(double phi) => V3(-rc * math.sin(phi), rc * math.cos(phi), 0);

  // Gdzie szwy.
  final sideSeams = <int>{};
  final cornerSeams = <int>{};
  switch ((i.seam, i.parts)) {
    case (TransitionSeam.corner, 1):
      cornerSeams.add(2);
    case (TransitionSeam.corner, 2):
      cornerSeams.addAll([0, 2]);
    case (TransitionSeam.corner, _):
      cornerSeams.addAll([0, 1, 2, 3]);
    case (TransitionSeam.sideA, 1):
      sideSeams.add(3);
    case (TransitionSeam.sideA, 2):
      sideSeams.addAll([1, 3]);
    case (TransitionSeam.sideB, 1):
      sideSeams.add(2);
    case (TransitionSeam.sideB, 2):
      sideSeams.addAll([0, 2]);
    case (_, _):
      sideSeams.addAll([0, 1, 2, 3]);
  }

  // Szczeble (linie dół–góra) kolejno po obwodzie.
  final rungs = <_Rung>[];
  var seamPts = 0;
  for (var s = 0; s < 4; s++) {
    final prev = (s + 3) % 4; // naroże przed bokiem s
    final next = s; // naroże za bokiem s (A dla boku D–A)
    final phiT = s * math.pi / 2;
    final tLabel = '${s * q + 1}';
    final t = circle(phiT);
    if (s == 0) {
      rungs.add(_Rung(_corners[prev], k[prev], tLabel, t, phiT, false));
    }
    if (sideSeams.contains(s)) {
      rungs.add(_Rung('M${s + 1}', mids[s], tLabel, t, phiT, true));
    }
    rungs.add(_Rung(_corners[next], k[next], tLabel, t, phiT, false));
    // Wachlarz naroża [next] nad φ ∈ (s·90°, (s+1)·90°).
    final phiMid = phiT + math.pi / 4;
    final cornerSeam = cornerSeams.contains(next);
    var midInserted = false;
    for (var j = 1; j < q; j++) {
      final phi = phiT + j * math.pi / 2 / q;
      if (cornerSeam && !midInserted && q.isOdd && phi > phiMid) {
        seamPts++;
        rungs.add(_Rung(_corners[next], k[next], 'S$seamPts', circle(phiMid),
            phiMid, true));
        midInserted = true;
      }
      final isMid = cornerSeam && q.isEven && j == q ~/ 2;
      rungs.add(_Rung(_corners[next], k[next], '${s * q + j + 1}', circle(phi),
          phi, isMid));
    }
    if (cornerSeam && q.isOdd && !midInserted) {
      seamPts++;
      rungs.add(_Rung(
          _corners[next], k[next], 'S$seamPts', circle(phiMid), phiMid, true));
    }
    if (s < 3) {
      final phiN = (s + 1) * math.pi / 2;
      rungs.add(_Rung(_corners[next], k[next], '${(s + 1) * q + 1}',
          circle(phiN), phiN, false));
    }
  }
  // Ostatni szczebel (D, 1) zamyka obwód — to rungs[0]. Wachlarz D kończy się
  // na φ = 360°, ale ostatni rung przed zamknięciem to D – ostatni punkt.

  // Obrót listy tak, by zaczynała się od szwu.
  final seamIdx = [
    for (var r = 0; r < rungs.length; r++)
      if (rungs[r].seam) r
  ];
  final m = rungs.length;

  int orientation(V3 p1, V3 p2, V3 p3, int fallback) {
    final nrm = (p2 - p1).cross(p3 - p1);
    final c = (p1 + p2 + p3) * (1 / 3);
    final axis = V3(ex * c.z / h, ey * c.z / h, c.z);
    final d = nrm.dot(c - axis);
    final scale = nrm.length * (c - axis).length;
    if (scale <= 0 || d.abs() < 1e-12 * scale) return fallback;
    return d > 0 ? 1 : -1;
  }

  final parts = <TransitionPart>[];
  for (var p = 0; p < seamIdx.length; p++) {
    final start = seamIdx[p];
    final end = seamIdx[(p + 1) % seamIdx.length];
    final count = ((end - start) % m + m) % m;
    final seq = [
      for (var c = 0; c <= (count == 0 ? m : count); c++) rungs[(start + c) % m]
    ];
    parts.add(_unfold(seq, orientation, circle, dCircle, densify));
  }

  // Części identyczne / lustrzane.
  final out = <TransitionPart>[];
  for (var p = 0; p < parts.length; p++) {
    var part = parts[p];
    for (var o = 0; o < p; o++) {
      final same = _sameShape(parts[o], part);
      if (same != null) {
        part = part._withSame(o, same);
        break;
      }
    }
    out.add(part);
  }

  final sides = <TransitionSide>[
    for (var s = 0; s < 4; s++)
      TransitionSide(
        '${_corners[(s + 3) % 4]}–${_corners[s]}',
        k[(s + 3) % 4].distanceTo(k[s]),
        _pointLineDistance(circle(s * math.pi / 2), k[(s + 3) % 4], k[s]),
      ),
  ];

  return TransitionResult(
    input: i,
    meanAMm: i.meanAMm,
    meanBMm: i.meanBMm,
    meanDMm: i.meanDMm,
    parts: out,
    sides: sides,
  );
}

double _pointLineDistance(V3 p, V3 a, V3 b) {
  final d = b - a;
  return (p - a).cross(d).length / d.length;
}

/// null — różne; false — identyczne; true — lustrzane.
bool? _sameShape(TransitionPart x, TransitionPart y) {
  List<double> sig(TransitionPart p) => [
        for (final l in p.trueLines) l.lengthMm,
        for (final l in p.topChords) l.lengthMm,
        for (final l in p.bottomEdges) l.lengthMm,
      ];
  bool eq(List<double> u, List<double> v) {
    if (u.length != v.length) return false;
    for (var i = 0; i < u.length; i++) {
      if ((u[i] - v[i]).abs() > 0.01) return false;
    }
    return true;
  }

  if (eq(sig(x), sig(y))) return false;
  List<double> rev(TransitionPart p) => [
        for (final l in p.trueLines.reversed) l.lengthMm,
        for (final l in p.topChords.reversed) l.lengthMm,
        for (final l in p.bottomEdges.reversed) l.lengthMm,
      ];
  if (eq(sig(x), rev(y))) return true;
  return null;
}

TransitionPart _unfold(
  List<_Rung> seq,
  int Function(V3, V3, V3, int) orientation,
  V3 Function(double) circle,
  V3 Function(double) dCircle,
  int densify,
) {
  // Stan rozwinięcia: bieżący punkt dolny i górny (2D).
  var b2 = const Pt(0, 0);
  var t2 = Pt(0, seq.first.bottom.distanceTo(seq.first.top));
  var sign = 1;
  final bottom = <Pt>[b2];
  final bottomLabels = <String>[seq.first.bottomLabel];
  final top = <Pt>[t2];
  final topDense = <Pt>[t2];
  final topLabels = <String>[seq.first.topLabel];
  final rungs2 = <(Pt, Pt)>[(b2, t2)];
  final trueLines = <TransitionLine>[
    TransitionLine('${seq.first.bottomLabel}–${seq.first.topLabel}',
        seq.first.bottom.distanceTo(seq.first.top)),
  ];
  final topChords = <TransitionLine>[];
  final bottomEdges = <TransitionLine>[];
  var topLen = 0.0;

  for (var r = 1; r < seq.length; r++) {
    final prev = seq[r - 1], cur = seq[r];
    if (cur.bottomLabel == prev.bottomLabel) {
      // Wachlarz stożka z wierzchołkiem w narożu.
      final apex = cur.bottom;
      var phi0 = prev.phi, phi1 = cur.phi;
      if (phi1 < phi0 - 1e-9) phi1 += 2 * math.pi;
      sign = orientation(apex, prev.top, cur.top, sign);
      final u0 = t2 - b2;
      final u0n = u0 * (1 / u0.magnitude);
      var psi = 0.0;
      Pt? last;
      for (var sub = 1; sub <= densify; sub++) {
        final pa = phi0 + (phi1 - phi0) * (sub - 1) / densify;
        final pb = phi0 + (phi1 - phi0) * sub / densify;
        psi += developedFanAngle(apex, circle, dCircle, pa, pb, steps: 8);
        final rho = circle(pb).distanceTo(apex);
        final pt = b2 + rotatePt(u0n, sign * psi) * rho;
        topLen += pt.distanceTo(topDense.last);
        topDense.add(pt);
        last = pt;
      }
      final newTop = last!;
      topChords.add(TransitionLine(
          '${prev.topLabel}–${cur.topLabel}', newTop.distanceTo(t2)));
      t2 = newTop;
      top.add(t2);
      topLabels.add(cur.topLabel);
    } else {
      // Trójkąt płaski: nowy punkt dolny z dwóch długości.
      final l1 = prev.bottom.distanceTo(cur.bottom);
      final l2 = cur.bottom.distanceTo(cur.top);
      sign = orientation(prev.bottom, cur.bottom, cur.top, sign);
      final w = t2 - b2;
      final d = w.magnitude;
      final along = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
      final hh = math.sqrt(math.max(0, l1 * l1 - along * along));
      final wn = w * (1 / d);
      final perp = Pt(-wn.y, wn.x);
      final nb = b2 + wn * along - perp * (sign * hh);
      bottomEdges
          .add(TransitionLine('${prev.bottomLabel}–${cur.bottomLabel}', l1));
      b2 = nb;
      bottom.add(b2);
      bottomLabels.add(cur.bottomLabel);
    }
    rungs2.add((b2, t2));
    trueLines.add(TransitionLine(
        '${cur.bottomLabel}–${cur.topLabel}', cur.bottom.distanceTo(cur.top)));
  }

  final raw = <Pt>[...bottom, ...topDense.reversed];
  final frame = PlateFrame.fit(bottom.first, bottom.last,
      down: bottom[bottom.length ~/ 2],
      up: topDense[topDense.length ~/ 2],
      all: raw);
  final marks = <PatternMark>[
    for (var j = 0; j < bottom.length; j++)
      PatternMark(bottomLabels[j], frame.map(bottom[j])),
    for (var j = 0; j < top.length; j++)
      PatternMark(topLabels[j], frame.map(top[j])),
  ];
  return TransitionPart(
    pattern: FlatPatternPart(
      outline: [for (final p in raw) frame.map(p)],
      bendLines: [
        for (var j = 1; j < rungs2.length - 1; j++)
          [frame.map(rungs2[j].$1), frame.map(rungs2[j].$2)],
      ],
      marks: marks,
      widthMm: frame.width,
      heightMm: frame.height,
    ),
    trueLines: trueLines,
    topChords: topChords,
    bottomEdges: bottomEdges,
    topEdgeMm: topLen,
    bottomEdgeMm: bottomEdges.fold(0.0, (s, l) => s + l.lengthMm),
  );
}
