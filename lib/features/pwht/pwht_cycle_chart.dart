// Wykres cyklu PWHT temperatura–czas (CustomPaint).
//
// Oś czasu obejmuje TYLKO część kontrolowaną cyklu (od temperatury kontrolnej
// w górę, wytrzymanie, w dół do temperatury kontrolnej). Nagrzewanie poniżej
// temperatury kontrolnej i swobodne chłodzenie są narysowane przerywaną linią
// na marginesach — poza skalą czasu, bo zależą od pieca / maty / izolacji.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/pwht/pwht_cycle.dart';
import '../../theme/app_theme.dart';

class PwhtCycleChart extends StatelessWidget {
  const PwhtCycleChart({
    super.key,
    required this.cycle,
    required this.holdMinC,
    required this.holdMaxC,
    required this.semanticLabel,
    this.height = 220,
  });

  final PwhtCycle cycle;

  /// Zakres temperatury wytrzymania z tabeli normy — pas na wykresie.
  final int holdMinC;
  final int holdMaxC;

  /// Opis wykresu dla czytnika ekranu (dwujęzyczny — z ekranu).
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: PwhtCyclePainter(
              cycle: cycle,
              holdMinC: holdMinC,
              holdMaxC: holdMaxC,
              textScale: MediaQuery.textScalerOf(context).scale(1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Malarz wykresu — publiczny, żeby test mógł sprawdzić skale osi.
class PwhtCyclePainter extends CustomPainter {
  PwhtCyclePainter({
    required this.cycle,
    required this.holdMinC,
    required this.holdMaxC,
    this.textScale = 1,
  });

  final PwhtCycle cycle;
  final int holdMinC;
  final int holdMaxC;
  final double textScale;

  /// Temperatura „startowa” stubów poza skalą (otoczenie) — tylko rysunek.
  static const double _ambientC = 20;

  /// Górna granica osi temperatury: wielokrotność 100 °C nad pasem wytrzymania.
  static double topTempC(int holdMaxC, int holdTempC) =>
      ((math.max(holdMaxC, holdTempC) + 50) / 100).ceil() * 100.0;

  /// „Ładny” krok osi czasu dla całkowitego czasu [h].
  static double timeStepHours(double totalHours) {
    const steps = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
    for (final s in steps) {
      if (totalHours / s <= 8) return s;
    }
    return 100;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final labelSize = 10.0 * textScale.clamp(1.0, 1.6);
    final left = 34.0 + 8 * (textScale - 1).clamp(0, 1);
    final bottom = 18.0 + labelSize;
    const top = 8.0;
    const right = 8.0;
    const stub = 22.0; // margines na odcinki poza skalą czasu

    final plot = Rect.fromLTRB(
      left + stub,
      top,
      size.width - right - stub,
      size.height - bottom,
    );
    if (plot.width <= 10 || plot.height <= 10) return;

    final total = cycle.totalHours <= 0 ? 1.0 : cycle.totalHours;
    final yTop = topTempC(holdMaxC, cycle.holdTempC);

    double x(double h) => plot.left + plot.width * (h / total);
    double y(double c) => plot.bottom - plot.height * (c / yTop);

    final gridPaint = Paint()
      ..color = kBorder
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      color: kTextMut,
      fontSize: labelSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    void label(String text, Offset anchor, {bool alignRight = false}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = alignRight ? anchor.dx - tp.width : anchor.dx - tp.width / 2;
      tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
    }

    // Siatka temperatury co 100 °C.
    for (var c = 0.0; c <= yTop + 0.1; c += 100) {
      final yy = y(c);
      canvas.drawLine(Offset(plot.left - stub, yy),
          Offset(plot.right + stub, yy), gridPaint);
      label(c.toStringAsFixed(0), Offset(left - 4, yy), alignRight: true);
    }

    // Siatka czasu.
    final step = timeStepHours(total);
    for (var h = 0.0; h <= total + 1e-9; h += step) {
      final xx = x(h);
      canvas.drawLine(Offset(xx, plot.top), Offset(xx, plot.bottom), gridPaint);
      label('${_fmtHours(h)} h', Offset(xx, plot.bottom + 6 + labelSize / 2));
    }

    // Pas temperatury wytrzymania z tabeli normy.
    canvas.drawRect(
      Rect.fromLTRB(plot.left - stub, y(holdMaxC.toDouble()), plot.right + stub,
          y(holdMinC.toDouble())),
      Paint()..color = kArc.withValues(alpha: 0.12),
    );

    // Temperatura kontrolna — przerywana.
    _dashedLine(
      canvas,
      Offset(plot.left - stub, y(cycle.controlTempC.toDouble())),
      Offset(plot.right + stub, y(cycle.controlTempC.toDouble())),
      Paint()
        ..color = kTextMut
        ..strokeWidth = 1,
    );

    // Odcinki poza skalą czasu (niekontrolowane) — przerywane.
    final stubPaint = Paint()
      ..color = kTextMut
      ..strokeWidth = 1.5;
    _dashedLine(canvas, Offset(plot.left - stub, y(_ambientC)),
        Offset(plot.left, y(cycle.controlTempC.toDouble())), stubPaint);
    _dashedLine(canvas, Offset(plot.right, y(cycle.controlTempC.toDouble())),
        Offset(plot.right + stub, y(_ambientC)), stubPaint);

    // Część kontrolowana: rampy bielą, wytrzymanie bursztynem.
    final p = cycle.points;
    final rampPaint = Paint()
      ..color = kText
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final holdPaint = Paint()
      ..color = kArc
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    Offset o(PwhtCyclePoint q) => Offset(x(q.hours), y(q.tempC));
    canvas.drawLine(o(p[0]), o(p[1]), rampPaint);
    canvas.drawLine(o(p[2]), o(p[3]), rampPaint);
    canvas.drawLine(o(p[1]), o(p[2]), holdPaint);
  }

  static String _fmtHours(double h) =>
      h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  static void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    var t = 0.0;
    while (t < len) {
      final end = math.min(t + dash, len);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  @override
  bool shouldRepaint(PwhtCyclePainter old) =>
      old.cycle.holdTempC != cycle.holdTempC ||
      old.cycle.controlTempC != cycle.controlTempC ||
      old.cycle.totalHours != cycle.totalHours ||
      old.cycle.rampUpHours != cycle.rampUpHours ||
      old.holdMinC != holdMinC ||
      old.holdMaxC != holdMaxC ||
      old.textScale != textScale;
}
