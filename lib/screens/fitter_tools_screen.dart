// ignore_for_file: prefer_const_constructors

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/nps_dn_od_r.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

const _kAccent       = Color(0xFF1A8A9B);
const _kAccentWarm   = Color(0xFFF5A623);   // wyróżnienia wynikowe
const _kResultBg     = Color(0xFF152530);
const _kResultBorder = Color(0xFF1A3A4A);
const _kSubtle       = Color(0xFF546E7A);   // tekst pomocniczy

class FitterToolsScreen extends StatelessWidget {
  final int initialTab;
  const FitterToolsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      initialIndex: initialTab.clamp(0, 7),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(pl: 'Kalkulatory - Fitter', en: 'Calculators - Fitter')),
          actions: [HelpButton(help: kHelpFitterTools)],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.tr(pl: 'Spadek', en: 'Slope')),
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
        body: const TabBarView(
          children: [
            _SlopeTab(),
            _ElbowTab(),
            _ElbowRotateTab(),
            _InsertTab(),
            _ReducerTab(),
            _PipeWeightTab(),
            _BevelTab(),
            _ThermalExpansionTab(),
          ],
        ),
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
      child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF78909C))),
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
    final copyValue = text
        .replaceAll(',', '.')
        .replaceAll(' ', ' ')
        .trim();
    return CopyOnLongPress(
      value: copyValue,
      child: Text(
        text,
        style: TextStyle(
          fontSize: isPrimary ? 26 : 17,
          fontWeight: isPrimary ? FontWeight.w800 : FontWeight.w600,
          color: isPrimary ? _kAccentWarm : const Color(0xFFE8ECF0),
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
            Expanded(child: Text(text, style: TextStyle(color: Colors.red.shade300, fontSize: 13))),
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
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0), letterSpacing: -0.2),
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
      child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF78909C))),
    );
  }
}

class _SlopeTab extends StatefulWidget {
  const _SlopeTab();

  @override
  State<_SlopeTab> createState() => _SlopeTabState();
}

class _SlopeTabState extends State<_SlopeTab> {
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
      final d = double.tryParse(_diameter.text.replaceAll(',', '.'));
      final pct = double.tryParse(_percent.text.replaceAll(',', '.'));
      if (d == null || d <= 0) {
        _error = _tr('Podaj średnicę zewnętrzną rury D (mm)', 'Enter pipe outside diameter D (mm)');
        return;
      }
      if (pct == null) {
        _error = _tr('Podaj spadek (%)', 'Enter slope (%)');
        return;
      }

      final alphaRad = math.atan(pct / 100.0);
      _alphaDeg = alphaRad * 180.0 / math.pi;
      _sawAngleDeg = 90.0 - _alphaDeg!;
      _deltaH = d * math.sin(alphaRad);

      _hint = _tr('Zetnij ${_deltaH!.toStringAsFixed(2)} mm albo utnij na pile ${_sawAngleDeg!.toStringAsFixed(2)}°', 'Cut ${_deltaH!.toStringAsFixed(2)} mm or set the saw to ${_sawAngleDeg!.toStringAsFixed(2)}°');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Spadek rury', 'Pipe slope')),
        _SectionDesc(
          _tr('Cięcie na skos (jedno cięcie) - policz różnicę wysokości na przekroju rury, żeby uzyskać spadek w %.', 'Single angled cut: calculate the height difference across the pipe section to achieve the required slope in %.'),
        ),
        TextField(
          controller: _diameter,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Średnica zewnętrzna rury D (mm)', 'Pipe outside diameter D (mm)')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _percent,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Spadek (%)', 'Slope (%)')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),
        if (_alphaDeg != null && _deltaH != null)
          _ResultCard(
            children: [
              _ResultLabel(_tr('Kąt spadku α', 'Slope angle α')),
              _ResultValue('${_alphaDeg!.toStringAsFixed(3)}°'),
              const SizedBox(height: 10),
              _ResultLabel(_tr('Kąt cięcia na pile (90° − α)', 'Saw cut angle (90° − α)')),
              _ResultValue('${_sawAngleDeg!.toStringAsFixed(3)}°'),
              const Divider(height: 24, color: Color(0xFF1A3A4A)),
              _ResultLabel(_tr('Różnica góra–dół na przekroju Δh', 'Top–bottom height diff. across pipe Δh')),
              _ResultValue('${_deltaH!.toStringAsFixed(2)} mm', isPrimary: true),
              if (_hint != null) ...[
                const SizedBox(height: 12),
                Text(_hint!, style: const TextStyle(fontSize: 13, color: _kSubtle)),
              ],
            ],
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

class _ElbowTab extends StatefulWidget {
  const _ElbowTab();

  @override
  State<_ElbowTab> createState() => _ElbowTabState();
}

class _ElbowTabState extends State<_ElbowTab> {
  // Kolano bazowe: 90 lub 45
  String _base = '90';

  // Pola wejściowe
  final _longTotal  = TextEditingController(); // długi bok (extrados) całego kolanka
  final _shortTotal = TextEditingController(); // krótki bok (intrados) całego kolanka
  final _targetAngle = TextEditingController(); // kąt jaki chcemy uzyskać

  // Wyniki
  double? _lCut;        // gdzie ciąć na długim boku
  double? _sCut;        // gdzie ciąć na krótkim boku
  double? _lRemain;     // pozostałość długi bok
  double? _sRemain;     // pozostałość krótki bok
  double? _remainAngle; // kąt pozostałości
  double? _odDerived;   // OD wyliczone z pomiarów (weryfikacja)
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
      final L = double.tryParse(_longTotal.text.replaceAll(',', '.'));
      final S = double.tryParse(_shortTotal.text.replaceAll(',', '.'));
      final T = double.tryParse(_targetAngle.text.replaceAll(',', '.'));

      if (L == null || S == null) return;

      if (L <= 0 || S <= 0) {
        _error = _tr('Podaj długości boków > 0 (mm)', 'Enter side lengths > 0 (mm)');
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

      // ── OBLICZENIA ───────────────────────────────────────────────────────
      // Proporcja łuków = proporcja kątów (łuk kołowy liniowo zależy od kąta)
      // L_cut = L_total × (θ_target / θ_base)
      // S_cut = S_total × (θ_target / θ_base)
      final ratio = T / baseAngle;

      _lCut     = L * ratio;
      _sCut     = S * ratio;
      _lRemain  = L - _lCut!;
      _sRemain  = S - _sCut!;
      _remainAngle = baseAngle - T;

      // OD wyliczone z pomiarów (do weryfikacji): OD = (L-S) / θ_base_rad
      final baseRad = baseAngle * math.pi / 180.0;
      _odDerived = (L - S) / baseRad;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseAngle = double.tryParse(_base) ?? 90.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
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
          initialValue: _base,
          decoration: InputDecoration(
              labelText: _tr('Kolano bazowe', 'Base elbow')),
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
                  Icon(Icons.straighten, size: 16, color: _kAccent.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Text(
                    _tr('Jak zmierzyć kolano:', 'How to measure the elbow:'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                style: const TextStyle(fontSize: 12, color: Color(0xFFB0BEC5), height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── POLA WEJŚCIOWE ────────────────────────────────────────────────
        TextField(
          controller: _longTotal,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _tr(
              'Długi bok kolanka — extrados (mm)',
              'Long side of elbow — extrados (mm)',
            ),
            hintText: _tr('np. 141.4', 'e.g. 141.4'),
            suffixText: 'mm',
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _shortTotal,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _tr(
              'Krótki bok kolanka — intrados (mm)',
              'Short side of elbow — intrados (mm)',
            ),
            hintText: _tr('np. 70.7', 'e.g. 70.7'),
            suffixText: 'mm',
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _targetAngle,
          keyboardType: TextInputType.number,
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
                    Icon(Icons.info_outline, size: 13, color: _kAccent.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text(
                      _tr(
                        'OD wyliczone z pomiaru: ${_odDerived!.toStringAsFixed(1)} mm',
                        'OD derived from measurement: ${_odDerived!.toStringAsFixed(1)} mm',
                      ),
                      style: TextStyle(fontSize: 12, color: _kAccent.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Główny wynik: gdzie ciąć
              Text(
                _tr('Odmierz od JEDNEGO końca kolanka:', 'Measure from ONE END of the elbow:'),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8ECF0)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _CutMeasureBox(
                      label: _tr('Długi bok\n(extrados)', 'Long side\n(extrados)'),
                      value: '${_lCut!.toStringAsFixed(1)} mm',
                      color: _kAccentWarm,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CutMeasureBox(
                      label: _tr('Krótki bok\n(intrados)', 'Short side\n(intrados)'),
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
                style: const TextStyle(fontSize: 11, color: _kSubtle, height: 1.5),
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
  const _ElbowRotateTab();

  @override
  State<_ElbowRotateTab> createState() => _ElbowRotateTabState();
}

class _ElbowRotateTabState extends State<_ElbowRotateTab> {
  final _od = TextEditingController();
  final _circ = TextEditingController();
  final _percent = TextEditingController();
  final _deg = TextEditingController();

  double? _resultMm;
  double? _resultDeg;
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

      final od = double.tryParse(_od.text.replaceAll(',', '.'));
      double? circ = double.tryParse(_circ.text.replaceAll(',', '.'));
      final pct = double.tryParse(_percent.text.replaceAll(',', '.'));
      final deg = double.tryParse(_deg.text.replaceAll(',', '.'));

      if ((circ == null || circ <= 0) && (od == null || od <= 0)) {
        _error = _tr('Podaj OD albo obwód (mm)', 'Enter OD or circumference (mm)');
        return;
      }
      circ ??= math.pi * od!;

      if (deg != null && deg > 0) {
        _resultDeg = deg;
        _resultMm = circ * (deg / 360.0);
        return;
      }
      if (pct != null) {
        _resultDeg = 360.0 * (pct / 100.0);
        _resultMm = circ * (pct / 100.0);
        return;
      }

      _error = _tr('Podaj % obrotu albo stopnie', 'Enter rotation % or degrees');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Obrót kolanka', 'Elbow rotation')),
        _SectionDesc(_tr('Przelicz obrót w % lub w stopniach na odmierzenie po obwodzie.', 'Convert rotation in % or degrees into a measured distance along the circumference.')),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _od,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _tr('OD (mm)', 'OD (mm)')),
                onChanged: (_) => _calc(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _circ,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _tr('Obwód (mm)', 'Circ. (mm)')),
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
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _tr('Obrót (%)', 'Rotation (%)')),
                onChanged: (_) => _calc(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _deg,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _tr('Obrót (°)', 'Rotation (°)')),
                onChanged: (_) => _calc(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_resultMm != null)
          _ResultCard(
            children: [
              _ResultLabel(_tr('Odmierz po obwodzie', 'Measure along circumference')),
              _ResultValue('${_resultMm!.toStringAsFixed(1)} mm', isPrimary: true),
              if (_resultDeg != null) ...[
                const SizedBox(height: 8),
                _ResultLabel(_tr('To odpowiada', 'Corresponds to')),
                _ResultValue('${_resultDeg!.toStringAsFixed(1)}°'),
              ],
            ],
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

class _InsertTab extends StatefulWidget {
  const _InsertTab();

  @override
  State<_InsertTab> createState() => _InsertTabState();
}

class _InsertTabState extends State<_InsertTab> {
  final _od = TextEditingController();
  final _radius = TextEditingController();
  final _angle = TextEditingController();
  final _offset = TextEditingController();

  // Wybór standardu promienia: 1D, 1.5D (LR), 3D, ręczny
  String _rMode = '1.5D';
  double? _rComputed; // obliczony R z OD + trybu

  double? _takeoff;
  double? _travel;
  double? _insert;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _od.dispose();
    _radius.dispose();
    _angle.dispose();
    _offset.dispose();
    super.dispose();
  }

  /// Oblicza R na podstawie OD i wybranego standardu,
  /// lub szuka w tabeli NPS (dla trybu 'table').
  double? _resolveR() {
    if (_rMode == 'manual') {
      return double.tryParse(_radius.text.replaceAll(',', '.'));
    }
    final od = double.tryParse(_od.text.replaceAll(',', '.'));
    if (od == null || od <= 0) return null;

    switch (_rMode) {
      case '1D':   return od * 1.0;
      case '1.5D': return od * 1.5;
      case '3D':   return od * 3.0;
      case 'table':
        // Szukaj najbliższego wpisu w tabeli NPS
        NpsRow? best;
        double bestDiff = double.infinity;
        for (final row in kNpsTable) {
          final diff = (row.odMm - od).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            best = row;
          }
        }
        return best?.rMm;
      default:
        return od * 1.5;
    }
  }

  void _calc() {
    setState(() {
      _error = null;
      _takeoff = null;
      _travel = null;
      _insert = null;
      _rComputed = null;

      final r = _resolveR();
      final ang = double.tryParse(_angle.text.replaceAll(',', '.'));
      final off = double.tryParse(_offset.text.replaceAll(',', '.'));

      if (_rMode != 'manual') {
        final od = double.tryParse(_od.text.replaceAll(',', '.'));
        if (od == null || od <= 0) {
          _error = _tr('Podaj średnicę OD rury (mm)', 'Enter pipe OD (mm)');
          return;
        }
      }

      if (r == null || r <= 0) {
        _error = _rMode == 'manual'
            ? _tr('Podaj promień kolanka R (mm)', 'Enter elbow radius R (mm)')
            : _tr('Nie znaleziono R dla podanej średnicy', 'R not found for given diameter');
        return;
      }
      _rComputed = r;

      if (ang == null || ang <= 0 || ang >= 180) {
        _error = _tr('Podaj kąt kolanka θ (1°–179°)', 'Enter elbow angle θ (1°–179°)');
        return;
      }
      if (off == null || off <= 0) {
        _error = _tr('Podaj odejście (offset) > 0 (mm)', 'Enter offset > 0 (mm)');
        return;
      }

      final angRad = ang * math.pi / 180.0;
      final takeoff = r * math.tan(angRad / 2.0);
      final travel  = off / math.sin(angRad);
      final insert  = travel - 2.0 * takeoff;

      if (insert.isNaN || insert.isInfinite) {
        _error = _tr('Nieprawidłowe dane wejściowe', 'Invalid input data');
        return;
      }

      _takeoff = takeoff;
      _travel  = travel;
      _insert  = insert;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Wstawka (offset)', 'Insert (offset)')),
        _SectionDesc(_tr(
          'Model: dwa identyczne kolanka o kącie θ.\n'
          'Wstawka = travel − 2 × take-off\n'
          'travel = offset / sin(θ),  take-off = R × tan(θ/2)',
          'Model: two identical elbows at angle θ.\n'
          'Insert = travel − 2 × take-off\n'
          'travel = offset / sin(θ),  take-off = R × tan(θ/2)',
        )),

        // ── Standard promienia ──────────────────────────────
        DropdownButtonFormField<String>(
          initialValue: _rMode,
          decoration: InputDecoration(
            labelText: _tr('Standard promienia kolanka', 'Elbow radius standard'),
          ),
          items: [
            DropdownMenuItem(value: '1D',    child: Text(_tr('1D — krótki promień (SR)', '1D — short radius (SR)'))),
            DropdownMenuItem(value: '1.5D',  child: Text(_tr('1.5D — długi promień (LR) ← typowy', '1.5D — long radius (LR) ← standard'))),
            DropdownMenuItem(value: '3D',    child: Text(_tr('3D — bardzo długi promień', '3D — extra long radius'))),
            DropdownMenuItem(value: 'table', child: Text(_tr('Z tabeli NPS (ASME B16.9)', 'From NPS table (ASME B16.9)'))),
            DropdownMenuItem(value: 'manual',child: Text(_tr('Ręcznie — wpisz R', 'Manual — enter R'))),
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
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _tr('Średnica zewnętrzna rury OD (mm)', 'Pipe outside diameter OD (mm)'),
              hintText: 'np. 60.3',
            ),
            onChanged: (_) => _calc(),
          ),
          if (_rComputed != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: _kAccent.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    _tr('R = ${_rComputed!.toStringAsFixed(2)} mm', 'R = ${_rComputed!.toStringAsFixed(2)} mm'),
                    style: TextStyle(fontSize: 12, color: _kAccent.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
        ] else ...[
          TextField(
            controller: _radius,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _tr('Promień kolanka R — oś gięcia (mm)', 'Elbow bend radius R — centerline (mm)'),
              hintText: 'np. 90.45',
            ),
            onChanged: (_) => _calc(),
          ),
        ],
        const SizedBox(height: 10),

        // ── Kąt kolanka ────────────────────────────────────
        TextField(
          controller: _angle,
          keyboardType: TextInputType.number,
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
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _tr('Odejście — offset (mm)', 'Offset (mm)'),
            hintText: 'np. 200',
            helperText: _tr('Prostopadła odległość między osiami dwóch równoległych rur', 'Perpendicular distance between two parallel pipe centrelines'),
          ),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),

        if (_takeoff != null && _travel != null && _insert != null)
          _ResultCard(
            children: [
              _ResultLabel('Take-off  T = R × tan(θ/2)'),
              _ResultValue('${_takeoff!.toStringAsFixed(1)} mm'),
              const SizedBox(height: 8),
              _ResultLabel('Travel  = offset / sin(θ)'),
              _ResultValue('${_travel!.toStringAsFixed(1)} mm'),
              const SizedBox(height: 12),
              _ResultLabel(_tr('Wstawka  = travel − 2×T', 'Insert  = travel − 2×T')),
              _ResultValue(
                '${_insert!.toStringAsFixed(1)} mm',
                isPrimary: _insert! > 0,
              ),
              if (_insert! < 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _tr(
                      'Wstawka ujemna — kolanka nachodzą na siebie. '
                      'Zwiększ odejście (offset) lub zmniejsz kąt/promień.',
                      'Negative insert — elbows overlap. '
                      'Increase the offset or reduce the angle/radius.',
                    ),
                    style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                  ),
                ),
              ] else if (_insert! < 50) ...[
                const SizedBox(height: 10),
                Text(
                  _tr(
                    'Wstawka bardzo krótka — sprawdź wymiary i możliwości montażu.',
                    'Insert is very short — verify dimensions and assembly clearance.',
                  ),
                  style: const TextStyle(color: Color(0xFF78909C), fontSize: 12),
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
                  Text(_tr('Typowe promienie R dla kolan LR (1.5D):', 'Typical R values for LR elbows (1.5D):'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  for (final row in kNpsTable.where((r) =>
                      r.odMm <= 220 && [21.3, 26.9, 33.7, 42.4, 48.3, 60.3, 76.1, 88.9, 114.3, 168.3, 219.1].contains(r.odMm)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'OD ${row.odMm.toStringAsFixed(1)} mm  →  R = ${row.rMm.toStringAsFixed(1)} mm  (DN${row.dn})',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB0BEC5)),
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
  const _ReducerTab();

  @override
  State<_ReducerTab> createState() => _ReducerTabState();
}

class _ReducerTabState extends State<_ReducerTab> {
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

      final d1 = double.tryParse(_d1.text.replaceAll(',', '.'));
      final d2 = double.tryParse(_d2.text.replaceAll(',', '.'));
      final l = double.tryParse(_len.text.replaceAll(',', '.'));
      final t = double.tryParse(_target.text.replaceAll(',', '.'));

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
        _error = _tr('Docelowa średnica musi być pomiędzy ${minD.toStringAsFixed(1)} i ${maxD.toStringAsFixed(1)}', 'Target diameter must be between ${minD.toStringAsFixed(1)} and ${maxD.toStringAsFixed(1)}');
        return;
      }

      final dLarge = maxD;
      final dSmall = minD;
      final x = l * (dLarge - t) / (dLarge - dSmall);
      _cutFromLarge = x;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _SectionTitle(_tr('Skrócenie redukcji do wymaganej średnicy', 'Trim reducer to the required diameter')),
        const SizedBox(height: 12),
        TextField(
          controller: _d1,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Średnica wejścia [mm]', 'Inlet diameter [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _d2,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Średnica wyjścia [mm]', 'Outlet diameter [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _len,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Długość redukcji L [mm]', 'Reducer length L [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _target,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Wymagana średnica [mm]', 'Required diameter [mm]')),
          onChanged: (_) => _calc(),
        ),
        const SizedBox(height: 16),
        if (_cutFromLarge != null)
          _ResultCard(
            children: [
              _ResultLabel(_tr('Odmierz od większego końca i utnij na', 'Measure from the larger end and cut at')),
              _ResultValue('${_cutFromLarge!.toStringAsFixed(1)} mm', isPrimary: true),
            ],
          ),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// TAB 6: CIĘŻAR RURY
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _PipeWeightTab extends StatefulWidget {
  const _PipeWeightTab();
  @override State<_PipeWeightTab> createState() => _PipeWeightTabState();
}

class _PipeWeightTabState extends State<_PipeWeightTab> {
  final _od  = TextEditingController();
  final _t   = TextEditingController();
  final _l   = TextEditingController(text: '1000');
  final _qty = TextEditingController(text: '1');
  String _mat = 'SS';

  double? _kgm;
  double? _kgPiece;
  double? _kgTotal;
  String? _error;

  static const Map<String, double> _density = {'SS': 7930.0, 'CS': 7850.0, 'AL': 2700.0};

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_od, _t, _l, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null; _kgm = null; _kgPiece = null; _kgTotal = null;
      final od  = double.tryParse(_od.text.replaceAll(',', '.'));
      final t   = double.tryParse(_t.text.replaceAll(',', '.'));
      final l   = double.tryParse(_l.text.replaceAll(',', '.')) ?? 1000;
      final qty = double.tryParse(_qty.text.replaceAll(',', '.')) ?? 1;
      if (od == null || od <= 0) { _error = _tr('Podaj OD rury (mm)', 'Enter pipe OD (mm)'); return; }
      if (t == null || t <= 0 || t >= od / 2) { _error = _tr('Podaj poprawną grubość ścianki', 'Enter valid wall thickness'); return; }
      final rho = _density[_mat] ?? 7930.0;
      final kgm = rho * math.pi * (od - t) * t / 1e6;
      _kgm     = kgm;
      _kgPiece = kgm * l / 1000.0;
      _kgTotal = _kgPiece! * qty;
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _SectionTitle(_tr('Ciężar rury', 'Pipe weight')),
      _SectionDesc(_tr(
        'm = ρ × ρ€ × (OD − t) × t   [kg/m]\n'
        'SS 316L: ρ = 7 930 kg/m³  ·  CS: 7 850  ·  Al: 2 700',
        'm = ρ × ρ€ × (OD − t) × t   [kg/m]\n'
        'SS 316L: ρ = 7 930 kg/m³  ·  CS: 7 850  ·  Al: 2 700',
      )),
      DropdownButtonFormField<String>(
        initialValue: _mat,
        decoration: InputDecoration(labelText: _tr('Materiał', 'Material')),
        items: const [
          DropdownMenuItem(value: 'SS', child: Text('SS (nierdzewna) 7 930 kg/m³')),
          DropdownMenuItem(value: 'CS', child: Text('CS (węglowa)   7 850 kg/m³')),
          DropdownMenuItem(value: 'AL', child: Text('Al (aluminium) 2 700 kg/m³')),
        ],
        onChanged: (v) { setState(() => _mat = v ?? 'SS'); _calc(); },
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _od, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'OD (mm)', hintText: '60.3'), onChanged: (_) => _calc())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _t, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('Gr. ścianki t (mm)', 'Wall t (mm)'), hintText: '2.0'), onChanged: (_) => _calc())),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _l, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('Długość (mm)', 'Length (mm)'), hintText: '1000', suffixText: 'mm'), onChanged: (_) => _calc())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('Ilość szt.', 'Qty'), hintText: '1'), onChanged: (_) => _calc())),
      ]),
      const SizedBox(height: 16),
      if (_kgm != null) _ResultCard(children: [
        _ResultLabel(_tr('Ciężar liniowy', 'Linear weight')),
        _ResultValue('${_kgm!.toStringAsFixed(3)} kg/m'),
        const SizedBox(height: 8),
        _ResultLabel(_tr('Odcinek ${_l.text} mm', 'Section ${_l.text} mm')),
        _ResultValue('${_kgPiece!.toStringAsFixed(3)} kg'),
        const SizedBox(height: 8),
        _ResultLabel(_tr('Razem (${_qty.text} szt.)', 'Total (${_qty.text} pcs)')),
        _ResultValue('${_kgTotal!.toStringAsFixed(2)} kg', isPrimary: true),
      ]),
      if (_error != null) _ErrorText(_error!),
    ],
  );
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// TAB 7: FAZOWANIE (BEVEL)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _BevelTab extends StatefulWidget {
  const _BevelTab();
  @override State<_BevelTab> createState() => _BevelTabState();
}

class _BevelTabState extends State<_BevelTab> {
  final _t       = TextEditingController();
  final _angCtrl = TextEditingController(text: '37.5');
  final _landCtrl= TextEditingController(text: '1.0');
  final _gapCtrl = TextEditingController(text: '0');
  String _type   = 'V';

  double? _depth;
  double? _width;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);
  @override
  void dispose() {
    for (final c in [_t, _angCtrl, _landCtrl, _gapCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null; _depth = null; _width = null;
      final t    = double.tryParse(_t.text.replaceAll(',', '.'));
      final ang  = double.tryParse(_angCtrl.text.replaceAll(',', '.')) ?? 37.5;
      final land = double.tryParse(_landCtrl.text.replaceAll(',', '.')) ?? 1.0;
      if (t == null || t <= 0) { _error = _tr('Podaj grubość ścianki t (mm)', 'Enter wall thickness t (mm)'); return; }
      final depth = t - land;
      if (depth <= 0) { _error = _tr('Próg â‰¥ grubości ścianki', 'Root face â‰¥ wall thickness'); return; }
      _depth = depth;
      _width = depth * math.tan(ang * math.pi / 180.0);
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _SectionTitle(_tr('Kalkulator fazowania', 'Bevel calculator')),
      _SectionDesc(_tr('Geometria fazy wg EN ISO 9692.', 'Bevel geometry per EN ISO 9692.')),
      DropdownButtonFormField<String>(
        initialValue: _type,
        decoration: InputDecoration(labelText: _tr('Typ złącza', 'Joint type')),
        items: const [
          DropdownMenuItem(value: 'V', child: Text('V — jednofazowe (typowe TIG)')),
          DropdownMenuItem(value: 'X', child: Text('X — dwustronne (grube ściany)')),
        ],
        onChanged: (v) { setState(() => _type = v ?? 'V'); _calc(); },
      ),
      const SizedBox(height: 10),
      TextField(controller: _t, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('Grubość ścianki t (mm)', 'Wall thickness t (mm)'), hintText: '8'), onChanged: (_) => _calc()),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _angCtrl, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _tr('Kąt α (°)', 'Angle α (°)'), hintText: '37.5', suffixText: '°', helperText: _tr('Typowo 30–37.5°', 'Typical 30–37.5°')),
            onChanged: (_) => _calc())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _landCtrl, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _tr('Próg b (mm)', 'Root face b (mm)'), hintText: '1.0', suffixText: 'mm', helperText: _tr('Typowo 0.5–2 mm', 'Typ. 0.5–2 mm')),
            onChanged: (_) => _calc())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _gapCtrl, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _tr('Szczelina g (mm)', 'Root gap g (mm)'), hintText: '2', suffixText: 'mm'),
            onChanged: (_) => _calc())),
      ]),
      const SizedBox(height: 16),
      if (_depth != null) _ResultCard(children: [
        _ResultLabel(_tr('Głębokość fazy h', 'Bevel depth h')),
        _ResultValue('${_depth!.toStringAsFixed(2)} mm'),
        const SizedBox(height: 8),
        _ResultLabel(_tr('Szerokość fazy na powierzchni', 'Bevel width at surface')),
        _ResultValue('${_width!.toStringAsFixed(2)} mm', isPrimary: true),
        const SizedBox(height: 10),
        Text(_tr(
          '• Fazuj pod kątem ${_angCtrl.text}° od progu (land) ${_landCtrl.text} mm\n'
          '• Szerokość otworu złącza: ${((double.tryParse(_gapCtrl.text) ?? 2) + 2 * _width!).toStringAsFixed(1)} mm\n'
          '${_type == "X" ? "• Złącze X: fazuj z obu stron po ${(_depth! / 2).toStringAsFixed(2)} mm" : ""}',
          '• Bevel at ${_angCtrl.text}° from root face ${_landCtrl.text} mm\n'
          '• Joint opening width: ${((double.tryParse(_gapCtrl.text) ?? 2) + 2 * _width!).toStringAsFixed(1)} mm\n'
          '${_type == "X" ? "• X joint: bevel both sides by ${(_depth! / 2).toStringAsFixed(2)} mm each" : ""}',
        ), style: const TextStyle(fontSize: 12, color: _kSubtle, height: 1.6)),
      ]),
      if (_error != null) _ErrorText(_error!),
    ],
  );
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// TAB 8: DYLATACJA CIEPLNA
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _ThermalExpansionTab extends StatefulWidget {
  const _ThermalExpansionTab();
  @override State<_ThermalExpansionTab> createState() => _ThermalExpansionTabState();
}

class _ThermalExpansionTabState extends State<_ThermalExpansionTab> {
  final _l  = TextEditingController();
  final _dt = TextEditingController();
  final _t1 = TextEditingController();
  final _t2 = TextEditingController();
  String _mat = 'SS316L';

  double? _dLmm;
  double? _dLm;
  String? _error;

  static const Map<String, double> _alpha = {
    'SS316L': 16.0e-6, 'SS304L': 17.2e-6,
    'CS':     12.0e-6, 'CuNi':  17.0e-6, 'Al': 23.6e-6,
  };

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
      _error = null; _dLmm = null; _dLm = null;
      double? dt;
      final t1v = double.tryParse(_t1.text.replaceAll(',', '.'));
      final t2v = double.tryParse(_t2.text.replaceAll(',', '.'));
      if (t1v != null && t2v != null) {
        dt = (t2v - t1v).abs();
        _dt.text = dt.toStringAsFixed(1);
      } else {
        dt = double.tryParse(_dt.text.replaceAll(',', '.'));
      }
      final l = double.tryParse(_l.text.replaceAll(',', '.'));
      if (l == null || l <= 0) { _error = _tr('Podaj długość rurociągu (m)', 'Enter pipeline length (m)'); return; }
      if (dt == null || dt < 0) { _error = _tr('Podaj różnicę temperatur ΔT', 'Enter temperature difference ΔT'); return; }
      final a = _alpha[_mat] ?? 16e-6;
      _dLm  = a * l * dt;
      _dLmm = _dLm! * 1000.0;
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
    children: [
      _SectionTitle(_tr('Dylatacja cieplna', 'Thermal expansion')),
      _SectionDesc(_tr(
        'ΔL = α × L × ΔT\n'
        'Ważne przy rurociągach instalowanych na zimno, pracujących w podwyższonej temperaturze.',
        'ΔL = α × L × ΔT\n'
        'Important for pipelines installed cold and operating at elevated temperature.',
      )),
      DropdownButtonFormField<String>(
        initialValue: _mat,
        decoration: InputDecoration(labelText: _tr('Materiał', 'Material')),
        items: const [
          DropdownMenuItem(value: 'SS316L', child: Text('SS 316L   α = 16.0 ×10â»â¶ /°C')),
          DropdownMenuItem(value: 'SS304L', child: Text('SS 304L   α = 17.2 ×10â»â¶ /°C')),
          DropdownMenuItem(value: 'CS',     child: Text('CS (węgl.) α = 12.0 ×10â»â¶ /°C')),
          DropdownMenuItem(value: 'CuNi',   child: Text('CuNi 90/10 α = 17.0 ×10â»â¶ /°C')),
          DropdownMenuItem(value: 'Al',     child: Text('Aluminium  α = 23.6 ×10â»â¶ /°C')),
        ],
        onChanged: (v) { setState(() => _mat = v ?? 'SS316L'); _calc(); },
      ),
      const SizedBox(height: 10),
      TextField(controller: _l, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('Długość rurociągu L (m)', 'Pipeline length L (m)'), hintText: '50', suffixText: 'm'), onChanged: (_) => _calc()),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _t1, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('T montażu (°C)', 'Install. T (°C)'), hintText: '20', suffixText: '°C'), onChanged: (_) => _calc())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _t2, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _tr('T pracy (°C)', 'Oper. T (°C)'), hintText: '120', suffixText: '°C'), onChanged: (_) => _calc())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _dt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'ΔT (°C)', hintText: '100', suffixText: '°C', helperText: _tr('lub T1 i T2', 'or T1 and T2')), onChanged: (_) => _calc())),
      ]),
      const SizedBox(height: 16),
      if (_dLmm != null) _ResultCard(children: [
        _ResultLabel('ΔL'),
        _ResultValue('${_dLmm!.toStringAsFixed(1)} mm', isPrimary: true),
        _ResultValue('${_dLm!.toStringAsFixed(4)} m'),
        const SizedBox(height: 10),
        Text(
          _dLmm! > 30
            ? _tr('âš  Dylatacja > 30 mm — wymagana kompensacja (lira, przegub, dylatator).', 'âš  Expansion > 30 mm — compensation required (expansion loop, joint or bellows).')
            : _tr('âœ“ Dylatacja mała — sprawdź czy trasa ma wystarczający odcinek elastyczny.', 'âœ“ Small expansion — verify the route has sufficient flexible section.'),
          style: TextStyle(fontSize: 12, color: _dLmm! > 30 ? _kAccentWarm : _kSubtle, fontWeight: _dLmm! > 30 ? FontWeight.w600 : FontWeight.normal),
        ),
      ]),
      if (_error != null) _ErrorText(_error!),
    ],
  );
}
