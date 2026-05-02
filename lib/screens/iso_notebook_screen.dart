import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

enum _Tool {
  // Line tools
  pipe, thin, dashed,
  // Component tools
  elbow, flange, valve, reducer, tee, weld,
}

extension _ToolX on _Tool {
  bool get isLine => index <= _Tool.dashed.index;
  bool get isComp => !isLine;
}

abstract class _Item {}

class _Seg implements _Item {
  final Offset a, b;
  final _Tool t;
  const _Seg(this.a, this.b, this.t);
}

class _Comp implements _Item {
  final Offset pos;
  final _Tool t;
  final int dir; // 0–5, each step = 60° in isometric space
  const _Comp(this.pos, this.t, [this.dir = 0]);
  _Comp rotate() => _Comp(pos, t, (dir + 1) % 6);
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class IsoNotebookScreen extends StatefulWidget {
  const IsoNotebookScreen({super.key});
  @override
  State<IsoNotebookScreen> createState() => _IsoState();
}

class _IsoState extends State<IsoNotebookScreen> {
  static const double _s = 32.0;

  final List<_Item> _items = [];
  final List<List<_Item>> _undo = [];

  Offset? _dragA, _dragB; // line-draw preview
  _Tool _tool = _Tool.pipe;

  // ── isometric snap ────────────────────────────────────────────────────────
  Offset _snap(Offset raw) {
    final dy = _s * math.sqrt(3) / 2.0;
    Offset best = Offset.zero;
    double bestD = double.infinity;
    for (int dr = -3; dr <= 3; dr++) {
      final row = (raw.dy / dy).round() + dr;
      if (row < 0) continue;
      final y = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : _s / 2.0;
      for (int dc = -3; dc <= 3; dc++) {
        final col = ((raw.dx - xOff) / _s).round() + dc;
        final pt = Offset(col * _s + xOff, y);
        final d = (raw - pt).distance;
        if (d < bestD) {
          bestD = d;
          best = pt;
        }
      }
    }
    return best;
  }

  // ── line drawing (pan) ────────────────────────────────────────────────────
  void _panStart(DragStartDetails d) {
    if (_tool.isComp) return;
    setState(() {
      _dragA = _snap(d.localPosition);
      _dragB = _dragA;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_tool.isComp) return;
    setState(() => _dragB = _snap(d.localPosition));
  }

  void _panEnd(DragEndDetails _) {
    if (_tool.isComp || _dragA == null || _dragB == null) return;
    if ((_dragB! - _dragA!).distance > _s * 0.25) {
      _push();
      _items.add(_Seg(_dragA!, _dragB!, _tool));
    }
    setState(() { _dragA = null; _dragB = null; });
  }

  // ── component placement (tap) ─────────────────────────────────────────────
  void _tapUp(TapUpDetails d) {
    if (_tool.isLine) return;
    final pt = _snap(d.localPosition);
    // Tap on existing component → rotate it
    final idx = _items.indexWhere(
      (it) => it is _Comp && (it.pos - pt).distance < _s * 0.45,
    );
    if (idx >= 0) {
      _push();
      setState(() => _items[idx] = (_items[idx] as _Comp).rotate());
    } else {
      // Place new component
      _push();
      setState(() => _items.add(_Comp(pt, _tool)));
    }
  }

  // Long-press to delete the nearest component
  void _longPress(LongPressStartDetails d) {
    final pt = _snap(d.localPosition);
    final idx = _items.indexWhere(
      (it) => it is _Comp && (it.pos - pt).distance < _s * 0.6,
    );
    if (idx >= 0) {
      _push();
      setState(() => _items.removeAt(idx));
    }
  }

  // ── undo/clear ────────────────────────────────────────────────────────────
  void _push() => _undo.add(List.from(_items));

  void _undoAction() {
    if (_undo.isEmpty) return;
    setState(() => _items..clear()..addAll(_undo.removeLast()));
  }

  void _clear() {
    if (_items.isEmpty) return;
    _push();
    setState(() => _items.clear());
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Zeszyt ISO', en: 'ISO Notebook')),
        actions: [
          HelpButton(help: kHelpIsoNotebook),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: context.tr(pl: 'Cofnij', en: 'Undo'),
            onPressed: _undo.isEmpty ? null : _undoAction,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Clear all'),
            onPressed: _items.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(tool: _tool, onTool: (t) => setState(() => _tool = t), cs: cs),
          Expanded(
            child: GestureDetector(
              onPanStart: _panStart,
              onPanUpdate: _panUpdate,
              onPanEnd: _panEnd,
              onTapUp: _tapUp,
              onLongPressStart: _longPress,
              child: CustomPaint(
                painter: _Painter(
                  items: _items,
                  dragA: _dragA,
                  dragB: _dragB,
                  tool: _tool,
                  s: _s,
                  cs: cs,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          _Hint(tool: _tool, cs: cs),
        ],
      ),
    );
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final _Tool tool;
  final ValueChanged<_Tool> onTool;
  final ColorScheme cs;
  const _Toolbar({required this.tool, required this.onTool, required this.cs});

  @override
  Widget build(BuildContext context) {
    final lineItems = [
      (_Tool.pipe,   Icons.remove,          context.tr(pl: 'Rura',   en: 'Pipe')),
      (_Tool.thin,   Icons.horizontal_rule, context.tr(pl: 'Linia',  en: 'Line')),
      (_Tool.dashed, Icons.more_horiz,      context.tr(pl: 'Ukryta', en: 'Hidden')),
    ];
    final compItems = [
      (_Tool.elbow,   Icons.turn_right,               context.tr(pl: 'Kolano',   en: 'Elbow')),
      (_Tool.flange,  Icons.view_column_outlined,     context.tr(pl: 'Kołnierz', en: 'Flange')),
      (_Tool.valve,   Icons.settings_input_svideo,    context.tr(pl: 'Zawór',    en: 'Valve')),
      (_Tool.reducer, Icons.compress,                 context.tr(pl: 'Redukcja', en: 'Reducer')),
      (_Tool.tee,     Icons.call_split,               context.tr(pl: 'Trójnik',  en: 'Tee')),
      (_Tool.weld,    Icons.radio_button_checked,     context.tr(pl: 'Spoina',   en: 'Weld')),
    ];

    Widget chip(_Tool t, IconData icon, String label) {
      final sel = tool == t;
      return GestureDetector(
        onTap: () => onTool(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: sel ? cs.primary : cs.outlineVariant,
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: sel ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel ? cs.primary : cs.onSurface,
              )),
          ]),
        ),
      );
    }

    return Container(
      color: cs.surfaceContainerHigh,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Row 1: line tools
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(children: [
            Text(context.tr(pl: 'Linia  ', en: 'Lines  '),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
            ...lineItems.map((e) => chip(e.$1, e.$2, e.$3)),
            const SizedBox(width: 12),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            const SizedBox(width: 12),
            Text(context.tr(pl: 'Komponenty  ', en: 'Components  '),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
            ...compItems.map((e) => chip(e.$1, e.$2, e.$3)),
          ]),
        ),
      ]),
    );
  }
}

// ─── Hint bar ────────────────────────────────────────────────────────────────

class _Hint extends StatelessWidget {
  final _Tool tool;
  final ColorScheme cs;
  const _Hint({required this.tool, required this.cs});

  @override
  Widget build(BuildContext context) {
    final msg = tool.isLine
        ? context.tr(
            pl: 'Przeciągnij między punktami siatki aby narysować odcinek',
            en: 'Drag between grid points to draw a segment')
        : context.tr(
            pl: 'Dotknij → umieść  •  Dotknij ponownie → obróć  •  Przytrzymaj → usuń',
            en: 'Tap → place  •  Tap again → rotate  •  Long-press → remove');
    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          tool.isLine ? Icons.touch_app_outlined : Icons.info_outline,
          size: 13,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(msg,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _Painter extends CustomPainter {
  final List<_Item> items;
  final Offset? dragA, dragB;
  final _Tool tool;
  final double s;
  final ColorScheme cs;

  const _Painter({
    required this.items,
    required this.dragA,
    required this.dragB,
    required this.tool,
    required this.s,
    required this.cs,
  });

  static const _sqrt3 = 1.7320508075688772;

  // ── 6 isometric direction unit vectors (screen coords, y-down) ────────────
  // dir 0: right | 1: up-right | 2: up-left | 3: left | 4: down-left | 5: down-right
  static const _dirVec = [
    Offset( 1.0,     0.0),
    Offset( 0.5,    -0.8660254),
    Offset(-0.5,    -0.8660254),
    Offset(-1.0,     0.0),
    Offset(-0.5,     0.8660254),
    Offset( 0.5,     0.8660254),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _drawBg(canvas, size);
    _drawGrid(canvas, size);
    _drawItems(canvas);
    if (dragA != null && dragB != null) _drawPreview(canvas);
  }

  // ── background ────────────────────────────────────────────────────────────
  void _drawBg(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = cs.surface,
    );
  }

  // ── isometric grid (3 families of parallel lines) ─────────────────────────
  void _drawGrid(Canvas canvas, Size size) {
    final dy = s * _sqrt3 / 2.0;       // vertical row spacing
    final cStep = _sqrt3 * s;          // c-step for diagonal families
    final gridPaint = Paint()
      ..color = cs.onSurface.withOpacity(0.10)
      ..strokeWidth = 0.65;

    // ── Family 1: horizontal lines at y = k * dy ───────────────────────────
    for (double y = 0; y <= size.height + dy; y += dy) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── Family 2: slope +√3 (60° up-right)  y = √3·x + c ─────────────────
    {
      final cMin = -_sqrt3 * size.width - cStep;
      final cMax = size.height + cStep;
      int k = (cMin / cStep).floor();
      while (k * cStep <= cMax) {
        final c = k * cStep;
        double x1, y1, x2, y2;
        if (c >= 0) { x1 = 0; y1 = c; }
        else        { x1 = -c / _sqrt3; y1 = 0; }
        final yR = _sqrt3 * size.width + c;
        if (yR <= size.height) { x2 = size.width; y2 = yR; }
        else                   { x2 = (size.height - c) / _sqrt3; y2 = size.height; }
        if (x2 >= 0 && x1 <= size.width) {
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), gridPaint);
        }
        k++;
      }
    }

    // ── Family 3: slope −√3 (120° up-left)  y = −√3·x + c ────────────────
    {
      final cMin = -cStep;
      final cMax = size.height + _sqrt3 * size.width + cStep;
      int k = (cMin / cStep).floor();
      while (k * cStep <= cMax) {
        final c = k * cStep;
        double x1, y1, x2, y2;
        if (c >= 0 && c <= size.height) { x1 = 0; y1 = c; }
        else if (c > size.height)       { x1 = (c - size.height) / _sqrt3; y1 = size.height; }
        else                            { x1 = c / _sqrt3; y1 = 0; }
        final yR = c - _sqrt3 * size.width;
        if (yR >= 0 && yR <= size.height) { x2 = size.width; y2 = yR; }
        else if (yR < 0)                  { x2 = c / _sqrt3; y2 = 0; }
        else                              { x2 = (c - size.height) / _sqrt3; y2 = size.height; }
        if (x2 >= 0 && x1 <= size.width) {
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), gridPaint);
        }
        k++;
      }
    }

    // ── Intersection dots (snap points) ───────────────────────────────────
    final dotPaint = Paint()
      ..color = cs.onSurface.withOpacity(0.22)
      ..strokeCap = StrokeCap.round;
    final rows = (size.height / dy).ceil() + 2;
    final cols = (size.width  / s ).ceil() + 4;
    for (int row = 0; row <= rows; row++) {
      final y    = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : s / 2.0;
      for (int col = -1; col <= cols; col++) {
        canvas.drawCircle(Offset(col * s + xOff, y), 1.5, dotPaint);
      }
    }
  }

  // ── all items ─────────────────────────────────────────────────────────────
  void _drawItems(Canvas canvas) {
    for (final it in items) {
      if (it is _Seg)  _drawSeg(canvas, it.a, it.b, it.t, alpha: 1.0);
      if (it is _Comp) _drawComp(canvas, it);
    }
  }

  // ── line segment ──────────────────────────────────────────────────────────
  void _drawSeg(Canvas canvas, Offset a, Offset b, _Tool t, {double alpha = 1.0}) {
    final color = cs.primary.withOpacity(alpha);
    switch (t) {
      case _Tool.pipe:
        canvas.drawLine(a, b,
          Paint()..color = color..strokeWidth = 5.0..strokeCap = StrokeCap.round);
        canvas.drawCircle(a, 5.5, Paint()..color = color);
        canvas.drawCircle(b, 5.5, Paint()..color = color);
      case _Tool.thin:
        canvas.drawLine(a, b,
          Paint()..color = color..strokeWidth = 1.5..strokeCap = StrokeCap.round);
      case _Tool.dashed:
        _dashed(canvas, a, b,
          Paint()..color = color..strokeWidth = 2.0..strokeCap = StrokeCap.round);
      default: break;
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 8.0, gap = 6.0;
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    double pos = 0;
    bool on = true;
    while (pos < total) {
      final len = math.min(on ? dash : gap, total - pos);
      if (on) canvas.drawLine(a + dir * pos, a + dir * (pos + len), p);
      pos += len;
      on = !on;
    }
  }

  // ── draw-preview while dragging ───────────────────────────────────────────
  void _drawPreview(Canvas canvas) {
    canvas.drawCircle(dragA!, 7.0, Paint()..color = cs.primary);
    _drawSeg(canvas, dragA!, dragB!, tool, alpha: 0.45);
    canvas.drawCircle(dragB!, 5.5,
      Paint()..color = cs.primary.withOpacity(0.6));
  }

  // ── component ─────────────────────────────────────────────────────────────
  void _drawComp(Canvas canvas, _Comp c) {
    canvas.save();
    canvas.translate(c.pos.dx, c.pos.dy);
    // Rotate so local +x aligns with isometric direction c.dir
    canvas.rotate(-c.dir * math.pi / 3.0);
    final r = s * 0.46;
    switch (c.t) {
      case _Tool.elbow:   _symElbow(canvas, r);   break;
      case _Tool.flange:  _symFlange(canvas, r);  break;
      case _Tool.valve:   _symValve(canvas, r);   break;
      case _Tool.reducer: _symReducer(canvas, r); break;
      case _Tool.tee:     _symTee(canvas, r);     break;
      case _Tool.weld:    _symWeld(canvas, r);    break;
      default: break;
    }
    canvas.restore();
  }

  // In symbol methods: origin = snap point, +x = primary pipe direction, +y = screen-down

  Paint get _pipePaint => Paint()
    ..color = cs.primary
    ..strokeWidth = 5.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  Paint get _symPaint => Paint()
    ..color = cs.secondary
    ..strokeWidth = 2.8
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  Paint get _symFill => Paint()
    ..color = cs.secondary
    ..style = PaintingStyle.fill;

  // ELBOW — L-bend: pipe comes from −x, turns to +y
  void _symElbow(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), const Offset(0, 0), p);
    canvas.drawLine(const Offset(0, 0), Offset(0, r), p);
    // Arc at corner
    final arcR = r * 0.45;
    final arcRect = Rect.fromCircle(
      center: Offset(-arcR, arcR), radius: arcR);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi / 2, false,
      Paint()
        ..color = cs.secondary
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke);
    // Node dot
    canvas.drawCircle(Offset.zero, 4.5, Paint()..color = cs.secondary);
  }

  // FLANGE — two short perpendicular bars flanking the pipe axis
  void _symFlange(Canvas canvas, double r) {
    final p = _pipePaint;
    // Pipe stubs
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.22, 0), p);
    canvas.drawLine(Offset(r * 0.22, 0), Offset(r, 0), p);
    // Two flange bars
    final sp = _symPaint..strokeWidth = 3.2;
    canvas.drawLine(Offset(-r * 0.22, -r * 0.48), Offset(-r * 0.22, r * 0.48), sp);
    canvas.drawLine(Offset( r * 0.22, -r * 0.48), Offset( r * 0.22, r * 0.48), sp);
  }

  // VALVE — gate valve symbol: two filled triangles meeting at apex
  void _symValve(Canvas canvas, double r) {
    final p = _pipePaint;
    // Pipe stubs
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.3, 0), p);
    canvas.drawLine(Offset(r * 0.3, 0), Offset(r, 0), p);
    // Left triangle (points right)
    final t1 = Path()
      ..moveTo(-r * 0.3, -r * 0.38)
      ..lineTo(0, 0)
      ..lineTo(-r * 0.3, r * 0.38)
      ..close();
    // Right triangle (points left)
    final t2 = Path()
      ..moveTo(r * 0.3, -r * 0.38)
      ..lineTo(0, 0)
      ..lineTo(r * 0.3, r * 0.38)
      ..close();
    canvas.drawPath(t1, _symFill);
    canvas.drawPath(t2, _symFill);
    // Stem line (bonnet)
    canvas.drawLine(const Offset(0, 0), Offset(0, -r * 0.5),
      _symPaint..strokeWidth = 2.5);
  }

  // REDUCER — tapering trapezoid
  void _symReducer(Canvas canvas, double r) {
    final p = _pipePaint;
    // Pipe stubs
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.28, 0), p);
    canvas.drawLine(Offset(r * 0.12, 0), Offset(r, 0),
      Paint()
        ..color = cs.primary
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    // Trapezoid body
    final path = Path()
      ..moveTo(-r * 0.28, -r * 0.38)
      ..lineTo( r * 0.12, -r * 0.18)
      ..lineTo( r * 0.12,  r * 0.18)
      ..lineTo(-r * 0.28,  r * 0.38)
      ..close();
    canvas.drawPath(path, _symPaint..strokeWidth = 2.5);
  }

  // TEE — through pipe on ±x, branch stub on −y
  void _symTee(Canvas canvas, double r) {
    final p = _pipePaint;
    // Through pipe
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
    // Branch
    canvas.drawLine(const Offset(0, 0), Offset(0, -r),
      Paint()
        ..color = cs.secondary
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    // Junction node
    canvas.drawCircle(Offset.zero, 5.0, Paint()..color = cs.secondary);
  }

  // WELD — butt-weld circle on the pipe
  void _symWeld(Canvas canvas, double r) {
    // Short pipe stubs
    canvas.drawLine(Offset(-r * 0.55, 0), Offset(-r * 0.22, 0), _pipePaint);
    canvas.drawLine(Offset( r * 0.22, 0), Offset( r * 0.55, 0), _pipePaint);
    // Weld ring
    canvas.drawCircle(
      Offset.zero, r * 0.22,
      Paint()
        ..color = cs.secondary
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke);
    // Filled centre dot
    canvas.drawCircle(Offset.zero, r * 0.07, _symFill);
  }

  @override
  bool shouldRepaint(_Painter old) =>
    items != old.items ||
    dragA != old.dragA ||
    dragB != old.dragB ||
    tool  != old.tool;
}
