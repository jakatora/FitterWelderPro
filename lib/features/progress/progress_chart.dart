// Wykres dzienny postępu: słupki DI (albo spoin) dzień po dniu, linia
// średniego tempa. CustomPaint — bez pakietów wykresów.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/progress/progress_filter.dart';
import '../../domain/progress/progress_report.dart';
import '../../domain/progress/weld_progress.dart';
import '../../domain/progress/work_calendar.dart';
import '../../theme/app_theme.dart';

/// Kolor słupków dni z okresu. Bursztyn zostaje dla wyniku głównego.
const Color kProgressBar = Color(0xFF4A9EFF);

class ProgressDailyChart extends StatelessWidget {
  /// Każdy dzień okna, rosnąco (zera też).
  final List<DayProgress> days;

  /// DI (true) albo liczba spoin (false).
  final bool showDi;

  /// Średnie tempo w tej samej jednostce — linia przerywana; null = bez linii.
  final double? average;

  /// Wybrany okres; dni spoza niego są wygaszone.
  final DayRange? highlight;

  final WorkWeek week;
  final bool en;

  const ProgressDailyChart({
    super.key,
    required this.days,
    required this.showDi,
    required this.week,
    required this.en,
    this.average,
    this.highlight,
  });

  double _value(DayProgress d) => showDi ? d.di : d.welds.toDouble();

  @override
  Widget build(BuildContext context) {
    final total = days.fold<double>(0, (s, d) => s + _value(d));
    final unit = showDi ? 'DI' : (en ? 'welds' : 'spoin');
    final semantics = days.isEmpty
        ? ''
        : '${en ? 'Daily chart' : 'Wykres dzienny'}: '
            '${dayLabel(days.first.day, en: en)} – '
            '${dayLabel(days.last.day, en: en)}, '
            '${progressNum(total, en: en)} $unit';
    return Semantics(
      label: semantics,
      child: SizedBox(
        height: 170,
        width: double.infinity,
        child: CustomPaint(
          painter: _DailyBarsPainter(
            values: [for (final d in days) _value(d)],
            days: [for (final d in days) d.day],
            inRange: [
              for (final d in days) highlight?.contains(d.day) ?? true,
            ],
            working: [for (final d in days) week.isWorkingDay(d.day)],
            average: average,
            en: en,
            decimals: showDi ? 1 : 0,
          ),
        ),
      ),
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  final List<double> values;
  final List<DateTime> days;
  final List<bool> inRange;
  final List<bool> working;
  final double? average;
  final bool en;
  final int decimals;

  _DailyBarsPainter({
    required this.values,
    required this.days,
    required this.inRange,
    required this.working,
    required this.average,
    required this.en,
    required this.decimals,
  });

  static const double _labelH = 16;
  static const double _topPad = 16;

  void _text(Canvas canvas, String s, Offset center,
      {Color color = kTextMut, double size = 10, FontWeight? weight}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size,
              color: color,
              fontWeight: weight,
              fontFeatures: const [FontFeature.tabularFigures()])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    final chartH = size.height - _labelH - _topPad;
    final baseY = _topPad + chartH;
    final maxV = math.max(
        values.fold<double>(0, math.max), (average ?? 0)).toDouble();
    final slot = size.width / n;
    final barW = math.max(2.0, slot * 0.68);

    // Linia bazowa.
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY),
        Paint()
          ..color = kBorder
          ..strokeWidth = 1);

    final showValues = n <= 14;
    final labelEvery = n <= 14 ? 1 : (n <= 21 ? 2 : 3);

    for (var i = 0; i < n; i++) {
      final v = values[i];
      final cx = slot * i + slot / 2;
      final h = maxV <= 0 ? 0.0 : (v / maxV) * chartH;
      if (v > 0) {
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barW / 2, baseY - math.max(h, 2), barW,
              math.max(h, 2)),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(
            rect,
            Paint()
              ..color = inRange[i]
                  ? kProgressBar
                  : kProgressBar.withValues(alpha: 0.3));
        if (showValues) {
          _text(
            canvas,
            progressNum(v, en: en, decimals: decimals),
            Offset(cx, baseY - math.max(h, 2) - 8),
            color: inRange[i] ? kText : kTextMut,
            size: 9.5,
            weight: FontWeight.w700,
          );
        }
      }
      final d = days[i];
      if (i % labelEvery == 0 || d.day == 1 || i == n - 1) {
        _text(
          canvas,
          '${d.day}',
          Offset(cx, baseY + _labelH / 2 + 1),
          color: working[i] ? kTextSec : kTextMut.withValues(alpha: 0.6),
          size: 10,
          weight: working[i] ? FontWeight.w600 : FontWeight.w400,
        );
      }
    }

    final avg = average;
    if (avg != null && avg > 0 && maxV > 0) {
      final y = baseY - (avg / maxV) * chartH;
      final paint = Paint()
        ..color = kTextSec
        ..strokeWidth = 1.2;
      const dash = 5.0, gap = 4.0;
      for (var x = 0.0; x < size.width; x += dash + gap) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DailyBarsPainter old) =>
      old.values != values ||
      old.days != days ||
      old.inRange != inRange ||
      old.average != average ||
      old.en != en;
}
