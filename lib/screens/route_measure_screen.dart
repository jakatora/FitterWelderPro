import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

enum _RefType { outer, center, inner }

enum _Mode { angle, horizontal, vertical }

class RouteMeasureScreen extends StatefulWidget {
  const RouteMeasureScreen({super.key});

  @override
  State<RouteMeasureScreen> createState() => _RouteMeasureScreenState();
}

class _RouteMeasureScreenState extends State<RouteMeasureScreen> {
  final _hypCtrl    = TextEditingController(); // c — hypotenuse (skos)
  final _odLeftCtrl  = TextEditingController();
  final _odRightCtrl = TextEditingController();
  final _inputCtrl  = TextEditingController(); // angle OR side a OR side b

  _RefType _leftRef  = _RefType.outer;
  _RefType _rightRef = _RefType.outer;
  _Mode    _mode     = _Mode.angle;

  // Results
  double? _ccc;   // corrected hypotenuse (C-C)
  double? _a;     // horizontal side
  double? _b;     // vertical side
  double? _alpha; // α in degrees
  double? _beta;  // β in degrees
  String? _error;

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  double _corrFor(_RefType ref, double od) {
    switch (ref) {
      case _RefType.outer:  return -od / 2.0;
      case _RefType.center: return 0.0;
      case _RefType.inner:  return  od / 2.0;
    }
  }

  void _recalc() {
    final c       = _parse(_hypCtrl.text);
    final odLeft  = _parse(_odLeftCtrl.text);
    final odRight = _parse(_odRightCtrl.text);
    final input   = _parse(_inputCtrl.text);

    if (c <= 0) {
      setState(() { _ccc = _a = _b = _alpha = _beta = null; _error = null; });
      return;
    }

    final ccc = c + _corrFor(_leftRef, odLeft) + _corrFor(_rightRef, odRight);
    if (ccc <= 0) {
      setState(() { _ccc = null; _a = _b = _alpha = _beta = null; _error = 'C-C ≤ 0'; });
      return;
    }

    double? a, b, alpha;
    String? err;

    switch (_mode) {
      case _Mode.angle:
        if (input > 0 && input < 90) {
          final rad = input * math.pi / 180.0;
          a     = ccc * math.cos(rad);
          b     = ccc * math.sin(rad);
          alpha = input;
        }
        break;

      case _Mode.horizontal:
        if (input > 0 && input < ccc) {
          b     = math.sqrt(ccc * ccc - input * input);
          a     = input;
          alpha = math.acos(input / ccc) * 180.0 / math.pi;
        } else if (input >= ccc) {
          err = context.tr(pl: 'a ≥ c — bok musi być krótszy od skosu', en: 'a ≥ c — side must be shorter than hypotenuse');
        }
        break;

      case _Mode.vertical:
        if (input > 0 && input < ccc) {
          a     = math.sqrt(ccc * ccc - input * input);
          b     = input;
          alpha = math.asin(input / ccc) * 180.0 / math.pi;
        } else if (input >= ccc) {
          err = context.tr(pl: 'b ≥ c — bok musi być krótszy od skosu', en: 'b ≥ c — side must be shorter than hypotenuse');
        }
        break;
    }

    setState(() {
      _ccc   = ccc;
      _a     = a;
      _b     = b;
      _alpha = alpha;
      _beta  = alpha != null ? 90.0 - alpha : null;
      _error = err;
    });
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_hypCtrl, _odLeftCtrl, _odRightCtrl, _inputCtrl]) {
      c.addListener(_recalc);
    }
  }

  @override
  void dispose() {
    for (final c in [_hypCtrl, _odLeftCtrl, _odRightCtrl, _inputCtrl]) {
      c.removeListener(_recalc);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Pomiar trasy – trójkąt', en: 'Route measurement – triangle')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hypotenuse ──────────────────────────────────────────────
            _sectionLabel(context.tr(
              pl: 'ZMIERZONY SKOS (PRZECIWPROSTOKĄTNA c)',
              en: 'MEASURED DIAGONAL (HYPOTENUSE c)',
            )),
            const SizedBox(height: 12),
            _field(_hypCtrl,
              label: context.tr(pl: 'Wymiar po skosie c', en: 'Diagonal measurement c'),
              suffix: 'mm'),
            const SizedBox(height: 24),

            // ── Correction ──────────────────────────────────────────────
            _sectionLabel(context.tr(pl: 'KOREKCJA POMIARU', en: 'MEASUREMENT CORRECTION')),
            const SizedBox(height: 8),
            _subLabel(context.tr(pl: 'Strona lewa', en: 'Left side')),
            const SizedBox(height: 6),
            _field(_odLeftCtrl,
              label: context.tr(pl: 'OD rury – strona lewa', en: 'Pipe OD – left side'),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _refSelector(
              selected: _leftRef,
              onChanged: (v) { setState(() => _leftRef = v); _recalc(); },
            ),
            const SizedBox(height: 16),
            _subLabel(context.tr(pl: 'Strona prawa', en: 'Right side')),
            const SizedBox(height: 6),
            _field(_odRightCtrl,
              label: context.tr(pl: 'OD rury – strona prawa', en: 'Pipe OD – right side'),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _refSelector(
              selected: _rightRef,
              onChanged: (v) { setState(() => _rightRef = v); _recalc(); },
            ),
            const SizedBox(height: 24),

            // ── Mode selector ───────────────────────────────────────────
            _sectionLabel(context.tr(pl: 'ZNANY PARAMETR', en: 'KNOWN PARAMETER')),
            const SizedBox(height: 8),
            _modeSelector(cs),
            const SizedBox(height: 12),
            _modeInputField(),
            const SizedBox(height: 24),

            // ── Results ─────────────────────────────────────────────────
            _sectionLabel(context.tr(pl: 'WYNIKI', en: 'RESULTS')),
            const SizedBox(height: 12),

            // C-C corrected
            _infoTile(
              icon: Icons.straighten,
              label: context.tr(pl: 'Skos C-C po korekcji', en: 'Corrected diagonal C-C'),
              value: _ccc != null ? '${_ccc!.toStringAsFixed(1)} mm' : '—',
              cs: cs,
              warm: false,
            ),
            const SizedBox(height: 10),

            // Horizontal side a — big, warm
            _bigTile(
              label: context.tr(pl: 'Bok poziomy  a', en: 'Horizontal side  a'),
              value: _a,
              cs: cs,
            ),
            const SizedBox(height: 10),

            // Vertical side b — big, warm
            _bigTile(
              label: context.tr(pl: 'Bok pionowy  b', en: 'Vertical side  b'),
              value: _b,
              cs: cs,
            ),
            const SizedBox(height: 10),

            // Angles
            Row(children: [
              Expanded(child: _infoTile(
                icon: Icons.rotate_right,
                label: 'α',
                value: _alpha != null ? '${_alpha!.toStringAsFixed(2)}°' : '—',
                cs: cs,
                warm: false,
              )),
              const SizedBox(width: 10),
              Expanded(child: _infoTile(
                icon: Icons.rotate_left,
                label: 'β',
                value: _beta != null ? '${_beta!.toStringAsFixed(2)}°' : '—',
                cs: cs,
                warm: false,
              )),
            ]),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                    style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.bold, fontSize: 13))),
                ]),
              ),
            ],

            const SizedBox(height: 20),

            // ASCII diagram
            _asciiDiagram(cs),

            const SizedBox(height: 16),
            Text(
              context.tr(
                pl: 'Korekcja: Zewnętrzna = −OD/2 · Oś = 0 · Wewnętrzna = +OD/2\n'
                    'c_cc = c_zmierzone + korekcja_L + korekcja_P',
                en: 'Correction: Outer = −OD/2 · Centre = 0 · Inner = +OD/2\n'
                    'c_cc = c_measured + correction_L + correction_R',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────────

  Widget _modeSelector(ColorScheme cs) {
    final modes = [
      (_Mode.angle,      context.tr(pl: 'Kąt α', en: 'Angle α')),
      (_Mode.horizontal, context.tr(pl: 'Bok poziomy a', en: 'Horiz. side a')),
      (_Mode.vertical,   context.tr(pl: 'Bok pionowy b', en: 'Vert. side b')),
    ];
    return Row(
      children: modes.map((m) {
        final sel = _mode == m.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () {
                setState(() => _mode = m.$1);
                _inputCtrl.clear();
                _recalc();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                ),
                child: Text(m.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: sel ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _modeInputField() {
    switch (_mode) {
      case _Mode.angle:
        return _field(_inputCtrl,
          label: context.tr(pl: 'Kąt α (stopnie)', en: 'Angle α (degrees)'),
          suffix: '°');
      case _Mode.horizontal:
        return _field(_inputCtrl,
          label: context.tr(pl: 'Bok poziomy a', en: 'Horizontal side a'),
          suffix: 'mm');
      case _Mode.vertical:
        return _field(_inputCtrl,
          label: context.tr(pl: 'Bok pionowy b', en: 'Vertical side b'),
          suffix: 'mm');
    }
  }

  Widget _bigTile({
    required String label,
    required double? value,
    required ColorScheme cs,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: cs.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value != null ? '${value.toStringAsFixed(1)} mm' : '—',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: cs.onTertiaryContainer,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme cs,
    required bool warm,
  }) {
    final bg   = warm ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg   = warm ? cs.onPrimaryContainer : cs.onSurface;
    final fgSub = warm ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(icon, size: 20, color: fgSub),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: fgSub)),
            Text(value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: fg)),
          ],
        )),
      ]),
    );
  }

  Widget _asciiDiagram(ColorScheme cs) {
    final aStr     = _a     != null ? '${_a!.toStringAsFixed(1)} mm'     : 'a';
    final bStr     = _b     != null ? '${_b!.toStringAsFixed(1)} mm'     : 'b';
    final cStr     = _ccc   != null ? '${_ccc!.toStringAsFixed(1)} mm'   : 'c';
    final alphaStr = _alpha != null ? '${_alpha!.toStringAsFixed(1)}°'   : 'α';
    final betaStr  = _beta  != null ? '${_beta!.toStringAsFixed(1)}°'    : 'β';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(pl: 'Schemat trójkąta', en: 'Triangle diagram'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            '|\\  \n'
            '|  \\  ← $cStr (skos)\n'
            '|    \\\n'
            '|  $betaStr \\\n'
            '|      \\\n'
            '+--$alphaStr--+\n'
            '  ↑ $aStr',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.7,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '← (bok pionowy b) = $bStr',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _refSelector({
    required _RefType selected,
    required ValueChanged<_RefType> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final options = [
      (_RefType.outer,  context.tr(pl: 'Zewnętrzna', en: 'Outer'),  '−OD/2'),
      (_RefType.center, context.tr(pl: 'Oś', en: 'Centre'),         '0'),
      (_RefType.inner,  context.tr(pl: 'Wewnętrzna', en: 'Inner'),  '+OD/2'),
    ];
    return Row(
      children: options.map((opt) {
        final isSel = selected == opt.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onChanged(opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSel ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSel ? cs.primary : cs.outlineVariant,
                  ),
                ),
                child: Column(children: [
                  Text(opt.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isSel ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  Text(opt.$3,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
  );

  Widget _subLabel(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
  );

  Widget _field(TextEditingController ctrl,
      {required String label, String? suffix}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
