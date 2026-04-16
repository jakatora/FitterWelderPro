import 'package:flutter/material.dart';

/// Proste ikonki "izometryczne" rysowane wektorowo.
/// Cel: brak assetów (mniej problemów na Windows) + czytelne rozróżnienie elementów.
class ComponentIcon extends StatelessWidget {
  final String type;
  final double size;

  const ComponentIcon({super.key, required this.type, this.size = 28});

  @override
  Widget build(BuildContext context) {
    // Rura ma inny kolor, żeby była czytelna na liście i w sekwencji.
    final cs = Theme.of(context).colorScheme;
    final iconColor = type == 'PIPE' ? cs.primary : cs.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ComponentPainter(type: type, color: iconColor),
      ),
    );
  }
}

class _ComponentPainter extends CustomPainter {
  final String type;
  final Color color;

  _ComponentPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = (size.shortestSide * 0.10).clamp(1.2, 3.2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final m = size.shortestSide * 0.18;

    // Helpers
    Offset o(double x, double y) => Offset(x, y);

    switch (type) {
      case 'PIPE':
        // prosta rura
        canvas.drawLine(o(m, h * 0.55), o(w - m, h * 0.55), p);
        canvas.drawLine(o(m, h * 0.35), o(w - m, h * 0.35), p);
        break;

      case 'ELB90':
        // kolano 90 (L)
        final path = Path()
          ..moveTo(m, h - m)
          ..lineTo(m, h * 0.45)
          ..lineTo(w - m, h * 0.45);
        canvas.drawPath(path, p);
        break;

      case 'ELB45':
        // kolano 45 (łamana)
        final path = Path()
          ..moveTo(m, h - m)
          ..lineTo(w * 0.45, h * 0.55)
          ..lineTo(w - m, h * 0.35);
        canvas.drawPath(path, p);
        break;

      case 'TEE':
        // trójnik (T)
        canvas.drawLine(o(m, h * 0.50), o(w - m, h * 0.50), p);
        canvas.drawLine(o(w * 0.55, h * 0.20), o(w * 0.55, h - m), p);
        break;

      case 'REDUCER':
        // redukcja (trapez)
        final topY = h * 0.33;
        final botY = h * 0.67;
        final leftX = m;
        final rightX = w - m;
        final midX = w * 0.55;
        final path = Path()
          ..moveTo(leftX, botY)
          ..lineTo(midX, topY)
          ..lineTo(rightX, topY)
          ..lineTo(rightX, botY)
          ..close();
        canvas.drawPath(path, p);
        break;

      case 'FLANGE':
        // flansza (dwie kreski + rura)
        canvas.drawLine(o(m, h * 0.50), o(w - m, h * 0.50), p);
        canvas.drawLine(o(w * 0.35, h * 0.28), o(w * 0.35, h * 0.72), p);
        canvas.drawLine(o(w * 0.55, h * 0.28), o(w * 0.55, h * 0.72), p);
        break;

      case 'VALVE':
        // zawór ("motylek")
        final cx = w * 0.5;
        final cy = h * 0.5;
        canvas.drawLine(o(m, cy), o(w - m, cy), p);
        final path = Path()
          ..moveTo(cx - m, cy)
          ..lineTo(cx, cy - m)
          ..lineTo(cx + m, cy)
          ..lineTo(cx, cy + m)
          ..close();
        canvas.drawPath(path, p);
        break;

      default:
        // other
        canvas.drawCircle(o(w * 0.5, h * 0.5), size.shortestSide * 0.28, p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ComponentPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
