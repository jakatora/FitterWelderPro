// Rysunki zakładki „Wymiary”: a i z w przekroju pachwiny oraz układ odcinków
// spoiny przerywanej (zwykłej i przestawnej).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'joint_section.dart' show kSectionPlate, kSectionPlateEdge;

TextPainter _label(String text, {double size = 15, Color color = kText}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

Paint _thin(Color c) => Paint()
  ..color = c
  ..strokeWidth = 1.6
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

void _tick(Canvas c, Offset p, Offset dir, Paint paint) {
  final n = Offset(-dir.dy, dir.dx) * 5;
  c.drawLine(p - n, p + n, paint);
}

/// Przekrój pachwiny równoramiennej z zaznaczonymi z (boki) i a (wysokość
/// trójkąta do przeciwprostokątnej).
class FilletDimensionPainter extends CustomPainter {
  const FilletDimensionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 2.6, size.height / 2.2);
    final origin = Offset(size.width / 2 - 0.55 * s, size.height * 0.70);
    Offset o(double x, double y) =>
        Offset(origin.dx + x * s, origin.dy - y * s);

    final plate = Paint()..color = kSectionPlate;
    final edge = _thin(kSectionPlateEdge);
    // Pas poziomy i środnik pionowy (po lewej).
    final flange = Rect.fromPoints(o(-0.45, 0), o(1.6, -0.22));
    final web = Rect.fromPoints(o(-0.45, 1.5), o(0, 0));
    canvas.drawRect(flange, plate);
    canvas.drawRect(flange, edge);
    canvas.drawRect(web, plate);
    canvas.drawRect(web, edge);

    // Spoina: boki z = 1 jednostka.
    final weld = Path()
      ..moveTo(o(0, 0).dx, o(0, 0).dy)
      ..lineTo(o(0, 1).dx, o(0, 1).dy)
      ..lineTo(o(1, 0).dx, o(1, 0).dy)
      ..close();
    canvas.drawPath(weld, Paint()..color = kArc.withValues(alpha: 0.85));
    canvas.drawPath(weld, _thin(const Color(0xFFFFC27A)));

    final dim = _thin(kText);
    // a: od narożnika prostopadle do przeciwprostokątnej.
    final aEnd = o(0.5, 0.5);
    canvas.drawLine(o(0, 0), aEnd, dim);
    _tick(canvas, aEnd, const Offset(1, -1) / math.sqrt2, dim);
    // Etykieta wewnątrz trójkąta — ciemna na bursztynie (kontrast).
    final aTp = _label('a', color: kOnArc);
    aTp.paint(canvas, o(0.36, 0.2) - Offset(0, aTp.height / 2));

    // z poziomo — pod pasem.
    const y0 = -0.38;
    canvas.drawLine(o(0, y0), o(1, y0), dim);
    _tick(canvas, o(0, y0), const Offset(1, 0), dim);
    _tick(canvas, o(1, y0), const Offset(1, 0), dim);
    canvas.drawLine(o(1, 0), o(1, y0 + 0.05), _thin(kTextMut));
    final z1 = _label('z');
    z1.paint(canvas, o(0.5, y0) - Offset(z1.width / 2, -3));

    // z pionowo — po prawej stronie spoiny, równolegle do środnika.
    const x0 = 1.25;
    canvas.drawLine(o(x0, 0), o(x0, 1), dim);
    _tick(canvas, o(x0, 0), const Offset(0, 1), dim);
    _tick(canvas, o(x0, 1), const Offset(0, 1), dim);
    canvas.drawLine(o(0, 1), o(x0 + 0.05, 1), _thin(kTextMut));
    final z2 = _label('z');
    z2.paint(canvas, o(x0, 0.5) + Offset(6, -z2.height / 2));
  }

  @override
  bool shouldRepaint(covariant FilletDimensionPainter old) => false;
}

/// Widok z góry na złącze ze spoiną przerywaną: n odcinków po l, odstęp e.
/// [staggered] — odcinki po drugiej stronie przesunięte o połowę podziałki
/// (naprzeciw przerw).
class IntermittentPainter extends CustomPainter {
  const IntermittentPainter({
    required this.count,
    required this.length,
    required this.gap,
    this.staggered = false,
  });

  final int count;
  final double length;
  final double gap;
  final bool staggered;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = length + gap;
    final total =
        count * length + (count - 1) * gap + (staggered ? pitch / 2 : 0);
    const margin = 16.0;
    final k = (size.width - 2 * margin) / total;
    final midY = size.height * (staggered ? 0.55 : 0.62);

    // Krawędź złącza (np. środnik widziany z góry).
    final joint = Paint()
      ..color = kSectionPlate
      ..style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromLTRB(margin - 6, midY - 5, size.width - margin + 6, midY + 5),
        joint);

    final weld = Paint()..color = kArc;
    for (var i = 0; i < count; i++) {
      final x = margin + i * pitch * k;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, midY - 15, length * k, 10),
              const Radius.circular(3)),
          weld);
      if (staggered) {
        final xs = x + pitch / 2 * k;
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(xs, midY + 5, length * k, 10),
                const Radius.circular(3)),
            weld);
      }
    }

    // Wymiary l i e nad pierwszym odcinkiem i pierwszą przerwą.
    final dim = _thin(kText);
    final yDim = midY - 30;
    final xa = margin, xb = margin + length * k, xc = margin + pitch * k;
    canvas.drawLine(Offset(xa, yDim), Offset(xb, yDim), dim);
    canvas.drawLine(Offset(xb, yDim), Offset(xc, yDim), dim);
    for (final x in [xa, xb, xc]) {
      canvas.drawLine(
          Offset(x, yDim - 6), Offset(x, midY - 16), _thin(kTextMut));
      _tick(canvas, Offset(x, yDim), const Offset(1, 0), dim);
    }
    final l = _label('l');
    l.paint(canvas, Offset((xa + xb) / 2 - l.width / 2, yDim - l.height - 2));
    final e = _label('e');
    e.paint(canvas, Offset((xb + xc) / 2 - e.width / 2, yDim - e.height - 2));
  }

  @override
  bool shouldRepaint(covariant IntermittentPainter old) =>
      old.count != count ||
      old.length != length ||
      old.gap != gap ||
      old.staggered != staggered;
}
