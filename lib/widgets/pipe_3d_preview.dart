// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Pipe3DPreview â€” peÅ‚ny 3D podglÄ…d trasy rurociÄ…gu.
//
//  Czyste Flutter + Canvas (bez zewnÄ™trznych bibliotek 3D).
//  Matematyka 3D: obrÃ³t wokÃ³Å‚ osi X (pitch) i Y (yaw) + perspektywa sÅ‚aba.
//  Segmenty rysowane z sortowaniem po gÅ‚Ä™bokoÅ›ci (painter's algorithm)
//  oraz cieniowaniem (ciemnieje w gÅ‚Ä™bi).
//
//  ObsÅ‚uguje:
//   â€¢ przeciÄ…ganie palcem/myszÄ… â†’ obrÃ³t (pitch + yaw)
//   â€¢ gest pinch / scroll â†’ zoom
//   â€¢ automatyczne dopasowanie widoku do bounding boxa
//   â€¢ podwÃ³jny tap â†’ reset widoku
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
import 'dart:math' as math;

import 'package:flutter/material.dart';

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  DANE WEJÅšCIOWE
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

/// Styl rysowania pojedynczego segmentu w 3D.
enum Pipe3DStyle {
  pipe,      // rura miÄ™dzy elementami
  fitting,   // armatura (zawÃ³r, koÅ‚nierz, redukcja)
  elbow,     // kolano (marker w punkcie zmiany kierunku)
  startMark, // znacznik poczÄ…tku trasy
  endMark,   // znacznik koÅ„ca trasy
  axis,      // oÅ› referencyjna (X/Y/Z)
}

/// Pojedynczy segment trasy w przestrzeni 3D (mm).
class Pipe3DSegment {
  final double x0, y0, z0;
  final double x1, y1, z1;
  final Color color;
  final double strokeMm;   // gruboÅ›Ä‡ wizualna (mm)
  final Pipe3DStyle style;
  final String label;

  const Pipe3DSegment({
    required this.x0, required this.y0, required this.z0,
    required this.x1, required this.y1, required this.z1,
    required this.color,
    this.strokeMm = 60,
    this.style = Pipe3DStyle.pipe,
    this.label = '',
  });
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  WIDÅ»ET
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class Pipe3DPreview extends StatefulWidget {
  final List<Pipe3DSegment> segments;

  /// WyÅ›wietlaj osie referencyjne X/Y/Z w rogu.
  final bool showAxes;

  /// DÅ‚ugoÅ›Ä‡ osi w mm (wizualna).
  final double axisLengthMm;

  /// TÅ‚o.
  final Color background;

  const Pipe3DPreview({
    super.key,
    required this.segments,
    this.showAxes = true,
    this.axisLengthMm = 300,
    this.background = const Color(0xFF0B0E17),
  });

  @override
  State<Pipe3DPreview> createState() => _Pipe3DPreviewState();
}

class _Pipe3DPreviewState extends State<Pipe3DPreview> {
  // KÄ…ty kamery (radiany)
  double _pitch = -0.45; // patrzy lekko z gÃ³ry
  double _yaw   =  0.70; // obrÃ³t wokÃ³Å‚ Y

  // MnoÅ¼nik zoomu nad auto-fit
  double _userZoom = 1.0;

  // Dla obsÅ‚ugi pinch (scale)
  double _scaleStart = 1.0;

  void _resetView() {
    setState(() {
      _pitch = -0.45;
      _yaw   = 0.70;
      _userZoom = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: widget.background,
        child: LayoutBuilder(
          builder: (ctx, box) {
            return Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _resetView,
                  onScaleStart: (_) { _scaleStart = _userZoom; },
                  onScaleUpdate: (d) {
                    setState(() {
                      // ObrÃ³t â€” z delta.translation
                      if (d.pointerCount == 1) {
                        _yaw   += d.focalPointDelta.dx * 0.008;
                        _pitch += d.focalPointDelta.dy * 0.008;
                        _pitch = _pitch.clamp(-math.pi / 2 + 0.05, math.pi / 2 - 0.05);
                      } else {
                        // Zoom
                        _userZoom = (_scaleStart * d.scale).clamp(0.2, 6.0);
                      }
                    });
                  },
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _Pipe3DPainter(
                      segments: widget.segments,
                      pitch: _pitch,
                      yaw: _yaw,
                      userZoom: _userZoom,
                      showAxes: widget.showAxes,
                      axisLengthMm: widget.axisLengthMm,
                    ),
                  ),
                ),
                // Reset widoku + mini info
                Positioned(
                  top: 8, right: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Reset widoku (dwuklik)',
                      icon: const Icon(Icons.center_focus_strong, color: Colors.white70, size: 20),
                      onPressed: _resetView,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8, left: 10,
                  child: Text(
                    'przeciÄ…gnij = obrÃ³t   Â·   szczypta = zoom',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  PAINTER â€” projekcja 3D â†’ 2D
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _Pipe3DPainter extends CustomPainter {
  final List<Pipe3DSegment> segments;
  final double pitch;
  final double yaw;
  final double userZoom;
  final bool showAxes;
  final double axisLengthMm;

  _Pipe3DPainter({
    required this.segments,
    required this.pitch,
    required this.yaw,
    required this.userZoom,
    required this.showAxes,
    required this.axisLengthMm,
  });

  /// Obraca punkt (x,y,z) wokÃ³Å‚ Y (yaw), potem X (pitch).
  /// Zwraca (X,Y,Z) w kamerze â€” Z = gÅ‚Ä™bokoÅ›Ä‡ (im wiÄ™ksze, tym dalej).
  (double, double, double) _rotate(double x, double y, double z) {
    // yaw (wokÃ³Å‚ Y)
    final cY = math.cos(yaw),  sY = math.sin(yaw);
    final x1 =  cY * x + sY * z;
    final z1 = -sY * x + cY * z;
    // pitch (wokÃ³Å‚ X)
    final cP = math.cos(pitch), sP = math.sin(pitch);
    final y2 = cP * y - sP * z1;
    final z2 = sP * y + cP * z1;
    return (x1, y2, z2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) {
      _paintEmpty(canvas, size);
      return;
    }

    // â”€â”€ Oblicz bounding box w przestrzeni kamery â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    double minPx =  1e18, maxPx = -1e18;
    double minPy =  1e18, maxPy = -1e18;

    final projected = <_Projected>[];
    final allPoints = <(double, double, double)>[];

    // zgromadÅº punkty do centrowania
    for (final s in segments) {
      allPoints.add(_rotate(s.x0, s.y0, s.z0));
      allPoints.add(_rotate(s.x1, s.y1, s.z1));
    }
    if (showAxes) {
      for (final p in [
        _rotate(0, 0, 0),
        _rotate(axisLengthMm, 0, 0),
        _rotate(0, axisLengthMm, 0),
        _rotate(0, 0, axisLengthMm),
      ]) {
        allPoints.add(p);
      }
    }

    for (final p in allPoints) {
      if (p.$1 < minPx) minPx = p.$1;
      if (p.$1 > maxPx) maxPx = p.$1;
      if (p.$2 < minPy) minPy = p.$2;
      if (p.$2 > maxPy) maxPy = p.$2;
    }

    final spanX = (maxPx - minPx).abs() + 1;
    final spanY = (maxPy - minPy).abs() + 1;
    final scale = math.min(size.width * 0.85 / spanX, size.height * 0.85 / spanY) * userZoom;

    final cx = size.width  / 2 - ((maxPx + minPx) / 2) * scale;
    final cy = size.height / 2 + ((maxPy + minPy) / 2) * scale;

    Offset project(double x, double y, double z) {
      final (rx, ry, _) = _rotate(x, y, z);
      return Offset(cx + rx * scale, cy - ry * scale);
    }

    double depth(double x, double y, double z) => _rotate(x, y, z).$3;

    // â”€â”€ PodÅ‚oga (siatka co 200 mm w pÅ‚aszczyÅºnie XY, Z=0) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final gridPaint = Paint()
      ..color = const Color(0xFF2C3354).withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    const gridStep = 200.0;
    const gridSpan = 2000.0;
    for (double a = -gridSpan; a <= gridSpan + 0.1; a += gridStep) {
      canvas.drawLine(project(a, -gridSpan, 0), project(a, gridSpan, 0), gridPaint);
      canvas.drawLine(project(-gridSpan, a, 0), project(gridSpan, a, 0), gridPaint);
    }

    // â”€â”€ Osie referencyjne â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (showAxes) {
      _drawAxis(canvas, project, 'X', axisLengthMm, 0, 0, const Color(0xFF4A9EFF));
      _drawAxis(canvas, project, 'Y', 0, axisLengthMm, 0, const Color(0xFF2ECC71));
      _drawAxis(canvas, project, 'Z', 0, 0, axisLengthMm, const Color(0xFFF5A623));
    }

    // â”€â”€ Przygotuj segmenty z gÅ‚Ä™bokoÅ›ciÄ… do sortowania â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    for (final s in segments) {
      final d0 = depth(s.x0, s.y0, s.z0);
      final d1 = depth(s.x1, s.y1, s.z1);
      projected.add(_Projected(
        seg:   s,
        p0:    project(s.x0, s.y0, s.z0),
        p1:    project(s.x1, s.y1, s.z1),
        depth: (d0 + d1) / 2,
      ));
    }

    // Sortuj malejÄ…co po gÅ‚Ä™bokoÅ›ci (dalekie pierwsze â€” painter's algorithm)
    projected.sort((a, b) => a.depth.compareTo(b.depth));

    // Normalizuj gÅ‚Ä™bokoÅ›Ä‡ do [0, 1] dla cieniowania
    final dMin = projected.isEmpty ? 0.0 : projected.first.depth;
    final dMax = projected.isEmpty ? 1.0 : projected.last.depth;
    final dRange = (dMax - dMin).abs() < 1e-6 ? 1.0 : (dMax - dMin);

    for (final p in projected) {
      final t = ((p.depth - dMin) / dRange).clamp(0.0, 1.0);
      _drawSegment(canvas, p, scale, t);
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  Rysowanie pojedynczego segmentu
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _drawSegment(Canvas canvas, _Projected p, double scale, double depthT) {
    final s = p.seg;

    // Zanikanie w gÅ‚Ä™bi â€” fronty jaÅ›niejsze, tyÅ‚ ciemniejszy
    final shade = 1.0 - 0.45 * depthT;
    final col = Color.from(
      alpha: s.color.a,
      red:   (s.color.r * shade).clamp(0.0, 1.0),
      green: (s.color.g * shade).clamp(0.0, 1.0),
      blue:  (s.color.b * shade).clamp(0.0, 1.0),
    );

    switch (s.style) {
      case Pipe3DStyle.pipe:
      case Pipe3DStyle.fitting:
        _drawTube(canvas, p.p0, p.p1, s.strokeMm * scale, col, isFitting: s.style == Pipe3DStyle.fitting);
        break;

      case Pipe3DStyle.elbow:
        _drawMarker(canvas, p.p0, col, radius: 10, label: s.label, fill: true);
        break;

      case Pipe3DStyle.startMark:
        _drawMarker(canvas, p.p0, col, radius: 8, label: s.label, fill: true);
        break;

      case Pipe3DStyle.endMark:
        _drawMarker(canvas, p.p0, col, radius: 10, label: s.label, fill: false);
        break;

      case Pipe3DStyle.axis:
        final paint = Paint()
          ..color = col.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p.p0, p.p1, paint);
        break;
    }
  }

  void _drawTube(Canvas canvas, Offset p0, Offset p1, double thickness, Color col,
      {bool isFitting = false}) {
    if ((p0 - p1).distanceSquared < 0.1) return;

    // Minimum visual thickness
    final t = thickness.clamp(3.0, 40.0);

    // CieÅ„
    canvas.drawLine(p0, p1, Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = t + 2
      ..strokeCap = StrokeCap.round);

    // Rura: gradient poprzeczny (symulacja cieniowania cylindrycznego)
    final angle = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
    final perp = angle + math.pi / 2;
    final half = t / 2;
    final shift = Offset(math.cos(perp) * half, math.sin(perp) * half);

    final gradient = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [
        Color.lerp(col, Colors.white, 0.25)!,
        col,
        Color.lerp(col, Colors.black, 0.35)!,
      ],
      stops: const [0.0, 0.45, 1.0],
    );

    final rect = Rect.fromPoints(p0 - shift * 1.5, p1 + shift * 1.5);
    final paint = Paint()
      ..shader = gradient.createShader(rect, textDirection: TextDirection.ltr)
      ..strokeWidth = t
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(p0, p1, paint);

    // Dla armatury â€” znaczniki na koÅ„cach (krÃ³tkie kreski prostopadÅ‚e)
    if (isFitting) {
      final markPaint = Paint()
        ..color = col
        ..strokeWidth = 2;
      final ml = t * 0.7;
      for (final pt in [p0, p1]) {
        canvas.drawLine(
          Offset(pt.dx + ml * math.cos(perp), pt.dy + ml * math.sin(perp)),
          Offset(pt.dx - ml * math.cos(perp), pt.dy - ml * math.sin(perp)),
          markPaint,
        );
      }
    }
  }

  void _drawMarker(Canvas canvas, Offset p, Color col,
      {required double radius, String label = '', bool fill = true}) {
    final paint = Paint()..color = col;
    if (fill) {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(p, radius, paint);
      canvas.drawCircle(p, radius, Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    } else {
      canvas.drawCircle(p, radius, Paint()
        ..color = col.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill);
      canvas.drawCircle(p, radius, paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    if (label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx + radius + 3, p.dy - radius / 2));
    }
  }

  void _drawAxis(Canvas canvas, Offset Function(double, double, double) project,
      String label, double dx, double dy, double dz, Color col) {
    final p0 = project(0, 0, 0);
    final p1 = project(dx, dy, dz);
    canvas.drawLine(p0, p1, Paint()
      ..color = col.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p1.dx + 4, p1.dy - 6));
  }

  void _paintEmpty(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Dodaj komponenty â†’ trasa pojawi siÄ™ w 3D',
        style: TextStyle(color: Color(0xFF55607A), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _Pipe3DPainter old) =>
      old.segments != segments ||
      old.pitch != pitch ||
      old.yaw != yaw ||
      old.userZoom != userZoom ||
      old.showAxes != showAxes;
}

class _Projected {
  final Pipe3DSegment seg;
  final Offset p0;
  final Offset p1;
  final double depth;
  _Projected({required this.seg, required this.p0, required this.p1, required this.depth});
}
