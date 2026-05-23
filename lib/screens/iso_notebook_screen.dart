import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/iso_parser.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ISO NOTEBOOK — full piping isometric sketch pad with a built-in cut
// calculator. A fitter draws the run, types the ISO (face-to-face) dimension
// for each segment, lists the take-outs of the components on its ends
// (elbow centre-to-face, flange thickness, valve width…), and the app gives
// back the length of pipe to actually saw:
//
//   CUT = ISO − Σ (component take-outs)
// ═══════════════════════════════════════════════════════════════════════════

enum _Tool {
  // Lines
  pipe, thin, dashed,
  // Fittings & components — drawn on grid points, rotatable
  elbow90, elbow45, tee, reducer, flange, blindFlange, cap,
  gateValve, ballValve, checkValve,
  weld, fieldWeld, support, instrument,
  // Annotations
  northArrow, flowArrow, text,
}

extension _ToolX on _Tool {
  bool get isLine => index <= _Tool.dashed.index;
  bool get isText => this == _Tool.text;
  bool get isComp => !isLine && !isText;
  bool get isWeld => this == _Tool.weld || this == _Tool.fieldWeld;
}

abstract class _Item {}

/// One component whose take-out is subtracted from the ISO dimension to
/// arrive at the cut length.
class _Deduct {
  final String name;   // human label, e.g. "Elbow 90°", "Flange"
  final String value;  // expression in mm
  const _Deduct(this.name, this.value);
}

/// Full cut calculation for a pipe segment: ISO − Σ deducts.
/// When [deducts] is empty the segment carries a plain dimension; when it is
/// non-empty the on-drawing label shows the resolved CUT in an accent colour.
class _CutCalc {
  final String iso;
  final List<_Deduct> deducts;
  const _CutCalc(this.iso, {this.deducts = const []});

  bool get hasDeducts => deducts.isNotEmpty;

  /// Resolved cut length in mm. NaN if the ISO itself cannot be parsed;
  /// unreadable deducts are skipped (so partial input still gives a number).
  double get cutMm {
    double v;
    try {
      v = parseIsoExpression(iso);
    } catch (_) {
      return double.nan;
    }
    for (final d in deducts) {
      if (d.value.trim().isEmpty) continue;
      try {
        v -= parseIsoExpression(d.value);
      } catch (_) {
        // skip unreadable deduct
      }
    }
    return v;
  }
}

/// Dialog return value: distinguishes "set new value", "remove", "cancel".
class _CalcResult {
  final _CutCalc? calc;
  final bool remove;
  const _CalcResult.set(this.calc) : remove = false;
  const _CalcResult.removed() : calc = null, remove = true;
}

class _Seg implements _Item {
  final Offset a, b;
  final _Tool t;
  final _CutCalc? calc;
  const _Seg(this.a, this.b, this.t, {this.calc});
  _Seg withCalc(_CutCalc? c) => _Seg(a, b, t, calc: c);
  bool get hasDim => calc != null;
}

class _Comp implements _Item {
  final Offset pos;
  final _Tool t;
  final int dir;
  final String label;
  const _Comp(this.pos, this.t, {this.dir = 0, this.label = ''});
  _Comp rotate() => _Comp(pos, t, dir: (dir + 1) % 6, label: label);
}

class _Note implements _Item {
  final Offset pos;
  final String text;
  const _Note(this.pos, this.text);
  _Note withText(String t) => _Note(pos, t);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class IsoNotebookScreen extends StatefulWidget {
  const IsoNotebookScreen({super.key});
  @override
  State<IsoNotebookScreen> createState() => _IsoState();
}

class _IsoState extends State<IsoNotebookScreen> {
  static const double _s = 32.0;

  final List<_Item> _items = [];
  final List<List<_Item>> _undo = [];
  int _version = 0; // bumped on every mutation → forces a repaint

  Offset? _dragA, _dragB;
  _Tool _tool = _Tool.pipe;
  String _projectName = '';

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  void _mutate(VoidCallback f) {
    setState(() {
      f();
      _version++;
    });
  }

  // ── isometric snap ──────────────────────────────────────────────────────────
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

  double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  // ── line drawing (pan) ──────────────────────────────────────────────────────
  void _panStart(DragStartDetails d) {
    if (!_tool.isLine) return;
    setState(() {
      _dragA = _snap(d.localPosition);
      _dragB = _dragA;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (!_tool.isLine) return;
    setState(() => _dragB = _snap(d.localPosition));
  }

  Future<void> _panEnd(DragEndDetails _) async {
    if (!_tool.isLine || _dragA == null || _dragB == null) return;
    final a = _dragA!, b = _dragB!;
    final tool = _tool;
    setState(() {
      _dragA = null;
      _dragB = null;
    });
    if ((b - a).distance <= _s * 0.25) return;

    _push();
    final seg = _Seg(a, b, tool);
    _mutate(() => _items.add(seg));

    // Pipe runs always carry a dimension on an ISO — ask for it right away.
    if (tool == _Tool.pipe) {
      final res = await _askCalc(null);
      if (!mounted) return;
      if (res != null && res.calc != null) {
        final idx = _items.indexOf(seg);
        if (idx >= 0) _mutate(() => _items[idx] = seg.withCalc(res.calc));
      }
    }
  }

  // ── next weld number ────────────────────────────────────────────────────────
  int _nextWeldNo() {
    int best = 0;
    for (final it in _items) {
      if (it is _Comp && it.t.isWeld) {
        final n = int.tryParse(it.label) ?? 0;
        if (n > best) best = n;
      }
    }
    return best + 1;
  }

  // ── tap ─────────────────────────────────────────────────────────────────────
  Future<void> _tapUp(TapUpDetails d) async {
    final raw = d.localPosition;

    if (_tool.isLine) {
      final hit = _nearestSeg(raw);
      if (hit >= 0) {
        final seg = _items[hit] as _Seg;
        final res = await _askCalc(seg.calc);
        if (res != null && mounted) {
          _push();
          if (res.remove) {
            _mutate(() => _items[hit] = seg.withCalc(null));
          } else {
            _mutate(() => _items[hit] = seg.withCalc(res.calc));
          }
        }
      }
      return;
    }

    if (_tool.isText) {
      final hitNote = _items.indexWhere(
        (it) => it is _Note && (it.pos - raw).distance < _s * 1.2,
      );
      if (hitNote >= 0) {
        final note = _items[hitNote] as _Note;
        final txt = await _askText(note.text);
        if (txt != null && mounted) {
          _push();
          _mutate(() {
            if (txt.isEmpty) {
              _items.removeAt(hitNote);
            } else {
              _items[hitNote] = note.withText(txt);
            }
          });
        }
      } else {
        final txt = await _askText('');
        if (txt != null && txt.isNotEmpty && mounted) {
          _push();
          _mutate(() => _items.add(_Note(_snap(raw), txt)));
        }
      }
      return;
    }

    final pt = _snap(raw);
    final idx = _items.indexWhere(
      (it) => it is _Comp && (it.pos - pt).distance < _s * 0.45,
    );
    if (idx >= 0) {
      _push();
      _mutate(() => _items[idx] = (_items[idx] as _Comp).rotate());
      return;
    }

    if (_tool == _Tool.instrument) {
      final tag = await _askText('', instrument: true);
      if (tag == null || !mounted) return;
      _push();
      _mutate(() => _items.add(_Comp(pt, _tool, label: tag)));
      return;
    }

    _push();
    _mutate(() {
      final label = _tool.isWeld ? '${_nextWeldNo()}' : '';
      _items.add(_Comp(pt, _tool, label: label));
    });
  }

  int _nearestSeg(Offset raw) {
    int best = -1;
    double bestD = _s * 0.5;
    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it is _Seg) {
        final dist = _distToSeg(raw, it.a, it.b);
        if (dist < bestD) {
          bestD = dist;
          best = i;
        }
      }
    }
    return best;
  }

  void _longPress(LongPressStartDetails d) {
    final raw = d.localPosition;
    final pt = _snap(raw);
    final compIdx = _items.indexWhere(
      (it) => it is _Comp && (it.pos - pt).distance < _s * 0.6,
    );
    if (compIdx >= 0) {
      _push();
      _mutate(() => _items.removeAt(compIdx));
      return;
    }
    final noteIdx = _items.indexWhere(
      (it) => it is _Note && (it.pos - raw).distance < _s * 1.4,
    );
    if (noteIdx >= 0) {
      _push();
      _mutate(() => _items.removeAt(noteIdx));
      return;
    }
    final segIdx = _nearestSeg(raw);
    if (segIdx >= 0) {
      _push();
      _mutate(() => _items.removeAt(segIdx));
    }
  }

  // ── dimension + cut-calc dialog ─────────────────────────────────────────────
  Future<_CalcResult?> _askCalc(_CutCalc? current) async {
    final isoCtrl = TextEditingController(text: current?.iso ?? '');
    final rows = <(TextEditingController name, TextEditingController value)>[];
    for (final d in current?.deducts ?? const <_Deduct>[]) {
      rows.add((
        TextEditingController(text: d.name),
        TextEditingController(text: d.value),
      ));
    }
    bool calcMode = current?.hasDeducts ?? false;

    return showDialog<_CalcResult>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) {
          final cs = Theme.of(dctx).colorScheme;

          // Live evaluation.
          double? isoMm;
          try {
            if (isoCtrl.text.trim().isNotEmpty) {
              isoMm = parseIsoExpression(isoCtrl.text);
            }
          } catch (_) {}
          double deductSum = 0;
          for (final r in rows) {
            if (r.$2.text.trim().isEmpty) continue;
            try {
              deductSum += parseIsoExpression(r.$2.text);
            } catch (_) {}
          }
          final cutMm = (isoMm == null) ? null : isoMm - deductSum;

          void rebuild() => setLocal(() {});

          return AlertDialog(
            title: Text(_tr('Wymiar / cięcie odcinka',
                'Segment dimension / cut')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Mode switch ──────────────────────────────────────────
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: false,
                            label: Text(_tr('Wymiar', 'Dimension')),
                            icon: const Icon(Icons.straighten)),
                        ButtonSegment(
                            value: true,
                            label: Text(_tr('Oblicz cięcie', 'Cut calc')),
                            icon: const Icon(Icons.content_cut)),
                      ],
                      selected: {calcMode},
                      onSelectionChanged: (s) =>
                          setLocal(() => calcMode = s.first),
                    ),
                    const SizedBox(height: 14),

                    // ── ISO field (used in both modes) ───────────────────────
                    Text(
                      calcMode
                          ? _tr('Wymiar ISO segmentu (czoło-czoło / oś-oś)',
                              'ISO dimension (face-to-face / centre-to-centre)')
                          : _tr('Wymiar odcinka', 'Segment dimension'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: isoCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: _tr('np. 1500 lub 3000+525-80',
                            'e.g. 1500 or 3000+525-80'),
                        suffixText: 'mm',
                      ),
                      onChanged: (_) => rebuild(),
                    ),

                    if (calcMode) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            _tr('Odejmij komponenty', 'Subtract components'),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.4),
                          ),
                          const Spacer(),
                          Text(
                            '${rows.length}',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (var i = 0; i < rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Text('−',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: cs.tertiary)),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  controller: rows[i].$1,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: _tr('komponent',
                                        'component'),
                                  ),
                                  onChanged: (_) => rebuild(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: rows[i].$2,
                                  keyboardType: TextInputType.text,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: '76',
                                    suffixText: 'mm',
                                  ),
                                  onChanged: (_) => rebuild(),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setLocal(() {
                                  rows.removeAt(i);
                                }),
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(
                              _tr('Dodaj komponent', 'Add component')),
                          onPressed: () => setLocal(() {
                            rows.add((
                              TextEditingController(),
                              TextEditingController(),
                            ));
                          }),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // ── Live result card ───────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.tertiary.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(_tr('ISO', 'ISO'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant)),
                                const Spacer(),
                                Text(
                                  isoMm == null
                                      ? '—'
                                      : '${isoMm.toStringAsFixed(1)} mm',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface),
                                ),
                              ],
                            ),
                            if (rows.isNotEmpty)
                              Row(
                                children: [
                                  Text(_tr('Suma odejmowań', 'Total deducts'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant)),
                                  const Spacer(),
                                  Text(
                                    '− ${deductSum.toStringAsFixed(1)} mm',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: cs.tertiary),
                                  ),
                                ],
                              ),
                            const Divider(),
                            Row(
                              children: [
                                Text(
                                  _tr('CUT — rura do ucięcia',
                                      'CUT — pipe to saw'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface),
                                ),
                                const Spacer(),
                                Text(
                                  cutMm == null
                                      ? '—'
                                      : '${cutMm.toStringAsFixed(1)} mm',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: (cutMm != null && cutMm < 0)
                                          ? cs.error
                                          : cs.primary,
                                      letterSpacing: -0.3),
                                ),
                              ],
                            ),
                            if (cutMm != null && cutMm < 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _tr(
                                      'Komponenty dłuższe niż ISO — sprawdź wymiary.',
                                      'Components longer than ISO — check dimensions.'),
                                  style: TextStyle(
                                      fontSize: 11, color: cs.error),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else if (isoMm != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '= ${isoMm.toStringAsFixed(1)} mm',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Text(
                      _tr(
                          'Możesz wpisać działanie: + − × i nawiasy.',
                          'You can type an expression: + − × and brackets.'),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (current != null)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dctx, const _CalcResult.removed()),
                  child: Text(_tr('Usuń', 'Remove'),
                      style: TextStyle(color: Theme.of(dctx).colorScheme.error)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: Text(_tr('Anuluj', 'Cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  final iso = isoCtrl.text.trim();
                  if (iso.isEmpty) {
                    Navigator.pop(dctx, const _CalcResult.removed());
                    return;
                  }
                  final deducts = <_Deduct>[];
                  if (calcMode) {
                    for (final r in rows) {
                      final v = r.$2.text.trim();
                      if (v.isEmpty) continue;
                      deducts.add(_Deduct(r.$1.text.trim(), v));
                    }
                  }
                  Navigator.pop(
                      dctx,
                      _CalcResult.set(
                          _CutCalc(iso, deducts: List.unmodifiable(deducts))));
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── free text / instrument tag dialog ───────────────────────────────────────
  Future<String?> _askText(String current, {bool instrument = false}) async {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(instrument
            ? _tr('Oznaczenie instrumentu', 'Instrument tag')
            : _tr('Tekst na rysunku', 'Drawing text')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: instrument
                    ? _tr('np. PI-01, TI-12', 'e.g. PI-01, TI-12')
                    : _tr('np. nr linii, EL +100.000',
                        'e.g. line no., EL +100.000'),
              ),
              onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
            ),
            if (!instrument)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _tr('Numer linii, rzędna, klasa rurociągu, notatka montażowa.',
                      'Line number, elevation, pipe class, erection note.'),
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(dctx).colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        actions: [
          if (current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dctx, ''),
              child: Text(_tr('Usuń', 'Remove'),
                  style: TextStyle(color: Theme.of(dctx).colorScheme.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, null),
            child: Text(_tr('Anuluj', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _projectName);
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(_tr('Nazwa rysunku / nr linii', 'Drawing name / line no.')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _tr('np. 6"-CWS-1234', 'e.g. 6"-CWS-1234'),
          ),
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, null),
            child: Text(_tr('Anuluj', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name != null) setState(() => _projectName = name);
  }

  // ── summary / BOM ───────────────────────────────────────────────────────────
  List<_Seg> get _pipes =>
      _items.whereType<_Seg>().where((s) => s.t == _Tool.pipe).toList();

  /// Total of all resolved CUTs (deducts already applied).
  double get _totalMm {
    double sum = 0;
    for (final s in _pipes) {
      final c = s.calc;
      if (c == null) continue;
      final v = c.cutMm;
      if (v.isFinite) sum += v;
    }
    return sum;
  }

  int get _dimensionedCount => _pipes.where((s) => s.calc != null).length;

  static String compName(_Tool t, bool pl) {
    switch (t) {
      case _Tool.elbow90:     return pl ? 'Kolano 90°' : 'Elbow 90°';
      case _Tool.elbow45:     return pl ? 'Kolano 45°' : 'Elbow 45°';
      case _Tool.tee:         return pl ? 'Trójnik' : 'Tee';
      case _Tool.reducer:     return pl ? 'Redukcja' : 'Reducer';
      case _Tool.flange:      return pl ? 'Kołnierz' : 'Flange';
      case _Tool.blindFlange: return pl ? 'Kołnierz ślepy' : 'Blind flange';
      case _Tool.cap:         return pl ? 'Zaślepka' : 'Cap';
      case _Tool.gateValve:   return pl ? 'Zawór zasuwowy' : 'Gate valve';
      case _Tool.ballValve:   return pl ? 'Zawór kulowy' : 'Ball valve';
      case _Tool.checkValve:  return pl ? 'Zawór zwrotny' : 'Check valve';
      case _Tool.weld:        return pl ? 'Spoina warsztatowa' : 'Shop weld';
      case _Tool.fieldWeld:   return pl ? 'Spoina montażowa' : 'Field weld';
      case _Tool.support:     return pl ? 'Podpora' : 'Support';
      case _Tool.instrument:  return pl ? 'Instrument' : 'Instrument';
      case _Tool.northArrow:  return pl ? 'Strzałka północy' : 'North arrow';
      case _Tool.flowArrow:   return pl ? 'Kierunek przepływu' : 'Flow arrow';
      default:                return t.name;
    }
  }

  Future<void> _copySummary() async {
    final isPl = context.language == AppLanguage.pl;
    final buf = StringBuffer();
    buf.writeln(_projectName.isEmpty
        ? _tr('Szkic izometryczny', 'Isometric sketch')
        : _projectName);
    buf.writeln('═' * 32);

    final pipes = _pipes;
    if (pipes.isNotEmpty) {
      buf.writeln(_tr('CUT LIST', 'CUT LIST'));
      var n = 0;
      for (final s in pipes) {
        n++;
        final c = s.calc;
        if (c == null) {
          buf.writeln('  $n. ${_tr('(bez wymiaru)', '(no dimension)')}');
          continue;
        }
        final cut = c.cutMm;
        final cutStr = cut.isFinite
            ? '${cut.toStringAsFixed(1)} mm'
            : _tr('(nieczytelne)', '(unreadable)');
        if (c.hasDeducts) {
          buf.writeln('  $n. ${_tr('ISO', 'ISO')}: ${c.iso}');
          for (final d in c.deducts) {
            final tag = d.name.isEmpty ? '?' : d.name;
            buf.writeln('       − $tag: ${d.value}');
          }
          buf.writeln('     ${_tr('CUT', 'CUT')}: $cutStr');
        } else {
          buf.writeln('  $n. ${c.iso}'
              '${cut.isFinite ? ' = $cutStr' : ''}');
        }
      }
      buf.writeln('  ${'─' * 24}');
      buf.writeln('  ${_tr('Suma CUT', 'Total CUT')}: '
          '${_totalMm.toStringAsFixed(1)} mm');
      buf.writeln('');
    }

    final counts = <_Tool, int>{};
    for (final it in _items) {
      if (it is _Comp && it.t != _Tool.northArrow && it.t != _Tool.flowArrow) {
        counts[it.t] = (counts[it.t] ?? 0) + 1;
      }
    }
    if (counts.isNotEmpty) {
      buf.writeln(_tr('ZESTAWIENIE MATERIAŁOWE (BOM)', 'MATERIAL LIST (BOM)'));
      for (final e in counts.entries) {
        buf.writeln('  ${compName(e.key, isPl)}: ${e.value}');
      }
      buf.writeln('');
    }

    final welds = _items.whereType<_Comp>().where((c) => c.t.isWeld).toList();
    if (welds.isNotEmpty) {
      buf.writeln('${_tr('Spoiny razem', 'Total welds')}: ${welds.length}');
    }

    final notes = _items.whereType<_Note>().toList();
    if (notes.isNotEmpty) {
      buf.writeln('');
      buf.writeln(_tr('OPISY', 'NOTES'));
      for (final nt in notes) {
        buf.writeln('  • ${nt.text}');
      }
    }

    await copyToClipboard(context, buf.toString(),
        label: _tr('Zestawienie', 'Summary'));
  }

  // ── undo / clear ────────────────────────────────────────────────────────────
  void _push() => _undo.add(List.from(_items));

  void _undoAction() {
    if (_undo.isEmpty) return;
    _mutate(() => _items..clear()..addAll(_undo.removeLast()));
  }

  void _clear() {
    if (_items.isEmpty) return;
    _push();
    _mutate(_items.clear);
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasComp = _items.any((it) => it is _Comp || it is _Note);
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editName,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _projectName.isEmpty
                      ? _tr('Zeszyt ISO', 'ISO Notebook')
                      : _projectName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
        actions: [
          HelpButton(help: kHelpIsoNotebook),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _tr('Kopiuj zestawienie', 'Copy summary'),
            onPressed: (_pipes.isEmpty && !hasComp) ? null : _copySummary,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: _tr('Cofnij', 'Undo'),
            onPressed: _undo.isEmpty ? null : _undoAction,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: _tr('Wyczyść', 'Clear all'),
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
                  version: _version,
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
          _SummaryBar(
            tool: _tool,
            pipeCount: _pipes.length,
            dimensioned: _dimensionedCount,
            totalMm: _totalMm,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

// ─── Toolbar ──────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final _Tool tool;
  final ValueChanged<_Tool> onTool;
  final ColorScheme cs;
  const _Toolbar({required this.tool, required this.onTool, required this.cs});

  @override
  Widget build(BuildContext context) {
    final lineItems = <(_Tool, IconData, String)>[
      (_Tool.pipe,   Icons.remove,          context.tr(pl: 'Rura',   en: 'Pipe')),
      (_Tool.thin,   Icons.horizontal_rule, context.tr(pl: 'Linia',  en: 'Line')),
      (_Tool.dashed, Icons.more_horiz,      context.tr(pl: 'Ukryta', en: 'Hidden')),
    ];
    final fittingItems = <(_Tool, IconData, String)>[
      (_Tool.elbow90,     Icons.turn_right,            context.tr(pl: 'Kolano 90°', en: 'Elbow 90°')),
      (_Tool.elbow45,     Icons.turn_slight_right,     context.tr(pl: 'Kolano 45°', en: 'Elbow 45°')),
      (_Tool.tee,         Icons.call_split,            context.tr(pl: 'Trójnik',    en: 'Tee')),
      (_Tool.reducer,     Icons.compress,              context.tr(pl: 'Redukcja',   en: 'Reducer')),
      (_Tool.flange,      Icons.view_column_outlined,  context.tr(pl: 'Kołnierz',   en: 'Flange')),
      (_Tool.blindFlange, Icons.stop_circle_outlined,  context.tr(pl: 'Ślepy',      en: 'Blind')),
      (_Tool.cap,         Icons.crop_square,           context.tr(pl: 'Zaślepka',   en: 'Cap')),
      (_Tool.gateValve,   Icons.settings_input_svideo, context.tr(pl: 'Zasuwa',     en: 'Gate v.')),
      (_Tool.ballValve,   Icons.circle,                context.tr(pl: 'Kulowy',     en: 'Ball v.')),
      (_Tool.checkValve,  Icons.play_arrow,            context.tr(pl: 'Zwrotny',    en: 'Check v.')),
      (_Tool.weld,        Icons.radio_button_unchecked,context.tr(pl: 'Spoina W',   en: 'Shop weld')),
      (_Tool.fieldWeld,   Icons.radio_button_checked,  context.tr(pl: 'Spoina M',   en: 'Field weld')),
      (_Tool.support,     Icons.change_history,        context.tr(pl: 'Podpora',    en: 'Support')),
      (_Tool.instrument,  Icons.circle_outlined,       context.tr(pl: 'Instrument', en: 'Instrument')),
    ];
    final annoItems = <(_Tool, IconData, String)>[
      (_Tool.northArrow, Icons.navigation, context.tr(pl: 'Północ',   en: 'North')),
      (_Tool.flowArrow,  Icons.east,       context.tr(pl: 'Przepływ', en: 'Flow')),
      (_Tool.text,       Icons.text_fields,context.tr(pl: 'Tekst',    en: 'Text')),
    ];

    Widget chip((_Tool, IconData, String) e) {
      final sel = tool == e.$1;
      return GestureDetector(
        onTap: () => onTool(e.$1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: sel ? cs.primary : cs.outlineVariant,
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(e.$2, size: 15, color: sel ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(e.$3,
              style: TextStyle(
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel ? cs.primary : cs.onSurface,
              )),
          ]),
        ),
      );
    }

    Widget groupLabel(String s) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(s,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700)),
        );

    return Container(
      color: cs.surfaceContainerHigh,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 2),
          child: Row(children: [
            groupLabel(context.tr(pl: 'LINIE', en: 'LINES')),
            ...lineItems.map(chip),
            const SizedBox(width: 10),
            Container(width: 1, height: 20, color: cs.outlineVariant),
            const SizedBox(width: 10),
            groupLabel(context.tr(pl: 'KSZTAŁTKI', en: 'FITTINGS')),
            ...fittingItems.map(chip),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
          child: Row(children: [
            groupLabel(context.tr(pl: 'OPISY', en: 'ANNOTATIONS')),
            ...annoItems.map(chip),
          ]),
        ),
      ]),
    );
  }
}

// ─── Summary bar ──────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final _Tool tool;
  final int pipeCount;
  final int dimensioned;
  final double totalMm;
  final ColorScheme cs;
  const _SummaryBar({
    required this.tool,
    required this.pipeCount,
    required this.dimensioned,
    required this.totalMm,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final String hint;
    if (tool.isLine) {
      hint = context.tr(
          pl: 'Przeciągnij rurę → wpisz ISO / oblicz cięcie. Dotknij odcinka → edytuj.',
          en: 'Drag a pipe → enter ISO / cut calc. Tap a segment → edit.');
    } else if (tool.isText) {
      hint = context.tr(
          pl: 'Dotknij → dodaj tekst (nr linii, rzędna). Dotknij tekstu → edytuj.',
          en: 'Tap → add text (line no., elevation). Tap text → edit.');
    } else {
      hint = context.tr(
          pl: 'Dotknij → umieść • ponownie → obróć • przytrzymaj → usuń',
          en: 'Tap → place • again → rotate • long-press → remove');
    }

    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pipeCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.content_cut, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${context.tr(pl: 'Odcinki', en: 'Segments')}: '
                    '$dimensioned/$pipeCount',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                  const Spacer(),
                  Text(
                    '${context.tr(pl: 'Suma CUT', en: 'Total CUT')}: '
                    '${totalMm.toStringAsFixed(1)} mm',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: cs.primary),
                  ),
                ],
              ),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              tool.isComp ? Icons.info_outline : Icons.touch_app_outlined,
              size: 13,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(hint,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _Painter extends CustomPainter {
  final List<_Item> items;
  final int version; // ticks on every mutation so shouldRepaint catches it
  final Offset? dragA, dragB;
  final _Tool tool;
  final double s;
  final ColorScheme cs;

  const _Painter({
    required this.items,
    required this.version,
    required this.dragA,
    required this.dragB,
    required this.tool,
    required this.s,
    required this.cs,
  });

  static const _sqrt3 = 1.7320508075688772;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBg(canvas, size);
    _drawGrid(canvas, size);
    _drawItems(canvas);
    if (dragA != null && dragB != null) _drawPreview(canvas);
  }

  void _drawBg(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = cs.surface,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final dy = s * _sqrt3 / 2.0;
    final cStep = _sqrt3 * s;
    final gridPaint = Paint()
      ..color = cs.onSurface.withValues(alpha: 0.10)
      ..strokeWidth = 0.65;

    for (double y = 0; y <= size.height + dy; y += dy) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
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

    final dotPaint = Paint()
      ..color = cs.onSurface.withValues(alpha: 0.22)
      ..strokeCap = StrokeCap.round;
    final rows = (size.height / dy).ceil() + 2;
    final cols = (size.width / s).ceil() + 4;
    for (int row = 0; row <= rows; row++) {
      final y = row * dy;
      final xOff = (row % 2 == 0) ? 0.0 : s / 2.0;
      for (int col = -1; col <= cols; col++) {
        canvas.drawCircle(Offset(col * s + xOff, y), 1.5, dotPaint);
      }
    }
  }

  void _drawItems(Canvas canvas) {
    for (final it in items) {
      if (it is _Seg) _drawSeg(canvas, it.a, it.b, it.t, alpha: 1.0);
    }
    for (final it in items) {
      if (it is _Seg && it.calc != null) _drawDim(canvas, it);
    }
    for (final it in items) {
      if (it is _Comp) {
        _drawComp(canvas, it);
        if (it.label.isNotEmpty) _drawCompLabel(canvas, it);
      }
    }
    for (final it in items) {
      if (it is _Note) _drawNote(canvas, it);
    }
  }

  void _drawSeg(Canvas canvas, Offset a, Offset b, _Tool t, {double alpha = 1.0}) {
    final color = cs.primary.withValues(alpha: alpha);
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

  void _drawDim(Canvas canvas, _Seg seg) {
    final c = seg.calc!;
    final mid = (seg.a + seg.b) / 2;
    final d = seg.b - seg.a;
    final len = d.distance;
    if (len < 1) return;
    final norm = Offset(-d.dy / len, d.dx / len);
    final pos = mid + norm * 15;

    final cutMm = c.cutMm;
    final accent = c.hasDeducts ? cs.tertiary : cs.primary;

    String label;
    if (!cutMm.isFinite) {
      label = c.iso.isEmpty ? '?' : c.iso;
    } else {
      label = cutMm == cutMm.roundToDouble()
          ? cutMm.toStringAsFixed(0)
          : cutMm.toStringAsFixed(1);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: accent,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Small "cut" marker (scissors-like notch) when the value is a CUT result.
    final extraW = c.hasDeducts ? 10.0 : 0.0;
    final rect = Rect.fromCenter(
      center: pos, width: tp.width + 10 + extraW, height: tp.height + 5);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = cs.surface);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    final textOrigin =
        pos - Offset(tp.width / 2 - extraW / 2, tp.height / 2);
    tp.paint(canvas, textOrigin);

    if (c.hasDeducts) {
      // Tiny notch on the left side of the chip to read as "cut".
      final notchX = rect.left + 5;
      final cy = pos.dy;
      final stroke = Paint()
        ..color = accent
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(notchX, cy - 3), Offset(notchX + 4, cy + 3), stroke);
      canvas.drawLine(
          Offset(notchX, cy + 3), Offset(notchX + 4, cy - 3), stroke);
    }
  }

  void _drawNote(Canvas canvas, _Note note) {
    final tp = TextPainter(
      text: TextSpan(
        text: note.text,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: note.pos, width: tp.width + 12, height: tp.height + 7);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = cs.secondaryContainer);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = cs.secondary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, note.pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawPreview(Canvas canvas) {
    canvas.drawCircle(dragA!, 7.0, Paint()..color = cs.primary);
    _drawSeg(canvas, dragA!, dragB!, tool, alpha: 0.45);
    canvas.drawCircle(dragB!, 5.5,
      Paint()..color = cs.primary.withValues(alpha: 0.6));
  }

  void _drawComp(Canvas canvas, _Comp c) {
    canvas.save();
    canvas.translate(c.pos.dx, c.pos.dy);
    canvas.rotate(-c.dir * math.pi / 3.0);
    final r = s * 0.46;
    switch (c.t) {
      case _Tool.elbow90:     _symElbow90(canvas, r);   break;
      case _Tool.elbow45:     _symElbow45(canvas, r);   break;
      case _Tool.tee:         _symTee(canvas, r);       break;
      case _Tool.reducer:     _symReducer(canvas, r);   break;
      case _Tool.flange:      _symFlange(canvas, r);    break;
      case _Tool.blindFlange: _symBlind(canvas, r);     break;
      case _Tool.cap:         _symCap(canvas, r);       break;
      case _Tool.gateValve:   _symGate(canvas, r);      break;
      case _Tool.ballValve:   _symBall(canvas, r);      break;
      case _Tool.checkValve:  _symCheck(canvas, r);     break;
      case _Tool.weld:        _symWeld(canvas, r, false); break;
      case _Tool.fieldWeld:   _symWeld(canvas, r, true);  break;
      case _Tool.support:     _symSupport(canvas, r);   break;
      case _Tool.instrument:  _symInstrument(canvas, r);break;
      case _Tool.northArrow:  _symNorth(canvas, r);     break;
      case _Tool.flowArrow:   _symFlow(canvas, r);      break;
      default: break;
    }
    canvas.restore();
  }

  void _drawCompLabel(Canvas canvas, _Comp c) {
    final tp = TextPainter(
      text: TextSpan(
        text: c.label,
        style: TextStyle(
          color: c.t.isWeld ? cs.error : cs.onSurface,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pos = c.t == _Tool.instrument
        ? c.pos
        : c.pos + Offset(s * 0.32, -s * 0.36);
    if (c.t != _Tool.instrument) {
      final rect = Rect.fromCenter(
        center: pos, width: tp.width + 6, height: tp.height + 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = cs.surface,
      );
    }
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

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

  void _symElbow90(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(0, r), p);
    final arcR = r * 0.45;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(-arcR, arcR), radius: arcR),
      -math.pi / 2, math.pi / 2, false,
      Paint()..color = cs.secondary..strokeWidth = 2.5..style = PaintingStyle.stroke);
    canvas.drawCircle(Offset.zero, 4.5, Paint()..color = cs.secondary);
  }

  void _symElbow45(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(r * 0.5, r * 0.866), p);
    canvas.drawCircle(Offset.zero, 4.5, Paint()..color = cs.secondary);
  }

  void _symTee(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
    canvas.drawLine(Offset.zero, Offset(0, -r),
      Paint()..color = cs.secondary..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    canvas.drawCircle(Offset.zero, 5.0, Paint()..color = cs.secondary);
  }

  void _symReducer(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.28, 0), p);
    canvas.drawLine(Offset(r * 0.12, 0), Offset(r, 0),
      Paint()..color = cs.primary..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    final path = Path()
      ..moveTo(-r * 0.28, -r * 0.38)
      ..lineTo( r * 0.12, -r * 0.18)
      ..lineTo( r * 0.12,  r * 0.18)
      ..lineTo(-r * 0.28,  r * 0.38)
      ..close();
    canvas.drawPath(path, _symPaint..strokeWidth = 2.5);
  }

  void _symFlange(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.22, 0), p);
    canvas.drawLine(Offset(r * 0.22, 0), Offset(r, 0), p);
    final sp = _symPaint..strokeWidth = 3.2;
    canvas.drawLine(Offset(-r * 0.22, -r * 0.48), Offset(-r * 0.22, r * 0.48), sp);
    canvas.drawLine(Offset( r * 0.22, -r * 0.48), Offset( r * 0.22, r * 0.48), sp);
  }

  void _symBlind(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.16, 0), p);
    final sp = _symPaint..strokeWidth = 3.4;
    canvas.drawLine(Offset(-r * 0.16, -r * 0.5), Offset(-r * 0.16, r * 0.5), sp);
    final cap = Path()
      ..moveTo(-r * 0.16, -r * 0.5)
      ..lineTo(r * 0.12, -r * 0.32)
      ..lineTo(r * 0.12, r * 0.32)
      ..lineTo(-r * 0.16, r * 0.5)
      ..close();
    canvas.drawPath(cap, Paint()
      ..color = cs.secondary.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill);
  }

  void _symCap(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.12, 0), p);
    final dome = Path()
      ..moveTo(-r * 0.12, -r * 0.42)
      ..quadraticBezierTo(r * 0.5, 0, -r * 0.12, r * 0.42)
      ..close();
    canvas.drawPath(dome, Paint()
      ..color = cs.secondary.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill);
    canvas.drawPath(dome, _symPaint..strokeWidth = 2.4);
  }

  void _symGate(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.3, 0), p);
    canvas.drawLine(Offset(r * 0.3, 0), Offset(r, 0), p);
    final t1 = Path()
      ..moveTo(-r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(-r * 0.3, r * 0.38)..close();
    final t2 = Path()
      ..moveTo(r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(r * 0.3, r * 0.38)..close();
    canvas.drawPath(t1, _symFill);
    canvas.drawPath(t2, _symFill);
    canvas.drawLine(Offset.zero, Offset(0, -r * 0.5), _symPaint..strokeWidth = 2.5);
  }

  void _symBall(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.3, 0), p);
    canvas.drawLine(Offset(r * 0.3, 0), Offset(r, 0), p);
    final t1 = Path()
      ..moveTo(-r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(-r * 0.3, r * 0.38)..close();
    final t2 = Path()
      ..moveTo(r * 0.3, -r * 0.38)..lineTo(0, 0)..lineTo(r * 0.3, r * 0.38)..close();
    canvas.drawPath(t1, _symFill);
    canvas.drawPath(t2, _symFill);
    canvas.drawCircle(Offset.zero, r * 0.2, Paint()..color = cs.surface);
    canvas.drawCircle(Offset.zero, r * 0.2, _symPaint..strokeWidth = 2.4);
    canvas.drawLine(Offset.zero, Offset(0, -r * 0.55), _symPaint..strokeWidth = 2.5);
  }

  void _symCheck(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r, 0), Offset(-r * 0.34, 0), p);
    canvas.drawLine(Offset(r * 0.34, 0), Offset(r, 0), p);
    final tri = Path()
      ..moveTo(-r * 0.34, -r * 0.38)
      ..lineTo(r * 0.34, 0)
      ..lineTo(-r * 0.34, r * 0.38)
      ..close();
    canvas.drawPath(tri, _symFill);
    canvas.drawLine(Offset(r * 0.34, -r * 0.4), Offset(r * 0.34, r * 0.4),
      _symPaint..strokeWidth = 2.6);
  }

  void _symWeld(Canvas canvas, double r, bool field) {
    canvas.drawLine(Offset(-r * 0.55, 0), Offset(-r * 0.2, 0), _pipePaint);
    canvas.drawLine(Offset(r * 0.2, 0), Offset(r * 0.55, 0), _pipePaint);
    if (field) {
      canvas.drawCircle(Offset.zero, r * 0.26, _symFill);
    } else {
      canvas.drawCircle(Offset.zero, r * 0.24,
        Paint()..color = cs.secondary..strokeWidth = 2.8..style = PaintingStyle.stroke);
      canvas.drawCircle(Offset.zero, r * 0.07, _symFill);
    }
  }

  void _symSupport(Canvas canvas, double r) {
    final p = _pipePaint;
    canvas.drawLine(Offset(-r * 0.6, 0), Offset(r * 0.6, 0), p);
    final tri = Path()
      ..moveTo(0, 0)
      ..lineTo(-r * 0.32, r * 0.55)
      ..lineTo(r * 0.32, r * 0.55)
      ..close();
    canvas.drawPath(tri, _symPaint..strokeWidth = 2.4);
    canvas.drawLine(Offset(-r * 0.5, r * 0.55), Offset(r * 0.5, r * 0.55),
      _symPaint..strokeWidth = 2.4);
  }

  void _symInstrument(Canvas canvas, double r) {
    canvas.drawLine(Offset.zero, Offset(0, -r * 0.55),
      _symPaint..strokeWidth = 1.8);
    final c = Offset(0, -r * 0.95);
    canvas.drawCircle(c, r * 0.4, Paint()..color = cs.surface);
    canvas.drawCircle(c, r * 0.4, _symPaint..strokeWidth = 2.2);
  }

  void _symNorth(Canvas canvas, double r) {
    final shaft = Paint()
      ..color = cs.tertiary
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, r * 0.7), Offset(0, -r * 0.55), shaft);
    final head = Path()
      ..moveTo(0, -r * 0.95)
      ..lineTo(-r * 0.28, -r * 0.45)
      ..lineTo(r * 0.28, -r * 0.45)
      ..close();
    canvas.drawPath(head, Paint()..color = cs.tertiary);
    final tp = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(
            color: cs.tertiary, fontSize: 13, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, r * 0.72));
  }

  void _symFlow(Canvas canvas, double r) {
    final paint = Paint()
      ..color = cs.tertiary
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.6, 0), Offset(r * 0.35, 0), paint);
    final head = Path()
      ..moveTo(r * 0.62, 0)
      ..lineTo(r * 0.2, -r * 0.3)
      ..lineTo(r * 0.2, r * 0.3)
      ..close();
    canvas.drawPath(head, Paint()..color = cs.tertiary);
  }

  @override
  bool shouldRepaint(_Painter old) =>
      version != old.version ||
      dragA != old.dragA ||
      dragB != old.dragB ||
      tool != old.tool;
}
