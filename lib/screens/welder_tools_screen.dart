// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';

import '../domain/welding/purge.dart';
import '../domain/welding/shielding_gas.dart';
import '../i18n/app_language.dart';
import '../services/weld_timer_service.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

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
    parseDecimal(c.text);

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
  /// False for whole-number fields (seconds read with int.tryParse).
  final bool decimal;
  const _NumField({required this.ctrl, required this.label, this.hint, this.unit, this.helper, this.onChanged, this.decimal = true});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: numberKeyboard(decimal: decimal),
    inputFormatters: numberInputFormatters(decimal: decimal),
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
      // Progi to przykłady z praktyki, nie normy — akceptację barwy / O₂
      // ustala specyfikacja projektu albo WPS.
      if (target <= 20)  { _assessment = _tr('Cel ≤ 20 ppm — przykładowo instalacje farmaceutyczne; wiąże specyfikacja / WPS', 'Target ≤ 20 ppm — e.g. pharma systems; the specification / WPS is binding'); _assessColor = _kGreen; }
      else if (target <= 100) { _assessment = _tr('Cel ≤ 100 ppm — przykładowo instalacje przemysłowe; wiąże specyfikacja / WPS', 'Target ≤ 100 ppm — e.g. industrial systems; the specification / WPS is binding'); _assessColor = _kOrange; }
      else { _assessment = _tr('Cel > 100 ppm — ryzyko przebarwień; sprawdź wymaganie specyfikacji', 'Target > 100 ppm — risk of discolouration; check the specification'); _assessColor = _kRed; }
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
        'Przykładowe cele: pharma < 20 ppm O₂, przemysł < 100 ppm O₂ — '
        'to nie progi normy; wiąże specyfikacja projektu / WPS.',
        'Exponential model: C(t) = C₀ × e^(−Q×t/V)\n'
        'Example targets: pharma < 20 ppm O₂, industry < 100 ppm O₂ — '
        'not code limits; the project specification / WPS is binding.',
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
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () => startPurgeCountdown(context,
                Duration(milliseconds: (_estimate!.timeSec * 1000).round())),
            icon: const Icon(Icons.timer_outlined),
            label: Text(_tr('Start timera purge (${_fmtTime(_estimate!.timeSec)})',
                'Start purge timer (${_fmtTime(_estimate!.timeSec)})')),
          ),
        ),
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
// Stan i odliczanie żyją w WeldTimerService (lib/services/weld_timer_service.dart):
// timer liczy dalej po zmianie zakładki i wyjściu z ekranu, a koniec
// odliczania alarmuje wibracją, dźwiękiem i pełnoekranowym komunikatem
// (WeldTimerAlarmOverlay w app.dart). Zakładka tylko wyświetla i steruje.
// Przyciski ≥ 64 dp — obsługa w rękawicach.

/// Minimalna wysokość przycisków timera (rękawice spawalnicze).
const double kWeldTimerButtonHeight = 72;

/// „Przerwać odliczanie?” — przed każdą akcją, która skasowałaby biegnący
/// albo zapauzowany timer (zmiana trybu, start purge z innego ekranu).
/// `true` = przerwać.
Future<bool> confirmWeldTimerInterrupt(
    BuildContext context, WeldTimerService timer) async {
  final modeName = switch (timer.mode) {
    WeldTimerMode.weld => context.tr(pl: 'stoper spawania', en: 'the welding stopwatch'),
    WeldTimerMode.cool => context.tr(pl: 'odliczanie chłodzenia', en: 'the cooldown countdown'),
    WeldTimerMode.purge => context.tr(pl: 'odliczanie purge', en: 'the purge countdown'),
  };
  final left = timer.remaining ?? timer.elapsed;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr(pl: 'Przerwać odliczanie?', en: 'Stop the countdown?')),
      content: Text(ctx.tr(
        pl: 'Biegnie $modeName (${_fmtClock(left)}). Zmiana skasuje ten czas.',
        en: '$modeName is running (${_fmtClock(left)}). Changing it clears that time.',
      )),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 56)),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr(pl: 'Nie, zostaw', en: 'No, keep it')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr(pl: 'Przerwij', en: 'Stop it')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Start odliczania purge przez [WeldTimerService] (alarm, tło, pełny
/// ekran) — z potwierdzeniem, gdy biegnie inne odliczanie.
Future<bool> startPurgeCountdown(BuildContext context, Duration duration,
    {WeldTimerService? service}) async {
  final timer = service ?? WeldTimerService.instance;
  if (timer.hasProgress && !await confirmWeldTimerInterrupt(context, timer)) {
    return false;
  }
  timer.startPurge(duration);
  if (!context.mounted) return true;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(context.tr(
        pl: 'Odliczanie purge ${_fmtClock(Duration(seconds: timer.purgeSeconds))} — '
            'alarm jak w zakładce Timer (Spawacz → Gaz, formowanie i timer).',
        en: 'Purge countdown ${_fmtClock(Duration(seconds: timer.purgeSeconds))} — '
            'alarm as in the Timer tab (Welder → Gas, purge and timer).',
      )),
    ));
  return true;
}

String _fmtClock(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String _fmtPlain(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

class _WeldTimerTab extends StatefulWidget {
  @override State<_WeldTimerTab> createState() => _WeldTimerTabState();
}

class _WeldTimerTabState extends State<_WeldTimerTab> {
  final WeldTimerService _timer = WeldTimerService.instance;

  // Pola startują z wartości serwisu — po powrocie na zakładkę widać to,
  // co spawacz ustawił wcześniej.
  late final _maxTempCtrl = TextEditingController(
      text: _timer.maxInterpassC == null ? '' : _fmtPlain(_timer.maxInterpassC!));
  late final _coolTimeCtrl = TextEditingController(
      text: _fmtPlain(_timer.coolTime.inMilliseconds / 60000));
  late final _purgeInputCtrl =
      TextEditingController(text: _timer.purgeSeconds.toString());

  @override
  void dispose() {
    // Timer NIE jest zatrzymywany — to serwis, liczy dalej.
    _maxTempCtrl.dispose();
    _coolTimeCtrl.dispose();
    _purgeInputCtrl.dispose();
    super.dispose();
  }

  void _applyMaxTemp() => _timer.setMaxInterpass(_num(_maxTempCtrl));

  void _applyCoolTime() {
    final min = _num(_coolTimeCtrl);
    if (min == null) return;
    _timer.setCoolTime(Duration(milliseconds: (min.clamp(0, 600) * 60000).round()));
  }

  void _applyPurge() {
    final s = int.tryParse(_purgeInputCtrl.text.trim());
    if (s != null) _timer.setPurgeSeconds(s);
  }

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _timer,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final mode = _timer.mode;
    final running = _timer.running;
    final finished = _timer.finished;
    final target = _timer.target;
    final elapsed = _timer.elapsed;
    final remaining = _timer.remaining;
    final progress = (target != null && target.inMilliseconds > 0)
        ? (elapsed.inMilliseconds / target.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final alarmText = weldTimerAlarmText(_timer.currentAlarm,
        english: context.language == AppLanguage.en);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        // Wybór trybu
        Row(children: [
          for (final m in [
            (WeldTimerMode.weld, _tr('Spawanie', 'Welding')),
            (WeldTimerMode.cool, _tr('Chłodzenie', 'Cooldown')),
            (WeldTimerMode.purge, 'Purge'),
          ])
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ModeButton(
                label: m.$2,
                selected: mode == m.$1,
                onTap: () async {
                  if (m.$1 == _timer.mode) return;
                  // Zmiana trybu kasuje biegnące / zapauzowane odliczanie —
                  // najpierw pytamy (przycisk trybu jest tuż nad zegarem).
                  if (_timer.hasProgress &&
                      !await confirmWeldTimerInterrupt(context, _timer)) {
                    return;
                  }
                  if (m.$1 == WeldTimerMode.purge) _applyPurge();
                  if (m.$1 == WeldTimerMode.cool) { _applyCoolTime(); _applyMaxTemp(); }
                  _timer.setMode(m.$1);
                },
              ),
            )),
        ]),
        const SizedBox(height: 16),

        // Parametry
        if (mode == WeldTimerMode.cool) ...[
          Row(children: [
            Expanded(child: _NumField(ctrl: _maxTempCtrl, label: _tr('Maks. temp. międzyściegowa z WPS (°C)', 'Max. interpass temp. from WPS (°C)'), hint: '150', unit: '°C', onChanged: _applyMaxTemp)),
            const SizedBox(width: 10),
            Expanded(child: _NumField(ctrl: _coolTimeCtrl, label: _tr('Czas chłodz. (min)', 'Cool time (min)'), hint: '2', unit: 'min', onChanged: _applyCoolTime)),
          ]),
          const SizedBox(height: 12),
        ],
        if (mode == WeldTimerMode.purge) ...[
          _NumField(ctrl: _purgeInputCtrl, label: _tr('Czas purge (s)', 'Purge time (s)'), hint: '90', unit: 's', onChanged: _applyPurge, decimal: false),
          const SizedBox(height: 12),
        ],

        // Wyświetlacz czasu: odliczanie pokazuje, ile ZOSTAŁO; stoper — ile minęło.
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: finished ? _kGreen.withValues(alpha: 0.15) : _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: finished ? _kGreen : _kBorder, width: finished ? 2 : 1),
          ),
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _fmtClock(remaining ?? elapsed),
                key: const ValueKey('weld-timer-display'),
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: finished ? _kGreen : (running ? _kOrange : _kSec)),
              ),
            ),
            if (target != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: _kBorder,
                valueColor: AlwaysStoppedAnimation(finished ? _kGreen : _kOrange),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text('${_tr('minęło', 'elapsed')} ${_fmtClock(elapsed)} / ${_fmtClock(target)}',
                   style: const TextStyle(fontSize: 13, color: _kMuted)),
            ],
            if (finished) ...[
              const SizedBox(height: 10),
              Text(_tr('✓ CZAS MINĄŁ', '✓ TIME UP'),
                   style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kGreen)),
              const SizedBox(height: 6),
              Text(
                alarmText.body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _kSec, fontWeight: FontWeight.w600),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // Przyciski — duże, pod rękawice.
        Row(children: [
          Expanded(child: SizedBox(
            height: kWeldTimerButtonHeight,
            child: ElevatedButton.icon(
              onPressed: running ? _timer.pause : _timer.start,
              icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 32),
              label: Text(
                running
                    ? _tr('Pauza', 'Pause')
                    : (finished ? _tr('Jeszcze raz', 'Again') : _tr('Start', 'Start')),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          )),
          const SizedBox(width: 10),
          SizedBox(
            height: kWeldTimerButtonHeight,
            child: OutlinedButton.icon(
              onPressed: _timer.reset,
              icon: const Icon(Icons.replay, size: 28),
              label: Text(_tr('Reset', 'Reset'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
        if (target != null) ...[
          const SizedBox(height: 8),
          _NoteText(_tr(
            'Timer liczy dalej po zmianie zakładki i wyjściu z ekranu. Na koniec: wibracja, dźwięk i komunikat na cały ekran; ekran nie gaśnie w trakcie odliczania. W tle — powiadomienie (jeśli na nie pozwolisz).',
            'The timer keeps running when you switch tabs or leave the screen. At the end: vibration, sound and a full-screen message; the screen stays on while counting down. In the background — a notification (if you allow it).',
          )),
        ],
        const _Disclaimer(),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? _kOrange.withValues(alpha: 0.15) : _kCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _kOrange : _kBorder, width: selected ? 2 : 1),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: selected ? _kOrange : _kSec)),
        ),
      ),
    ),
  );
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
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
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
