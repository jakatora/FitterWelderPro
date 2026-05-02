// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';

// ── Kolory ────────────────────────────────────────────────────────────────
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kMuted  = Color(0xFF55607A);
const _kSec    = Color(0xFF9BA3C7);

class WelderToolsScreen extends StatelessWidget {
  const WelderToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(pl: 'Kalkulatory - Spawacz', en: 'Calculators - Welder')),
          actions: [HelpButton(help: kHelpWelderTools)],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.tr(pl: 'Heat Input', en: 'Heat Input')),
              Tab(text: context.tr(pl: 'Temperatura', en: 'Preheat')),
              Tab(text: 'O₂ Purge'),
              Tab(text: context.tr(pl: 'Gaz', en: 'Gas')),
              Tab(text: 'Timer'),
              Tab(text: context.tr(pl: 'Ciśnienie', en: 'Pressure')),
            ],
          ),
        ),
        body: TabBarView(children: [
          _HeatInputTab(),
          _PreheatTab(),
          _O2PurgeTab(),
          _GasConsumptionTab(),
          _WeldTimerTab(),
          _PressureConverterTab(),
        ]),
      ),
    );
  }
}

// ── Wspólne widgety ───────────────────────────────────────────────────────
class _NumField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final String? unit;
  final String? helper;
  final VoidCallback? onChanged;
  const _NumField({required this.ctrl, required this.label, this.hint, this.unit, this.helper, this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, hintText: hint, suffixText: unit, helperText: helper),
    onChanged: (_) => onChanged?.call(),
  );
}

class _ResultCard extends StatelessWidget {
  final List<Widget> rows;
  const _ResultCard({required this.rows});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [_kOrange.withOpacity(0.10), _kOrange.withOpacity(0.03)]),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _kOrange.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
  );
}

class _RRow extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;
  final Color? color;
  final bool dimmed;
  const _RRow(this.label, this.value, {this.primary = false, this.color, this.dimmed = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: dimmed ? _kMuted : _kSec))),
        Text(value, style: TextStyle(
          fontSize: primary ? 22 : 14,
          fontWeight: primary ? FontWeight.w800 : FontWeight.w600,
          color: color ?? (primary ? _kOrange : const Color(0xFFE8ECF0)),
          letterSpacing: primary ? -0.4 : 0,
        )),
      ],
    ),
  );
}

class _ErrBox extends StatelessWidget {
  final String t;
  const _ErrBox(this.t);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: _kRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kRed.withOpacity(0.3))),
    child: Text(t, style: TextStyle(fontSize: 12, color: _kRed.withOpacity(0.9))),
  );
}

class _InfoBox extends StatelessWidget {
  final String t;
  const _InfoBox(this.t);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _kBlue.withOpacity(0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _kBlue.withOpacity(0.2)),
    ),
    child: Text(t, style: const TextStyle(fontSize: 12, color: _kSec, height: 1.5)),
  );
}

class _SecLabel extends StatelessWidget {
  final String t;
  const _SecLabel(this.t);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _kMuted, letterSpacing: 1.2)),
  );
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 1: HEAT INPUT (Energia liniowa)
// ══════════════════════════════════════════════════════════════════════════
class _HeatInputTab extends StatefulWidget {
  @override
  State<_HeatInputTab> createState() => _HeatInputTabState();
}

class _HeatInputTabState extends State<_HeatInputTab> {
  final _uCtrl = TextEditingController();   // napięcie V
  final _iCtrl = TextEditingController();   // prąd A
  final _vCtrl = TextEditingController();   // prędkość mm/min
  final _kCtrl = TextEditingController(text: '0.80'); // wsp. termiczny

  double? _hiKJmm;
  double? _hiJmm;
  String? _assessment;
  Color? _assessColor;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override void dispose() { _uCtrl.dispose(); _iCtrl.dispose(); _vCtrl.dispose(); _kCtrl.dispose(); super.dispose(); }

  void _calc() {
    setState(() {
      _error = null; _hiKJmm = null; _hiJmm = null; _assessment = null; _assessColor = null;
      final u = double.tryParse(_uCtrl.text.replaceAll(',', '.'));
      final i = double.tryParse(_iCtrl.text.replaceAll(',', '.'));
      final v = double.tryParse(_vCtrl.text.replaceAll(',', '.'));
      final k = double.tryParse(_kCtrl.text.replaceAll(',', '.')) ?? 1.0;
      if (u == null || u <= 0) { _error = _tr('Podaj napięcie U [V]', 'Enter voltage U [V]'); return; }
      if (i == null || i <= 0) { _error = _tr('Podaj prąd I [A]', 'Enter current I [A]'); return; }
      if (v == null || v <= 0) { _error = _tr('Podaj prędkość spawania v [mm/min]', 'Enter welding speed v [mm/min]'); return; }
      // HI [kJ/mm] = k × U × I × 60 / (v × 1000)
      _hiJmm  = k * u * i * 60.0 / v;
      _hiKJmm = _hiJmm! / 1000.0;
      // Ocena dla stali nierdzewnej SS 316L / 304L
      if (_hiKJmm! < 0.3)       { _assessment = _tr('Za mała — ryzyko braku wtopienia', 'Too low — risk of lack of fusion'); _assessColor = _kRed; }
      else if (_hiKJmm! <= 1.0) { _assessment = _tr('Dobra — typowy zakres dla SS', 'Good — typical range for SS'); _assessColor = _kGreen; }
      else if (_hiKJmm! <= 1.5) { _assessment = _tr('Akceptowalna — sprawdź WPS', 'Acceptable — verify with WPS'); _assessColor = _kOrange; }
      else                       { _assessment = _tr('Za duża — ryzyko sensityzacji SS, spawaj wolniej', 'Too high — risk of SS sensitisation, weld slower'); _assessColor = _kRed; }
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _InfoBox(_tr(
        'Energia liniowa wg EN 1011 / ASME IX:\n'
        'HI = k × U × I × 60 / (v × 1000)  [kJ/mm]\n'
        'k = wsp. termiczny: TIG=0.60, MIG=0.80, MMA=1.00',
        'Heat input per EN 1011 / ASME IX:\n'
        'HI = k × U × I × 60 / (v × 1000)  [kJ/mm]\n'
        'k = thermal efficiency: TIG=0.60, MIG=0.80, MMA=1.00',
      )),
      Row(children: [
        Expanded(child: _NumField(ctrl: _uCtrl, label: _tr('Napięcie U', 'Voltage U'), hint: '12', unit: 'V', onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _iCtrl, label: _tr('Prąd I', 'Current I'), hint: '80', unit: 'A', onChanged: _calc)),
      ]),
      const SizedBox(height: 10),
      _NumField(ctrl: _vCtrl, label: _tr('Prędkość spawania v', 'Welding speed v'), hint: '100', unit: 'mm/min', onChanged: _calc),
      const SizedBox(height: 10),
      _NumField(ctrl: _kCtrl, label: _tr('Wsp. termiczny k (TIG=0.60, MIG=0.80, MMA=1.00)', 'Thermal eff. k (TIG=0.60, MIG=0.80, MMA=1.00)'), hint: '0.80', onChanged: _calc),
      const SizedBox(height: 14),
      if (_hiKJmm != null) _ResultCard(rows: [
        _RRow(_tr('Energia liniowa HI', 'Heat input HI'), '${_hiKJmm!.toStringAsFixed(3)} kJ/mm', primary: true),
        _RRow('', '${_hiJmm!.toStringAsFixed(0)} J/mm', dimmed: true),
        const Divider(height: 16, color: _kBorder),
        if (_assessment != null) Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _assessColor)),
          const SizedBox(width: 8),
          Expanded(child: Text(_assessment!, style: TextStyle(fontSize: 12, color: _assessColor, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        _RRow(_tr('Limit WPS (typowy SS)', 'Typical SS WPS limit'), '≤ 1.0 kJ/mm', dimmed: true),
      ]),
      if (_error != null) _ErrBox(_error!),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 2: TEMPERATURA PODGRZEWANIA I MIĘDZYŚCIEGOWA
// ══════════════════════════════════════════════════════════════════════════
class _PreheatTab extends StatefulWidget {
  @override State<_PreheatTab> createState() => _PreheatTabState();
}

class _PreheatTabState extends State<_PreheatTab> {
  final _tCtrl   = TextEditingController();  // grubość ścianki mm
  final _cCtrl   = TextEditingController();  // %C
  final _mnCtrl  = TextEditingController();  // %Mn
  final _siCtrl  = TextEditingController();  // %Si
  final _crCtrl  = TextEditingController();  // %Cr
  final _moCtrl  = TextEditingController();  // %Mo
  final _niCtrl  = TextEditingController();  // %Ni
  final _cuCtrl  = TextEditingController();  // %Cu
  final _vCtrl   = TextEditingController();  // %V
  String _matType = 'CS'; // CS lub SS (pre-set)

  double? _cev;
  double? _tMin;   // temperatura podgrzewania min °C
  double? _tiMax;  // temperatura międzyściegowa max °C
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override void dispose() {
    for (final c in [_tCtrl, _cCtrl, _mnCtrl, _siCtrl, _crCtrl, _moCtrl, _niCtrl, _cuCtrl, _vCtrl]) c.dispose();
    super.dispose();
  }

  void _presetSS() {
    _cCtrl.text = '0.03'; _mnCtrl.text = '2.0'; _siCtrl.text = '0.75';
    _crCtrl.text = '17.0'; _moCtrl.text = '2.5'; _niCtrl.text = '12.0';
    _cuCtrl.text = '0'; _vCtrl.text = '0';
    setState(() => _matType = 'SS');
    _calc();
  }

  void _presetCS() {
    _cCtrl.text = '0.20'; _mnCtrl.text = '1.50'; _siCtrl.text = '0.35';
    _crCtrl.text = '0'; _moCtrl.text = '0'; _niCtrl.text = '0';
    _cuCtrl.text = '0'; _vCtrl.text = '0';
    setState(() => _matType = 'CS');
    _calc();
  }

  void _calc() {
    setState(() {
      _error = null; _cev = null; _tMin = null; _tiMax = null;
      final t  = double.tryParse(_tCtrl.text.replaceAll(',', '.'));
      final c  = double.tryParse(_cCtrl.text.replaceAll(',', '.'));
      final mn = double.tryParse(_mnCtrl.text.replaceAll(',', '.')) ?? 0;
      final cr = double.tryParse(_crCtrl.text.replaceAll(',', '.')) ?? 0;
      final mo = double.tryParse(_moCtrl.text.replaceAll(',', '.')) ?? 0;
      final ni = double.tryParse(_niCtrl.text.replaceAll(',', '.')) ?? 0;
      final cu = double.tryParse(_cuCtrl.text.replaceAll(',', '.')) ?? 0;
      final v  = double.tryParse(_vCtrl.text.replaceAll(',', '.')) ?? 0;
      if (t == null || t <= 0) { _error = _tr('Podaj grubość ścianki', 'Enter wall thickness'); return; }
      if (c == null) { _error = _tr('Podaj % C', 'Enter % C'); return; }
      // CEV = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15  (EN ISO 17642 / IIW)
      final cev = c + mn / 6.0 + (cr + mo + v) / 5.0 + (ni + cu) / 15.0;
      _cev = cev;
      // Temperatura podgrzewania wg EN ISO 13916 / CET method uproszczona
      if (_matType == 'SS') {
        _tMin = 0;    // SS austenitic — brak podgrzewania
        _tiMax = 175; // max międzyściegowa wg EN ISO 16834
      } else {
        // CS: uproszczona formuła Seferian
        final tp = 350.0 * math.sqrt(cev - 0.25) + 0.25 * math.sqrt(t) - 25;
        _tMin = tp < 0 ? 0 : tp;
        _tiMax = 250;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _InfoBox(_tr(
        'CEV wg IIW: C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15\n'
        'Temp. podgrzewania wg EN ISO 13916 / Seferian.',
        'CEV per IIW: C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15\n'
        'Preheat temp. per EN ISO 13916 / Seferian.',
      )),
      // Preset buttons
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: _presetSS,
          style: OutlinedButton.styleFrom(side: BorderSide(color: _matType == 'SS' ? _kOrange : _kBorder)),
          child: Text('SS 316L', style: TextStyle(color: _matType == 'SS' ? _kOrange : _kSec)),
        )),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton(
          onPressed: _presetCS,
          style: OutlinedButton.styleFrom(side: BorderSide(color: _matType == 'CS' ? _kOrange : _kBorder)),
          child: Text('CS (przykład)', style: TextStyle(color: _matType == 'CS' ? _kOrange : _kSec)),
        )),
      ]),
      const SizedBox(height: 12),
      _NumField(ctrl: _tCtrl, label: _tr('Grubość ścianki t (mm)', 'Wall thickness t (mm)'), hint: '3.0', unit: 'mm', onChanged: _calc),
      const SizedBox(height: 10),
      _SecLabel(_tr('Skład chemiczny (%)', 'Chemical composition (%)')),
      Row(children: [
        Expanded(child: _NumField(ctrl: _cCtrl,  label: 'C %',  hint: '0.03', onChanged: _calc)),
        const SizedBox(width: 8),
        Expanded(child: _NumField(ctrl: _mnCtrl, label: 'Mn %', hint: '2.0',  onChanged: _calc)),
        const SizedBox(width: 8),
        Expanded(child: _NumField(ctrl: _siCtrl, label: 'Si %', hint: '0.75', onChanged: _calc)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _NumField(ctrl: _crCtrl, label: 'Cr %', hint: '17',   onChanged: _calc)),
        const SizedBox(width: 8),
        Expanded(child: _NumField(ctrl: _moCtrl, label: 'Mo %', hint: '2.5',  onChanged: _calc)),
        const SizedBox(width: 8),
        Expanded(child: _NumField(ctrl: _niCtrl, label: 'Ni %', hint: '12',   onChanged: _calc)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _NumField(ctrl: _cuCtrl, label: 'Cu %', hint: '0',    onChanged: _calc)),
        const SizedBox(width: 8),
        Expanded(child: _NumField(ctrl: _vCtrl,  label: 'V %',  hint: '0',    onChanged: _calc)),
        const SizedBox(width: 8),
        const Expanded(child: SizedBox()),
      ]),
      const SizedBox(height: 14),
      if (_cev != null) _ResultCard(rows: [
        _RRow('CEV (IIW)', _cev!.toStringAsFixed(3), primary: true),
        const Divider(height: 16, color: _kBorder),
        _RRow(_tr('Temperatura podgrzewania min.', 'Min. preheat temperature'),
              '${_tMin!.toStringAsFixed(0)} °C',
              color: _tMin! > 0 ? _kOrange : _kGreen, primary: false),
        _RRow(_tr('Temperatura międzyściegowa max.', 'Max. interpass temperature'),
              '${_tiMax!.toStringAsFixed(0)} °C',
              color: _kBlue),
        const SizedBox(height: 8),
        if (_matType == 'SS')
          Text(_tr('SS austenityczna — brak wymagania podgrzewania (EN ISO 16834).',
                   'Austenitic SS — no preheat required (EN ISO 16834).'),
               style: const TextStyle(fontSize: 11, color: _kSec)),
        if (_matType == 'CS' && _cev! > 0.45)
          Text(_tr('⚠ CEV > 0.45 — wysoka skłonność do pęknięć na zimno. Wymagane podgrzewanie!',
                   '⚠ CEV > 0.45 — high risk of cold cracking. Preheat mandatory!'),
               style: const TextStyle(fontSize: 11, color: _kRed, fontWeight: FontWeight.w600)),
      ]),
      if (_error != null) _ErrBox(_error!),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 3: O₂ PURGE (model wykładniczy, ppm)
// ══════════════════════════════════════════════════════════════════════════
class _O2PurgeTab extends StatefulWidget {
  @override State<_O2PurgeTab> createState() => _O2PurgeTabState();
}

class _O2PurgeTabState extends State<_O2PurgeTab> {
  final _odCtrl = TextEditingController();
  final _tCtrl  = TextEditingController();
  final _lCtrl  = TextEditingController();  // długość mm
  final _qCtrl  = TextEditingController();  // L/min
  final _c0Ctrl = TextEditingController(text: '210000'); // ppm O₂ na start (powietrze=210000ppm)
  final _targetCtrl = TextEditingController(text: '20'); // target ppm

  double? _volL;
  double? _timeSec;
  double? _finalPpm;
  double? _exchanges;
  String? _assessment;
  Color? _assessColor;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override void dispose() { for (final c in [_odCtrl, _tCtrl, _lCtrl, _qCtrl, _c0Ctrl, _targetCtrl]) c.dispose(); super.dispose(); }

  void _calc() {
    setState(() {
      _error = null; _volL = null; _timeSec = null; _finalPpm = null; _exchanges = null; _assessment = null;
      final od = double.tryParse(_odCtrl.text.replaceAll(',', '.'));
      final t  = double.tryParse(_tCtrl.text.replaceAll(',', '.'));
      final l  = double.tryParse(_lCtrl.text.replaceAll(',', '.'));
      final q  = double.tryParse(_qCtrl.text.replaceAll(',', '.'));
      final c0 = double.tryParse(_c0Ctrl.text.replaceAll(',', '.')) ?? 210000;
      final target = double.tryParse(_targetCtrl.text.replaceAll(',', '.')) ?? 20;
      if (od == null || od <= 0 || t == null || t <= 0) { _error = _tr('Podaj OD i grubość ścianki', 'Enter OD and wall thickness'); return; }
      if (l == null || l <= 0) { _error = _tr('Podaj długość odcinka (mm)', 'Enter section length (mm)'); return; }
      if (q == null || q <= 0) { _error = _tr('Podaj przepływ gazu Q (L/min)', 'Enter gas flow Q (L/min)'); return; }
      final id = od - 2.0 * t;
      if (id <= 0) { _error = _tr('OD mniejszy niż 2×t', 'OD smaller than 2×t'); return; }
      // Objętość [L]
      final vol = math.pi * (id / 2.0) * (id / 2.0) * l / 1e6;
      _volL = vol;
      // Czas [s] aby osiągnąć target ppm: C(t) = C0 × exp(-Q×t/V)
      // => t = -V/Q × ln(target/C0)
      final qLps = q / 60.0; // L/s
      final timeSec = -(vol / qLps) * math.log(target / c0);
      _timeSec = timeSec;
      // Stężenie po 5 wymianach
      _exchanges = q * (timeSec / 60.0) / vol;
      _finalPpm  = c0 * math.exp(-qLps * timeSec / vol);
      // Ocena
      if (_finalPpm! <= 20)  { _assessment = _tr('Doskonały — < 20 ppm (standard pharma)', 'Excellent — < 20 ppm (pharma grade)'); _assessColor = _kGreen; }
      else if (_finalPpm! <= 100) { _assessment = _tr('Dobry — < 100 ppm (standard przemysłowy)', 'Good — < 100 ppm (industrial grade)'); _assessColor = _kOrange; }
      else { _assessment = _tr('Niewystarczający — ryzyko przebarwień', 'Insufficient — risk of discolouration'); _assessColor = _kRed; }
    });
  }

  String _fmtTime(double sec) {
    final m = (sec / 60).floor();
    final s = (sec % 60).round();
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _InfoBox(_tr(
        'Model wykładniczy: C(t) = C₀ × e^(−Q×t/V)\n'
        'Standard pharma: cel < 20 ppm O₂\n'
        'Standard przemysłowy: < 100 ppm O₂',
        'Exponential model: C(t) = C₀ × e^(−Q×t/V)\n'
        'Pharma standard: target < 20 ppm O₂\n'
        'Industrial standard: < 100 ppm O₂',
      )),
      Row(children: [
        Expanded(child: _NumField(ctrl: _odCtrl, label: 'OD (mm)', hint: '60.3', unit: 'mm', onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _tCtrl, label: 't (mm)', hint: '2.0', unit: 'mm', onChanged: _calc)),
      ]),
      const SizedBox(height: 10),
      _NumField(ctrl: _lCtrl, label: _tr('Długość odcinka do purge (mm)', 'Section length to purge (mm)'), hint: '1000', unit: 'mm', onChanged: _calc),
      const SizedBox(height: 10),
      _NumField(ctrl: _qCtrl, label: _tr('Przepływ gazu Q (L/min)', 'Gas flow Q (L/min)'), hint: '10', unit: 'L/min', onChanged: _calc),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _NumField(ctrl: _c0Ctrl, label: _tr('Stężenie startowe (ppm)', 'Initial concentration (ppm)'), hint: '210000', helper: _tr('Powietrze = 210 000 ppm', 'Air = 210 000 ppm'), onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _targetCtrl, label: _tr('Cel (ppm O₂)', 'Target (ppm O₂)'), hint: '20', onChanged: _calc)),
      ]),
      const SizedBox(height: 14),
      if (_volL != null && _timeSec != null) _ResultCard(rows: [
        _RRow(_tr('Objętość odcinka', 'Section volume'), '${_volL!.toStringAsFixed(3)} L'),
        _RRow(_tr('Czas purge', 'Purge time'), _fmtTime(_timeSec!), primary: true),
        _RRow(_tr('Wymian objętości', 'Volume changes'), _exchanges!.toStringAsFixed(1)),
        const Divider(height: 16, color: _kBorder),
        _RRow(_tr('Stężenie końcowe', 'Final concentration'), '${_finalPpm!.toStringAsFixed(1)} ppm O₂'),
        if (_assessment != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _assessColor)),
            const SizedBox(width: 8),
            Expanded(child: Text(_assessment!, style: TextStyle(fontSize: 12, color: _assessColor, fontWeight: FontWeight.w600))),
          ]),
        ],
      ]),
      if (_error != null) _ErrBox(_error!),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 4: ZUŻYCIE GAZU
// ══════════════════════════════════════════════════════════════════════════
class _GasConsumptionTab extends StatefulWidget {
  @override State<_GasConsumptionTab> createState() => _GasConsumptionTabState();
}

class _GasConsumptionTabState extends State<_GasConsumptionTab> {
  final _nCtrl    = TextEditingController(); // liczba spoin
  final _tCtrl    = TextEditingController(); // czas spawania na spoinę [min]
  final _torchCtrl= TextEditingController(text: '10'); // torch L/min
  final _preCtrl  = TextEditingController(text: '5');  // pre-flow [s]
  final _postCtrl = TextEditingController(text: '10'); // post-flow [s]
  final _purgeCtrl= TextEditingController(); // purge L/min
  final _purgeTCtrl= TextEditingController(); // czas purge [min]
  final _bottleCtrl= TextEditingController(text: '50'); // pojemność butli [L gaz]

  double? _totalL;
  double? _bottles;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override void dispose() { for (final c in [_nCtrl, _tCtrl, _torchCtrl, _preCtrl, _postCtrl, _purgeCtrl, _purgeTCtrl, _bottleCtrl]) c.dispose(); super.dispose(); }

  void _calc() {
    setState(() {
      _error = null; _totalL = null; _bottles = null;
      final n  = double.tryParse(_nCtrl.text.replaceAll(',', '.'));
      final t  = double.tryParse(_tCtrl.text.replaceAll(',', '.'));
      final qt = double.tryParse(_torchCtrl.text.replaceAll(',', '.')) ?? 10;
      final pre = double.tryParse(_preCtrl.text.replaceAll(',', '.')) ?? 5;
      final post= double.tryParse(_postCtrl.text.replaceAll(',', '.')) ?? 10;
      final qp = double.tryParse(_purgeCtrl.text.replaceAll(',', '.')) ?? 0;
      final tp = double.tryParse(_purgeTCtrl.text.replaceAll(',', '.')) ?? 0;
      final vB = double.tryParse(_bottleCtrl.text.replaceAll(',', '.')) ?? 50;
      if (n == null || n <= 0) { _error = _tr('Podaj liczbę spoin', 'Enter number of welds'); return; }
      if (t == null || t <= 0) { _error = _tr('Podaj czas spawania na spoinę (min)', 'Enter weld time per joint (min)'); return; }
      // Gas = torch_weld + pre/post + purge
      final torchWeld = n * t * qt; // L
      final prePost   = n * (pre + post) / 60.0 * qt; // L
      final purge     = (qp > 0 && tp > 0) ? n * tp * qp : 0.0; // L
      _totalL = torchWeld + prePost + purge;
      _bottles = _totalL! / vB;
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _InfoBox(_tr(
        'Szacuje całkowite zużycie gazu ochronnego (torch) i purge dla projektu.',
        'Estimates total shielding gas (torch) and purge consumption for a project.',
      )),
      _SecLabel(_tr('Parametry spawania', 'Welding parameters')),
      Row(children: [
        Expanded(child: _NumField(ctrl: _nCtrl, label: _tr('Liczba spoin', 'Number of welds'), hint: '20', onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _tCtrl, label: _tr('Czas na spoinę (min)', 'Time per weld (min)'), hint: '5', unit: 'min', onChanged: _calc)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _NumField(ctrl: _torchCtrl, label: _tr('Torch Q (L/min)', 'Torch Q (L/min)'), hint: '10', unit: 'L/min', onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _preCtrl, label: _tr('Pre-flow (s)', 'Pre-flow (s)'), hint: '5', unit: 's', onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _postCtrl, label: _tr('Post-flow (s)', 'Post-flow (s)'), hint: '10', unit: 's', onChanged: _calc)),
      ]),
      _SecLabel(_tr('Purge (jeśli dotyczy)', 'Purge (if applicable)')),
      Row(children: [
        Expanded(child: _NumField(ctrl: _purgeCtrl, label: _tr('Purge Q (L/min)', 'Purge Q (L/min)'), hint: '10', unit: 'L/min', onChanged: _calc)),
        const SizedBox(width: 10),
        Expanded(child: _NumField(ctrl: _purgeTCtrl, label: _tr('Czas purge (min)', 'Purge time (min)'), hint: '2', unit: 'min', onChanged: _calc)),
      ]),
      _SecLabel(_tr('Butla', 'Cylinder')),
      _NumField(ctrl: _bottleCtrl, label: _tr('Pojemność butli (L gazu, np. Ar50L=50)', 'Cylinder capacity (L gas, e.g. Ar50L=50)'), hint: '50', unit: 'L', onChanged: _calc),
      const SizedBox(height: 14),
      if (_totalL != null) _ResultCard(rows: [
        _RRow(_tr('Łącznie gazu', 'Total gas'), '${_totalL!.toStringAsFixed(0)} L', primary: true),
        const Divider(height: 16, color: _kBorder),
        _RRow(_tr('Liczba butli', 'Number of cylinders'), '${_bottles!.toStringAsFixed(1)} szt.'),
        _RRow(_tr('Zapas (zaokrąglij w górę)', 'Round up for safety'), '${_bottles!.ceil()} szt.', color: _kOrange),
      ]),
      if (_error != null) _ErrBox(_error!),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 5: TIMER SPAWALNICZY
// ══════════════════════════════════════════════════════════════════════════
class _WeldTimerTab extends StatefulWidget {
  @override State<_WeldTimerTab> createState() => _WeldTimerTabState();
}

class _WeldTimerTabState extends State<_WeldTimerTab> {
  final _maxTempCtrl = TextEditingController(text: '150');
  final _coolTimeCtrl = TextEditingController(text: '2');

  Timer? _timer;
  int _elapsed = 0;          // sekundy
  bool _running = false;
  bool _alarm = false;
  String _mode = 'WELD';     // WELD | COOL | PURGE
  int _purgeSec = 0;
  final _purgeInputCtrl = TextEditingController(text: '90');

  @override void dispose() { _timer?.cancel(); _maxTempCtrl.dispose(); _coolTimeCtrl.dispose(); _purgeInputCtrl.dispose(); super.dispose(); }

  void _start() { _timer?.cancel(); setState(() { _running = true; _alarm = false; }); _timer = Timer.periodic(const Duration(seconds: 1), (_) { setState(() { _elapsed++; if (_mode == 'COOL') { final cool = (double.tryParse(_coolTimeCtrl.text) ?? 2) * 60; if (_elapsed >= cool.toInt()) _alarm = true; } if (_mode == 'PURGE') { if (_elapsed >= _purgeSec) _alarm = true; } }); }); }
  void _pause() { _timer?.cancel(); setState(() => _running = false); }
  void _reset() { _timer?.cancel(); setState(() { _elapsed = 0; _running = false; _alarm = false; }); }
  void _setMode(String m) { _reset(); setState(() { _mode = m; if (m == 'PURGE') _purgeSec = int.tryParse(_purgeInputCtrl.text) ?? 90; }); }

  String _fmt(int s) { final m = s ~/ 60; final ss = s % 60; return '${m.toString().padLeft(2,'0')}:${ss.toString().padLeft(2,'0')}'; }

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  Widget build(BuildContext context) {
    final targetSec = _mode == 'COOL'
        ? ((double.tryParse(_coolTimeCtrl.text) ?? 2) * 60).toInt()
        : (_mode == 'PURGE' ? _purgeSec : 0);
    final progress = (targetSec > 0) ? (_elapsed / targetSec).clamp(0.0, 1.0) : 0.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        // Wybór trybu
        Row(children: [
          for (final m in [('WELD', _tr('Spawanie', 'Welding')), ('COOL', _tr('Chłodzenie', 'Cooldown')), ('PURGE', 'Purge')])
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _setMode(m.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _mode == m.$1 ? _kOrange.withOpacity(0.15) : _kCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _mode == m.$1 ? _kOrange : _kBorder, width: _mode == m.$1 ? 1.5 : 1),
                  ),
                  child: Text(m.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _mode == m.$1 ? _kOrange : _kSec)),
                ),
              ),
            )),
        ]),
        const SizedBox(height: 16),

        // Parametry
        if (_mode == 'COOL') ...[
          Row(children: [
            Expanded(child: _NumField(ctrl: _maxTempCtrl, label: _tr('Temp. max. (°C)', 'Max. temp. (°C)'), hint: '150', unit: '°C', onChanged: null)),
            const SizedBox(width: 10),
            Expanded(child: _NumField(ctrl: _coolTimeCtrl, label: _tr('Czas chłodz. (min)', 'Cool time (min)'), hint: '2', unit: 'min', onChanged: null)),
          ]),
          const SizedBox(height: 12),
        ],
        if (_mode == 'PURGE') ...[
          Row(children: [
            Expanded(child: _NumField(ctrl: _purgeInputCtrl, label: _tr('Czas purge (s)', 'Purge time (s)'), hint: '90', unit: 's', onChanged: null)),
            const SizedBox(width: 10),
            ElevatedButton(onPressed: () => setState(() => _purgeSec = int.tryParse(_purgeInputCtrl.text) ?? 90), child: Text(_tr('Ustaw', 'Set'))),
          ]),
          const SizedBox(height: 12),
        ],

        // Wyświetlacz czasu
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _alarm ? _kGreen.withOpacity(0.15) : _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _alarm ? _kGreen : _kBorder, width: _alarm ? 2 : 1),
          ),
          child: Column(children: [
            Text(
              _fmt(_elapsed),
              style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: 2,
                  color: _alarm ? _kGreen : (_running ? _kOrange : _kSec)),
            ),
            if (targetSec > 0) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: _kBorder,
                valueColor: AlwaysStoppedAnimation(_alarm ? _kGreen : _kOrange),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text('${(_elapsed / 60.0).toStringAsFixed(1)} / ${(targetSec / 60.0).toStringAsFixed(1)} min',
                   style: const TextStyle(fontSize: 12, color: _kMuted)),
            ],
            if (_alarm) ...[
              const SizedBox(height: 10),
              Text(_tr('✓ CZAS MINĄŁ', '✓ TIME UP'),
                   style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kGreen)),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // Przyciski
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _running ? _pause : _start,
            icon: Icon(_running ? Icons.pause : Icons.play_arrow),
            label: Text(_running ? _tr('Pauza', 'Pause') : _tr('Start', 'Start')),
          )),
          const SizedBox(width: 10),
          OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.replay), label: Text(_tr('Reset', 'Reset'))),
        ]),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 6: PRZELICZNIK CIŚNIENIA
// ══════════════════════════════════════════════════════════════════════════
class _PressureConverterTab extends StatefulWidget {
  @override State<_PressureConverterTab> createState() => _PressureConverterTabState();
}

class _PressureConverterTabState extends State<_PressureConverterTab> {
  final _valCtrl = TextEditingController();
  String _fromUnit = 'bar';

  final Map<String, double> _toBar = {
    'bar': 1.0, 'MPa': 10.0, 'kPa': 0.01, 'Pa': 0.00001,
    'PSI': 0.0689476, 'atm': 1.01325, 'kgf/cm²': 0.980665,
  };

  Map<String, String>? _results;
  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override void dispose() { _valCtrl.dispose(); super.dispose(); }

  void _calc() {
    setState(() {
      _results = null;
      final v = double.tryParse(_valCtrl.text.replaceAll(',', '.'));
      if (v == null) return;
      final inBar = v * (_toBar[_fromUnit] ?? 1.0);
      _results = {};
      for (final e in _toBar.entries) {
        _results![e.key] = (inBar / e.value).toStringAsFixed(e.key == 'Pa' ? 0 : 4);
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _InfoBox(_tr('Przelicznik jednostek ciśnienia — próby hydrostatyczne, regulatory gazu.', 'Pressure unit converter — hydrostatic tests, gas regulators.')),
      Row(children: [
        Expanded(child: TextField(
          controller: _valCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: _tr('Wartość', 'Value')),
          onChanged: (_) => _calc(),
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(
          value: _fromUnit,
          decoration: InputDecoration(labelText: _tr('Jednostka', 'Unit')),
          items: _toBar.keys.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
          onChanged: (v) { setState(() => _fromUnit = v ?? 'bar'); _calc(); },
        )),
      ]),
      const SizedBox(height: 14),
      if (_results != null) _ResultCard(rows: [
        for (final e in _results!.entries) _RRow(e.key, e.value, primary: e.key == _fromUnit),
      ]),
    ],
  );
}
