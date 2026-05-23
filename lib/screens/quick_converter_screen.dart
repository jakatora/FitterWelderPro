import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

/// Pocket-converter: length (mm â†” in, ft), temperature (Â°C â†” Â°F),
/// pressure (bar â†” MPa â†” psi), mass-flow (slpm â†” l/min â†” cfh).
/// Long-press any result to copy it.
class QuickConverterScreen extends StatelessWidget {
  const QuickConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(
              pl: 'Konwerter jednostek', en: 'Unit converter')),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.tr(pl: 'DÅ‚ugoÅ›Ä‡', en: 'Length')),
              Tab(text: context.tr(pl: 'Temperatura', en: 'Temperature')),
              Tab(text: context.tr(pl: 'CiÅ›nienie', en: 'Pressure')),
              Tab(text: context.tr(pl: 'PrzepÅ‚yw gazu', en: 'Gas flow')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LengthTab(),
            _TempTab(),
            _PressureTab(),
            _FlowTab(),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
double? _parse(String s) {
  if (s.trim().isEmpty) return null;
  return double.tryParse(s.replaceAll(',', '.'));
}

String _fmt(double v, {int frac = 3}) {
  if (v.abs() >= 10000) return v.toStringAsFixed(0);
  if (v.abs() >= 100) return v.toStringAsFixed(1);
  return v.toStringAsFixed(frac);
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Row({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: _kSec, fontSize: 13)),
            CopyOnLongPress(
              value: value,
              label: label,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
            ),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

class _SmallHint extends StatelessWidget {
  final String text;
  const _SmallHint(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style: const TextStyle(
                color: _kMuted, fontSize: 11, fontStyle: FontStyle.italic)),
      );
}

// â”€â”€â”€ LENGTH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _LengthTab extends StatefulWidget {
  const _LengthTab();
  @override
  State<_LengthTab> createState() => _LengthTabState();
}

class _LengthTabState extends State<_LengthTab> {
  final _ctrl = TextEditingController();
  String _src = 'mm';

  static const _toMm = {
    'mm': 1.0,
    'cm': 10.0,
    'm': 1000.0,
    'in': 25.4,
    'ft': 304.8,
  };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _parse(_ctrl.text);
    final mm = (v ?? 0) * _toMm[_src]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'WartoÅ›Ä‡', en: 'Value'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: _toMm.keys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (k) => setState(() => _src = k ?? 'mm'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (v != null)
          _Card(children: [
            _Row(label: 'mm', value: _fmt(mm), color: _kOrange),
            _Row(label: 'cm', value: _fmt(mm / 10), color: _kSec),
            _Row(label: 'm', value: _fmt(mm / 1000), color: _kSec),
            _Row(label: 'in (")', value: _fmt(mm / 25.4), color: _kBlue),
            _Row(label: 'ft', value: _fmt(mm / 304.8), color: _kSec),
            _SmallHint(context.tr(
                pl: 'Przytrzymaj wartoÅ›Ä‡ â†’ kopia do schowka.',
                en: 'Long-press a value â†’ copy to clipboard.')),
          ]),
      ],
    );
  }
}

// â”€â”€â”€ TEMPERATURE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _TempTab extends StatefulWidget {
  const _TempTab();
  @override
  State<_TempTab> createState() => _TempTabState();
}

class _TempTabState extends State<_TempTab> {
  final _ctrl = TextEditingController();
  String _src = 'Â°C';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _parse(_ctrl.text);
    double c = 0;
    if (v != null) {
      switch (_src) {
        case 'Â°C':
          c = v;
          break;
        case 'Â°F':
          c = (v - 32) * 5 / 9;
          break;
        case 'K':
          c = v - 273.15;
          break;
      }
    }
    final f = c * 9 / 5 + 32;
    final k = c + 273.15;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\-0-9.,]'))
                ],
                decoration: InputDecoration(
                    labelText: context.tr(pl: 'WartoÅ›Ä‡', en: 'Value')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: const [
                  DropdownMenuItem(value: 'Â°C', child: Text('Â°C')),
                  DropdownMenuItem(value: 'Â°F', child: Text('Â°F')),
                  DropdownMenuItem(value: 'K', child: Text('K')),
                ],
                onChanged: (k) => setState(() => _src = k ?? 'Â°C'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (v != null)
          _Card(children: [
            _Row(label: 'Â°C', value: _fmt(c, frac: 1), color: _kOrange),
            _Row(label: 'Â°F', value: _fmt(f, frac: 1), color: _kBlue),
            _Row(label: 'K', value: _fmt(k, frac: 1), color: _kSec),
            _SmallHint(context.tr(
                pl: 'NajczÄ™sty case: konwersja temperatury podgrzewania (preheat) z PWPS w Â°F.',
                en: 'Most common: converting preheat temperature from a PWPS given in Â°F.')),
          ]),
      ],
    );
  }
}

// â”€â”€â”€ PRESSURE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PressureTab extends StatefulWidget {
  const _PressureTab();
  @override
  State<_PressureTab> createState() => _PressureTabState();
}

class _PressureTabState extends State<_PressureTab> {
  final _ctrl = TextEditingController();
  String _src = 'bar';

  static const _toBar = {
    'bar': 1.0,
    'MPa': 10.0,
    'kPa': 0.01,
    'psi': 0.0689476,
    'atm': 1.01325,
  };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _parse(_ctrl.text);
    final bar = (v ?? 0) * _toBar[_src]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                decoration: InputDecoration(
                    labelText: context.tr(pl: 'WartoÅ›Ä‡', en: 'Value')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: _toBar.keys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (k) => setState(() => _src = k ?? 'bar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (v != null)
          _Card(children: [
            _Row(label: 'bar', value: _fmt(bar), color: _kOrange),
            _Row(label: 'MPa', value: _fmt(bar / 10), color: _kSec),
            _Row(label: 'kPa', value: _fmt(bar * 100), color: _kSec),
            _Row(label: 'psi', value: _fmt(bar / 0.0689476), color: _kBlue),
            _Row(label: 'atm', value: _fmt(bar / 1.01325), color: _kSec),
            _SmallHint(context.tr(
                pl: 'Test hydrauliczny zwykle podany w MPa, manometry w bar lub psi.',
                en: 'Hydrotest pressure is usually given in MPa, gauges read bar or psi.')),
          ]),
      ],
    );
  }
}

// â”€â”€â”€ GAS FLOW â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _FlowTab extends StatefulWidget {
  const _FlowTab();
  @override
  State<_FlowTab> createState() => _FlowTabState();
}

class _FlowTabState extends State<_FlowTab> {
  final _ctrl = TextEditingController();
  String _src = 'l/min';

  // Normal conditions; rotameters on shielding-gas regulators are calibrated
  // for atmospheric flow, so l/min == slpm to engineering accuracy on site.
  static const _toLpm = {
    'l/min': 1.0,
    'slpm': 1.0,
    'cfh': 0.4719474,
    'scfh': 0.4719474,
  };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _parse(_ctrl.text);
    final lpm = (v ?? 0) * _toLpm[_src]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                decoration: InputDecoration(
                    labelText: context.tr(pl: 'WartoÅ›Ä‡', en: 'Value')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: _toLpm.keys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (k) => setState(() => _src = k ?? 'l/min'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (v != null)
          _Card(children: [
            _Row(label: 'l/min',  value: _fmt(lpm), color: _kOrange),
            _Row(label: 'slpm',   value: _fmt(lpm), color: _kSec),
            _Row(label: 'cfh',    value: _fmt(lpm / 0.4719474), color: _kBlue),
            _Row(label: 'scfh',   value: _fmt(lpm / 0.4719474), color: _kSec),
            _SmallHint(context.tr(
                pl: 'Argon / mix M21: typowy GMAW 12â€“18 l/min, TIG 6â€“12 l/min.',
                en: 'Argon / M21 mix: typical GMAW 12â€“18 l/min, TIG 6â€“12 l/min.')),
          ]),
      ],
    );
  }
}
