import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';

// P1-14: lokalna definicja pomocy dla ekranu hydrotest
// (kHelpHydrotest nie istnieje w help_button.dart — dodajemy lokalnie,
// żeby nie ruszać współdzielonego pliku z tej zmiany).
final kHelpHydrotest = ScreenHelp(
  titlePl: 'Próba ciśnieniowa',
  titleEn: 'Hydrostatic test',
  bodyPl:
      'Kalkulator próby ciśnieniowej hydrostatycznej (hydrotest). Liczy ciśnienie '
      'testowe = współczynnik × ciśnienie projektowe (1.5× wg ASME B31.3 § 345.4.2), '
      'objętość wody do napełnienia linii oraz szacowany czas napełniania przy '
      'zadanej wydajności pompy. Minimalny czas próby: 10 min.',
  bodyEn:
      'Hydrostatic pressure-test calculator. Computes test pressure = factor × '
      'design pressure (1.5× per ASME B31.3 § 345.4.2), the water volume needed '
      'to fill the line and the estimated fill time at the given pump flow. '
      'Minimum hold time: 10 min.',
  stepsPl: [
    HelpStep('📏', 'Wpisz OD, ściankę i długość linii (mm / m).'),
    HelpStep('🧮', 'Podaj ciśnienie projektowe i wybierz współczynnik (1.5 / 1.3 / 1.43).'),
    HelpStep('💧', 'Wpisz wydajność pompy (L/min) — policzy czas napełniania.'),
    HelpStep('⚠️', 'Strefę testu oznakuj i wygrodź — procedurę pisze inżynier QC.'),
  ],
  stepsEn: [
    HelpStep('📏', 'Enter OD, wall and line length (mm / m).'),
    HelpStep('🧮', 'Enter design pressure and pick a factor (1.5 / 1.3 / 1.43).'),
    HelpStep('💧', 'Enter pump flow (L/min) — fill time will be calculated.'),
    HelpStep('⚠️', 'Mark and cordon off the test area — QC engineer writes the procedure.'),
  ],
);

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

  // P1-04: reset całego ekranu — wszystkie pola + współczynnik do domyślnego 1.5×.
  void _resetAll() {
    Haptic.tap();
    _odCtrl.clear();
    _wallCtrl.clear();
    _lengthCtrl.clear();
    _designCtrl.clear();
    _flowCtrl.text = '40';
    setState(() => _factor = 1.5);
    FocusScope.of(context).unfocus();
    debugPrint('[hydrotest] reset all controllers');
  }

  // P1-30: granice sensowności wejścia — twarde górne kapy zatrzymują
  // wartości nieosiągalne fizycznie zanim trafią do toStringAsFixed.
  static const double _kMaxOdMm     = 5000;     // 5 m — większe rury to nie hydrotest ręczny
  static const double _kMaxWallMm   = 200;      // 200 mm ścianka — koniec realnego zakresu
  static const double _kMaxLengthM  = 100000;   // 100 km — sanity, nie produkcja
  static const double _kMaxDesignBar = 2000;    // 2000 bar — okolice ASME B31.3 max
  static const double _kMaxFlowLpm   = 10000;   // 10 000 L/min — sanity dla pompy

  // P1-30: zwraca komunikat błędu per-pole albo null, gdy ok / puste.
  String? _odError(double? v) {
    if (_odCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v <= 0) return _tr('OD musi być > 0', 'OD must be > 0');
    if (v > _kMaxOdMm) return _tr('Sprawdź wymiar', 'Check value');
    return null;
  }

  String? _wallError(double? v, double? od) {
    if (_wallCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v <= 0) return _tr('Ścianka musi być > 0', 'Wall must be > 0');
    if (v > _kMaxWallMm) return _tr('Sprawdź wymiar', 'Check value');
    if (od != null && od > 0 && v * 2 >= od) {
      return _tr('Ścianka ≥ ½ OD', 'Wall ≥ ½ OD');
    }
    return null;
  }

  String? _lengthError(double? v) {
    if (_lengthCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v <= 0) return _tr('Długość musi być > 0', 'Length must be > 0');
    if (v > _kMaxLengthM) return _tr('Sprawdź długość', 'Check length');
    return null;
  }

  String? _designError(double? v) {
    if (_designCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v <= 0) return _tr('Ciśnienie musi być > 0', 'Pressure must be > 0');
    if (v > _kMaxDesignBar) return _tr('Sprawdź ciśnienie', 'Check pressure');
    return null;
  }

  String? _flowError(double? v) {
    if (_flowCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v < 0) return _tr('Wydajność ≥ 0', 'Flow ≥ 0');
    if (v > _kMaxFlowLpm) return _tr('Sprawdź wydajność', 'Check flow');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final od = _p(_odCtrl);
    final wall = _p(_wallCtrl);
    final lengthM = _p(_lengthCtrl);
    final design = _p(_designCtrl);
    final flowLpm = _p(_flowCtrl) ?? 0;

    // P1-30: zsyp do per-field errorText.
    final odErr     = _odError(od);
    final wallErr   = _wallError(wall, od);
    final lengthErr = _lengthError(lengthM);
    final designErr = _designError(design);
    final flowErr   = _flowError(_p(_flowCtrl));

    String? error;
    double? id, volL, testPressure, fillMin;
    // Obliczenia tylko gdy wartości są sensowne (per-field errors wyczyszczone).
    if (od != null && wall != null && odErr == null && wallErr == null) {
      id = od - 2 * wall;
      if (lengthM != null && lengthM > 0 && lengthErr == null) {
        // Volume = π · ID²/4 · L (mm³) → litres
        volL = math.pi * id * id / 4.0 * (lengthM * 1000) * 1e-6;
        if (flowLpm > 0 && flowErr == null) fillMin = volL / flowLpm;
      }
    } else if (od != null && wall != null) {
      // Trzymamy stary tekst sanity banneru dla wstecznej kompatybilności,
      // ale per-field errorText pokaże szczegół przy konkretnym wejściu.
      if (od <= 0 || wall <= 0) {
        error = _tr('OD i ścianka muszą być > 0.',
            'OD and wall must be > 0.');
      } else if (wall * 2 >= od) {
        error = _tr('Ścianka ≥ ½ OD — sprawdź wymiary.',
            'Wall ≥ ½ OD — check the values.');
      }
    }
    if (design != null && design > 0 && designErr == null) {
      testPressure = design * _factor;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Próba ciśnieniowa', 'Hydrostatic test')),
        actions: [
          // P1-04: globalny reset (Wyczyść) — ikona refresh, 48dp tap target.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: _tr('Wyczyść', 'Clear'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _resetAll,
          ),
          // P1-26: Share / Kopiuj — jednolinijkowy trace do schowka.
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: _tr('Udostępnij wynik', 'Share result'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: (volL == null && testPressure == null)
                ? null
                : () => _shareOneLineTrace(
                    od: od, wall: wall, id: id, lengthM: lengthM,
                    design: design, factor: _factor,
                    testPressure: testPressure, volL: volL,
                    flowLpm: flowLpm, fillMin: fillMin),
          ),
          // Pełen raport (multi-line) — zachowane dla zgodności z istniejącym UX.
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _tr('Kopiuj raport', 'Copy report'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: (volL == null && testPressure == null)
                ? null
                : () => _copyReport(
                    od: od, wall: wall, id: id, lengthM: lengthM,
                    design: design, factor: _factor,
                    testPressure: testPressure, volL: volL,
                    flowLpm: flowLpm, fillMin: fillMin),
          ),
          // P1-14: HelpButton (kHelpHydrotest) zdefiniowany lokalnie powyżej.
          HelpButton(help: kHelpHydrotest),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          // ── P1-15: BHP / min. czas próby — przypięte ZAWSZE NAD wejściami ──
          _SafetyHoldBanner(
            text: _tr(
              'BHP: woda pod ciśnieniem ma dużą energię. Strefę testu '
              'oznakuj i wygrodź, ludzie poza strefą, zawory '
              'odpowietrzające na najwyższych punktach, manometr '
              'kalibrowany. Procedurę pisze inżynier QC. Minimalny czas '
              'próby: 10 min (ASME B31.3 § 345.4.2).',
              'SAFETY: pressurised water carries significant energy. '
              'Mark and cordon off the test area, keep people out, fit '
              'vents at high points, use a calibrated gauge. The QC '
              'engineer writes the procedure. Minimum hold time: 10 min '
              '(ASME B31.3 § 345.4.2).',
            ),
          ),
          const SizedBox(height: 14),

          // ── Geometry ──
          _SectionHeader(_tr('GEOMETRIA RURY', 'PIPE GEOMETRY')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NumField(
              ctrl: _odCtrl, label: _tr('OD (mm)', 'OD (mm)'),
              hint: '60.3', onChanged: () => setState(() {}),
              errorText: odErr,
              textInputAction: TextInputAction.next)),
            const SizedBox(width: 10),
            Expanded(child: _NumField(
              ctrl: _wallCtrl, label: _tr('Ścianka t (mm)', 'Wall t (mm)'),
              hint: '3.91', onChanged: () => setState(() {}),
              errorText: wallErr,
              textInputAction: TextInputAction.next)),
          ]),
          const SizedBox(height: 10),
          _NumField(
            ctrl: _lengthCtrl,
            label: _tr('Długość linii (m)', 'Line length (m)'),
            hint: '120',
            onChanged: () => setState(() {}),
            errorText: lengthErr,
            textInputAction: TextInputAction.next,
          ),

          const SizedBox(height: 14),
          _SectionHeader(_tr('CIŚNIENIE', 'PRESSURE')),
          const SizedBox(height: 8),
          _NumField(
            ctrl: _designCtrl,
            label: _tr('Ciśnienie projektowe (bar)', 'Design pressure (bar)'),
            hint: '10',
            onChanged: () => setState(() {}),
            errorText: designErr,
            textInputAction: TextInputAction.next,
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
            label: _tr('Wydajność pompy (L/min)', 'Pump flow (L/min)'),
            hint: '40',
            onChanged: () => setState(() {}),
            errorText: flowErr,
            textInputAction: TextInputAction.done,
            onSubmitted: () => FocusScope.of(context).unfocus(),
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
                        sub: '${flowLpm.toStringAsFixed(0)} L/min',
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
            // P1-15: dolny baner BHP zdjęty — pasek bezpieczeństwa jest teraz
            // pinowany NAD wejściami (zawsze widoczny, nie tylko po wyliczeniu).
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
          '${flowLpm.toStringAsFixed(0)} L/min');
    }
    buf.writeln('${_tr('Min. czas próby', 'Min. hold time')}: 10 min');
    if (!mounted) return;
    await copyToClipboard(context, buf.toString(),
        label: _tr('Raport hydrotest', 'Hydrotest report'));
  }

  // P1-26: jednolinijkowy trace — szybki paste do dziennika / SMS / chat.
  Future<void> _shareOneLineTrace({
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
    final parts = <String>[];
    if (od != null) parts.add('OD=${od.toStringAsFixed(1)}mm');
    if (wall != null) parts.add('t=${wall.toStringAsFixed(2)}mm');
    if (id != null) parts.add('ID=${id.toStringAsFixed(1)}mm');
    if (lengthM != null) parts.add('L=${lengthM.toStringAsFixed(1)}m');
    if (design != null) {
      parts.add('Pd=${design.toStringAsFixed(1)}bar×${factor.toStringAsFixed(2)}');
    }
    if (testPressure != null) {
      parts.add('Pt=${testPressure.toStringAsFixed(1)}bar');
    }
    if (volL != null) parts.add('V=${volL.toStringAsFixed(1)}L');
    if (fillMin != null) {
      parts.add('fill≈${fillMin.toStringAsFixed(1)}min@${flowLpm.toStringAsFixed(0)}L/min');
    }
    parts.add('hold≥10min');
    final trace = '${_tr('HYDRO', 'HYDRO')}: ${parts.join(' · ')}';
    debugPrint('[hydrotest] share one-line: $trace');
    if (!mounted) return;
    await copyToClipboard(context, trace,
        label: _tr('Trace hydrotest', 'Hydrotest trace'));
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
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  // P1-30: per-field errorText — wstrzykiwany z _HydrotestScreenState.
  final String? errorText;
  const _NumField({
    required this.ctrl,
    required this.label,
    required this.onChanged,
    this.hint,
    this.textInputAction,
    this.onSubmitted,
    this.errorText,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
      ),
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
    );
  }
}

// P1-15: pinowany baner BHP + minimalny czas próby, zawsze NAD wejściami.
class _SafetyHoldBanner extends StatelessWidget {
  final String text;
  const _SafetyHoldBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: _kSec, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
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
      onTap: () {
        if (!selected) Haptic.tap();
        onTap();
      },
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
