// Znaki (glify) symboli spoin rysowane na Canvas — wspólne dla ściągi,
// kreatora i rysunków linii odniesienia.
//
// Układ współrzędnych glifu: x poziomo (0 = środek symbolu), y „na zewnątrz”
// od linii odniesienia (0 = na linii, h = szczyt symbolu). [outward] = -1
// rysuje symbol NAD linią (w górę ekranu), +1 — POD linią. Odbicie jest tylko
// pionowe: pionowa kreska ½V, ½Y, J i pachwiny zostaje zawsze po LEWEJ,
// tak jak w normie.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/weld_symbols/weld_symbol.dart';

/// Odwzorowanie współrzędnych glifu na ekran.
class GlyphFrame {
  const GlyphFrame(this.origin, this.h, this.outward);

  /// Punkt na linii odniesienia pod środkiem symbolu.
  final Offset origin;

  /// Wysokość symbolu [px].
  final double h;

  /// -1 = nad linią, +1 = pod linią.
  final double outward;

  Offset p(double x, double y) =>
      Offset(origin.dx + x * h, origin.dy + outward * y * h);
}

/// Połowa szerokości glifu (w jednostkach h) — do ustawienia wymiarów obok.
double glyphHalfWidth(WeldKind kind) => switch (kind) {
      WeldKind.fillet => 0.5,
      WeldKind.squareButt => 0.3,
      WeldKind.singleV => 0.58,
      WeldKind.singleBevel => 0.4,
      WeldKind.singleVRootFace => 0.5,
      WeldKind.singleBevelRootFace => 0.4,
      WeldKind.singleU => 0.4,
      WeldKind.singleJ => 0.4,
      WeldKind.backingRun => 0.48,
      WeldKind.plug => 0.45,
      WeldKind.spot => 0.42,
      WeldKind.seam => 0.65,
      WeldKind.surfacing => 0.55,
      WeldKind.edge => 0.4,
    };

Paint glyphStroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _poly(Canvas c, GlyphFrame f, List<(double, double)> pts, Paint paint,
    {bool close = false}) {
  final start = f.p(pts.first.$1, pts.first.$2);
  final path = Path()..moveTo(start.dx, start.dy);
  for (final pt in pts.skip(1)) {
    final o = f.p(pt.$1, pt.$2);
    path.lineTo(o.dx, o.dy);
  }
  if (close) path.close();
  c.drawPath(path, paint);
}

/// Łuk w układzie glifu: środek (cx, cy), promień r, kąty od [a0] do [a1]
/// (radiany, matematycznie: y w górę = „na zewnątrz”).
List<(double, double)> _arc(
    double cx, double cy, double r, double a0, double a1,
    {int steps = 18}) {
  return [
    for (var i = 0; i <= steps; i++)
      (
        cx + r * math.cos(a0 + (a1 - a0) * i / steps),
        cy + r * math.sin(a0 + (a1 - a0) * i / steps),
      ),
  ];
}

/// Rysuje symbol podstawowy [kind] w ramce [f].
void paintBasicGlyph(Canvas c, WeldKind kind, GlyphFrame f, Paint paint) {
  switch (kind) {
    case WeldKind.fillet:
      _poly(c, f, const [(-0.5, 0), (-0.5, 1), (0.5, 0)], paint, close: true);
    case WeldKind.squareButt:
      _poly(c, f, const [(-0.22, 0), (-0.22, 1)], paint);
      _poly(c, f, const [(0.22, 0), (0.22, 1)], paint);
    case WeldKind.singleV:
      _poly(c, f, const [(-0.58, 1), (0, 0), (0.58, 1)], paint);
    case WeldKind.singleBevel:
      _poly(c, f, const [(-0.28, 1), (-0.28, 0), (0.4, 1)], paint);
    case WeldKind.singleVRootFace:
      _poly(c, f, const [(0, 0), (0, 0.4)], paint);
      _poly(c, f, const [(-0.5, 1), (0, 0.4), (0.5, 1)], paint);
    case WeldKind.singleBevelRootFace:
      _poly(c, f, const [(-0.28, 1), (-0.28, 0)], paint);
      _poly(c, f, const [(-0.28, 0.4), (0.4, 1)], paint);
    case WeldKind.singleU:
      const r = 0.32;
      _poly(c, f, const [(0, 0), (0, 0.3)], paint);
      _poly(
          c,
          f,
          [
            (-r, 1.0),
            ..._arc(0, 0.3 + r, r, math.pi, 2 * math.pi),
            (r, 1.0),
          ],
          paint);
    case WeldKind.singleJ:
      const r = 0.42;
      const x0 = -0.28;
      _poly(c, f, const [(x0, 0), (x0, 1)], paint);
      _poly(
          c,
          f,
          [
            ..._arc(x0, 0.3 + r, r, 1.5 * math.pi, 2 * math.pi),
            (x0 + r, 1.0),
          ],
          paint);
    case WeldKind.backingRun:
      _poly(c, f, _arc(0, 0, 0.45, math.pi, 0), paint);
    case WeldKind.plug:
      _poly(c, f, const [(-0.45, 0), (-0.45, 0.62), (0.45, 0.62), (0.45, 0)],
          paint);
    case WeldKind.spot:
      _poly(c, f, _arc(0, 0.42, 0.42, 0, 2 * math.pi, steps: 32), paint);
    case WeldKind.seam:
      _poly(c, f, _arc(0, 0.42, 0.42, 0, 2 * math.pi, steps: 32), paint);
      _poly(c, f, const [(-0.65, 0.3), (0.65, 0.3)], paint);
      _poly(c, f, const [(-0.65, 0.54), (0.65, 0.54)], paint);
    case WeldKind.surfacing:
      _poly(c, f, _arc(-0.26, 0, 0.26, math.pi, 0), paint);
      _poly(c, f, _arc(0.26, 0, 0.26, math.pi, 0), paint);
    case WeldKind.edge:
      // EN ISO 2553:2019: prostokąt na linii przedzielony pionową kreską.
      _poly(c, f, const [(-0.38, 0), (-0.38, 0.8), (0.38, 0.8), (0.38, 0)],
          paint);
      _poly(c, f, const [(0, 0), (0, 0.8)], paint);
  }
}

/// Symbol kształtu lica nad symbolem podstawowym (po jego zewnętrznej
/// stronie). Pachwina — równolegle do przeciwprostokątnej trójkąta, pozostałe
/// — poziomo nad symbolem.
void paintContour(
    Canvas c, WeldKind kind, WeldContour contour, GlyphFrame f, Paint paint) {
  if (contour == WeldContour.none) return;
  if (kind == WeldKind.fillet) {
    // Przeciwprostokątna od (-0,5; 1) do (0,5; 0); normalna na zewnątrz
    // (od wnętrza trójkąta) = (1, 1)/√2. Odsunięcie 0,22 h.
    const off = 0.22;
    final n = off / math.sqrt2;
    final ax = -0.5 + n, ay = 1.0 + n;
    final bx = 0.5 + n, by = 0.0 + n;
    const bulge = 0.14;
    final pts = <(double, double)>[];
    for (var i = 0; i <= 16; i++) {
      final t = i / 16;
      final k = switch (contour) {
        WeldContour.convex => bulge * 4 * t * (1 - t),
        WeldContour.concave => -bulge * 4 * t * (1 - t),
        _ => 0.0,
      };
      pts.add((
        ax + (bx - ax) * t + k / math.sqrt2,
        ay + (by - ay) * t + k / math.sqrt2,
      ));
    }
    _poly(c, f, pts, paint);
    return;
  }
  final w = glyphHalfWidth(kind) + 0.05;
  const base = 1.25;
  const bulge = 0.16;
  final pts = <(double, double)>[];
  for (var i = 0; i <= 16; i++) {
    final t = i / 16;
    final x = -w + 2 * w * t;
    final k = switch (contour) {
      WeldContour.convex => bulge * 4 * t * (1 - t),
      WeldContour.concave => bulge - bulge * 4 * t * (1 - t),
      _ => 0.0,
    };
    pts.add((x, base + k));
  }
  _poly(c, f, pts, paint);
}

/// Wysokość (w jednostkach h) zajęta przez glif razem z symbolem lica.
double glyphExtent(WeldKind kind, WeldContour contour) =>
    contour == WeldContour.none ? 1.0 : 1.45;
