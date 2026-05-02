// ignore_for_file: prefer_const_constructors
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../i18n/app_language.dart';
import '../widgets/pipe_3d_preview.dart';
import '../widgets/help_button.dart';

// ── Kolory ─────────────────────────────────────────────────────────────────
const _kOrange  = Color(0xFFF5A623);
const _kBlue    = Color(0xFF4A9EFF);
const _kGreen   = Color(0xFF2ECC71);
const _kRed     = Color(0xFFE74C3C);
const _kPurple  = Color(0xFFAB47BC);
const _kCard    = Color(0xFF1A1D26);
const _kBorder  = Color(0xFF2C3354);
const _kMuted   = Color(0xFF55607A);
const _kSec     = Color(0xFF9BA3C7);

// ══════════════════════════════════════════════════════════════════════════
//  MODEL DANYCH
// ══════════════════════════════════════════════════════════════════════════

enum Dir3D { x, y, z }

extension Dir3DExt on Dir3D {
  String get label => name.toUpperCase();

  Color get color {
    switch (this) {
      case Dir3D.x: return _kBlue;
      case Dir3D.y: return _kGreen;
      case Dir3D.z: return _kOrange;
    }
  }

  /// Obie kierunki prostopadłe (wyjścia z ELB90)
  List<Dir3D> get perp => Dir3D.values.where((d) => d != this).toList();

  /// Wektor jednostkowy w tym kierunku
  (double, double, double) get delta {
    switch (this) {
      case Dir3D.x: return (1, 0, 0);
      case Dir3D.y: return (0, 1, 0);
      case Dir3D.z: return (0, 0, 1);
    }
  }
}

enum SpoolType { pipe, valve, flange, reducer, other, openEnd, elbow90, elbow45 }

extension SpoolTypeExt on SpoolType {
  bool get isElbow   => this == SpoolType.elbow90 || this == SpoolType.elbow45;
  bool get isFitting => !isElbow && this != SpoolType.pipe && this != SpoolType.openEnd;

  String label(BuildContext ctx) {
    switch (this) {
      case SpoolType.pipe:    return ctx.tr(pl: 'Rura', en: 'Pipe');
      case SpoolType.valve:   return ctx.tr(pl: 'Zawór', en: 'Valve');
      case SpoolType.flange:  return ctx.tr(pl: 'Kołnierz', en: 'Flange');
      case SpoolType.reducer: return ctx.tr(pl: 'Redukcja', en: 'Reducer');
      case SpoolType.other:   return ctx.tr(pl: 'Inne', en: 'Other');
      case SpoolType.openEnd: return ctx.tr(pl: 'Koniec', en: 'End');
      case SpoolType.elbow90: return ctx.tr(pl: 'Kolano 90°', en: 'Elbow 90°');
      case SpoolType.elbow45: return ctx.tr(pl: 'Kolano 45°', en: 'Elbow 45°');
    }
  }

  IconData get icon {
    switch (this) {
      case SpoolType.pipe:    return Icons.horizontal_rule;
      case SpoolType.valve:   return Icons.settings_input_component_outlined;
      case SpoolType.flange:  return Icons.circle_outlined;
      case SpoolType.reducer: return Icons.compress;
      case SpoolType.other:   return Icons.category_outlined;
      case SpoolType.openEnd: return Icons.flag_outlined;
      case SpoolType.elbow90: return Icons.turn_right;
      case SpoolType.elbow45: return Icons.north_east;
    }
  }
}

/// Komponent w sekwencji trasy.
class SpoolComp {
  final String id;
  SpoolType type;
  Dir3D enterDir;
  Dir3D? exitDir;      // kolanka
  double axisMm;       // kolanka: odjąć z wymiaru
  double lengthMm;     // armatura: długość
  String label;

  SpoolComp({
    required this.id,
    required this.type,
    required this.enterDir,
    this.exitDir,
    this.axisMm = 0,
    this.lengthMm = 0,
    this.label = '',
  });

  bool get isElbow => type.isElbow;
  bool get isFitting => type.isFitting;
  Dir3D get dirAfter => exitDir ?? enterDir;
}

/// Segment 3D do rysowania (izometryczny painter).
class _Seg3D {
  final double x0, y0, z0, x1, y1, z1;
  final Color color;
  final double strokeW;
  final bool isElbow;
  final bool isFitting;
  final bool isEnd;
  final String label;

  const _Seg3D({
    required this.x0, required this.y0, required this.z0,
    required this.x1, required this.y1, required this.z1,
    required this.color,
    this.strokeW = 4,
    this.isElbow = false,
    this.isFitting = false,
    this.isEnd = false,
    this.label = '',
  });

  double get depth => (x0 + x1) / 2 + (y0 + y1) / 2 - (z0 + z1) / 2;
}

/// Noga trasy (prosta rura między kolanami/końcami).
class SpoolLeg {
  final int idx;
  final Dir3D direction;
  final List<SpoolComp> fittingsInLeg;
  final SpoolComp? startElbow;
  final SpoolComp? endElbow;
  final double startTakeoffMm;
  final double endTakeoffMm;
  final double fittingsTotalMm;
  final String dimKey;

  double? fieldMm;
  double? cutMm;

  SpoolLeg({
    required this.idx,
    required this.direction,
    required this.fittingsInLeg,
    required this.startElbow,
    required this.endElbow,
    required this.startTakeoffMm,
    required this.endTakeoffMm,
    required this.fittingsTotalMm,
    required this.dimKey,
  });

  void calc(double gapMm) {
    final fm = fieldMm;
    if (fm == null || fm <= 0) { cutMm = null; return; }
    final welds = (startElbow == null ? 0 : 1) + (endElbow == null ? 0 : 1);
    cutMm = fm - startTakeoffMm - fittingsTotalMm - endTakeoffMm - welds * gapMm;
  }

  String question(BuildContext ctx) {
    final fit = fittingsInLeg.isEmpty
        ? ''
        : '  [${fittingsInLeg.map((f) => '${f.type.label(ctx)} ${f.lengthMm.toStringAsFixed(0)}mm').join(', ')}]';
    return ctx.tr(
      pl: 'Wymiar $dimKey w osi ${direction.label}$fit',
      en: 'Dimension $dimKey along ${direction.label} axis$fit',
    );
  }
}

// ── buildLegs ──────────────────────────────────────────────────────────────
List<SpoolLeg> _buildLegs(List<SpoolComp> comps) {
  if (comps.isEmpty) return [];
  final legs = <SpoolLeg>[];
  final dirCount = <Dir3D, int>{};
  int legStart = 0;
  SpoolComp? prevElbow;

  for (int i = 0; i <= comps.length; i++) {
    final atEnd  = i == comps.length;
    final isElbow = !atEnd && comps[i].isElbow;

    if (i > 0 && (atEnd || isElbow)) {
      final legComps  = comps.sublist(legStart, i);
      final dir       = legComps.first.enterDir;
      dirCount[dir]   = (dirCount[dir] ?? 0) + 1;
      final idx       = dirCount[dir]!;
      final key       = '${dir.label}${idx > 1 ? idx.toString() : ""}';
      final fittings  = legComps.where((c) => c.isFitting).toList();
      final fitLen    = fittings.fold(0.0, (s, c) => s + c.lengthMm);

      legs.add(SpoolLeg(
        idx:             legs.length + 1,
        direction:       dir,
        fittingsInLeg:   fittings,
        startElbow:      prevElbow,
        endElbow:        (!atEnd && isElbow) ? comps[i] : null,
        startTakeoffMm:  prevElbow?.axisMm ?? 0,
        endTakeoffMm:    (!atEnd && isElbow) ? comps[i].axisMm : 0,
        fittingsTotalMm: fitLen,
        dimKey:          key,
      ));

      if (isElbow) { prevElbow = comps[i]; legStart = i + 1; }
    }
  }
  return legs;
}

// ── build3DSegments ─────────────────────────────────────────────────────────
// Tworzy segmenty do rysowania 3D na podstawie listy komponentów.
const _kPipeLen   = 2.5;  // jednostki wyświetlania dla rury między elementami
const _kFitLen    = 0.8;  // jednostki wyświetlania dla armatury
const _kElbRadius = 0.5;  // oznaczenie kolana

List<_Seg3D> _build3DSegs(List<SpoolComp> comps, Dir3D startDir) {
  if (comps.isEmpty) return [];
  final segs = <_Seg3D>[];
  double x = 0, y = 0, z = 0;
  Dir3D dir = startDir;

  // Punkt startowy
  segs.add(_Seg3D(x0: x, y0: y, z0: z, x1: x, y1: y, z1: z,
      color: dir.color, strokeW: 10, label: 'START'));

  bool lastWasElbow = true; // start = treated as "after elbow"

  for (int i = 0; i < comps.length; i++) {
    final c = comps[i];

    if (!lastWasElbow && !c.isElbow) {
      // Dodaj segment rury przed tym komponentem (placeholder)
      final (dx, dy, dz) = dir.delta;
      final len = c.isFitting ? _kFitLen : _kPipeLen;
      segs.add(_Seg3D(
        x0: x, y0: y, z0: z,
        x1: x + dx*len, y1: y + dy*len, z1: z + dz*len,
        color: dir.color, strokeW: c.isFitting ? 7 : 4,
        isFitting: c.isFitting,
        label: c.isFitting ? c.type.label(_DummyCtx()) : '',
      ));
      x += dx*len; y += dy*len; z += dz*len;
    }

    if (c.isElbow) {
      // Kolano: narysuj łuk/oznaczenie i zmień kierunek
      final exitDir = c.dirAfter;
      segs.add(_Seg3D(
        x0: x, y0: y, z0: z, x1: x, y1: y, z1: z,
        color: _kPurple, strokeW: 12, isElbow: true,
        label: '${dir.label}→${exitDir.label}',
      ));
      // Dodaj krótki segment w nowym kierunku (żeby kolano było widoczne)
      final (dx, dy, dz) = exitDir.delta;
      segs.add(_Seg3D(
        x0: x, y0: y, z0: z,
        x1: x + dx*_kElbRadius, y1: y + dy*_kElbRadius, z1: z + dz*_kElbRadius,
        color: exitDir.color, strokeW: 4,
      ));
      x += dx*_kElbRadius; y += dy*_kElbRadius; z += dz*_kElbRadius;
      dir = exitDir;
      lastWasElbow = true;
    } else if (c.type == SpoolType.openEnd) {
      segs.add(_Seg3D(x0: x, y0: y, z0: z, x1: x, y1: y, z1: z,
          color: _kGreen, strokeW: 12, isEnd: true, label: 'END'));
      lastWasElbow = false;
    } else {
      lastWasElbow = false;
    }
  }

  // Dodaj końcowy segment rury jeśli ostatni komponent nie był kolankım/końcem
  if (!lastWasElbow && (comps.isEmpty || (!comps.last.isElbow && comps.last.type != SpoolType.openEnd))) {
    final (dx, dy, dz) = dir.delta;
    segs.add(_Seg3D(
      x0: x, y0: y, z0: z,
      x1: x + dx*_kPipeLen, y1: y + dy*_kPipeLen, z1: z + dz*_kPipeLen,
      color: dir.color.withOpacity(0.4), strokeW: 4,
    ));
  }

  return segs;
}

// Dummy context do label armatury w _build3DSegs (bez kontekstu budowania)
class _DummyCtx extends BuildContext {
  _DummyCtx();
  @override dynamic noSuchMethod(Invocation i) => '';
}

// ══════════════════════════════════════════════════════════════════════════
//  IZOMETRYCZNY PAINTER 3D
// ══════════════════════════════════════════════════════════════════════════

class _Iso3DPainter extends CustomPainter {
  final List<_Seg3D> segments;
  final Dir3D currentDir;
  final double cx, cy;

  const _Iso3DPainter({
    required this.segments,
    required this.currentDir,
    required this.cx,
    required this.cy,
  });

  static const _cos30 = 0.8660254;
  static const _sin30 = 0.5;

  Offset _project(double x, double y, double z, double scale) {
    final px = (x - y) * _cos30;
    final py = (x + y) * _sin30 - z;
    return Offset(cx + px * scale, cy + py * scale);
  }

  /// Auto-scale to fit all segments in the view.
  double _calcScale(Size size) {
    if (segments.isEmpty) return 30;
    double minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (final s in segments) {
      for (final (wx, wy, wz) in [(s.x0, s.y0, s.z0), (s.x1, s.y1, s.z1)]) {
        final px = (wx - wy) * _cos30;
        final py = (wx + wy) * _sin30 - wz;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
      }
    }
    final spanX = (maxX - minX).abs() + 4;
    final spanY = (maxY - minY).abs() + 4;
    final scaleX = size.width  * 0.85 / spanX;
    final scaleY = size.height * 0.85 / spanY;
    return math.min(scaleX, scaleY).clamp(15.0, 50.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _calcScale(size);

    // ── Siatka podłogi ────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFF2C3354).withOpacity(0.5)
      ..strokeWidth = 0.5;
    for (var g = -2; g <= 8; g++) {
      final a = _project(g.toDouble(), -2, 0, scale);
      final b = _project(g.toDouble(),  8, 0, scale);
      canvas.drawLine(a, b, gridPaint);
      final c = _project(-2, g.toDouble(), 0, scale);
      final d = _project( 8, g.toDouble(), 0, scale);
      canvas.drawLine(c, d, gridPaint);
    }

    // ── Osie ──────────────────────────────────────────────────────────────
    _drawAxis(canvas, scale, Dir3D.x, 4.5, 'X');
    _drawAxis(canvas, scale, Dir3D.y, 4.5, 'Y');
    _drawAxis(canvas, scale, Dir3D.z, 4.0, 'Z');

    // ── Segmenty (sortuj po głębokości) ───────────────────────────────────
    final sorted = List<_Seg3D>.from(segments)
      ..sort((a, b) => a.depth.compareTo(b.depth));

    for (final seg in sorted) {
      _drawSeg(canvas, seg, scale);
    }

    // ── Wskaźnik kierunku bieżącego ───────────────────────────────────────
    if (segments.isNotEmpty) {
      final last = sorted.last;
      final p = _project(last.x1, last.y1, last.z1, scale);
      final (dx, dy, dz) = currentDir.delta;
      final p2 = _project(
          last.x1 + dx * 1.2, last.y1 + dy * 1.2, last.z1 + dz * 1.2, scale);
      final arrowPaint = Paint()
        ..color = currentDir.color.withOpacity(0.7)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      _drawDashedLine(canvas, p, p2, arrowPaint);
      // Grot
      final angle = math.atan2(p2.dy - p.dy, p2.dx - p.dx);
      const arrowLen = 8.0;
      canvas.drawLine(p2,
          Offset(p2.dx - arrowLen * math.cos(angle - 0.4), p2.dy - arrowLen * math.sin(angle - 0.4)),
          arrowPaint..strokeWidth = 2);
      canvas.drawLine(p2,
          Offset(p2.dx - arrowLen * math.cos(angle + 0.4), p2.dy - arrowLen * math.sin(angle + 0.4)),
          arrowPaint..strokeWidth = 2);
    }
  }

  void _drawAxis(Canvas canvas, double scale, Dir3D dir, double len, String label) {
    final o = _project(0, 0, 0, scale);
    final (dx, dy, dz) = dir.delta;
    final e = _project(dx * len, dy * len, dz * len, scale);
    final paint = Paint()
      ..color = dir.color.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(o, e, paint);
    // Label
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(color: dir.color, fontSize: 11, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(e.dx + 4, e.dy - 6));
  }

  void _drawSeg(Canvas canvas, _Seg3D seg, double scale) {
    final p0 = _project(seg.x0, seg.y0, seg.z0, scale);
    final p1 = _project(seg.x1, seg.y1, seg.z1, scale);
    final paint = Paint()
      ..color = seg.color
      ..strokeWidth = seg.strokeW
      ..strokeCap = StrokeCap.round;

    if (seg.isElbow) {
      // Kolano: duży kółko + krzyżyk
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(p0, 8, paint);
      paint
        ..color = Colors.white.withOpacity(0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(p0, 8, paint);
      // Label kolana
      if (seg.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: seg.label, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p0.dx + 10, p0.dy - 6));
      }
    } else if (seg.isEnd) {
      // Koniec: flaga
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(p0, 10, paint..color = seg.color.withOpacity(0.2));
      paint.style = PaintingStyle.stroke;
      canvas.drawCircle(p0, 10, paint..strokeWidth = 2..color = seg.color);
      final tp = TextPainter(
        text: TextSpan(text: seg.label, style: TextStyle(color: seg.color, fontSize: 8, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p0.dx + 12, p0.dy - 5));
    } else if (p0 != p1) {
      // Segment rury lub armatury
      paint.style = PaintingStyle.stroke;
      // Cień
      canvas.drawLine(p0, p1, Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..strokeWidth = seg.strokeW + 2
        ..strokeCap = StrokeCap.round);
      // Linia
      canvas.drawLine(p0, p1, paint);
      // Dla armatury: dodatkowe znaczniki na końcach
      if (seg.isFitting) {
        final markPaint = Paint()..color = seg.color..strokeWidth = 2;
        const markLen = 4.0;
        final angle = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
        final perp  = angle + math.pi / 2;
        for (final pt in [p0, p1]) {
          canvas.drawLine(
            Offset(pt.dx + markLen * math.cos(perp), pt.dy + markLen * math.sin(perp)),
            Offset(pt.dx - markLen * math.cos(perp), pt.dy - markLen * math.sin(perp)),
            markPaint,
          );
        }
      }
    } else {
      // Punkt startowy
      canvas.drawCircle(p0, 6, paint..style = PaintingStyle.fill..color = seg.color);
      canvas.drawCircle(p0, 6, Paint()..color = Colors.white.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p0, Offset p1, Paint paint) {
    const dashLen  = 8.0;
    const gapLen   = 5.0;
    final total = (p1 - p0).distance;
    final dir   = (p1 - p0) / total;
    double pos  = 0;
    bool draw   = true;
    while (pos < total) {
      final end = math.min(pos + (draw ? dashLen : gapLen), total);
      if (draw) canvas.drawLine(p0 + dir * pos, p0 + dir * end, paint);
      pos += draw ? dashLen : gapLen;
      draw = !draw;
    }
  }

  @override
  bool shouldRepaint(covariant _Iso3DPainter old) =>
      old.segments.length != segments.length || old.currentDir != currentDir;
}

// ══════════════════════════════════════════════════════════════════════════
//  GŁÓWNY EKRAN
// ══════════════════════════════════════════════════════════════════════════

class SpoolPlannerScreen extends StatefulWidget {
  const SpoolPlannerScreen({super.key});
  @override State<SpoolPlannerScreen> createState() => _SpoolPlannerScreenState();
}

class _SpoolPlannerScreenState extends State<SpoolPlannerScreen> {
  static const _uuid = Uuid();

  final _odCtrl  = TextEditingController();
  final _gapCtrl = TextEditingController(text: '0');
  Dir3D _startDir = Dir3D.x;

  final List<SpoolComp> _comps = [];
  List<SpoolLeg> _legs = [];
  List<_Seg3D>   _segs3D = [];

  int _step = 0; // 0=buduj, 1=wymiary, 2=wyniki

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  double get _gapMm => double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0.0;

  Dir3D _currentDir() => _comps.isEmpty ? _startDir : _comps.last.dirAfter;

  void _rebuild() {
    _legs   = _buildLegs(_comps);
    _segs3D = _build3DSegs(_comps, _startDir);
    setState(() {});
  }

  /// Skala: 1 jednostka w `_Seg3D` = ~500 mm w podglądzie 3D.
  /// Pozwala widokowi 3D używać jednostek mm (spójnie z osiami referencyjnymi).
  static const double _unitMm = 500;

  /// Konwertuje wewnętrzne `_Seg3D` na `Pipe3DSegment` dla nowego widoku 3D.
  List<Pipe3DSegment> _toPipe3DSegments() {
    final out = <Pipe3DSegment>[];
    for (final s in _segs3D) {
      Pipe3DStyle style;
      double stroke;
      if (s.isElbow) {
        style  = Pipe3DStyle.elbow;
        stroke = 60;
      } else if (s.isEnd) {
        style  = Pipe3DStyle.endMark;
        stroke = 60;
      } else if (s.isFitting) {
        style  = Pipe3DStyle.fitting;
        stroke = 80;
      } else {
        style  = Pipe3DStyle.pipe;
        stroke = 60;
      }
      out.add(Pipe3DSegment(
        x0: s.x0 * _unitMm, y0: s.y0 * _unitMm, z0: s.z0 * _unitMm,
        x1: s.x1 * _unitMm, y1: s.y1 * _unitMm, z1: s.z1 * _unitMm,
        color: s.color,
        strokeMm: stroke,
        style: style,
        label: s.label,
      ));
    }
    return out;
  }

  // ── Dodaj komponent ────────────────────────────────────────────────────
  Future<void> _addComp(SpoolType type) async {
    final cur = _currentDir();

    if (type.isElbow) {
      final exit = await _pickExitDir(cur, type);
      if (!mounted || exit == null) return;
      final axis = await _askDouble(
        _tr('Kolano — wymiar do osi (mm)', 'Elbow — axis dim (mm)'),
        hint: '76.2',
      );
      if (!mounted || axis == null) return;
      _comps.add(SpoolComp(id: _uuid.v4(), type: type, enterDir: cur, exitDir: exit, axisMm: axis));
    } else if (type.isFitting) {
      final len = await _askDouble(
        '${type.label(context)} — ${_tr("długość (mm)", "length (mm)")}',
        hint: '150',
      );
      if (!mounted || len == null) return;
      _comps.add(SpoolComp(id: _uuid.v4(), type: type, enterDir: cur, lengthMm: len));
    } else {
      _comps.add(SpoolComp(id: _uuid.v4(), type: type, enterDir: cur));
    }
    _rebuild();
  }

  Future<Dir3D?> _pickExitDir(Dir3D enter, SpoolType type) async {
    return showModalBottomSheet<Dir3D>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ExitDirSheet(enter: enter),
    );
  }

  Future<double?> _askDouble(String title, {String hint = ''}) async {
    final ctrl = TextEditingController();
    return showDialog<double?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, null), child: Text(_tr('Anuluj', 'Cancel'))),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              Navigator.pop(_, (v != null && v > 0) ? v : null);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: Text(_tr('Projektant trasy 3D', 'Route planner 3D')),
        actions: [
          HelpButton(help: kHelpSpoolPlanner),
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: Text(_tr('Edytuj', 'Edit'), style: const TextStyle(color: _kOrange)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Row(
            children: List.generate(3, (i) => Expanded(
              child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: i <= _step ? _kOrange : _kBorder),
            )),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 3D WIDOK (pełny, obracalny) ────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0F1117),
              padding: const EdgeInsets.all(6),
              child: _segs3D.isEmpty
                  ? _emptyCanvas(context)
                  : Pipe3DPreview(
                      segments: _toPipe3DSegments(),
                      axisLengthMm: _unitMm * 1.2,
                    ),
            ),
          ),

          // ── DOLNA CZĘŚĆ ────────────────────────────────────────────────
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A1D26),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              child: _step == 0
                  ? _buildPalette()
                  : _step == 1
                      ? _buildDimensions()
                      : _buildResults(),
            ),
          ),
        ],
      ),
      floatingActionButton: _step < 2 && _legs.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _step++),
              backgroundColor: _kOrange,
              foregroundColor: Colors.black,
              icon: Icon(_step == 0 ? Icons.arrow_forward : Icons.calculate),
              label: Text(_step == 0
                  ? _tr('Wymiary →', 'Dimensions →')
                  : _tr('Oblicz →', 'Calculate →')),
            )
          : null,
    );
  }

  Widget _emptyCanvas(BuildContext ctx) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.route_outlined, size: 48, color: _kMuted.withOpacity(0.5)),
      const SizedBox(height: 12),
      Text(
        ctx.tr(pl: 'Dodaj komponenty → trasa pojawi się tutaj', en: 'Add components → route appears here'),
        style: const TextStyle(color: _kMuted, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    ]),
  );

  // ── PALETA KOMPONENTÓW ─────────────────────────────────────────────────
  Widget _buildPalette() {
    final cur = _currentDir();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 14 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parametry
          Row(children: [
            Expanded(child: TextField(
              controller: _odCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'OD (mm)', hintText: '60.3'),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _gapCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _tr('Gap (mm)', 'Gap (mm)'), hintText: '2'),
            )),
            const SizedBox(width: 10),
            // Kierunek startowy
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tr('Start:', 'Start:'), style: const TextStyle(fontSize: 10, color: _kMuted)),
              Row(children: Dir3D.values.map((d) => GestureDetector(
                onTap: () { setState(() { _startDir = d; if (_comps.isNotEmpty) _comps.first.enterDir = d; _rebuild(); }); },
                child: Container(
                  width: 32, height: 32,
                  margin: const EdgeInsets.only(right: 4, top: 4),
                  decoration: BoxDecoration(
                    color: _startDir == d ? d.color.withOpacity(0.2) : _kCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _startDir == d ? d.color : _kBorder, width: _startDir == d ? 1.5 : 1),
                  ),
                  child: Center(child: Text(d.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _startDir == d ? d.color : _kSec))),
                ),
              )).toList()),
            ]),
          ]),
          const SizedBox(height: 14),

          // Wskaźnik bieżącego kierunku
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cur.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cur.color.withOpacity(0.4)),
              ),
              child: Text(
                _tr('Kierunek: ${cur.label}', 'Direction: ${cur.label}'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cur.color),
              ),
            ),
            if (_comps.isNotEmpty) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () { _comps.removeLast(); _rebuild(); },
                icon: const Icon(Icons.undo, size: 14),
                label: Text(_tr('Cofnij', 'Undo')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kSec, side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // Kolanka
          Text(_tr('Zmiana kierunku:', 'Change direction:'),
              style: const TextStyle(fontSize: 10, color: _kMuted, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _PaletteBtn(_tr('Kolano 90°', 'Elbow 90°'), SpoolType.elbow90, Icons.turn_right, _kPurple, _addComp),
            _PaletteBtn(_tr('Kolano 45°', 'Elbow 45°'), SpoolType.elbow45, Icons.north_east, _kPurple, _addComp),
          ]),
          const SizedBox(height: 10),

          // Armatura
          Text(_tr('Armatura:', 'Fittings:'),
              style: const TextStyle(fontSize: 10, color: _kMuted, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _PaletteBtn(_tr('Zawór', 'Valve'),        SpoolType.valve,    Icons.settings_input_component_outlined, _kBlue,   _addComp),
            _PaletteBtn(_tr('Kołnierz', 'Flange'),    SpoolType.flange,   Icons.circle_outlined,                   _kBlue,   _addComp),
            _PaletteBtn(_tr('Redukcja', 'Reducer'),   SpoolType.reducer,  Icons.compress,                          _kBlue,   _addComp),
            _PaletteBtn(_tr('Inne', 'Other'),         SpoolType.other,    Icons.category_outlined,                 _kSec,    _addComp),
            _PaletteBtn(_tr('Koniec', 'End'),         SpoolType.openEnd,  Icons.flag_outlined,                     _kGreen,  _addComp),
          ]),

          // Lista komponentów
          if (_comps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: _kBorder),
            const SizedBox(height: 6),
            _RouteChipList(comps: _comps),
          ],
        ],
      ),
    );
  }

  // ── WYMIARY ────────────────────────────────────────────────────────────
  Widget _buildDimensions() {
    if (_legs.isEmpty) return Center(child: Text(_tr('Brak nóg do obliczenia', 'No legs')));
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 100 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _kBlue.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBlue.withOpacity(0.2))),
          child: Text(
            _tr('Wpisz wymiary zmierzone w terenie (oś do osi).', 'Enter field measurements (axis to axis).'),
            style: const TextStyle(fontSize: 12, color: _kSec),
          ),
        ),
        const SizedBox(height: 12),
        ..._legs.map((leg) => _LegDimInput(leg: leg, gapMm: _gapMm, onChanged: () => setState(() {}))),
      ],
    );
  }

  // ── WYNIKI ─────────────────────────────────────────────────────────────
  Widget _buildResults() {
    final total = _legs.fold(0.0, (s, l) => s + (l.cutMm ?? 0));
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        ..._legs.map((l) {
          final ok = l.cutMm != null && l.cutMm! > 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: l.direction.color.withOpacity(0.3), width: 1.5),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: l.direction.color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(l.dimKey, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: l.direction.color))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rura ${l.idx}  ·  oś ${l.direction.label}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFE8ECF0))),
                if (l.fieldMm != null)
                  Text('${l.dimKey} = ${l.fieldMm!.toStringAsFixed(0)} mm',
                      style: const TextStyle(fontSize: 11, color: _kSec)),
              ])),
              Text(
                l.cutMm != null ? '${l.cutMm!.toStringAsFixed(1)} mm' : '—',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ok ? _kOrange : _kRed),
              ),
            ]),
          );
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kGreen.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGreen.withOpacity(0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_tr('Łączna rura netto', 'Total net pipe'),
                style: const TextStyle(fontSize: 13, color: _kSec)),
            Text('${(total / 1000).toStringAsFixed(3)} m',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kOrange)),
          ]),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  WIDGETY POMOCNICZE
// ══════════════════════════════════════════════════════════════════════════

class _PaletteBtn extends StatelessWidget {
  final String label;
  final SpoolType type;
  final IconData icon;
  final Color color;
  final Future<void> Function(SpoolType) onTap;
  const _PaletteBtn(this.label, this.type, this.icon, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onTap(type),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _RouteChipList extends StatelessWidget {
  final List<SpoolComp> comps;
  const _RouteChipList({required this.comps});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: comps.map((c) {
        final color = c.isElbow ? _kPurple : (c.isFitting ? _kBlue : _kGreen);
        return Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(c.type.icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              c.isElbow ? '${c.enterDir.label}→${c.dirAfter.label}' : c.type.label(context),
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
            ),
          ]),
        );
      }).toList(),
    ),
  );
}

class _LegDimInput extends StatefulWidget {
  final SpoolLeg leg;
  final double gapMm;
  final VoidCallback onChanged;
  const _LegDimInput({required this.leg, required this.gapMm, required this.onChanged});
  @override State<_LegDimInput> createState() => _LegDimInputState();
}

class _LegDimInputState extends State<_LegDimInput> {
  late final TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.leg.fieldMm?.toStringAsFixed(0)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final leg = widget.leg;
    final dir = leg.direction;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dir.color.withOpacity(0.35), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: dir.color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Text('${leg.dimKey}  (${dir.label})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dir.color)),
          ),
          const SizedBox(width: 8),
          Text('Rura ${leg.idx}', style: const TextStyle(fontSize: 11, color: _kMuted)),
        ]),
        const SizedBox(height: 6),
        // Skład nogi
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (leg.startTakeoffMm > 0) _chip('oś kolana: ${leg.startTakeoffMm.toStringAsFixed(0)}mm', _kPurple),
          ...leg.fittingsInLeg.map((f) => _chip('${f.type.label(context)}: ${f.lengthMm.toStringAsFixed(0)}mm', _kBlue)),
          if (leg.endTakeoffMm > 0) _chip('oś kolana: ${leg.endTakeoffMm.toStringAsFixed(0)}mm', _kPurple),
        ]),
        const SizedBox(height: 8),
        Text(leg.question(context), style: const TextStyle(fontSize: 12, color: _kSec)),
        const SizedBox(height: 6),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '${leg.dimKey} (mm)',
            suffixText: 'mm',
            filled: true, fillColor: const Color(0xFF22263A),
          ),
          onChanged: (v) {
            leg.fieldMm = double.tryParse(v.replaceAll(',', '.'));
            leg.calc(widget.gapMm);
            widget.onChanged();
          },
        ),
        if (leg.cutMm != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'CUT Rura ${leg.idx} = ${leg.cutMm!.toStringAsFixed(1)} mm',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: leg.cutMm! > 0 ? _kOrange : _kRed),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withOpacity(0.25))),
    child: Text(t, style: TextStyle(fontSize: 10, color: c)),
  );
}

// ── Sheet: wybór kierunku wyjścia z kolana ─────────────────────────────────
class _ExitDirSheet extends StatelessWidget {
  final Dir3D enter;
  const _ExitDirSheet({required this.enter});

  @override
  Widget build(BuildContext context) {
    final perp = enter.perp;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(pl: 'Kolano wchodzi z ${enter.label} — skręca do:', en: 'Elbow enters from ${enter.label} — turns to:'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Mini 3D diagram z zaznaczonym wejściem
            SizedBox(
              height: 120,
              child: CustomPaint(
                size: const Size(double.infinity, 120),
                painter: _Iso3DPainter(
                  segments: [
                    _Seg3D(x0: 0, y0: 0, z0: 0, x1: 1.5, y1: 0, z1: 0, color: Dir3D.x.color, strokeW: 4),
                    _Seg3D(x0: 0, y0: 0, z0: 0, x1: 0, y1: 1.5, z1: 0, color: Dir3D.y.color, strokeW: 4),
                    _Seg3D(x0: 0, y0: 0, z0: 0, x1: 0, y1: 0, z1: 1.5, color: Dir3D.z.color, strokeW: 4),
                    // Wejście (enter)
                    _Seg3D(
                      x0: enter == Dir3D.x ? -1.5 : 0,
                      y0: enter == Dir3D.y ? -1.5 : 0,
                      z0: enter == Dir3D.z ? -1.5 : 0,
                      x1: 0, y1: 0, z1: 0,
                      color: enter.color, strokeW: 7,
                    ),
                  ],
                  currentDir: enter,
                  cx: 160, cy: 60,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: perp.map((d) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, d),
                  child: Container(
                    width: 100, height: 72,
                    decoration: BoxDecoration(
                      color: d.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: d.color, width: 1.5),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.arrow_forward, color: d.color, size: 28),
                      const SizedBox(height: 4),
                      Text(d.label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: d.color)),
                      Text(
                        d == Dir3D.x ? context.tr(pl: 'poziom 1', en: 'horiz 1')
                            : d == Dir3D.y ? context.tr(pl: 'poziom 2', en: 'horiz 2')
                            : context.tr(pl: 'pion', en: 'vertical'),
                        style: TextStyle(fontSize: 10, color: d.color.withOpacity(0.7)),
                      ),
                    ]),
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}