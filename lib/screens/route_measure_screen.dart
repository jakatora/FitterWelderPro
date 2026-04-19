import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

enum _RefType { outer, center, inner }

class RouteMeasureScreen extends StatefulWidget {
  const RouteMeasureScreen({super.key});

  @override
  State<RouteMeasureScreen> createState() => _RouteMeasureScreenState();
}

class _RouteMeasureScreenState extends State<RouteMeasureScreen> {
  final _measController = TextEditingController();
  final _odLeftController  = TextEditingController();
  final _odRightController = TextEditingController();

  _RefType _leftRef  = _RefType.outer;
  _RefType _rightRef = _RefType.outer;

  final _ccController         = TextEditingController();
  final _correctionController = TextEditingController();

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Centre-to-centre calculation from a field measurement.
  //
  // Correction per side:
  //   outer  → −OD/2  (measured from outside surface; centre is OD/2 inward)
  //   center →  0     (measured from centre; no correction needed)
  //   inner  → +OD/2  (measured from inside surface; centre is OD/2 outward)
  //
  // C-C = measurement + correction_left + correction_right
  //
  // Verification (measurement=850, OD=60.3, left=outer, right=outer):
  //   correction = −60.3/2 + (−60.3/2) = −30.15 − 30.15 = −60.3mm
  //   C-C = 850 − 60.3 = 789.7mm  ✓
  void _calculate() {
    final meas    = _parse(_measController.text);
    final odLeft  = _parse(_odLeftController.text);
    final odRight = _parse(_odRightController.text);

    if (meas <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Wpisz wymiar pomiaru > 0', en: 'Enter measurement > 0')),
      ));
      return;
    }

    final corrLeft  = _correctionFor(_leftRef, odLeft);
    final corrRight = _correctionFor(_rightRef, odRight);
    final totalCorr = corrLeft + corrRight;
    final cc        = meas + totalCorr;

    _correctionController.text = totalCorr.toStringAsFixed(2);
    _ccController.text         = cc.toStringAsFixed(1);

    setState(() {});
  }

  double _correctionFor(_RefType ref, double od) {
    switch (ref) {
      case _RefType.outer:  return -od / 2.0;
      case _RefType.center: return 0.0;
      case _RefType.inner:  return  od / 2.0;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _measController, _odLeftController, _odRightController,
      _ccController, _correctionController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Pomiar trasy – C-C', en: 'Route measurement – C-C')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context.tr(pl: 'POMIAR TAŚMĄ', en: 'TAPE MEASUREMENT')),
            const SizedBox(height: 12),
            _field(_measController,
              label: context.tr(pl: 'Zmierzony wymiar', en: 'Measured dimension'),
              suffix: 'mm'),
            const SizedBox(height: 24),

            _sectionLabel(context.tr(pl: 'STRONA LEWA', en: 'LEFT SIDE')),
            const SizedBox(height: 8),
            _field(_odLeftController,
              label: context.tr(pl: 'OD rury/kształtki – strona lewa', en: 'Pipe/fitting OD – left side'),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _refSelector(
              selected: _leftRef,
              onChanged: (v) => setState(() => _leftRef = v),
            ),
            const SizedBox(height: 20),

            _sectionLabel(context.tr(pl: 'STRONA PRAWA', en: 'RIGHT SIDE')),
            const SizedBox(height: 8),
            _field(_odRightController,
              label: context.tr(pl: 'OD rury/kształtki – strona prawa', en: 'Pipe/fitting OD – right side'),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _refSelector(
              selected: _rightRef,
              onChanged: (v) => setState(() => _rightRef = v),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: Text(context.tr(pl: 'OBLICZ', en: 'CALCULATE')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 24),

            _sectionLabel(context.tr(pl: 'WYNIKI', en: 'RESULTS')),
            const SizedBox(height: 12),

            _result(_correctionController,
              label: context.tr(pl: 'Korekcja (suma obu stron)', en: 'Correction (both sides total)'),
              suffix: 'mm'),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.straighten, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(pl: 'C-C (oś do osi)', en: 'C-C (centre to centre)'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _ccController.text.isEmpty ? '—' : '${_ccController.text} mm',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                )),
              ]),
            ),

            const SizedBox(height: 16),
            Text(
              context.tr(
                pl: 'Korekcja na stronę:\n'
                    '• Zewnętrzna (outer): −OD/2\n'
                    '• Środkowa (center): 0\n'
                    '• Wewnętrzna (inner): +OD/2\n'
                    'C-C = pomiar + korekcja_L + korekcja_P',
                en: 'Correction per side:\n'
                    '• Outer: −OD/2\n'
                    '• Centre: 0\n'
                    '• Inner: +OD/2\n'
                    'C-C = measurement + correction_L + correction_R',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _refSelector({
    required _RefType selected,
    required ValueChanged<_RefType> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final options = [
      (_RefType.outer,  context.tr(pl: 'Zewnętrzna', en: 'Outer'),  context.tr(pl: '−OD/2', en: '−OD/2')),
      (_RefType.center, context.tr(pl: 'Środkowa', en: 'Centre'),   context.tr(pl: '0', en: '0')),
      (_RefType.inner,  context.tr(pl: 'Wewnętrzna', en: 'Inner'),  context.tr(pl: '+OD/2', en: '+OD/2')),
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

  Widget _result(TextEditingController ctrl,
      {required String label, String suffix = 'mm'}) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        filled: true,
      ),
    );
  }
}
