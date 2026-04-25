import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

enum _SegType { pipe, thin, dashed }

class _Seg {
  final Offset start;
  final Offset end;
  final _SegType type;
  const _Seg(this.start, this.end, this.type);
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class IsoNotebookScreen extends StatefulWidget {
  const IsoNotebookScreen({super.key});
  @override
  State<IsoNotebookScreen> createState() => _IsoNotebookScreenState();
}

class _IsoNotebookScreenState extends State<IsoNotebookScreen> {
  // grid step — roughly comfortable for a finger
  static const double _s = 34.0;

  final List<_Seg> _segs = [];
  final List<List<_Seg>> _undoStack = [];

  Offset? _startPt;  // snapped start
  Offset? _snapPt;   // snapped end preview while dragging
  _SegType _penType  = _SegType.pipe;

  // ── snapping ───────────────────────────────────────────────────────────────
  // Isometric grid:  dy = s·√3/2,  odd rows offset by s/2
  Offset _snap(Offset raw) {
    final dy = _s * math.sqrt(3) / 2.0;
    Offset best = Offset.zero;
    double bestDist = double.infinity;

    for (int dr = -2; dr <= 2; dr++) {
      final row = (raw.dy / dy).round() + dr;
      if (row < 0) continue;
      final y = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : _s / 2.0;
      for (int dc = -2; dc <= 2; dc++) {
        final col = ((raw.dx - xOff) / _s).round() + dc;
        final pt = Offset(col * _s + xOff, y);
        final d = (raw - pt).distance;
        if (d < bestDist) {
          bestDist = d;
          best = pt;
        }
      }
    }
    return best;
  }

  // ── gestures ───────────────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    setState(() {
      _startPt = _snap(d.localPosition);
      _snapPt  = _startPt;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _snapPt = _snap(d.localPosition));
  }

  void _onPanEnd(DragEndDetails _) {
    if (_startPt == null || _snapPt == null) return;
    if ((_snapPt! - _startPt!).distance > _s * 0.3) {
      _undoStack.add(List.from(_segs));
      _segs.add(_Seg(_startPt!, _snapPt!, _penType));
    }
    setState(() { _startPt = null; _snapPt = null; });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() { _segs..clear()..addAll(_undoStack.removeLast()); });
  }

  void _clear() {
    if (_segs.isEmpty) return;
    setState(() { _undoStack.add(List.from(_segs)); _segs.clear(); });
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Zeszyt ISO', en: 'ISO Notebook')),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: context.tr(pl: 'Cofnij', en: 'Undo'),
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Clear all'),
            onPressed: _segs.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── pasek narzędzi ───────────────────────────────────────────────
          _Toolbar(
            selected: _penType,
            onSelect: (t) => setState(() => _penType = t),
            cs: cs,
          ),
          // ── płótno ───────────────────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: CustomPaint(
                painter: _CanvasPainter(
                  segs: _segs,
                  startPt: _startPt,
                  snapPt: _snapPt,
                  penType: _penType,
                  s: _s,
                  cs: cs,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          // ── legenda ──────────────────────────────────────────────────────
          _Legend(cs: cs),
        ],
      ),
    );
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final _SegType selected;
  final ValueChanged<_SegType> onSelect;
  final ColorScheme cs;
  const _Toolbar({required this.selected, required this.onSelect, required this.cs});

  @override
  Widget build(BuildContext context) {
    final items = [
      (_SegType.pipe,   Icons.remove,        context.tr(pl: 'Rura', en: 'Pipe')),
      (_SegType.thin,   Icons.horizontal_rule, context.tr(pl: 'Linia', en: 'Line')),
      (_SegType.dashed, Icons.more_horiz,    context.tr(pl: 'Ukryta', en: 'Hidden')),
    ];
    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            context.tr(pl: 'Pióro: ', en: 'Pen: '),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          ...items.map((item) {
            final isSel = selected == item.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onSelect(item.$1),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? cs.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? cs.primary : cs.outlineVariant,
                    ),
                  ),
                  child: Row(children: [
                    Icon(item.$2, size: 16,
                      color: isSel ? cs.primary : cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(item.$3,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? cs.primary : cs.onSurface,
                      )),
                  ]),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Legend ──────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final ColorScheme cs;
  const _Legend({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            context.tr(
              pl: 'Przeciągnij między punktami siatki aby narysować odcinek',
              en: 'Drag between grid points to draw a segment',
            ),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  final List<_Seg> segs;
  final Offset? startPt;
  final Offset? snapPt;
  final _SegType penType;
  final double s;
  final ColorScheme cs;

  const _CanvasPainter({
    required this.segs,
    required this.startPt,
    required this.snapPt,
    required this.penType,
    required this.s,
    required this.cs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGrid(canvas, size);
    _drawSegs(canvas);
    if (startPt != null && snapPt != null) _drawPreview(canvas);
  }

  // ── kratkowany papier ISO ──────────────────────────────────────────────────
  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = cs.surface,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final dy   = s * math.sqrt(3) / 2.0;
    final rows = (size.height / dy).ceil() + 2;
    final cols = (size.width / s).ceil() + 4;

    final dotPaint = Paint()
      ..color = cs.onSurface.withOpacity(0.22)
      ..strokeCap = StrokeCap.round;

    for (int row = 0; row <= rows; row++) {
      final y    = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : s / 2.0;
      for (int col = -1; col <= cols; col++) {
        canvas.drawCircle(Offset(col * s + xOff, y), 2.0, dotPaint);
      }
    }
  }

  // ── narysowane odcinki ────────────────────────────────────────────────────
  void _drawSegs(Canvas canvas) {
    for (final seg in segs) {
      _drawSeg(canvas, seg.start, seg.end, seg.type, alpha: 1.0);
    }
  }

  void _drawSeg(Canvas canvas, Offset a, Offset b, _SegType type,
      {double alpha = 1.0}) {
    final color = cs.primary.withOpacity(alpha);
    switch (type) {
      case _SegType.pipe:
        // gruba linia rury + małe kropki na końcach
        canvas.drawLine(a, b,
          Paint()
            ..color = color
            ..strokeWidth = 4.5
            ..strokeCap = StrokeCap.round);
        canvas.drawCircle(a, 5.0, Paint()..color = color);
        canvas.drawCircle(b, 5.0, Paint()..color = color);
        break;

      case _SegType.thin:
        canvas.drawLine(a, b,
          Paint()
            ..color = color
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round);
        break;

      case _SegType.dashed:
        _drawDashed(canvas, a, b,
          Paint()
            ..color = color
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round);
        break;
    }
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLen = 8.0;
    const gapLen  = 6.0;
    final total   = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    double pos = 0;
    bool drawing = true;
    while (pos < total) {
      final segLen = math.min(drawing ? dashLen : gapLen, total - pos);
      if (drawing) {
        canvas.drawLine(a + dir * pos, a + dir * (pos + segLen), paint);
      }
      pos += segLen;
      drawing = !drawing;
    }
  }

  // ── podgląd rysowanego odcinka ────────────────────────────────────────────
  void _drawPreview(Canvas canvas) {
    // start — wyraźna kropka
    canvas.drawCircle(
      startPt!,
      7.0,
      Paint()..color = cs.primary,
    );
    // linia do snappowanego końca
    _drawSeg(canvas, startPt!, snapPt!, penType, alpha: 0.45);
    // snapowany koniec
    canvas.drawCircle(
      snapPt!,
      5.0,
      Paint()..color = cs.primary.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
    segs != old.segs ||
    startPt != old.startPt ||
    snapPt != old.snapPt;
}
