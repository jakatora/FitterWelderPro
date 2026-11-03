import 'package:flutter/material.dart';

/// Small, original technical illustrations for the main work areas.
enum IndustrialArtworkKind {
  fitter, welder, cutting, branch, route, table, flange, calculator,
  inspection, finishing, costing, helmet, electrode, filler, orbital,
  tank, blueprint, scanner, library, measurement, bevel, assistant,
  elbowMeasure, elbowCut, elbowRotate, insert, reducer, mitre, bender, cone,
  saddle, saddleTemplate, rollingOffset, pipeSlope, slopeCut, expansion,
  pipeDiameter, pipeWall, pipeWeight, steelProfiles, sanitaryPipe,
  unitConversion, dictionary, pipeSupport, torque, flangeCheck, boltKit,
  weldHeat, gasTimer, heatTreatment, weldStrength, powerSource,
  weldPasses, weldDistortion, coolingTime,
}

class IndustrialArtwork extends StatelessWidget {
  const IndustrialArtwork({super.key, required this.kind, this.size = 52, this.glyph});
  final IndustrialArtworkKind kind;
  final double size;
  final IconData? glyph;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.square(
            dimension: size,
            child: Stack(children: [
              CustomPaint(size: Size.square(size), painter: _IndustrialPainter(kind)),
              if (glyph != null)
                Positioned(right: 1, bottom: 1,
                  child: Container(
                    padding: EdgeInsets.all(size * 0.035),
                    decoration: BoxDecoration(color: const Color(0xff102230),
                      borderRadius: BorderRadius.circular(5)),
                    child: Icon(glyph, color: const Color(0xffffc46a), size: size * 0.27),
                  )),
            ]),
          ),
        ),
      );
}

class _IndustrialPainter extends CustomPainter {
  const _IndustrialPainter(this.kind);
  final IndustrialArtworkKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xff243547), Color(0xff101b29)],
    ).createShader(bounds));
    final grid = Paint()..color = const Color(0x244f7d99)..strokeWidth = 0.8;
    for (var n = 15.0; n < 100; n += 20) {
      canvas.drawLine(Offset(n, 0), Offset(n, 100), grid);
      canvas.drawLine(Offset(0, n), Offset(100, n), grid);
    }
    if (kind == IndustrialArtworkKind.fitter) {
      final elbow = Path()..moveTo(12, 68)..lineTo(42, 68)
        ..quadraticBezierTo(70, 68, 70, 40)..lineTo(70, 13);
      canvas.drawPath(elbow, Paint()..color = const Color(0xff647a8c)
        ..style = PaintingStyle.stroke..strokeWidth = 24..strokeCap = StrokeCap.butt);
      canvas.drawPath(elbow, Paint()..color = const Color(0xffc1d1d9)
        ..style = PaintingStyle.stroke..strokeWidth = 15..strokeCap = StrokeCap.butt);
      canvas.drawPath(elbow, Paint()..color = const Color(0xffe5edf0)
        ..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.butt);
      final seam = Paint()..color = const Color(0xffffa939)..strokeWidth = 3;
      canvas.drawLine(const Offset(31, 56), const Offset(31, 80), seam);
      canvas.drawLine(const Offset(58, 31), const Offset(82, 31), seam);
      canvas.drawCircle(const Offset(70, 13), 4, Paint()..color = const Color(0xff314958));
    } else if (kind == IndustrialArtworkKind.welder) {
      final plate = Path()..moveTo(14, 76)..lineTo(77, 76)..lineTo(88, 84)
        ..lineTo(25, 84)..close();
      canvas.drawPath(plate, Paint()..color = const Color(0xff8da3b0));
      canvas.drawLine(const Offset(25, 77), const Offset(75, 77),
          Paint()..color = const Color(0xffffa939)..strokeWidth = 4..strokeCap = StrokeCap.round);
      final torch = Path()..moveTo(37, 15)..lineTo(48, 12)..lineTo(64, 48)
        ..lineTo(56, 52)..close();
      canvas.drawPath(torch, Paint()..color = const Color(0xffb8ccd5));
      canvas.drawPath(torch, Paint()..color = const Color(0xff506778)
        ..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawLine(const Offset(58, 50), const Offset(63, 64),
          Paint()..color = const Color(0xffffc36a)..strokeWidth = 4..strokeCap = StrokeCap.round);
      final spark = Paint()..color = const Color(0xffffbb5d)..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final points in [
        [const Offset(65, 68), const Offset(72, 63)],
        [const Offset(67, 72), const Offset(77, 72)],
        [const Offset(57, 68), const Offset(51, 62)],
      ]) {
        canvas.drawLine(points[0], points[1], spark);
      }
      canvas.drawCircle(const Offset(63, 70), 4, Paint()..color = const Color(0xffffe5a6));
    } else {
      _paintCategory(canvas);
    }
    canvas.restore();
  }

  void _paintCategory(Canvas canvas) {
    final steel = Paint()..color = const Color(0xffb8ccd5)
      ..style = PaintingStyle.stroke..strokeWidth = 7
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final amber = Paint()..color = const Color(0xffffad43)
      ..style = PaintingStyle.stroke..strokeWidth = 4
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case IndustrialArtworkKind.cutting:
        canvas.drawLine(const Offset(15, 65), const Offset(85, 65), steel..strokeWidth = 15);
        canvas.drawCircle(const Offset(55, 40), 18, amber..strokeWidth = 5);
        canvas.drawLine(const Offset(55, 20), const Offset(55, 60), steel..strokeWidth = 3);
      case IndustrialArtworkKind.branch:
        canvas.drawLine(const Offset(15, 69), const Offset(85, 69), steel..strokeWidth = 16);
        canvas.drawLine(const Offset(50, 65), const Offset(50, 20), steel);
        canvas.drawLine(const Offset(41, 50), const Offset(59, 50), amber);
      case IndustrialArtworkKind.route:
        final route = Path()..moveTo(17, 75)..lineTo(40, 75)..lineTo(40, 45)
          ..lineTo(74, 45)..lineTo(74, 23);
        canvas.drawPath(route, steel..strokeWidth = 12);
        canvas.drawLine(const Offset(25, 88), const Offset(79, 69), amber);
      case IndustrialArtworkKind.table:
      case IndustrialArtworkKind.calculator:
      case IndustrialArtworkKind.costing:
        final border = RRect.fromRectAndRadius(const Rect.fromLTWH(22, 14, 56, 72), const Radius.circular(6));
        canvas.drawRRect(border, steel..strokeWidth = 4);
        canvas.drawLine(const Offset(29, 31), const Offset(71, 31), amber);
        for (var row = 0; row < 3; row++) {
          for (var col = 0; col < (kind == IndustrialArtworkKind.costing ? 2 : 3); col++) {
            canvas.drawRRect(RRect.fromRectAndRadius(
                Rect.fromLTWH(30 + col * 15.0, 40 + row * 13.0, 8, 6), const Radius.circular(2)),
                Paint()..color = const Color(0xffb8ccd5));
          }
        }
      case IndustrialArtworkKind.flange:
        canvas.drawCircle(const Offset(50, 50), 29, steel..strokeWidth = 9);
        canvas.drawCircle(const Offset(50, 50), 13, amber..strokeWidth = 4);
        for (final p in [const Offset(50, 27), const Offset(73, 50),
          const Offset(50, 73), const Offset(27, 50)]) {
          canvas.drawCircle(p, 3, Paint()..color = const Color(0xffffad43));
        }
      case IndustrialArtworkKind.inspection:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(19, 18, 45, 58),
          const Radius.circular(4)), steel..strokeWidth = 4);
        canvas.drawLine(const Offset(28, 32), const Offset(54, 32), amber);
        canvas.drawLine(const Offset(28, 44), const Offset(48, 44), amber);
        canvas.drawCircle(const Offset(65, 65), 13, steel..strokeWidth = 5);
        canvas.drawLine(const Offset(74, 74), const Offset(85, 85), amber..strokeWidth = 5);
      case IndustrialArtworkKind.finishing:
        canvas.drawCircle(const Offset(47, 53), 24, steel..strokeWidth = 7);
        canvas.drawCircle(const Offset(47, 53), 8, amber);
        canvas.drawLine(const Offset(66, 35), const Offset(78, 23), steel..strokeWidth = 8);
        canvas.drawLine(const Offset(73, 66), const Offset(83, 73), amber);
      case IndustrialArtworkKind.weldHeat:
        canvas.drawLine(const Offset(18, 73), const Offset(82, 73), steel..strokeWidth = 10);
        canvas.drawLine(const Offset(29, 73), const Offset(71, 73), amber..strokeWidth = 5);
        final flame = Path()..moveTo(50, 60)..cubicTo(28, 51, 40, 34, 48, 21)
          ..cubicTo(48, 35, 67, 35, 62, 49)..quadraticBezierTo(60, 57, 50, 60)..close();
        canvas.drawPath(flame, amber..strokeWidth = 4);
      case IndustrialArtworkKind.gasTimer:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 28, 32, 50),
          const Radius.circular(10)), steel..strokeWidth = 5);
        canvas.drawLine(const Offset(32, 27), const Offset(32, 20), steel..strokeWidth = 4);
        canvas.drawLine(const Offset(26, 20), const Offset(39, 20), steel);
        canvas.drawLine(const Offset(27, 48), const Offset(49, 48), amber..strokeWidth = 3);
        canvas.drawCircle(const Offset(68, 57), 14, amber..strokeWidth = 4);
        canvas.drawLine(const Offset(68, 57), const Offset(68, 48), steel..strokeWidth = 3);
        canvas.drawLine(const Offset(68, 57), const Offset(74, 61), steel);
      case IndustrialArtworkKind.heatTreatment:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 24, 60, 54),
          const Radius.circular(5)), steel..strokeWidth = 5);
        canvas.drawLine(const Offset(24, 65), const Offset(76, 65), steel..strokeWidth = 3);
        for (final x in [35.0, 50.0, 65.0]) {
          final wave = Path()..moveTo(x, 57)..quadraticBezierTo(x - 6, 49, x, 42)
            ..quadraticBezierTo(x + 6, 35, x, 28);
          canvas.drawPath(wave, amber..strokeWidth = 3);
        }
      case IndustrialArtworkKind.weldStrength:
        canvas.drawLine(const Offset(25, 24), const Offset(25, 75), steel..strokeWidth = 10);
        canvas.drawLine(const Offset(25, 75), const Offset(78, 75), steel);
        final weld = Path()..moveTo(31, 67)..lineTo(47, 67)..lineTo(31, 50)..close();
        canvas.drawPath(weld, Paint()..color = const Color(0xffffad43));
        canvas.drawLine(const Offset(58, 23), const Offset(58, 50), amber..strokeWidth = 4);
        canvas.drawLine(const Offset(50, 31), const Offset(58, 23), amber);
        canvas.drawLine(const Offset(66, 31), const Offset(58, 23), amber);
      case IndustrialArtworkKind.powerSource:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 17, 56, 68),
          const Radius.circular(7)), steel..strokeWidth = 5);
        canvas.drawCircle(const Offset(50, 31), 6, amber..strokeWidth = 3);
        final bolt = Path()..moveTo(52, 42)..lineTo(41, 60)..lineTo(50, 60)
          ..lineTo(46, 74)..lineTo(62, 53)..lineTo(52, 53)..close();
        canvas.drawPath(bolt, Paint()..color = const Color(0xffffad43));
      case IndustrialArtworkKind.weldPasses:
        canvas.drawLine(const Offset(18, 75), const Offset(82, 75), steel..strokeWidth = 8);
        for (var i = 0; i < 3; i++) {
          canvas.drawArc(Rect.fromLTWH(28 + i * 7.0, 52 - i * 10.0, 44 - i * 14.0, 24),
            3.14, 3.14, false, amber..strokeWidth = 4);
        }
      case IndustrialArtworkKind.weldDistortion:
        final plate = Path()..moveTo(15, 70)..quadraticBezierTo(50, 76, 85, 55);
        canvas.drawPath(plate, steel..strokeWidth = 10);
        canvas.drawLine(const Offset(18, 82), const Offset(82, 82), amber..strokeWidth = 2);
        canvas.drawLine(const Offset(74, 28), const Offset(74, 47), amber..strokeWidth = 4);
        canvas.drawLine(const Offset(67, 40), const Offset(74, 47), amber);
        canvas.drawLine(const Offset(81, 40), const Offset(74, 47), amber);
      case IndustrialArtworkKind.coolingTime:
        canvas.drawCircle(const Offset(48, 48), 27, steel..strokeWidth = 5);
        canvas.drawLine(const Offset(48, 48), const Offset(48, 30), amber..strokeWidth = 4);
        canvas.drawLine(const Offset(48, 48), const Offset(62, 55), amber);
        canvas.drawLine(const Offset(35, 80), const Offset(61, 80), steel..strokeWidth = 4);
      case IndustrialArtworkKind.helmet:
        final helmet = Path()..moveTo(20, 20)..quadraticBezierTo(50, 10, 80, 20)
          ..lineTo(74, 70)..lineTo(50, 84)..lineTo(26, 70)..close();
        canvas.drawPath(helmet, Paint()..color = const Color(0xff8fa9b7));
        canvas.drawPath(helmet, steel..strokeWidth = 3);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 31, 38, 20),
          const Radius.circular(3)), Paint()..color = const Color(0xff193745));
        canvas.drawLine(const Offset(39, 47), const Offset(59, 35), amber..strokeWidth = 2);
      case IndustrialArtworkKind.electrode:
        canvas.drawLine(const Offset(24, 76), const Offset(73, 27), steel..strokeWidth = 10);
        canvas.drawLine(const Offset(62, 38), const Offset(73, 27), amber..strokeWidth = 10);
        canvas.drawLine(const Offset(19, 81), const Offset(25, 75), steel..strokeWidth = 3);
      case IndustrialArtworkKind.filler:
        for (var i = 0; i < 4; i++) {
          canvas.drawLine(Offset(20, 28 + i * 14), Offset(78, 28 + i * 14),
            i == 1 ? (amber..strokeWidth = 5) : (steel..strokeWidth = 5));
        }
      case IndustrialArtworkKind.orbital:
        canvas.drawCircle(const Offset(50, 50), 26, steel..strokeWidth = 12);
        canvas.drawArc(const Rect.fromLTWH(24, 24, 52, 52), -1.5, 2.1, false, amber..strokeWidth = 5);
        canvas.drawCircle(const Offset(50, 50), 11, steel..strokeWidth = 3);
        canvas.drawLine(const Offset(69, 68), const Offset(82, 81), steel..strokeWidth = 7);
      case IndustrialArtworkKind.tank:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(25, 18, 50, 64),
          const Radius.circular(20)), steel..strokeWidth = 5);
        canvas.drawLine(const Offset(28, 42), const Offset(72, 42), amber);
        canvas.drawLine(const Offset(28, 59), const Offset(72, 59), amber..strokeWidth = 2);
      case IndustrialArtworkKind.blueprint:
      case IndustrialArtworkKind.scanner:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 16, 60, 68),
          const Radius.circular(4)), steel..strokeWidth = 3);
        final iso = Path()..moveTo(29, 63)..lineTo(44, 54)..lineTo(44, 39)
          ..lineTo(60, 30)..lineTo(70, 36);
        canvas.drawPath(iso, amber..strokeWidth = 4);
        if (kind == IndustrialArtworkKind.scanner) {
          canvas.drawLine(const Offset(16, 51), const Offset(84, 51), steel..strokeWidth = 3);
        }
      case IndustrialArtworkKind.library:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(17, 26, 66, 52),
          const Radius.circular(4)), steel..strokeWidth = 4);
        canvas.drawLine(const Offset(18, 43), const Offset(82, 43), amber);
        canvas.drawCircle(const Offset(37, 60), 9, steel..strokeWidth = 4);
        canvas.drawLine(const Offset(58, 55), const Offset(70, 55), amber);
        canvas.drawLine(const Offset(58, 65), const Offset(70, 65), amber);
      case IndustrialArtworkKind.measurement:
        canvas.drawLine(const Offset(18, 48), const Offset(82, 48), steel..strokeWidth = 14);
        canvas.drawLine(const Offset(20, 72), const Offset(80, 72), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(20, 66), const Offset(20, 78), amber);
        canvas.drawLine(const Offset(80, 66), const Offset(80, 78), amber);
      case IndustrialArtworkKind.bevel:
        final left = Path()..moveTo(15, 26)..lineTo(39, 26)..lineTo(50, 50)
          ..lineTo(39, 74)..lineTo(15, 74);
        final right = Path()..moveTo(85, 26)..lineTo(61, 26)..lineTo(50, 50)
          ..lineTo(61, 74)..lineTo(85, 74);
        canvas.drawPath(left, steel..strokeWidth = 6);
        canvas.drawPath(right, steel);
        canvas.drawCircle(const Offset(50, 50), 4, Paint()..color = const Color(0xffffad43));
      case IndustrialArtworkKind.assistant:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(18, 18, 64, 50),
          const Radius.circular(12)), steel..strokeWidth = 4);
        for (final x in [35.0, 50.0, 65.0]) {
          canvas.drawCircle(Offset(x, 43), 4, Paint()..color = const Color(0xffffad43));
        }
        canvas.drawLine(const Offset(34, 68), const Offset(28, 80), steel..strokeWidth = 4);
      case IndustrialArtworkKind.elbowMeasure:
      case IndustrialArtworkKind.elbowCut:
      case IndustrialArtworkKind.elbowRotate:
        final elbow = Path()..moveTo(15, 70)..lineTo(43, 70)
          ..quadraticBezierTo(70, 70, 70, 43)..lineTo(70, 17);
        canvas.drawPath(elbow, steel..strokeWidth = 17..strokeCap = StrokeCap.butt);
        if (kind == IndustrialArtworkKind.elbowMeasure) {
          canvas.drawLine(const Offset(17, 88), const Offset(70, 88), amber..strokeWidth = 3);
          canvas.drawLine(const Offset(17, 83), const Offset(17, 93), amber);
          canvas.drawLine(const Offset(70, 83), const Offset(70, 93), amber);
        } else if (kind == IndustrialArtworkKind.elbowCut) {
          canvas.drawLine(const Offset(55, 46), const Offset(82, 61), amber..strokeWidth = 4);
          canvas.drawLine(const Offset(52, 42), const Offset(47, 39), amber..strokeWidth = 2);
        } else {
          canvas.drawArc(const Rect.fromLTWH(8, 10, 77, 72), 3.4, 1.8, false, amber..strokeWidth = 3);
          final arrow = Path()..moveTo(43, 9)..lineTo(53, 11)..lineTo(47, 19);
          canvas.drawPath(arrow, amber);
        }
      case IndustrialArtworkKind.insert:
        final offset = Path()..moveTo(12, 72)..lineTo(33, 72)..lineTo(66, 29)..lineTo(88, 29);
        canvas.drawPath(offset, steel..strokeWidth = 13);
        canvas.drawLine(const Offset(40, 54), const Offset(55, 65), amber..strokeWidth = 3);
      case IndustrialArtworkKind.reducer:
        final reducer = Path()..moveTo(13, 31)..lineTo(45, 31)..lineTo(72, 40)
          ..lineTo(88, 40)..lineTo(88, 60)..lineTo(72, 60)
          ..lineTo(45, 69)..lineTo(13, 69)..close();
        canvas.drawPath(reducer, Paint()..color = const Color(0xff8fa9b7));
        canvas.drawPath(reducer, steel..strokeWidth = 3);
        canvas.drawLine(const Offset(70, 37), const Offset(70, 63), amber..strokeWidth = 4);
      case IndustrialArtworkKind.mitre:
        final bend = Path()..moveTo(13, 74)..lineTo(41, 74)..lineTo(65, 59)
          ..lineTo(75, 38)..lineTo(75, 16);
        canvas.drawPath(bend, steel..strokeWidth = 15..strokeCap = StrokeCap.butt);
        canvas.drawLine(const Offset(35, 66), const Offset(42, 81), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(58, 52), const Offset(71, 64), amber);
        canvas.drawLine(const Offset(67, 37), const Offset(83, 41), amber);
      case IndustrialArtworkKind.bender:
        canvas.drawArc(const Rect.fromLTWH(15, 24, 58, 58), 1.55, 3.0, false, steel..strokeWidth = 9);
        canvas.drawLine(const Offset(42, 26), const Offset(83, 15), amber..strokeWidth = 7);
        canvas.drawLine(const Offset(45, 82), const Offset(83, 82), steel..strokeWidth = 7);
      case IndustrialArtworkKind.cone:
        final cone = Path()..moveTo(20, 70)..quadraticBezierTo(50, 88, 80, 70)
          ..lineTo(62, 28)..quadraticBezierTo(50, 35, 38, 28)..close();
        canvas.drawPath(cone, steel..strokeWidth = 4);
        canvas.drawArc(const Rect.fromLTWH(38, 23, 24, 12), 0, 3.14, false, amber..strokeWidth = 3);
      case IndustrialArtworkKind.saddle:
        canvas.drawLine(const Offset(14, 69), const Offset(86, 69), steel..strokeWidth = 18);
        final tube = Path()..moveTo(40, 17)..lineTo(40, 58)
          ..quadraticBezierTo(50, 71, 60, 58)..lineTo(60, 17);
        canvas.drawPath(tube, steel..strokeWidth = 4);
        final seam = Path()..moveTo(40, 58)..quadraticBezierTo(50, 71, 60, 58);
        canvas.drawPath(seam, amber..strokeWidth = 4);
      case IndustrialArtworkKind.saddleTemplate:
        final page = RRect.fromRectAndRadius(const Rect.fromLTWH(19, 14, 62, 72),
            const Radius.circular(4));
        canvas.drawRRect(page, steel..strokeWidth = 4);
        final wave = Path()..moveTo(26, 56)..cubicTo(36, 35, 43, 35, 51, 56)
          ..cubicTo(58, 76, 67, 76, 75, 56);
        canvas.drawPath(wave, amber..strokeWidth = 4);
        canvas.drawLine(const Offset(27, 25), const Offset(61, 25), steel..strokeWidth = 2);
      case IndustrialArtworkKind.rollingOffset:
        final offset = Path()..moveTo(16, 75)..lineTo(36, 65)..lineTo(64, 36)..lineTo(84, 26);
        canvas.drawPath(offset, steel..strokeWidth = 11);
        canvas.drawLine(const Offset(36, 65), const Offset(36, 38), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(36, 38), const Offset(64, 23), amber);
      case IndustrialArtworkKind.pipeSlope:
        canvas.drawLine(const Offset(14, 64), const Offset(84, 38), steel..strokeWidth = 14);
        canvas.drawLine(const Offset(15, 82), const Offset(84, 82), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(75, 76), const Offset(84, 82), amber);
      case IndustrialArtworkKind.slopeCut:
        canvas.drawLine(const Offset(15, 55), const Offset(82, 55), steel..strokeWidth = 23);
        canvas.drawLine(const Offset(52, 38), const Offset(68, 72), amber..strokeWidth = 4);
      case IndustrialArtworkKind.expansion:
        canvas.drawLine(const Offset(16, 52), const Offset(84, 52), steel..strokeWidth = 13);
        canvas.drawLine(const Offset(22, 27), const Offset(78, 27), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(22, 27), const Offset(31, 20), amber);
        canvas.drawLine(const Offset(22, 27), const Offset(31, 34), amber);
        canvas.drawLine(const Offset(78, 27), const Offset(69, 20), amber);
        canvas.drawLine(const Offset(78, 27), const Offset(69, 34), amber);
      case IndustrialArtworkKind.pipeDiameter:
      case IndustrialArtworkKind.pipeWall:
        canvas.drawCircle(const Offset(50, 48), 27, steel..strokeWidth = 9);
        if (kind == IndustrialArtworkKind.pipeDiameter) {
          canvas.drawLine(const Offset(24, 48), const Offset(76, 48), amber..strokeWidth = 3);
          canvas.drawLine(const Offset(24, 42), const Offset(24, 54), amber);
          canvas.drawLine(const Offset(76, 42), const Offset(76, 54), amber);
        } else {
          canvas.drawLine(const Offset(48, 18), const Offset(48, 31), amber..strokeWidth = 4);
          canvas.drawLine(const Offset(40, 23), const Offset(56, 23), amber..strokeWidth = 2);
        }
      case IndustrialArtworkKind.pipeWeight:
        canvas.drawLine(const Offset(20, 28), const Offset(80, 28), steel..strokeWidth = 14);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(29, 48, 42, 31),
          const Radius.circular(6)), steel..strokeWidth = 4);
        canvas.drawArc(const Rect.fromLTWH(39, 53, 22, 18), 3.14, 3.14, false, amber..strokeWidth = 3);
        canvas.drawLine(const Offset(50, 62), const Offset(57, 57), amber);
      case IndustrialArtworkKind.steelProfiles:
        final beam = Path()..moveTo(25, 18)..lineTo(75, 18)..lineTo(75, 29)
          ..lineTo(57, 29)..lineTo(57, 71)..lineTo(75, 71)..lineTo(75, 82)
          ..lineTo(25, 82)..lineTo(25, 71)..lineTo(43, 71)..lineTo(43, 29)
          ..lineTo(25, 29)..close();
        canvas.drawPath(beam, Paint()..color = const Color(0xffa9c0cb));
        canvas.drawLine(const Offset(25, 82), const Offset(75, 82), amber..strokeWidth = 3);
      case IndustrialArtworkKind.sanitaryPipe:
        canvas.drawLine(const Offset(17, 61), const Offset(82, 35), steel..strokeWidth = 16);
        canvas.drawLine(const Offset(19, 56), const Offset(81, 32), Paint()
          ..color = const Color(0xffe7f2f5)..strokeWidth = 3..strokeCap = StrokeCap.round);
        canvas.drawLine(const Offset(30, 18), const Offset(30, 33), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(23, 25), const Offset(37, 25), amber);
      case IndustrialArtworkKind.unitConversion:
        canvas.drawLine(const Offset(19, 35), const Offset(79, 35), steel..strokeWidth = 5);
        canvas.drawLine(const Offset(79, 35), const Offset(69, 27), steel);
        canvas.drawLine(const Offset(79, 35), const Offset(69, 43), steel);
        canvas.drawLine(const Offset(81, 66), const Offset(21, 66), amber..strokeWidth = 5);
        canvas.drawLine(const Offset(21, 66), const Offset(31, 58), amber);
        canvas.drawLine(const Offset(21, 66), const Offset(31, 74), amber);
      case IndustrialArtworkKind.dictionary:
        final book = Path()..moveTo(50, 27)..quadraticBezierTo(36, 18, 19, 22)
          ..lineTo(19, 74)..quadraticBezierTo(36, 70, 50, 79)
          ..quadraticBezierTo(64, 70, 81, 74)..lineTo(81, 22)
          ..quadraticBezierTo(64, 18, 50, 27)..close();
        canvas.drawPath(book, steel..strokeWidth = 4);
        canvas.drawLine(const Offset(50, 27), const Offset(50, 79), amber..strokeWidth = 3);
        canvas.drawLine(const Offset(27, 38), const Offset(41, 40), steel..strokeWidth = 2);
        canvas.drawLine(const Offset(59, 40), const Offset(73, 38), steel);
      case IndustrialArtworkKind.pipeSupport:
        canvas.drawLine(const Offset(13, 42), const Offset(87, 42), steel..strokeWidth = 16);
        final support = Path()..moveTo(30, 52)..quadraticBezierTo(50, 70, 70, 52)
          ..moveTo(50, 64)..lineTo(50, 82)..moveTo(34, 82)..lineTo(66, 82);
        canvas.drawPath(support, amber..strokeWidth = 5);
      case IndustrialArtworkKind.torque:
        canvas.drawCircle(const Offset(40, 44), 20, steel..strokeWidth = 7);
        canvas.drawCircle(const Offset(40, 44), 7, amber..strokeWidth = 4);
        canvas.drawLine(const Offset(54, 58), const Offset(79, 83), steel..strokeWidth = 8);
        canvas.drawArc(const Rect.fromLTWH(13, 16, 54, 54), 3.2, 1.5, false, amber..strokeWidth = 3);
      case IndustrialArtworkKind.flangeCheck:
        canvas.drawCircle(const Offset(42, 49), 25, steel..strokeWidth = 7);
        canvas.drawCircle(const Offset(42, 49), 10, steel..strokeWidth = 3);
        final check = Path()..moveTo(55, 72)..lineTo(65, 82)..lineTo(84, 60);
        canvas.drawPath(check, amber..strokeWidth = 6);
      case IndustrialArtworkKind.boltKit:
        canvas.drawLine(const Offset(20, 35), const Offset(80, 35), steel..strokeWidth = 7);
        canvas.drawLine(const Offset(20, 58), const Offset(80, 58), steel);
        for (final x in [31.0, 57.0]) {
          canvas.drawLine(Offset(x, 27), Offset(x, 43), amber..strokeWidth = 4);
          canvas.drawLine(Offset(x + 8, 50), Offset(x + 8, 66), amber);
        }
      case IndustrialArtworkKind.fitter:
      case IndustrialArtworkKind.welder:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _IndustrialPainter oldDelegate) => oldDelegate.kind != kind;
}
