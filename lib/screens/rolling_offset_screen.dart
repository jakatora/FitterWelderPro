import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

class RollingOffsetScreen extends StatefulWidget {
  const RollingOffsetScreen({super.key});

  @override
  State<RollingOffsetScreen> createState() => _RollingOffsetScreenState();
}

class _RollingOffsetScreenState extends State<RollingOffsetScreen> {
  final _riseController   = TextEditingController();
  final _spreadController = TextEditingController();

  final _trueOffsetController = TextEditingController();
  final _travelController     = TextEditingController();
  final _runController        = TextEditingController();
  final _multiplierController = TextEditingController();

  String _selectedAngle = '45';
  final _customAngleController = TextEditingController();

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Rolling offset formulas:
  //   True Offset = √(Rise² + Spread²)
  //   Travel      = True Offset / sin(θ)   [θ = elbow angle]
  //   Run         = True Offset / tan(θ)   = √(Travel² − True Offset²)
  //   Multiplier  = 1 / sin(θ)
  //
  // Verification (Rise=300, Spread=400, θ=45°):
  //   True Offset = √(90000+160000) = √250000 = 500mm
  //   Multiplier  = 1/sin(45°) = √2 ≈ 1.4142
  //   Travel      = 500 × 1.4142 = 707.1mm
  //   Run         = 500/tan(45°) = 500mm
  void _calculate() {
    // Wipe stale result fields BEFORE the validation early-returns. Without
    // this, a fitter who computed pipe A, then mistypes Rise on pipe B and
    // hits CALCULATE still sees the stale 707.1 in the Travel field — copies
    // it to the saw, cuts pipe to the wrong length.
    _trueOffsetController.clear();
    _multiplierController.clear();
    _travelController.clear();
    _runController.clear();

    final rise   = _parse(_riseController.text);
    final spread = _parse(_spreadController.text);
    final angleDeg = _selectedAngle == 'custom'
        ? _parse(_customAngleController.text)
        : _parse(_selectedAngle);

    if (rise <= 0 || spread <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(context.tr(pl: 'Wpisz Rise i Spread > 0', en: 'Enter Rise and Spread > 0')),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: context.tr(pl: 'OK', en: 'OK'),
          onPressed: () {},
        ),
      ));
      return;
    }
    if (angleDeg <= 0 || angleDeg >= 90) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Kąt musi być między 1° a 89°', en: 'Angle must be between 1° and 89°')),
      ));
      return;
    }

    final angleRad  = angleDeg * math.pi / 180.0;
    final trueOffset = math.sqrt(rise * rise + spread * spread);
    final multiplier = 1.0 / math.sin(angleRad);
    final travel     = trueOffset * multiplier;
    final run        = trueOffset / math.tan(angleRad);

    _trueOffsetController.text = trueOffset.toStringAsFixed(1);
    _multiplierController.text = multiplier.toStringAsFixed(4);
    _travelController.text     = travel.toStringAsFixed(1);
    _runController.text        = run.toStringAsFixed(1);

    setState(() {});
  }

  // Dirty when fitter has typed Rise/Spread/custom-angle but not yet copied results.
  // Accidental swipe-back in gloves would silently wipe the input.
  bool get _isDirty =>
      _riseController.text.trim().isNotEmpty ||
      _spreadController.text.trim().isNotEmpty ||
      _customAngleController.text.trim().isNotEmpty;

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Porzucić dane?', en: 'Discard inputs?')),
        content: Text(context.tr(
          pl: 'Wpisane Rise, Spread i kąt zostaną utracone.',
          en: 'Entered Rise, Spread and angle will be lost.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(pl: 'Wróć do edycji', en: 'Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr(pl: 'Porzuć', en: 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _riseController, _spreadController, _customAngleController,
      _trueOffsetController, _travelController, _runController, _multiplierController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (discard && mounted) nav.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Rolling Offset', en: 'Rolling Offset')),
        actions: [HelpButton(help: kHelpRollingOffset)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context.tr(pl: 'KĄT KOLAN', en: 'ELBOW ANGLE')),
            const SizedBox(height: 8),
            Row(children: [
              _angleBtn(cs, '45', '45°'),
              const SizedBox(width: 8),
              _angleBtn(cs, '60', '60°'),
              const SizedBox(width: 8),
              _angleBtn(cs, '30', '30°'),
              const SizedBox(width: 8),
              _angleBtn(cs, 'custom', context.tr(pl: 'Inny', en: 'Custom')),
            ]),
            if (_selectedAngle == 'custom') ...[
              const SizedBox(height: 12),
              _field(_customAngleController,
                label: context.tr(pl: 'Kąt kolana (°)', en: 'Elbow angle (°)'), suffix: '°'),
            ],
            const SizedBox(height: 20),

            _sectionLabel(context.tr(pl: 'DANE WEJŚCIOWE', en: 'INPUT DATA')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_riseController,
                label: context.tr(pl: 'Rise (odchylenie pionowe)', en: 'Rise (vertical offset)'),
                suffix: 'mm')),
              const SizedBox(width: 12),
              Expanded(child: _field(_spreadController,
                label: context.tr(pl: 'Spread (odchylenie boczne)', en: 'Spread (lateral offset)'),
                suffix: 'mm',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _calculate())),
            ]),
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
            _result(_trueOffsetController,
              label: context.tr(pl: 'True Offset = √(Rise²+Spread²)', en: 'True Offset = √(Rise²+Spread²)')),
            const SizedBox(height: 12),
            _result(_multiplierController,
              label: context.tr(pl: 'Multiplier = 1/sin(θ)', en: 'Multiplier = 1/sin(θ)'),
              suffix: '×'),
            const SizedBox(height: 12),
            _result(_travelController,
              label: context.tr(
                pl: 'Travel = True Offset × Multiplier',
                en: 'Travel = True Offset × Multiplier',
              )),
            const SizedBox(height: 12),
            _result(_runController,
              label: context.tr(
                pl: 'Run = True Offset / tan(θ)',
                en: 'Run = True Offset / tan(θ)',
              )),
            const SizedBox(height: 16),

            Text(
              context.tr(
                pl: 'Travel to długość każdego z 2 kolanek (oś do osi). Run to poziomy bieg między punktami odejścia.',
                en: 'Travel is the centre-to-centre length of each of the 2 offset elbows. Run is the horizontal distance between take-off points.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
  );

  Widget _angleBtn(ColorScheme cs, String value, String label) {
    final selected = _selectedAngle == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedAngle = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: selected ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // Positive decimal only: digits + single '.' or ',' separator. Blocks '-', 'e', spaces.
  static final _positiveDecimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*'));

  Widget _field(TextEditingController ctrl,
      {required String label, String? suffix,
      TextInputAction textInputAction = TextInputAction.next,
      ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
      inputFormatters: [_positiveDecimalFormatter],
      textInputAction: textInputAction,
      onSubmitted: onSubmitted ??
          (_) => FocusScope.of(context).nextFocus(),
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
