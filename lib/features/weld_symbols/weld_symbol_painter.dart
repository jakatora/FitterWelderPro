// Pełny symbol spoiny: strzałka, linia odniesienia (ciągła + ewentualnie
// przerywana), symbol(e) podstawowe, wymiary, symbole uzupełniające i ogon.
// Opcjonalnie z przekrojem złącza, w który celuje strzałka — wtedy widać,
// po której stronie leży spoina.
//
// Grube linie (2,6 px) i jasne kolory na ciemnym tle: rysunek ma być
// czytelny na słońcu. Spoina (symbol podstawowy, metal spoiny w przekroju)
// jest bursztynowa — „gorąca”, reszta w bieli i szarości stali.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/weld_symbols/weld_symbol.dart';
import '../../domain/weld_symbols/weld_symbol_description.dart';
import '../../theme/app_theme.dart';
import 'joint_section.dart';
import 'weld_glyphs.dart';

class WeldSymbolPainter extends CustomPainter {
  WeldSymbolPainter({
    required this.spec,
    required this.en,
    this.showJoint = true,
    this.glyphColor = kArc,
  });

  final WeldSymbolSpec spec;

  /// Format liczb (przecinek / kropka) w wymiarach.
  final bool en;

  /// Rysuj przekrój złącza ze strzałką wskazującą stronę.
  final bool showJoint;

  final Color glyphColor;

  // Wymiary bazowe (w wirtualnym układzie przed skalowaniem do miejsca).
  static const double _h = 26;
  static const double _stroke = 2.6;
  static const double _dashGap = 9;
  static const double _jointT = 34;

  TextPainter _tp(String text, double size, Color color,
      {FontWeight weight = FontWeight.w700}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final notation = notationFor(spec, en: en);
    final layout = spec.layout;
    final kind = spec.kind;

    final sizeTp = notation.size.isEmpty ? null : _tp(notation.size, 17, kText);
    // Przestawna: „n × l”, znak Z przecinający linię, „(e)”.
    final staggered =
        spec.staggered && spec.staggerApplies && spec.intermittentComplete;
    final rightTp = notation.right.isEmpty || staggered
        ? null
        : _tp(notation.right, 17, kText);
    final leadTp = staggered ? _tp(notation.rightLead, 17, kText) : null;
    final gapTp = staggered ? _tp(notation.rightGap, 17, kText) : null;
    const zW = 14.0;
    final tailTp = notation.tail.isEmpty
        ? null
        : _tp(notation.tail, 14, kTextSec, weight: FontWeight.w600);
    final backingApplies =
        spec.backing != BackingStrip.none && spec.backingApplies;
    final backingTp = backingApplies
        ? _tp(spec.backing == BackingStrip.permanent ? 'M' : 'MR', 13, kText)
        : null;

    // ── Układ poziomy (wirtualny) ───────────────────────────────────────────
    final double x0 = showJoint ? 150 : 56; // załamanie strzałki
    final gw = glyphHalfWidth(kind) * _h;
    final leftZone = (spec.fieldWeld || spec.allAround) ? 30.0 : 12.0;
    final sizeW = sizeTp?.width ?? 0;
    final xs = x0 + leftZone + (sizeW > 0 ? sizeW + 7 : 0) + gw + 4;
    final rightW = staggered
        ? leadTp!.width + 6 + zW + 6 + gapTp!.width
        : (rightTp?.width ?? 0);
    final x1 =
        math.max(xs + gw + (rightW > 0 ? rightW + 7 : 0) + 14, xs + gw + 30);
    final needW = tailTp == null ? x1 + 8 : x1 + 18 + tailTp.width + 8;

    final double refY = showJoint ? 48 : 62;
    final double needH = showJoint ? 192 : 128;

    // Dopasuj do miejsca (najwyżej ×1,3 — grube linie nie mogą puchnąć bez
    // końca) i wyśrodkuj.
    final scale =
        math.min(1.3, math.min(size.width / needW, size.height / needH));
    final dx = math.max(0.0, (size.width - needW * scale) / 2);
    final dy = math.max(0.0, (size.height - needH * scale) / 2);

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final line = Paint()
      ..color = kText
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final glyph = glyphStroke(glyphColor, _stroke + 0.4);

    // ── Przekrój złącza i strzałka ─────────────────────────────────────────
    final Offset target;
    if (showJoint) {
      final origin = Offset(kind == WeldKind.fillet ? 62 : 66,
          kind == WeldKind.fillet ? 168 : 140);
      paintJointSection(canvas, origin, _jointT, kind,
          side: spec.side, contour: spec.contour, backing: spec.backing);
      target = jointArrowTarget(kind, origin, _jointT);
    } else {
      target = Offset(x0 - 30, refY + 50);
    }
    // ½V, ½Y, J: strzałka łamana, wskazuje element do ukosowania.
    final Offset? kink = spec.oneMemberPrepared
        ? target + (showJoint ? const Offset(8, -58) : const Offset(4, -26))
        : null;
    _arrow(canvas, Offset(x0, refY), target, line, kink: kink);

    // ── Linia odniesienia ───────────────────────────────────────────────────
    canvas.drawLine(Offset(x0, refY), Offset(x1, refY), line);
    if (layout.dashedLine) {
      _dashed(canvas, Offset(x0 + 2, refY + _dashGap),
          Offset(x1, refY + _dashGap), line);
    }

    // ── Symbole podstawowe, lico, wymiary ─────────────────────────────────
    for (final p in layout.placements) {
      final baseY = p.line == RefLine.dashed ? refY + _dashGap : refY;
      final out = p.position == RefPosition.above ? -1.0 : 1.0;
      final frame = GlyphFrame(Offset(xs, baseY), _h, out);
      paintBasicGlyph(canvas, kind, frame, glyph);
      paintContour(canvas, kind, spec.contour, frame, glyph);
      final cy = baseY + out * _h * 0.5;
      if (sizeTp != null) {
        sizeTp.paint(
            canvas, Offset(xs - gw - 7 - sizeTp.width, cy - sizeTp.height / 2));
      }
      if (rightTp != null) {
        rightTp.paint(canvas, Offset(xs + gw + 7, cy - rightTp.height / 2));
      }
      if (leadTp != null && gapTp != null) {
        leadTp.paint(canvas, Offset(xs + gw + 7, cy - leadTp.height / 2));
        gapTp.paint(
            canvas,
            Offset(
                xs + gw + 7 + leadTp.width + 12 + zW, cy - gapTp.height / 2));
      }
    }
    if (leadTp != null) {
      // Znak Z: górna kreska nad linią, ukośna przez linię, dolna pod nią.
      final zx = xs + gw + 7 + leadTp.width + 6;
      final top = refY - _h * 0.5 - 6, bottom = refY + _h * 0.5 + 6;
      final z = Path()
        ..moveTo(zx, top)
        ..lineTo(zx + zW, top)
        ..lineTo(zx, bottom)
        ..lineTo(zx + zW, bottom);
      canvas.drawPath(z, glyphStroke(kText, _stroke));
    }

    // ── Podkładka M / MR — po przeciwnej stronie linii niż symbol ─────────
    if (backingTp != null && layout.placements.length == 1) {
      final p = layout.placements.single;
      final double boxH = backingTp.height + 4;
      final double boxW = backingTp.width + 12;
      final Rect box;
      if (p.line == RefLine.dashed) {
        // Symbol pod linią przerywaną → prostokąt nad linią ciągłą.
        box = Rect.fromLTWH(xs - boxW / 2, refY - 4 - boxH, boxW, boxH);
      } else if (p.position == RefPosition.above) {
        final under = layout.dashedLine ? refY + _dashGap : refY;
        box = Rect.fromLTWH(xs - boxW / 2, under + 4, boxW, boxH);
      } else {
        box = Rect.fromLTWH(xs - boxW / 2, refY - 4 - boxH, boxW, boxH);
      }
      canvas.drawRect(box, line);
      backingTp.paint(
          canvas,
          Offset(box.center.dx - backingTp.width / 2,
              box.center.dy - backingTp.height / 2));
    }

    // ── Dookoła i montażowa — na załamaniu strzałki ───────────────────────
    if (spec.allAround) {
      canvas.drawCircle(Offset(x0, refY), 8, line);
    }
    if (spec.fieldWeld) {
      final top = refY - _h * 1.3;
      canvas.drawLine(Offset(x0, refY), Offset(x0, top), line);
      final flag = Path()
        ..moveTo(x0, top)
        ..lineTo(x0 + _h * 0.85, top + _h * 0.27)
        ..lineTo(x0, top + _h * 0.54)
        ..close();
      canvas.drawPath(flag, Paint()..color = kText);
    }

    // ── Ogon ────────────────────────────────────────────────────────────────
    if (tailTp != null) {
      canvas.drawLine(Offset(x1, refY), Offset(x1 + 12, refY - 11), line);
      canvas.drawLine(Offset(x1, refY), Offset(x1 + 12, refY + 11), line);
      tailTp.paint(canvas, Offset(x1 + 18, refY - tailTp.height / 2));
    }

    canvas.restore();
  }

  void _arrow(Canvas c, Offset from, Offset to, Paint paint, {Offset? kink}) {
    final start = kink ?? from;
    if (kink != null) c.drawLine(from, kink, paint);
    final dir = (to - start) / (to - start).distance;
    const head = 13.0;
    final base = to - dir * head;
    c.drawLine(start, base, paint);
    final nrm = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(base.dx + nrm.dx * 5.5, base.dy + nrm.dy * 5.5)
      ..lineTo(base.dx - nrm.dx * 5.5, base.dy - nrm.dy * 5.5)
      ..close();
    c.drawPath(path, Paint()..color = paint.color);
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint paint) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    const dash = 8.0, gap = 6.0;
    var d = 0.0;
    while (d < len) {
      final e = math.min(d + dash, len);
      c.drawLine(a + dir * d, a + dir * e, paint);
      d = e + gap;
    }
  }

  @override
  bool shouldRepaint(covariant WeldSymbolPainter old) =>
      old.spec != spec ||
      old.en != en ||
      old.showJoint != showJoint ||
      old.glyphColor != glyphColor;
}

/// Sam symbol podstawowy na krótkim odcinku linii (ściąga).
class GlyphOnLinePainter extends CustomPainter {
  const GlyphOnLinePainter(this.kind, {this.contour = WeldContour.none});

  final WeldKind kind;
  final WeldContour contour;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = glyphExtent(kind, contour);
    final h = math.min(size.height * 0.62 / extent, size.width * 0.38);
    final y = size.height * 0.5 + h * extent * 0.5;
    final line = Paint()
      ..color = kText
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(size.width * 0.08, y), Offset(size.width * 0.92, y), line);
    final frame = GlyphFrame(Offset(size.width / 2, y), h, -1);
    final paint = glyphStroke(kArc, 3);
    paintBasicGlyph(canvas, kind, frame, paint);
    paintContour(canvas, kind, contour, frame, paint);
  }

  @override
  bool shouldRepaint(covariant GlyphOnLinePainter old) =>
      old.kind != kind || old.contour != contour;
}

/// Ścieg od strony grani: spoina na V po stronie strzałki (na linii ciągłej)
/// i półkole po stronie przeciwnej (pod linią przerywaną) — system A.
class BackRunSymbolPainter extends CustomPainter {
  const BackRunSymbolPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const needW = 230.0, needH = 128.0;
    final scale =
        math.min(1.0, math.min(size.width / needW, size.height / needH));
    canvas.save();
    canvas.translate(math.max(0.0, (size.width - needW * scale) / 2),
        math.max(0.0, (size.height - needH * scale) / 2));
    canvas.scale(scale);
    const x0 = 56.0, x1 = 200.0, refY = 56.0, xs = 128.0, h = 26.0;
    final line = Paint()
      ..color = kText
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(x0, refY), const Offset(x1, refY), line);
    var d = x0 + 2;
    while (d < x1) {
      canvas.drawLine(
          Offset(d, refY + 9), Offset(math.min(d + 8, x1), refY + 9), line);
      d += 14;
    }
    // Strzałka.
    const tip = Offset(x0 - 30, refY + 56);
    final dir = (tip - const Offset(x0, refY)) /
        (tip - const Offset(x0, refY)).distance;
    final base = tip - dir * 13;
    canvas.drawLine(const Offset(x0, refY), base, line);
    final nrm = Offset(-dir.dy, dir.dx);
    canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + nrm.dx * 5.5, base.dy + nrm.dy * 5.5)
          ..lineTo(base.dx - nrm.dx * 5.5, base.dy - nrm.dy * 5.5)
          ..close(),
        Paint()..color = kText);
    final glyph = glyphStroke(kArc, 3);
    paintBasicGlyph(canvas, WeldKind.singleV,
        const GlyphFrame(Offset(xs, refY), h, -1), glyph);
    paintBasicGlyph(canvas, WeldKind.backingRun,
        const GlyphFrame(Offset(xs, refY + 9), h, 1), glyph);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BackRunSymbolPainter old) => false;
}
