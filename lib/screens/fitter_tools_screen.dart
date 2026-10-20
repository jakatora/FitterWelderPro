// ignore_for_file: prefer_const_constructors

import 'dart:math' as math;
import '../assistant/core/tool_bridge.dart';

import 'package:flutter/material.dart';

import '../data/nps_dn_od_r.dart';
import '../domain/fitter/fitter_calcs.dart';
import '../i18n/app_language.dart';
import '../services/takeout_catalog.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

export '../domain/fitter/fitter_calcs.dart' show slopeCutDeltaMm;

const _kAccent = Color(0xFF1A8A9B);
const _kAccentWarm = Color(0xFFFF8E1E); // wyróżnienia wynikowe
const _kResultBg = Color(0xFF152530);
const _kResultBorder = Color(0xFF1A3A4A);
const _kSubtle = Color(0xFF546E7A); // tekst pomocniczy

/// Offset spool between two identical elbows of angle [angleDeg].
class InsertCalc {
  final double takeoutMm;
  final double travelMm;

  /// travel − 2 × take-out: distance between the two elbow ends.
  final double insertMm;

  /// insert − 2 × weld gap: the pipe length to cut (two butt welds), same
  /// convention as Rolling Offset (`rollingCutLengthMm`).
  final double cutMm;

  /// run = offset / tan θ: how far along the line the second elbow sits.
  final double runMm;
  const InsertCalc({
    required this.takeoutMm,
    required this.travelMm,
    required this.insertMm,
    required this.cutMm,
    required this.runMm,
  });
}

/// travel = offset / sin θ; insert = travel − 2 × [takeoutMm];
/// cut = insert − 2 × [weldGapMm].
InsertCalc insertBetweenElbows({
  required double offsetMm,
  required double angleDeg,
  required double takeoutMm,
  double weldGapMm = 0,
}) {
  final rad = angleDeg * math.pi / 180.0;
  final travel = offsetMm / math.sin(rad);
  final insert = travel - 2.0 * takeoutMm;
  return InsertCalc(
    takeoutMm: takeoutMm,
    travelMm: travel,
    insertMm: insert,
    cutMm: insert - 2.0 * weldGapMm,
    runMm: offsetMm / math.tan(rad),
  );
}

class FitterToolsScreen extends StatefulWidget {
  final int initialTab;
  const FitterToolsScreen({super.key, this.initialTab = 0});

  @override
  State<FitterToolsScreen> createState() => _FitterToolsScreenState();
}

const _fitterTabIds = [
  'slope_cut',
  'elbow_cut',
  'elbow_rotation',
  'insert',
  'reducer',
  'pipe_weight',
  'bevel',
  'thermal_expansion'
];
const _fitterFields = <String, Set<String>>{
  'slope_cut': {'od_mm', 'slope_pct'},
  'elbow_cut': {
    'base_angle_deg',
    'extrados_mm',
    'intrados_mm',
    'target_angle_deg'
  },
  'elbow_rotation': {'od_mm', 'circumference_mm', 'degrees', 'percent'},
  'insert': {'mode', 'od_mm', 'radius_mm', 'angle_deg', 'offset_mm', 'gap_mm'},
  'reducer': {'d1_mm', 'd2_mm', 'length_mm', 'target_mm'},
  'pipe_weight': {'od_mm', 'wall_mm', 'length_mm', 'quantity', 'material'},
  'bevel': {
    'wall_mm',
    'angle_deg',
    'root_face_mm',
    'gap_mm',
    'joint',
    'convention'
  },
  'thermal_expansion': {'length_m', 'delta_k', 'material'},
};

abstract interface class _FitterTabInput {
  Set<String> applyFields(Map<String, Object?> fields);
}

double? _finite(Map<String, Object?> fields, String key) {
  final value = fields[key];
  return value is num && value.isFinite ? value.toDouble() : null;
}

bool _positive(double? v) => v != null && v > 0;

class _FitterToolsScreenState extends State<FitterToolsScreen>
    with SingleTickerProviderStateMixin, ToolHandleHost<FitterToolsScreen>
    implements TabbedToolHandle {
  late final TabController _tabs;
  final _keys = List.generate(8, (_) => GlobalKey());
  @override
  String get toolId => _fitterTabIds[_tabs.index];
  @override
  Set<String> get toolIds => _fitterTabIds.toSet();
  @override
  Set<String> get supportedFields => _fitterFields[toolId]!;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 8, initialIndex: widget.initialTab.clamp(0, 7), vsync: this);
    markReady();
  }

  @override
  bool selectTool(String id) {
    final index = _fitterTabIds.indexOf(id);
    if (index < 0 || !mounted) return false;
    _tabs.index = index;
    return true;
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final target = _tabs.index;
    if (fields.isEmpty) {
      return supportedFields;
    }
    if (fields.keys.any((key) => !supportedFields.contains(key))) {
      return fields.keys.toSet();
    }
    for (var frame = 0;
        frame < 4 && _keys[target].currentState == null;
        frame++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _tabs.index != target) return fields.keys.toSet();
    }
    if (!mounted || _tabs.index != target) return fields.keys.toSet();
    final state = _keys[target].currentState;
    return state is _FitterTabInput
        ? (state as _FitterTabInput).applyFields(fields)
        : fields.keys.toSet();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            context.tr(pl: 'Kalkulatory montera', en: 'Fitter calculators')),
        actions: [HelpButton(help: kHelpFitterTools)],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: context.tr(pl: 'Cięcie pod spadek', en: 'Slope cut')),
            Tab(text: context.tr(pl: 'Cięcie kolanka', en: 'Elbow cut')),
            Tab(text: context.tr(pl: 'Obrót kolanka', en: 'Elbow rotation')),
            Tab(text: context.tr(pl: 'Wstawka', en: 'Insert')),
            Tab(text: context.tr(pl: 'Redukcja', en: 'Reducer')),
            Tab(text: context.tr(pl: 'Ciężar rury', en: 'Pipe weight')),
            Tab(text: context.tr(pl: 'Fazowanie', en: 'Bevel')),
            Tab(text: context.tr(pl: 'Dylatacja', en: 'Expansion')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _SlopeTab(key: _keys[0]),
          _ElbowTab(key: _keys[1]),
          _ElbowRotateTab(key: _keys[2]),
          _InsertTab(key: _keys[3]),
          _ReducerTab(key: _keys[4]),
          _PipeWeightTab(key: _keys[5]),
          _BevelTab(key: _keys[6]),
          _ThermalExpansionTab(key: _keys[7]),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final List<Widget> children;
  const _ResultCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kResultBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kResultBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _ResultLabel extends StatelessWidget {
  final String text;
  const _ResultLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: Color(0xFF78909C))),
    );
  }
}

class _ResultValue extends StatelessWidget {
  final String text;
  final bool isPrimary;
  const _ResultValue(this.text, {this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    // Long-press copies the numeric/text value to clipboard so a fitter can
    // paste it straight into a chat/SMS without retyping (gloves + small keys).
    final copyValue = text.replaceAll(',', '.').replaceAll(' ', ' ').trim();
    return CopyOnLongPress(
      value: copyValue,
      child: Text(
        text,
        style: TextStyle(
          fontSize: isPrimary ? 26 : 17,
          fontWeight: isPrimary ? FontWeight.w800 : FontWeight.w600,
          color: isPrimary ? _kAccentWarm : const Color(0xFFE7ECF3),
          letterSpacing: isPrimary ? -0.5 : 0,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.red.shade300),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style:
                        TextStyle(color: Colors.red.shade300, fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE7ECF3),
          letterSpacing: -0.2),
    );
  }
}

class _SectionDesc extends StatelessWidget {
  final String text;
  const _SectionDesc(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: Color(0xFF78909C))),
    );
  }
}

class _SlopeTab extends StatefulWidget {
  const _SlopeTab({super.key});

  @override
  State<_SlopeTab> createState() => _SlopeTabState();
}

class _SlopeTabState extends State<_SlopeTab> implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final d = _finite(f, 'od_mm'), pct = _finite(f, 'slope_pct');
    if (!_positive(d) || pct == null) return {'od_mm', 'slope_pct'};
    final delta = slopeCutDeltaMm(d!, pct);
    if (!delta.isFinite) return {'od_mm', 'slope_pct'};
    _diameter.text = d.toString();
    _percent.text = pct.toString();
    _calc();
    return {};
  }

  final _diameter = TextEditingController();
  final _percent = TextEditingController();

  double? _alphaDeg;
  double? _deltaH;
  double? _sawAngleDeg;
  String? _hint;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _diameter.dispose();
    _percent.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null;
      _alphaDeg = null;
      _deltaH = null;
      _sawAngleDeg = null;
      _hint = null;
      final d = parseDecimal(_diameter.text);
      final pct = parseDecimal(_percent.text);
      if (d == null || d <= 0) {
        _error = _tr('Podaj średnicę zewnętrzną rury D (mm)',
            'Enter pipe outside diameter D (mm)');
        return;
      }
      if (pct == null) {
        _error = _tr('Podaj spadek (%)', 'Enter slope (%)');
        return;
      }

      final saw = slopeSawAngles(pct);
      _alphaDeg = saw.fromSquareDeg;
      _sawAngleDeg = saw.scale90Deg;
      // Δh = D·tan α (same convention as the Slope screen: rise = L·tan α).
      _deltaH = slopeCutDeltaMm(d, pct);

      // Most band / mitre saws read 0° for a square cut — the setting is α,
      // not 90° − α (which on such a scale would cut almost along the pipe).
      _hint = _tr(
          'Zetnij ${_deltaH!.toStringAsFixed(2)} mm albo odchyl piłę o '
              '${_alphaDeg!.toStringAsFixed(2)}° od cięcia prostopadłego '
              '(piła ze skalą 0° = prosto). Na skali, gdzie 90° = prosto: '
              '${_sawAngleDeg!.toStringAsFixed(2)}°.',
          'Cut ${_deltaH!.toStringAsFixed(2)} mm or tilt the saw '
              '${_alphaDeg!.toStringAsFixed(2)}° off square (saw scale '
              '0° = square). On a scale where 90° = square: '
              '${_sawAngleDeg!.toStringAsFixed(2)}°.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Cięcie pod spadek', 'Slope cut')),
        _SectionDesc(
          _tr('Cięcie na skos (jedno cięcie) - policz różnicę wysokości na przekroju rury, żeby uzyskać spadek w %.',
              'Single angled cut: calculate the height difference across the pipe section to achieve the required slope in %.'),
        ),
        TextField(
          controller: _diameter,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
              labelText: _tr('Średnica zewnętrzna rury D (mm)',
                  'Pipe outside diameter D (mm)')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _percent,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration:
              InputDecoration(labelText: _tr('Spadek (%)', 'Slope (%)')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),
        if (_alphaDeg != null && _deltaH != null)
          _ResultCard(
            children: [
              _ResultLabel(_tr('Kąt spadku α', 'Slope angle α')),
              _ResultValue('${_alphaDeg!.toStringAsFixed(3)}°'),
              const SizedBox(height: 10),
              _ResultLabel(_tr(
                  'Piła — odchylenie od cięcia prostopadłego (skala 0° = prosto)',
                  'Saw — tilt off square (scale 0° = square)')),
              _ResultValue('${_alphaDeg!.toStringAsFixed(3)}°'),
              const SizedBox(height: 4),
              Text(
                _tr('Na skali, gdzie 90° = cięcie prostopadłe: ${_sawAngleDeg!.toStringAsFixed(3)}° (90° − α)',
                    'On a scale where 90° = square cut: ${_sawAngleDeg!.toStringAsFixed(3)}° (90° − α)'),
                style: const TextStyle(fontSize: 12, color: _kSubtle),
              ),
              const Divider(height: 24, color: Color(0xFF1A3A4A)),
              _ResultLabel(_tr('Różnica góra–dół na przekroju Δh = D × tan α',
                  'Top–bottom height diff. across pipe Δh = D × tan α')),
              _ResultValue('${_deltaH!.toStringAsFixed(2)} mm',
                  isPrimary: true),
              if (_hint != null) ...[
                const SizedBox(height: 12),
                Text(_hint!,
                    style: const TextStyle(fontSize: 13, color: _kSubtle)),
              ],
            ],
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

class _ElbowTab extends StatefulWidget {
  const _ElbowTab({super.key});

  @override
  State<_ElbowTab> createState() => _ElbowTabState();
}

class _ElbowTabState extends State<_ElbowTab> implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final base = _finite(f, 'base_angle_deg'),
        l = _finite(f, 'extrados_mm'),
        short = _finite(f, 'intrados_mm'),
        angle = _finite(f, 'target_angle_deg');
    if (!const [45.0, 90.0].contains(base) ||
        l == null ||
        short == null ||
        angle == null) {
      return f.keys.toSet();
    }
    final r = elbowCut(
        baseAngleDeg: base!,
        extradosMm: l,
        intradosMm: short,
        targetAngleDeg: angle);
    if (r == null || !r.odDerivedMm.isFinite || !r.longCutMm.isFinite) {
      return f.keys.toSet();
    }
    _base = base.toInt().toString();
    _longTotal.text = l.toString();
    _shortTotal.text = short.toString();
    _targetAngle.text = angle.toString();
    _calc();
    return {};
  }

  // Kolano bazowe: 90 lub 45
  String _base = '90';

  // Pola wejściowe
  final _longTotal =
      TextEditingController(); // długi bok (extrados) całego kolanka
  final _shortTotal =
      TextEditingController(); // krótki bok (intrados) całego kolanka
  final _targetAngle = TextEditingController(); // kąt jaki chcemy uzyskać

  // Wyniki
  double? _lCut; // gdzie ciąć na długim boku
  double? _sCut; // gdzie ciąć na krótkim boku
  double? _lRemain; // pozostałość długi bok
  double? _sRemain; // pozostałość krótki bok
  double? _remainAngle; // kąt pozostałości
  double? _odDerived; // OD wyliczone z pomiarów (weryfikacja)
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _longTotal.dispose();
    _shortTotal.dispose();
    _targetAngle.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null;
      _lCut = _sCut = _lRemain = _sRemain = _remainAngle = _odDerived = null;

      final baseAngle = double.parse(_base);
      final L = parseDecimal(_longTotal.text);
      final S = parseDecimal(_shortTotal.text);
      final T = parseDecimal(_targetAngle.text);

      if (L == null || S == null) return;

      if (L <= 0 || S <= 0) {
        _error =
            _tr('Podaj długości boków > 0 (mm)', 'Enter side lengths > 0 (mm)');
        return;
      }
      if (L <= S) {
        _error = _tr(
          'Długi bok (extrados) musi być większy niż krótki bok (intrados)',
          'Long side (extrados) must be greater than short side (intrados)',
        );
        return;
      }
      if (T == null) return;
      if (T <= 0 || T >= baseAngle) {
        _error = _tr(
          'Kąt docelowy musi być między 0° a ${baseAngle.toStringAsFixed(0)}°',
          'Target angle must be between 0° and ${baseAngle.toStringAsFixed(0)}°',
        );
        return;
      }

      // Proporcja łuków = proporcja kątów — lib/domain/fitter/fitter_calcs.dart.
      final r = elbowCut(
        baseAngleDeg: baseAngle,
        extradosMm: L,
        intradosMm: S,
        targetAngleDeg: T,
      );
      if (r == null) return;
      _lCut = r.longCutMm;
      _sCut = r.shortCutMm;
      _lRemain = r.longRemainMm;
      _sRemain = r.shortRemainMm;
      _remainAngle = r.remainAngleDeg;
      _odDerived = r.odDerivedMm;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseAngle = double.tryParse(_base) ?? 90.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Cięcie kolanka', 'Elbow cut')),
        _SectionDesc(_tr(
          'Podaj wymiary całego kolanka i żądany kąt. '
              'Program powie gdzie zaznaczyć cięcie na zewnętrznym (extrados) '
              'i wewnętrznym (intrados) łuku.',
          'Enter the total elbow dimensions and the desired angle. '
              'The app will tell you where to mark the cut on the outer (extrados) '
              'and inner (intrados) arc.',
        )),

        // ── KOLANO BAZOWE ────────────────────────────────────────────────
        DropdownButtonFormField<String>(
          key: ValueKey(_base),
          initialValue: _base,
          decoration:
              InputDecoration(labelText: _tr('Kolano bazowe', 'Base elbow')),
          items: const [
            DropdownMenuItem(value: '90', child: Text('90°')),
            DropdownMenuItem(value: '45', child: Text('45°')),
          ],
          onChanged: (v) {
            setState(() => _base = v ?? '90');
            _calc();
          },
        ),
        const SizedBox(height: 14),

        // ── INSTRUKCJA POMIARU ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.straighten,
                      size: 16, color: _kAccent.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Text(
                    _tr('Jak zmierzyć kolano:', 'How to measure the elbow:'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _tr(
                  '1. Zmierz taśmą PO ŁUKU po zewnętrznej stronie (extrados) '
                      '— to jest DŁUGI BOK.\n'
                      '2. Zmierz taśmą PO ŁUKU po wewnętrznej stronie (intrados) '
                      '— to jest KRÓTKI BOK.\n'
                      '3. Wpisz żądany kąt (np. 60° z kolana 90°).\n'
                      '4. Odmierz wynikowe L_cut i S_cut od TEGO SAMEGO końca, '
                      'zaznacz oba punkty i tnij.',
                  '1. Measure WITH A TAPE ALONG THE ARC on the outer side (extrados) '
                      '— this is the LONG SIDE.\n'
                      '2. Measure WITH A TAPE ALONG THE ARC on the inner side (intrados) '
                      '— this is the SHORT SIDE.\n'
                      '3. Enter the desired angle (e.g., 60° from a 90° elbow).\n'
                      '4. Mark L_cut and S_cut from the SAME END and cut.',
                ),
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFB0BEC5), height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── POLA WEJŚCIOWE ────────────────────────────────────────────────
        TextField(
          controller: _longTotal,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr(
              'Długi bok kolanka — extrados (mm)',
              'Long side of elbow — extrados (mm)',
            ),
            hintText: _tr('np. 166.7 (DN50 LR)', 'e.g. 166.7 (DN50 LR)'),
            suffixText: 'mm',
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _shortTotal,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr(
              'Krótki bok kolanka — intrados (mm)',
              'Short side of elbow — intrados (mm)',
            ),
            hintText: _tr('np. 72.0 (DN50 LR)', 'e.g. 72.0 (DN50 LR)'),
            suffixText: 'mm',
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _targetAngle,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr(
              'Żądany kąt kolanka (°)',
              'Desired elbow angle (°)',
            ),
            hintText: _tr('np. 60', 'e.g. 60'),
            helperText: _tr(
              'Musi być między 0° a ${baseAngle.toStringAsFixed(0)}°',
              'Must be between 0° and ${baseAngle.toStringAsFixed(0)}°',
            ),
            suffixText: '°',
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),

        // ── WYNIKI ────────────────────────────────────────────────────────
        if (_lCut != null && _sCut != null)
          _ResultCard(
            children: [
              // OD wyliczone (informacyjnie)
              if (_odDerived != null) ...[
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 13, color: _kAccent.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text(
                      _tr(
                        'OD wyliczone z pomiaru: ${_odDerived!.toStringAsFixed(1)} mm',
                        'OD derived from measurement: ${_odDerived!.toStringAsFixed(1)} mm',
                      ),
                      style: TextStyle(
                          fontSize: 12, color: _kAccent.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Główny wynik: gdzie ciąć
              Text(
                _tr('Odmierz od JEDNEGO końca kolanka:',
                    'Measure from ONE END of the elbow:'),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE7ECF3)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _CutMeasureBox(
                      label:
                          _tr('Długi bok\n(extrados)', 'Long side\n(extrados)'),
                      value: '${_lCut!.toStringAsFixed(1)} mm',
                      color: _kAccentWarm,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CutMeasureBox(
                      label: _tr(
                          'Krótki bok\n(intrados)', 'Short side\n(intrados)'),
                      value: '${_sCut!.toStringAsFixed(1)} mm',
                      color: _kAccentWarm,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _tr(
                  'Zaznacz oba punkty, połącz linią i tnij.',
                  'Mark both points, connect them and cut.',
                ),
                style: const TextStyle(fontSize: 12, color: _kSubtle),
              ),

              const Divider(height: 28, color: Color(0xFF1A3A4A)),

              // Pozostałość
              Text(
                _tr('Pozostałość po cięciu (${_remainAngle!.toStringAsFixed(1)}°):',
                    'Offcut (${_remainAngle!.toStringAsFixed(1)}°):'),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9BA3C7)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _CutMeasureBox(
                      label: _tr('Długi bok', 'Long side'),
                      value: '${_lRemain!.toStringAsFixed(1)} mm',
                      color: const Color(0xFF9BA3C7),
                      small: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CutMeasureBox(
                      label: _tr('Krótki bok', 'Short side'),
                      value: '${_sRemain!.toStringAsFixed(1)} mm',
                      color: const Color(0xFF9BA3C7),
                      small: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _tr(
                  'Formuła: L_cut = L_total × (θ_cel / θ_baza)  '
                      '— łuk kołowy jest proporcjonalny do kąta.',
                  'Formula: L_cut = L_total × (θ_target / θ_base)  '
                      '— circular arc is proportional to the angle.',
                ),
                style:
                    const TextStyle(fontSize: 11, color: _kSubtle, height: 1.5),
              ),
            ],
          ),

        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

// ── Pudełko z wymiarem cięcia ─────────────────────────────────────────────────
class _CutMeasureBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool small;

  const _CutMeasureBox({
    required this.label,
    required this.value,
    required this.color,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.8),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: small ? 16 : 20,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ElbowRotateTab extends StatefulWidget {
  const _ElbowRotateTab({super.key});

  @override
  State<_ElbowRotateTab> createState() => _ElbowRotateTabState();
}

class _ElbowRotateTabState extends State<_ElbowRotateTab>
    implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final od = _finite(f, 'od_mm'),
        circ = _finite(f, 'circumference_mm'),
        deg = _finite(f, 'degrees'),
        pct = _finite(f, 'percent');
    if (f.keys.any((k) => _finite(f, k) == null)) return f.keys.toSet();
    if ((od != null) == (circ != null) || (deg != null) == (pct != null)) {
      return f.keys.toSet();
    }
    if ((od != null && !_positive(od)) ||
        (circ != null && !_positive(circ)) ||
        (deg != null && !_positive(deg)) ||
        (pct != null && !_positive(pct))) {
      return f.keys.toSet();
    }
    final r = rotationArc(
        odMm: od, circumferenceMm: circ, degrees: deg, percent: pct);
    if (r.arc == null || !r.arc!.arcMm.isFinite) return f.keys.toSet();
    _od.text = od?.toString() ?? '';
    _circ.text = circ?.toString() ?? '';
    _deg.text = deg?.toString() ?? '';
    _percent.text = pct?.toString() ?? '';
    _calc();
    return {};
  }

  final _od = TextEditingController();
  final _circ = TextEditingController();
  final _percent = TextEditingController();
  final _deg = TextEditingController();

  double? _resultMm;
  double? _resultDeg;
  bool _overTurn = false;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _od.dispose();
    _circ.dispose();
    _percent.dispose();
    _deg.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null;
      _resultMm = null;
      _resultDeg = null;
      _overTurn = false;

      // A typed circumference of 0 counts as empty (computed from OD) —
      // lib/domain/fitter/fitter_calcs.dart rotationArc.
      final r = rotationArc(
        odMm: parseDecimal(_od.text),
        circumferenceMm: parseDecimal(_circ.text),
        percent: parseDecimal(_percent.text),
        degrees: parseDecimal(_deg.text),
      );
      switch (r.error) {
        case RotationError.noSize:
          _error =
              _tr('Podaj OD albo obwód (mm)', 'Enter OD or circumference (mm)');
          return;
        case RotationError.noRotation:
          // Nothing typed yet — no red error while the fitter is still typing.
          if (_percent.text.trim().isEmpty && _deg.text.trim().isEmpty) return;
          _error = _tr('Podaj % obrotu albo stopnie > 0',
              'Enter rotation % or degrees > 0');
          return;
        case null:
          break;
      }
      final arc = r.arc!;
      _resultDeg = arc.degrees;
      _resultMm = arc.arcMm;
      _overTurn = arc.overFullTurn;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Obrót kolanka', 'Elbow rotation')),
        _SectionDesc(_tr(
            'Przelicz obrót w % lub w stopniach na odmierzenie po obwodzie.',
            'Convert rotation in % or degrees into a measured distance along the circumference.')),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _od,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration:
                    InputDecoration(labelText: _tr('OD (mm)', 'OD (mm)')),
                onChanged: (_) => _calc(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _circ,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration:
                    InputDecoration(labelText: _tr('Obwód (mm)', 'Circ. (mm)')),
                onChanged: (_) => _calc(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _percent,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                    labelText: _tr('Obrót (%)', 'Rotation (%)')),
                onChanged: (_) => _calc(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _deg,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                    labelText: _tr('Obrót (°)', 'Rotation (°)')),
                onChanged: (_) => _calc(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_resultMm != null)
          _ResultCard(
            children: [
              _ResultLabel(
                  _tr('Odmierz po obwodzie', 'Measure along circumference')),
              _ResultValue('${_resultMm!.toStringAsFixed(1)} mm',
                  isPrimary: true),
              if (_resultDeg != null) ...[
                const SizedBox(height: 8),
                _ResultLabel(_tr('To odpowiada', 'Corresponds to')),
                _ResultValue('${_resultDeg!.toStringAsFixed(1)}°'),
              ],
              if (_overTurn) ...[
                const SizedBox(height: 8),
                Text(
                  _tr('Uwaga: więcej niż pełny obrót (> 360° / > 100 %) — sprawdź wpis.',
                      'Note: more than one full turn (> 360° / > 100 %) — check the input.'),
                  style: const TextStyle(fontSize: 12, color: _kAccentWarm),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _tr('Gdy wpisane są oba pola, liczą się stopnie.',
                    'When both fields are filled, degrees are used.'),
                style: const TextStyle(fontSize: 11, color: _kSubtle),
              ),
            ],
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

class _InsertTab extends StatefulWidget {
  const _InsertTab({super.key});

  @override
  State<_InsertTab> createState() => _InsertTabState();
}

class _InsertTabState extends State<_InsertTab> implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final mode = f['mode'];
    final angle = _finite(f, 'angle_deg'),
        off = _finite(f, 'offset_mm'),
        gap = _finite(f, 'gap_mm');
    if (!const ['manual', '1D', '1.5D', '3D'].contains(mode) ||
        !_positive(angle) ||
        !_positive(off) ||
        gap == null ||
        gap < 0) {
      return f.keys.toSet();
    }
    double? takeout;
    final radius = _finite(f, 'radius_mm'), od = _finite(f, 'od_mm');
    if (mode == 'manual') {
      if (!_positive(radius) || angle! >= 180 || f.containsKey('od_mm')) {
        return f.keys.toSet();
      }
      takeout = radius! * math.tan(angle * math.pi / 360);
    } else {
      if (!_positive(od) || angle! > 90 || f.containsKey('radius_mm')) {
        return f.keys.toSet();
      }
      final row = b169RowForOd(od!);
      final type = switch (mode) {
        '1D' => ElbowRadiusType.short1D,
        '3D' => ElbowRadiusType.long3D,
        _ => ElbowRadiusType.long15D
      };
      if (row == null) return {'od_mm'};
      takeout = b169ElbowTakeout(dn: row.dn, type: type, angleDeg: angle)?.mm;
    }
    if (takeout == null || !takeout.isFinite) return f.keys.toSet();
    final calc = insertBetweenElbows(
        offsetMm: off!, angleDeg: angle, takeoutMm: takeout, weldGapMm: gap);
    if (!calc.cutMm.isFinite ||
        calc.cutMm <= 0 ||
        !calc.travelMm.isFinite ||
        !calc.runMm.isFinite) {
      return f.keys.toSet();
    }
    _rMode = mode as String;
    _od.text = od?.toString() ?? '';
    _radius.text = radius?.toString() ?? '';
    _angle.text = angle.toString();
    _offset.text = off.toString();
    _gap.text = gap.toString();
    _calc();
    return {};
  }

  final _od = TextEditingController();
  final _radius = TextEditingController();
  final _angle = TextEditingController();
  final _offset = TextEditingController();
  final _gap = TextEditingController();

  // Rodzina kolan: '1D' (SR), '1.5D' (LR), '3D' wg ASME B16.9 albo 'manual'.
  String _rMode = '1.5D';
  double? _rComputed; // promień / A kolana 90° użyty w obliczeniu
  String? _sizeInfo; // "OD 60.3 → DN50 (NPS 2\")"

  double? _takeoff;
  double? _travel;
  double? _insert;
  double? _cut;
  double? _run;
  double _gapMm = 0;
  String? _source; // skąd take-out (tabela / segment / ręcznie)
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _od.dispose();
    _radius.dispose();
    _angle.dispose();
    _offset.dispose();
    _gap.dispose();
    super.dispose();
  }

  static String _f(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  ElbowRadiusType get _type => switch (_rMode) {
        '1D' => ElbowRadiusType.short1D,
        '3D' => ElbowRadiusType.long3D,
        _ => ElbowRadiusType.long15D,
      };

  /// Take-out from the ASME B16.9 tables for the OD entered; sets [_error]
  /// and returns null when no standard elbow exists.
  double? _tableTakeoff(double ang) {
    final od = parseDecimal(_od.text);
    if (od == null || od <= 0) {
      _error = _tr('Podaj średnicę OD rury (mm)', 'Enter pipe OD (mm)');
      return null;
    }
    final row = b169RowForOd(od);
    if (row == null) {
      _error = _tr(
        'OD ${_f(od)} mm nie jest średnicą rury ASME B36.10 ani EN 10220 seria 1 — '
            'kolan ASME B16.9 dla niej nie ma. Wybierz „Ręcznie — wpisz R” i wpisz R z karty kolana.',
        'OD ${_f(od)} mm is not an ASME B36.10 or EN 10220 series 1 pipe — '
            'there are no ASME B16.9 elbows for it. Choose "Manual — enter R" and type R from the elbow datasheet.',
      );
      return null;
    }
    if (ang <= 0 || ang > 90) {
      _error = _tr(
        'Kolano ASME B16.9 ma kąt 1°–90°. Dla większego kąta użyj trybu „Ręcznie”.',
        'An ASME B16.9 elbow is 1°–90°. For a larger angle use "Manual".',
      );
      return null;
    }
    _sizeInfo = 'OD ${_f(od)} → DN${row.dn} (NPS ${row.nps})';
    final t = b169ElbowTakeout(dn: row.dn, type: _type, angleDeg: ang);
    if (t == null) {
      _error = switch (_type) {
        ElbowRadiusType.short1D => _tr(
            'Kolano SR (1D) wg ASME B16.9 istnieje dopiero od DN25 (NPS 1). Dla DN${row.dn} wybierz LR lub „Ręcznie”.',
            'An SR (1D) elbow per ASME B16.9 starts at DN25 (NPS 1). For DN${row.dn} choose LR or "Manual".'),
        ElbowRadiusType.long3D when row.dn < 20 => _tr(
            'Kolano 3D wg ASME B16.9 istnieje od DN20 (NPS 3/4).',
            'A 3D elbow per ASME B16.9 starts at DN20 (NPS 3/4).'),
        _ => _tr(
            'Brak DN${row.dn} w tabeli kolan ASME B16.9 w aplikacji (DN15–DN600). Użyj trybu „Ręcznie”.',
            'DN${row.dn} is not in the app\'s ASME B16.9 elbow table (DN15–DN600). Use "Manual".'),
      };
      return null;
    }
    _rComputed = t.a90Mm.toDouble();
    final family = switch (_type) {
      ElbowRadiusType.short1D => 'SR',
      ElbowRadiusType.long15D => 'LR',
      ElbowRadiusType.long3D => '3D',
    };
    final table = switch (_type) {
      ElbowRadiusType.short1D => '6.1-4',
      ElbowRadiusType.long15D => '6.1-1',
      ElbowRadiusType.long3D => '6.1-6',
    };
    final nps = row.nps.replaceAll('"', '');
    _source = switch (t.basis) {
      TakeoutBasis.tableA90 => _tr(
          'ASME B16.9 tab. $table: kolano 90° $family NPS $nps — A = ${t.a90Mm} mm',
          'ASME B16.9 Table $table: 90° $family elbow NPS $nps — A = ${t.a90Mm} mm'),
      TakeoutBasis.tableB45 => _tr(
          'ASME B16.9 tab. $table: kolano 45° $family NPS $nps — B = ${_f(t.mm)} mm',
          'ASME B16.9 Table $table: 45° $family elbow NPS $nps — B = ${_f(t.mm)} mm'),
      TakeoutBasis.segment => _tr(
          'ASME B16.9 §6.2.4 (segment kolana 90° $family): A × tan(θ/2) = ${t.a90Mm} × tan(${_f(ang / 2)}°)'
              '${_type == ElbowRadiusType.short1D && ang == 45 ? ' — norma nie ma kolana SR 45°' : ''}',
          'ASME B16.9 §6.2.4 (segment of a 90° $family elbow): A × tan(θ/2) = ${t.a90Mm} × tan(${_f(ang / 2)}°)'
              '${_type == ElbowRadiusType.short1D && ang == 45 ? ' — the standard has no SR 45° elbow' : ''}'),
    };
    return t.mm;
  }

  void _calc() {
    setState(() {
      _error = null;
      _takeoff = null;
      _travel = null;
      _insert = null;
      _cut = null;
      _run = null;
      _rComputed = null;
      _sizeInfo = null;
      _source = null;

      final ang = parseDecimal(_angle.text);
      final off = parseDecimal(_offset.text);

      double? takeoff;
      if (_rMode == 'manual') {
        final r = parseDecimal(_radius.text);
        if (r == null || r <= 0) {
          _error =
              _tr('Podaj promień kolanka R (mm)', 'Enter elbow radius R (mm)');
          return;
        }
        _rComputed = r;
        if (ang == null || ang <= 0 || ang >= 180) {
          _error = _tr(
              'Podaj kąt kolanka θ (1°–179°)', 'Enter elbow angle θ (1°–179°)');
          return;
        }
        takeoff = r * math.tan(ang * math.pi / 360.0);
        _source = _tr(
          'R × tan(θ/2) = ${_f(r)} × tan(${_f(ang / 2)}°) — R wpisany ręcznie',
          'R × tan(θ/2) = ${_f(r)} × tan(${_f(ang / 2)}°) — R entered manually',
        );
      } else {
        final od = parseDecimal(_od.text);
        if (od == null || od <= 0) {
          _error = _tr('Podaj średnicę OD rury (mm)', 'Enter pipe OD (mm)');
          return;
        }
        if (ang == null) {
          _error = _tr(
              'Podaj kąt kolanka θ (1°–90°)', 'Enter elbow angle θ (1°–90°)');
          return;
        }
        takeoff = _tableTakeoff(ang);
        if (takeoff == null) return;
      }

      if (off == null || off <= 0) {
        _error =
            _tr('Podaj odejście (offset) > 0 (mm)', 'Enter offset > 0 (mm)');
        return;
      }
      // Weld gap: empty = 0 (as in Rolling Offset), negative = error.
      final gapText = _gap.text.trim();
      final gap = gapText.isEmpty ? 0.0 : parseDecimal(gapText);
      if (gap == null || gap < 0) {
        _error =
            _tr('Szczelina spoiny: wpisz ≥ 0 mm', 'Weld gap: enter ≥ 0 mm');
        return;
      }

      final calc = insertBetweenElbows(
          offsetMm: off, angleDeg: ang, takeoutMm: takeoff, weldGapMm: gap);
      if (!calc.insertMm.isFinite || !calc.travelMm.isFinite) {
        _error = _tr('Nieprawidłowe dane wejściowe', 'Invalid input data');
        return;
      }

      _takeoff = calc.takeoutMm;
      _travel = calc.travelMm;
      _insert = calc.insertMm;
      _cut = calc.cutMm;
      _run = calc.runMm;
      _gapMm = gap;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Wstawka (offset)', 'Insert (offset)')),
        _SectionDesc(_tr(
          'Model: dwa identyczne kolanka o kącie θ.\n'
              'Do cięcia = travel − 2 × take-out − 2 × szczelina,  travel = offset / sin(θ)\n'
              'Take-out kolana ASME B16.9: 90° i 45° — wymiary A / B z tabel normy; '
              'inny kąt — segment kolana 90°: A × tan(θ/2) (§6.2.4). '
              'Tryb ręczny: R × tan(θ/2).',
          'Model: two identical elbows at angle θ.\n'
              'Cut = travel − 2 × take-out − 2 × gap,  travel = offset / sin(θ)\n'
              'ASME B16.9 elbow take-out: 90° and 45° — dimensions A / B from the '
              'standard\'s tables; other angles — segment of a 90° elbow: '
              'A × tan(θ/2) (§6.2.4). Manual mode: R × tan(θ/2).',
        )),

        // ── Standard promienia ──────────────────────────────
        DropdownButtonFormField<String>(
          key: ValueKey(_rMode),
          initialValue: _rMode,
          decoration: InputDecoration(
            labelText:
                _tr('Standard promienia kolanka', 'Elbow radius standard'),
          ),
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: '1D',
                child: Text(_tr('1D — krótki promień SR (B16.9, od DN25)',
                    '1D — short radius SR (B16.9, from DN25)'))),
            DropdownMenuItem(
                value: '1.5D',
                child: Text(_tr('1.5D — długi promień LR (B16.9) ← typowy',
                    '1.5D — long radius LR (B16.9) ← standard'))),
            DropdownMenuItem(
                value: '3D',
                child: Text(
                    _tr('3D — promień 3D (B16.9)', '3D — 3D radius (B16.9)'))),
            DropdownMenuItem(
                value: 'manual',
                child: Text(_tr('Ręcznie — wpisz R', 'Manual — enter R'))),
          ],
          onChanged: (v) {
            setState(() => _rMode = v ?? '1.5D');
            _calc();
          },
        ),
        const SizedBox(height: 10),

        // ── Pole OD lub R ───────────────────────────────────
        if (_rMode != 'manual') ...[
          TextField(
            controller: _od,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            decoration: InputDecoration(
              labelText: _tr('Średnica zewnętrzna rury OD (mm)',
                  'Pipe outside diameter OD (mm)'),
              hintText: _tr('np. 60.3', 'e.g. 60.3'),
            ),
            onChanged: (_) => _calc(),
          ),
          if (_rComputed != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: _kAccent.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_sizeInfo == null ? '' : '$_sizeInfo · '}'
                      '${_tr('R = A kolana 90°', 'R = A of the 90° elbow')} = ${_f(_rComputed!)} mm',
                      style: TextStyle(
                          fontSize: 12,
                          color: _kAccent.withValues(alpha: 0.85)),
                    ),
                  ),
                ],
              ),
            ),
        ] else ...[
          TextField(
            controller: _radius,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            decoration: InputDecoration(
              labelText: _tr('Promień kolanka R — oś gięcia (mm)',
                  'Elbow bend radius R — centerline (mm)'),
              hintText: _tr('np. 76 (DN50 LR)', 'e.g. 76 (DN50 LR)'),
            ),
            onChanged: (_) => _calc(),
          ),
        ],
        const SizedBox(height: 10),

        // ── Kąt kolanka ────────────────────────────────────
        TextField(
          controller: _angle,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr('Kąt kolanka θ (°)', 'Elbow angle θ (°)'),
            hintText: '90',
            suffixText: '°',
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),

        // ── Odejście ───────────────────────────────────────
        TextField(
          controller: _offset,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr('Odejście — offset (mm)', 'Offset (mm)'),
            hintText: _tr('np. 200', 'e.g. 200'),
            helperText: _tr(
                'Prostopadła odległość między osiami dwóch równoległych rur',
                'Perpendicular distance between two parallel pipe centrelines'),
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),

        // ── Szczelina spoiny ───────────────────────────────
        TextField(
          controller: _gap,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr('Szczelina spoiny g (mm)', 'Weld gap g (mm)'),
            hintText: '0',
            suffixText: 'mm',
            helperText: _tr(
                'Wstawka ma 2 spoiny doczołowe — odejmuję 2 × g. Puste = 0.',
                'The insert has 2 butt welds — 2 × g is deducted. Empty = 0.'),
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),

        if (_takeoff != null &&
            _travel != null &&
            _insert != null &&
            _cut != null)
          _ResultCard(
            children: [
              _ResultLabel(_tr('Take-out kolana T', 'Elbow take-out T')),
              _ResultValue('${_takeoff!.toStringAsFixed(1)} mm'),
              if (_source != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _source!,
                    style: const TextStyle(
                        fontSize: 11, color: _kSubtle, height: 1.4),
                  ),
                ),
              const SizedBox(height: 8),
              _ResultLabel('Travel  = offset / sin(θ)'),
              _ResultValue('${_travel!.toStringAsFixed(1)} mm'),
              if (_run != null) ...[
                const SizedBox(height: 8),
                _ResultLabel(_tr(
                    'Run (przesunięcie wzdłuż linii) = offset / tan(θ)',
                    'Run (along the line) = offset / tan(θ)')),
                _ResultValue('${_run!.toStringAsFixed(1)} mm'),
              ],
              if (_gapMm > 0) ...[
                const SizedBox(height: 8),
                _ResultLabel(_tr('Wstawka między końcami kolan = travel − 2×T',
                    'Insert between elbow ends = travel − 2×T')),
                _ResultValue('${_insert!.toStringAsFixed(1)} mm'),
              ],
              const SizedBox(height: 12),
              _ResultLabel(_tr('Wstawka do cięcia = travel − 2×T − 2×g',
                  'Insert to cut = travel − 2×T − 2×g')),
              _ResultValue(
                '${_cut!.toStringAsFixed(1)} mm',
                isPrimary: _cut! > 0,
              ),
              if (_cut! < 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _tr(
                      'Wstawka ujemna — kolanka nachodzą na siebie. '
                          'Zwiększ odejście (offset) lub zmniejsz kąt/promień.',
                      'Negative insert — elbows overlap. '
                          'Increase the offset or reduce the angle/radius.',
                    ),
                    style:
                        TextStyle(color: Colors.orange.shade300, fontSize: 13),
                  ),
                ),
              ] else if (_cut! < 50) ...[
                const SizedBox(height: 10),
                Text(
                  _tr(
                    'Wstawka bardzo krótka — sprawdź wymiary i możliwości montażu.',
                    'Insert is very short — verify dimensions and assembly clearance.',
                  ),
                  style:
                      const TextStyle(color: Color(0xFF78909C), fontSize: 12),
                ),
              ],
            ],
          ),

        if (_error != null) _ErrorText(_error!),

        const SizedBox(height: 16),
        // ── Tabela podpowiedzi R ─────────────────────────
        if (_rMode == 'manual') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      _tr('Promień R kolan LR (= A kolana 90°), ASME B16.9 / EN 10253-2:',
                          'LR elbow radius R (= A of the 90° elbow), ASME B16.9 / EN 10253-2:'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  for (final row in kNpsTable.where((r) =>
                      r.odMm <= 220 &&
                      [
                        21.3,
                        26.9,
                        33.7,
                        42.4,
                        48.3,
                        60.3,
                        76.1,
                        88.9,
                        114.3,
                        168.3,
                        219.1
                      ].contains(r.odMm)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'OD ${row.odMm.toStringAsFixed(1)} mm  →  R = ${row.rMm.toStringAsFixed(1)} mm  (DN${row.dn})',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFB0BEC5)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReducerTab extends StatefulWidget {
  const _ReducerTab({super.key});

  @override
  State<_ReducerTab> createState() => _ReducerTabState();
}

class _ReducerTabState extends State<_ReducerTab> implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final d1 = _finite(f, 'd1_mm'),
        d2 = _finite(f, 'd2_mm'),
        l = _finite(f, 'length_mm'),
        target = _finite(f, 'target_mm');
    if (!_positive(d1) ||
        !_positive(d2) ||
        !_positive(l) ||
        !_positive(target)) {
      return f.keys.toSet();
    }
    final r = reducerCutFromLargeMm(
        d1Mm: d1!, d2Mm: d2!, lengthMm: l!, targetMm: target!);
    if (r == null || !r.isFinite) return f.keys.toSet();
    _d1.text = d1.toString();
    _d2.text = d2.toString();
    _len.text = l.toString();
    _target.text = target.toString();
    _calc();
    return {};
  }

  final _d1 = TextEditingController();
  final _d2 = TextEditingController();
  final _len = TextEditingController();
  final _target = TextEditingController();

  double? _cutFromLarge;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _d1.dispose();
    _d2.dispose();
    _len.dispose();
    _target.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null;
      _cutFromLarge = null;

      final d1 = parseDecimal(_d1.text);
      final d2 = parseDecimal(_d2.text);
      final l = parseDecimal(_len.text);
      final t = parseDecimal(_target.text);

      if (d1 == null || d2 == null || l == null || t == null) return;
      if (l <= 0) {
        _error = _tr('Podaj długość redukcji', 'Enter reducer length');
        return;
      }
      if ((d1 - d2).abs() < 0.0001) {
        _error = _tr('Średnice muszą być różne', 'Diameters must be different');
        return;
      }
      final maxD = math.max(d1, d2);
      final minD = math.min(d1, d2);
      if (t > maxD || t < minD) {
        _error = _tr(
            'Docelowa średnica musi być pomiędzy ${minD.toStringAsFixed(1)} i ${maxD.toStringAsFixed(1)}',
            'Target diameter must be between ${minD.toStringAsFixed(1)} and ${maxD.toStringAsFixed(1)}');
        return;
      }

      _cutFromLarge =
          reducerCutFromLargeMm(d1Mm: d1, d2Mm: d2, lengthMm: l, targetMm: t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Skrócenie redukcji do wymaganej średnicy',
            'Trim reducer to the required diameter')),
        _SectionDesc(_tr(
          'x = L × (OD duże − OD cel) / (OD duże − OD małe), liczone od dużego końca. '
              'Model zakłada stożek na całej długości L. Redukcje ASME B16.9 / EN 10253 mają '
              'na końcach krótkie odcinki walcowe (pod fazę) — zmierz długość samej części '
              'stożkowej, wpisz ją jako L i odmierzaj od początku stożka. Średnice = OD.',
          'x = L × (OD large − OD target) / (OD large − OD small), from the large end. '
              'The model assumes a cone over the whole length L. ASME B16.9 / EN 10253 reducers '
              'have short cylindrical ends (for the bevel) — measure the conical part only, '
              'enter it as L and measure from the start of the cone. Diameters are OD.',
        )),
        TextField(
          controller: _d1,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
              labelText: _tr('OD wejścia [mm]', 'Inlet OD [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _d2,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
              labelText: _tr('OD wyjścia [mm]', 'Outlet OD [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _len,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
              labelText: _tr(
                  'Długość części stożkowej L [mm]', 'Conical length L [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _target,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
              labelText: _tr('Wymagane OD [mm]', 'Required OD [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),
        if (_cutFromLarge != null)
          _ResultCard(
            children: [
              _ResultLabel(_tr('Odmierz od większego końca i utnij na',
                  'Measure from the larger end and cut at')),
              _ResultValue('${_cutFromLarge!.toStringAsFixed(1)} mm',
                  isPrimary: true),
            ],
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 6: CIĘŻAR RURY
// ══════════════════════════════════════════════════════════════════════════
class _PipeWeightTab extends StatefulWidget {
  const _PipeWeightTab({super.key});
  @override
  State<_PipeWeightTab> createState() => _PipeWeightTabState();
}

class _PipeWeightTabState extends State<_PipeWeightTab>
    implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final od = _finite(f, 'od_mm'),
        wall = _finite(f, 'wall_mm'),
        length = _finite(f, 'length_mm'),
        qty = _finite(f, 'quantity');
    final mat =
        PipeMaterial.values.where((v) => v.name == f['material']).firstOrNull;
    if (!_positive(od) || !_positive(wall) || wall! >= od! / 2 || mat == null) {
      return f.keys.toSet();
    }
    if (f.containsKey('length_mm') && !_positive(length)) return {'length_mm'};
    if (f.containsKey('quantity') &&
        (!_positive(qty) ||
            qty != qty!.roundToDouble() ||
            length == null ||
            qty > 2147483647)) {
      return {'quantity'};
    }
    final kgm = pipeMassKgPerM(od, wall, kPipeDensityKgM3[mat]!);
    final total = kgm * (length ?? 1000) / 1000 * (qty ?? 1);
    if (!kgm.isFinite || !total.isFinite) return f.keys.toSet();
    _mat = mat;
    _od.text = od.toString();
    _t.text = wall.toString();
    _l.text = length?.toString() ?? '';
    _qty.text = qty?.toString() ?? '';
    _calc();
    return {};
  }

  final _od = TextEditingController();
  final _t = TextEditingController();
  final _l = TextEditingController(text: '1000');
  final _qty = TextEditingController(text: '1');
  PipeMaterial _mat = PipeMaterial.ss316;

  double? _kgm;
  double? _lengthMm;
  double? _kgPiece;
  int? _qtyPcs;
  double? _kgTotal;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_od, _t, _l, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  void _calc() {
    setState(() {
      _error = null;
      _kgm = null;
      _kgPiece = null;
      _kgTotal = null;
      _lengthMm = null;
      _qtyPcs = null;
      final od = parseDecimal(_od.text);
      final t = parseDecimal(_t.text);
      if (od == null || od <= 0) {
        _error = _tr('Podaj OD rury (mm)', 'Enter pipe OD (mm)');
        return;
      }
      if (t == null || t <= 0 || t >= od / 2) {
        _error =
            _tr('Podaj poprawną grubość ścianki', 'Enter valid wall thickness');
        return;
      }
      _kgm = pipeMassKgPerM(od, t, kPipeDensityKgM3[_mat]!);

      // No silent defaults: an empty length / quantity just hides that line.
      final lText = _l.text.trim();
      if (lText.isNotEmpty) {
        final l = parseDecimal(lText);
        if (l == null || l <= 0) {
          _error = _tr('Długość: wpisz > 0 mm', 'Length: enter > 0 mm');
          return;
        }
        _lengthMm = l;
        _kgPiece = _kgm! * l / 1000.0;
      }
      final qText = _qty.text.trim();
      if (qText.isNotEmpty && _kgPiece != null) {
        final q = parseDecimal(qText);
        if (q == null || q <= 0 || q != q.roundToDouble()) {
          _error = _tr('Ilość: wpisz całkowitą liczbę sztuk ≥ 1',
              'Qty: enter a whole number ≥ 1');
          return;
        }
        _qtyPcs = q.round();
        _kgTotal = _kgPiece! * _qtyPcs!;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _SectionTitle(_tr('Ciężar rury', 'Pipe weight')),
          _SectionDesc(_tr(
            'm = ρ × π × (OD − t) × t   [kg/m]\n'
                'ρ: SS 316/316L 8 000 · SS 304/304L 7 900 kg/m³ (EN 10088-1) · CS 7 850 · Al 2 700',
            'm = ρ × π × (OD − t) × t   [kg/m]\n'
                'ρ: SS 316/316L 8,000 · SS 304/304L 7,900 kg/m³ (EN 10088-1) · CS 7,850 · Al 2,700',
          )),
          DropdownButtonFormField<PipeMaterial>(
            key: ValueKey(_mat),
            initialValue: _mat,
            isExpanded: true,
            decoration: InputDecoration(labelText: _tr('Materiał', 'Material')),
            items: [
              DropdownMenuItem(
                  value: PipeMaterial.ss316,
                  child: Text(_tr('SS 316/316L (nierdzewna) 8 000 kg/m³',
                      'SS 316/316L (stainless) 8,000 kg/m³'))),
              DropdownMenuItem(
                  value: PipeMaterial.ss304,
                  child: Text(_tr('SS 304/304L (nierdzewna) 7 900 kg/m³',
                      'SS 304/304L (stainless) 7,900 kg/m³'))),
              DropdownMenuItem(
                  value: PipeMaterial.cs,
                  child: Text(_tr(
                      'CS (węglowa) 7 850 kg/m³', 'CS (carbon) 7,850 kg/m³'))),
              DropdownMenuItem(
                  value: PipeMaterial.al,
                  child: Text(_tr('Al (aluminium) 2 700 kg/m³',
                      'Al (aluminium) 2,700 kg/m³'))),
            ],
            onChanged: (v) {
              setState(() => _mat = v ?? PipeMaterial.ss316);
              _calc();
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _od,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    decoration:
                        InputDecoration(labelText: 'OD (mm)', hintText: '60.3'),
                    onChanged: (_) => _calc())),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: _t,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    decoration: InputDecoration(
                        labelText: _tr('Gr. ścianki t (mm)', 'Wall t (mm)'),
                        hintText: '2.0'),
                    onChanged: (_) => _calc())),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _l,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    decoration: InputDecoration(
                        labelText: _tr('Długość (mm)', 'Length (mm)'),
                        hintText: '1000',
                        suffixText: 'mm'),
                    onChanged: (_) => _calc())),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: _qty,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    decoration: InputDecoration(
                        labelText: _tr('Ilość szt.', 'Qty'), hintText: '1'),
                    onChanged: (_) => _calc())),
          ]),
          const SizedBox(height: 16),
          if (_kgm != null && _error == null)
            _ResultCard(children: [
              _ResultLabel(_tr('Ciężar liniowy', 'Linear weight')),
              _ResultValue('${_kgm!.toStringAsFixed(3)} kg/m',
                  isPrimary: _kgPiece == null),
              if (_kgPiece != null) ...[
                const SizedBox(height: 8),
                _ResultLabel(_tr('Odcinek ${_fmt(_lengthMm!)} mm',
                    'Section ${_fmt(_lengthMm!)} mm')),
                _ResultValue('${_kgPiece!.toStringAsFixed(3)} kg',
                    isPrimary: _kgTotal == null),
              ],
              if (_kgTotal != null) ...[
                const SizedBox(height: 8),
                _ResultLabel(
                    _tr('Razem ($_qtyPcs szt.)', 'Total ($_qtyPcs pcs)')),
                _ResultValue('${_kgTotal!.toStringAsFixed(2)} kg',
                    isPrimary: true),
              ],
            ]),
          if (_error != null) _ErrorText(_error!),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 7: FAZOWANIE (BEVEL)
// ══════════════════════════════════════════════════════════════════════════
class _BevelTab extends StatefulWidget {
  const _BevelTab({super.key});
  @override
  State<_BevelTab> createState() => _BevelTabState();
}

class _BevelTabState extends State<_BevelTab> implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final wall = _finite(f, 'wall_mm'),
        angle = _finite(f, 'angle_deg'),
        land = _finite(f, 'root_face_mm'),
        gap = _finite(f, 'gap_mm');
    final joint =
        BevelJoint.values.where((v) => v.name == f['joint']).firstOrNull;
    final conv = BevelAngleConvention.values
        .where((v) => v.name == f['convention'])
        .firstOrNull;
    if (joint == null ||
        conv == null ||
        validateBevel(
                wallMm: wall,
                angleDeg: angle,
                convention: conv,
                rootFaceMm: land,
                gapMm: gap) !=
            null) {
      return f.keys.toSet();
    }
    final r = bevelGeometry(
        joint: joint,
        wallMm: wall!,
        angleDeg: angle!,
        convention: conv,
        rootFaceMm: land!,
        gapMm: gap!);
    if (!r.grooveOpeningMm.isFinite || !r.widthPerSideMm.isFinite) {
      return f.keys.toSet();
    }
    _joint = joint;
    _conv = conv;
    _t.text = wall.toString();
    _angCtrl.text = angle.toString();
    _landCtrl.text = land.toString();
    _gapCtrl.text = gap.toString();
    _calc();
    return {};
  }

  final _t = TextEditingController();
  final _angCtrl = TextEditingController(text: '37.5');
  final _landCtrl = TextEditingController(text: '1.0');
  final _gapCtrl = TextEditingController(text: '0');
  BevelJoint _joint = BevelJoint.v;
  BevelAngleConvention _conv = BevelAngleConvention.perSide;

  BevelGeometry? _geo;
  double? _wall;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_t, _angCtrl, _landCtrl, _gapCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _f(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00')
        ? v.toStringAsFixed(0)
        : (s.endsWith('0') ? v.toStringAsFixed(1) : s);
  }

  /// Switching the convention converts the value already typed
  /// (37.5 per side ↔ 75 included), so the geometry does not change.
  void _setConvention(BevelAngleConvention c) {
    if (c == _conv) return;
    final a = parseDecimal(_angCtrl.text);
    if (a != null) {
      _angCtrl.text = _f(convertBevelAngle(a, from: _conv, to: c));
    }
    setState(() => _conv = c);
    _calc();
  }

  void _calc() {
    setState(() {
      _error = null;
      _geo = null;
      _wall = null;
      final t = parseDecimal(_t.text);
      final ang = parseDecimal(_angCtrl.text);
      final land = parseDecimal(_landCtrl.text);
      final gap = parseDecimal(_gapCtrl.text);
      final err = validateBevel(
          wallMm: t,
          angleDeg: ang,
          convention: _conv,
          rootFaceMm: land,
          gapMm: gap);
      if (err != null) {
        // Nothing typed yet — no red error on an untouched tab.
        if (_t.text.trim().isEmpty) return;
        _error = switch (err) {
          BevelInputError.thickness =>
            _tr('Podaj grubość ścianki t (mm)', 'Enter wall thickness t (mm)'),
          BevelInputError.angle => _conv == BevelAngleConvention.perSide
              ? _tr('Kąt fazy β na stronę: wpisz 0–60° (np. 37,5)',
                  'Bevel angle β per side: enter 0–60° (e.g. 37.5)')
              : _tr('Kąt rowka α: wpisz 0–120° (np. 60)',
                  'Groove angle α: enter 0–120° (e.g. 60)'),
          BevelInputError.rootFace => _tr(
              'Próg b: wpisz ≥ 0 i mniej niż grubość ścianki',
              'Root face b: enter ≥ 0 and less than the wall'),
          BevelInputError.gap => _tr(
              'Szczelina g: wpisz ≥ 0 mm (0 = bez szczeliny)',
              'Root gap g: enter ≥ 0 mm (0 = no gap)'),
        };
        return;
      }
      _wall = t;
      _geo = bevelGeometry(
          joint: _joint,
          wallMm: t!,
          angleDeg: ang!,
          convention: _conv,
          rootFaceMm: land!,
          gapMm: gap!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final perSide = _conv == BevelAngleConvention.perSide;
    final g = _geo;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Kalkulator fazowania', 'Bevel calculator')),
        _SectionDesc(_tr(
          'Najpierw wybierz, jak podany jest kąt: EN ISO 9692-1 podaje kąt ROWKA α '
              '(całkowity, np. 60°), ASME B16.25 kąt fazy NA STRONĘ β (37,5°; rowek 75°). '
              'Szerokość fazy na stronę w = h × tan β.',
          'First choose how the angle is given: EN ISO 9692-1 gives the GROOVE angle α '
              '(included, e.g. 60°), ASME B16.25 the bevel angle PER SIDE β (37.5°; groove 75°). '
              'Bevel width per side w = h × tan β.',
        )),
        DropdownButtonFormField<BevelJoint>(
          key: ValueKey(_joint),
          initialValue: _joint,
          isExpanded: true,
          decoration:
              InputDecoration(labelText: _tr('Typ złącza', 'Joint type')),
          items: [
            DropdownMenuItem(
                value: BevelJoint.v,
                child: Text(_tr('V — jednostronne (typowe TIG)',
                    'V — single-sided (typical TIG)'))),
            DropdownMenuItem(
                value: BevelJoint.x,
                child: Text(_tr('X — dwustronne (grube ścianki)',
                    'X — double-sided (thick walls)'))),
          ],
          onChanged: (v) {
            setState(() => _joint = v ?? BevelJoint.v);
            _calc();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<BevelAngleConvention>(
          key: ValueKey(_conv),
          initialValue: _conv,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: _tr('Jak podany jest kąt', 'How the angle is given')),
          items: [
            DropdownMenuItem(
                value: BevelAngleConvention.perSide,
                child: Text(_tr('Kąt fazy na stronę β (ASME B16.25, 37,5°)',
                    'Bevel angle per side β (ASME B16.25, 37.5°)'))),
            DropdownMenuItem(
                value: BevelAngleConvention.grooveIncluded,
                child: Text(_tr(
                    'Kąt rowka α całkowity (EN ISO 9692-1, np. 60°)',
                    'Included groove angle α (EN ISO 9692-1, e.g. 60°)'))),
          ],
          onChanged: (v) => _setConvention(v ?? BevelAngleConvention.perSide),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _t,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            decoration: InputDecoration(
                labelText:
                    _tr('Grubość ścianki t (mm)', 'Wall thickness t (mm)'),
                hintText: '8'),
            onChanged: (_) => _calc()),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: TextField(
                  controller: _angCtrl,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  decoration: InputDecoration(
                      labelText: perSide
                          ? _tr('Kąt fazy β (°)', 'Bevel angle β (°)')
                          : _tr('Kąt rowka α (°)', 'Groove angle α (°)'),
                      hintText: perSide ? '37.5' : '60',
                      suffixText: '°',
                      helperText: perSide
                          ? _tr('na stronę', 'per side')
                          : _tr('całkowity', 'included')),
                  onChanged: (_) => _calc())),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: _landCtrl,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  decoration: InputDecoration(
                      labelText: _tr('Próg b (mm)', 'Root face b (mm)'),
                      hintText: '1.0',
                      suffixText: 'mm',
                      helperText: _tr('Typowo 0.5–2 mm', 'Typ. 0.5–2 mm')),
                  onChanged: (_) => _calc())),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: _gapCtrl,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  decoration: InputDecoration(
                      labelText: _tr('Szczelina g (mm)', 'Root gap g (mm)'),
                      hintText: '0',
                      suffixText: 'mm'),
                  onChanged: (_) => _calc())),
        ]),
        const SizedBox(height: 16),
        if (g != null)
          _ResultCard(children: [
            _ResultLabel(_tr('Kąt fazy na stronę β / kąt rowka α',
                'Bevel angle per side β / groove angle α')),
            _ResultValue('β ${_f(g.perSideDeg)}° · α ${_f(g.grooveDeg)}°'),
            const SizedBox(height: 8),
            _ResultLabel(g.joint == BevelJoint.x
                ? _tr('Głębokość fazy h z każdej strony = (t − b) / 2',
                    'Bevel depth h from each face = (t − b) / 2')
                : _tr('Głębokość fazy h = t − b', 'Bevel depth h = t − b')),
            _ResultValue('${g.depthPerFaceMm.toStringAsFixed(2)} mm'),
            const SizedBox(height: 8),
            _ResultLabel(_tr('Szerokość fazy na stronę w = h × tan β',
                'Bevel width per side w = h × tan β')),
            _ResultValue('${g.widthPerSideMm.toStringAsFixed(2)} mm',
                isPrimary: true),
            const SizedBox(height: 8),
            _ResultLabel(_tr('Szerokość rowka na powierzchni = g + 2w',
                'Groove width at the surface = g + 2w')),
            _ResultValue('${g.grooveOpeningMm.toStringAsFixed(2)} mm'),
            const SizedBox(height: 10),
            Text(
              g.joint == BevelJoint.x
                  ? _tr(
                      '• Złącze X: fazuj każdy koniec z OBU stron — po ${g.depthPerFaceMm.toStringAsFixed(2)} mm głębokości i ${g.widthPerSideMm.toStringAsFixed(2)} mm szerokości; próg w środku ścianki.',
                      '• X joint: bevel each end from BOTH faces — ${g.depthPerFaceMm.toStringAsFixed(2)} mm deep and ${g.widthPerSideMm.toStringAsFixed(2)} mm wide each; root face in the middle of the wall.')
                  : _tr(
                      '• Fazuj każdy koniec pod β = ${_f(g.perSideDeg)}° do progu ${_landCtrl.text.trim()} mm.',
                      '• Bevel each end at β = ${_f(g.perSideDeg)}° down to a ${_landCtrl.text.trim()} mm root face.'),
              style:
                  const TextStyle(fontSize: 12, color: _kSubtle, height: 1.6),
            ),
            if (_wall != null && _wall! > 22 && perSide) ...[
              const SizedBox(height: 6),
              Text(
                _tr('Ścianka > 22 mm: ASME B16.25 przewiduje fazę złożoną (37,5° + 10°) — ten kalkulator liczy fazę prostą.',
                    'Wall > 22 mm: ASME B16.25 uses a compound bevel (37.5° + 10°) — this calculator covers a plain bevel.'),
                style: const TextStyle(
                    fontSize: 12, color: _kAccentWarm, height: 1.4),
              ),
            ],
          ]),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TAB 8: DYLATACJA CIEPLNA
// ══════════════════════════════════════════════════════════════════════════
class _ThermalExpansionTab extends StatefulWidget {
  const _ThermalExpansionTab({super.key});
  @override
  State<_ThermalExpansionTab> createState() => _ThermalExpansionTabState();
}

class _ThermalExpansionTabState extends State<_ThermalExpansionTab>
    implements _FitterTabInput {
  @override
  Set<String> applyFields(Map<String, Object?> f) {
    final length = _finite(f, 'length_m'), delta = _finite(f, 'delta_k');
    final mat = ExpansionMaterial.values
        .where((v) => v.name == f['material'])
        .firstOrNull;
    if (!_positive(length) || delta == null || delta < 0 || mat == null) {
      return f.keys.toSet();
    }
    final result = thermalExpansionMm(kExpansionAlpha[mat]!, length!, delta);
    if (!result.isFinite) return f.keys.toSet();
    _mat = mat;
    _l.text = length.toString();
    _dt.text = delta.toString();
    _t1.clear();
    _t2.clear();
    _calc();
    return {};
  }

  final _l = TextEditingController();
  final _dt = TextEditingController();
  final _t1 = TextEditingController();
  final _t2 = TextEditingController();
  ExpansionMaterial _mat = ExpansionMaterial.ss316L;

  double? _dLmm;
  double? _dLm;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_l, _dt, _t1, _t2]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null;
      _dLmm = null;
      _dLm = null;
      double? dt;
      final t1v = parseDecimal(_t1.text);
      final t2v = parseDecimal(_t2.text);
      if (t1v != null && t2v != null) {
        dt = (t2v - t1v).abs();
        _dt.text = dt.toStringAsFixed(1);
      } else {
        dt = parseDecimal(_dt.text);
      }
      final l = parseDecimal(_l.text);
      if (l == null || l <= 0) {
        _error =
            _tr('Podaj długość rurociągu (m)', 'Enter pipeline length (m)');
        return;
      }
      if (dt == null || dt < 0) {
        _error = _tr(
            'Podaj różnicę temperatur ΔT', 'Enter temperature difference ΔT');
        return;
      }
      _dLmm = thermalExpansionMm(kExpansionAlpha[_mat]!, l, dt);
      _dLm = _dLmm! / 1000.0;
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _SectionTitle(_tr('Dylatacja cieplna', 'Thermal expansion')),
          _SectionDesc(_tr(
            'ΔL = α × L × ΔT  (L w METRACH)\n'
                'α średnie 20–100 °C; przy wyższej temperaturze pracy α rośnie (np. stal węglowa ok. 13 ×10⁻⁶ przy 300 °C) — wynik jest wtedy zaniżony.',
            'ΔL = α × L × ΔT  (L in METRES)\n'
                'Mean α 20–100 °C; at higher operating temperatures α grows (e.g. carbon steel ≈ 13 ×10⁻⁶ at 300 °C) — the result is then low.',
          )),
          DropdownButtonFormField<ExpansionMaterial>(
            key: ValueKey(_mat),
            initialValue: _mat,
            isExpanded: true,
            decoration: InputDecoration(labelText: _tr('Materiał', 'Material')),
            items: [
              DropdownMenuItem(
                  value: ExpansionMaterial.ss316L,
                  child: Text('SS 316L   α = 16.0 ×10⁻⁶ /°C')),
              DropdownMenuItem(
                  value: ExpansionMaterial.ss304L,
                  child: Text('SS 304L   α = 16.0 ×10⁻⁶ /°C')),
              DropdownMenuItem(
                  value: ExpansionMaterial.cs,
                  child: Text(_tr('CS (węglowa) α = 12.0 ×10⁻⁶ /°C',
                      'CS (carbon) α = 12.0 ×10⁻⁶ /°C'))),
              DropdownMenuItem(
                  value: ExpansionMaterial.cuNi,
                  child: Text('CuNi 90/10 α = 17.0 ×10⁻⁶ /°C')),
              DropdownMenuItem(
                  value: ExpansionMaterial.al,
                  child: Text('Aluminium  α = 23.6 ×10⁻⁶ /°C')),
            ],
            onChanged: (v) {
              setState(() => _mat = v ?? ExpansionMaterial.ss316L);
              _calc();
            },
          ),
          const SizedBox(height: 10),
          TextField(
              controller: _l,
              keyboardType: numberKeyboard(),
              inputFormatters: numberInputFormatters(),
              decoration: InputDecoration(
                  labelText:
                      _tr('Długość rurociągu L (m)', 'Pipeline length L (m)'),
                  hintText: '50',
                  suffixText: 'm'),
              onChanged: (_) => _calc()),
          const SizedBox(height: 10),
          Row(children: [
            // Temperatures can be below zero (winter install, cold lines) — signed.
            Expanded(
                child: TextField(
                    controller: _t1,
                    keyboardType: numberKeyboard(signed: true),
                    inputFormatters: numberInputFormatters(signed: true),
                    decoration: InputDecoration(
                        labelText: _tr('T montażu (°C)', 'Install. T (°C)'),
                        hintText: '20',
                        suffixText: '°C'),
                    onChanged: (_) => _calc())),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: _t2,
                    keyboardType: numberKeyboard(signed: true),
                    inputFormatters: numberInputFormatters(signed: true),
                    decoration: InputDecoration(
                        labelText: _tr('T pracy (°C)', 'Oper. T (°C)'),
                        hintText: '120',
                        suffixText: '°C'),
                    onChanged: (_) => _calc())),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: _dt,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    decoration: InputDecoration(
                        labelText: 'ΔT (°C)',
                        hintText: '100',
                        suffixText: '°C',
                        helperText: _tr('lub T1 i T2', 'or T1 and T2')),
                    onChanged: (_) => _calc())),
          ]),
          const SizedBox(height: 16),
          if (_dLmm != null)
            _ResultCard(children: [
              _ResultLabel('ΔL'),
              _ResultValue('${_dLmm!.toStringAsFixed(1)} mm', isPrimary: true),
              _ResultValue('${_dLm!.toStringAsFixed(4)} m'),
              const SizedBox(height: 10),
              Text(
                _dLmm! > 30
                    ? _tr(
                        '⚠ Dylatacja > 30 mm — sprawdź z projektem / stress engineerem, czy trasa ma kompensację (lira, ramię L/Z, kompensator). Próg 30 mm to reguła praktyczna, nie norma.',
                        '⚠ Expansion > 30 mm — check with the design / stress engineer that the route is compensated (loop, L/Z leg, bellows). The 30 mm threshold is a rule of thumb, not a code value.')
                    : _tr(
                        '✓ Dylatacja mała — sprawdź czy trasa ma wystarczający odcinek elastyczny.',
                        '✓ Small expansion — verify the route has sufficient flexible section.'),
                style: TextStyle(
                    fontSize: 12,
                    color: _dLmm! > 30 ? _kAccentWarm : _kSubtle,
                    fontWeight:
                        _dLmm! > 30 ? FontWeight.w600 : FontWeight.normal),
              ),
            ]),
          if (_error != null) _ErrorText(_error!),
        ],
      );
}
