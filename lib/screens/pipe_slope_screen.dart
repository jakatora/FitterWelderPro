import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';

class PipeSlopeScreen extends StatefulWidget {
  const PipeSlopeScreen({super.key});

  @override
  State<PipeSlopeScreen> createState() => _PipeSlopeScreenState();
}

class _PipeSlopeScreenState extends State<PipeSlopeScreen> {
  // Mode: calculate rise from length+slope, OR length from rise+slope, OR slope from length+rise
  String _mode = 'length_to_rise';

  final _lengthController = TextEditingController();
  final _slopeController  = TextEditingController();
  final _riseController   = TextEditingController();

  final _angleController  = TextEditingController();
  final _mmPerMController = TextEditingController();

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Pipe slope formulas:
  //   Rise = Length × slope% / 100
  //   Angle = atan(Rise / Length) = atan(slope% / 100)  [in degrees]
  //   mm per metre = slope% × 10
  //
  // Verification (Length=6000mm, slope=1%):
  //   Rise = 6000 × 0.01 = 60mm
  //   Angle = atan(0.01) ≈ 0.5729°
  //   mm/m  = 10
  void _calculate() {
    if (_mode == 'length_to_rise') {
      final length = _parse(_lengthController.text);
      final slope  = _parse(_slopeController.text);
      if (length <= 0 || slope <= 0) {
        _showError(context.tr(pl: 'Wpisz długość i nachylenie > 0', en: 'Enter length and slope > 0'));
        return;
      }
      final rise     = length * slope / 100.0;
      final angleRad = math.atan(slope / 100.0);
      final angleDeg = angleRad * 180.0 / math.pi;
      final mmPerM   = slope * 10.0;

      _riseController.text    = rise.toStringAsFixed(1);
      _angleController.text   = angleDeg.toStringAsFixed(3);
      _mmPerMController.text  = mmPerM.toStringAsFixed(1);
    } else if (_mode == 'rise_to_length') {
      final rise   = _parse(_riseController.text);
      final slope  = _parse(_slopeController.text);
      if (rise <= 0 || slope <= 0) {
        _showError(context.tr(pl: 'Wpisz wznios i nachylenie > 0', en: 'Enter rise and slope > 0'));
        return;
      }
      final length   = rise / (slope / 100.0);
      final angleRad = math.atan(slope / 100.0);
      final angleDeg = angleRad * 180.0 / math.pi;
      final mmPerM   = slope * 10.0;

      _lengthController.text  = length.toStringAsFixed(1);
      _angleController.text   = angleDeg.toStringAsFixed(3);
      _mmPerMController.text  = mmPerM.toStringAsFixed(1);
    } else {
      // slope from length + rise
      final length = _parse(_lengthController.text);
      final rise   = _parse(_riseController.text);
      if (length <= 0 || rise <= 0) {
        _showError(context.tr(pl: 'Wpisz długość i wznios > 0', en: 'Enter length and rise > 0'));
        return;
      }
      final slope    = (rise / length) * 100.0;
      final angleRad = math.atan(rise / length);
      final angleDeg = angleRad * 180.0 / math.pi;
      final mmPerM   = slope * 10.0;

      _slopeController.text   = slope.toStringAsFixed(3);
      _angleController.text   = angleDeg.toStringAsFixed(3);
      _mmPerMController.text  = mmPerM.toStringAsFixed(1);
    }

    setState(() {});
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    for (final c in [
      _lengthController, _slopeController, _riseController,
      _angleController, _mmPerMController,
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
            _sectionLabel(context.tr(pl: 'TRYB OBLICZEŃ', en: 'CALCULATION MODE')),
            const SizedBox(height: 8),
            _modeSelector(),
            const SizedBox(height: 20),

            _sectionLabel(context.tr(pl: 'DANE WEJŚCIOWE', en: 'INPUT DATA')),
            const SizedBox(height: 12),

            if (_mode != 'slope_from_lr') ...[
              _field(
                _lengthController,
                label: context.tr(pl: 'Długość rury', en: 'Pipe length'),
                suffix: 'mm',
                readOnly: _mode == 'rise_to_length',
              ),
              const SizedBox(height: 12),
            ],

            if (_mode == 'slope_from_lr' || _mode == 'length_to_rise') ...[
              _field(
                _slopeController,
                label: context.tr(pl: 'Nachylenie', en: 'Slope'),
                suffix: '%',
                readOnly: _mode == 'slope_from_lr',
              ),
              const SizedBox(height: 12),
            ],

            if (_mode != 'length_to_rise') ...[
              _field(
                _riseController,
                label: context.tr(pl: 'Wznios (Rise)', en: 'Rise'),
                suffix: 'mm',
                readOnly: _mode == 'rise_to_length',
              ),
              const SizedBox(height: 12),
            ],

            if (_mode == 'slope_from_lr') ...[
              _field(
                _lengthController,
                label: context.tr(pl: 'Długość rury', en: 'Pipe length'),
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
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 24),

            _sectionLabel(context.tr(pl: 'WYNIKI', en: 'RESULTS')),
            const SizedBox(height: 12),

            if (_mode == 'length_to_rise')
              _result(_riseController,
                label: context.tr(pl: 'Wznios (Rise)', en: 'Rise'), suffix: 'mm'),

            if (_mode == 'rise_to_length') ...[
              _result(_lengthController,
                label: context.tr(pl: 'Długość rury', en: 'Pipe length'), suffix: 'mm'),
            ],

            if (_mode == 'slope_from_lr')
              _result(_slopeController,
                label: context.tr(pl: 'Nachylenie', en: 'Slope'), suffix: '%'),

            const SizedBox(height: 12),
            _result(_angleController,
              label: context.tr(pl: 'Kąt nachylenia', en: 'Slope angle'), suffix: '°'),
            const SizedBox(height: 12),
            _result(_mmPerMController,
              label: context.tr(pl: 'mm na metr bieżący', en: 'mm per running metre'), suffix: 'mm/m'),

            const SizedBox(height: 16),
            Text(
              context.tr(
                pl: 'Wzory: Rise = Długość × %/100  |  Kąt = atan(Rise/Długość)  |  mm/m = % × 10',
                en: 'Formulas: Rise = Length × %/100  |  Angle = atan(Rise/Length)  |  mm/m = % × 10',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeSelector() {
    final cs = Theme.of(context).colorScheme;
    final modes = [
      ('length_to_rise', context.tr(pl: 'Długość → Wznios', en: 'Length → Rise')),
      ('rise_to_length', context.tr(pl: 'Wznios → Długość', en: 'Rise → Length')),
      ('slope_from_lr',  context.tr(pl: 'Wyznacz %', en: 'Find slope %')),
    ];
    return Column(
      children: modes.map((m) {
        final selected = _mode == m.$1;
        return InkWell(
          onTap: () => setState(() => _mode = m.$1),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer.withValues(alpha: 0.4) : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
              ),
            ),
            child: Row(children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(m.$2, style: TextStyle(color: selected ? cs.onPrimaryContainer : null)),
            ]),
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
      {required String label, String? suffix, bool readOnly = false}) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
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
      ),
    );
  }
}
