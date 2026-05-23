import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

/// Hydrostatic-test calculator for a pipe run.
/// Inputs the design pressure and pipe geometry, gives back:
///   • test pressure   = factor × design (1.5 per ASME B31.3 § 345.4.2)
///   • water volume    needed to fill the run
///   • allowable hold time / min test duration (10 min minimum per B31.3)
///   • estimated time to fill at a given pump flow
class HydrotestScreen extends StatefulWidget {
  const HydrotestScreen({super.key});

  @override
  State<HydrotestScreen> createState() => _HydrotestScreenState();
}

class _HydrotestScreenState extends State<HydrotestScreen> {
  final _odCtrl     = TextEditingController();
  final _wallCtrl   = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _designCtrl = TextEditingController();
  final _flowCtrl   = TextEditingController(text: '40');

  /// ASME B31.3 default test factor is 1.5 × design.
  double _factor = 1.5;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    for (final c in [_odCtrl, _wallCtrl, _lengthCtrl, _designCtrl, _flowCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _p(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final od = _p(_odCtrl);
    final wall = _p(_wallCtrl);
    final lengthM = _p(_lengthCtrl);
    final design = _p(_designCtrl);
    final flowLpm = _p(_flowCtrl) ?? 0;

    String? error;
    double? id, volL, testPressure, fillMin;
    if (od != null && wall != null) {
      if (wall * 2 >= od) {
        error = _tr('Ścianka ≥ ½ OD — sprawdź wymiary.',
            'Wall ≥ ½ OD — check the values.');
      } else {
        id = od - 2 * wall;
        if (lengthM != null && lengthM > 0) {
          // Volume = π · ID²/4 · L (mm³) → litres
          volL = math.pi * id * id / 4.0 * (lengthM * 1000) * 1e-6;
          if (flowLpm > 0) fillMin = volL / flowLpm;
        }
      }
    }
    if (design != null && design > 0) {
      testPressure = design * _factor;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Próba ciśnieniowa', 'Hydrostatic test')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _tr('Kopiuj raport', 'Copy report'),
            onPressed: (volL == null && testPressure == null)
                ? null
                : () => _copyReport(
                    od: od, wall: wall, id: id, lengthM: lengthM,
                    design: design, factor: _factor,
                    testPressure: testPressure, volL: volL,
                    flowLpm: flowLpm, fillMin: fillMin),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          // ── Geometry ──
          _SectionHeader(_tr('GEOMETRIA RURY', 'PIPE GEOMETRY')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NumField(
              ctrl: _odCtrl, label: _tr('OD (mm)', 'OD (mm)'),
              hint: '60.3', onChanged: () => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(child: _NumField(
              ctrl: _wallCtrl, label: _tr('Ścianka t (mm)', 'Wall t (mm)'),
              hint: '3.91', onChanged: () => setState(() {}))),
          ]),
          const SizedBox(height: 10),
          _NumField(
            ctrl: _lengthCtrl,
            label: _tr('Długość linii (m)', 'Line length (m)'),
            hint: '120',
            onChanged: () => setState(() {}),
          ),

          const SizedBox(height: 14),
          _SectionHeader(_tr('CIŚNIENIE', 'PRESSURE')),
          const SizedBox(height: 8),
          _NumField(
            ctrl: _designCtrl,
            label: _tr('Ciśnienie projektowe (bar)', 'Design pressure (bar)'),
            hint: '10',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FactorChip(
                    label: '1.5 ×',
                    sub: _tr('ASME B31.3', 'ASME B31.3'),
                    selected: _factor == 1.5,
                    onTap: () => setState(() => _factor = 1.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FactorChip(
                    label: '1.3 ×',
                    sub: _tr('PED gaz', 'PED gas'),
                    selected: _factor == 1.3,
                    onTap: () => setState(() => _factor = 1.3)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FactorChip(
                    label: '1.43 ×',
                    sub: _tr('B31.1 para', 'B31.1 steam'),
                    selected: _factor == 1.43,
                    onTap: () => setState(() => _factor = 1.43)),
              ),
            ],
          ),

          const SizedBox(height: 14),
          _SectionHeader(_tr('NAPEŁNIANIE', 'FILLING')),
          const SizedBox(height: 8),
          _NumField(
            ctrl: _flowCtrl,
            label: _tr('Wydajność pompy (l/min)', 'Pump flow (l/min)'),
            hint: '40',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 18),

          if (error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kRed.withValues(alpha: 0.3)),
              ),
              child: Text(error,
                  style: const TextStyle(color: _kRed, fontSize: 13)),
            ),

          // ── Results ──
          if (testPressure != null || volL != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kOrange.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (testPressure != null)
                    _ResRow(
                      label: _tr('Ciśnienie testowe', 'Test pressure'),
                      value: '${testPressure.toStringAsFixed(2)} bar',
                      sub: '= ${(testPressure / 10).toStringAsFixed(3)} MPa  '
                          '= ${(testPressure * 14.5038).toStringAsFixed(0)} psi',
                      color: _kOrange,
                      big: true,
                    ),
                  if (testPressure != null && volL != null)
                    const Divider(height: 18, color: _kBorder),
                  if (volL != null) ...[
                    _ResRow(
                      label: _tr('Objętość wody', 'Water volume'),
                      value: '${volL.toStringAsFixed(1)} L',
                      sub: '= ${(volL / 1000).toStringAsFixed(3)} m³',
                      color: _kBlue,
                      big: true,
                    ),
                    if (id != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_tr('ID', 'ID')}: ${id.toStringAsFixed(2)} mm',
                          style: const TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ),
                    if (fillMin != null) ...[
                      const Divider(height: 18, color: _kBorder),
                      _ResRow(
                        label: _tr('Czas napełniania', 'Fill time'),
                        value: '≈ ${fillMin.toStringAsFixed(1)} min',
                        sub: '${flowLpm.toStringAsFixed(0)} l/min',
                        color: _kGreen,
                        big: false,
                      ),
                    ],
                  ],
                  const Divider(height: 18, color: _kBorder),
                  _ResRow(
                    label: _tr('Minimalny czas próby',
                        'Minimum hold time'),
                    value: '10 min',
                    sub: _tr('wg ASME B31.3 § 345.4.2',
                        'per ASME B31.3 § 345.4.2'),
                    color: _kSec,
                    big: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kRed.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _kRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr(
                        'BHP: woda pod ciśnieniem ma dużą energię. Strefa testu '
                        'oznakowana i wygrodzona, ludzie poza strefą, zawory '
                        'odpowietrzające na najwyższych punktach, manometr '
                        'kalibrowany. Procedurę pisze inżynier QC.',
                        'SAFETY: pressurised water carries significant energy. '
                        'Mark and cordon off the test area, keep people out, fit '
                        'vents at high points, use a calibrated gauge. The QC '
                        'engineer writes the procedure.',
                      ),
                      style: const TextStyle(
                          color: _kSec, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyReport({
    required double? od,
    required double? wall,
    required double? id,
    required double? lengthM,
    required double? design,
    required double factor,
    required double? testPressure,
    required double? volL,
    required double flowLpm,
    required double? fillMin,
  }) async {
    final buf = StringBuffer();
    buf.writeln(_tr('Próba ciśnieniowa — raport',
        'Hydrostatic test — report'));
    buf.writeln('─' * 28);
    if (od != null) buf.writeln('OD: ${od.toStringAsFixed(2)} mm');
    if (wall != null) buf.writeln('Wall: ${wall.toStringAsFixed(2)} mm');
    if (id != null) buf.writeln('ID: ${id.toStringAsFixed(2)} mm');
    if (lengthM != null) {
      buf.writeln('${_tr('Długość', 'Length')}: '
          '${lengthM.toStringAsFixed(1)} m');
    }
    if (design != null) {
      buf.writeln('${_tr('Ciśnienie projektowe', 'Design pressure')}: '
          '${design.toStringAsFixed(2)} bar');
      buf.writeln('${_tr('Współczynnik', 'Factor')}: '
          '${factor.toStringAsFixed(2)} ×');
    }
    if (testPressure != null) {
      buf.writeln('${_tr('Ciśnienie testowe', 'Test pressure')}: '
          '${testPressure.toStringAsFixed(2)} bar  '
          '(${(testPressure / 10).toStringAsFixed(3)} MPa, '
          '${(testPressure * 14.5038).toStringAsFixed(0)} psi)');
    }
    if (volL != null) {
      buf.writeln('${_tr('Objętość wody', 'Water volume')}: '
          '${volL.toStringAsFixed(1)} L  '
          '(${(volL / 1000).toStringAsFixed(3)} m³)');
    }
    if (fillMin != null) {
      buf.writeln('${_tr('Czas napełniania', 'Fill time')}: '
          '≈ ${fillMin.toStringAsFixed(1)} min @ '
          '${flowLpm.toStringAsFixed(0)} l/min');
    }
    buf.writeln('${_tr('Min. czas próby', 'Min. hold time')}: 10 min');
    if (!mounted) return;
    await copyToClipboard(context, buf.toString(),
        label: _tr('Raport hydrotest', 'Hydrotest report'));
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: _kMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1),
      );
}

class _NumField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final VoidCallback onChanged;
  const _NumField({
    required this.ctrl,
    required this.label,
    required this.onChanged,
    this.hint,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
      ],
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => onChanged(),
    );
  }
}

class _FactorChip extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _FactorChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kOrange.withValues(alpha: 0.14) : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? _kOrange : _kBorder,
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? _kOrange : _kSec,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ResRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color color;
  final bool big;
  const _ResRow({
    required this.label,
    required this.value,
    required this.color,
    this.sub,
    this.big = false,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: _kSec, fontSize: 13)),
            ),
            CopyOnLongPress(
              value: value,
              label: label,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: big ? 20 : 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
            ),
          ],
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub!,
                style: const TextStyle(color: _kMuted, fontSize: 11)),
          ),
      ],
    );
  }
}
