// ignore_for_file: prefer_const_constructors

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_language.dart';
import '../services/flange_catalog.dart';
import '../utils/clipboard_helper.dart';

// Bolt torque calculator for flanged joints — ASME PCC-1 approach.
//
// Formula used: T = K × F × d
//   T = torque [N·m]
//   K = nut factor (lube-dependent: ~0.20 dry, ~0.16 Cu anti-seize, ~0.13 Ni)
//   F = bolt preload [N]  (we target 50-75% of bolt SMYS for ASME PCC-1)
//   d = nominal bolt diameter [m]
//
// Bolt preload F = σ_target × A_s
//   σ_target = preload fraction × yield strength (SMYS)
//   A_s     = tensile stress area = π/4 × (d - 0.9382×p)²  (UNC thread)
//
// Bolt grades supported (ASME A193):
//   B7   — standard CS for most service, SMYS depends on diameter
//   B7M  — modified B7, lower hardness for NACE / sour service
//   B16  — Cr-Mo for high T (≤540°C steam)
//   B8M  — SS 316, lower strength but corrosion-resistant
//
// Limits and disclaimers per ASME PCC-1:
//   - This is an approximation. Real assemblies should use manufacturer-
//     specific torque charts when available, especially for non-standard
//     gaskets (spiral-wound w/ inner ring, RTJ, lined flanges).
//   - Re-torque after first thermal cycle (PTFE-lined: after 24 h cure).
//   - Always tighten in star pattern at 25/50/75/100% of target.

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kAccent = Color(0xFFAB47BC);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);
const _kGold = Color(0xFFE8C14B);

class BoltTorqueScreen extends StatefulWidget {
  const BoltTorqueScreen({super.key});

  @override
  State<BoltTorqueScreen> createState() => _BoltTorqueScreenState();
}

class _BoltTorqueScreenState extends State<BoltTorqueScreen> {
  // ─── Input state ────────────────────────────────────────────────────────
  String _boltSize = '5/8'; // Inch nominal
  String _grade = 'B7';
  String _lube = 'cu_anti_seize';
  double _preloadFraction = 0.50; // 50% of SMYS — ASME PCC-1 default

  /// Flange-driven preset. When set, the bolt size dropdown is filled from
  /// the catalog and the bolt count surfaces on the result card. Null = manual
  /// mode (the original behaviour — user picks bolt size directly).
  int? _flangeDn;
  int? _flangeClass;
  int? _flangeBoltCount;

  void _applyFlangePreset(int dn, int cls) {
    final b = FlangeCatalog.lookup(dn, cls);
    if (b == null) {
      // DN/Class combo not in ASME B16.5 (e.g., small DN at high class).
      // Drop the stale preset chip so the user isn't left thinking the old
      // bolt count still applies, and tell them to pick a valid combo.
      setState(() {
        _flangeDn = null;
        _flangeClass = null;
        _flangeBoltCount = null;
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          backgroundColor: _kCard,
          content: Text(
            context.tr(
              pl: 'Brak DN$dn × Class $cls w B16.5 — wybierz inną kombinację lub tryb ręczny.',
              en: 'DN$dn × Class $cls not in B16.5 — pick another combo or manual mode.',
            ),
            style: const TextStyle(color: _kTextSec, fontSize: 12),
          ),
        ),
      );
      return;
    }
    setState(() {
      _flangeDn = dn;
      _flangeClass = cls;
      _flangeBoltCount = b.boltCount;
      _boltSize = b.boltSize;
    });
    _recalculate();
  }

  void _clearFlangePreset() {
    setState(() {
      _flangeDn = null;
      _flangeClass = null;
      _flangeBoltCount = null;
    });
    _savePrefs();
  }

  // Results
  double? _torqueNm;
  double? _torqueFtLb;
  double? _preloadKN;

  // ─── Reference data ──────────────────────────────────────────────────────
  /// Nominal diameter (mm) for standard bolt sizes used in flanges.
  static const Map<String, double> _boltDiamMm = {
    '1/2': 12.70,
    '5/8': 15.88,
    '3/4': 19.05,
    '7/8': 22.23,
    '1': 25.40,
    '1-1/8': 28.58,
    '1-1/4': 31.75,
    '1-3/8': 34.93,
    '1-1/2': 38.10,
    '1-5/8': 41.28,
    '1-3/4': 44.45,
    '1-7/8': 47.63,
    '2': 50.80,
  };

  /// Threads per inch (UNC). Used to compute tensile stress area.
  static const Map<String, int> _threadsPerInch = {
    '1/2': 13,
    '5/8': 11,
    '3/4': 10,
    '7/8': 9,
    '1': 8,
    '1-1/8': 7,
    '1-1/4': 7,
    '1-3/8': 6,
    '1-1/2': 6,
    '1-5/8': 5,
    '1-3/4': 5,
    '1-7/8': 5,
    '2': 4,
  };

  /// SMYS [MPa] for ASTM A193 bolt grades. Note: B7 SMYS drops for >2.5" dia,
  /// but for the standard flange range here (≤2") it stays at 105 ksi = 724 MPa.
  /// Source: ASTM A193/A193M Table 2.
  static const Map<String, int> _smysMpa = {
    'B7': 724,   // 105 ksi
    'B7M': 552,  // 80 ksi  (lower hardness ≤22 HRC for sour service)
    'B16': 724,  // 105 ksi (Cr-Mo, similar SMYS but better creep)
    'B8M': 207,  // 30 ksi  (SS 316, much lower strength)
  };

  /// Nut factor K — lubricant-dependent.
  static const Map<String, double> _kFactor = {
    'dry': 0.20,
    'oil': 0.18,
    'cu_anti_seize': 0.16,
    'ni_anti_seize': 0.13,
    'moly_paste': 0.11,
  };

  // ─── Calculation ─────────────────────────────────────────────────────────
  void _recalculate() {
    final dMm = _boltDiamMm[_boltSize];
    final smys = _smysMpa[_grade];
    final k = _kFactor[_lube];
    final tpi = _threadsPerInch[_boltSize];
    if (dMm == null || smys == null || k == null || tpi == null) {
      setState(() {
        _torqueNm = null;
        _torqueFtLb = null;
        _preloadKN = null;
      });
      return;
    }

    // Tensile stress area A_s [mm²] for UNC thread:
    //   p (pitch, mm) = 25.4 / tpi
    //   d_basic (mm) = d
    //   A_s = π/4 × (d − 0.9382 × p)²
    final p = 25.4 / tpi;
    final dEff = dMm - 0.9382 * p;
    final asMm2 = math.pi / 4.0 * dEff * dEff;

    // Preload force F [N] = σ × A
    final sigmaMpa = smys * _preloadFraction; // MPa = N/mm²
    final fN = sigmaMpa * asMm2;

    // Torque T [N·m] = K × F × d  (d in metres)
    final tNm = k * fN * (dMm / 1000.0);

    setState(() {
      _torqueNm = tNm;
      _torqueFtLb = tNm / 1.3558;
      _preloadKN = fN / 1000.0;
    });
    _savePrefs();
  }

  // Autosave so a fitter who backs out mid-pick doesn't lose their setup
  // (DN, class, grade, lube, preload %) and have to start from defaults.
  static const _kPrefBoltSize = 'bolt_torque.bolt_size';
  static const _kPrefGrade = 'bolt_torque.grade';
  static const _kPrefLube = 'bolt_torque.lube';
  static const _kPrefPreload = 'bolt_torque.preload_fraction';
  static const _kPrefFlangeDn = 'bolt_torque.flange_dn';
  static const _kPrefFlangeClass = 'bolt_torque.flange_class';

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final boltSize = prefs.getString(_kPrefBoltSize);
    final grade = prefs.getString(_kPrefGrade);
    final lube = prefs.getString(_kPrefLube);
    final preload = prefs.getDouble(_kPrefPreload);
    final dn = prefs.getInt(_kPrefFlangeDn);
    final cls = prefs.getInt(_kPrefFlangeClass);
    setState(() {
      if (boltSize != null && _boltDiamMm.containsKey(boltSize)) _boltSize = boltSize;
      if (grade != null && _smysMpa.containsKey(grade)) _grade = grade;
      if (lube != null && _kFactor.containsKey(lube)) _lube = lube;
      if (preload != null && preload >= 0.30 && preload <= 0.75) _preloadFraction = preload;
    });
    if (dn != null && cls != null) {
      _applyFlangePreset(dn, cls);
    } else {
      _recalculate();
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefBoltSize, _boltSize);
    await prefs.setString(_kPrefGrade, _grade);
    await prefs.setString(_kPrefLube, _lube);
    await prefs.setDouble(_kPrefPreload, _preloadFraction);
    if (_flangeDn != null && _flangeClass != null) {
      await prefs.setInt(_kPrefFlangeDn, _flangeDn!);
      await prefs.setInt(_kPrefFlangeClass, _flangeClass!);
    } else {
      await prefs.remove(_kPrefFlangeDn);
      await prefs.remove(_kPrefFlangeClass);
    }
  }

  @override
  void initState() {
    super.initState();
    _recalculate();
    _loadPrefs();
  }

  // ─── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Row(
          children: [
            Text(context.tr(pl: 'Moment dokręcania', en: 'Bolt torque')),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kGold.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _kGold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(
            title: context.tr(pl: 'Preset kołnierza (B16.5)', en: 'Flange preset (B16.5)'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    pl: 'Wybierz DN i klasę — śruba i ilość ustawią się same.',
                    en: 'Pick DN & class — bolt size and count fill in automatically.',
                  ),
                  style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DropdownRow(
                        label: context.tr(pl: 'DN', en: 'DN'),
                        value: _flangeDn ?? 50,
                        items: FlangeCatalog.dns,
                        labelOf: FlangeCatalog.dnLabel,
                        onChanged: (v) =>
                            _applyFlangePreset(v, _flangeClass ?? 150),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DropdownRow(
                        label: context.tr(pl: 'Klasa', en: 'Class'),
                        value: _flangeClass ?? 150,
                        items: FlangeCatalog.classes,
                        labelOf: (c) => '#$c',
                        onChanged: (v) =>
                            _applyFlangePreset(_flangeDn ?? 50, v),
                      ),
                    ),
                  ],
                ),
                if (_flangeBoltCount != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kGold.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_outlined, color: _kGold, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              pl: '$_flangeBoltCount × $_boltSize" śrub',
                              en: '$_flangeBoltCount × $_boltSize" bolts',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _kGold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _clearFlangePreset,
                          child: Text(context.tr(pl: 'Reczne', en: 'Manual')),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: context.tr(pl: 'Śruba', en: 'Bolt'),
            child: Column(
              children: [
                _DropdownRow(
                  label: context.tr(pl: 'Wielkość (cal)', en: 'Size (inch)'),
                  value: _boltSize,
                  items: _boltDiamMm.keys.toList(),
                  onChanged: (v) {
                    setState(() => _boltSize = v);
                    _recalculate();
                  },
                ),
                const SizedBox(height: 10),
                _DropdownRow(
                  label: context.tr(pl: 'Klasa (A193)', en: 'Grade (A193)'),
                  value: _grade,
                  items: const ['B7', 'B7M', 'B16', 'B8M'],
                  subtitles: {
                    'B7': context.tr(pl: 'Standard CS — ogólne zastosowanie', en: 'Standard CS — general purpose'),
                    'B7M': context.tr(pl: 'Sour service / NACE (≤22 HRC)', en: 'Sour service / NACE (≤22 HRC)'),
                    'B16': context.tr(pl: 'Cr-Mo — wysokie T (steam ≤540°C)', en: 'Cr-Mo — high T (steam ≤540°C)'),
                    'B8M': context.tr(pl: 'SS 316 — korozja, niższa wytrzymałość', en: 'SS 316 — corrosion, lower strength'),
                  },
                  onChanged: (v) {
                    setState(() => _grade = v);
                    _recalculate();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _SectionCard(
            title: context.tr(pl: 'Smarowanie i preload', en: 'Lubrication & preload'),
            child: Column(
              children: [
                _DropdownRow(
                  label: context.tr(pl: 'Smar (K-factor)', en: 'Lube (K-factor)'),
                  value: _lube,
                  items: const ['dry', 'oil', 'cu_anti_seize', 'ni_anti_seize', 'moly_paste'],
                  labelOf: (v) {
                    final k = _kFactor[v]!;
                    return '${_lubeName(v, context)}  •  K=${k.toStringAsFixed(2)}';
                  },
                  onChanged: (v) {
                    setState(() => _lube = v);
                    _recalculate();
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(
                          pl: 'Preload (% SMYS)',
                          en: 'Preload (% SMYS)',
                        ),
                        style: const TextStyle(color: _kTextSec, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${(_preloadFraction * 100).toStringAsFixed(0)} %',
                      style: const TextStyle(
                        color: _kAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _preloadFraction,
                  min: 0.30,
                  max: 0.75,
                  divisions: 9,
                  activeColor: _kAccent,
                  inactiveColor: _kBorder,
                  onChanged: (v) {
                    setState(() => _preloadFraction = v);
                    _recalculate();
                  },
                ),
                Text(
                  context.tr(
                    pl: 'ASME PCC-1 zaleca 50% SMYS dla flange średniego ryzyka, 60-70% dla krytycznego.',
                    en: 'ASME PCC-1 recommends 50% SMYS for typical flanges, 60-70% for critical.',
                  ),
                  style: const TextStyle(color: _kTextMut, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─── Result card ────────────────────────────────────────────────
          if (_torqueNm != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kAccent.withValues(alpha: 0.20), _kAccent.withValues(alpha: 0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kAccent.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt_outlined, color: _kAccent, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        context.tr(pl: 'Moment dokręcania', en: 'Tightening torque'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kTextSec,
                          letterSpacing: 0.8,
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
                        _torqueNm!.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: _kAccent,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'N·m',
                        style: const TextStyle(
                          fontSize: 18,
                          color: _kTextSec,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_torqueFtLb!.toStringAsFixed(0)} ft·lb',
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kTextMut,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      pl: 'Preload: ${_preloadKN!.toStringAsFixed(1)} kN',
                      en: 'Preload: ${_preloadKN!.toStringAsFixed(1)} kN',
                    ),
                    style: const TextStyle(color: _kTextMut, fontSize: 12),
                  ),
                  if (_flangeBoltCount != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        pl: '$_flangeBoltCount śrub × ${_torqueNm!.toStringAsFixed(0)} N·m, gwiazda 25/50/75/100%',
                        en: '$_flangeBoltCount bolts × ${_torqueNm!.toStringAsFixed(0)} N·m, star 25/50/75/100%',
                      ),
                      style: const TextStyle(color: _kTextMut, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final s =
                                '${_torqueNm!.toStringAsFixed(0)} N·m (${_torqueFtLb!.toStringAsFixed(0)} ft·lb)';
                            copyToClipboard(context, s, label: 'Torque');
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(context.tr(pl: 'Kopiuj', en: 'Copy')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kAccent,
                            side: BorderSide(color: _kAccent.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Full handover note for WhatsApp/SMS to foreman: torque
                      // alone isn't enough — they need bolt size, grade, lube
                      // and the star-pattern reminder to repeat the job.
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final flangeLine = (_flangeDn != null && _flangeClass != null)
                                ? 'DN$_flangeDn #$_flangeClass'
                                  '${_flangeBoltCount != null ? ' (${_flangeBoltCount}x)' : ''}\n'
                                : '';
                            final lubeLine = _lubeName(_lube, context);
                            final msg = context.tr(
                              pl: '${flangeLine}Sruba: $_boltSize" $_grade\n'
                                  'Smar: $lubeLine\n'
                                  'Preload: ${(_preloadFraction * 100).toStringAsFixed(0)}% SMYS\n'
                                  'MOMENT: ${_torqueNm!.toStringAsFixed(0)} N·m '
                                  '(${_torqueFtLb!.toStringAsFixed(0)} ft·lb)\n'
                                  'Gwiazda 25/50/75/100%, re-torque po 20min-4h.',
                              en: '${flangeLine}Bolt: $_boltSize" $_grade\n'
                                  'Lube: $lubeLine\n'
                                  'Preload: ${(_preloadFraction * 100).toStringAsFixed(0)}% SMYS\n'
                                  'TORQUE: ${_torqueNm!.toStringAsFixed(0)} N·m '
                                  '(${_torqueFtLb!.toStringAsFixed(0)} ft·lb)\n'
                                  'Star 25/50/75/100%, re-torque after 20min-4h.',
                            );
                            Share.share(msg,
                                subject: context.tr(
                                    pl: 'Moment dokrecania',
                                    en: 'Bolt torque'));
                          },
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: Text(context.tr(pl: 'Udostepnij', en: 'Share')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kAccent,
                            side: BorderSide(color: _kAccent.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (_torqueNm == null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: _kTextMut, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        pl: 'Brak wyniku — sprawdź, czy wybrany rozmiar śruby '
                            'i klasa są obsługiwane (B7 / B7M / B16 / B8M).',
                        en: 'No result — make sure the selected bolt size and '
                            'grade are supported (B7 / B7M / B16 / B8M).',
                      ),
                      style: const TextStyle(
                          color: _kTextSec, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // ─── Star pattern reference ─────────────────────────────────────
          _SectionCard(
            title: context.tr(pl: 'Procedura skręcania (ASME PCC-1)', en: 'Tightening procedure (ASME PCC-1)'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepLine(num: '1', text: context.tr(pl: 'Smaruj gwinty + powierzchnię nakrętki', en: 'Lube threads + nut bearing face')),
                _StepLine(num: '2', text: context.tr(pl: 'Ręcznie dokręć wszystkie śruby', en: 'Hand-tighten all bolts')),
                _StepLine(num: '3', text: context.tr(pl: '25% target — gwiazda', en: '25% target — star pattern')),
                _StepLine(num: '4', text: context.tr(pl: '50% target — gwiazda', en: '50% target — star pattern')),
                _StepLine(num: '5', text: context.tr(pl: '75% target — gwiazda', en: '75% target — star pattern')),
                _StepLine(num: '6', text: context.tr(pl: '100% target — gwiazda', en: '100% target — star pattern')),
                _StepLine(num: '7', text: context.tr(pl: 'Final pass: 100% — okrężnie', en: 'Final pass: 100% — circular')),
                _StepLine(num: '8', text: context.tr(pl: 'Relaxation pass po 20 min - 4 h (re-torque 100%)', en: 'Relaxation pass after 20 min - 4 h (re-torque 100%)')),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kAccent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: _kAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                            pl: 'PTFE-lined flanges: dodatkowe re-torque po 24h service + po pierwszym cyklu termicznym.',
                            en: 'PTFE-lined flanges: extra re-torque after 24h service + after first thermal cycle.',
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
            ),
          ),

          const SizedBox(height: 14),
          Text(
            context.tr(
              pl: 'Kalkulacja orientacyjna. Dla krytycznych flange użyj manufacturer chart.',
              en: 'Approximate. Use manufacturer chart for critical flanges.',
            ),
            style: const TextStyle(fontSize: 11, color: _kTextMut),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _lubeName(String key, BuildContext context) {
    switch (key) {
      case 'dry':
        return context.tr(pl: 'Sucha', en: 'Dry');
      case 'oil':
        return context.tr(pl: 'Olej maszynowy', en: 'Machine oil');
      case 'cu_anti_seize':
        return context.tr(pl: 'Pasta Cu (anti-seize)', en: 'Cu anti-seize');
      case 'ni_anti_seize':
        return context.tr(pl: 'Pasta Ni (anti-seize)', en: 'Ni anti-seize');
      case 'moly_paste':
        return context.tr(pl: 'Pasta MoS₂', en: 'MoS₂ paste');
    }
    return key;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sub-widgets
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

class _DropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final Map<T, String>? subtitles;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelOf,
    this.subtitles,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = subtitles?[value];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _kTextSec, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: _kCard,
              icon: const Icon(Icons.keyboard_arrow_down, color: _kTextMut),
              style: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 14),
              items: items
                  .map((e) => DropdownMenuItem<T>(
                        value: e,
                        child: Text(labelOf?.call(e) ?? e.toString()),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final String num;
  final String text;
  const _StepLine({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              num,
              style: TextStyle(
                fontSize: 11,
                color: _kAccent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: _kTextSec, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
