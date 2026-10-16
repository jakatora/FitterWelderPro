// Przekroje złączy do ściągi i kreatora: blachy (stal — zimna, szara)
// i spoina (gorąca — bursztyn kArc).
//
// Jednostka rysunku = grubość blachy t. Punkt (0, 0) to oś złącza na
// powierzchni od strony strzałki (góra rysunku); y rośnie w dół, w głąb
// blachy. Przekroje są poglądowe — pokazują kształt rowka i stronę spoiny,
// nie wymiary przygotowania brzegów (te są w WPS i EN ISO 9692-1).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/weld_symbols/weld_symbol.dart';
import '../../theme/app_theme.dart';

const Color kSectionPlate = Color(0xFF4A5468);
const Color kSectionPlateEdge = kTextSec;

typedef _Pt = (double, double);

const double _g = 0.05; // połowa odstępu w grani

class _Mapper {
  const _Mapper(this.origin, this.t);
  final Offset origin;
  final double t;
  Offset o(double x, double y) => Offset(origin.dx + x * t, origin.dy + y * t);
  Path path(List<_Pt> pts, {bool close = true}) {
    final p = Path()
      ..moveTo(
          o(pts.first.$1, pts.first.$2).dx, o(pts.first.$1, pts.first.$2).dy);
    for (final q in pts.skip(1)) {
      final v = o(q.$1, q.$2);
      p.lineTo(v.dx, v.dy);
    }
    if (close) p.close();
    return p;
  }
}

Paint _fill(Color c) => Paint()
  ..color = c
  ..style = PaintingStyle.fill;

Paint _line(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round;

void _plate(Canvas c, _Mapper m, List<_Pt> pts) {
  final p = m.path(pts);
  c.drawPath(p, _fill(kSectionPlate));
  c.drawPath(p, _line(kSectionPlateEdge, 1.4));
}

void _weld(Canvas c, _Mapper m, List<_Pt> pts, {Color color = kArc}) {
  final p = m.path(pts);
  c.drawPath(p, _fill(color));
  c.drawPath(p, _line(const Color(0xFFFFC27A), 1.2));
}

// ── Profile rowków (rowek otwarty od góry, punkty z góry na dół) ────────────

List<_Pt> _leftEdge(WeldKind k) => switch (k) {
      WeldKind.singleV => const [(-0.6, 0), (-_g, 1)],
      WeldKind.singleVRootFace => const [(-0.5, 0), (-_g, 0.55), (-_g, 1)],
      WeldKind.singleU => const [
          (-0.42, 0),
          (-0.34, 0.4),
          (-0.31, 0.5),
          (-0.25, 0.58),
          (-0.16, 0.63),
          (-_g, 0.65),
          (-_g, 1),
        ],
      _ => const [(-_g, 0), (-_g, 1)],
    };

List<_Pt> _rightEdge(WeldKind k) => switch (k) {
      WeldKind.singleV => const [(0.6, 0), (_g, 1)],
      WeldKind.singleBevel => const [(0.75, 0), (_g, 1)],
      WeldKind.singleVRootFace => const [(0.5, 0), (_g, 0.55), (_g, 1)],
      WeldKind.singleBevelRootFace => const [(0.65, 0), (_g, 0.55), (_g, 1)],
      WeldKind.singleU => [for (final p in _leftEdge(k)) (-p.$1, p.$2)],
      WeldKind.singleJ => const [
          (0.55, 0),
          (0.45, 0.4),
          (0.4, 0.5),
          (0.32, 0.58),
          (0.2, 0.63),
          (_g, 0.65),
          (_g, 1),
        ],
      _ => const [(_g, 0), (_g, 1)],
    };

/// Krawędź dla strony spoiny: od strony strzałki (góra), przeciwnej (dół)
/// albo obu (rowek dwustronny, każdy na połowę grubości).
List<_Pt> _sided(List<_Pt> top, WeldSide side) => switch (side) {
      WeldSide.arrow => top,
      WeldSide.other => [for (final p in top.reversed) (p.$1, 1 - p.$2)],
      WeldSide.both => [
          for (final p in top) (p.$1, p.$2 * 0.5),
          for (final p in top.reversed) (p.$1, 1 - p.$2 * 0.5),
        ],
    };

/// Łuk lica / grani między x [xl] i [xr] na powierzchni [y0]; [out] = -1
/// na zewnątrz w górę, +1 w dół; [h] > 0 wypukłe, < 0 wklęsłe.
List<_Pt> _face(double xl, double xr, double y0, double out, double h,
    {double overhang = 0.06}) {
  final a = xl - overhang, b = xr + overhang;
  return [
    for (var i = 0; i <= 14; i++)
      (
        a + (b - a) * i / 14,
        y0 + out * h * 4 * (i / 14) * (1 - i / 14),
      ),
  ];
}

double _capHeight(WeldContour contour) => switch (contour) {
      WeldContour.flat => 0,
      WeldContour.concave => -0.07,
      WeldContour.convex => 0.17,
      WeldContour.none => 0.1,
    };

void _paintGroove(Canvas c, _Mapper m, WeldKind kind, WeldSide side,
    WeldContour contour, BackingStrip backing) {
  final left = _sided(_leftEdge(kind), side);
  final right = _sided(_rightEdge(kind), side);
  _plate(c, m, [(-1.5, 0), ...left, (-1.5, 1)]);
  _plate(c, m, [(1.5, 0), (1.5, 1), ...right.reversed]);

  final topOpen = side != WeldSide.other;
  final bottomOpen = side != WeldSide.arrow;
  final cap = _capHeight(contour);
  final capOverhang = cap < 0 ? 0.0 : 0.06;
  final hasBacking = backing != BackingStrip.none && side != WeldSide.both;

  final top = topOpen
      ? _face(left.first.$1, right.first.$1, 0, -1, cap, overhang: capOverhang)
      : hasBacking
          ? [left.first, right.first]
          : _face(left.first.$1, right.first.$1, 0, -1, 0.08, overhang: 0.02);
  final bottom = bottomOpen
      ? _face(left.last.$1, right.last.$1, 1, 1, cap, overhang: capOverhang)
      : hasBacking
          ? [left.last, right.last]
          : _face(left.last.$1, right.last.$1, 1, 1, 0.08, overhang: 0.02);

  _weld(c, m, [
    ...top,
    ...right,
    ...bottom.reversed,
    ...left.reversed,
  ]);

  if (hasBacking) {
    final y0 = side == WeldSide.arrow ? 1.0 : -0.2;
    final rect = Rect.fromPoints(m.o(-0.6, y0), m.o(0.6, y0 + 0.2));
    if (backing == BackingStrip.permanent) {
      c.drawRect(rect, _fill(kSectionPlate));
      c.drawRect(rect, _line(kSectionPlateEdge, 1.4));
    } else {
      _dashedRect(c, rect, _line(kSectionPlateEdge, 1.4));
    }
  }
}

void _dashedRect(Canvas c, Rect r, Paint paint) {
  void dashed(Offset a, Offset b) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    const dash = 5.0, gap = 4.0;
    var d = 0.0;
    while (d < len) {
      final e = math.min(d + dash, len);
      c.drawLine(a + dir * d, a + dir * e, paint);
      d = e + gap;
    }
  }

  dashed(r.topLeft, r.topRight);
  dashed(r.topRight, r.bottomRight);
  dashed(r.bottomRight, r.bottomLeft);
  dashed(r.bottomLeft, r.topLeft);
}

void _filletTriangle(Canvas c, _Mapper m, double sign, WeldContour contour) {
  // sign = +1: prawa pachwina (strona strzałki — strzałka przychodzi z prawej
  // góry), -1: lewa (strona przeciwna).
  const z = 0.55;
  const web = 0.22;
  final x0 = sign * web;
  final bulge = switch (contour) {
    WeldContour.convex => 0.1,
    WeldContour.concave => -0.1,
    _ => 0.0,
  };
  // Przeciwprostokątna od (x0, -z) do (x0 + sign·z, 0); normalna na zewnątrz
  // = (sign, -1)/√2.
  final hyp = <_Pt>[
    for (var i = 0; i <= 14; i++)
      (
        x0 +
            sign * z * (i / 14) +
            sign * bulge * 4 * (i / 14) * (1 - i / 14) / math.sqrt2,
        -z + z * (i / 14) - bulge * 4 * (i / 14) * (1 - i / 14) / math.sqrt2,
      ),
  ];
  _weld(c, m, [(x0, 0), ...hyp]);
}

/// Rysuje przekrój złącza dla [kind]. [origin] — oś złącza na powierzchni od
/// strony strzałki, [t] — grubość blachy w pikselach.
void paintJointSection(
  Canvas c,
  Offset origin,
  double t,
  WeldKind kind, {
  WeldSide side = WeldSide.arrow,
  WeldContour contour = WeldContour.none,
  BackingStrip backing = BackingStrip.none,
}) {
  final m = _Mapper(origin, t);
  switch (kind) {
    case WeldKind.fillet:
      // Teownik: pas poziomy + środnik pionowy; strona strzałki = prawa.
      _plate(c, m, const [(-1.5, 0), (1.5, 0), (1.5, 0.45), (-1.5, 0.45)]);
      _plate(c, m, const [(-0.22, -1.3), (0.22, -1.3), (0.22, 0), (-0.22, 0)]);
      if (side != WeldSide.other) _filletTriangle(c, m, 1, contour);
      if (side != WeldSide.arrow) _filletTriangle(c, m, -1, contour);
    case WeldKind.squareButt ||
          WeldKind.singleV ||
          WeldKind.singleBevel ||
          WeldKind.singleVRootFace ||
          WeldKind.singleBevelRootFace ||
          WeldKind.singleU ||
          WeldKind.singleJ:
      _paintGroove(c, m, kind, side, contour, backing);
    case WeldKind.backingRun:
      _paintGroove(
          c, m, WeldKind.singleV, WeldSide.arrow, contour, BackingStrip.none);
      // Podpoina od strony grani — osobny ścieg, ciemniejszy obrys.
      final bead = [
        for (var i = 0; i <= 16; i++)
          (
            0.28 * math.cos(math.pi * i / 16),
            1 + 0.16 * math.sin(math.pi * i / 16)
          ),
      ];
      final p = m.path(bead);
      c.drawPath(p, _fill(const Color(0xFFFFB04D)));
      c.drawPath(p, _line(const Color(0xFF8A4A00), 1.6));
    case WeldKind.plug:
      _plate(c, m, const [(-1.5, 0.5), (1.5, 0.5), (1.5, 1), (-1.5, 1)]);
      _plate(c, m, const [(-1.2, 0), (-0.3, 0), (-0.3, 0.5), (-1.2, 0.5)]);
      _plate(c, m, const [(0.3, 0), (1.2, 0), (1.2, 0.5), (0.3, 0.5)]);
      _weld(c, m, [
        ..._face(-0.3, 0.3, 0, -1, 0.1, overhang: 0.04),
        (0.3, 0.5),
        (0.25, 0.6),
        (-0.25, 0.6),
        (-0.3, 0.5),
      ]);
    case WeldKind.spot:
      _plate(c, m, const [(-1.2, 0), (1.2, 0), (1.2, 0.5), (-1.2, 0.5)]);
      _plate(c, m, const [(-1.5, 0.5), (1.5, 0.5), (1.5, 1), (-1.5, 1)]);
      c.drawOval(
          Rect.fromCenter(
              center: m.o(0, 0.5), width: 0.7 * t, height: 0.36 * t),
          _fill(kArc));
    case WeldKind.seam:
      // Widok z góry: dwie blachy na zakładkę i szereg zachodzących punktów.
      _plate(c, m, const [(-1.5, -0.2), (0.4, -0.2), (0.4, 1.2), (-1.5, 1.2)]);
      _plate(
          c, m, const [(-0.4, -0.05), (1.5, -0.05), (1.5, 1.35), (-0.4, 1.35)]);
      for (var i = 0; i < 6; i++) {
        c.drawCircle(m.o(0, 0.05 + i * 0.22), 0.16 * t, _fill(kArc));
      }
    case WeldKind.surfacing:
      _plate(c, m, const [(-1.5, 0.3), (1.5, 0.3), (1.5, 1), (-1.5, 1)]);
      for (var i = 0; i < 5; i++) {
        final cx = -0.96 + i * 0.48;
        _weld(c, m, [
          for (var k = 0; k <= 12; k++)
            (
              cx + 0.3 * math.cos(math.pi * k / 12),
              0.3 - 0.2 * math.sin(math.pi * k / 12)
            ),
        ]);
      }
    case WeldKind.edge:
      // Dwie blachy ułożone równolegle, spoina na ich czołach.
      _plate(c, m, const [(-0.5, 0), (0, 0), (0, 1.3), (-0.5, 1.3)]);
      _plate(c, m, const [(0, 0), (0.5, 0), (0.5, 1.3), (0, 1.3)]);
      _weld(c, m, [
        ..._face(-0.5, 0.5, 0, -1, 0.22, overhang: 0.02),
        (0.5, 0.12),
        (-0.5, 0.12),
      ]);
  }
}

/// Punkt przekroju, w który celuje grot strzałki (w pikselach).
Offset jointArrowTarget(WeldKind kind, Offset origin, double t) {
  if (kind == WeldKind.fillet) {
    // Środek lica prawej pachwiny (strona strzałki), lekko na zewnątrz.
    return Offset(origin.dx + (0.22 + 0.3) * t, origin.dy - 0.3 * t);
  }
  // ½V, ½Y, J: ukosowana jest prawa blacha — strzałka wskazuje ją
  // (EN ISO 2553: przy jednym brzegu ukosowanym strzałka łamana wskazuje
  // element do ukosowania).
  if (kind == WeldKind.singleBevel ||
      kind == WeldKind.singleBevelRootFace ||
      kind == WeldKind.singleJ) {
    return Offset(origin.dx + 0.95 * t, origin.dy);
  }
  return origin;
}

/// Prostokąt zajmowany przez przekrój (w jednostkach t, względem osi złącza).
Rect jointBounds(WeldKind kind) => switch (kind) {
      WeldKind.fillet => const Rect.fromLTRB(-1.5, -1.3, 1.5, 0.45),
      WeldKind.seam => const Rect.fromLTRB(-1.5, -0.2, 1.5, 1.35),
      WeldKind.edge => const Rect.fromLTRB(-0.6, -0.25, 0.6, 1.3),
      _ => const Rect.fromLTRB(-1.5, -0.3, 1.5, 1.3),
    };

/// Sam przekrój w ramce (ściąga).
class JointSectionPainter extends CustomPainter {
  const JointSectionPainter(this.kind,
      {this.side = WeldSide.arrow,
      this.contour = WeldContour.none,
      this.backing = BackingStrip.none});

  final WeldKind kind;
  final WeldSide side;
  final WeldContour contour;
  final BackingStrip backing;

  @override
  void paint(Canvas canvas, Size size) {
    final b = jointBounds(kind);
    final t =
        math.min((size.width - 8) / b.width, (size.height - 8) / b.height);
    final origin = Offset(
      size.width / 2 - b.center.dx * t,
      size.height / 2 - b.center.dy * t,
    );
    paintJointSection(canvas, origin, t, kind,
        side: side, contour: contour, backing: backing);
  }

  @override
  bool shouldRepaint(covariant JointSectionPainter old) =>
      old.kind != kind ||
      old.side != side ||
      old.contour != contour ||
      old.backing != backing;
}
