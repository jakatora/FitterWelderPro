import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

class PipeRouteCalculatorScreen extends StatefulWidget {
  const PipeRouteCalculatorScreen({super.key});

  @override
  State<PipeRouteCalculatorScreen> createState() => _PipeRouteCalculatorScreenState();
}

class _PipeRouteCalculatorScreenState extends State<PipeRouteCalculatorScreen> {
  final _h1Controller = TextEditingController();
  final _h2Controller = TextEditingController();
  final _xController  = TextEditingController();
  final _yController  = TextEditingController();
  final _rController  = TextEditingController(text: '0');

  final _seg1Controller  = TextEditingController();
  final _seg2Controller  = TextEditingController();
  final _seg3Controller  = TextEditingController();
  final _totalController = TextEditingController();

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Route: horizontal X → vertical |H1−H2| → horizontal Y
  // 3 × 90° elbows. Pipe segments between elbows (face-to-face, not C-C):
  //   Segment1 = X − R          (from wall/reference to face of elbow 1)
  //   Segment2 = |H1−H2| − 2R   (between face of elbow 1 and face of elbow 2)
  //   Segment3 = Y − R          (from face of elbow 2 to wall/reference)
  // where R = elbow takeout (centre-to-face). For LR 90° elbow: takeout = R_CLR.
  void _calculate() {
    final h1 = _parse(_h1Controller.text);
    final h2 = _parse(_h2Controller.text);
    final x  = _parse(_xController.text);
    final y  = _parse(_yController.text);
    final r  = _parse(_rController.text);

    if (x <= 0 || y <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Wpisz X i Y > 0', en: 'Enter X and Y > 0')),
      ));
      return;
    }
    if (r < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'R (takeout) nie może być ujemne',
          en: 'R (takeout) cannot be negative',
        )),
      ));
      return;
    }
    if (r > x || r > y || 2 * r > (h1 - h2).abs()) {
      final messenger = ScaffoldMessenger.of(context);
      final prevR = _rController.text;
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'R za duże dla podanych wymiarów (odcinek wyszedłby ujemny)',
          en: 'R too large for given dimensions (segment would be negative)',
        )),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: context.tr(pl: 'Wyzeruj R', en: 'Reset R'),
          onPressed: () {
            _rController.text = '0';
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(
              content: Text(context.tr(pl: 'R = 0. Policz ponownie.', en: 'R = 0. Recalculate.')),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: context.tr(pl: 'Cofnij', en: 'Undo'),
                onPressed: () => _rController.text = prevR,
              ),
            ));
          },
        ),
      ));
      return;
    }

    final seg1  = x - r;
    final seg2  = (h1 - h2).abs() - 2 * r;
    final seg3  = y - r;
    final total = math.max(0, seg1) + math.max(0, seg2) + math.max(0, seg3);

    _seg1Controller.text  = seg1.toStringAsFixed(1);
    _seg2Controller.text  = seg2.toStringAsFixed(1);
    _seg3Controller.text  = seg3.toStringAsFixed(1);
    _totalController.text = total.toStringAsFixed(1);

    setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _h1Controller, _h2Controller, _xController, _yController, _rController,
      _seg1Controller, _seg2Controller, _seg3Controller, _totalController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Trasa rur – 3 kolanka 90°', en: 'Pipe route – 3 × 90° elbows')),
        actions: [HelpButton(help: kHelpPipeRoute)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context.tr(pl: 'DANE WEJŚCIOWE', en: 'INPUT DATA')),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: _field(_h1Controller,
                label: context.tr(pl: 'H1 – wys. startu', en: 'H1 – start height'), suffix: 'mm')),
              const SizedBox(width: 12),
              Expanded(child: _field(_h2Controller,
                label: context.tr(pl: 'H2 – wys. końca', en: 'H2 – end height'), suffix: 'mm')),
            ]),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: _field(_xController,
                label: context.tr(pl: 'X – bieg poziomy 1', en: 'X – horizontal run 1'), suffix: 'mm')),
              const SizedBox(width: 12),
              Expanded(child: _field(_yController,
                label: context.tr(pl: 'Y – bieg poziomy 2', en: 'Y – horizontal run 2'), suffix: 'mm')),
            ]),
            const SizedBox(height: 12),

            _field(_rController,
              label: context.tr(
                pl: 'R – takeout kolanka 90° (C-F)',
                en: 'R – elbow 90° takeout (C-F)',
              ),
              suffix: 'mm',
              helper: context.tr(
                pl: 'Dla kolanka LR: takeout = promień CLR. Wpisz 0 jeśli liczysz C-C.',
                en: 'For LR elbow: takeout = CLR radius. Enter 0 if calculating C-C.',
              ),
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
            _sectionLabel(context.tr(pl: 'WYNIKI – długości odcinków rur', en: 'RESULTS – pipe segment lengths')),
            const SizedBox(height: 12),

            _result(_seg1Controller,
              label: context.tr(pl: 'Odcinek 1 (poziomy, X−R)', en: 'Segment 1 (horizontal, X−R)')),
            const SizedBox(height: 12),
            _result(_seg2Controller,
              label: context.tr(pl: 'Odcinek 2 (pionowy, |H1−H2|−2R)', en: 'Segment 2 (vertical, |H1−H2|−2R)')),
            const SizedBox(height: 12),
            _result(_seg3Controller,
              label: context.tr(pl: 'Odcinek 3 (poziomy, Y−R)', en: 'Segment 3 (horizontal, Y−R)')),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.straighten, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      context.tr(pl: 'SUMA (bez kolanek)', en: 'TOTAL (excl. elbows)'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _totalController.text.isEmpty ? '—' : '${_totalController.text} mm',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 16),
            Text(
              context.tr(
                pl: 'Wzór: Odcinek = wymiar C-C − takeout. Takeout dla LR 90° = promień CLR (np. 1,5×DN).',
                en: 'Formula: Segment = C-C dimension − takeout. Takeout for LR 90° = CLR radius (e.g. 1.5×DN).',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // ASME/ISO iso convention: each joint between segments is a weld;
            // mark FW (field weld, open flag) vs SW (shop weld, filled dot) so the
            // welder knows what to weld on site. 3 elbows = 4 joints in this route.
            Text(
              context.tr(
                pl: 'Spoiny: 4 złącza (zw. spoin obwodowych). Oznacz na izometryku FW – spoina montażowa (flaga), SW – spoina warsztatowa (kropka).',
                en: 'Welds: 4 joints (circumferential butts). Mark on iso as FW – field weld (open flag), SW – shop weld (filled dot).',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
    ),
  );

  Widget _field(TextEditingController ctrl,
      {required String label, String? suffix, String? helper}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _result(TextEditingController ctrl, {required String label}) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'mm',
        border: const OutlineInputBorder(),
        filled: true,
        suffixIcon: IconButton(
          icon: const Icon(Icons.content_copy, size: 18),
          tooltip: context.tr(pl: 'Kopiuj', en: 'Copy'),
          onPressed: ctrl.text.trim().isEmpty
              ? null
              : () => copyToClipboard(context, ctrl.text, label: label),
        ),
      ),
    );
  }
}
