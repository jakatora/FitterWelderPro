import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

/// Pocket-converter: length (mm ↔ in, ft), temperature (°C ↔ °F),
/// pressure (bar ↔ MPa ↔ psi), mass-flow (slpm ↔ l/min ↔ cfh).
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
          actions: [
            HelpButton(help: kHelpHome),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.tr(pl: 'Długość', en: 'Length')),
              Tab(text: context.tr(pl: 'Temperatura', en: 'Temperature')),
              Tab(text: context.tr(pl: 'Ciśnienie', en: 'Pressure')),
              Tab(text: context.tr(pl: 'Przepływ gazu', en: 'Gas flow')),
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

// ─── helpers ──────────────────────────────────────────────────────────────────
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
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Padding(
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
          ),
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

// ─── LENGTH ───────────────────────────────────────────────────────────────────
class _LengthTab extends StatefulWidget {
  const _LengthTab();
  @override
  State<_LengthTab> createState() => _LengthTabState();
}

class _LengthTabState extends State<_LengthTab> {
  final _ctrl = TextEditingController();
  String _src = 'mm';

  void _clear() {
    Haptic.tap();
    _ctrl.clear();
    setState(() => _src = 'mm');
  }

  static const _toMm = {
    'mm': 1.0,
    'cm': 10.0,
    'm': 1000.0,
    'in': 25.4,
    'ft': 304.8,
  };

  // Pre-built once: dropdown rebuilds on every keystroke otherwise.
  static const _items = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'mm', child: Text('mm')),
    DropdownMenuItem(value: 'cm', child: Text('cm')),
    DropdownMenuItem(value: 'm', child: Text('m')),
    DropdownMenuItem(value: 'in', child: Text('in')),
    DropdownMenuItem(value: 'ft', child: Text('ft')),
  ];

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
                  labelText: context.tr(pl: 'Wartość', en: 'Value'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: _items,
                onChanged: (k) {
                  Haptic.tap();
                  setState(() => _src = k ?? 'mm');
                },
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _clear,
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
                pl: 'Przytrzymaj wartość → kopia do schowka.',
                en: 'Long-press a value → copy to clipboard.')),
          ]),
      ],
    );
  }
}

// ─── TEMPERATURE ──────────────────────────────────────────────────────────────
class _TempTab extends StatefulWidget {
  const _TempTab();
  @override
  State<_TempTab> createState() => _TempTabState();
}

class _TempTabState extends State<_TempTab> {
  final _ctrl = TextEditingController();
  String _src = '°C';

  void _clear() {
    Haptic.tap();
    _ctrl.clear();
    setState(() => _src = '°C');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _parse(_ctrl.text);
    // Kelvin cannot be negative (absolute zero floor); flag inline.
    final kelvinBelowZero = v != null && _src == 'K' && v < 0;
    double c = 0;
    if (v != null && !kelvinBelowZero) {
      switch (_src) {
        case '°C':
          c = v;
          break;
        case '°F':
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
                  labelText: context.tr(pl: 'Wartość', en: 'Value'),
                  errorText: kelvinBelowZero
                      ? context.tr(
                          pl: 'K nie może być ujemna (zero absolutne).',
                          en: 'K cannot be negative (absolute zero).')
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: const [
                  DropdownMenuItem(value: '°C', child: Text('°C')),
                  DropdownMenuItem(value: '°F', child: Text('°F')),
                  DropdownMenuItem(value: 'K', child: Text('K')),
                ],
                onChanged: (k) => setState(() => _src = k ?? '°C'),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _clear,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (v != null && !kelvinBelowZero)
          _Card(children: [
            _Row(label: '°C', value: _fmt(c, frac: 1), color: _kOrange),
            _Row(label: '°F', value: _fmt(f, frac: 1), color: _kBlue),
            _Row(label: 'K', value: _fmt(k, frac: 1), color: _kSec),
            _SmallHint(context.tr(
                pl: 'Najczęsty case: konwersja temperatury podgrzewania (preheat) z PWPS w °F.',
                en: 'Most common: converting preheat temperature from a PWPS given in °F.')),
          ]),
      ],
    );
  }
}

// ─── PRESSURE ─────────────────────────────────────────────────────────────────
class _PressureTab extends StatefulWidget {
  const _PressureTab();
  @override
  State<_PressureTab> createState() => _PressureTabState();
}

class _PressureTabState extends State<_PressureTab> {
  final _ctrl = TextEditingController();
  String _src = 'bar';

  void _clear() {
    Haptic.tap();
    _ctrl.clear();
    setState(() => _src = 'bar');
  }

  static const _toBar = {
    'bar': 1.0,
    'MPa': 10.0,
    'kPa': 0.01,
    'psi': 0.0689476,
    'atm': 1.01325,
  };

  static const _items = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'bar', child: Text('bar')),
    DropdownMenuItem(value: 'MPa', child: Text('MPa')),
    DropdownMenuItem(value: 'kPa', child: Text('kPa')),
    DropdownMenuItem(value: 'psi', child: Text('psi')),
    DropdownMenuItem(value: 'atm', child: Text('atm')),
  ];

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
                    labelText: context.tr(pl: 'Wartość', en: 'Value')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: _items,
                onChanged: (k) => setState(() => _src = k ?? 'bar'),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _clear,
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

// ─── GAS FLOW ─────────────────────────────────────────────────────────────────
class _FlowTab extends StatefulWidget {
  const _FlowTab();
  @override
  State<_FlowTab> createState() => _FlowTabState();
}

class _FlowTabState extends State<_FlowTab> {
  final _ctrl = TextEditingController();
  String _src = 'l/min';

  void _clear() {
    Haptic.tap();
    _ctrl.clear();
    setState(() => _src = 'l/min');
  }

  // Normal conditions; rotameters on shielding-gas regulators are calibrated
  // for atmospheric flow, so l/min == slpm to engineering accuracy on site.
  static const _toLpm = {
    'l/min': 1.0,
    'slpm': 1.0,
    'cfh': 0.4719474,
    'scfh': 0.4719474,
  };

  static const _items = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'l/min', child: Text('l/min')),
    DropdownMenuItem(value: 'slpm', child: Text('slpm')),
    DropdownMenuItem(value: 'cfh', child: Text('cfh')),
    DropdownMenuItem(value: 'scfh', child: Text('scfh')),
  ];

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
                    labelText: context.tr(pl: 'Wartość', en: 'Value')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _src,
                items: _items,
                onChanged: (k) => setState(() => _src = k ?? 'l/min'),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _clear,
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
                pl: 'Argon / mix M21: typowy GMAW 12–18 l/min, TIG 6–12 l/min.',
                en: 'Argon / M21 mix: typical GMAW 12–18 l/min, TIG 6–12 l/min.')),
          ]),
      ],
    );
  }
}
