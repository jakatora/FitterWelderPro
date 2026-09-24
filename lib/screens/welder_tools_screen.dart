// ignore_for_file: prefer_const_constructors
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/welding/purge.dart';
import '../domain/welding/shielding_gas.dart';
import '../i18n/app_language.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

// All arithmetic of these calculators lives in lib/domain/welding/ — this
// screen only parses the fields and renders the results.
//
// Heat input i podgrzewanie (CE / Seferian) mają jeden ekran: HeatInputScreen
// („Heat input i CE”). Zakładki tego ekranu kiedyś je dublowały — zostały tu
// tylko gaz, formowanie, timer i ciśnienie.

// ── Kolory ────────────────────────────────────────────────────────────────
const _kOrange = Color(0xFFFF8E1E);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)
const _kSec    = Color(0xFF9BA3C7);

double? _num(TextEditingController c) =>
    double.tryParse(c.text.trim().replaceAll(',', '.'));

class WelderToolsScreen extends StatelessWidget {
  /// Zakładka otwierana na starcie (jak `FitterToolsScreen(initialTab:)`).
  final int initialTab;
  const WelderToolsScreen({super.key, this.initialTab = tabGas});

  static const int tabGas = 0;
  static const int tabPurge = 1;
  static const int tabTimer = 2;
  static const int tabPressure = 3;
  static const int tabCount = 4;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabCount,
      initialIndex: initialTab.clamp(0, tabCount - 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(pl: 'Gaz, formowanie i timer', en: 'Gas, purge and timer')),
          actions: [HelpButton(help: kHelpWelderTools)],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.tr(pl: 'Gaz', en: 'Gas')),
              Tab(text: 'O₂ Purge'),
              Tab(text: 'Timer'),
              Tab(text: context.tr(pl: 'Ciśnienie', en: 'Pressure')),
            ],
          ),
        ),
        body: TabBarView(children: [
          _GasConsumptionTab(),
          _O2PurgeTab(),
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
    decoration: InputDecoration(labelText: label, hintText: hint, suffixText: unit, helperText: helper, helperMaxLines: 3),
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
      gradient: LinearGradient(colors: [_kOrange.withValues(alpha: 0.10), _kOrange.withValues(alpha: 0.03)]),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _kOrange.withValues(alpha: 0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
  );
}

class _RRow extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;
  final Color? color;
  const _RRow(this.label, this.value, {this.primary = false, this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: _kSec))),
        // Long-press the numeric value to copy it (gloves + small keys → no retyping).
        CopyOnLongPress(
          value: value,
          label: label.isEmpty ? null : label,
          child: Text(value, style: TextStyle(
            fontSize: primary ? 22 : 14,
            fontWeight: primary ? FontWeight.w800 : FontWeight.w600,
            color: color ?? (primary ? _kOrange : const Color(0xFFE7ECF3)),
            letterSpacing: primary ? -0.4 : 0,
          )),
        ),
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
    decoration: BoxDecoration(color: _kRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kRed.withValues(alpha: 0.3))),
    child: Text(t, style: TextStyle(fontSize: 12, color: _kRed.withValues(alpha: 0.9))),
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
      color: _kBlue.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
    ),
    child: Text(t, style: const TextStyle(fontSize: 12, color: _kSec, height: 1.5)),
  );
}

class _NoteText extends StatelessWidget {
  final String t;
  const _NoteText(this.t);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(t, style: const TextStyle(fontSize: 11, color: _kSec, height: 1.4)),
  );
}

/// One-line reminder under every calculator: the result is an aid, the WPS
/// and project specification are binding. Small and at the bottom so it
/// never covers the number itself.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.gavel_outlined, size: 13, color: _kMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.tr(
              pl: 'Wynik pomocniczy — wiąże WPS / specyfikacja projektu.',
              en: 'Auxiliary result — the WPS / project specification is binding.',
            ),
            style: const TextStyle(fontSize: 11, color: _kMuted, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    ),
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

// ═══════════════════════════════════════════════════════════════════════════
// ZAKŁADKA: O₂ PURGE (model wykładniczy, ppm)
// ═══════════════════════════════════════════════════════════════════════════
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

  PurgeEstimate? _estimate;
  double? _target;
  String? _assessment;
  Color? _assessColor;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_odCtrl, _tCtrl, _lCtrl, _qCtrl, _c0Ctrl, _targetCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null; _estimate = null; _target = null; _assessment = null;
      final od = _num(_odCtrl);
      final t  = _num(_tCtrl);
      final l  = _num(_lCtrl);
      final q  = _num(_qCtrl);
      final c0 = _num(_c0Ctrl) ?? 210000;
      final target = _num(_targetCtrl) ?? 20;
      if (od == null || od <= 0 || t == null || t <= 0) { _error = _tr('Podaj OD i grubość ścianki', 'Enter OD and wall thickness'); return; }
      if (l == null || l <= 0) { _error = _tr('Podaj długość odcinka (mm)', 'Enter section length (mm)'); return; }
      if (q == null || q <= 0) { _error = _tr('Podaj przepływ gazu Q (L/min)', 'Enter gas flow Q (L/min)'); return; }
      final r = estimatePurge(
        odMm: od, wallMm: t, lengthMm: l, flowLpm: q,
        initialPpm: c0, targetPpm: target,
      );
      switch (r.error) {
        case PurgeInputError.geometry:
          _error = _tr('OD mniejszy niż 2×t', 'OD smaller than 2×t'); return;
        case PurgeInputError.flow:
          _error = _tr('Podaj przepływ gazu Q (L/min)', 'Enter gas flow Q (L/min)'); return;
        case PurgeInputError.initialConcentration:
          _error = _tr('Stężenie startowe musi być > 0 ppm', 'Initial concentration must be > 0 ppm'); return;
        case PurgeInputError.target:
          _error = _tr('Cel musi być > 0 ppm — model wykładniczy nigdy nie osiąga zera',
                       'Target must be > 0 ppm — the exponential model never reaches zero'); return;
        case PurgeInputError.targetNotBelowInitial:
          _error = _tr('Cel musi być niższy od stężenia startowego',
                       'Target must be lower than the initial concentration'); return;
        case null:
          break;
      }
      _estimate = r.estimate;
      _target = target;
      if (target <= 20)  { _assessment = _tr('Cel < 20 ppm (standard pharma)', 'Target < 20 ppm (pharma grade)'); _assessColor = _kGreen; }
      else if (target <= 100) { _assessment = _tr('Cel < 100 ppm (standard przemysłowy)', 'Target < 100 ppm (industrial grade)'); _assessColor = _kOrange; }
      else { _assessment = _tr('Cel > 100 ppm — ryzyko przebarwień', 'Target > 100 ppm — risk of discolouration'); _assessColor = _kRed; }
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
      if (_estimate != null) _ResultCard(rows: [
        _RRow(_tr('Objętość odcinka', 'Section volume'), '${_estimate!.volumeL.toStringAsFixed(3)} L'),
        _RRow(_tr('Czas purge', 'Purge time'), _fmtTime(_estimate!.timeSec), primary: true),
        _RRow(_tr('Wymian objętości', 'Volume changes'), _estimate!.volumeChanges.toStringAsFixed(1)),
        _RRow(_tr('Gaz na purge', 'Purge gas'), '${(_num(_qCtrl)! * _estimate!.timeSec / 60).toStringAsFixed(1)} L'),
        const Divider(height: 16, color: _kBorder),
        _RRow(_tr('Cel', 'Target'), '${_target!.toStringAsFixed(_target! < 10 ? 1 : 0)} ppm O₂'),
        if (_assessment != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _assessColor)),
            const SizedBox(width: 8),
            Expanded(child: Text(_assessment!, style: TextStyle(fontSize: 12, color: _assessColor, fontWeight: FontWeight.w600))),
          ]),
        ],
        _NoteText(_tr(
          'Czas orientacyjny (model pełnego wymieszania) — zweryfikuj analizatorem O₂ przed spawaniem.',
          'Estimated time (perfect-mixing model) — verify with an O₂ analyser before welding.',
        )),
      ]),
      if (_error != null) _ErrBox(_error!),
      const _Disclaimer(),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ZAKŁADKA: ZUŻYCIE GAZU
// ═══════════════════════════════════════════════════════════════════════════
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
  // Cylinder: WATER capacity [L] + fill pressure [bar] (+ optional residual
  // reserve). "50 L" on a cylinder is its water volume, not 50 L of gas —
  // 50 L × 200 bar ≈ 10 000 L of argon (audit 2026-09: was ~200× off).
  final _waterCtrl = TextEditingController(text: '50');
  final _pressureCtrl = TextEditingController(text: '200');
  final _reserveCtrl = TextEditingController();

  double? _totalL;
  double? _gasPerCylinderL;
  double? _bottles;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_nCtrl, _tCtrl, _torchCtrl, _preCtrl, _postCtrl, _purgeCtrl, _purgeTCtrl, _waterCtrl, _pressureCtrl, _reserveCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null; _totalL = null; _bottles = null; _gasPerCylinderL = null;
      final n  = _num(_nCtrl);
      final t  = _num(_tCtrl);
      if (n == null || n <= 0) { _error = _tr('Podaj liczbę spoin', 'Enter number of welds'); return; }
      if (t == null || t <= 0) { _error = _tr('Podaj czas spawania na spoinę (min)', 'Enter weld time per joint (min)'); return; }
      final g = estimateGasConsumption(
        welds: n,
        weldMinutes: t,
        torchLpm: _num(_torchCtrl) ?? 10,
        preFlowS: _num(_preCtrl) ?? 5,
        postFlowS: _num(_postCtrl) ?? 10,
        purgeLpm: _num(_purgeCtrl) ?? 0,
        purgeMinutes: _num(_purgeTCtrl) ?? 0,
      );
      if (g == null) { _error = _tr('Sprawdź przepływy i czasy (> 0)', 'Check flows and times (> 0)'); return; }
      _totalL = g.totalL;
      final perCylinder = usableCylinderGasL(
        waterCapacityL: _num(_waterCtrl) ?? 50,
        fillPressureBar: _num(_pressureCtrl) ?? 200,
        reserveBar: _num(_reserveCtrl) ?? 0,
      );
      if (perCylinder == null) {
        _error = _tr('Sprawdź butlę: pojemność > 0, rezerwa < ciśnienia napełnienia',
                     'Check the cylinder: capacity > 0, reserve below fill pressure');
        return;
      }
      _gasPerCylinderL = perCylinder;
      _bottles = cylindersNeeded(totalGasL: g.totalL, usableGasPerCylinderL: perCylinder);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pcs = _tr('szt.', 'pcs');
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _InfoBox(_tr(
          'Szacuje całkowite zużycie gazu ochronnego (palnik) i formującego (purge) dla projektu '
          'oraz liczbę butli: gaz w butli ≈ pojemność wodna × (ciśnienie − rezerwa).',
          'Estimates total shielding (torch) and purge gas for a project and the number of cylinders: '
          'gas in a cylinder ≈ water capacity × (pressure − reserve).',
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
        Row(children: [
          Expanded(child: _NumField(ctrl: _waterCtrl, label: _tr('Pojemność wodna butli', 'Cylinder water capacity'), hint: '50', unit: 'L', onChanged: _calc)),
          const SizedBox(width: 10),
          Expanded(child: _NumField(ctrl: _pressureCtrl, label: _tr('Ciśnienie napełnienia', 'Fill pressure'), hint: '200', unit: 'bar', onChanged: _calc)),
        ]),
        const SizedBox(height: 10),
        _NumField(
          ctrl: _reserveCtrl,
          label: _tr('Rezerwa resztkowa', 'Residual reserve'),
          hint: '0',
          unit: 'bar',
          helper: _tr('Opcjonalnie, np. 10 bar — butli nie opróżnia się do zera.',
                      'Optional, e.g. 10 bar — cylinders are not emptied to zero.'),
          onChanged: _calc,
        ),
        const SizedBox(height: 14),
        if (_totalL != null && _bottles != null) _ResultCard(rows: [
          _RRow(_tr('Łącznie gazu', 'Total gas'), '${_totalL!.toStringAsFixed(0)} L', primary: true),
          const Divider(height: 16, color: _kBorder),
          _RRow(_tr('Gaz w 1 butli ≈ V × (p − p_rez)', 'Gas per cylinder ≈ V × (p − p_res)'), '${_gasPerCylinderL!.toStringAsFixed(0)} L'),
          _RRow(_tr('Liczba butli', 'Number of cylinders'), '${_bottles!.toStringAsFixed(2)} $pcs'),
          _RRow(_tr('Do zamówienia (zaokrąglone w górę)', 'To order (rounded up)'), '${_bottles!.ceil()} $pcs', color: _kOrange),
          _NoteText(_tr(
            'Przybliżenie gazu doskonałego. Dostawcy podają dla argonu 50 L / 200 bar ok. 10,7 m³ — '
            'wynik jest więc lekko zachowawczy.',
            'Ideal-gas approximation. Suppliers list about 10.7 m³ for argon 50 L / 200 bar — '
            'so the result is slightly conservative.',
          )),
        ]),
        if (_error != null) _ErrBox(_error!),
        const _Disclaimer(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ZAKŁADKA: TIMER SPAWALNICZY
// ═══════════════════════════════════════════════════════════════════════════
class _WeldTimerTab extends StatefulWidget {
  @override State<_WeldTimerTab> createState() => _WeldTimerTabState();
}

class _WeldTimerTabState extends State<_WeldTimerTab> {
  // Max interpass temperature from the WPS — not calculated, used as the
  // reminder shown when the cooldown time is up ("measure; weld on only at
  // ≤ X °C").
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

  int get _coolSec => (((_num(_coolTimeCtrl) ?? 2).clamp(0, 600)) * 60).toInt();

  void _start() { _timer?.cancel(); setState(() { _running = true; _alarm = false; }); _timer = Timer.periodic(const Duration(seconds: 1), (_) { setState(() { _elapsed++; if (_mode == 'COOL') { if (_elapsed >= _coolSec) _alarm = true; } if (_mode == 'PURGE') { if (_elapsed >= _purgeSec) _alarm = true; } }); }); }
  void _pause() { _timer?.cancel(); setState(() => _running = false); }
  void _reset() { _timer?.cancel(); setState(() { _elapsed = 0; _running = false; _alarm = false; }); }
  void _setMode(String m) { _reset(); setState(() { _mode = m; if (m == 'PURGE') _purgeSec = int.tryParse(_purgeInputCtrl.text) ?? 90; }); }

  String _fmt(int s) { final m = s ~/ 60; final ss = s % 60; return '${m.toString().padLeft(2,'0')}:${ss.toString().padLeft(2,'0')}'; }

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  Widget build(BuildContext context) {
    final targetSec = _mode == 'COOL'
        ? _coolSec
        : (_mode == 'PURGE' ? _purgeSec : 0);
    final progress = (targetSec > 0) ? (_elapsed / targetSec).clamp(0.0, 1.0) : 0.0;
    final maxTemp = _num(_maxTempCtrl);

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
                    color: _mode == m.$1 ? _kOrange.withValues(alpha: 0.15) : _kCard,
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
            Expanded(child: _NumField(ctrl: _maxTempCtrl, label: _tr('Maks. temp. międzyściegowa z WPS (°C)', 'Max. interpass temp. from WPS (°C)'), hint: '150', unit: '°C', onChanged: () => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(child: _NumField(ctrl: _coolTimeCtrl, label: _tr('Czas chłodz. (min)', 'Cool time (min)'), hint: '2', unit: 'min', onChanged: () => setState(() {}))),
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
            color: _alarm ? _kGreen.withValues(alpha: 0.15) : _kCard,
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
              if (_mode == 'COOL' && maxTemp != null && maxTemp > 0) ...[
                const SizedBox(height: 6),
                Text(
                  _tr('Zmierz temperaturę pirometrem — kolejny ścieg dopiero przy ≤ ${maxTemp.toStringAsFixed(0)} °C (WPS).',
                      'Measure the temperature — next pass only at ≤ ${maxTemp.toStringAsFixed(0)} °C (WPS).'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: _kSec, fontWeight: FontWeight.w600),
                ),
              ],
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
        const _Disclaimer(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ZAKŁADKA: PRZELICZNIK CIŚNIENIA
// ═══════════════════════════════════════════════════════════════════════════
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
      final v = _num(_valCtrl);
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
          initialValue: _fromUnit,
          decoration: InputDecoration(labelText: _tr('Jednostka', 'Unit')),
          items: _toBar.keys.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
          onChanged: (v) { setState(() => _fromUnit = v ?? 'bar'); _calc(); },
        )),
      ]),
      const SizedBox(height: 14),
      if (_results != null) _ResultCard(rows: [
        for (final e in _results!.entries) _RRow(e.key, e.value, primary: e.key == _fromUnit),
      ]),
      const _Disclaimer(),
    ],
  );
}
