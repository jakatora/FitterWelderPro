import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../data/elbow_takeouts.dart';
import '../i18n/app_language.dart';
import '../services/takeout_catalog.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/calculation_guide.dart';
import '../widgets/number_field.dart';

/// Roll of the offset plane (= how far the elbow is turned) measured from
/// the vertical, in degrees: atan(Spread / Rise). Rise is the vertical and
/// Spread the lateral offset as entered on this screen; the roll from the
/// horizontal is 90° minus this value.
double rollFromVerticalDeg(double rise, double spread) =>
    math.atan2(spread, rise) * 180.0 / math.pi;

/// Pipe to cut between the two offset elbows:
/// Travel − 2 × take-out − 2 × weld gap.
double rollingCutLengthMm({
  required double travelMm,
  required double takeoutMm,
  double gapMm = 0,
}) =>
    travelMm - 2.0 * takeoutMm - 2.0 * gapMm;

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
  final _rollVController      = TextEditingController();
  final _rollHController      = TextEditingController();

  // Optional cut length: B16.9 LR elbow size + weld gap.
  int? _dn;
  final _gapController        = TextEditingController();
  final _takeoutController    = TextEditingController();
  final _cutController        = TextEditingController();
  String? _takeoutSource;
  bool _cutNegative = false;

  String _selectedAngle = '45';
  final _customAngleController = TextEditingController();

  // P1-12: yellow banner when multiplier > 10 (extreme shallow angle → tiny
  // sin(θ) blows the Travel/Multiplier up; fitter should double-check kąt).
  bool _showMultiplierWarning = false;
  (double, double, double)? _lastCalculation;

  void _clearComputed() {
    _trueOffsetController.clear();
    _multiplierController.clear();
    _travelController.clear();
    _runController.clear();
    _rollVController.clear();
    _rollHController.clear();
    _takeoutController.clear();
    _cutController.clear();
    _takeoutSource = null;
    _cutNegative = false;
    _showMultiplierWarning = false;
    _lastCalculation = null;
  }

  Widget _guide() {
    final (rise, spread, angle) = _lastCalculation ?? (300.0, 400.0, 45.0);
    final offset = _lastCalculation == null ? '500.0' : _trueOffsetController.text;
    final travel = _lastCalculation == null ? '707.1' : _travelController.text;
    return CalculationGuide(
      hasResult: _lastCalculation != null,
      inputs: context.tr(
        pl: 'Rise to przesunięcie pionowe osi rur. Spread to przesunięcie boczne osi, mierzone prostopadle do Rise. Wpisz oba wymiary w mm i wybierz kąt kolan.',
        en: 'Rise is the vertical offset of the pipe centrelines. Spread is the lateral offset, measured perpendicular to Rise. Enter both in mm and select the elbow angle.'),
      steps: [
        context.tr(pl: 'Rzeczywiste odsunięcie osi:\n√(${guideNumber(rise)}² + ${guideNumber(spread)}²) = $offset mm',
          en: 'True offset of the centrelines:\n√(${guideNumber(rise)}² + ${guideNumber(spread)}²) = $offset mm'),
        context.tr(pl: 'Odległość między punktami przecięcia osi kolan:\n$offset / sin(${guideNumber(angle)}°) = $travel mm',
          en: 'Distance between the elbow centreline intersection points:\n$offset / sin(${guideNumber(angle)}°) = $travel mm'),
      ],
      caution: context.tr(
        pl: 'Travel nie jest długością cięcia ani długością kolana. Przed cięciem uwzględnij zabudowy obu kształtek, sposób wymiarowania i szczeliny z dokumentacji projektu. Obliczenia używają pełnej precyzji; prezentowane liczby są zaokrąglone.',
        en: 'Travel is not a cut length or an elbow length. Before cutting, account for both fitting take-outs, dimension references and gaps from the project documentation. Calculations use full precision; displayed numbers are rounded.'),
    );
  }

  double _parse(String v) => parseDecimal(v) ?? 0;

  // P1-04: Wyczyść — reset all controllers + selected angle back to 45°
  // default. Multi-job shift = 3-4 calcs back-to-back; manual field clearing
  // in gloves is painful and inconsistent.
  void _resetAll() {
    setState(() {
      _riseController.clear();
      _spreadController.clear();
      _customAngleController.clear();
      _clearComputed();
      _gapController.clear();
      _dn = null;
      _selectedAngle = '45';
    });
  }

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
    //
    // P0r-05: the clears alone are silently invisible on the validation
    // early-return paths because no setState fires — the copy IconButton
    // stays "enabled" against now-empty controllers. setState here rebuilds
    // the enable-state and also exposes the cleared form factor when the
    // user fixes the validation error.
    setState(_clearComputed);

    final rise   = _parse(_riseController.text);
    final spread = _parse(_spreadController.text);
    final angleDeg = _selectedAngle == 'custom'
        ? _parse(_customAngleController.text)
        : _parse(_selectedAngle);

    if (!rise.isFinite || !spread.isFinite || rise <= 0 || spread <= 0) {
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
    // P1-12: Reject angle ≤ 5° or ≥ 89°; allow exactly 90° as edge case
    // (Run = 0, Multiplier = 1). Below 5° sin(θ) collapses → multiplier
    // explodes; above 89° (except 90°) tan(θ) blows up.
    if (!angleDeg.isFinite || angleDeg <= 5 || (angleDeg >= 89 && angleDeg != 90)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Kąt musi być > 5° i < 89° (lub dokładnie 90°)',
          en: 'Angle must be > 5° and < 89° (or exactly 90°)',
        )),
      ));
      return;
    }

    final angleRad  = angleDeg * math.pi / 180.0;
    final trueOffset = math.sqrt(rise * rise + spread * spread);
    final multiplier = 1.0 / math.sin(angleRad);
    final travel     = trueOffset * multiplier;
    // 90° edge case: tan(π/2) is mathematically infinite, but math.tan
    // returns a huge finite float. Pin Run to 0.0 explicitly so the saw
    // gets a clean reading.
    final run        = angleDeg == 90 ? 0.0 : trueOffset / math.tan(angleRad);

    if (![trueOffset, multiplier, travel, run].every((v) => v.isFinite)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Wynik poza zakresem. Sprawdź wartości i jednostki.',
          en: 'Result out of range. Check the values and units.',
        )),
      ));
      return;
    }

    _trueOffsetController.text = trueOffset.toStringAsFixed(1);
    _multiplierController.text = multiplier.toStringAsFixed(4);
    _travelController.text     = travel.toStringAsFixed(1);
    _runController.text        = run.toStringAsFixed(1);
    final rollV = rollFromVerticalDeg(rise, spread);
    _rollVController.text      = rollV.toStringAsFixed(1);
    _rollHController.text      = (90.0 - rollV).toStringAsFixed(1);

    // Optional: cut length from the ASME B16.9 LR elbow take-out.
    final dn = _dn;
    if (dn != null) {
      final t = b169ElbowTakeout(
          dn: dn, type: ElbowRadiusType.long15D, angleDeg: angleDeg);
      final gap = _parse(_gapController.text);
      if (t != null && gap.isFinite && gap >= 0) {
        final cut = rollingCutLengthMm(
            travelMm: travel, takeoutMm: t.mm, gapMm: gap);
        _takeoutController.text = t.mm.toStringAsFixed(1);
        _cutController.text     = cut.toStringAsFixed(1);
        _cutNegative = cut <= 0;
        final half = (angleDeg / 2).toStringAsFixed(angleDeg % 2 == 0 ? 0 : 1);
        _takeoutSource = switch (t.basis) {
          TakeoutBasis.tableA90 => context.tr(
              pl: 'ASME B16.9 tab. 6.1-1: kolano 90° LR DN$dn — A = ${t.a90Mm} mm',
              en: 'ASME B16.9 Table 6.1-1: 90° LR elbow DN$dn — A = ${t.a90Mm} mm'),
          TakeoutBasis.tableB45 => context.tr(
              pl: 'ASME B16.9 tab. 6.1-1: kolano 45° LR DN$dn — B = ${t.mm.toStringAsFixed(0)} mm',
              en: 'ASME B16.9 Table 6.1-1: 45° LR elbow DN$dn — B = ${t.mm.toStringAsFixed(0)} mm'),
          TakeoutBasis.segment => context.tr(
              pl: 'ASME B16.9 §6.2.4 (segment kolana 90° LR DN$dn): A × tan(θ/2) = ${t.a90Mm} × tan($half°)',
              en: 'ASME B16.9 §6.2.4 (segment of a 90° LR elbow DN$dn): A × tan(θ/2) = ${t.a90Mm} × tan($half°)'),
        };
      }
    }

    setState(() {
      _showMultiplierWarning = multiplier > 10;
      _lastCalculation = (rise, spread, angleDeg);
    });
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
      _rollVController, _rollHController, _gapController, _takeoutController,
      _cutController,
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
        actions: [
          // P1-04: explicit reset of every controller + chip state. 48 dp
          // tap target via default IconButton constraints.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
            onPressed: _resetAll,
          ),
          HelpButton(help: kHelpRollingOffset),
        ],
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
            const SizedBox(height: 16),

            _sectionLabel(context.tr(
                pl: 'DŁUGOŚĆ CIĘCIA (OPCJONALNIE)',
                en: 'CUT LENGTH (OPTIONAL)')),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _dn,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Kolana ASME B16.9 LR — DN',
                    en: 'ASME B16.9 LR elbows — DN'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<int>(
                  value: null,
                  child: Text(
                    context.tr(pl: '— bez kolan (tylko Travel)', en: '— no elbows (Travel only)'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final e in kElbowTakeouts)
                  DropdownMenuItem<int>(
                    value: e.dn,
                    child: Text('DN${e.dn} (${e.nps}")',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                _clearComputed();
                _dn = v;
              }),
            ),
            const SizedBox(height: 12),
            _field(_gapController,
              label: context.tr(pl: 'Szczelina spoiny (mm)', en: 'Weld root gap (mm)'),
              suffix: 'mm',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _calculate()),
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
            // P1-12: yellow banner when multiplier > 10 → very shallow kąt,
            // tiny sin(θ) blows Travel up; fitter should re-check angle.
            if (_showMultiplierWarning) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr(
                          pl: 'Multiplier > 10 — sprawdź kąt; bardzo płaskie kolano daje ogromny Travel.',
                          en: 'Multiplier > 10 — check angle; a very shallow elbow yields a huge Travel.',
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
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
            const SizedBox(height: 12),
            _result(_rollVController,
              label: context.tr(
                pl: 'Obrót kolana od pionu = atan(Spread / Rise)',
                en: 'Elbow roll from vertical = atan(Spread / Rise)',
              ),
              suffix: '°'),
            const SizedBox(height: 12),
            _result(_rollHController,
              label: context.tr(
                pl: 'Obrót od poziomu = atan(Rise / Spread)',
                en: 'Roll from horizontal = atan(Rise / Spread)',
              ),
              suffix: '°'),
            if (_dn != null) ...[
              const SizedBox(height: 12),
              _result(_takeoutController,
                label: context.tr(pl: 'Take-out kolana T', en: 'Elbow take-out T')),
              if (_takeoutSource != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    _takeoutSource!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              _result(_cutController,
                label: context.tr(
                  pl: 'Długość cięcia = Travel − 2×T − 2×szczelina',
                  en: 'Cut length = Travel − 2×T − 2×gap',
                )),
              if (_cutNegative)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    context.tr(
                      pl: 'Kolana nachodzą na siebie — odsadzka za mała dla tego DN i kąta.',
                      en: 'The elbows overlap — the offset is too small for this DN and angle.',
                    ),
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
            ],
            const SizedBox(height: 16),

            Text(
              context.tr(
                pl: 'Travel to wymiar osiowy między kolanami, nie długość cięcia. Run to rzut wzdłuż kierunku początkowej rury.',
                en: 'Travel is the centreline dimension between elbows, not a cut length. Run is the projection along the original pipe direction.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _guide(),
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
        // P0r-06: tapping a different angle preset post-calc used to leave
        // the 45° Travel=707.1 visible while the chip jumped to 60° — fitter
        // copies 707.1 thinking it's the 60° value. Wipe results on every
        // chip change AND clear the custom-angle field when switching away.
        onTap: () => setState(() {
          if (_selectedAngle != value) {
            _clearComputed();
            if (value != 'custom') {
              _customAngleController.clear();
            }
          }
          _selectedAngle = value;
        }),
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

  Widget _field(TextEditingController ctrl,
      {required String label, String? suffix,
      TextInputAction textInputAction = TextInputAction.next,
      ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => setState(_clearComputed),
      // Positive decimal only: digits and '.' / ','. The shared formatter
      // refuses '-', 'e' and letters outright (the old prefix filter cut a
      // paste like "1e5" down to "1" without a word).
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
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
