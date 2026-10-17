import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/pipe_schedules.dart';
import '../database/hydrotest_dao.dart';
import '../database/instrument_dao.dart';
import '../domain/instruments/instrument.dart';
import '../domain/pressure_test/hydrotest_protocol_meta.dart';
import '../domain/pressure_test/test_pressure.dart';
import '../i18n/app_language.dart';
import '../services/hydrotest_export.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../widgets/number_field.dart';

// P1-14: lokalna definicja pomocy dla ekranu hydrotest
// (kHelpHydrotest nie istnieje w help_button.dart — dodajemy lokalnie,
// żeby nie ruszać współdzielonego pliku z tej zmiany).
final kHelpHydrotest = ScreenHelp(
  titlePl: 'Próba ciśnieniowa',
  titleEn: 'Pressure test',
  bodyPl:
      'Kalkulator próby ciśnieniowej. Liczy minimalne ciśnienie próby wg '
      'wybranej normy: ASME B31.3 hydro (Pt = 1,5·P·ST/S, ST/S ≤ 6,5, '
      '§345.4.2), B31.3 pneumatyczna (1,1·P, §345.5.4), B31.1 hydro (1,5·P, '
      '§137.4.5), EN 13480-5 / PED (większa z 1,25·PS·f_test/f i 1,43·PS) '
      'oraz ASME VIII-1 zbiorniki (1,3·MAWP·LSR, UG-99(b)). Do tego objętość '
      'wody i czas napełniania. Minimalny czas pod ciśnieniem próby wg B31.3: '
      '10 min (§345.2.2(a)).',
  bodyEn:
      'Pressure-test calculator. Computes the minimum test pressure for the '
      'selected code: ASME B31.3 hydro (Pt = 1.5·P·ST/S, ST/S ≤ 6.5, '
      '§345.4.2), B31.3 pneumatic (1.1·P, §345.5.4), B31.1 hydro (1.5·P, '
      '§137.4.5), EN 13480-5 / PED (greater of 1.25·PS·f_test/f and 1.43·PS) '
      'and ASME VIII-1 vessels (1.3·MAWP·LSR, UG-99(b)), plus the water volume '
      'and fill time. Minimum hold at test pressure per B31.3: 10 min '
      '(§345.2.2(a)).',
  stepsPl: [
    HelpStep('📏', 'Wpisz OD, ściankę i długość linii (mm / m).'),
    HelpStep('📘', 'Wybierz normę i rodzaj próby.'),
    HelpStep('🧮', 'Podaj ciśnienie obliczeniowe i — jeśli norma tego wymaga — '
        'stosunek naprężeń (ST/S, f_test/f, LSR; domyślnie 1,0).'),
    HelpStep('💧', 'Wpisz wydajność pompy (L/min) — policzy czas napełniania.'),
    HelpStep('⚠️', 'Strefę testu oznakuj i wygrodź — procedurę pisze inżynier QC.'),
  ],
  stepsEn: [
    HelpStep('📏', 'Enter OD, wall and line length (mm / m).'),
    HelpStep('📘', 'Pick the code and the test type.'),
    HelpStep('🧮', 'Enter the design pressure and — where the code needs it — '
        'the stress ratio (ST/S, f_test/f, LSR; 1.0 by default).'),
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
const _kMuted  = kTextMut;

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

/// Pressure-test calculator for a pipe run (or a vessel).
/// Inputs the design pressure, the code preset and pipe geometry, gives back:
///   • minimum test pressure per the selected code preset — arithmetic in
///     `lib/domain/pressure_test/test_pressure.dart` (B31.3 §345.4.2:
///     1.5·P·ST/S; B31.3 §345.5.4 pneumatic 1.1·P; B31.1 §137.4.5 1.5·P;
///     EN 13480-5 / PED max(1.25·PS·f_test/f, 1.43·PS); VIII-1 UG-99(b)
///     1.3·MAWP·LSR)
///   • water volume    needed to fill the run
///   • minimum hold time for the code (B31.3 §345.2.2(a): 10 min)
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

  /// Temperature correction for the preset: ST/S (B31.3), f_test/f
  /// (EN 13480-5) or LSR (ASME VIII-1). Empty means 1.0.
  final _ratioCtrl  = TextEditingController();

  /// Optional yield strength at test temperature [MPa] — lets the screen
  /// warn per B31.3 §345.2.1(a) when the test pressure would yield the pipe.
  final _yieldCtrl  = TextEditingController();

  /// Water column (hydrostatic tests): how far the highest point is above the
  /// gauge and the lowest point below it [m]. Pt applies „at any point”
  /// (B31.1 §137.4.5, B31.3 §345.4.2), so a gauge below the high point must
  /// read more, and the low point sees more (used for the yield check).
  final _highCtrl = TextEditingController();
  final _lowCtrl  = TextEditingController();

  /// Code preset. ASME B31.3 hydrostatic is the default, as before.
  PressureTestPreset _preset = PressureTestPreset.b313Hydro;

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
    for (final c in [
      _odCtrl, _wallCtrl, _lengthCtrl, _designCtrl, _flowCtrl, _ratioCtrl,
      _yieldCtrl, _highCtrl, _lowCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _p(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseDecimal(c.text);

  // P1-04: reset całego ekranu — wszystkie pola + preset do domyślnego B31.3.
  void _resetAll() {
    Haptic.tap();
    _odCtrl.clear();
    _wallCtrl.clear();
    _lengthCtrl.clear();
    _designCtrl.clear();
    _ratioCtrl.clear();
    _yieldCtrl.clear();
    _highCtrl.clear();
    _lowCtrl.clear();
    _flowCtrl.text = '40';
    setState(() {
      _preset = PressureTestPreset.b313Hydro;
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

  /// Sanity cap for a stress ratio. B31.3 itself caps ST/S at 6.5; anything
  /// above ~10 is a typo (a stress typed where a ratio was expected).
  static const double _kMaxRatio = 10;

  /// Upper sanity cap for a yield strength [MPa].
  static const double _kMaxYieldMpa = 2000;

  String? _ratioError(double? v) {
    if (_ratioCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v <= 0) return _tr('Musi być > 0', 'Must be > 0');
    if (v > _kMaxRatio) return _tr('Sprawdź wartość', 'Check value');
    return null;
  }

  /// Heights of the water column [m]: 0–1000.
  String? _heightError(TextEditingController c, double? v) {
    if (c.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v < 0) return _tr('Musi być ≥ 0', 'Must be ≥ 0');
    if (v > 1000) return _tr('Sprawdź wartość', 'Check value');
    return null;
  }

  String? _yieldError(double? v) {
    if (_yieldCtrl.text.trim().isEmpty) return null;
    if (v == null) return _tr('Nieprawidłowa liczba', 'Invalid number');
    if (v <= 0) return _tr('Musi być > 0', 'Must be > 0');
    if (v > _kMaxYieldMpa) return _tr('Sprawdź wartość', 'Check value');
    return null;
  }

  /// Short bilingual name of a preset for the picker and the report.
  String _presetTitle(PressureTestPreset p) {
    switch (p) {
      case PressureTestPreset.b313Hydro:
        return _tr('ASME B31.3 — hydrostatyczna', 'ASME B31.3 — hydrostatic');
      case PressureTestPreset.b313Pneumatic:
        return _tr('ASME B31.3 — pneumatyczna', 'ASME B31.3 — pneumatic');
      case PressureTestPreset.b311Hydro:
        return _tr('ASME B31.1 — hydrostatyczna', 'ASME B31.1 — hydrostatic');
      case PressureTestPreset.en13480Hydro:
        return _tr('EN 13480-5 / PED — hydrostatyczna',
            'EN 13480-5 / PED — hydrostatic');
      case PressureTestPreset.asmeVIII1Hydro:
        return _tr('ASME VIII-1 — zbiornik, hydrostatyczna',
            'ASME VIII-1 — vessel, hydrostatic');
    }
  }

  /// Label of the stress-ratio field for presets that use one.
  String _ratioLabel(PressureTestPreset p) {
    final symbol = p.ratioSymbol ?? '';
    if (p == PressureTestPreset.asmeVIII1Hydro) {
      return _tr('$symbol (najmniejszy stosunek naprężeń)',
          '$symbol (lowest stress ratio)');
    }
    return _tr('$symbol (korekta temperaturowa)',
        '$symbol (temperature correction)');
  }

  /// What the stress ratio means, per preset.
  String _ratioHelp(PressureTestPreset p) {
    switch (p) {
      case PressureTestPreset.b313Hydro:
        return _tr(
          'ST — naprężenie dopuszczalne materiału w temperaturze próby, S — w '
          'temperaturze obliczeniowej (§345.4.2). Puste = 1,0 (S w temp. '
          'obliczeniowej nie niższe niż w temp. próby). Maks. 6,5.',
          'ST — allowable stress at test temperature, S — at design '
          'temperature (§345.4.2). Empty = 1.0 (S at design temperature not '
          'lower than at test temperature). Max 6.5.',
        );
      case PressureTestPreset.en13480Hydro:
        return _tr(
          'f_test — naprężenie nominalne w temperaturze próby, f — w '
          'temperaturze obliczeniowej. Pt = większa z 1,25·PS·f_test/f i '
          '1,43·PS. Puste = 1,0.',
          'f_test — nominal design stress at test temperature, f — at design '
          'temperature. Pt = greater of 1.25·PS·f_test/f and 1.43·PS. '
          'Empty = 1.0.',
        );
      case PressureTestPreset.asmeVIII1Hydro:
        return _tr(
          'LSR — najmniejszy dla materiałów zbiornika stosunek S w temp. próby '
          'do S w temp. obliczeniowej (UG-99(b)). Ciśnienie bazowe = MAWP. '
          'Puste = 1,0.',
          'LSR — lowest ratio, over the vessel materials, of S at test '
          'temperature to S at design temperature (UG-99(b)). Base pressure = '
          'MAWP. Empty = 1.0.',
        );
      case PressureTestPreset.b313Pneumatic:
      case PressureTestPreset.b311Hydro:
        return '';
    }
  }

  /// Yield check line: σ at the highest-pressure point vs the preset's limit
  /// (100 % Re B31.3 hydro, 90 % Re B31.3 pneumatic) or, for EN 13480-5,
  /// σ / Re with the limit „to be confirmed in the standard”.
  Widget _yieldResult({
    required double hoopMpa,
    required double yieldMpa,
    required double? fraction,
    required double? limitBar,
    required double ptBar,
    required bool atLowPoint,
  }) {
    final pct = (hoopMpa / yieldMpa * 100).toStringAsFixed(0);
    final sigma = atLowPoint
        ? _tr('σ w najniższym punkcie = ${hoopMpa.toStringAsFixed(0)} MPa',
            'Hoop stress at the lowest point = ${hoopMpa.toStringAsFixed(0)} MPa')
        : _tr('σ przy Pt = ${hoopMpa.toStringAsFixed(0)} MPa',
            'Hoop stress at Pt = ${hoopMpa.toStringAsFixed(0)} MPa');
    if (fraction == null) {
      // EN 13480-5 — limit not verified in the standard text.
      final over = hoopMpa > yieldMpa;
      final text = _tr(
        '$sigma ($pct % Re). Granica wg EN 13480-3 (f_test) — do potwierdzenia '
            'w normie.${over ? ' Naprężenie powyżej Re — Pt za wysokie.' : ''}',
        '$sigma ($pct % of yield). Limit per EN 13480-3 (f_test) — to be '
            'confirmed in the standard.${over ? ' Stress above yield — Pt too high.' : ''}',
      );
      return over
          ? _SheetWarning(text: text)
          : Text(text, style: const TextStyle(color: _kSec, fontSize: 11));
    }
    final limitPct = (fraction * 100).toStringAsFixed(0);
    final over = hoopMpa > yieldMpa * fraction;
    final limitText = limitBar == null ? '—' : limitBar.toStringAsFixed(2);
    if (_preset.isPneumatic) {
      final text = _tr(
        '$sigma ($pct % Re). Maks. Pt = mniejsza z 1,33 · P i ciśnienia przy '
            '$limitPct % Re = $limitText bar.'
            '${ptBar > (limitBar ?? double.infinity) ? ' Pt ${ptBar.toStringAsFixed(2)} bar przekracza maksimum.' : ''}',
        '$sigma ($pct % of yield). Max Pt = lesser of 1.33 · P and the pressure '
            'at $limitPct % of yield = $limitText bar.'
            '${ptBar > (limitBar ?? double.infinity) ? ' Pt ${ptBar.toStringAsFixed(2)} bar exceeds the maximum.' : ''}',
      );
      return over || ptBar > (limitBar ?? double.infinity)
          ? _SheetWarning(text: text)
          : Text(text, style: const TextStyle(color: _kGreen, fontSize: 11));
    }
    if (over) {
      return _SheetWarning(
        text: _tr(
          '$sigma > Re ${yieldMpa.toStringAsFixed(0)} MPa. Wg §345.2.1(a) '
              'Pt można obniżyć do $limitText bar'
              '${atLowPoint ? ' (w najniższym punkcie)' : ''} — decyzja inżyniera.',
          '$sigma > yield ${yieldMpa.toStringAsFixed(0)} MPa. Per §345.2.1(a) '
              'Pt may be reduced to $limitText bar'
              '${atLowPoint ? ' (at the lowest point)' : ''} — '
              "the engineer's decision.",
        ),
      );
    }
    return Text(
      _tr('$sigma ($pct % Re)', '$sigma ($pct % of yield)'),
      style: const TextStyle(color: _kGreen, fontSize: 11),
    );
  }

  /// The arithmetic with the numbers in, e.g.
  /// `Pt = 1.5 · 10.00 · 1.20 = 18.00 bar`.
  static String _calcLine(PressureTestResult r) {
    final p = r.preset;
    String n(double v) {
      final s = v.toString();
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    final design = r.designBar.toStringAsFixed(2);
    final pt = r.testPressureBar.toStringAsFixed(2);
    final ratio = r.ratioApplied.toStringAsFixed(2);
    final floor = p.floorFactor;
    if (floor != null) {
      final a = p.factor * r.designBar * r.ratioApplied;
      final b = floor * r.designBar;
      return 'Pt = max(${n(p.factor)} · $design · $ratio; ${n(floor)} · $design)'
          ' = max(${a.toStringAsFixed(2)}; ${b.toStringAsFixed(2)}) = $pt bar';
    }
    final ratioPart = p.ratioSymbol == null ? '' : ' · $ratio';
    return 'Pt = ${n(p.factor)} · $design$ratioPart = $pt bar';
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
    // Temperature correction (ST/S, f_test/f, LSR) — only for presets that
    // use one. Empty field = 1.0.
    final usesRatio = _preset.ratioSymbol != null;
    final ratioInput = usesRatio ? _p(_ratioCtrl) : null;
    final ratioErr = usesRatio ? _ratioError(ratioInput) : null;
    // Optional yield check — B31.3 hydro §345.2.1(a) (σ ≤ Re), B31.3
    // pneumatic §345.5.4 (≤ 90 % Re), EN 13480-5 (f_test — to be confirmed
    // in the standard, shown as σ/Re only).
    final yieldCheck = presetHasYieldCheck(_preset);
    final yieldInput = yieldCheck ? _p(_yieldCtrl) : null;
    final yieldErr = yieldCheck ? _yieldError(yieldInput) : null;
    final yieldFraction = yieldFractionLimit(_preset);
    // Water column — hydrostatic presets only (gas head is negligible).
    final hydro = !_preset.isPneumatic;
    final highM = hydro ? _p(_highCtrl) : null;
    final lowM = hydro ? _p(_lowCtrl) : null;
    final highErr = hydro ? _heightError(_highCtrl, highM) : null;
    final lowErr = hydro ? _heightError(_lowCtrl, lowM) : null;

    PressureTestResult? calc;
    if (design != null && design > 0 && designErr == null && ratioErr == null) {
      calc = computeTestPressure(
        preset: _preset,
        designBar: design,
        stressRatio: ratioInput ?? 1.0,
      );
      testPressure = calc.testPressureBar;
    }
    HydrostaticHeadResult? head;
    if (calc != null &&
        hydro &&
        highErr == null &&
        lowErr == null &&
        ((highM ?? 0) > 0 || (lowM ?? 0) > 0)) {
      head = hydrostaticHead(
        ptBar: calc.testPressureBar,
        highestAboveGaugeM: highM ?? 0,
        lowestBelowGaugeM: lowM ?? 0,
      );
    }
    // The highest pressure in the system: Pt, or the low point with the
    // water column on top.
    final maxPointBar = head?.lowestPointBar ?? calc?.testPressureBar;
    double? hoopMpa, ptAtYieldBar;
    if (calc != null &&
        maxPointBar != null &&
        yieldInput != null &&
        yieldInput > 0 &&
        yieldErr == null &&
        id != null &&
        od != null &&
        wall != null) {
      hoopMpa = hoopStressMpa(pressureBar: maxPointBar, odMm: od, wallMm: wall);
      ptAtYieldBar = pressureAtHoopStressBar(
          stressMpa: yieldInput * (yieldFraction ?? 1.0),
          odMm: od,
          wallMm: wall);
    }
    // Pneumatic: max Pt = lesser of 1.33·P and the pressure at 90 % Re.
    final pneuMaxBar = (calc != null &&
            _preset.isPneumatic &&
            calc.maxTestPressureBar != null &&
            ptAtYieldBar != null)
        ? math.min(calc.maxTestPressureBar!, ptAtYieldBar)
        : null;
    final minHold = _preset.minHoldMinutes;
    final minHoldText = minHold == null
        ? _tr('wg procedury', 'per procedure')
        : '${minHold.toStringAsFixed(0)} min';
    final holdRef = _preset.holdClause ?? _preset.reference;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Próba ciśnieniowa', 'Pressure test')),
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
                    design: design, calc: calc,
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
                    design: design, calc: calc,
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
              'BHP: medium pod ciśnieniem ma dużą energię. Strefę testu '
              'oznakuj i wygrodź, ludzie poza strefą, zawory '
              'odpowietrzające na najwyższych punktach, manometr '
              'kalibrowany. Procedurę pisze inżynier QC. Minimalny czas '
              'pod ciśnieniem próby: $minHoldText ($holdRef).',
              'SAFETY: the pressurised medium carries significant energy. '
              'Mark and cordon off the test area, keep people out, fit '
              'vents at high points, use a calibrated gauge. The QC '
              'engineer writes the procedure. Minimum hold at test '
              'pressure: $minHoldText ($holdRef).',
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
                  helper: _preset.pressureSymbol == 'P'
                      ? null
                      : _tr('= ${_preset.pressureSymbol} w normie',
                          '= ${_preset.pressureSymbol} in the code'),
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
          const SizedBox(height: 14),
          _SectionHeader(_tr('NORMA I RODZAJ PRÓBY', 'CODE AND TEST TYPE')),
          const SizedBox(height: 8),
          // Each preset carries its own formula and clause — the old chips
          // labelled 1.43× as "B31.1 steam" (it is PED/EN 13480-5) and 1.3× as
          // "PED gas" (it is ASME VIII-1 UG-99 hydro).
          for (final p in PressureTestPreset.values) ...[
            _PresetTile(
              title: _presetTitle(p),
              formula: '${p.formula(decimalSeparator: '.')}  ·  ${p.reference}',
              pneumatic: p.isPneumatic,
              selected: _preset == p,
              onTap: () {
                if (_preset == p) return;
                setState(() => _preset = p);
                debugPrint('[hydrotest] preset → ${p.id}');
              },
            ),
            const SizedBox(height: 6),
          ],
          if (_preset.isPneumatic) ...[
            const SizedBox(height: 4),
            _SafetyHoldBanner(
              text: _tr(
                'PRÓBA PNEUMATYCZNA: sprężony gaz magazynuje wielokrotnie więcej '
                'energii niż woda przy tym samym ciśnieniu — rozszczelnienie '
                'działa jak wybuch, z odłamkami. Tylko gdy próba wodna jest '
                'niewykonalna, na podstawie procedury i zgody inżyniera: zawór '
                'bezpieczeństwa, stopniowe podnoszenie ciśnienia, strefa '
                'wykluczenia, sprawdzenie ryzyka kruchego pękania '
                '(ASME B31.3 §345.5).',
                'PNEUMATIC TEST: compressed gas stores many times more energy '
                'than water at the same pressure — a rupture acts like an '
                'explosion, with fragments. Only when a hydrostatic test is '
                'impracticable, under an engineered procedure and approval: '
                'relief valve, stepwise pressurisation, exclusion zone, '
                'brittle-fracture check (ASME B31.3 §345.5).',
              ),
            ),
          ],
          if (usesRatio) ...[
            const SizedBox(height: 4),
            _NumField(
              ctrl: _ratioCtrl,
              label: _ratioLabel(_preset),
              hint: '1.0',
              onChanged: () => setState(() {}),
              errorText: ratioErr,
              textInputAction: TextInputAction.next,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _ratioHelp(_preset),
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, height: 1.35),
              ),
            ),
            if (calc != null && calc.ratioCapped)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _SheetWarning(
                  text: _tr(
                    '${_preset.ratioSymbol} > ${_preset.ratioCap} — przyjęto '
                    '${_preset.ratioCap} (${_preset.reference}).',
                    '${_preset.ratioSymbol} > ${_preset.ratioCap} — '
                    '${_preset.ratioCap} used (${_preset.reference}).',
                  ),
                ),
              ),
            if (ratioInput != null && ratioErr == null && ratioInput < 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _SheetWarning(
                  text: _tr(
                    '${_preset.ratioSymbol} < 1 — zwykle naprężenie w temp. '
                    'próby nie jest niższe niż w temp. obliczeniowej. Sprawdź '
                    'wartości.',
                    '${_preset.ratioSymbol} < 1 — the stress at test '
                    'temperature is normally not lower than at design '
                    'temperature. Check the values.',
                  ),
                ),
              ),
          ],
          if (hydro) ...[
            const SizedBox(height: 14),
            _SectionHeader(_tr('SŁUP WODY', 'WATER COLUMN')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _NumField(
                  ctrl: _highCtrl,
                  label: _tr('Najwyższy punkt nad manometrem (m)',
                      'Highest point above gauge (m)'),
                  hint: '0',
                  onChanged: () => setState(() {}),
                  errorText: highErr,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  ctrl: _lowCtrl,
                  label: _tr('Najniższy punkt pod manometrem (m)',
                      'Lowest point below gauge (m)'),
                  hint: '0',
                  onChanged: () => setState(() {}),
                  errorText: lowErr,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _tr(
                  'Pt obowiązuje w każdym punkcie układu (B31.1 §137.4.5, '
                  'B31.3 §345.4.2). Woda: 0,0981 bar na metr — manometr poniżej '
                  'najwyższego punktu musi pokazać więcej, a najniższy punkt '
                  'ma jeszcze więcej (to ciśnienie idzie do sprawdzenia Re).',
                  'Pt applies at any point of the system (B31.1 §137.4.5, '
                  'B31.3 §345.4.2). Water: 0.0981 bar per metre — a gauge below '
                  'the highest point must read more, and the lowest point sees '
                  'even more (that pressure goes into the yield check).',
                ),
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, height: 1.35),
              ),
            ),
          ],
          if (yieldCheck) ...[
            const SizedBox(height: 10),
            _NumField(
              ctrl: _yieldCtrl,
              label: _tr('Re w temp. próby (MPa) — opcjonalnie',
                  'Yield at test temp. (MPa) — optional'),
              hint: '240',
              onChanged: () => setState(() {}),
              errorText: yieldErr,
              textInputAction: TextInputAction.next,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                switch (_preset) {
                  PressureTestPreset.b313Pneumatic => _tr(
                      '§345.5.4: Pt nie większe niż mniejsza z wartości: 1,33 · P '
                      'albo ciśnienie dające naprężenie 90 % Re w temp. próby. '
                      'Liczone na wpisanej ściance — norma wymaga ścianki '
                      'minimalnej.',
                      '§345.5.4: Pt not above the lesser of 1.33 · P and the '
                      'pressure giving a stress of 90 % of yield at test '
                      'temperature. Calculated on the entered wall — the code '
                      'wants the minimum wall.'),
                  PressureTestPreset.en13480Hydro => _tr(
                      'EN 13480-5: ciśnienie próby ograniczone naprężeniem '
                      'w warunkach próby wg EN 13480-3 (f_test). Dokładna granica '
                      '— do potwierdzenia w normie; aplikacja pokazuje σ / Re. '
                      'Liczone na wpisanej ściance.',
                      'EN 13480-5: the test pressure is limited by the stress in '
                      'test conditions per EN 13480-3 (f_test). The exact limit '
                      '— to be confirmed in the standard; the app shows σ / Re. '
                      'Calculated on the entered wall.'),
                  _ => _tr(
                      '§345.2.1(a): jeśli Pt dałoby naprężenie obwodowe lub '
                      'wzdłużne powyżej Re w temp. próby albo ciśnienie > 1,5 × '
                      'rating komponentu (np. kołnierza), Pt można obniżyć do tej '
                      'granicy. Liczone na wpisanej ściance — norma wymaga ścianki '
                      'minimalnej.',
                      '§345.2.1(a): if Pt would produce a hoop or longitudinal '
                      'stress above the yield strength at test temperature, or '
                      'exceed 1.5 × a component rating (e.g. a flange), Pt may be '
                      'reduced to that limit. Calculated on the entered wall — the '
                      'code wants the minimum wall.'),
                },
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, height: 1.35),
              ),
            ),
            if (hoopMpa != null && ptAtYieldBar != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _yieldResult(
                  hoopMpa: hoopMpa,
                  yieldMpa: yieldInput!,
                  fraction: yieldFraction,
                  limitBar: _preset.isPneumatic ? pneuMaxBar : ptAtYieldBar,
                  ptBar: calc!.testPressureBar,
                  atLowPoint: head != null && (lowM ?? 0) > 0,
                ),
              ),
          ],

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
                  if (testPressure != null && calc != null) ...[
                    _ResRow(
                      label: _tr('Ciśnienie testowe', 'Test pressure'),
                      value: '${testPressure.toStringAsFixed(2)} bar',
                      sub: '= ${(testPressure / 10).toStringAsFixed(3)} MPa  '
                          '= ${(testPressure * 14.5038).toStringAsFixed(0)} psi',
                      color: _kOrange,
                      big: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_calcLine(calc)}  (${_preset.reference})',
                        style: const TextStyle(color: _kMuted, fontSize: 11),
                      ),
                    ),
                    if (calc.maxTestPressureBar != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _tr(
                            'Maks.: ${_preset.maxFactor} · P = '
                            '${calc.maxTestPressureBar!.toStringAsFixed(2)} bar '
                            'lub ciśnienie dające 90 % Re — mniejsza z wartości '
                            '(${_preset.clause}).',
                            'Max: ${_preset.maxFactor} · P = '
                            '${calc.maxTestPressureBar!.toStringAsFixed(2)} bar '
                            'or the pressure giving 90 % of yield — whichever '
                            'is lower (${_preset.clause}).',
                          ),
                          style: const TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ),
                  ],
                  if (head != null) ...[
                    const Divider(height: 18, color: _kBorder),
                    _ResRow(
                      label: _tr('Odczyt manometru — min.',
                          'Gauge reading — min.'),
                      value: '${head.gaugeReadingBar.toStringAsFixed(2)} bar',
                      sub: _tr(
                          'Pt + słup wody ${(highM ?? 0).toStringAsFixed(1)} m'
                              ' · najniższy punkt: ${head.lowestPointBar.toStringAsFixed(2)} bar',
                          'Pt + water column ${(highM ?? 0).toStringAsFixed(1)} m'
                              ' · lowest point: ${head.lowestPointBar.toStringAsFixed(2)} bar'),
                      color: _kOrange,
                      big: false,
                    ),
                  ],
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
                    value: minHoldText,
                    sub: _tr('wg $holdRef', 'per $holdRef'),
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
              'Zapisana próba zostaje w telefonie: projekt, pakiet, system/linia, '
              'data, norma, medium, manometr i zawór bezpieczeństwa, zmierzone '
              'ciśnienia, temperatury i czas, wynik i świadek — z protokołem '
              'PDF do podpisu.',
              'A saved test stays on the phone: project, package, system/line, '
              'date, code, medium, gauge and relief valve, measured pressures, '
              'temperatures and hold, result and witness — with a PDF protocol '
              'to sign.',
            ),
            style: const TextStyle(color: _kMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                // Saving needs a test pressure: a protocol whose central
                // number is blank is not a protocol.
                onPressed: (calc == null || _busy)
                    ? null
                    : () => _openSaveSheet(
                          od: od,
                          wall: wall,
                          lengthM: lengthM,
                          calc: calc,
                          stressRatio: ratioInput,
                          volL: volL,
                          head: head,
                          highM: highM,
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
    required PressureTestResult? calc,
    required double? stressRatio,
    required double? volL,
    required HydrostaticHeadResult? head,
    required double? highM,
  }) async {
    if (calc == null) return;
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
          testPressureBar: calc.testPressureBar,
          preset: calc.preset,
          stressRatio: stressRatio,
          gaugeTargetBar: head?.gaugeReadingBar ?? calc.testPressureBar,
          designBar: calc.designBar,
          headNote: head == null
              ? null
              : 'Słup wody / water column: najwyższy punkt '
                  '${highM!.toStringAsFixed(1)} m nad manometrem — wymagany '
                  'odczyt ≥ ${head.gaugeReadingBar.toStringAsFixed(2)} bar; '
                  'najniższy punkt ${head.lowestPointBar.toStringAsFixed(2)} bar. / '
                  'highest point ${highM.toStringAsFixed(1)} m above the gauge — '
                  'required reading ≥ ${head.gaugeReadingBar.toStringAsFixed(2)} bar.',
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
      designBar: calc.designBar,
      // Pt / P — the effective multiplier, so B31.3 with ST/S = 1.2 files
      // 1.8, not the bare 1.5 that no longer produces the printed pressure.
      factor: calc.effectiveFactor,
      testPressureBar: calc.testPressureBar,
      volumeL: volL,
      notes: draft.notes,
      // Protocol fields — schema v19 columns (hydrotest_protocol_meta.dart).
      meta: draft.meta,
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
    required PressureTestResult? calc,
    required double? testPressure,
    required double? volL,
    required double flowLpm,
    required double? fillMin,
  }) async {
    final buf = StringBuffer();
    buf.writeln(_tr('Próba ciśnieniowa — raport',
        'Pressure test — report'));
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
    }
    if (calc != null) {
      buf.writeln('${_tr('Norma', 'Code')}: ${_presetTitle(calc.preset)} '
          '(${calc.preset.reference})');
      buf.writeln(_calcLine(calc));
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
    final minHold = _preset.minHoldMinutes;
    buf.writeln('${_tr('Min. czas próby', 'Min. hold time')}: '
        '${minHold == null ? _tr('wg procedury', 'per procedure') : '${minHold.toStringAsFixed(0)} min'}'
        ' (${_preset.holdClause ?? _preset.reference})');
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
    required PressureTestResult? calc,
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
      parts.add('Pd=${design.toStringAsFixed(1)}bar');
    }
    if (calc != null) {
      final p = calc.preset;
      parts.add(p.ratioSymbol == null
          ? p.reference
          : '${p.reference} ${p.ratioSymbol}=${calc.ratioApplied.toStringAsFixed(2)}');
    }
    if (testPressure != null) {
      parts.add('Pt=${testPressure.toStringAsFixed(1)}bar');
    }
    if (volL != null) parts.add('V=${volL.toStringAsFixed(1)}L');
    if (fillMin != null) {
      parts.add('fill≈${fillMin.toStringAsFixed(1)}min@${flowLpm.toStringAsFixed(0)}L/min');
    }
    final minHold = _preset.minHoldMinutes;
    if (minHold != null) parts.add('hold≥${minHold.toStringAsFixed(0)}min');
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
  final String? helper;
  final VoidCallback onChanged;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  // P1-30: per-field errorText — wstrzykiwany z _HydrotestScreenState.
  final String? errorText;
  /// Temperatures may be below zero (outdoor test in winter) — minus key.
  final bool signed;
  const _NumField({
    required this.ctrl,
    required this.label,
    required this.onChanged,
    this.hint,
    this.helper,
    this.textInputAction,
    this.onSubmitted,
    this.errorText,
    this.signed = false,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: numberKeyboard(signed: signed),
      textInputAction: textInputAction,
      inputFormatters: numberInputFormatters(signed: signed),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
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

/// One code preset in the picker: name on the first line, formula and clause
/// on the second — so the multiplier can never again be shown under the wrong
/// code's name.
class _PresetTile extends StatelessWidget {
  final String title;
  final String formula;
  final bool pneumatic;
  final bool selected;
  final VoidCallback onTap;
  const _PresetTile({
    required this.title,
    required this.formula,
    required this.pneumatic,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final accent = pneumatic ? _kRed : _kOrange;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          if (!selected) Haptic.tap();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : _kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? accent : _kBorder,
                width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? accent : _kMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: selected ? accent : _kSec,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(formula,
                        style: const TextStyle(color: _kMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
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

  /// Protocol fields the record has no columns for (company, project, test
  /// package, P&ID/ISO, medium, preset, ST/S, metal temperature, gauge range
  /// and calibration, relief valve, protocol no./revision).
  final HydrotestProtocolMeta meta;

  const _HydrotestDraft({
    required this.systemName,
    required this.date,
    required this.gauge,
    required this.result,
    required this.meta,
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
///
/// MEASURED fields (start/end pressure, temperatures, hold time) open EMPTY.
/// The calculated test pressure and the code's minimum hold are shown as
/// hints only: a pre-filled value that nobody overwrote would print on the
/// protocol as if it had been read off the gauge.
class _HydrotestSaveSheet extends StatefulWidget {
  /// Pressure unit the calculator screen was set to — the gauge fields open in
  /// the same unit so the welder does not switch context mid-test.
  final String initialUnit;

  /// Calculated test pressure in bar — shown as the hint of the "start
  /// pressure" field, never as its value.
  final double testPressureBar;

  /// Code preset the test pressure was calculated to.
  final PressureTestPreset preset;

  /// Stress ratio typed into the calculator (null = 1.0 / not used).
  final double? stressRatio;

  /// Minimum gauge reading [bar]: Pt, or Pt + the water column when the
  /// gauge sits below the highest point (B31.1 §137.4.5 „at any point”).
  final double gaugeTargetBar;

  /// Design pressure P [bar] — the pneumatic upper limit is maxFactor·P.
  final double designBar;

  /// Line appended to the notes when the water column was used, so the
  /// protocol states the required gauge reading.
  final String? headNote;

  const _HydrotestSaveSheet({
    required this.initialUnit,
    required this.testPressureBar,
    required this.preset,
    required this.stressRatio,
    required this.gaugeTargetBar,
    required this.designBar,
    this.headNote,
  });

  @override
  State<_HydrotestSaveSheet> createState() => _HydrotestSaveSheetState();
}

class _HydrotestSaveSheetState extends State<_HydrotestSaveSheet> {
  // Project / document
  final _companyCtrl = TextEditingController();
  final _projectCtrl = TextEditingController();
  final _packageCtrl = TextEditingController();
  final _drawingsCtrl = TextEditingController();
  final _protocolNoCtrl = TextEditingController();
  final _revisionCtrl = TextEditingController();
  // Identification
  final _systemCtrl = TextEditingController();
  final _mediumCtrl = TextEditingController();
  // Gauge and relief
  final _gaugeCtrl = TextEditingController();
  final _gaugeRangeCtrl = TextEditingController();
  final _calDueCtrl = TextEditingController();
  final _reliefCtrl = TextEditingController();
  // Measured — all start EMPTY (see the class doc).
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _metalTempCtrl = TextEditingController();
  final _holdCtrl = TextEditingController();
  // Result
  final _witnessCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late final TextEditingController _dateCtrl;

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
  }

  @override
  void dispose() {
    for (final c in [
      _companyCtrl, _projectCtrl, _packageCtrl, _drawingsCtrl,
      _protocolNoCtrl, _revisionCtrl, _systemCtrl, _mediumCtrl, _gaugeCtrl,
      _gaugeRangeCtrl, _calDueCtrl, _reliefCtrl, _startCtrl, _endCtrl,
      _tempCtrl, _metalTempCtrl, _holdCtrl, _witnessCtrl, _notesCtrl,
      _dateCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _today() => _iso(DateTime.now());

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  double? _num(TextEditingController c) => c.text.trim().isEmpty
      ? null
      : parseDecimal(c.text);

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

  Future<void> _pickDate(TextEditingController ctrl,
      {required int yearsBack, required int yearsAhead}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text.trim()) ?? now,
      firstDate: DateTime(now.year - yearsBack),
      lastDate: DateTime(now.year + yearsAhead),
    );
    if (picked == null) return;
    setState(() => ctrl.text = _iso(picked));
  }

  /// Manometr z rejestru przyrządów (v27): wypełnia „nr / świadectwo"
  /// i termin kalibracji — protokół nazywa konkretny, wzorcowany manometr.
  Future<void> _pickGaugeFromRegister() async {
    List<Instrument> gauges;
    try {
      gauges = (await InstrumentDao().listAll())
          .where((i) => i.kind == InstrumentKind.pressureGauge)
          .toList();
    } catch (_) {
      gauges = const [];
    }
    if (!mounted) return;
    final en = AppLanguageController.isEnglish;
    final today = DateTime.now();
    final picked = await showModalBottomSheet<Instrument>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: gauges.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Text(_tr(
                    'W rejestrze przyrządów nie ma manometrów. Dodaj je w '
                        '„Przyrządy i kalibracja” (menu spawacza).',
                    'There are no pressure gauges in the instrument register. '
                        'Add them in "Instruments and calibration" (welder menu).')),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final g in sortForRegister(gauges, today))
                    ListTile(
                      key: ValueKey('hydro-gauge-${g.id}'),
                      title: Text(g.displayName(en: en)),
                      subtitle: Text(
                        g.dueDate == null
                            ? _tr('brak terminu kalibracji', 'no calibration due date')
                            : '${_tr('kalibracja do', 'calibrated until')} '
                                '${_iso(g.dueDate!)}'
                                '${g.statusOn(today) == InstrumentStatus.overdue ? _tr(' — PO TERMINIE', ' — OVERDUE') : ''}',
                      ),
                      onTap: () => Navigator.pop(ctx, g),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final cert = picked.certificateNo.trim();
      _gaugeCtrl.text = [
        picked.displayName(en: en),
        if (cert.isNotEmpty) _tr('św. $cert', 'cert. $cert'),
      ].join(' / ');
      final due = picked.dueDate;
      if (due != null) _calDueCtrl.text = _iso(due);
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
        notes: [
          if (widget.headNote != null) widget.headNote!,
          if (_notesCtrl.text.trim().isNotEmpty) _notesCtrl.text.trim(),
        ].join('\n'),
        meta: HydrotestProtocolMeta(
          company: _companyCtrl.text.trim(),
          project: _projectCtrl.text.trim(),
          testPackage: _packageCtrl.text.trim(),
          drawingRefs: _drawingsCtrl.text.trim(),
          testMedium: _mediumCtrl.text.trim(),
          presetId: widget.preset.id,
          stressRatio:
              widget.preset.ratioSymbol == null ? null : (widget.stressRatio ?? 1.0),
          metalTempC: _num(_metalTempCtrl),
          gaugeRange: _gaugeRangeCtrl.text.trim(),
          gaugeCalibrationDue: _calDueCtrl.text.trim(),
          reliefSetBar: _bar(_reliefCtrl),
          protocolNo: _protocolNoCtrl.text.trim(),
          revision: _revisionCtrl.text.trim(),
        ),
      ),
    );
  }

  Widget _text(
    TextEditingController ctrl,
    String label, {
    String? hint,
    Widget? suffix,
    bool rebuild = false,
  }) =>
      TextField(
        controller: ctrl,
        textInputAction: TextInputAction.next,
        onChanged: rebuild ? (_) => setState(() {}) : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final minHold = preset.minHoldMinutes;
    final hold = _num(_holdCtrl);
    final shortHold = hold != null && minHold != null && hold < minHold;
    final minHoldLabel = minHold == null ? '' : minHold.toStringAsFixed(0);
    final drop = _dropBar;
    final passWithDrop = _result == kHydrotestPass &&
        drop != null &&
        drop > kHydrotestDropEpsilonBar;
    final startBar = _bar(_startCtrl);
    final endBar = _bar(_endCtrl);
    final calculatedHint =
        pressureFromBar(widget.gaugeTargetBar, _unit).toStringAsFixed(2);
    final pressureIssues = checkRecordedStartPressure(
      preset: preset,
      startBar: startBar,
      requiredBar: widget.gaugeTargetBar,
      designBar: widget.designBar,
    );
    final startLow =
        pressureIssues.contains(RecordedPressureIssue.startBelowRequired);
    final startHigh =
        pressureIssues.contains(RecordedPressureIssue.startAboveMax);
    final targetText =
        '${pressureFromBar(widget.gaugeTargetBar, _unit).toStringAsFixed(2)} $_unit';
    final maxText = preset.maxFactor == null
        ? ''
        : '${pressureFromBar(preset.maxFactor! * widget.designBar, _unit).toStringAsFixed(2)} $_unit';
    // B31.3 §345.5.1 — relief valve on a pneumatic test.
    final reliefBar = _bar(_reliefCtrl);
    final reliefMax = pneumaticReliefMaxBar(widget.testPressureBar);
    final reliefTooHigh = preset == PressureTestPreset.b313Pneumatic &&
        reliefBar != null &&
        reliefBar > reliefMax + kRecordedPressureToleranceBar;
    final reliefMaxText =
        '${pressureFromBar(reliefMax, _unit).toStringAsFixed(2)} $_unit';
    // ASME VIII-1 UG-102(b) — gauge range 1.5–4 × test pressure.
    final fullScale =
        gaugeFullScaleBar(_gaugeRangeCtrl.text, defaultUnit: _unit);
    final gaugeOutOfRange = preset == PressureTestPreset.asmeVIII1Hydro &&
        fullScale != null &&
        !gaugeRangeWithinUg102(fullScale, widget.testPressureBar);
    final calDue = _calDueCtrl.text.trim();
    final testDate = _dateCtrl.text.trim();
    final calibrationExpired = _isoDate.hasMatch(calDue) &&
        _isoDate.hasMatch(testDate) &&
        calDue.compareTo(testDate) < 0;
    final ratioText = preset.ratioSymbol == null
        ? ''
        : '  ·  ${preset.ratioSymbol} = '
            '${(widget.stressRatio ?? 1.0).toStringAsFixed(2)}';

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
                'go zapisuje. Pola pomiarowe wpisz z manometru i termometru — '
                'puste pole drukuje się jako „—”, nie jako pomiar.',
                'The entry goes into the register on this phone and can be '
                'printed as a protocol. The PASS/FAIL verdict is the QC '
                "engineer's — the app only records it. Type the measured "
                'fields from the gauge and thermometer — an empty field prints '
                'as "—", not as a reading.',
              ),
              style: const TextStyle(color: _kMuted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 14),

            _SectionHeader(_tr('PROJEKT / DOKUMENT', 'PROJECT / DOCUMENT')),
            const SizedBox(height: 8),
            _text(_companyCtrl, _tr('Firma', 'Company')),
            const SizedBox(height: 10),
            _text(_projectCtrl, _tr('Projekt / klient', 'Project / client')),
            const SizedBox(height: 10),
            _text(_packageCtrl,
                _tr('Nr pakietu testowego', 'Test package no.'),
                hint: _tr('np. TP-101-03', 'e.g. TP-101-03')),
            const SizedBox(height: 10),
            _text(_drawingsCtrl, _tr('P&ID / ISO', 'P&ID / ISO'),
                hint: _tr('np. 101-PI-003 rev B; ISO 101-0042',
                    'e.g. 101-PI-003 rev B; ISO 101-0042')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 2,
                child: _text(
                    _protocolNoCtrl, _tr('Nr protokołu', 'Protocol no.')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _text(_revisionCtrl, _tr('Rewizja', 'Revision'),
                    hint: '0'),
              ),
            ]),

            const SizedBox(height: 16),
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
            _text(
              _dateCtrl,
              _tr('Data próby', 'Test date'),
              hint: 'YYYY-MM-DD',
              rebuild: true,
              suffix: IconButton(
                icon: const Icon(Icons.calendar_month_outlined, size: 20),
                tooltip: _tr('Wybierz datę', 'Pick date'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () =>
                    _pickDate(_dateCtrl, yearsBack: 5, yearsAhead: 1),
              ),
            ),
            const SizedBox(height: 10),
            // Read-only: the code and the ratio come from the calculator, so
            // the protocol cannot claim a code the pressure was not worked to.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF12141C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                '${_tr('Rodzaj próby i norma', 'Test type and code')}: '
                '${preset.isPneumatic ? _tr('pneumatyczna', 'pneumatic') : _tr('hydrostatyczna', 'hydrostatic')}'
                ' — ${preset.reference}$ratioText',
                style: const TextStyle(color: _kSec, fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            _text(_mediumCtrl, _tr('Medium próby', 'Test fluid'),
                hint: preset.isPneumatic
                    ? _tr('np. azot', 'e.g. nitrogen')
                    : _tr('np. woda', 'e.g. water')),

            const SizedBox(height: 16),
            _SectionHeader(
                _tr('MANOMETR I ZABEZPIECZENIE', 'GAUGE AND RELIEF')),
            const SizedBox(height: 8),
            // ASME B31.3 § 345.5.1 wants a calibrated gauge; the protocol has
            // to be able to name which one.
            _text(_gaugeCtrl,
                _tr('Manometr (nr / świadectwo)', 'Gauge (no. / certificate)'),
                hint: _tr('np. M-12 / św. 123/2026', 'e.g. M-12 / cert. 123/2026')),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('hydro-gauge-from-register'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48)),
                onPressed: _pickGaugeFromRegister,
                icon: const Icon(Icons.speed_outlined, size: 18),
                label: Text(_tr(
                    'Z rejestru przyrządów', 'From the instrument register')),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: _text(
                    _gaugeRangeCtrl, _tr('Zakres manometru', 'Gauge range'),
                    hint: _tr('np. 0–25 bar', 'e.g. 0–25 bar'),
                    rebuild: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _text(
                  _calDueCtrl,
                  _tr('Kalibracja ważna do', 'Calibration due'),
                  hint: 'YYYY-MM-DD',
                  rebuild: true,
                  suffix: IconButton(
                    icon: const Icon(Icons.event_available_outlined, size: 20),
                    tooltip: _tr('Wybierz datę', 'Pick date'),
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () =>
                        _pickDate(_calDueCtrl, yearsBack: 3, yearsAhead: 5),
                  ),
                ),
              ),
            ]),
            if (calibrationExpired)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Kalibracja manometru wygasła przed datą próby. '
                    'Zostanie to odnotowane na protokole.',
                    'The gauge calibration expired before the test date. '
                    'It will be noted on the protocol.',
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _NumField(
              ctrl: _reliefCtrl,
              label: _tr('Nastawa zaworu bezpieczeństwa ($_unit)',
                  'Relief valve set pressure ($_unit)'),
              onChanged: () => setState(() {}),
              textInputAction: TextInputAction.next,
            ),
            if (reliefTooHigh)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Nastawa zaworu powyżej Pt + mniejsza z 345 kPa i 10 % Pt '
                    '= $reliefMaxText (ASME B31.3 §345.5.1).',
                    'Relief set pressure above Pt + the lesser of 345 kPa and '
                    '10 % of Pt = $reliefMaxText (ASME B31.3 §345.5.1).',
                  ),
                ),
              ),
            if (gaugeOutOfRange)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Zakres manometru poza 1,5–4 × ciśnienie próby '
                    '(ASME VIII-1 UG-102(b): ok. 2 × Pt).',
                    'Gauge range outside 1.5–4 × the test pressure '
                    '(ASME VIII-1 UG-102(b): about 2 × Pt).',
                  ),
                ),
              ),

            const SizedBox(height: 16),
            _SectionHeader(
                _tr('PRZEBIEG PRÓBY — POMIARY', 'TEST RECORD — MEASURED')),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _NumField(
                    ctrl: _startCtrl,
                    label: _tr('Ciśnienie pocz. ($_unit)',
                        'Start pressure ($_unit)'),
                    // Hint, not value: the calculated pressure is the target,
                    // the field is what the gauge actually showed.
                    hint: _tr('obl. $calculatedHint', 'calc. $calculatedHint'),
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
            if (startLow)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Ciśnienie początkowe poniżej wymaganego ($targetText) — '
                    'próba nie osiągnęła ciśnienia próby. Wynik PASS zostanie '
                    'na protokole oznaczony jako NIEZGODNY Z NORMĄ.',
                    'Start pressure below the required $targetText — the test '
                    'did not reach the test pressure. A PASS result will be '
                    'marked NOT CODE-COMPLIANT on the protocol.',
                  ),
                ),
              ),
            if (startHigh)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Ciśnienie początkowe powyżej maks. ${preset.maxFactor}·P '
                    '= $maxText (${preset.reference}). Zostanie to oznaczone '
                    'na protokole.',
                    'Start pressure above the max ${preset.maxFactor}·P = '
                    '$maxText (${preset.reference}). It will be marked on the '
                    'protocol.',
                  ),
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
                  label: _tr('Temp. wody / otoczenia (°C)',
                      'Fluid / ambient temp. (°C)'),
                  onChanged: () => setState(() {}),
                  textInputAction: TextInputAction.next,
                  signed: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  ctrl: _metalTempCtrl,
                  label: _tr('Temp. metalu (°C)', 'Metal temp. (°C)'),
                  onChanged: () => setState(() {}),
                  textInputAction: TextInputAction.next,
                  signed: true,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _NumField(
              ctrl: _holdCtrl,
              label: _tr('Czas wytrzymania (min)', 'Hold time (min)'),
              hint: minHold == null
                  ? null
                  : 'min. ${minHold.toStringAsFixed(0)}',
              onChanged: () => setState(() {}),
              textInputAction: TextInputAction.next,
            ),
            if (shortHold)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SheetWarning(
                  text: _tr(
                    'Czas wytrzymania krótszy niż $minHoldLabel '
                    'min (${preset.holdClause ?? preset.reference}). '
                    'Zostanie to odnotowane na protokole.',
                    'Hold time shorter than $minHoldLabel min '
                    '(${preset.holdClause ?? preset.reference}). '
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
    final minHold = formatHydrotestHold(hydrotestMinHoldMinutes(record));
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
                if (!hydrotestMeetsMinimumHold(record))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      tr('czas wytrzymania < $minHold',
                          'hold time < $minHold'),
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
