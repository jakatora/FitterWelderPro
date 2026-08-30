import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/pipe_schedules.dart';
import '../database/hydrotest_dao.dart';
import '../i18n/app_language.dart';
import '../services/hydrotest_export.dart';
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

const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF5A6478);

/// Converts a pressure typed in [unit] into bar — the app's base unit for
/// pressure, in the calculator and in `hydrotest_dao.dart` alike.
///
/// Top-level and pure so there is exactly ONE implementation of the two
/// conversion factors on this screen. The design-pressure field and the gauge
/// readings on the save sheet both route through here; two hand-written copies
/// of `v / 14.5038` is how a filed protocol ends up quoting a test pressure
/// the crew never ran.
///
/// An unrecognised [unit] is read as bar rather than throwing: the value comes
/// from a three-way toggle that cannot produce anything else, and a calculator
/// that crashes mid-typing is worse than one that falls back to its default.
double pressureToBar(double value, String unit) {
  switch (unit) {
    case 'MPa':
      return value * kBarPerMpa; // 1 MPa = 10 bar
    case 'psi':
      return value / kPsiPerBar; // 1 bar ≈ 14.5038 psi
    case 'bar':
    default:
      return value;
  }
}

/// Inverse of [pressureToBar] — used to pre-fill a gauge field with a
/// calculated value in whichever unit the crew is reading.
double pressureFromBar(double bar, String unit) {
  switch (unit) {
    case 'MPa':
      return bar / kBarPerMpa;
    case 'psi':
      return bar * kPsiPerBar;
    case 'bar':
    default:
      return bar;
  }
}

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

  // P2-05: jednostka ciśnienia projektowego — wartość w polu jest interpretowana
  // jako ta jednostka i konwertowana do barów wewnętrznie (kalkulacje liczą w bar).
  // 'bar' | 'MPa' | 'psi'
  String _designUnit = 'bar';

  /// Register of saved tests. The calculator itself stays stateless; this is
  /// the only thing on the screen that outlives a pop.
  final _dao = HydrotestDao();
  static const _uuid = Uuid();

  /// How many tests are already filed — drives the register button's label.
  int _registerCount = 0;

  /// True while a PDF is rendering, so a double tap cannot start two share
  /// sheets racing for the same temp file (same guard the weld journal uses).
  bool _busy = false;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  // P2-05: konwersja wartości projektowej (w wybranej jednostce) → bar.
  // Delegates to the top-level [pressureToBar] so the save sheet's gauge
  // fields and this field can never drift apart.
  double? _designBarFromInput(double? v) =>
      v == null ? null : pressureToBar(v, _designUnit);

  @override
  void initState() {
    super.initState();
    _refreshRegisterCount();
  }

  /// Refreshes the filed-test counter.
  ///
  /// Failure is swallowed on purpose (logged, not surfaced): a welder opening
  /// this screen wants the arithmetic, and a database that cannot be counted
  /// must not put an error banner between him and the test pressure. The
  /// failure becomes visible the moment he actually opens the register or
  /// tries to save, where it can be acted on.
  Future<void> _refreshRegisterCount() async {
    try {
      final n = await _dao.count();
      if (!mounted) return;
      setState(() => _registerCount = n);
    } catch (e) {
      debugPrint('[hydrotest] register count failed: $e');
    }
  }

  // P2-05: zakres pickera DN/SCH — zgodnie z backlog (DN15..DN300 × SCH10/40/80).
  // Reuse danych z lib/data/pipe_schedules.dart (kPipeWalls, kSchedules).
  // Kolumny 10S → "SCH 10" w UI (typowo "Schedule 10" — mapowane na 10S).
  static const List<int> _kPickerDn = [
    15, 20, 25, 32, 40, 50, 65, 80, 100, 125, 150, 200, 250, 300,
  ];
  static const List<String> _kPickerSch = ['10S', '40', '80'];

  String _schLabel(String key) {
    switch (key) {
      case '10S':
        return 'SCH 10';
      case '40':
        return 'SCH 40';
      case '80':
        return 'SCH 80';
      default:
        return 'SCH $key';
    }
  }

  Future<void> _openDnSchPicker() async {
    Haptic.tap();
    final picked = await showModalBottomSheet<_DnSchPick>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DnSchPickerSheet(
        dnList: _kPickerDn,
        schList: _kPickerSch,
        schLabel: _schLabel,
      ),
    );
    if (!mounted || picked == null) return;
    final row = kPipeWalls.firstWhere(
      (r) => r.dn == picked.dn,
      orElse: () => kPipeWalls.first,
    );
    final wall = row.walls[picked.sch];
    if (wall == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'Brak danych dla DN${picked.dn} × ${_schLabel(picked.sch)}',
            'No data for DN${picked.dn} × ${_schLabel(picked.sch)}',
          )),
        ),
      );
      return;
    }
    setState(() {
      _odCtrl.text = row.od.toStringAsFixed(1);
      _wallCtrl.text = wall.toStringAsFixed(2);
    });
    debugPrint('[hydrotest] dn/sch picked: DN${picked.dn} ${picked.sch} '
        '→ OD=${row.od} wall=$wall');
  }

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
    setState(() {
      _factor = 1.5;
      // P2-05: reset jednostki ciśnienia projektowego do bar (domyślnie).
      _designUnit = 'bar';
    });
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

  // P2-05: walidator dostaje wartość surową z pola (w wybranej jednostce);
  // limit sensowności kalibrujemy do ekwiwalentu w barach.
  String? _designError(double? raw) {
    if (_designCtrl.text.trim().isEmpty) return null;
    if (raw == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (raw <= 0) return _tr('Ciśnienie musi być > 0', 'Pressure must be > 0');
    final bar = _designBarFromInput(raw) ?? raw;
    if (bar > _kMaxDesignBar) return _tr('Sprawdź ciśnienie', 'Check pressure');
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
    final designInput = _p(_designCtrl);
    // P2-05: wewnętrznie wszystkie obliczenia w barach; wejście może być w bar/MPa/psi.
    final design = _designBarFromInput(designInput);
    final flowLpm = _p(_flowCtrl) ?? 0;

    // P1-30: zsyp do per-field errorText.
    final odErr     = _odError(od);
    final wallErr   = _wallError(wall, od);
    final lengthErr = _lengthError(lengthM);
    final designErr = _designError(designInput);
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
          const SizedBox(height: 6),
          // P2-05: szybki picker DN/SCH — auto-fill OD + ścianki z B36.10M.
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: TextButton.icon(
                onPressed: _openDnSchPicker,
                icon: const Icon(Icons.list_alt, size: 18, color: _kBlue),
                label: Text(
                  _tr('📋 DN/SCH — wybierz z tabeli',
                      '📋 DN/SCH — pick from table'),
                  style: const TextStyle(
                      color: _kBlue, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
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
          // P2-05: pole + przełącznik jednostki (bar / MPa / psi) obok siebie.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NumField(
                  ctrl: _designCtrl,
                  label: _tr(
                      'Ciśnienie projektowe ($_designUnit)',
                      'Design pressure ($_designUnit)'),
                  hint: _designUnit == 'psi'
                      ? '145'
                      : (_designUnit == 'MPa' ? '1.0' : '10'),
                  onChanged: () => setState(() {}),
                  errorText: designErr,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 10),
              _PressureUnitToggle(
                value: _designUnit,
                onChanged: (u) {
                  if (u == _designUnit) return;
                  Haptic.tap();
                  setState(() => _designUnit = u);
                  debugPrint('[hydrotest] design unit → $u');
                },
              ),
            ],
          ),
          // P2-05: live preview "= X MPa" (zawsze widoczne gdy wartość parsuje się).
          if (designInput != null && designErr == null && design != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _designUnit == 'MPa'
                    ? '= ${design.toStringAsFixed(2)} bar '
                        '= ${(design * 14.5038).toStringAsFixed(0)} psi'
                    : '= ${(design / 10).toStringAsFixed(3)} MPa'
                        '${_designUnit == 'psi'
                            ? '  = ${design.toStringAsFixed(2)} bar'
                            : ''}',
                style: const TextStyle(color: _kMuted, fontSize: 11),
              ),
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

          // ── Register ────────────────────────────────────────────────────
          // The calculation used to die with the screen: the share button only
          // copied a line of text to the clipboard, so a pressure test — an
          // ACCEPTANCE step that ASME B31.3 § 345.2.7 wants a retained record
          // of — left nothing behind. Filing it here is what turns this screen
          // from a calculator into a document.
          //
          // Placed at the end of the list rather than in the AppBar because
          // the bar already carries four actions; a fifth and sixth would push
          // the title off a 360 dp phone.
          const SizedBox(height: 22),
          _SectionHeader(_tr('REJESTR PRÓB', 'TEST REGISTER')),
          const SizedBox(height: 6),
          Text(
            _tr(
              'Zapisana próba zostaje w telefonie: system/linia, data, manometr, '
              'ciśnienie początkowe i końcowe, temperatura, czas wytrzymania, '
              'wynik i świadek — z protokołem PDF do podpisu.',
              'A saved test stays on the phone: system/line, date, gauge, start '
              'and end pressure, temperature, hold time, result and witness — '
              'with a PDF protocol to sign.',
            ),
            style: const TextStyle(color: _kMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                // Saving needs a test pressure: a protocol whose central
                // number is blank is not a protocol.
                onPressed: (testPressure == null || _busy)
                    ? null
                    : () => _openSaveSheet(
                          od: od,
                          wall: wall,
                          lengthM: lengthM,
                          design: design,
                          testPressure: testPressure,
                          volL: volL,
                        ),
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                label: Text(_tr('Zapisz próbę', 'Save test')),
                style: FilledButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _openRegister,
                icon: const Icon(Icons.fact_check_outlined,
                    size: 18, color: _kBlue),
                label: Text(
                  _registerCount > 0
                      ? _tr('Rejestr ($_registerCount)',
                          'Register ($_registerCount)')
                      : _tr('Rejestr', 'Register'),
                  style: const TextStyle(color: _kBlue),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kBorder),
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ]),
          if (testPressure == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _tr('Podaj ciśnienie projektowe, żeby zapisać próbę.',
                    'Enter the design pressure to save a test.'),
                style: const TextStyle(color: _kMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  /// Collects the witnessed half of the test and files it.
  ///
  /// The calculated values are passed in from `build` and stored as a snapshot
  /// (see [HydrotestRecord]): a protocol reprinted next year must show the
  /// numbers the crew worked to, not whatever the calculator would produce
  /// today.
  Future<void> _openSaveSheet({
    required double? od,
    required double? wall,
    required double? lengthM,
    required double? design,
    required double? testPressure,
    required double? volL,
  }) async {
    Haptic.tap();
    final draft = await showModalBottomSheet<_HydrotestDraft>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      // Same reasoning as the weld-journal editor: this sheet holds a dozen
      // hand-typed fields witnessed at the manifold, and neither a stray tap
      // on the scrim nor a gloved thumb brushing downwards may throw them
      // away. The Cancel button and the system back gesture remain.
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _HydrotestSaveSheet(
          initialUnit: _designUnit,
          testPressureBar: testPressure,
        ),
      ),
    );
    if (draft == null) return;
    // Separate line, not `draft == null || !mounted`: everything below reads
    // the BuildContext, and a bare `if (!mounted) return;` is the form the
    // analyzer recognises as the guard for it.
    if (!mounted) return;

    final record = HydrotestRecord(
      id: _uuid.v4(),
      systemName: draft.systemName,
      date: draft.date,
      gauge: draft.gauge,
      pressureStartBar: draft.pressureStartBar,
      pressureEndBar: draft.pressureEndBar,
      temperatureC: draft.temperatureC,
      holdMinutes: draft.holdMinutes,
      result: draft.result,
      witness: draft.witness,
      odMm: od,
      wallMm: wall,
      // Metres on screen, MILLIMETRES in the database — every other length in
      // the app is stored in mm and this one is not going to be the exception.
      lineLengthMm: lengthM == null ? null : lengthM * 1000.0,
      designBar: design,
      factor: _factor,
      testPressureBar: testPressure,
      volumeL: volL,
      notes: draft.notes,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    // Messenger AND every string are resolved BEFORE the write: all of them
    // read the BuildContext, and after an await this State may be gone.
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg =
        _tr('Nie udało się zapisać próby.', 'Failed to save the test.');
    final savedMsg =
        _tr('Próba zapisana w rejestrze.', 'Test filed in the register.');
    final pdfLabel = _tr('Protokół PDF', 'PDF protocol');
    try {
      await _dao.insert(record);
    } catch (e) {
      debugPrint('[hydrotest] save failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(failedMsg)));
      return;
    }
    Haptic.saved();
    debugPrint('[hydrotest] saved test ${record.id} → ${record.result}');
    messenger.showSnackBar(SnackBar(
      content: Text(savedMsg),
      // The protocol is the point of saving, so it is one tap away from the
      // confirmation rather than buried in the register list.
      action: SnackBarAction(
        label: pdfLabel,
        onPressed: () => _sharePdf(record),
      ),
    ));
    await _refreshRegisterCount();
  }

  Future<void> _sharePdf(HydrotestRecord record) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await shareHydrotestProtocol(context, record);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    Haptic.tap();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _HydrotestRegisterSheet(dao: _dao),
    );
    if (!mounted) return;
    // The sheet can delete rows, so the badge is re-read rather than guessed.
    await _refreshRegisterCount();
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

// ─────────────────────────────────────────────────────────────────────────────
// P2-05: DN/SCH picker + przełącznik jednostki ciśnienia projektowego.
// ─────────────────────────────────────────────────────────────────────────────

/// P2-05: zwracany z bottom sheeta wybór użytkownika.
class _DnSchPick {
  final int dn;
  final String sch;
  const _DnSchPick(this.dn, this.sch);
}

/// P2-05: bottom-sheet picker — DN15..DN300 × SCH10/40/80.
/// Czyta `kPipeWalls` z lib/data/pipe_schedules.dart (offline).
class _DnSchPickerSheet extends StatefulWidget {
  final List<int> dnList;
  final List<String> schList;
  final String Function(String) schLabel;
  const _DnSchPickerSheet({
    required this.dnList,
    required this.schList,
    required this.schLabel,
  });

  @override
  State<_DnSchPickerSheet> createState() => _DnSchPickerSheetState();
}

class _DnSchPickerSheetState extends State<_DnSchPickerSheet> {
  int? _dn;
  String? _sch;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  PipeRow? _rowFor(int dn) {
    for (final r in kPipeWalls) {
      if (r.dn == dn) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final row = _dn == null ? null : _rowFor(_dn!);
    final wall =
        (row != null && _sch != null) ? row.walls[_sch!] : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 16 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              _tr('Wybierz DN i SCH', 'Pick DN and SCH'),
              style: const TextStyle(
                  color: _kOrange,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2),
            ),
            const SizedBox(height: 4),
            Text(
              _tr('ASME B36.10M — auto-wypełni OD i ściankę.',
                  'ASME B36.10M — auto-fills OD and wall.'),
              style: const TextStyle(color: _kMuted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text(
              _tr('DN', 'DN'),
              style: const TextStyle(
                  color: _kSec, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final dn in widget.dnList)
                  ChoiceChip(
                    label: Text('DN$dn'),
                    selected: _dn == dn,
                    onSelected: (_) {
                      Haptic.tap();
                      setState(() => _dn = dn);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _tr('Schedule', 'Schedule'),
              style: const TextStyle(
                  color: _kSec, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in widget.schList)
                  ChoiceChip(
                    label: Text(widget.schLabel(s)),
                    selected: _sch == s,
                    onSelected: (_) {
                      Haptic.tap();
                      setState(() => _sch = s);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // preview
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF12141C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                row == null
                    ? _tr('Wybierz DN', 'Pick a DN')
                    : (_sch == null
                        ? '${_tr('DN', 'DN')}${row.dn}  ·  '
                            'OD ${row.od.toStringAsFixed(1)} mm  ·  '
                            '${_tr('wybierz SCH', 'pick SCH')}'
                        : (wall == null
                            ? _tr(
                                'Brak danych dla DN${row.dn} × ${widget.schLabel(_sch!)}',
                                'No data for DN${row.dn} × ${widget.schLabel(_sch!)}')
                            : 'DN${row.dn}  ·  '
                                'OD ${row.od.toStringAsFixed(1)} mm  ·  '
                                't ${wall.toStringAsFixed(2)} mm  '
                                '(${widget.schLabel(_sch!)})')),
                style: const TextStyle(
                    color: _kSec,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(_tr('Anuluj', 'Cancel'),
                        style: const TextStyle(color: _kSec)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: (_dn != null && _sch != null && wall != null)
                        ? () => Navigator.pop(
                            context, _DnSchPick(_dn!, _sch!))
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kOrange,
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(_tr('Wybierz', 'Pick'),
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// P2-05: trzy-pozycyjny segmented control bar / MPa / psi.
class _PressureUnitToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _PressureUnitToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget cell(String key, String label) {
      final selected = key == value;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: InkWell(
          onTap: () => onChanged(key),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? _kOrange.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? _kOrange : _kSec,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell('bar', 'bar'),
          cell('MPa', 'MPa'),
          cell('psi', 'psi'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REJESTR PRÓB — zapis, lista, protokół PDF.
// Test register — filing, listing, PDF protocol.
// ─────────────────────────────────────────────────────────────────────────────

/// Renders the protocol and hands it to the OS share sheet, reporting a
/// failure instead of leaving a dead button.
///
/// Top-level because two places need it: the calculator screen (right after a
/// save) and the register list. The messenger is captured BEFORE the await so
/// the error path never reaches for a `BuildContext` across an async gap — the
/// sheet it belongs to may well be gone by then.
Future<void> shareHydrotestProtocol(
  BuildContext context,
  HydrotestRecord record,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.tr(
    pl: 'Nie udało się utworzyć protokołu PDF.',
    en: 'Failed to create the PDF protocol.',
  );
  try {
    await HydrotestExport.sharePdf(record: record);
  } catch (e) {
    debugPrint('[hydrotest] pdf export failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

/// The witnessed half of a test, as collected by [_HydrotestSaveSheet].
///
/// Deliberately separate from [HydrotestRecord]: the sheet knows what happened
/// at the manifold, the screen knows the calculation and the uuid. Handing a
/// half-built record around would invite somebody to file one with the
/// calculated fields left null.
class _HydrotestDraft {
  final String systemName;
  final String date;
  final String gauge;
  final double? pressureStartBar;
  final double? pressureEndBar;
  final double? temperatureC;
  final double? holdMinutes;
  final String result;
  final String witness;
  final String notes;

  const _HydrotestDraft({
    required this.systemName,
    required this.date,
    required this.gauge,
    required this.result,
    this.pressureStartBar,
    this.pressureEndBar,
    this.temperatureC,
    this.holdMinutes,
    this.witness = '',
    this.notes = '',
  });
}

/// Bottom sheet that collects what was actually witnessed at the test.
///
/// Only two fields are mandatory — the system tag and the PASS/FAIL verdict.
/// Everything else may be left blank on purpose: a crew without a thermometer
/// must still be able to file a record, and the printed protocol names what is
/// missing (see `hydrotestMissingNote`) instead of hiding the gap behind a
/// zero.
class _HydrotestSaveSheet extends StatefulWidget {
  /// Pressure unit the calculator screen was set to — the gauge fields open in
  /// the same unit so the welder does not switch context mid-test.
  final String initialUnit;

  /// Calculated test pressure in bar; pre-fills the "start pressure" field,
  /// which is what the pump is brought up to.
  final double? testPressureBar;

  const _HydrotestSaveSheet({
    required this.initialUnit,
    required this.testPressureBar,
  });

  @override
  State<_HydrotestSaveSheet> createState() => _HydrotestSaveSheetState();
}

class _HydrotestSaveSheetState extends State<_HydrotestSaveSheet> {
  final _systemCtrl = TextEditingController();
  final _gaugeCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  // Pre-filled with the code minimum: 10 min is what the crew is aiming for,
  // and typing over it is quicker than typing it from scratch.
  final _holdCtrl = TextEditingController(text: '10');
  final _witnessCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late final TextEditingController _dateCtrl;
  late final TextEditingController _startCtrl;

  late String _unit;

  /// Null until the crew picks. There is deliberately NO default: the app
  /// records a test, it does not sign one off, and a pre-selected PASS is
  /// exactly the kind of default that gets tapped through.
  String? _result;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _unit = widget.initialUnit;
    _dateCtrl = TextEditingController(text: _today());
    final p = widget.testPressureBar;
    _startCtrl = TextEditingController(
      text: p == null ? '' : pressureFromBar(p, _unit).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _systemCtrl, _gaugeCtrl, _endCtrl, _tempCtrl, _holdCtrl,
      _witnessCtrl, _notesCtrl, _dateCtrl, _startCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  double? _num(TextEditingController c) => c.text.trim().isEmpty
      ? null
      : double.tryParse(c.text.replaceAll(',', '.'));

  /// A gauge reading converted to bar, the unit the register stores.
  double? _bar(TextEditingController c) {
    final v = _num(c);
    return v == null ? null : pressureToBar(v, _unit);
  }

  double? get _dropBar {
    final a = _bar(_startCtrl);
    final b = _bar(_endCtrl);
    if (a == null || b == null) return null;
    return a - b;
  }

  bool get _canSave => _systemCtrl.text.trim().isNotEmpty && _result != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateCtrl.text.trim()) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _dateCtrl.text = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  void _submit() {
    if (!_canSave) return;
    Haptic.tap();
    Navigator.pop(
      context,
      _HydrotestDraft(
        systemName: _systemCtrl.text.trim(),
        date: _dateCtrl.text.trim(),
        gauge: _gaugeCtrl.text.trim(),
        pressureStartBar: _bar(_startCtrl),
        pressureEndBar: _bar(_endCtrl),
        temperatureC: _num(_tempCtrl),
        holdMinutes: _num(_holdCtrl),
        result: _result!,
        witness: _witnessCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hold = _num(_holdCtrl);
    final shortHold = hold != null && hold < kHydrotestMinHoldMinutes;
    final drop = _dropBar;
    final passWithDrop = _result == kHydrotestPass &&
        drop != null &&
        drop > kHydrotestDropEpsilonBar;
    final startBar = _bar(_startCtrl);
    final endBar = _bar(_endCtrl);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              _tr('Zapisz próbę do rejestru', 'File the test'),
              style: const TextStyle(
                  color: _kOrange,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2),
            ),
            const SizedBox(height: 4),
            Text(
              _tr(
                'Wpis trafia do rejestru w telefonie i można z niego wydrukować '
                'protokół. Wynik PASS/FAIL ustala inżynier QC — aplikacja tylko '
                'go zapisuje.',
                'The entry goes into the register on this phone and can be '
                'printed as a protocol. The PASS/FAIL verdict is the QC '
                "engineer's — the app only records it.",
              ),
              style: const TextStyle(color: _kMuted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 14),

            _SectionHeader(_tr('IDENTYFIKACJA', 'IDENTIFICATION')),
            const SizedBox(height: 8),
            TextField(
              controller: _systemCtrl,
              textInputAction: TextInputAction.next,
              // Rebuild on every keystroke: the Save button is gated on this
              // field being non-empty, so it has to react as it is typed.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _tr('System / linia *', 'System / line *'),
                hintText: _tr('np. WFI-101', 'e.g. WFI-101'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dateCtrl,
              decoration: InputDecoration(
                labelText: _tr('Data próby', 'Test date'),
                hintText: 'YYYY-MM-DD',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined, size: 20),
                  tooltip: _tr('Wybierz datę', 'Pick date'),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _pickDate,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _gaugeCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                // ASME B31.3 § 345.5.1 wants a calibrated gauge; the protocol
                // has to be able to name which one.
                labelText: _tr(
                    'Manometr (nr / kalibracja)', 'Gauge (no. / calibration)'),
                hintText: _tr(
                    'np. M-12 / kal. 2026-03', 'e.g. M-12 / cal. 2026-03'),
              ),
            ),

            const SizedBox(height: 16),
            _SectionHeader(_tr('PRZEBIEG PRÓBY', 'TEST RECORD')),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _NumField(
                    ctrl: _startCtrl,
                    label: _tr('Ciśnienie pocz. ($_unit)',
                        'Start pressure ($_unit)'),
                    onChanged: () => setState(() {}),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 10),
                _PressureUnitToggle(
                  value: _unit,
                  onChanged: (u) {
                    if (u == _unit) return;
                    Haptic.tap();
                    // Same semantics as the calculator's toggle: the typed
                    // NUMBER stays, its unit changes. Silently converting the
                    // digits under a welder's thumb is worse than making him
                    // read the "stored as … bar" line below.
                    setState(() => _unit = u);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            _NumField(
              ctrl: _endCtrl,
              label: _tr('Ciśnienie końcowe ($_unit)', 'End pressure ($_unit)'),
              onChanged: () => setState(() {}),
              textInputAction: TextInputAction.next,
            ),
            // Only shown for MPa/psi: in bar the field value and the stored
            // value are the same number and the line would be noise.
            if (_unit != 'bar' && startBar != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  '${_tr('Zapis w rejestrze', 'Stored as')}: '
                  '${startBar.toStringAsFixed(2)} bar'
                  '${endBar == null ? '' : ' → ${endBar.toStringAsFixed(2)} bar'}',
                  style: const TextStyle(color: _kMuted, fontSize: 11),
                ),
              ),
            if (drop != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  '${_tr('Spadek ciśnienia', 'Pressure drop')}: '
                  '${drop.toStringAsFixed(2)} bar',
                  style: TextStyle(
                    color: drop > kHydrotestDropEpsilonBar ? _kRed : _kGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _NumField(
                  ctrl: _tempCtrl,
                  label: _tr('Temperatura (°C)', 'Temperature (°C)'),
                  hint: '12',
                  onChanged: () => setState(() {}),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  ctrl: _holdCtrl,
                  label: _tr('Czas wytrzymania (min)', 'Hold time (min)'),
                  hint: '10',
                  onChanged: () => setState(() {}),
                  textInputAction: TextInputAction.next,
                ),
              ),
            ]),
            if (shortHold)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Czas wytrzymania krótszy niż 10 min (ASME B31.3 § 345.4.2). '
                    'Zostanie to odnotowane na protokole.',
                    'Hold time shorter than 10 min (ASME B31.3 § 345.4.2). '
                    'It will be noted on the protocol.',
                  ),
                ),
              ),

            const SizedBox(height: 16),
            _SectionHeader(_tr('WYNIK', 'RESULT')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _ResultChip(
                  label: _tr('PASS — pozytywny', 'PASS'),
                  color: _kGreen,
                  selected: _result == kHydrotestPass,
                  onTap: () => setState(() => _result = kHydrotestPass),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResultChip(
                  label: _tr('FAIL — negatywny', 'FAIL'),
                  color: _kRed,
                  selected: _result == kHydrotestFail,
                  onTap: () => setState(() => _result = kHydrotestFail),
                ),
              ),
            ]),
            if (passWithDrop)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Wynik PASS mimo spadku ciśnienia — uzasadnij w uwagach '
                    '(np. zmiana temperatury). Ostrzeżenie trafi na protokół.',
                    'PASS despite a pressure drop — justify it in the notes '
                    '(e.g. temperature change). The warning goes on the protocol.',
                  ),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _witnessCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: _tr('Świadek / inspektor', 'Witness / inspector'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _tr('Uwagi', 'Notes'),
                hintText: _tr(
                    'np. odpowietrzenie na najwyższym punkcie, korki 2×',
                    'e.g. vented at high point, 2 blinds fitted'),
              ),
            ),

            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(_tr('Anuluj', 'Cancel'),
                      style: const TextStyle(color: _kSec)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _canSave ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kOrange,
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(_tr('Zapisz', 'Save'),
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (!_canSave)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _tr('Wymagane: system/linia i wynik PASS/FAIL.',
                      'Required: system/line and the PASS/FAIL result.'),
                  style: const TextStyle(color: _kMuted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Orange advisory strip used inside the save sheet. Not red: none of these
/// conditions blocks the save — the crew may have a good reason, and the note
/// is carried onto the protocol either way.
class _SheetWarning extends StatelessWidget {
  final String text;
  const _SheetWarning({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _kOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kOrange.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _kOrange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: _kSec, fontSize: 11, height: 1.35)),
            ),
          ],
        ),
      );
}

/// PASS / FAIL selector. Deliberately a pair of large chips rather than a
/// dropdown: gloved thumbs, and the verdict is the one field nobody may miss.
class _ResultChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ResultChip({
    required this.label,
    required this.color,
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
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : _kBorder, width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? color : _kSec,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// The filed tests, newest first, each with a one-tap PDF protocol.
class _HydrotestRegisterSheet extends StatefulWidget {
  final HydrotestDao dao;
  const _HydrotestRegisterSheet({required this.dao});
  @override
  State<_HydrotestRegisterSheet> createState() =>
      _HydrotestRegisterSheetState();
}

class _HydrotestRegisterSheetState extends State<_HydrotestRegisterSheet> {
  List<HydrotestRecord> _rows = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.dao.listAll();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      // Reported INSIDE the sheet, not as a SnackBar: a snack behind a modal
      // is a message the welder never sees, and this is the one place where a
      // broken register has to be actionable (Retry).
      debugPrint('[hydrotest] register load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _tr('Nie udało się wczytać rejestru.',
            'Failed to load the register.');
      });
    }
  }

  Future<void> _share(HydrotestRecord r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await shareHydrotestProtocol(context, r);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(HydrotestRecord r) async {
    final label = r.systemName.trim().isEmpty ? r.date : r.systemName.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Usunąć próbę?', 'Delete test?')),
        content: Text(_tr(
          'Wpis "$label" zniknie z rejestru. Wydrukowane protokoły zostają.',
          'The "$label" entry disappears from the register. Printed protocols stay.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('Anuluj', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Usuń', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    // Both resolved before the delete — see the same note in _openSaveSheet.
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg =
        _tr('Nie udało się usunąć próby.', 'Failed to delete the test.');
    try {
      await widget.dao.deleteById(r.id);
    } catch (e) {
      debugPrint('[hydrotest] register delete failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(failedMsg)));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(children: [
                Expanded(
                  child: Text(
                    _tr('Rejestr prób ciśnieniowych', 'Pressure test register'),
                    style: const TextStyle(
                        color: _kOrange,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: _kSec),
                  tooltip: _tr('Zamknij', 'Close'),
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 6),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kOrange));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 44, color: _kRed),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: _kSec, fontSize: 13)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(_tr('Ponów', 'Retry'),
                  style: const TextStyle(color: _kBlue)),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fact_check_outlined, size: 52, color: _kMuted),
            const SizedBox(height: 12),
            Text(
              _tr(
                  'Brak zapisanych prób.\nPolicz próbę i naciśnij "Zapisz próbę".',
                  'No tests filed yet.\nRun a calculation and tap "Save test".'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding:
          EdgeInsets.only(bottom: 8 + MediaQuery.viewPaddingOf(context).bottom),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _HydrotestRegisterTile(
        record: _rows[i],
        busy: _busy,
        onShare: () => _share(_rows[i]),
        onDelete: () => _delete(_rows[i]),
      ),
    );
  }
}

/// One filed test. Shows the three things a foreman scans a register for:
/// which line, when, and did it hold.
class _HydrotestRegisterTile extends StatelessWidget {
  final HydrotestRecord record;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _HydrotestRegisterTile({
    required this.record,
    required this.busy,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    String tr(String pl, String en) => context.tr(pl: pl, en: en);
    final passed = record.passed;
    final ink = passed ? _kGreen : _kRed;
    final system = record.systemName.trim();
    final details = <String>[
      if (record.date.trim().isNotEmpty) record.date.trim(),
      if (record.testPressureBar != null)
        '${record.testPressureBar!.toStringAsFixed(1)} bar',
      if (record.holdMinutes != null)
        '${record.holdMinutes!.toStringAsFixed(0)} min',
      if (record.volumeL != null) '${record.volumeL!.toStringAsFixed(0)} L',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              passed ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: ink,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  system.isEmpty ? tr('(bez systemu)', '(no system)') : system,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE7ECF3)),
                ),
                const SizedBox(height: 3),
                Text(
                  details.join('  ·  '),
                  style: const TextStyle(fontSize: 11, color: _kMuted),
                ),
                // A short hold is the most common reason a filed test does not
                // survive review, so it is flagged in the list too — not only
                // on the printed protocol.
                if (!record.meetsMinimumHold)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      tr('czas wytrzymania < 10 min', 'hold time < 10 min'),
                      style: const TextStyle(fontSize: 10, color: _kOrange),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined,
                size: 20, color: _kBlue),
            tooltip: tr('Protokół PDF', 'PDF protocol'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: busy ? null : onShare,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: _kMuted),
            tooltip: tr('Usuń', 'Delete'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}
