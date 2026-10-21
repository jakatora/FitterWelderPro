import 'package:flutter/material.dart';

import '../domain/fitter/pipe_slope.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/calculation_guide.dart';
import '../widgets/number_field.dart';
import '../assistant/core/tool_bridge.dart';
import '../assistant/core/skill.dart' show ModuleActionResult, AssistantText;

class PipeSlopeScreen extends StatefulWidget {
  const PipeSlopeScreen({super.key});

  @override
  State<PipeSlopeScreen> createState() => _PipeSlopeScreenState();
}

class _PipeSlopeScreenState extends State<PipeSlopeScreen>
    with ToolHandleHost<PipeSlopeScreen>
    implements InputToolHandle, ModuleActionHandle {
  @override
  String get toolId => 'pipe_slope';
  @override
  Set<String> get supportedFields =>
      const {'mode', 'length_mm', 'rise_mm', 'slope_pct', 'action'};
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'mode': _mode,
        if (_mode != 'rise_to_length')
          'length_mm': parseDecimal(_lengthController.text),
        if (_mode != 'length_to_rise')
          'rise_mm': parseDecimal(_riseController.text),
        if (_mode != 'slope_from_lr')
          'slope_pct': parseDecimal(_slopeController.text),
      });
  @override
  Future<ModuleActionResult> performAction(String action,
      {String? field}) async {
    if (!mounted) {
      return const ModuleActionResult(false,
          AssistantText('Moduł jest zamknięty.', 'The module is closed.'));
    }
    if (action == 'formula' && field == null) {
      _showFormulaInfo();
      return const ModuleActionResult(
          true,
          AssistantText('Otworzono objaśnienie wzorów spadku rury.',
              'Pipe-slope formula explanation opened.'));
    }
    if (action != 'copy') {
      return const ModuleActionResult(
          false,
          AssistantText('Ta czynność nie jest dostępna w tym module.',
              'This action is unavailable in this module.'));
    }
    final primary = _mode == 'length_to_rise'
        ? 'rise_mm'
        : _mode == 'rise_to_length'
            ? 'length_mm'
            : 'slope_pct';
    final key = field == null || field == 'result' ? primary : field;
    final selected = switch (key) {
      'rise_mm' when primary == key => (
          _riseController,
          'mm',
          const AssistantText('Wznios', 'Rise')
        ),
      'length_mm' when primary == key => (
          _lengthController,
          'mm',
          const AssistantText('Długość w rzucie poziomym', 'Horizontal run')
        ),
      'slope_pct' when primary == key => (
          _slopeController,
          '%',
          const AssistantText('Nachylenie', 'Slope')
        ),
      'angle_deg' => (
          _angleController,
          '°',
          const AssistantText('Kąt nachylenia', 'Slope angle')
        ),
      'mm_per_m' => (
          _mmPerMController,
          'mm/m',
          const AssistantText('Milimetry na metr', 'Millimetres per metre')
        ),
      _ => null,
    };
    if (selected == null) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Wybrana wielkość nie jest wynikiem w bieżącym trybie. Wybierz wynik, kąt nachylenia lub mm na metr.',
              'That quantity is not a result in the current mode. Choose the result, slope angle or mm per metre.'));
    }
    final (controller, unit, label) = selected;
    final text = controller.text.trim();
    if (_lastCalculation == null || text.isEmpty) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Brak aktualnego wyniku do skopiowania. Najpierw oblicz spadek.',
              'There is no current result to copy. Calculate the slope first.'));
    }
    await copyToClipboard(context, text, label: label.of(context.language));
    return ModuleActionResult(
        true,
        AssistantText('Skopiowano: ${label.pl} — $text $unit.',
            'Copied: ${label.en} — $text $unit.'));
  }

  @override
  void initState() {
    super.initState();
    markReady();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted) return fields.keys.toSet();
    if (fields.length == 1 && fields['action'] == 'formula') {
      final r = await performAction('formula');
      return r.completed ? {} : {'action'};
    }
    if (fields.length == 1 && fields['action'] == 'clear') {
      setState(() {
        for (final c in [
          _lengthController,
          _riseController,
          _slopeController,
          _angleController,
          _mmPerMController
        ]) {
          c.clear();
        }
        _lastCalculation = null;
      });
      return {};
    }
    if (fields.containsKey('action')) return fields.keys.toSet();
    final invalidNumbers = fields.entries
        .where((e) =>
            e.key != 'mode' &&
            (e.value is! num ||
                !(e.value as num).isFinite ||
                (e.value as num) <= 0))
        .map((e) => e.key)
        .toSet();
    if (invalidNumbers.isNotEmpty) return invalidNumbers;
    if (fields.keys.any((key) => !supportedFields.contains(key))) {
      return fields.keys.toSet();
    }
    final mode = fields['mode'];
    if (!const ['length_to_rise', 'rise_to_length', 'slope_from_lr']
        .contains(mode)) {
      return {'mode'};
    }
    final a = mode == 'rise_to_length' ? 'rise_mm' : 'length_mm';
    final b = mode == 'slope_from_lr' ? 'rise_mm' : 'slope_pct';
    final first = fields[a];
    final second = fields[b];
    if (first is! num || !first.isFinite || first <= 0) return {a};
    if (second is! num || !second.isFinite || second <= 0) return {b};
    final result = switch (mode) {
      'length_to_rise' => slopeRiseFromLength(
          lengthMm: first.toDouble(), slopePct: second.toDouble()),
      'rise_to_length' => slopeLengthFromRise(
          riseMm: first.toDouble(), slopePct: second.toDouble()),
      _ => slopeFromLengthAndRise(
          lengthMm: first.toDouble(), riseMm: second.toDouble()),
    };
    if (!mounted || result == null) return {a, b};
    for (final (key, expected) in [
      ('length_mm', result.lengthMm),
      ('rise_mm', result.riseMm),
      ('slope_pct', result.slopePct)
    ]) {
      final value = fields[key];
      if (value is num &&
          (value - expected).abs() >
              1e-9 * expected.abs().clamp(1, double.infinity)) {
        return {key};
      }
    }
    setState(() {
      _mode = mode as String;
      _lengthController.text = result.lengthMm.toString();
      _riseController.text = result.riseMm.toString();
      _slopeController.text = result.slopePct.toString();
    });
    _calculate();
    return {};
  }

  // Mode: calculate rise from length+slope, OR length from rise+slope, OR slope from length+rise
  String _mode = 'length_to_rise';

  final _lengthController = TextEditingController();
  final _slopeController = TextEditingController();
  final _riseController = TextEditingController();

  final _angleController = TextEditingController();
  final _mmPerMController = TextEditingController();
  (double, double, double)? _lastCalculation;

  double _parse(String v) => parseDecimal(v) ?? 0;

  // Pipe slope formulas:
  //   Rise = Length × slope% / 100
  //   Angle = atan(Rise / Length) = atan(slope% / 100)  [in degrees]
  //   mm per metre = slope% × 10
  //
  // Verification (Length=6000mm, slope=1%):
  //   Rise = 6000 × 0.01 = 60mm
  //   Angle = atan(0.01) ≈ 0.5729°
  //   mm/m  = 10
  void _clearComputed() {
    if (_mode == 'length_to_rise') _riseController.clear();
    if (_mode == 'rise_to_length') _lengthController.clear();
    if (_mode == 'slope_from_lr') _slopeController.clear();
    _angleController.clear();
    _mmPerMController.clear();
    _lastCalculation = null;
  }

  // Numbers come from lib/domain/fitter/pipe_slope.dart; the screen keeps
  // its own input check only to pick the right message (bad input vs a
  // result out of range).
  void _calculate() {
    setState(_clearComputed);
    final PipeSlopeResult? result;
    if (_mode == 'length_to_rise') {
      final length = _parse(_lengthController.text);
      final slope = _parse(_slopeController.text);
      if (!length.isFinite || !slope.isFinite || length <= 0 || slope <= 0) {
        _showError(context.tr(
            pl: 'Wpisz długość i nachylenie > 0',
            en: 'Enter length and slope > 0'));
        return;
      }
      result = slopeRiseFromLength(lengthMm: length, slopePct: slope);
      if (result == null) {
        _showRangeError();
        return;
      }

      _riseController.text = result.riseMm.toStringAsFixed(1);
    } else if (_mode == 'rise_to_length') {
      final rise = _parse(_riseController.text);
      final slope = _parse(_slopeController.text);
      if (!rise.isFinite || !slope.isFinite || rise <= 0 || slope <= 0) {
        _showError(context.tr(
            pl: 'Wpisz wznios i nachylenie > 0',
            en: 'Enter rise and slope > 0'));
        return;
      }
      result = slopeLengthFromRise(riseMm: rise, slopePct: slope);
      if (result == null) {
        _showRangeError();
        return;
      }

      _lengthController.text = result.lengthMm.toStringAsFixed(1);
    } else {
      // slope from length + rise
      final length = _parse(_lengthController.text);
      final rise = _parse(_riseController.text);
      if (!length.isFinite || !rise.isFinite || length <= 0 || rise <= 0) {
        _showError(context.tr(
            pl: 'Wpisz długość i wznios > 0', en: 'Enter length and rise > 0'));
        return;
      }
      result = slopeFromLengthAndRise(lengthMm: length, riseMm: rise);
      if (result == null) {
        _showRangeError();
        return;
      }

      _slopeController.text = result.slopePct.toStringAsFixed(3);
    }

    _angleController.text = result.angleDeg.toStringAsFixed(3);
    _mmPerMController.text = result.mmPerM.toStringAsFixed(1);
    _lastCalculation = (result.lengthMm, result.slopePct, result.riseMm);

    setState(() {});
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showRangeError() => _showError(context.tr(
      pl: 'Wynik poza zakresem. Sprawdź wartości i jednostki.',
      en: 'Result out of range. Check the values and units.'));

  Widget _guide() {
    final (length, slope, rise) = _lastCalculation ?? (6000.0, 1.0, 60.0);
    final l = guideNumber(length);
    final s = guideNumber(slope);
    final r = guideNumber(rise);
    return CalculationGuide(
      hasResult: _lastCalculation != null,
      inputs: context.tr(
          pl: 'Długość oznacza rzut poziomy odcinka, nie długość po skosie. Wznios to różnica wysokości końców. Wpisuj wymiary w mm; 1 m = 1000 mm.',
          en: 'Length is the horizontal projection, not the sloping pipe length. Rise is the height difference between the ends. Enter dimensions in mm; 1 m = 1000 mm.'),
      steps: [
        if (_mode == 'length_to_rise')
          context.tr(
              pl: 'Wznios = długość × nachylenie / 100\n$l × $s / 100 = ${rise.toStringAsFixed(1)} mm',
              en: 'Rise = length × slope / 100\n$l × $s / 100 = ${rise.toStringAsFixed(1)} mm'),
        if (_mode == 'rise_to_length')
          context.tr(
              pl: 'Długość = wznios / (nachylenie / 100)\n$r / ($s / 100) = ${length.toStringAsFixed(1)} mm',
              en: 'Length = rise / (slope / 100)\n$r / ($s / 100) = ${length.toStringAsFixed(1)} mm'),
        if (_mode == 'slope_from_lr')
          context.tr(
              pl: 'Nachylenie = wznios / długość × 100\n$r / $l × 100 = ${slope.toStringAsFixed(3)}%',
              en: 'Slope = rise / length × 100\n$r / $l × 100 = ${slope.toStringAsFixed(3)}%'),
        context.tr(
            pl: 'Na każdy metr poziomy: $s × 10 = ${(slope * 10).toStringAsFixed(1)} mm różnicy wysokości.',
            en: 'For each horizontal metre: $s × 10 = ${(slope * 10).toStringAsFixed(1)} mm height difference.'),
      ],
      caution: context.tr(
          pl: '1% nie oznacza 1°. Wymagany spadek i kierunek ustala dokumentacja projektu. Przyciski procentów to skróty wpisywania, nie zalecenia projektowe.',
          en: '1% does not mean 1°. The project documentation determines the required slope and direction. Percentage presets are input shortcuts, not design recommendations.'),
    );
  }

  void _showFormulaInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Źródło wzorów', en: 'Formula source')),
        content: SingleChildScrollView(
          child: Text(
            context.tr(
              pl: 'Geometria liniowa (długość w rzucie poziomym):\n'
                  '  Rise = Długość × (% / 100)\n'
                  '  Kąt  = atan(Rise / Długość)\n'
                  '  mm/m = % × 10\n\n'
                  'Przykłady przeliczeń, nie zalecenia projektowe:\n'
                  '  1:100 = 1% = 10 mm/m\n'
                  '  1:200 = 0,5% = 5 mm/m\n'
                  '  1:50 = 2% = 20 mm/m\n\n'
                  'Wymagany spadek dobierz z dokumentacji projektu.',
              en: 'Linear geometry (horizontal length):\n'
                  '  Rise = Length × (% / 100)\n'
                  '  Angle = atan(Rise / Length)\n'
                  '  mm/m  = % × 10\n\n'
                  'Conversion examples, not design recommendations:\n'
                  '  1:100 = 1% = 10 mm/m\n'
                  '  1:200 = 0.5% = 5 mm/m\n'
                  '  1:50 = 2% = 20 mm/m\n\n'
                  'Use the project documentation to select the required slope.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr(pl: 'OK', en: 'OK')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _lengthController,
      _slopeController,
      _riseController,
      _angleController,
      _mmPerMController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Spadek rury', en: 'Pipe slope')),
        actions: [HelpButton(help: kHelpPipeSlope)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
                context.tr(pl: 'TRYB OBLICZEŃ', en: 'CALCULATION MODE')),
            const SizedBox(height: 8),
            _modeSelector(),
            const SizedBox(height: 20),

            _sectionLabel(context.tr(pl: 'DANE WEJŚCIOWE', en: 'INPUT DATA')),
            const SizedBox(height: 12),

            if (_mode == 'length_to_rise' || _mode == 'slope_from_lr') ...[
              _field(
                _lengthController,
                label: context.tr(pl: 'Długość rury', en: 'Pipe length'),
                suffix: 'mm',
                helperText: context.tr(
                    pl: 'Rzut poziomy; 1 m = 1000 mm',
                    en: 'Horizontal projection; 1 m = 1000 mm'),
              ),
              const SizedBox(height: 12),
            ],

            if (_mode == 'length_to_rise') ...[
              _field(
                _slopeController,
                label: context.tr(pl: 'Nachylenie', en: 'Slope'),
                suffix: '%',
                helperText: context.tr(
                  pl: '1% = 10 mm/m = 1:100',
                  en: '1% = 10 mm/m = 1:100',
                ),
              ),
              if (_mode == 'length_to_rise') ...[
                const SizedBox(height: 8),
                _slopePresets(),
              ],
              const SizedBox(height: 12),
            ],

            if (_mode == 'rise_to_length') ...[
              _field(
                _slopeController,
                label: context.tr(pl: 'Nachylenie', en: 'Slope'),
                suffix: '%',
                helperText: context.tr(
                  pl: '1% = 10 mm/m = 1:100',
                  en: '1% = 10 mm/m = 1:100',
                ),
              ),
              const SizedBox(height: 8),
              _slopePresets(),
              const SizedBox(height: 12),
            ],

            if (_mode != 'length_to_rise') ...[
              _field(
                _riseController,
                label: context.tr(pl: 'Wznios (Rise)', en: 'Rise'),
                suffix: 'mm',
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: Text(context.tr(pl: 'OBLICZ', en: 'CALCULATE')),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 24),

            _sectionLabel(context.tr(pl: 'WYNIKI', en: 'RESULTS')),
            const SizedBox(height: 12),

            if (_mode == 'length_to_rise')
              _result(_riseController,
                  label: context.tr(pl: 'Wznios (Rise)', en: 'Rise'),
                  suffix: 'mm'),

            if (_mode == 'rise_to_length') ...[
              _result(_lengthController,
                  label: context.tr(pl: 'Długość rury', en: 'Pipe length'),
                  suffix: 'mm'),
            ],

            if (_mode == 'slope_from_lr')
              _result(_slopeController,
                  label: context.tr(pl: 'Nachylenie', en: 'Slope'),
                  suffix: '%'),

            const SizedBox(height: 12),
            _result(_angleController,
                label: context.tr(pl: 'Kąt nachylenia', en: 'Slope angle'),
                suffix: '°'),
            const SizedBox(height: 12),
            _result(_mmPerMController,
                label: context.tr(
                    pl: 'mm na metr bieżący', en: 'mm per running metre'),
                suffix: 'mm/m'),

            const SizedBox(height: 16),
            _guide(),
            const SizedBox(height: 16),
            // Formula reference remains available alongside the worked guide.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Wzory: Rise = Długość × %/100  |  Kąt = atan(Rise/Długość)  |  mm/m = % × 10',
                      en: 'Formulas: Rise = Length × %/100  |  Angle = atan(Rise/Length)  |  mm/m = % × 10',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip:
                      context.tr(pl: 'Źródło wzorów', en: 'Formula source'),
                  onPressed: _showFormulaInfo,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeSelector() {
    final cs = Theme.of(context).colorScheme;
    final modes = [
      (
        'length_to_rise',
        context.tr(pl: 'Długość → Wznios', en: 'Length → Rise')
      ),
      (
        'rise_to_length',
        context.tr(pl: 'Wznios → Długość', en: 'Rise → Length')
      ),
      ('slope_from_lr', context.tr(pl: 'Wyznacz %', en: 'Find slope %')),
    ];
    return Column(
      children: modes.map((m) {
        final selected = _mode == m.$1;
        // Custom radio row: expose selection + group membership to screen
        // readers; the visual radio icon is decorative once Semantics conveys
        // the state, so it is excluded to avoid double announcement.
        return Semantics(
          button: true,
          inMutuallyExclusiveGroup: true,
          selected: selected,
          label: m.$2,
          child: InkWell(
            onTap: () => setState(() {
              if (_mode == m.$1) return;
              _clearComputed();
              _mode = m.$1;
              _clearComputed();
            }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primaryContainer.withValues(alpha: 0.4)
                    : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                ),
              ),
              child: Row(children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(m.$2,
                        style: TextStyle(
                            color: selected ? cs.onPrimaryContainer : null))),
              ]),
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

  /// Drainage-slope presets. In food & pharma the line must self-drain, so the
  /// slope is a spec requirement — these are the values that actually appear
  /// on hygienic-piping drawings (1:100 is the common default).
  Widget _slopePresets() {
    final cs = Theme.of(context).colorScheme;
    const presets = <(String, String)>[
      ('0.5', '1:200'),
      ('0.67', '1:150'),
      ('1', '1:100'),
      ('2', '1:50'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
              pl: 'Skróty wpisywania — dotknij, aby wstawić i przeliczyć:',
              en: 'Input shortcuts — tap to apply and recalculate:'),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: presets.map((p) {
            final selected = _parse(_slopeController.text) == _parse(p.$1);
            return Tooltip(
              message: context.tr(
                pl: 'Wstaw ${p.$1}% (${p.$2}) i od razu przelicz',
                en: 'Set ${p.$1}% (${p.$2}) and recalc immediately',
              ),
              child: ActionChip(
                label: Text('${p.$1}%  (${p.$2})',
                    style: const TextStyle(fontSize: 12)),
                backgroundColor:
                    selected ? cs.primaryContainer : cs.surfaceContainerHigh,
                side: BorderSide(
                    color: selected ? cs.primary : cs.outlineVariant),
                onPressed: () {
                  setState(() => _slopeController.text = p.$1);
                  _calculate();
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl,
      {required String label,
      String? suffix,
      bool readOnly = false,
      String? helperText}) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      onChanged: (_) => setState(_clearComputed),
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
        filled: readOnly,
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
