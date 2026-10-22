import '../assistant/core/calculator_result_readback.dart';
// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pipe_schedules.dart';
import '../assistant/core/tool_bridge.dart';
import '../domain/welding/heat_input.dart';
import '../domain/welding/preheat.dart';
import '../domain/wps/wps_record.dart';
import '../features/wps/wps_picker_sheet.dart';
import '../i18n/app_language.dart';
import '../services/material_catalog.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

// Heat input + preheat calculator for arc welding (SMAW / GMAW / FCAW / GTAW / SAW).
// All arithmetic lives in lib/domain/welding/ (heat_input.dart, preheat.dart);
// this screen only parses fields and renders results.
//
// Heat input — two conventions, selectable on screen:
//   EN 1011-1 / EN ISO 15614-1:  Q = k × U × I × 60 / (v × 1000)  [kJ/mm]
//     k per EN 1011-1 Table 1: SAW 1.0; MMA, MIG/MAG, FCAW (incl. 114) 0.8;
//     TIG 0.6.
//   ASME IX QW-409.1(a):         HI = U × I × 60 / v  — NO efficiency factor.
//
// WPS range: empty by default (no verdict until the welder types the range
// from HIS WPS). The range is a hard boundary — no tolerance band.
//
// Preheat — three named sources shown side by side (see preheat.dart):
//   code minimum (ASME B31.3 Tab. 330.1.1, by P-No + thickness), Seferian
//   estimate, and the non-normative CE rule of thumb. Binding: the WPS.
//
// To jest JEDYNY ekran heat input i podgrzewania. Zakładki „Heat Input" i
// „Temperatura" w kalkulatorach spawacza dublowały te obliczenia i zostały
// usunięte; to, czego tu brakowało, przeszło tutaj: η z WPS (nadpisanie
// sprawności procesu), Seferian [C] z grubością, typowa max temperatura
// międzyściegowa i ostrzeżenie CE ≥ 0.45.

const _kBg = Color(0xFF0B0E13);
const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kAccent = Color(0xFFEF5350);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = kTextMut; // token motywu (kontrast ≥ 4,5:1)
const _kGold = Color(0xFFE8C14B);
const _kGreen = Color(0xFF2ECC71);
const _kOrange = Color(0xFFFF8E1E);

class HeatInputScreen extends StatefulWidget {
  /// Source of the "Wybierz WPS" list; `null` = the WPS library
  /// (`WpsDao().listAll()`). Tests pass a list in memory.
  final WpsLoader? wpsLoader;

  const HeatInputScreen({super.key, this.wpsLoader});

  @override
  State<HeatInputScreen> createState() => _HeatInputScreenState();
}

class _HeatInputScreenState extends State<HeatInputScreen>
    with SingleTickerProviderStateMixin, ToolHandleHost<HeatInputScreen>
    implements InputToolHandle, CalculatorResultToolHandle {
  late final TabController _assistantTabs;
  bool _assistantNeedsHydrogen = false;
  static const _chemKeys = {
    'c_pct',
    'mn_pct',
    'cr_pct',
    'mo_pct',
    'v_pct',
    'ni_pct',
    'cu_pct'
  };
  @override
  String get toolId => 'heat_input';
  @override
  Map<String, Object?> get inputFields =>
      Map.unmodifiable(_assistantTabs.index != 0
          ? const <String, Object?>{}
          : {
              'process': _process,
              'standard': _standard.name,
              'volts': parseDecimal(_voltsCtrl.text),
              'amps': parseDecimal(_ampsCtrl.text),
              'travel_mm_min': parseDecimal(_travelCtrl.text),
              if (_etaCtrl.text.trim().isNotEmpty)
                'efficiency': parseDecimal(_etaCtrl.text),
            });
  @override
  HeatInputResultReadback? get questionResult {
    if (_assistantTabs.index != 0) return null;
    final value = _heatInputKjPerMm;
    if (value != null &&
        (!value.isFinite || !_unit.fromKjPerMm(value).isFinite)) {
      return null;
    }
    final asme = _standard == HeatInputStandard.asmeIx;
    return HeatInputResultReadback(
      valueKjPerMm: value,
      displayValue: value == null ? null : double.tryParse(_unit.format(value)),
      unit: _unit,
      efficiency: asme || value == null ? null : _eta,
      efficiencySource: asme
          ? EfficiencyReadbackSource.notUsed
          : _etaOverride == null
              ? EfficiencyReadbackSource.processDefault
              : EfficiencyReadbackSource.explicitOverride,
    );
  }

  @override
  Set<String> get supportedFields => const {
        'volts',
        'amps',
        'travel_mm_min',
        'process',
        'standard',
        'efficiency',
        ..._chemKeys,
        'thickness_mm',
        'grade_key'
      };
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.keys.any((k) =>
        _chemKeys.contains(k) || k == 'thickness_mm' || k == 'grade_key')) {
      final allowed = {..._chemKeys, 'thickness_mm', 'grade_key'};
      final rejected = fields.keys.toSet().difference(allowed);
      for (final k in {..._chemKeys, 'thickness_mm'}) {
        final v = fields[k];
        if (v is! num ||
            !v.isFinite ||
            (k == 'thickness_mm' ? v <= 0 : v < 0 || v > 100)) {
          rejected.add(k);
        }
      }
      final grade = MaterialCatalog.all
          .where((m) => m.key == fields['grade_key'])
          .firstOrNull;
      if (fields.containsKey('grade_key') && grade == null) {
        rejected.add('grade_key');
      }
      if (grade != null) {
        final values = [
          grade.c,
          grade.mn,
          grade.cr,
          grade.mo,
          grade.v,
          grade.ni,
          grade.cu
        ];
        var i = 0;
        for (final k in _chemKeys) {
          if (fields[k] is! num ||
              ((fields[k] as num) - values[i]).abs() > .000001) {
            rejected.add(k);
          }
          i++;
        }
      }
      if (_chemKeys.every((k) => fields[k] is num) &&
          _chemKeys.fold<double>(
                  0, (sum, k) => sum + (fields[k] as num).toDouble()) >
              100) {
        rejected.addAll(_chemKeys);
      }
      if (rejected.isEmpty) {
        final s = seferianPreheat(
            c: (fields['c_pct'] as num).toDouble(),
            mn: (fields['mn_pct'] as num).toDouble(),
            cr: (fields['cr_pct'] as num).toDouble(),
            mo: (fields['mo_pct'] as num).toDouble(),
            ni: (fields['ni_pct'] as num).toDouble(),
            thicknessMm: (fields['thickness_mm'] as num).toDouble());
        if (s == null || !s.preheatC.isFinite || !s.totalCe.isFinite) {
          rejected.add('thickness_mm');
        }
      }
      if (rejected.isNotEmpty || !mounted) {
        return rejected.isEmpty ? fields.keys.toSet() : rejected;
      }
      setState(() {
        final ctrls = [
          _cCtrl,
          _mnCtrl,
          _crCtrl,
          _moCtrl,
          _vCtrl,
          _niCtrl,
          _cuCtrl
        ];
        var i = 0;
        for (final k in _chemKeys) {
          ctrls[i++].text = fields[k].toString();
        }
        _thicknessCtrl.text = fields['thickness_mm'].toString();
        _material = grade;
        _selectedDn = null;
        _selectedSch = null;
        _hintOdMm = null;
        _hintWallMm = null;
        _voltsCtrl.clear();
        _ampsCtrl.clear();
        _travelCtrl.clear();
        _etaCtrl.clear();
        _assistantNeedsHydrogen = true;
        _assistantTabs.index = 1;
      });
      return {};
    }
    final rejected = fields.keys.toSet().difference(supportedFields);
    for (final e in fields.entries) {
      final value = e.value;
      if (e.key == 'process') {
        if (value is! String || WeldingProcess.fromCode(value) == null) {
          rejected.add(e.key);
        }
      } else if (e.key == 'standard') {
        if (!HeatInputStandard.values.any((s) => s.name == value)) {
          rejected.add(e.key);
        }
      } else if (value is! num ||
          !value.isFinite ||
          value <= 0 ||
          (e.key == 'efficiency' && value > 1)) {
        rejected.add(e.key);
      }
    }
    if (rejected.isNotEmpty || !mounted) {
      return rejected.isEmpty ? fields.keys.toSet() : rejected;
    }
    setState(() {
      if (fields['process'] case final String process) {
        if (_process != process) {
          _wpsMinCtrl.clear();
          _wpsMaxCtrl.clear();
          _wpsSource = null;
        }
        _etaCtrl.clear();
        _process = process;
      }
      if (fields['standard'] case final String standard) {
        final next = HeatInputStandard.values.byName(standard);
        if (next != _standard) {
          _wpsMinCtrl.clear();
          _wpsMaxCtrl.clear();
          _wpsSource = null;
        }
        _standard = next;
      }
      if (fields['efficiency'] case final num value) {
        _etaCtrl.text = value.toString();
      }
      if (fields['volts'] case final num value) {
        _voltsCtrl.text = value.toString();
      }
      if (fields['amps'] case final num value) {
        _ampsCtrl.text = value.toString();
      }
      if (fields['travel_mm_min'] case final num value) {
        _travelCtrl.text = value.toString();
      }
      // Results are computed directly by build from these controllers.
      _assistantTabs.index = 0;
    });
    return {};
  }

  // ─── Heat input inputs ──────────────────────────────────────────────────
  final _voltsCtrl = TextEditingController(text: '22');
  final _ampsCtrl = TextEditingController(text: '110');
  final _travelCtrl = TextEditingController(text: '200');
  String _process = 'SMAW';
  HeatInputStandard _standard = HeatInputStandard.en1011;

  /// η (EN 1011-1 k) typed from the WPS — optional. Empty = the process η
  /// from EN 1011-1 Table 1. Cleared on process change: a WPS value belongs
  /// to one process.
  final _etaCtrl = TextEditingController();

  // ─── Pre-heat / CE inputs ───────────────────────────────────────────────
  final _cCtrl = TextEditingController(text: '0.20');
  final _mnCtrl = TextEditingController(text: '1.00');
  final _crCtrl = TextEditingController(text: '0.00');
  final _moCtrl = TextEditingController(text: '0.00');
  final _vCtrl = TextEditingController(text: '0.00');
  final _niCtrl = TextEditingController(text: '0.00');
  final _cuCtrl = TextEditingController(text: '0.00');
  final _thicknessCtrl = TextEditingController(text: '15');

  // WPS range — deliberately EMPTY until the welder types the range from his
  // WPS (audit 2026-09: a default 1.0–2.5 kJ/mm made every process default
  // glow red "OUT of WPS range").
  final _wpsMinCtrl = TextEditingController();
  final _wpsMaxCtrl = TextEditingController();

  /// Jednostka wyniku i zakresu WPS. WPS amerykańskie podają zwykle J/in
  /// (1 kJ/mm = 25,4 kJ/in = 25 400 J/in). Obliczenia zawsze w kJ/mm.
  HeatInputUnit _unit = HeatInputUnit.kjPerMm;

  /// v = L / t — długość ściegu [mm] i czas jarzenia [s] (stoper).
  final _beadLenCtrl = TextEditingController();
  final _arcTimeCtrl = TextEditingController();

  /// WPS the range was taken from ("Wybierz WPS"); cleared when the welder
  /// edits the range by hand or picks another calculation standard.
  WpsRecord? _wpsSource;

  /// Selected material preset (null = manual chemistry). When the welder
  /// picks a grade we fill in every chemistry cell and show the grade's
  /// P-No, code minimum preheat and typical WPS practice. The WPS range is
  /// NOT filled — a catalog "typical window" is not the welder's WPS.
  MaterialSpec? _material;

  // P2-05: DN/SCH picker — heat_input has no OD/wall fields, so we surface
  // the auto-filled values as a hint chip below the material strip. Last
  // pick persists via SharedPreferences so a welder cycling between calcs
  // keeps the same spool size.
  static const String _kPrefsDn = 'heat_input_pipe_dn';
  static const String _kPrefsSch = 'heat_input_pipe_sch';
  int? _selectedDn;
  String? _selectedSch;
  double? _hintOdMm;
  double? _hintWallMm;

  /// Capture the previous chemistry before overwriting with [m]. Returned map
  /// is later used by the Undo SnackBar action so a stray chip tap can be
  /// reversed without re-typing 7 cells.
  Map<TextEditingController, String> _snapshotChemistry() => {
        _cCtrl: _cCtrl.text,
        _mnCtrl: _mnCtrl.text,
        _crCtrl: _crCtrl.text,
        _moCtrl: _moCtrl.text,
        _vCtrl: _vCtrl.text,
        _niCtrl: _niCtrl.text,
        _cuCtrl: _cuCtrl.text,
      };

  void _applyMaterial(MaterialSpec m) {
    final prev = _snapshotChemistry();
    final prevMaterial = _material;
    setState(() {
      _material = m;
      _cCtrl.text = m.c.toStringAsFixed(2);
      _mnCtrl.text = m.mn.toStringAsFixed(2);
      _crCtrl.text = m.cr.toStringAsFixed(2);
      _moCtrl.text = m.mo.toStringAsFixed(2);
      _vCtrl.text = m.v.toStringAsFixed(2);
      _niCtrl.text = m.ni.toStringAsFixed(2);
      _cuCtrl.text = m.cu.toStringAsFixed(2);
    });
    // P1-16: notify + offer Undo so a misclick doesn't silently wipe a custom
    // chemistry the welder spent 60 s entering off a 3.1 cert.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            context.tr(
              pl: 'Nadpisano chemię gatunkiem ${m.key}',
              en: 'Chemistry overwritten with ${m.key}',
            ),
          ),
          action: SnackBarAction(
            label: context.tr(pl: 'Cofnij', en: 'Undo'),
            onPressed: () {
              if (!mounted) return;
              setState(() {
                prev.forEach((ctrl, text) => ctrl.text = text);
                _material = prevMaterial;
              });
            },
          ),
        ),
      );
  }

  /// Clear the selected material chip without touching chemistry — used when
  /// the welder taps an already-selected chip. P1-16.
  void _clearMaterialSelection() {
    setState(() => _material = null);
  }

  // P2-05: restore the last DN/SCH the welder picked so they don't re-tap
  // through 18 sizes every shift.
  Future<void> _restorePipeSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final dn = prefs.getInt(_kPrefsDn);
      final sch = prefs.getString(_kPrefsSch);
      if (dn == null || sch == null) return;
      _applyPipeSize(dn: dn, sch: sch, persist: false);
    } catch (e) {
      debugPrint('[heat_input] restore pipe size failed: $e');
    }
  }

  Future<void> _persistPipeSize(int dn, String sch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPrefsDn, dn);
      await prefs.setString(_kPrefsSch, sch);
    } catch (e) {
      debugPrint('[heat_input] persist pipe size failed: $e');
    }
  }

  /// P2-05: resolve a (DN, SCH) pair against the offline ASME B36.10/19 table
  /// and stash the OD + wall as hint values. heat_input does not have OD/wall
  /// fields of its own, so the result is shown as a read-only hint badge.
  void _applyPipeSize({
    required int dn,
    required String sch,
    bool persist = true,
  }) {
    PipeRow? row;
    for (final r in kPipeWalls) {
      if (r.dn == dn) {
        row = r;
        break;
      }
    }
    if (row == null) return;
    final wall = row.walls[sch];
    if (wall == null) return;
    final od = row.od;
    final prevThickness = _thicknessCtrl.text;
    final wallText = _fmtWall(wall);
    setState(() {
      _selectedDn = dn;
      _selectedSch = sch;
      _hintOdMm = od;
      _hintWallMm = wall;
      // Ścianka z tabeli JEST grubością do obliczeń (Seferian, minimum
      // kodowe) — dawniej była tylko podpowiedzią, a liczyło się 15 mm.
      _thicknessCtrl.text = wallText;
    });
    if (persist) {
      _persistPipeSize(dn, sch);
      if (prevThickness != wallText) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(context.tr(
              pl: 'Grubość do obliczeń: $wallText mm (DN$dn Sch $sch)',
              en: 'Thickness for calculation: $wallText mm (DN$dn Sch $sch)',
            )),
            action: SnackBarAction(
              label: context.tr(pl: 'Cofnij', en: 'Undo'),
              onPressed: () {
                if (!mounted) return;
                setState(() => _thicknessCtrl.text = prevThickness);
              },
            ),
          ));
      }
    }
  }

  static String _fmtWall(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// P2-05: open the DN/SCH picker. Same showModalBottomSheet pattern used
  /// by NpsTableSheet — DN row tap commits, SCH chips above filter on which
  /// schedule (and hide cells where the wall isn't normally produced).
  Future<void> _openPipeSizePicker() async {
    final picked = await showModalBottomSheet<({int dn, String sch})>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DnSchPickerSheet(
        initialDn: _selectedDn,
        initialSch: _selectedSch ?? 'STD',
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    _applyPipeSize(dn: picked.dn, sch: picked.sch);
  }

  void _clearPipeSize() {
    setState(() {
      _selectedDn = null;
      _selectedSch = null;
      _hintOdMm = null;
      _hintWallMm = null;
    });
    // Best-effort wipe of the persisted pick.
    SharedPreferences.getInstance().then((p) {
      p.remove(_kPrefsDn);
      p.remove(_kPrefsSch);
    }).catchError((e) {
      debugPrint('[heat_input] clear pipe size failed: $e');
    });
  }

  /// Wyczyść — wipes all inputs + chip back to factory defaults. P1-04.
  void _resetAll() {
    setState(() {
      _assistantNeedsHydrogen = false;
      _voltsCtrl.text = '22';
      _ampsCtrl.text = '110';
      _travelCtrl.text = '200';
      _process = 'SMAW';
      _standard = HeatInputStandard.en1011;
      _etaCtrl.clear();
      _cCtrl.text = '0.20';
      _mnCtrl.text = '1.00';
      _crCtrl.text = '0.00';
      _moCtrl.text = '0.00';
      _vCtrl.text = '0.00';
      _niCtrl.text = '0.00';
      _cuCtrl.text = '0.00';
      _thicknessCtrl.text = '15';
      _wpsMinCtrl.clear();
      _wpsMaxCtrl.clear();
      _wpsSource = null;
      _material = null;
      // P2-05: Wyczyść also drops the DN/SCH hint so the welder starts
      // from a clean slate.
      _selectedDn = null;
      _selectedSch = null;
      _hintOdMm = null;
      _hintWallMm = null;
    });
  }

  static String _fmtWps(double v) =>
      v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  /// "Wybierz WPS": the range min–max and the calculation standard come from
  /// the WPS library — the range means something only in the WPS's own
  /// convention (EN 1011-1 with η vs ASME IX without).
  Future<void> _pickWps() async {
    final w = await showWpsPickerSheet(context,
        currentId: _wpsSource?.id, load: widget.wpsLoader);
    if (w == null || !mounted) return;
    if (w.heatInputMinKjMm == null && w.heatInputMaxKjMm == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: '${w.displayName} nie ma zakresu energii liniowej — uzupełnij '
              'go w Bibliotece WPS albo wpisz ręcznie.',
          en: '${w.displayName} has no heat input range — add it in the WPS '
              'library or type it by hand.',
        )),
      ));
      return;
    }
    setState(() {
      final min = w.heatInputMinKjMm;
      final max = w.heatInputMaxKjMm;
      _wpsMinCtrl.text = min == null ? '' : _fmtWps(min * _unit.factor);
      _wpsMaxCtrl.text = max == null ? '' : _fmtWps(max * _unit.factor);
      _standard = w.heatInputMethod;
      _wpsSource = w;
    });
  }

  /// Per-process thermal efficiency k — single source of truth is the
  /// [WeldingProcess] enum (EN 1011-1 Table 1), shared with the Welder
  /// calculators screen.
  static final Map<String, double> _efficiency = {
    for (final p in WeldingProcess.values) p.code: p.thermalEfficiency,
  };

  /// η of the selected process (EN 1011-1 Table 1).
  double get _processEta => _efficiency[_process] ?? 0.80;

  /// η typed from the WPS: null when the field is empty, NaN when it is not
  /// a number (the domain then refuses to compute — no silent fallback).
  double? get _etaOverride {
    final t = _etaCtrl.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t) ?? double.nan;
  }

  /// Empty override, or one inside (0; 1] — the range EN 1011-1 allows.
  bool get _etaOverrideValid {
    final k = _etaOverride;
    return k == null || (k.isFinite && k > 0 && k <= 1);
  }

  /// η actually used by the EN 1011-1 formula.
  double get _eta => _etaOverride ?? _processEta;

  // P1-16: sensible default (V, I, travel mm/min) per process. Swapped in when
  // the welder changes process so the fields hold realistic numbers.
  static const Map<String, List<double>> _defaultParams = {
    'SMAW': [22, 110, 200],
    'GMAW': [24, 180, 350],
    'FCAW-G': [26, 200, 320],
    'FCAW-S': [24, 180, 280],
    'GTAW': [12, 100, 90],
    'SAW': [32, 500, 600],
  };

  List<double> _defaultParamsFor(String process) =>
      _defaultParams[process] ?? const [22, 110, 200];

  void _applyDefaultParams(String process) {
    final p = _defaultParamsFor(process);
    _voltsCtrl.text = p[0].toStringAsFixed(0);
    _ampsCtrl.text = p[1].toStringAsFixed(0);
    _travelCtrl.text = p[2].toStringAsFixed(0);
  }

  double _parse(TextEditingController c) => parseDecimal(c.text) ?? 0.0;

  /// Empty field → null (used for the optional WPS bounds).
  double? _parseOptional(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t);
  }

  @override
  void initState() {
    super.initState();
    _assistantTabs = TabController(length: 2, vsync: this);
    // P2-05: rehydrate the last DN/SCH pick so the hint chip shows up
    // immediately on the Preheat tab.
    _restorePipeSize().whenComplete(markReady);
  }

  @override
  void dispose() {
    _assistantTabs.dispose();
    _voltsCtrl.dispose();
    _ampsCtrl.dispose();
    _travelCtrl.dispose();
    _etaCtrl.dispose();
    _cCtrl.dispose();
    _mnCtrl.dispose();
    _crCtrl.dispose();
    _moCtrl.dispose();
    _vCtrl.dispose();
    _niCtrl.dispose();
    _cuCtrl.dispose();
    _thicknessCtrl.dispose();
    _wpsMinCtrl.dispose();
    _wpsMaxCtrl.dispose();
    _beadLenCtrl.dispose();
    _arcTimeCtrl.dispose();
    super.dispose();
  }

  // ─── Computed ────────────────────────────────────────────────────────────
  /// null = nie da się policzyć (np. η z WPS spoza 0–1, zerowa prędkość) —
  /// ekran pokazuje „—” i nie pozwala skopiować wyniku (dawniej „0.00”).
  double? get _heatInputKjPerMm => heatInputKJPerMm(
        volts: _parse(_voltsCtrl),
        amps: _parse(_ampsCtrl),
        travelMmPerMin: _parse(_travelCtrl),
        standard: _standard,
        efficiency: _eta,
      );

  double get _ce => carbonEquivalentIiw(
        c: _parse(_cCtrl),
        mn: _parse(_mnCtrl),
        cr: _parse(_crCtrl),
        mo: _parse(_moCtrl),
        v: _parse(_vCtrl),
        ni: _parse(_niCtrl),
        cu: _parse(_cuCtrl),
      );

  _PreheatView _preheatView() {
    final ce = _ce;
    final t = _parse(_thicknessCtrl);
    final stainless = isStainlessComposition(cr: _parse(_crCtrl));
    final rule = ceRuleOfThumb(ce: ce, thicknessMm: t);
    final seferian = seferianPreheat(
      c: _parse(_cCtrl),
      mn: _parse(_mnCtrl),
      cr: _parse(_crCtrl),
      ni: _parse(_niCtrl),
      mo: _parse(_moCtrl),
      thicknessMm: t,
    );
    final m = _material;
    final codeMin = m == null
        ? null
        : b313CurrentMinPreheatC(
            pNo: m.pNo,
            thicknessMm: t,
            smtsMpa: m.smtsMpa,
            carbonPct: _parse(_cCtrl),
            chromiumPct: _parse(_crCtrl),
          );
    final codeMin2012 = m == null
        ? null
        : b313MinPreheatC(pNo: m.pNo, thicknessMm: t, smtsMpa: m.smtsMpa);
    final crMo = !stainless &&
        (m != null
            ? isCrMoPNo(m.pNo)
            : isCrMoComposition(cr: _parse(_crCtrl), mo: _parse(_moCtrl)));
    // EN 1011-2 zał. C metoda B — Q to energia liniowa wg EN 1011-1 (z η)
    // z pierwszej zakładki, niezależnie od wybranej tam konwencji.
    final qEn = heatInputKJPerMm(
      volts: _parse(_voltsCtrl),
      amps: _parse(_ampsCtrl),
      travelMmPerMin: _parse(_travelCtrl),
      standard: HeatInputStandard.en1011,
      efficiency: _eta,
    );
    final cet = qEn == null || _assistantNeedsHydrogen
        ? null
        : en1011MethodBPreheat(
            c: _parse(_cCtrl),
            mn: _parse(_mnCtrl),
            mo: _parse(_moCtrl),
            cr: _parse(_crCtrl),
            cu: _parse(_cuCtrl),
            ni: _parse(_niCtrl),
            v: _parse(_vCtrl),
            thicknessMm: t,
            hdMlPer100g: _hd,
            heatInputKjMm: qEn,
          );
    return _PreheatView(
      ce: ce,
      thicknessMm: t,
      stainless: stainless,
      crMo: crMo,
      rule: rule,
      seferianC: seferian?.preheatC,
      seferianTotalCe: seferian?.totalCe,
      codeMinC: codeMin,
      codeMin2012C: codeMin2012,
      cet: cet,
      qEnKjMm: qEn,
    );
  }

  /// Wodór dyfundujący HD [ml/100 g] dla metody B (H5 / H10 / H15).
  double _hd = 10;

  String _cetNote(_PreheatView p) {
    if (_assistantNeedsHydrogen) {
      return context.tr(
          pl: 'Nie podano wodoru HD ani parametrów EN dla tego obliczenia. Metoda B nie jest wyznaczona.',
          en: 'No hydrogen HD or EN parameters were supplied for this calculation. Method B has not been calculated.');
    }
    final r = p.cet;
    if (p.qEnKjMm == null || r == null) {
      return context.tr(
        pl: 'Policz najpierw heat input (zakładka 1) — metoda B potrzebuje Q wg EN 1011-1.',
        en: 'Calculate heat input first (tab 1) — method B needs Q per EN 1011-1.',
      );
    }
    final q = p.qEnKjMm!.toStringAsFixed(2);
    final base = context.tr(
      pl: 'CET = ${r.cet.toStringAsFixed(3)} · HD = ${_hd.toStringAsFixed(0)} ml/100 g · Q = $q kJ/mm (EN 1011-1).',
      en: 'CET = ${r.cet.toStringAsFixed(3)} · HD = ${_hd.toStringAsFixed(0)} ml/100 g · Q = $q kJ/mm (EN 1011-1).',
    );
    if (r.outOfRange.isEmpty) return base;
    final why = [
      for (final o in r.outOfRange)
        switch (o) {
          CetOutOfRange.cet =>
            context.tr(pl: 'CET poza 0,2–0,5 %', en: 'CET outside 0.2–0.5 %'),
          CetOutOfRange.thickness => context.tr(
              pl: 'grubość poza 10–90 mm', en: 'thickness outside 10–90 mm'),
          CetOutOfRange.hydrogen => context.tr(
              pl: 'HD poza 1–20 ml/100 g', en: 'HD outside 1–20 ml/100 g'),
          CetOutOfRange.heatInput => context.tr(
              pl: 'Q poza 0,5–4,0 kJ/mm', en: 'Q outside 0.5–4.0 kJ/mm'),
          CetOutOfRange.composition => context.tr(
              pl: 'skład poza zakresem metody',
              en: 'chemistry outside the method range'),
        },
    ].join(', ');
    return '$base ${context.tr(pl: 'Poza zakresem stosowania: $why.', en: 'Outside the scope: $why.')}';
  }

  String _ruleNote(CeRuleOfThumb r) {
    switch (r.band) {
      case CeBand.low:
        return r.thickWall
            ? context.tr(
                pl: 'CE < 0.35, ścianka ≥ 25 mm — podgrzewanie ostrożnościowe',
                en: 'CE < 0.35, wall ≥ 25 mm — precautionary preheat')
            : context.tr(
                pl: 'CE < 0.35, cienka ścianka — zwykle bez podgrzewania',
                en: 'CE < 0.35, thin wall — usually no preheat');
      case CeBand.medium:
        return context.tr(
            pl: 'CE 0.35–0.45 — niskie podgrzewanie (pasmo 100–150 °C)',
            en: 'CE 0.35–0.45 — low preheat (band 100–150 °C)');
      case CeBand.high:
        return context.tr(
            pl: 'CE 0.45–0.55 — średnie podgrzewanie (150–200 °C) + elektrody niskowodorowe',
            en: 'CE 0.45–0.55 — medium preheat (150–200 °C) + low-hydrogen electrodes');
      case CeBand.critical:
        return context.tr(
            pl: 'CE > 0.55 — wysokie podgrzewanie (200–300 °C), rozważ PWHT',
            en: 'CE > 0.55 — high preheat (200–300 °C), consider PWHT');
    }
  }

  String get _disclaimer => context.tr(
        pl: 'Wynik pomocniczy — wiąże WPS / specyfikacja projektu.',
        en: 'Auxiliary result — the WPS / project specification is binding.',
      );

  @override
  Widget build(BuildContext context) {
    final hi = _heatInputKjPerMm;
    // Pola zakresu są w wybranej jednostce; porównanie zawsze w kJ/mm.
    final wpsMin = _parseOptional(_wpsMinCtrl) == null
        ? null
        : _parseOptional(_wpsMinCtrl)! / _unit.factor;
    final wpsMax = _parseOptional(_wpsMaxCtrl) == null
        ? null
        : _parseOptional(_wpsMaxCtrl)! / _unit.factor;
    final verdict = hi != null && hi > 0
        ? checkWpsRange(hi, min: wpsMin, max: wpsMax)
        : WpsRangeVerdict.notSet;
    final preheat = _preheatView();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCard,
          // Ta sama nazwa co kafel w menu SPAWACZ. Bez znaczka „PRO" —
          // narzędzie jest darmowe, a płatne rzeczy są ukryte całkowicie.
          title: Text(
            context.tr(pl: 'Heat input i CE', en: 'Heat input and CE'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            // P1-26: one-tap share of the full trace (HI + CE + Preheat) so a
            // welder can paste it straight into a WhatsApp to the inspector.
            IconButton(
              tooltip: context.tr(pl: 'Udostępnij wynik', en: 'Share result'),
              icon: const Icon(Icons.ios_share),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _shareTrace(hi, preheat),
            ),
            // P1-04: Wyczyść — resets all controllers + clears material chip.
            IconButton(
              tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
              icon: const Icon(Icons.refresh),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _resetAll,
            ),
            // P1-14: shared HelpButton — own sheet since heat input and
            // preheat left the welder calculators screen.
            HelpButton(help: kHelpHeatInput),
          ],
          bottom: TabBar(
            controller: _assistantTabs,
            isScrollable: false,
            indicatorColor: _kAccent,
            tabs: [
              Tab(text: context.tr(pl: 'Heat input', en: 'Heat input')),
              Tab(text: context.tr(pl: 'Preheat / CE', en: 'Preheat / CE')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _assistantTabs,
          children: [
            _heatInputTab(hi, wpsMin, wpsMax, verdict),
            _preheatTab(preheat),
          ],
        ),
      ),
    );
  }

  /// Which η the result used — process η (EN 1011-1), η typed from the WPS,
  /// or none (ASME IX). Never prints NaN for a mistyped η.
  String _efficiencyNote(bool asme) {
    if (asme) {
      return context.tr(
        pl: 'ASME IX QW-409.1: bez współczynnika sprawności (energia łuku).',
        en: 'ASME IX QW-409.1: no efficiency factor (arc energy).',
      );
    }
    if (!_etaOverrideValid) {
      return context.tr(
        pl: 'Sprawdź η z WPS — musi być w zakresie 0–1.',
        en: 'Check η from WPS — it must be within 0–1.',
      );
    }
    if (_etaOverride != null) {
      final k = _eta.toStringAsFixed(2);
      final p = _processEta.toStringAsFixed(2);
      return context.tr(
        pl: 'η z WPS: $k (EN 1011-1 dla $_process: $p)',
        en: 'η from WPS: $k (EN 1011-1 for $_process: $p)',
      );
    }
    return context.tr(
      pl: 'Efektywność łuku $_process: ${(_eta * 100).toStringAsFixed(0)}% (EN 1011-1)',
      en: 'Arc efficiency $_process: ${(_eta * 100).toStringAsFixed(0)}% (EN 1011-1)',
    );
  }

  String _fmtRange(double? min, double? max) {
    final lo = min == null ? '—' : _unit.format(min);
    final hi = max == null ? '—' : _unit.format(max);
    return '$lo – $hi ${_unit.label}';
  }

  /// Zmiana jednostki przelicza wpisany zakres WPS (pola są w jednostce).
  void _setUnit(HeatInputUnit u) {
    if (u == _unit) return;
    String conv(TextEditingController c) {
      final v = _parseOptional(c);
      if (v == null) return c.text;
      return _fmtWps(u.fromKjPerMm(_unit.toKjPerMm(v)));
    }

    setState(() {
      _wpsMinCtrl.text = conv(_wpsMinCtrl);
      _wpsMaxCtrl.text = conv(_wpsMaxCtrl);
      _unit = u;
    });
  }

  double? get _measuredSpeed => travelSpeedMmPerMin(
        lengthMm: _parseOptional(_beadLenCtrl) ?? 0,
        seconds: _parseOptional(_arcTimeCtrl) ?? 0,
      );

  // ─── Tab 1: Heat input ──────────────────────────────────────────────────
  Widget _heatInputTab(
      double? hi, double? wpsMin, double? wpsMax, WpsRangeVerdict verdict) {
    // The WPS range is a hard boundary: in range = green, outside = red.
    // No verdict (neutral colour) until the welder enters the range.
    final Color okColour;
    final IconData icon;
    final String verdictText;
    final range = _fmtRange(wpsMin, wpsMax);
    switch (verdict) {
      case WpsRangeVerdict.notSet when hi == null:
        okColour = _kTextMut;
        icon = Icons.block;
        verdictText = context.tr(
          pl: 'Brak wyniku — popraw dane (η z WPS 0–1, prędkość > 0).',
          en: 'No result — fix the inputs (η from WPS 0–1, travel speed > 0).',
        );
      case WpsRangeVerdict.notSet:
        okColour = _kOrange;
        icon = Icons.info_outline;
        verdictText = context.tr(
          pl: 'Wpisz zakres z WPS, aby porównać (min i/lub max).',
          en: 'Enter the WPS range to compare (min and/or max).',
        );
      case WpsRangeVerdict.invalidRange:
        okColour = _kGold;
        icon = Icons.help_outline;
        verdictText = context.tr(
          pl: 'Sprawdź zakres WPS — min większe od max albo wartość ujemna.',
          en: 'Check the WPS range — min above max or a negative value.',
        );
      case WpsRangeVerdict.inRange:
        okColour = _kGreen;
        icon = Icons.check_circle_outline;
        verdictText = context.tr(
          pl: '✓ W zakresie WPS ($range)',
          en: '✓ Within WPS range ($range)',
        );
      case WpsRangeVerdict.belowMin:
      case WpsRangeVerdict.aboveMax:
        okColour = _kAccent;
        icon = Icons.warning_amber_outlined;
        verdictText = context.tr(
          pl: '⚠ POZA zakresem WPS ($range) — koryguj parametry',
          en: '⚠ OUT of WPS range ($range) — adjust parameters',
        );
    }
    final asme = _standard == HeatInputStandard.asmeIx;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionCard(
          title: context.tr(pl: 'Parametry łuku', en: 'Arc parameters'),
          child: Column(
            children: [
              _ProcessSelector(
                value: _process,
                efficiency: _efficiency,
                onChanged: (v) => setState(() {
                  // η z WPS dotyczy jednego procesu — przy zmianie procesu
                  // wraca η z EN 1011-1.
                  if (v != _process) _etaCtrl.clear();
                  _process = v;
                  // P1-16: swap sensible defaults for the new process.
                  _applyDefaultParams(v);
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Napięcie', en: 'Voltage'),
                      ctrl: _voltsCtrl,
                      suffix: 'V',
                      rejectNegative: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Prąd', en: 'Current'),
                      ctrl: _ampsCtrl,
                      suffix: 'A',
                      rejectNegative: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _NumField(
                label: context.tr(pl: 'Prędkość spawania', en: 'Travel speed'),
                ctrl: _travelCtrl,
                suffix: 'mm/min',
                rejectNegative: true,
                rejectZero: true,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              // v = L / t: spawacz ma zwykle miarkę i stoper, nie mm/min.
              Text(
                context.tr(
                  pl: 'Albo z pomiaru: długość ściegu i czas jarzenia łuku',
                  en: 'Or from a measurement: bead length and arc time',
                ),
                style: const TextStyle(fontSize: 11, color: _kTextSec),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      label:
                          context.tr(pl: 'Długość ściegu', en: 'Bead length'),
                      ctrl: _beadLenCtrl,
                      suffix: 'mm',
                      rejectNegative: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Czas jarzenia', en: 'Arc time'),
                      ctrl: _arcTimeCtrl,
                      suffix: 's',
                      rejectNegative: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_measuredSpeed != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48)),
                    onPressed: () => setState(() {
                      _travelCtrl.text = _measuredSpeed!.toStringAsFixed(0);
                    }),
                    icon: const Icon(Icons.speed, size: 18),
                    label: Text(context.tr(
                      pl: 'Wpisz v = ${_measuredSpeed!.toStringAsFixed(0)} mm/min',
                      en: 'Use v = ${_measuredSpeed!.toStringAsFixed(0)} mm/min',
                    )),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        _SectionCard(
          title: context.tr(pl: 'Norma liczenia', en: 'Calculation standard'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('EN 1011-1'),
                    selected: !asme,
                    onSelected: (_) => setState(() {
                      if (_standard != HeatInputStandard.en1011) {
                        _wpsSource = null;
                      }
                      _standard = HeatInputStandard.en1011;
                    }),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  ChoiceChip(
                    label: const Text('ASME IX'),
                    selected: asme,
                    onSelected: (_) => setState(() {
                      if (_standard != HeatInputStandard.asmeIx) {
                        _wpsSource = null;
                      }
                      _standard = HeatInputStandard.asmeIx;
                    }),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                asme
                    ? context.tr(
                        pl: 'ASME IX QW-409.1: HI = U × I × 60 / v — bez współczynnika sprawności.',
                        en: 'ASME IX QW-409.1: HI = U × I × 60 / v — no efficiency factor.',
                      )
                    : context.tr(
                        pl: 'EN 1011-1 / EN ISO 15614-1: Q = η × U × I × 60 / v (η wg procesu).',
                        en: 'EN 1011-1 / EN ISO 15614-1: Q = η × U × I × 60 / v (η by process).',
                      ),
                style: const TextStyle(
                    fontSize: 11, color: _kTextSec, height: 1.4),
              ),
              // η z WPS — tylko EN 1011-1 (ASME IX liczy bez η).
              if (!asme) ...[
                const SizedBox(height: 10),
                _NumField(
                  label: context.tr(
                    pl: 'η z WPS (opcjonalnie)',
                    en: 'η from WPS (optional)',
                  ),
                  ctrl: _etaCtrl,
                  helper: context.tr(
                    pl: 'Puste = η procesu $_process wg EN 1011-1 '
                        '(${_processEta.toStringAsFixed(2)}). Wpisz tylko, gdy WPS podaje inną wartość.',
                    en: 'Empty = η of $_process per EN 1011-1 '
                        '(${_processEta.toStringAsFixed(2)}). Enter only if the WPS states another value.',
                  ),
                  rejectNegative: true,
                  rejectZero: true,
                  maxValue: 1,
                  onChanged: () => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        _SectionCard(
          title: context.tr(
              pl: 'Zakres WPS (${_unit.label})',
              en: 'WPS range (${_unit.label})'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Jednostka wyniku i zakresu — WPS wg ASME zwykle w J/in.
              SegmentedButton<HeatInputUnit>(
                segments: [
                  for (final u in HeatInputUnit.values)
                    ButtonSegment(value: u, label: Text(u.label)),
                ],
                selected: {_unit},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _setUnit(s.first),
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(const Size(48, 48)),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Min', en: 'Min'),
                      ctrl: _wpsMinCtrl,
                      suffix: _unit.label,
                      rejectNegative: true,
                      onChanged: () => setState(() => _wpsSource = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Max', en: 'Max'),
                      ctrl: _wpsMaxCtrl,
                      suffix: _unit.label,
                      rejectNegative: true,
                      onChanged: () => setState(() => _wpsSource = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _pickWps,
                  icon: const Icon(Icons.library_books_outlined, size: 20),
                  label: Text(context.tr(pl: 'Wybierz WPS', en: 'Pick WPS')),
                ),
              ),
              if (_wpsSource != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr(
                      pl: 'Zakres i norma liczenia z ${_wpsSource!.displayName}.',
                      en: 'Range and standard from ${_wpsSource!.displayName}.',
                    ),
                    style: const TextStyle(
                        fontSize: 11, color: _kTextSec, height: 1.4),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Result
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                okColour.withValues(alpha: 0.20),
                okColour.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: okColour.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: okColour, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    context.tr(pl: 'Heat input', en: 'Heat input'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kTextSec,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Tap-target for welders in gloves: 32 px hit, 14 px glyph.
                  InkResponse(
                    onTap: () => _showHeatInputFormulaDialog(context),
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: _kTextMut,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    // P1-16: HI to 2 decimals — matches the precision welders
                    // see on a qualified WPS sheet. No result → „—”, never 0.00.
                    hi == null ? '—' : _unit.format(hi),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: okColour,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _unit.label,
                    style: const TextStyle(
                      fontSize: 16,
                      color: _kTextSec,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                verdictText,
                style: TextStyle(
                  color:
                      verdict == WpsRangeVerdict.notSet ? _kTextSec : okColour,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _efficiencyNote(asme),
                style: TextStyle(
                  color: !asme && !_etaOverrideValid ? _kAccent : _kTextMut,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _disclaimer,
                style: const TextStyle(
                    color: _kTextMut,
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: hi == null
                    ? null
                    : () {
                        copyToClipboard(
                          context,
                          '${_unit.format(hi)} ${_unit.label} ($_process, ${asme ? 'ASME IX' : 'EN 1011-1'})',
                          label: 'HI',
                        );
                      },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(context.tr(pl: 'Kopiuj wynik', en: 'Copy result')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: okColour,
                  side: BorderSide(
                    color: okColour.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        _InfoCard(
          icon: Icons.lightbulb_outline,
          text: context.tr(
            pl: 'Porównuj z WPS liczonym w tej samej konwencji: WPS wg EN ISO 15614-1 '
                'podaje energię z η, WPS wg ASME IX — bez η. '
                'Za wysokie HI = gruboziarnista HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, ryzyko pęknięć wodorowych.',
            en: 'Compare with a WPS written in the same convention: an EN ISO 15614-1 WPS '
                'uses η, an ASME IX WPS does not. '
                'Too high HI = coarse-grain HAZ, low toughness. Too low HI = fast cooling, hydrogen cracking risk.',
          ),
        ),
      ],
    );
  }

  // ─── Tab 2: Preheat / CE ────────────────────────────────────────────────
  Widget _preheatTab(_PreheatView p) {
    final isPl = context.language == AppLanguage.pl;
    final severity = p.ceMethods ? _bandColor(p.rule.band) : _kTextSec;
    final tLabel = p.thicknessMm > 0 ? p.thicknessMm.toStringAsFixed(0) : '—';
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionCard(
          title: context.tr(pl: 'Materiał', en: 'Material'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  pl: 'Wybierz gatunek — chemia uzupełni się sama (typowa, nie z atestu).',
                  en: 'Pick a grade — chemistry auto-fills (typical, not from the MTR).',
                ),
                style: const TextStyle(
                    fontSize: 11, color: _kTextMut, height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in MaterialCatalog.all)
                    Tooltip(
                      // P1-16: per-chip tooltip with the typical practice
                      // note so a welder can scan grade options without
                      // committing to an overwrite.
                      message:
                          '${m.name} · P-No ${m.pNo}\n${isPl ? m.practicePl : m.practiceEn}',
                      child: ChoiceChip(
                        label:
                            Text(m.key, style: const TextStyle(fontSize: 11)),
                        selected: _material?.key == m.key,
                        onSelected: (_) {
                          // P1-16: tap on the already-selected chip clears the
                          // selection without rewriting chemistry.
                          if (_material?.key == m.key) {
                            _clearMaterialSelection();
                          } else {
                            _applyMaterial(m);
                          }
                        },
                        labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                ],
              ),
              // P2-05: DN/SCH picker sits BELOW the material chip strip.
              // heat_input has no OD/wall input fields, so the resolved
              // values are surfaced as a read-only hint chip; this still
              // gives the welder a sanity check for HI / preheat decisions
              // (thicker wall → more conservative preheat).
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openPipeSizePicker,
                      icon: const Text('📋', style: TextStyle(fontSize: 14)),
                      label: Text(
                        _selectedDn == null
                            ? context.tr(
                                pl: 'DN / SCH (rozmiar rury)',
                                en: 'DN / SCH (pipe size)',
                              )
                            : context.tr(
                                pl: 'DN$_selectedDn · Sch $_selectedSch',
                                en: 'DN$_selectedDn · Sch $_selectedSch',
                              ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kTextSec,
                        side: BorderSide(color: _kBorder),
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (_selectedDn != null) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: context.tr(
                        pl: 'Wyczyść rozmiar rury',
                        en: 'Clear pipe size',
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      color: _kTextMut,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: _clearPipeSize,
                    ),
                  ],
                ],
              ),
              if (_hintOdMm != null && _hintWallMm != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: _kTextMut),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                            pl: 'Z tabeli: OD ${_hintOdMm!.toStringAsFixed(2)} mm · '
                                'ścianka ${_hintWallMm!.toStringAsFixed(2)} mm '
                                '(ASME B36.10/19)',
                            en: 'From table: OD ${_hintOdMm!.toStringAsFixed(2)} mm · '
                                'wall ${_hintWallMm!.toStringAsFixed(2)} mm '
                                '(ASME B36.10/19)',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kTextSec,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_material != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kOrange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_material!.name} · P-No ${_material!.pNo}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _kOrange,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr(
                          pl: 'Praktyka WPS (orientacyjnie): ${_material!.practicePl}',
                          en: 'WPS practice (indicative): ${_material!.practiceEn}',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kTextSec,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr(
                          pl: 'Typowe okno HI w WPS: ${_material!.hiMin.toStringAsFixed(1)}–${_material!.hiMax.toStringAsFixed(1)} kJ/mm (informacyjnie — porównuj z własnym WPS).',
                          en: 'Typical WPS HI window: ${_material!.hiMin.toStringAsFixed(1)}–${_material!.hiMax.toStringAsFixed(1)} kJ/mm (for reference — compare with your own WPS).',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: _kTextMut,
                          height: 1.4,
                        ),
                      ),
                      if ((isPl ? _material!.notesPl : _material!.notesEn)
                          .isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          isPl ? _material!.notesPl : _material!.notesEn,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _kTextMut,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                      ],
                      // P1-17: ferritic low-alloy / martensitic groups (C-Mo,
                      // Cr-Mo, Grade 91, 410) → low-hydrogen consumables
                      // irrespective of CE. Not for austenitic / duplex / Ni.
                      if (_material!.lowHydrogenAdvised) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.bolt_outlined, size: 14, color: _kGold),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                context.tr(
                                  pl: 'Stosuj materiały dodatkowe niskowodorowe właściwe dla gatunku (wg WPS) — P-No ${_material!.pNo}.',
                                  en: 'Use low-hydrogen consumables matching the grade (per WPS) — P-No ${_material!.pNo}.',
                                ),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _kGold,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title:
              context.tr(pl: 'Skład chemiczny (% wt)', en: 'Chemistry (% wt)'),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _NumField(
                          label: 'C',
                          ctrl: _cCtrl,
                          onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _NumField(
                          label: 'Mn',
                          ctrl: _mnCtrl,
                          onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _NumField(
                          label: 'Cr',
                          ctrl: _crCtrl,
                          onChanged: () => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _NumField(
                          label: 'Mo',
                          ctrl: _moCtrl,
                          onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _NumField(
                          label: 'V',
                          ctrl: _vCtrl,
                          onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _NumField(
                          label: 'Ni',
                          ctrl: _niCtrl,
                          onChanged: () => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _NumField(
                          label: 'Cu',
                          ctrl: _cuCtrl,
                          onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _NumField(
                      label: context.tr(pl: 'Grubość', en: 'Thickness'),
                      ctrl: _thicknessCtrl,
                      suffix: 'mm',
                      rejectNegative: true,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'CE_IIW = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15',
                style: const TextStyle(color: _kTextMut, fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // CE Result + Preheat methods
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                severity.withValues(alpha: 0.20),
                severity.withValues(alpha: 0.05)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: severity.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department_outlined,
                      color: severity, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    context.tr(
                        pl: 'Carbon Equivalent (CE)',
                        en: 'Carbon Equivalent (CE)'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kTextSec,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: context.tr(
                      pl: 'CE (bezwymiarowy) — wskaźnik hartowności stali. '
                          'Im wyższy, tym większe ryzyko twardej HAZ i pęknięć '
                          'wodorowych — stąd potrzeba preheat. Skala: '
                          '<0.35 łatwo spawalna, >0.55 trudno spawalna.',
                      en: 'CE (dimensionless) — steel hardenability index. '
                          'Higher = harder HAZ and higher hydrogen cracking '
                          'risk, hence the need for preheat. Scale: '
                          '<0.35 easily weldable, >0.55 hard to weld.',
                    ),
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 8),
                    textStyle: const TextStyle(
                        fontSize: 11, color: Colors.white, height: 1.4),
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: _kTextMut,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (p.stainless)
                Text(
                  context.tr(
                    pl: 'Cr ≥ 10.5 % — stal nierdzewna (EN 10088-1). CE i metody '
                        'podgrzewania ze składu nie mają tu zastosowania: '
                        'austenityczne i duplex się nie podgrzewa (liczy się max '
                        'interpass — dla austenitycznej 304/316L typowo ~150–175 °C, '
                        'wg WPS — i niskie HI; przegrzanie → sensytyzacja → korozja '
                        'międzykrystaliczna), martenzytyczne — wg WPS.',
                    en: 'Cr ≥ 10.5 % — stainless steel (EN 10088-1). CE and '
                        'chemistry-based preheat methods do not apply: austenitic '
                        'and duplex are not preheated (max interpass — typically '
                        '~150–175 °C for austenitic 304/316L, per WPS — and low HI '
                        'matter; overheating → sensitisation → intergranular '
                        'corrosion), martensitic — per WPS.',
                  ),
                  style: const TextStyle(
                      color: _kTextSec, fontSize: 12, height: 1.4),
                )
              else if (p.crMo)
                Text(
                  _material != null
                      ? context.tr(
                          pl: 'Stal Cr-Mo / CSEF (P-No ${_material!.pNo}) — CE i metody '
                              'ze składu (Seferian, reguła CE) nie są dla niej przeznaczone '
                              'i dają mylące liczby. Wiąże minimum kodowe (niżej) i WPS.',
                          en: 'Cr-Mo / CSEF steel (P-No ${_material!.pNo}) — CE and '
                              'chemistry-based methods (Seferian, CE rule) are not meant '
                              'for it and give misleading numbers. The code minimum (below) '
                              'and the WPS govern.',
                        )
                      : context.tr(
                          pl: 'Skład wygląda na stal Cr-Mo (Cr ${_crCtrl.text} %, Mo ${_moCtrl.text} %) — '
                              'CE i metody ze składu (Seferian, reguła CE) nie są dla niej '
                              'przeznaczone. Wybierz gatunek z listy, żeby zobaczyć minimum '
                              'kodowe; wiąże WPS.',
                          en: 'The chemistry looks like a Cr-Mo steel (Cr ${_crCtrl.text} %, Mo ${_moCtrl.text} %) — '
                              'CE and chemistry-based methods (Seferian, CE rule) are not meant '
                              'for it. Pick the grade from the list to see the code minimum; '
                              'the WPS governs.',
                        ),
                  style: const TextStyle(
                      color: _kTextSec, fontSize: 12, height: 1.4),
                )
              else
                Text(
                  p.ce.toStringAsFixed(3),
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: severity,
                    height: 1,
                  ),
                ),
              if (p.highCe) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    pl: '⚠ CE ≥ 0.45 — wysoka skłonność do pęknięć na zimno. '
                        'Podgrzewanie wg WPS konieczne.',
                    en: '⚠ CE ≥ 0.45 — high risk of cold cracking. '
                        'Preheat per WPS is a must.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kAccent,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Divider(color: _kBorder),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  pl: 'Podgrzewanie — metody (t = $tLabel mm)',
                  en: 'Preheat — methods (t = $tLabel mm)',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kTextSec,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              if (_material != null) ...[
                _MethodRow(
                  label: context.tr(
                    pl: 'Minimum kodowe ASME B31.3 ≥ 2014 Tab. 330.1.1 (P-No ${_material!.pNo})',
                    en: 'Code minimum ASME B31.3 ≥ 2014 Tab. 330.1.1 (P-No ${_material!.pNo})',
                  ),
                  value: p.codeMinC == null ? '—' : '${p.codeMinC} °C',
                  hint: p.codeMinC == null
                      ? context.tr(
                          pl: 'Brak tej grupy w tabeli aktualnego wydania — do potwierdzenia w normie projektu.',
                          en: 'This group is not in the current-edition table — to be confirmed in the project code.',
                        )
                      : context.tr(
                          pl: 'Wartości jak ASME B31.1-2022 Tab. 131.4.1-1 (od 2014 B31.3 ma te same wymagania). '
                              'Liczone z t = $tLabel mm, Rm min ${_material!.smtsMpa == null ? '—' : '${_material!.smtsMpa!.toStringAsFixed(0)} MPa'}, '
                              'C i Cr z pól składu. Sprawdź wydanie wskazane w specyfikacji projektu.',
                          en: 'Values as ASME B31.1-2022 Table 131.4.1-1 (since 2014 B31.3 has the same requirements). '
                              'Uses t = $tLabel mm, SMTS ${_material!.smtsMpa == null ? '—' : '${_material!.smtsMpa!.toStringAsFixed(0)} MPa'}, '
                              'C and Cr from the chemistry fields. Check the edition named in the project specification.',
                        ),
                ),
                _MethodRow(
                  label: context.tr(
                    pl: 'ASME B31.3-2012 Tab. 330.1.1 (wydanie zastąpione)',
                    en: 'ASME B31.3-2012 Tab. 330.1.1 (superseded edition)',
                  ),
                  value: p.codeMin2012C == null ? '—' : '${p.codeMin2012C} °C',
                  hint: context.tr(
                    pl: 'Tylko gdy specyfikacja projektu wskazuje wydanie 2012.',
                    en: 'Only when the project specification names the 2012 edition.',
                  ),
                ),
              ],
              if (p.crMo && _material == null)
                _MethodRow(
                  label: context.tr(
                    pl: 'Minimum kodowe ASME B31.3',
                    en: 'Code minimum ASME B31.3',
                  ),
                  value: '—',
                  hint: context.tr(
                    pl: 'Wybierz gatunek (P-No) z listy u góry.',
                    en: 'Pick the grade (P-No) from the list above.',
                  ),
                ),
              if (p.crMo)
                _MethodRow(
                  label: context.tr(
                    pl: 'Temperatura z WPS',
                    en: 'Temperature from the WPS',
                  ),
                  value: 'WPS',
                  hint: context.tr(
                    pl: 'Wiąże WPS; nie niżej niż minimum kodowe.',
                    en: 'The WPS governs; never below the code minimum.',
                  ),
                ),
              if (p.ceMethods) ...[
                // Normatywna metoda obliczeniowa — przed szacunkami.
                _MethodRow(
                  label: context.tr(
                    pl: 'EN 1011-2 zał. C, metoda B (CET, wodór, energia liniowa)',
                    en: 'EN 1011-2 Annex C, method B (CET, hydrogen, heat input)',
                  ),
                  value: p.cet?.preheatC == null
                      ? '—'
                      : p.cet!.preheatC! <= 0
                          ? '≤ 0 °C'
                          : '${p.cet!.preheatC!.toStringAsFixed(0)} °C',
                  hint: _cetNote(p),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final hd in const [5.0, 10.0, 15.0])
                      ChoiceChip(
                        label: Text('HD ${hd.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11)),
                        selected: !_assistantNeedsHydrogen && _hd == hd,
                        onSelected: (_) => setState(() {
                          _hd = hd;
                          _assistantNeedsHydrogen = false;
                        }),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _MethodRow(
                  label: context.tr(
                    pl: 'Seferian (szacunek z chemii i grubości)',
                    en: 'Seferian (estimate from chemistry and thickness)',
                  ),
                  value: p.seferianC == null
                      ? '—'
                      : '${p.seferianC!.toStringAsFixed(0)} °C',
                  hint: context.tr(
                    pl: 'Stale węglowe i niskostopowe; bez wodoru i energii liniowej.'
                        '${p.seferianTotalCe == null ? '' : ' [C] z grubością = ${p.seferianTotalCe!.toStringAsFixed(3)}.'}',
                    en: 'Carbon and low-alloy steels; ignores hydrogen and heat input.'
                        '${p.seferianTotalCe == null ? '' : ' [C] with thickness = ${p.seferianTotalCe!.toStringAsFixed(3)}.'}',
                  ),
                ),
                _MethodRow(
                  label: context.tr(
                    pl: 'Reguła orientacyjna CE (nienormatywna)',
                    en: 'CE rule of thumb (non-normative)',
                  ),
                  value: '${p.rule.preheatC.toStringAsFixed(0)} °C',
                  hint: _ruleNote(p.rule),
                  valueColor: severity,
                ),
              ],
              // Nie metoda podgrzewania, tylko górna granica — ale spawacz
              // szuka jej w tym samym miejscu. Z katalogu, gdy gatunek ją ma
              // (P91 250–300 °C, 316L < 175 °C), inaczej typowo C-Mn.
              if (_material?.interpassMax != null)
                _MethodRow(
                  label: context.tr(
                    pl: 'Temp. międzyściegowa max (praktyka dla gatunku — wg WPS)',
                    en: 'Max. interpass temp. (grade practice — per WPS)',
                  ),
                  value: _material!.interpassMax!,
                  hint: context.tr(
                    pl: 'Z katalogu gatunku ${_material!.key}. Wiąże wartość z WPS.',
                    en: 'From the ${_material!.key} catalog entry. The WPS value is binding.',
                  ),
                )
              else if (!p.stainless) ...[
                _MethodRow(
                  label: context.tr(
                    pl: 'Temp. międzyściegowa max (typowo — wg WPS)',
                    en: 'Max. interpass temp. (typical — per WPS)',
                  ),
                  value: '250 °C',
                  hint: context.tr(
                    pl: 'Typowo dla stali węglowych C-Mn; Cr-Mo (np. P91) ma inne '
                        'granice. Wiąże wartość z WPS.',
                    en: 'Typical for C-Mn carbon steels; Cr-Mo (e.g. P91) has other '
                        'limits. The WPS value is binding.',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Te liczby odpowiadają na różne pytania, więc mogą się różnić: '
                      'minimum kodowe to dolna granica kodu rurociągowego dla grupy P-No i grubości, '
                      'Seferian i reguła CE szacują ryzyko pęknięć zimnych ze składu. '
                      'Normatywne metody obliczeniowe: EN 1011-2 zał. C — metoda B (CET, z wodorem i energią liniową) '
                      'liczona wyżej; metoda A (CE, nomogramy) — odczyt z normy. Stosuj temperaturę z WPS; '
                      'nie niższą niż minimum kodowe.',
                  en: 'These numbers answer different questions, so they can differ: '
                      'the code minimum is the piping-code lower limit for the P-No and thickness, '
                      'Seferian and the CE rule estimate cold-cracking risk from chemistry. '
                      'Normative calculation methods: EN 1011-2 Annex C — method B (CET, with hydrogen and heat input) '
                      'calculated above; method A (CE, nomograms) — read from the standard. Use the WPS temperature; '
                      'never below the code minimum.',
                ),
                style: const TextStyle(
                    color: _kTextSec, fontSize: 11, height: 1.45),
              ),
              const SizedBox(height: 6),
              Text(
                _disclaimer,
                style: const TextStyle(
                    color: _kTextMut,
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Tabela pasm CE ma sens tylko tam, gdzie metody z CE są pokazywane
        // (nie dla nierdzewnej i Cr-Mo / P91).
        if (p.ceMethods) ...[
          _SectionCard(
            title: context.tr(
                pl: 'Reguła orientacyjna CE (nienormatywna)',
                en: 'CE rule of thumb (non-normative)'),
            child: Column(
              children: [
                _CeRow(
                    range: 'CE <0.35',
                    preheat: '0 / 50 °C',
                    note: context.tr(
                        pl: 'Cienka ścianka brak / ≥25 mm (~1") = 50 °C',
                        en: 'Thin: none / ≥25 mm (~1"): 50 °C'),
                    color: _kGreen),
                _CeRow(
                    range: '0.35-0.45',
                    preheat: '100-150 °C',
                    note: context.tr(
                        pl: 'Niskie podgrzewanie', en: 'Low preheat'),
                    color: _kGold),
                _CeRow(
                    range: '0.45-0.55',
                    preheat: '150-200 °C',
                    note: context.tr(
                        pl: '+ elektrody niskowodorowe',
                        en: '+ low-H electrodes'),
                    color: _kOrange),
                _CeRow(
                    range: 'CE >0.55',
                    preheat: '200-300 °C',
                    note:
                        context.tr(pl: '+ rozważ PWHT', en: '+ consider PWHT'),
                    color: _kAccent),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        _InfoCard(
          icon: Icons.info_outline,
          text: context.tr(
            pl: 'Stale Cr-Mo (P-No 4, 5A, 5B, 5C, 15E): metody z CE nie są do nich przeznaczone, '
                'więc ekran ich nie pokazuje — obowiązuje minimum kodowe i WPS. Katalog (praktyka WPS): '
                'P22 200–250 °C, PWHT 690–720 °C; P91 200–250 °C, PWHT 750–770 °C.',
            en: 'Cr-Mo steels (P-No 4, 5A, 5B, 5C, 15E): CE-based methods are not meant for them, '
                'so the screen hides them — the code minimum and the WPS govern. Catalog (WPS practice): '
                'P22 200–250 °C, PWHT 690–720 °C; P91 200–250 °C, PWHT 750–770 °C.',
          ),
        ),
      ],
    );
  }

  void _showHeatInputFormulaDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _kBorder),
        ),
        title: Text(
          context.tr(pl: 'Skąd ten wynik?', en: 'Where does this come from?'),
          style: const TextStyle(
              color: Color(0xFFE7ECF3),
              fontSize: 15,
              fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr(
                  pl: 'EN 1011-1 / EN ISO 15614-1 (z η):',
                  en: 'EN 1011-1 / EN ISO 15614-1 (with η):',
                ),
                style: const TextStyle(
                    color: _kTextSec,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6),
              ),
              const SizedBox(height: 6),
              Text(
                'Q [kJ/mm] = η × V × I × 60 / (s × 1000)',
                style: const TextStyle(
                    color: Color(0xFFE7ECF3),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                  pl: 'ASME IX QW-409.1 (bez η):',
                  en: 'ASME IX QW-409.1 (no η):',
                ),
                style: const TextStyle(
                    color: _kTextSec,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6),
              ),
              const SizedBox(height: 6),
              Text(
                'HI [kJ/mm] = V × I × 60 / (s × 1000)',
                style: const TextStyle(
                    color: Color(0xFFE7ECF3),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                  pl: 'V — napięcie [V]\nI — prąd [A]\ns — prędkość spawania [mm/min]\nη — sprawność cieplna procesu (EN 1011-1 tab. 1)',
                  en: 'V — voltage [V]\nI — current [A]\ns — travel speed [mm/min]\nη — process thermal efficiency (EN 1011-1 Table 1)',
                ),
                style: const TextStyle(
                    color: _kTextSec, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                    pl: 'Sprawność η (EN 1011-1):',
                    en: 'Efficiency η (EN 1011-1):'),
                style: const TextStyle(
                    color: _kTextSec,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6),
              ),
              const SizedBox(height: 4),
              Text(
                'SAW (121) = 1.0\nSMAW / MMA (111) = 0.8\nGMAW (131/135) = 0.8\nFCAW-G / FCAW-S (136/137, 114) = 0.8\nGTAW / TIG (141) = 0.6',
                style: const TextStyle(
                    color: Color(0xFFE7ECF3), fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                  pl: 'Za wysokie HI = gruboziarnista HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, pęknięcia wodorowe.',
                  en: 'Too high HI = coarse-grain HAZ, low toughness. Too low HI = fast cooling, hydrogen cracks.',
                ),
                style: const TextStyle(
                    color: _kTextMut,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: _kAccent),
            child: Text(context.tr(pl: 'OK', en: 'OK')),
          ),
        ],
      ),
    );
  }

  // P1-26: build the trace combining HI + CE + Preheat + material.
  // Welder pastes this into a WhatsApp message to the inspector — no need to
  // re-type any number.
  String _buildTraceString(double? hi, _PreheatView p) {
    final mat =
        _material?.key ?? context.tr(pl: 'własny skład', en: 'custom chem.');
    final std = _standard == HeatInputStandard.asmeIx
        ? context.tr(pl: 'ASME IX, bez η', en: 'ASME IX, no η')
        : !_etaOverrideValid
            ? 'EN 1011-1 · η —'
            : _etaOverride != null
                ? 'EN 1011-1 · η ${_eta.toStringAsFixed(2)} (WPS)'
                : 'EN 1011-1 · η ${_eta.toStringAsFixed(2)}';
    final lines = <String>[
      hi == null
          ? context.tr(
              pl: 'Heat input: — (brak wyniku, $_process · $std)',
              en: 'Heat input: — (no result, $_process · $std)')
          : 'Heat input: ${_unit.format(hi)} ${_unit.label} ($_process · $std)',
      p.stainless
          ? context.tr(
              pl: 'CE: nie dotyczy (stal nierdzewna) · Materiał: $mat',
              en: 'CE: n/a (stainless) · Material: $mat')
          : p.crMo
              ? context.tr(
                  pl:
                      'CE: nie stosować do stali Cr-Mo — minimum kodowe i WPS · Materiał: $mat',
                  en:
                      'CE: not for Cr-Mo steels — code minimum and WPS · Material: $mat')
              : context.tr(
                  pl: 'CE_IIW: ${p.ce.toStringAsFixed(3)} · Materiał: $mat',
                  en: 'CE_IIW: ${p.ce.toStringAsFixed(3)} · Material: $mat'),
      if (_material != null) ...[
        context.tr(
          pl: 'Min. kodowe B31.3 ≥ 2014 (= B31.1 Tab. 131.4.1-1): ${p.codeMinC == null ? '—' : '${p.codeMinC} °C'}',
          en: 'Code min. B31.3 ≥ 2014 (= B31.1 Tab. 131.4.1-1): ${p.codeMinC == null ? '—' : '${p.codeMinC} °C'}',
        ),
        context.tr(
          pl: 'Min. kodowe B31.3-2012: ${p.codeMin2012C == null ? '—' : '${p.codeMin2012C} °C'}',
          en: 'Code min. B31.3-2012: ${p.codeMin2012C == null ? '—' : '${p.codeMin2012C} °C'}',
        ),
      ],
      if (p.ceMethods) ...[
        'EN 1011-2 C.3 (CET ${p.cet?.cet.toStringAsFixed(3) ?? '—'}, HD ${_hd.toStringAsFixed(0)}): '
            '${p.cet?.preheatC == null ? '—' : '${p.cet!.preheatC!.toStringAsFixed(0)} °C'}',
        'Seferian: ${p.seferianC == null ? '—' : '${p.seferianC!.toStringAsFixed(0)} °C ([C] ${p.seferianTotalCe!.toStringAsFixed(3)})'}',
        context.tr(
          pl: 'Reguła CE: ${p.rule.preheatC.toStringAsFixed(0)} °C — ${_ruleNote(p.rule)}',
          en: 'CE rule: ${p.rule.preheatC.toStringAsFixed(0)} °C — ${_ruleNote(p.rule)}',
        ),
      ],
      _disclaimer,
    ];
    return lines.join('\n');
  }

  Future<void> _shareTrace(double? hi, _PreheatView p) async {
    try {
      await Share.share(
        _buildTraceString(hi, p),
        subject: context.tr(
          pl: 'Heat input i CE — wynik',
          en: 'Heat input and CE — result',
        ),
      );
    } catch (e) {
      debugPrint('heat_input share failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.tr(
              pl: 'Nie udało się udostępnić — spróbuj ponownie',
              en: 'Share failed — try again',
            )),
            action: SnackBarAction(
              label: context.tr(pl: 'Ponów', en: 'Retry'),
              onPressed: () => _shareTrace(hi, p),
            ),
          ),
        );
    }
  }

  Color _bandColor(CeBand b) {
    switch (b) {
      case CeBand.low:
        return _kGreen;
      case CeBand.medium:
        return _kGold;
      case CeBand.high:
        return _kOrange;
      case CeBand.critical:
        return _kAccent;
    }
  }
}

/// Everything the Preheat tab shows, computed once per build from the
/// domain functions.
class _PreheatView {
  final double ce;
  final double thicknessMm;
  final bool stainless;
  final CeRuleOfThumb rule;
  final double? seferianC;

  /// Seferian [C] = [C]c × (1 + 0.005·t) — the equivalent the °C comes from.
  final double? seferianTotalCe;

  /// ASME B31.3 ≥ 2014 (= B31.1-2022 Tab. 131.4.1-1).
  final int? codeMinC;

  /// ASME B31.3-2012 (wydanie zastąpione) — do porównania.
  final int? codeMin2012C;

  /// Cr-Mo / P91 (P-No 4, 5A, 5B, 5C, 15E): metody z CE ukryte.
  final bool crMo;

  /// EN 1011-2 zał. C metoda B; null, gdy brak Q.
  final CetPreheatResult? cet;
  final double? qEnKjMm;
  const _PreheatView({
    this.cet,
    this.qEnKjMm,
    required this.ce,
    required this.thicknessMm,
    required this.stainless,
    required this.crMo,
    required this.rule,
    required this.seferianC,
    required this.seferianTotalCe,
    required this.codeMinC,
    required this.codeMin2012C,
  });

  /// Metody szacowania z CE (Seferian, reguła CE) mają sens.
  bool get ceMethods => !stainless && !crMo;

  /// CE ≥ 0.45 (bands "high" and "critical") — cold-cracking warning.
  bool get highCe =>
      ceMethods && (rule.band == CeBand.high || rule.band == CeBand.critical);
}

/// One named preheat method: label + value + one-line "when it applies".
class _MethodRow extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final Color? valueColor;
  const _MethodRow({
    required this.label,
    required this.value,
    required this.hint,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE7ECF3),
                      fontWeight: FontWeight.w700,
                      height: 1.3),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                      fontSize: 10.5, color: _kTextMut, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          CopyOnLongPress(
            value: value,
            label: label,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: valueColor ?? const Color(0xFFE7ECF3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Reusable bits
// ════════════════════════════════════════════════════════════════════════════
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _kTextMut,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? suffix;
  final VoidCallback onChanged;
  // P1-30: when true, negative values (including parse-as-negative) surface a
  // PL/EN errorText instead of silently propagating into HI/CE math.
  final bool rejectNegative;
  final bool rejectZero;

  /// Upper bound (inclusive), e.g. 1 for η. Null = no bound.
  final double? maxValue;

  /// Hint line under the field (e.g. which default applies when empty).
  final String? helper;
  const _NumField({
    required this.label,
    required this.ctrl,
    this.suffix,
    required this.onChanged,
    this.rejectNegative = false,
    this.rejectZero = false,
    this.maxValue,
    this.helper,
  });

  /// Derived from the controller text so the parent doesn't need to plumb a
  /// separate validity flag. Empty input is OK (lots of fields are optional);
  /// only flag a non-empty value that can't be parsed.
  bool get _invalid {
    final t = ctrl.text.trim();
    if (t.isEmpty) return false;
    return parseDecimal(t) == null;
  }

  /// P1-30: non-empty negative value on a field marked rejectNegative.
  bool get _negative {
    if (!rejectNegative) return false;
    final t = ctrl.text.trim();
    if (t.isEmpty) return false;
    final v = parseDecimal(t);
    return v != null && v < 0;
  }

  bool get _zero {
    if (!rejectZero) return false;
    final t = ctrl.text.trim();
    if (t.isEmpty) return false;
    final v = parseDecimal(t);
    return v != null && v == 0;
  }

  bool get _tooHigh {
    final max = maxValue;
    if (max == null) return false;
    final t = ctrl.text.trim();
    if (t.isEmpty) return false;
    final v = parseDecimal(t);
    return v != null && v > max;
  }

  String _fmtMax(double max) =>
      max == max.roundToDouble() ? max.toStringAsFixed(0) : max.toString();

  @override
  Widget build(BuildContext context) {
    final hasError = _invalid || _negative || _zero || _tooHigh;
    return TextField(
      controller: ctrl,
      // No minus key on the pad (nothing here is negative), but a field that
      // FLAGS a negative (rejectNegative) lets a pasted '-' through, so the
      // welder sees "must be > 0" instead of the sign silently vanishing.
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(signed: rejectNegative),
      onChanged: (_) => onChanged(),
      style: const TextStyle(color: Color(0xFFE7ECF3)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSec, fontSize: 12),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: _kTextMut, fontSize: 11),
        filled: true,
        fillColor: _kBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        helperText: helper,
        helperMaxLines: 3,
        helperStyle: const TextStyle(color: _kTextMut, fontSize: 10.5),
        errorText: !hasError
            ? null
            : _negative || _zero
                ? context.tr(
                    pl: 'Wartość musi być > 0',
                    en: 'Value must be > 0',
                  )
                : _tooHigh
                    ? context.tr(
                        pl: 'Wartość musi być ≤ ${_fmtMax(maxValue!)}',
                        en: 'Value must be ≤ ${_fmtMax(maxValue!)}',
                      )
                    : context.tr(
                        pl: 'Nieprawidłowa liczba', en: 'Invalid number'),
        errorStyle: const TextStyle(fontSize: 10),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kAccent, width: 1.2),
        ),
      ),
    );
  }
}

class _ProcessSelector extends StatelessWidget {
  final String value;
  final Map<String, double> efficiency;
  final ValueChanged<String> onChanged;
  const _ProcessSelector({
    required this.value,
    required this.efficiency,
    required this.onChanged,
  });

  // P1-16: FCAW split into FCAW-G / FCAW-S, SAW kept as the high-η option.
  static const _options = ['SMAW', 'GMAW', 'FCAW-G', 'FCAW-S', 'GTAW', 'SAW'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _options.map((opt) {
        final active = opt == value;
        final eta = efficiency[opt] ?? 0.80;
        return Semantics(
          button: true,
          selected: active,
          label:
              '$opt ${context.tr(pl: 'proces spawania', en: 'welding process')}',
          // P1-16: per-chip tooltip surfaces η so a welder can sanity-check
          // before tapping (long-press on Material to peek, tap to commit).
          child: Tooltip(
            // Nazwa europejska z numerem EN ISO 4063 (TIG 141, MMA 111…) —
            // tak ją znał spawacz z dawnej zakładki kalkulatorów.
            message: context.tr(
              pl: '$opt (${WeldingProcess.fromCode(opt)?.euLabel ?? opt}) — η = ${eta.toStringAsFixed(2)}',
              en: '$opt (${WeldingProcess.fromCode(opt)?.euLabel ?? opt}) — η = ${eta.toStringAsFixed(2)}',
            ),
            child: GestureDetector(
              onTap: () => onChanged(opt),
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _kAccent.withValues(alpha: 0.18) : _kBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? _kAccent : _kBorder,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      color: active ? _kAccent : _kTextSec,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CeRow extends StatelessWidget {
  final String range;
  final String preheat;
  final String note;
  final Color color;
  const _CeRow(
      {required this.range,
      required this.preheat,
      required this.note,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              range,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              preheat,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFE7ECF3),
                  fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              note,
              style:
                  const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _kAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  const TextStyle(fontSize: 11, color: _kTextSec, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// P2-05: DN / SCH picker bottom sheet (ASME B36.10M / B36.19M).
// Same showModalBottomSheet pattern used by NpsTableSheet — schedule chips
// at the top filter the column, DN rows commit on tap. Pop result is a
// ({int dn, String sch}) record consumed by `_applyPipeSize`.
// ════════════════════════════════════════════════════════════════════════════
class _DnSchPickerSheet extends StatefulWidget {
  final int? initialDn;
  final String initialSch;
  const _DnSchPickerSheet({
    required this.initialDn,
    required this.initialSch,
  });

  @override
  State<_DnSchPickerSheet> createState() => _DnSchPickerSheetState();
}

class _DnSchPickerSheetState extends State<_DnSchPickerSheet> {
  late String _sch;

  @override
  void initState() {
    super.initState();
    _sch = kSchedules.contains(widget.initialSch) ? widget.initialSch : 'STD';
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  pl: 'Wybierz rozmiar rury (DN / SCH)',
                  en: 'Pick pipe size (DN / SCH)',
                ),
                style: const TextStyle(
                  color: Color(0xFFE7ECF3),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  pl: 'ASME B36.10M (CS / alloy) + B36.19M (stainless).',
                  en: 'ASME B36.10M (CS / alloy) + B36.19M (stainless).',
                ),
                style: const TextStyle(
                  color: _kTextMut,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in kSchedules) ...[
                      ChoiceChip(
                        label: Text(
                          s == 'STD' ? 'STD' : 'Sch $s',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _sch == s,
                        onSelected: (_) => setState(() => _sch = s),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: _kBorder, height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: kPipeWalls.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: _kBorder, height: 1),
                  itemBuilder: (ctx, i) {
                    final row = kPipeWalls[i];
                    final wall = row.walls[_sch];
                    final selected = widget.initialDn == row.dn;
                    return InkWell(
                      onTap: wall == null
                          ? null
                          : () => Navigator.of(ctx).pop(
                                (dn: row.dn, sch: _sch),
                              ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 72,
                                child: Text(
                                  'DN${row.dn}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? _kOrange
                                        : const Color(0xFFE7ECF3),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '${row.nps}"',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _kTextMut,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  context.tr(
                                    pl: 'OD ${row.od.toStringAsFixed(2)} mm',
                                    en: 'OD ${row.od.toStringAsFixed(2)} mm',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _kTextSec,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 96,
                                child: Text(
                                  wall == null
                                      ? '—'
                                      : context.tr(
                                          pl: 't ${wall.toStringAsFixed(2)} mm',
                                          en: 't ${wall.toStringAsFixed(2)} mm',
                                        ),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: wall == null
                                        ? _kTextMut
                                        : const Color(0xFFE7ECF3),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
