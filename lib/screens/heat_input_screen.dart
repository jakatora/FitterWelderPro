// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/material_catalog.dart';
import '../utils/clipboard_helper.dart';

// Heat input + preheat calculator for arc welding (SMAW / GMAW / FCAW / GTAW / SAW).
//
// Heat input:
//   HI [kJ/mm] = (V × I × 60) / (travel_speed_mm_min × 1000) × η
//   η = arc efficiency factor:
//     - SMAW (stick): 0.80
//     - GMAW (MIG):   0.80
//     - FCAW:         0.80
//     - GTAW (TIG):   0.60
//     - SAW:          0.90
//
// Carbon equivalent — IIW formula (most common):
//   CE_IIW = C + Mn/6 + (Cr + Mo + V)/5 + (Ni + Cu)/15
//
// Pre-heat thresholds (rule of thumb, applies P1 carbon steel):
//   CE <0.35     → no preheat (thin wall) or 50 °C (>25 mm)
//   CE 0.35-0.45 → 100-150 °C
//   CE 0.45-0.55 → 150-200 °C + low-H electrodes
//   CE >0.55     → 200-300 °C + PWHT mandatory
//
// Specific alloys override the rule (P91 / P22 / 304L / Inconel etc.).

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kAccent = Color(0xFFEF5350);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);
const _kGold = Color(0xFFE8C14B);
const _kGreen = Color(0xFF2ECC71);
const _kOrange = Color(0xFFF5A623);

class HeatInputScreen extends StatefulWidget {
  const HeatInputScreen({super.key});

  @override
  State<HeatInputScreen> createState() => _HeatInputScreenState();
}

class _HeatInputScreenState extends State<HeatInputScreen> {
  // ─── Heat input inputs ──────────────────────────────────────────────────
  final _voltsCtrl = TextEditingController(text: '22');
  final _ampsCtrl = TextEditingController(text: '110');
  final _travelCtrl = TextEditingController(text: '200');
  String _process = 'SMAW';

  // ─── Pre-heat / CE inputs ───────────────────────────────────────────────
  final _cCtrl = TextEditingController(text: '0.20');
  final _mnCtrl = TextEditingController(text: '1.00');
  final _crCtrl = TextEditingController(text: '0.00');
  final _moCtrl = TextEditingController(text: '0.00');
  final _vCtrl = TextEditingController(text: '0.00');
  final _niCtrl = TextEditingController(text: '0.00');
  final _cuCtrl = TextEditingController(text: '0.00');
  final _thicknessCtrl = TextEditingController(text: '15');

  // WPS range
  final _wpsMinCtrl = TextEditingController(text: '1.0');
  final _wpsMaxCtrl = TextEditingController(text: '2.5');

  /// Selected material preset (null = manual chemistry). When the welder
  /// picks a grade we fill in every chemistry cell + the WPS heat input window
  /// + surface the recommended preheat note next to the CE result.
  MaterialSpec? _material;

  void _applyMaterial(MaterialSpec m) {
    setState(() {
      _material = m;
      _cCtrl.text = m.c.toStringAsFixed(2);
      _mnCtrl.text = m.mn.toStringAsFixed(2);
      _crCtrl.text = m.cr.toStringAsFixed(2);
      _moCtrl.text = m.mo.toStringAsFixed(2);
      _vCtrl.text = m.v.toStringAsFixed(2);
      _niCtrl.text = m.ni.toStringAsFixed(2);
      _cuCtrl.text = m.cu.toStringAsFixed(2);
      _wpsMinCtrl.text = m.hiMin.toStringAsFixed(1);
      _wpsMaxCtrl.text = m.hiMax.toStringAsFixed(1);
    });
  }

  static const Map<String, double> _efficiency = {
    'SMAW': 0.80,
    'GMAW': 0.80,
    'FCAW': 0.80,
    'GTAW': 0.60,
    'SAW': 0.90,
  };

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;


  @override
  void dispose() {
    _voltsCtrl.dispose();
    _ampsCtrl.dispose();
    _travelCtrl.dispose();
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
    super.dispose();
  }

  // ─── Computed ────────────────────────────────────────────────────────────
  double get _heatInputKjPerMm {
    final v = _parse(_voltsCtrl);
    final i = _parse(_ampsCtrl);
    final s = _parse(_travelCtrl);
    final eta = _efficiency[_process] ?? 0.80;
    if (v <= 0 || i <= 0 || s <= 0) return 0;
    return (v * i * 60.0) / (s * 1000.0) * eta;
  }

  double get _ce {
    final c = _parse(_cCtrl);
    final mn = _parse(_mnCtrl);
    final cr = _parse(_crCtrl);
    final mo = _parse(_moCtrl);
    final vv = _parse(_vCtrl);
    final ni = _parse(_niCtrl);
    final cu = _parse(_cuCtrl);
    return c + mn / 6 + (cr + mo + vv) / 5 + (ni + cu) / 15;
  }

  _PreheatRec _preheatRecommendation(double ce, double thickness) {
    if (ce < 0.35) {
      if (thickness >= 25) {
        return _PreheatRec(50, 'low', 'CE <0.35, gruba ścianka — preheat ostrożności');
      }
      return _PreheatRec(0, 'none', 'CE <0.35, brak preheat dla cienkich');
    }
    if (ce < 0.45) return _PreheatRec(125, 'medium', 'CE 0.35-0.45, niski preheat');
    if (ce < 0.55) return _PreheatRec(175, 'high', 'CE 0.45-0.55, średni preheat + low-H elektrody');
    return _PreheatRec(250, 'critical', 'CE >0.55, wysoki preheat + PWHT mandatory');
  }

  @override
  Widget build(BuildContext context) {
    final hi = _heatInputKjPerMm;
    final wpsMin = _parse(_wpsMinCtrl);
    final wpsMax = _parse(_wpsMaxCtrl);
    final inRange = hi >= wpsMin && hi <= wpsMax;

    final ce = _ce;
    final thickness = _parse(_thicknessCtrl);
    final preheat = _preheatRecommendation(ce, thickness);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCard,
          title: Row(
            children: [
              Text(context.tr(pl: 'Heat input + Preheat', en: 'Heat input + Preheat')),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kGold.withValues(alpha: 0.3)),
                ),
                child: Text(
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
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: _kAccent,
            tabs: [
              Tab(text: context.tr(pl: 'Heat input', en: 'Heat input')),
              Tab(text: context.tr(pl: 'Preheat / CE', en: 'Preheat / CE')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _heatInputTab(hi, wpsMin, wpsMax, inRange),
            _preheatTab(ce, preheat),
          ],
        ),
      ),
    );
  }

  // ─── Tab 1: Heat input ──────────────────────────────────────────────────
  Widget _heatInputTab(double hi, double wpsMin, double wpsMax, bool inRange) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionCard(
          title: context.tr(pl: 'Parametry łuku', en: 'Arc parameters'),
          child: Column(
            children: [
              _ProcessSelector(
                value: _process,
                onChanged: (v) => setState(() => _process = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Napięcie', en: 'Voltage'),
                      ctrl: _voltsCtrl,
                      suffix: 'V',
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumField(
                      label: context.tr(pl: 'Prąd', en: 'Current'),
                      ctrl: _ampsCtrl,
                      suffix: 'A',
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
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        _SectionCard(
          title: context.tr(pl: 'Zakres WPS (kJ/mm)', en: 'WPS range (kJ/mm)'),
          child: Row(
            children: [
              Expanded(
                child: _NumField(
                  label: context.tr(pl: 'Min', en: 'Min'),
                  ctrl: _wpsMinCtrl,
                  suffix: 'kJ/mm',
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: context.tr(pl: 'Max', en: 'Max'),
                  ctrl: _wpsMaxCtrl,
                  suffix: 'kJ/mm',
                  onChanged: () => setState(() {}),
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
              colors: inRange
                  ? [_kGreen.withValues(alpha: 0.20), _kGreen.withValues(alpha: 0.05)]
                  : [_kAccent.withValues(alpha: 0.20), _kAccent.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (inRange ? _kGreen : _kAccent).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    inRange ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                    color: inRange ? _kGreen : _kAccent,
                    size: 22,
                  ),
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
                    hi.toStringAsFixed(3),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: inRange ? _kGreen : _kAccent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'kJ/mm',
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
                inRange
                    ? context.tr(
                        pl: '✓ W zakresie WPS ($wpsMin - $wpsMax kJ/mm)',
                        en: '✓ Within WPS range ($wpsMin - $wpsMax kJ/mm)',
                      )
                    : context.tr(
                        pl: '⚠ POZA zakresem WPS ($wpsMin - $wpsMax kJ/mm) — koryguj parametry',
                        en: '⚠ OUT of WPS range ($wpsMin - $wpsMax kJ/mm) — adjust parameters',
                      ),
                style: TextStyle(
                  color: inRange ? _kGreen : _kAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  pl: 'Efektywność łuku $_process: ${(_efficiency[_process]! * 100).toStringAsFixed(0)}%',
                  en: 'Arc efficiency $_process: ${(_efficiency[_process]! * 100).toStringAsFixed(0)}%',
                ),
                style: const TextStyle(color: _kTextMut, fontSize: 11),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  copyToClipboard(
                    context,
                    '${hi.toStringAsFixed(3)} kJ/mm ($_process)',
                    label: 'HI',
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(context.tr(pl: 'Kopiuj wynik', en: 'Copy result')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: inRange ? _kGreen : _kAccent,
                  side: BorderSide(
                    color: (inRange ? _kGreen : _kAccent).withValues(alpha: 0.5),
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
            pl: 'Heat input formula: HI = (V × I × 60) / (travel × 1000) × η. '
                'Za wysokie HI = coarse grain HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, hydrogen cracking.',
            en: 'Heat input formula: HI = (V × I × 60) / (travel × 1000) × η. '
                'Too high HI = coarse-grain HAZ, low toughness. Too low HI = fast cooling, hydrogen cracking.',
          ),
        ),
      ],
    );
  }

  // ─── Tab 2: Preheat / CE ────────────────────────────────────────────────
  Widget _preheatTab(double ce, _PreheatRec rec) {
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
                  pl: 'Wybierz gatunek — chemia + zakres WPS uzupełnią się same.',
                  en: 'Pick a grade — chemistry + WPS range auto-fill.',
                ),
                style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in MaterialCatalog.all)
                    ChoiceChip(
                      label: Text(m.key, style: const TextStyle(fontSize: 11)),
                      selected: _material?.key == m.key,
                      onSelected: (_) => _applyMaterial(m),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                ],
              ),
              if (_material != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kOrange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_material!.name} · P-No ${_material!.pNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _kOrange,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr(
                          pl: 'Preheat zalecany: ${_material!.preheatNote}',
                          en: 'Recommended preheat: ${_material!.preheatNote}',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kTextSec,
                          height: 1.4,
                        ),
                      ),
                      if (_material!.notes.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _material!.notes,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _kTextMut,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
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
          title: context.tr(pl: 'Skład chemiczny (% wt)', en: 'Chemistry (% wt)'),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _NumField(label: 'C', ctrl: _cCtrl, onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _NumField(label: 'Mn', ctrl: _mnCtrl, onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _NumField(label: 'Cr', ctrl: _crCtrl, onChanged: () => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _NumField(label: 'Mo', ctrl: _moCtrl, onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _NumField(label: 'V', ctrl: _vCtrl, onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: _NumField(label: 'Ni', ctrl: _niCtrl, onChanged: () => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _NumField(label: 'Cu', ctrl: _cuCtrl, onChanged: () => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _NumField(
                      label: context.tr(pl: 'Grubość', en: 'Thickness'),
                      ctrl: _thicknessCtrl,
                      suffix: 'mm',
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'CE_IIW = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15',
                  en: 'CE_IIW = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15',
                ),
                style: const TextStyle(color: _kTextMut, fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // CE Result + Preheat
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_severityColor(rec.severity).withValues(alpha: 0.20),
                _severityColor(rec.severity).withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _severityColor(rec.severity).withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department_outlined, color: _severityColor(rec.severity), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    context.tr(pl: 'Carbon Equivalent (CE)', en: 'Carbon Equivalent (CE)'),
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
                    textStyle: const TextStyle(fontSize: 11, color: Colors.white, height: 1.4),
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
              Text(
                ce.toStringAsFixed(3),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: _severityColor(rec.severity),
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: _kBorder),
              const SizedBox(height: 8),
              Text(
                context.tr(pl: 'Rekomendowany preheat', en: 'Recommended preheat'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kTextSec,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    rec.tempC > 0 ? rec.tempC.toStringAsFixed(0) : '—',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: _severityColor(rec.severity),
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (rec.tempC > 0)
                    Text(
                      '°C',
                      style: const TextStyle(
                        fontSize: 16,
                        color: _kTextSec,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                rec.note,
                style: const TextStyle(color: _kTextSec, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _SectionCard(
          title: context.tr(pl: 'Tabela referencyjna', en: 'Reference table'),
          child: Column(
            children: [
              _CeRow(range: 'CE <0.35', preheat: '0 / 50 °C', note: context.tr(pl: 'Cienka ścianka brak / >25 mm (~1") = 50 °C', en: 'Thin: none / >25 mm (~1"): 50 °C'), color: _kGreen),
              _CeRow(range: '0.35-0.45', preheat: '100-150 °C', note: context.tr(pl: 'Niski preheat', en: 'Low preheat'), color: _kGold),
              _CeRow(range: '0.45-0.55', preheat: '150-200 °C', note: context.tr(pl: '+ low-H elektrody', en: '+ low-H electrodes'), color: _kOrange),
              _CeRow(range: 'CE >0.55', preheat: '200-300 °C', note: context.tr(pl: '+ PWHT mandatory', en: '+ PWHT mandatory'), color: _kAccent),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _InfoCard(
          icon: Icons.info_outline,
          text: context.tr(
            pl: 'Specjalne alloye nadpisują regułę CE: P91 = 200-300°C + PWHT 730-760°C, '
                'P22 = ≥150°C dla ≥10 mm (~3/8"). Sprawdź WPS dla swojego materiału.',
            en: 'Special alloys override CE rule: P91 = 200-300°C + PWHT 730-760°C, '
                'P22 = ≥150°C for ≥10 mm (~3/8"). Check WPS for your material.',
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
          style: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 15, fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr(
                  pl: 'Wzór (ASME IX / EN ISO 15614):',
                  en: 'Formula (ASME IX / EN ISO 15614):',
                ),
                style: const TextStyle(color: _kTextSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
              ),
              const SizedBox(height: 6),
              Text(
                'HI [kJ/mm] = (V × I × 60) / (s × 1000) × η',
                style: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 13, fontWeight: FontWeight.w700, height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                  pl: 'V — napięcie [V]\nI — prąd [A]\ns — prędkość spawania [mm/min]\nη — efektywność łuku (zależna od procesu)',
                  en: 'V — voltage [V]\nI — current [A]\ns — travel speed [mm/min]\nη — arc efficiency (process-dependent)',
                ),
                style: const TextStyle(color: _kTextSec, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(pl: 'Efektywność η:', en: 'Efficiency η:'),
                style: const TextStyle(color: _kTextSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
              ),
              const SizedBox(height: 4),
              Text(
                'SMAW / GMAW / FCAW = 0.80\nGTAW (TIG) = 0.60\nSAW = 0.90',
                style: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                  pl: 'Za wysokie HI = gruboziarnista HAZ, niska udarność. Za niskie HI = szybkie chłodzenie, pęknięcia wodorowe.',
                  en: 'Too high HI = coarse-grain HAZ, low toughness. Too low HI = fast cooling, hydrogen cracks.',
                ),
                style: const TextStyle(color: _kTextMut, fontSize: 11, fontStyle: FontStyle.italic, height: 1.4),
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

  Color _severityColor(String s) {
    switch (s) {
      case 'none':
      case 'low':
        return _kGreen;
      case 'medium':
        return _kGold;
      case 'high':
        return _kOrange;
      case 'critical':
        return _kAccent;
    }
    return _kTextMut;
  }
}

class _PreheatRec {
  final double tempC;
  final String severity;
  final String note;
  const _PreheatRec(this.tempC, this.severity, this.note);
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
  const _NumField({
    required this.label,
    required this.ctrl,
    this.suffix,
    required this.onChanged,
  });

  /// Derived from the controller text so the parent doesn't need to plumb a
  /// separate validity flag. Empty input is OK (lots of fields are optional);
  /// only flag a non-empty value that can't be parsed.
  bool get _invalid {
    final t = ctrl.text.trim();
    if (t.isEmpty) return false;
    return double.tryParse(t.replaceAll(',', '.')) == null;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged(),
      style: const TextStyle(color: Color(0xFFE8ECF0)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSec, fontSize: 12),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: _kTextMut, fontSize: 11),
        filled: true,
        fillColor: _kBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        errorText: _invalid
            ? context.tr(pl: 'Nieprawidłowa liczba', en: 'Invalid number')
            : null,
        errorStyle: const TextStyle(fontSize: 10),
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
  final ValueChanged<String> onChanged;
  const _ProcessSelector({required this.value, required this.onChanged});

  static const _options = ['SMAW', 'GMAW', 'FCAW', 'GTAW', 'SAW'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _options.map((opt) {
        final active = opt == value;
        return Semantics(
          button: true,
          selected: active,
          label: '$opt ${context.tr(pl: 'proces spawania', en: 'welding process')}',
          child: GestureDetector(
            onTap: () => onChanged(opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  const _CeRow({required this.range, required this.preheat, required this.note, required this.color});

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
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              preheat,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE8ECF0), fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              note,
              style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
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
              style: const TextStyle(fontSize: 11, color: _kTextSec, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
