// Czas stygnięcia t8/5 (EN 1011-2:2001 zał. D): wynik, werdykt względem
// okna z WPS / od producenta stali, podpowiedź odwrotna (jakie Q, jakie T0)
// i wykres t8/5 w funkcji energii liniowej. Logika: domain/welding/
// cooling_time.dart; energia liniowa: domain/welding/heat_input.dart.
// Uwagi w zastrzeżeniu (stale C-Mn i niskostopowe, równe grubości, Q²
// w 2D) — za opracowaniami Ovako, MIGAL.CO i Lorch (źródła [O] [M] [L]
// w cooling_time.dart); zakresu stosowania z tekstu normy nie potwierdzono,
// więc ekran go nie przypisuje normie.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/welding/cooling_time.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/welding/heat_input.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';

class CoolingTimePage extends StatefulWidget {
  const CoolingTimePage({super.key});

  @override
  State<CoolingTimePage> createState() => _CoolingTimePageState();
}

class _CoolingTimePageState extends State<CoolingTimePage>
    with ToolHandleHost<CoolingTimePage>
    implements InputToolHandle {
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'input_mode': _fromParams ? 'parameters' : 'heat_input',
        'q_kj_mm': _heatInput,
        if (_fromParams) ...{
          'volts': _parse(_u),
          'amps': _parse(_i),
          'travel_mm_min': _parse(_v),
          'process': _process.code,
        },
        'preheat_c': _parse(_t0),
        'thickness_mm': _parse(_d),
        'shape': _shape.name,
        'window_min_s': parseDecimal(_wMin.text),
        'window_max_s': parseDecimal(_wMax.text),
        'window_source': 'visible_form_unverified',
      });
  @override
  String get toolId => 'cooling_time';
  @override
  Set<String> get supportedFields => const {
        'q_kj_mm',
        'preheat_c',
        'thickness_mm',
        'shape',
        'window_min_s',
        'window_max_s',
        'input_mode',
        'process',
        'volts',
        'amps',
        'travel_mm_min',
      };
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    markReady();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final rejected = fields.keys.toSet().difference(supportedFields);
    double? n(String k) =>
        fields[k] is num ? (fields[k] as num).toDouble() : null;
    final q = n('q_kj_mm'), t = n('preheat_c'), d = n('thickness_mm');
    final mode = fields['input_mode'] ?? 'heat_input';
    if (!const ['heat_input', 'parameters'].contains(mode)) {
      rejected.add('input_mode');
    }
    final process = fields['process'] is String
        ? WeldingProcess.fromCode(fields['process'] as String)
        : null;
    const parameterKeys = ['process', 'volts', 'amps', 'travel_mm_min'];
    if (mode == 'parameters') {
      if (process == null) rejected.add('process');
      for (final key in parameterKeys.skip(1)) {
        final value = n(key);
        if (value == null || !value.isFinite || value <= 0) rejected.add(key);
      }
      if (rejected.isEmpty) {
        final computed = heatInputKJPerMm(
            volts: n('volts')!,
            amps: n('amps')!,
            travelMmPerMin: n('travel_mm_min')!,
            efficiency: process!.thermalEfficiency,
            standard: HeatInputStandard.en1011);
        if (computed == null ||
            q == null ||
            (computed - q).abs() > 1e-9 * (computed.abs() + 1)) {
          rejected.add('q_kj_mm');
        }
      }
    } else if (parameterKeys.any(fields.containsKey)) {
      rejected.addAll(parameterKeys.where(fields.containsKey));
    }
    final shape =
        WeldShape.values.where((s) => s.name == fields['shape']).firstOrNull;
    if (q == null || !q.isFinite || q <= 0) rejected.add('q_kj_mm');
    if (t == null || !t.isFinite || t <= -273.15 || t >= 500) {
      rejected.add('preheat_c');
    }
    if (d == null || !d.isFinite || d <= 0) rejected.add('thickness_mm');
    if (shape == null) rejected.add('shape');
    for (final k in const ['window_min_s', 'window_max_s']) {
      if (fields.containsKey(k) &&
          (n(k) == null || !n(k)!.isFinite || n(k)! <= 0)) {
        rejected.add(k);
      }
    }
    final min = n('window_min_s'), max = n('window_max_s');
    if (min != null && max != null && min > max) {
      rejected.addAll({'window_min_s', 'window_max_s'});
    }
    if (rejected.isEmpty &&
        coolingTime(
                heatInputKjMm: q!,
                preheatC: t!,
                thicknessMm: d!,
                shape: shape!) ==
            null) {
      rejected.add('q_kj_mm');
    }
    if (rejected.isNotEmpty || !mounted) {
      return rejected.isEmpty ? fields.keys.toSet() : rejected;
    }
    setState(() {
      _fromParams = mode == 'parameters';
      if (_fromParams) {
        _process = process!;
        _u.text = n('volts').toString();
        _i.text = n('amps').toString();
        _v.text = n('travel_mm_min').toString();
      } else {
        _q.text = q.toString();
      }
      _t0.text = t.toString();
      _d.text = d.toString();
      _shape = shape!;
      // An example window is never the user's WPS window.
      _wMin.text = min?.toString() ?? '';
      _wMax.text = max?.toString() ?? '';
    });
    return {};
  }

  // Q ≈ 1 kJ/mm, T0 100 °C, blacha 20 mm, ścieg wypełniający czołowej —
  // typowy punkt wyjścia dla S690; okno 5–15 s to tylko przykład.
  final _q = TextEditingController(text: '1,0');
  final _u = TextEditingController(text: '28');
  final _i = TextEditingController(text: '250');
  final _v = TextEditingController(text: '350');
  final _t0 = TextEditingController(text: '100');
  final _d = TextEditingController(text: '20');
  final _wMin = TextEditingController(text: '5');
  final _wMax = TextEditingController(text: '15');

  /// true — Q liczone z U, I, v i k procesu; false — Q wpisane z WPS.
  bool _fromParams = false;
  WeldingProcess _process = WeldingProcess.gmaw;
  WeldShape _shape = WeldShape.buttFillRun;

  @override
  void dispose() {
    for (final c in [_q, _u, _i, _v, _t0, _d, _wMin, _wMax]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  /// Liczba z przecinkiem w PL, kropką w EN — stała liczba miejsc.
  String _n(double v, [int decimals = 1]) {
    final s = v.toStringAsFixed(decimals);
    return _en ? s : s.replaceAll('.', ',');
  }

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t);
  }

  double? _parseWindow(TextEditingController c) => c.text.trim().isEmpty
      ? null
      : (parseDecimal(c.text.trim()) ?? double.nan);

  /// Q [kJ/mm] wg EN 1011-1 (z k). Z parametrów — przez heat_input.dart.
  double? get _heatInput {
    if (!_fromParams) return _parse(_q);
    final u = _parse(_u), i = _parse(_i), v = _parse(_v);
    if (u == null || i == null || v == null) return null;
    return heatInputKJPerMm(
      volts: u,
      amps: i,
      travelMmPerMin: v,
      standard: HeatInputStandard.en1011,
      efficiency: _process.thermalEfficiency,
    );
  }

  String _shapeLabel(WeldShape s) => switch (s) {
        WeldShape.beadOnPlate =>
          context.tr(pl: 'Ścieg na blasze', en: 'Bead on plate'),
        WeldShape.buttFillRun =>
          context.tr(pl: 'Wypełnienie czołowej', en: 'Butt weld fill run'),
        WeldShape.filletCorner => context.tr(
            pl: 'Pachwinowa 1-ściegowa, narożna',
            en: 'Single-run fillet, corner'),
        WeldShape.filletTee => context.tr(
            pl: 'Pachwinowa 1-ściegowa, teowa',
            en: 'Single-run fillet, T-joint'),
      };

  String _shapeFactors(WeldShape s) {
    final f2 =
        s.hasF2Range ? '${_n(s.f2Min, 2)}–${_n(s.f2Max, 2)}' : _n(s.f2Min, 2);
    return 'F2 = $f2 · F3 = ${_n(s.f3, 2)}';
  }

  Widget _field(
    TextEditingController c,
    String label, {
    required Key key,
    String? unit,
    String? helper,
    bool signed = false,
  }) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(signed: signed),
        inputFormatters: numberInputFormatters(signed: signed),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  @override
  Widget build(BuildContext context) {
    final q = _heatInput;
    final t0 = _parse(_t0);
    final d = _parse(_d);
    // Niepusta, ale nieczytelna granica okna („5,5,5”) to błąd wpisu —
    // NaN daje werdykt „złe okno”, a nie po cichu „brak granicy”.
    final wMin = _parseWindow(_wMin);
    final wMax = _parseWindow(_wMax);

    final problems = <String>[
      if (q == null || q <= 0)
        _fromParams
            ? context.tr(
                pl: 'Podaj napięcie, prąd i prędkość spawania (> 0).',
                en: 'Enter voltage, current and travel speed (> 0).')
            : context.tr(
                pl: 'Podaj energię liniową Q (> 0 kJ/mm).',
                en: 'Enter the heat input Q (> 0 kJ/mm).'),
      if (t0 == null || t0 >= 500)
        context.tr(
            pl: 'Podaj temperaturę podgrzewania / międzyściegową (poniżej 500 °C).',
            en: 'Enter the preheat / interpass temperature (below 500 °C).'),
      if (d == null || d <= 0)
        context.tr(
            pl: 'Podaj grubość blachy (> 0 mm).',
            en: 'Enter the plate thickness (> 0 mm).'),
    ];
    final r = problems.isEmpty
        ? coolingTime(
            heatInputKjMm: q!, preheatC: t0!, thicknessMm: d!, shape: _shape)
        : null;
    if (r == null && problems.isEmpty) {
      problems.add(context.tr(
          pl: 'Dane są poza zakresem obliczeń. Sprawdź Q, temperaturę i grubość.',
          en: 'Values are outside the calculation range. Check Q, temperature and thickness.'));
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(
              context.tr(pl: 'Czas stygnięcia t8/5', en: 'Cooling time t8/5'))),
      body: ListView(
        key: const ValueKey('cool-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _energySection(q),
          _jointSection(),
          _windowSection(),
          if (r == null)
            QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: problems.join('\n'),
            )
          else ...[
            _resultSection(r, wMin, wMax),
            _inverseSection(r, wMin, wMax),
            _chartSection(r, wMin, wMax),
          ],
          _disclaimer(),
        ],
      ),
    );
  }

  // ── Wejście ────────────────────────────────────────────────────────────

  Widget _energySection(double? q) {
    return QuoteSection(
      title: context.tr(pl: 'Energia liniowa Q', en: 'Heat input Q'),
      subtitle: context.tr(
          pl: 'Q wg EN 1011-1 — z k procesu: Q = k·U·I·60/(v·1000). Energia łuku '
              'z WPS wg ASME IX (bez k) to inna liczba.',
          en: 'Q per EN 1011-1 — with the process factor k: Q = k·U·I·60/(v·1000). '
              'ASME IX arc energy (no k) is a different number.'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const ValueKey('cool-mode-q'),
              label: Text(context.tr(pl: 'Q z WPS', en: 'Q from WPS')),
              selected: !_fromParams,
              onSelected: (_) => setState(() => _fromParams = false),
            ),
            ChoiceChip(
              key: const ValueKey('cool-mode-params'),
              label: Text(context.tr(pl: 'Z U, I, v', en: 'From U, I, v')),
              selected: _fromParams,
              onSelected: (_) => setState(() => _fromParams = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_fromParams)
          _field(_q, context.tr(pl: 'Energia liniowa Q', en: 'Heat input Q'),
              key: const ValueKey('cool-q'), unit: 'kJ/mm')
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in WeldingProcess.values)
                ChoiceChip(
                  key: ValueKey('cool-process-${p.name}'),
                  label: Text(p.euLabel),
                  selected: _process == p,
                  onSelected: (_) => setState(() => _process = p),
                ),
            ],
          ),
          _caption(context.tr(
              pl: 'k = ${_n(_process.thermalEfficiency, 1)} (EN 1011-1 tab. 1)',
              en: 'k = ${_n(_process.thermalEfficiency, 1)} (EN 1011-1 Table 1)')),
          const SizedBox(height: 10),
          FieldPair(
            left: _field(_u, context.tr(pl: 'Napięcie U', en: 'Voltage U'),
                key: const ValueKey('cool-u'), unit: 'V'),
            right: _field(_i, context.tr(pl: 'Prąd I', en: 'Current I'),
                key: const ValueKey('cool-i'), unit: 'A'),
          ),
          const SizedBox(height: 10),
          _field(
              _v, context.tr(pl: 'Prędkość spawania v', en: 'Travel speed v'),
              key: const ValueKey('cool-v'), unit: 'mm/min'),
          if (q != null && q > 0)
            _caption(context.tr(
                pl: 'Q = ${_n(q, 2)} kJ/mm', en: 'Q = ${_n(q, 2)} kJ/mm')),
        ],
      ],
    );
  }

  Widget _jointSection() {
    return QuoteSection(
      title:
          context.tr(pl: 'Złącze i temperatura', en: 'Joint and temperature'),
      children: [
        FieldPair(
          left: _field(
              _t0,
              context.tr(
                  pl: 'Podgrzewanie / międzyściegowa T0',
                  en: 'Preheat / interpass T0'),
              key: const ValueKey('cool-t0'),
              unit: '°C',
              signed: true),
          right: _field(
              _d, context.tr(pl: 'Grubość blachy d', en: 'Plate thickness d'),
              key: const ValueKey('cool-d'), unit: 'mm'),
        ),
        const SizedBox(height: 14),
        Text(context.tr(pl: 'Rodzaj spoiny', en: 'Type of weld'),
            style: const TextStyle(color: kTextSec, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in WeldShape.values)
              ChoiceChip(
                key: ValueKey('cool-shape-${s.name}'),
                label: Text(_shapeLabel(s)),
                selected: _shape == s,
                onSelected: (_) => setState(() => _shape = s),
              ),
          ],
        ),
        _caption(context.tr(
            pl: '${_shapeFactors(_shape)} (EN 1011-2 tabl. D.1)',
            en: '${_shapeFactors(_shape)} (EN 1011-2 Table D.1)')),
      ],
    );
  }

  Widget _windowSection() {
    return QuoteSection(
      title: context.tr(pl: 'Okno t8/5', en: 't8/5 window'),
      subtitle: context.tr(
          pl: 'Z WPS albo zaleceń producenta stali. Wystarczy jedna granica.',
          en: 'From the WPS or the steel maker. One limit is enough.'),
      children: [
        FieldPair(
          left:
              _field(_wMin, 'min', key: const ValueKey('cool-wmin'), unit: 's'),
          right:
              _field(_wMax, 'max', key: const ValueKey('cool-wmax'), unit: 's'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (n, p) in _windowExamples.indexed)
              ActionChip(
                key: ValueKey('cool-preset-$n'),
                label: Text('${p.steel} · ${_n(p.min, 0)}–${_n(p.max, 0)} s'),
                onPressed: () => setState(() {
                  _wMin.text = _n(p.min, 0);
                  _wMax.text = _n(p.max, 0);
                }),
              ),
          ],
        ),
        _caption(context.tr(
            pl: 'Przykłady z kart producentów (SSAB „Welding of Strenx”, '
                'Dillinger) — sprawdź aktualne wydanie karty swojej stali.',
            en: 'Examples from steel makers’ leaflets (SSAB “Welding of '
                'Strenx”, Dillinger) — check the current sheet for your steel.')),
      ],
    );
  }

  /// Przykładowe okna t8/5 z kart producentów (stan na 2026-10):
  ///  • SSAB „Welding of Strenx” (2026): Strenx 960 E / 1100 E / 1300 E
  ///    5–15 s; Strenx 700 E / 900 E 5–20 s.
  ///  • Dillinger, karty DILLIMAX: 690 — 5–20 s; 890 — 5–12 s.
  /// Producenci zmieniają zalecenia między wydaniami (np. Strenx 700 w 2018
  /// miał 5–25 s), dlatego to tylko skróty do wpisania, nie dane wiążące.
  static const _windowExamples = <({String steel, double min, double max})>[
    (steel: 'Strenx 960 E', min: 5, max: 15),
    (steel: 'Strenx 700 E', min: 5, max: 20),
    (steel: 'DILLIMAX 890', min: 5, max: 12),
    (steel: 'DILLIMAX 690', min: 5, max: 20),
  ];

  // ── Wynik ──────────────────────────────────────────────────────────────

  String _tText(double a, double b) =>
      (b - a).abs() < 0.05 ? _n(a) : '${_n(a)}–${_n(b)}';

  String _flowText(HeatFlow f) => f == HeatFlow.threeD
      ? context.tr(
          pl: 'przepływ 3D (gruba blacha)', en: '3D flow (thick plate)')
      : context.tr(
          pl: 'przepływ 2D (cienka blacha)', en: '2D flow (thin plate)');

  String _windowText(double? wMin, double? wMax) {
    if (wMin != null && wMax != null) return '${_n(wMin)}–${_n(wMax)} s';
    if (wMin != null) return '≥ ${_n(wMin)} s';
    return '≤ ${_n(wMax!)} s';
  }

  Widget _resultSection(CoolingTimeResult r, double? wMin, double? wMax) {
    final verdict = checkT85Window(r.t85MinS, r.t85MaxS, min: wMin, max: wMax);
    final (fLo, fHi) = r.shapeFactor;
    final fName = r.flow == HeatFlow.threeD ? 'F3' : 'F2';
    final fText = (fHi - fLo).abs() < 1e-9
        ? '$fName = ${_n(fLo, 2)}'
        : '$fName = ${_n(fLo, 2)}–${_n(fHi, 2)}';
    return QuoteSection(
      title: context.tr(pl: 'Wynik', en: 'Result'),
      children: [
        Readout(
          key: const ValueKey('cool-result'),
          label: 't8/5',
          value: _tText(r.t85MinS, r.t85MaxS),
          unit: 's · ${_flowText(r.flow)}',
          hot: true,
        ),
        const SizedBox(height: 12),
        _verdictNotice(verdict, r, wMin, wMax),
        _kv(context.tr(pl: 'Energia liniowa Q', en: 'Heat input Q'),
            '${_n(r.heatInputKjMm, 2)} kJ/mm'),
        _kv(
            context.tr(
                pl: 'Grubość przejściowa d_t', en: 'Transition thickness d_t'),
            '${_n(r.transitionThicknessMm)} mm'),
        _kv(
            context.tr(pl: 'Model', en: 'Model'),
            r.flow == HeatFlow.threeD
                ? context.tr(pl: '3D (d ≥ d_t)', en: '3D (d ≥ d_t)')
                : context.tr(pl: '2D (d < d_t)', en: '2D (d < d_t)')),
        _kv(context.tr(pl: 'Współczynnik kształtu', en: 'Shape factor'), fText),
        _kv(context.tr(pl: 't8/5 wg wzoru 3D', en: 't8/5 by 3D equation'),
            '${_n(r.t85ThreeDS)} s'),
        _kv(context.tr(pl: 't8/5 wg wzoru 2D', en: 't8/5 by 2D equation'),
            '${_tText(r.t85TwoDMinS, r.t85TwoDMaxS)} s'),
      ],
    );
  }

  Widget _verdictNotice(
      T85Verdict v, CoolingTimeResult r, double? wMin, double? wMax) {
    final lo = wMin == null ? '—' : _n(wMin);
    final hi = wMax == null ? '—' : _n(wMax);
    // Przy granicy wynik z 1 miejscem („5,0 s”) wyglądałby jak sprzeczność
    // z werdyktem „poniżej 5,0 s” — w werdykcie 2 miejsca.
    final t2 = (r.t85MaxS - r.t85MinS).abs() < 0.005
        ? _n(r.t85MinS, 2)
        : '${_n(r.t85MinS, 2)}–${_n(r.t85MaxS, 2)}';
    final (Color color, IconData icon, String text) = switch (v) {
      T85Verdict.notSet => (
          kTextSec,
          Icons.info_outline,
          context.tr(
              pl: 'Wpisz okno t8/5 z WPS lub od producenta stali, żeby '
                  'dostać werdykt i podpowiedź.',
              en: 'Enter the t8/5 window from the WPS or the steel maker to '
                  'get a verdict and a hint.'),
        ),
      T85Verdict.invalidWindow => (
          kFail,
          Icons.error_outline,
          context.tr(
              pl: 'Okno t8/5: wpisz liczby > 0, min nie większe niż max.',
              en: 't8/5 window: enter numbers > 0, min not above max.'),
        ),
      T85Verdict.inWindow => (
          kPass,
          Icons.check_circle_outline,
          context.tr(
              pl: 'W oknie ${_windowText(wMin, wMax)}.',
              en: 'Within the ${_windowText(wMin, wMax)} window.'),
        ),
      T85Verdict.tooShort => (
          kFail,
          Icons.ac_unit,
          context.tr(
              pl: 'Za krótko — $t2 s, poniżej $lo s. Stygnie za szybko: '
                  'ryzyko twardej, kruchej SWC. Zwiększ Q albo T0.',
              en: 'Too short — $t2 s, below $lo s. Cools too fast: risk of '
                  'a hard, brittle HAZ. Raise Q or T0.'),
        ),
      T85Verdict.tooLong => (
          kFail,
          Icons.local_fire_department_outlined,
          context.tr(
              pl: 'Za długo — $t2 s, powyżej $hi s. Stygnie za wolno: '
                  'spadek udarności i wytrzymałości SWC. Zmniejsz Q albo T0.',
              en: 'Too long — $t2 s, above $hi s. Cools too slowly: loss of '
                  'HAZ toughness and strength. Lower Q or T0.'),
        ),
      T85Verdict.partly => (
          kWarn,
          Icons.warning_amber_outlined,
          context.tr(
              pl: 'Częściowo poza oknem ${_windowText(wMin, wMax)}: dla tej '
                  'spoiny pachwinowej norma podaje F2 jako przedział '
                  '(${_shapeFactors(r.shape)}), więc wynik też jest przedziałem. '
                  'Ustaw parametry tak, żeby cały przedział mieścił się w oknie.',
              en: 'Partly outside the ${_windowText(wMin, wMax)} window: for this '
                  'fillet weld the standard gives F2 as a range '
                  '(${_shapeFactors(r.shape)}), so the result is a range too. '
                  'Set the parameters so the whole range fits.'),
        ),
    };
    return KeyedSubtree(
      key: ValueKey('cool-verdict-${v.name}'),
      child: QuoteNotice(color: color, icon: icon, text: text),
    );
  }

  Widget _kv(String k, String v) => CopyOnLongPress(
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kText,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );

  // ── Podpowiedź odwrotna ────────────────────────────────────────────────

  String _rangeText(List<SolvedRange> ranges, String unit, int decimals,
      {required double searchMin, required double searchMax}) {
    String one(SolvedRange s) {
      if (s.clippedLow && s.clippedHigh) {
        return context.tr(
            pl: 'cały sprawdzony zakres ${_n(searchMin, decimals)}–${_n(searchMax, decimals)} $unit',
            en: 'the whole checked range ${_n(searchMin, decimals)}–${_n(searchMax, decimals)} $unit');
      }
      if (s.clippedLow) return '≤ ${_n(s.max, decimals)} $unit';
      if (s.clippedHigh) {
        return context.tr(
            pl: '≥ ${_n(s.min, decimals)} $unit (sprawdzone do ${_n(searchMax, decimals)})',
            en: '≥ ${_n(s.min, decimals)} $unit (checked up to ${_n(searchMax, decimals)})');
      }
      return '${_n(s.min, decimals)}–${_n(s.max, decimals)} $unit';
    }

    return ranges.map(one).join(context.tr(pl: ' albo ', en: ' or '));
  }

  Widget _inverseSection(CoolingTimeResult r, double? wMin, double? wMax) {
    final windowOk = (wMin != null || wMax != null) &&
        checkT85Window(r.t85MinS, r.t85MaxS, min: wMin, max: wMax) !=
            T85Verdict.invalidWindow;
    if (!windowOk) return const SizedBox.shrink();
    final qRanges = heatInputRangesForWindow(
        preheatC: r.preheatC,
        thicknessMm: r.thicknessMm,
        shape: r.shape,
        min: wMin,
        max: wMax);
    final tRanges = preheatRangesForWindow(
        heatInputKjMm: r.heatInputKjMm,
        thicknessMm: r.thicknessMm,
        shape: r.shape,
        min: wMin,
        max: wMax);

    // Z U, I, k: przedział Q → przedział prędkości (odwrotnie: większe Q =
    // mniejsza prędkość).
    String? speedText;
    if (_fromParams && qRanges.isNotEmpty) {
      final u = _parse(_u), i = _parse(_i);
      if (u != null && i != null) {
        String speed(SolvedRange s) {
          final k = _process.thermalEfficiency;
          final vFast = travelSpeedForHeatInput(
              volts: u, amps: i, efficiency: k, heatInputKjMm: s.min);
          final vSlow = travelSpeedForHeatInput(
              volts: u, amps: i, efficiency: k, heatInputKjMm: s.max);
          if (vFast == null || vSlow == null) return '';
          if (s.clippedLow && s.clippedHigh) return '';
          if (s.clippedLow) return '≥ ${_n(vSlow, 0)} mm/min';
          if (s.clippedHigh) return '≤ ${_n(vFast, 0)} mm/min';
          return '${_n(vSlow, 0)}–${_n(vFast, 0)} mm/min';
        }

        speedText = qRanges
            .map(speed)
            .where((s) => s.isNotEmpty)
            .join(context.tr(pl: ' albo ', en: ' or '));
      }
    }

    final none = context.tr(
        pl: 'brak rozwiązania w sprawdzanym zakresie',
        en: 'no solution in the checked range');
    return QuoteSection(
      title: context.tr(pl: 'Jak trafić w okno', en: 'How to hit the window'),
      subtitle: context.tr(
          pl: 'Każdy wiersz zmienia jeden parametr, pozostałe jak wyżej.',
          en: 'Each line changes one parameter, the rest as above.'),
      children: [
        _kv(
          context.tr(
              pl: 'Energia Q (T0 = ${_n(r.preheatC, 0)} °C)',
              en: 'Heat input Q (T0 = ${_n(r.preheatC, 0)} °C)'),
          qRanges.isEmpty
              ? none
              : _rangeText(qRanges, 'kJ/mm', 2,
                  searchMin: kQSearchMinKjMm, searchMax: kQSearchMaxKjMm),
        ),
        if (speedText != null && speedText.isNotEmpty)
          _kv(
            context.tr(
                pl: 'Prędkość przy ${_n(_parse(_u)!, 0)} V / ${_n(_parse(_i)!, 0)} A',
                en: 'Travel speed at ${_n(_parse(_u)!, 0)} V / ${_n(_parse(_i)!, 0)} A'),
            speedText,
          ),
        _kv(
          context.tr(
              pl: 'Temperatura T0 (Q = ${_n(r.heatInputKjMm, 2)} kJ/mm)',
              en: 'Temperature T0 (Q = ${_n(r.heatInputKjMm, 2)} kJ/mm)'),
          tRanges.isEmpty
              ? none
              : _rangeText(tRanges, '°C', 0,
                  searchMin: kT0SearchMinC, searchMax: kT0SearchMaxC),
        ),
        _caption(context.tr(
            pl: 'T0 nie niżej niż minimum podgrzewania z WPS (zimne pęknięcia, '
                'EN 1011-2 zał. C) i nie wyżej niż maks. temperatura '
                'międzyściegowa z WPS.',
            en: 'T0 not below the WPS minimum preheat (cold cracking, '
                'EN 1011-2 Annex C) and not above the WPS maximum interpass '
                'temperature.')),
      ],
    );
  }

  // ── Wykres ─────────────────────────────────────────────────────────────

  Widget _chartSection(CoolingTimeResult r, double? wMin, double? wMax) {
    final validWindow =
        checkT85Window(r.t85MinS, r.t85MaxS, min: wMin, max: wMax) !=
            T85Verdict.invalidWindow;
    return QuoteSection(
      title: context.tr(pl: 't8/5 w funkcji Q', en: 't8/5 versus Q'),
      subtitle: context.tr(
          pl: 'T0 = ${_n(r.preheatC, 0)} °C, d = ${_n(r.thicknessMm, 0)} mm. '
              'Pas — okno t8/5, punkt — Twoje Q, kreska — przejście 3D/2D.',
          en: 'T0 = ${_n(r.preheatC, 0)} °C, d = ${_n(r.thicknessMm, 0)} mm. '
              'Band — t8/5 window, dot — your Q, dashed line — 3D/2D switch.'),
      children: [
        CoolingTimeChart(
          key: const ValueKey('cool-chart'),
          result: r,
          windowMin: validWindow ? wMin : null,
          windowMax: validWindow ? wMax : null,
          semanticLabel: context.tr(
              pl: 'Wykres czasu t8/5 w funkcji energii liniowej',
              en: 'Chart of t8/5 versus heat input'),
        ),
      ],
    );
  }

  // ── Zastrzeżenie ───────────────────────────────────────────────────────

  Widget _disclaimer() {
    return QuoteNotice(
      text: context.tr(
          pl: 'Model uproszczony z EN 1011-2:2001 zał. D — szacunek, nie pomiar. '
              'Wiążą WPS/WPQR i zalecenia producenta stali; wynik nie zastępuje '
              'kwalifikacji technologii. Uwagi z opracowań przytaczających te wzory '
              '(nie cytat z normy): wzory dotyczą stali węglowo-manganowych '
              'i niskostopowych; liczone dla elementów o równej grubości — przy '
              'różnych grubościach wynik jest orientacyjny; w przepływie 2D błąd Q '
              'wchodzi do kwadratu. Q musi być energią liniową wg EN 1011-1 (z k), '
              'a T0 — temperaturą przed danym ściegiem.',
          en: 'Simplified model from EN 1011-2:2001 Annex D — an estimate, not a '
              'measurement. The WPS/WPQR and the steel maker’s recommendations are '
              'binding; this does not replace procedure qualification. Notes from '
              'publications quoting these equations (not a quote from the '
              'standard): they apply to C-Mn and low-alloy steels; they assume '
              'members of equal thickness — with unequal thickness the result is '
              'indicative only; in 2D flow an error in Q is squared. Q must be the '
              'EN 1011-1 heat input (with k) and T0 the temperature before the pass.'),
    );
  }
}

/// Wykres t8/5(Q) dla bieżącego T0, d i rodzaju spoiny.
class CoolingTimeChart extends StatelessWidget {
  const CoolingTimeChart({
    super.key,
    required this.result,
    required this.semanticLabel,
    this.windowMin,
    this.windowMax,
    this.height = 220,
  });

  final CoolingTimeResult result;
  final double? windowMin;
  final double? windowMax;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: CoolingTimePainter(
              result: result,
              windowMin: windowMin,
              windowMax: windowMax,
              decimalComma: context.language != AppLanguage.en,
              textScale: MediaQuery.textScalerOf(context).scale(1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Malarz wykresu — publiczny, żeby test mógł sprawdzić skale osi.
class CoolingTimePainter extends CustomPainter {
  CoolingTimePainter({
    required this.result,
    this.windowMin,
    this.windowMax,
    this.decimalComma = true,
    this.textScale = 1,
  });

  final CoolingTimeResult result;
  final double? windowMin;
  final double? windowMax;
  final bool decimalComma;
  final double textScale;

  /// „Ładna” górna granica osi (1; 2; 2,5; 5 × 10ⁿ) nie mniejsza niż [v].
  static double niceCeil(double v) {
    if (!v.isFinite || v <= 0) return 1;
    final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / e;
    final n = f <= 1
        ? 1.0
        : f <= 2
            ? 2.0
            : f <= 2.5
                ? 2.5
                : f <= 5
                    ? 5.0
                    : 10.0;
    return n * e;
  }

  /// Krok siatki (1; 2; 5 × 10ⁿ) nie mniejszy niż [v].
  static double niceStep(double v) {
    if (!v.isFinite || v <= 0) return 1;
    final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / e;
    final n = f <= 1
        ? 1.0
        : f <= 2
            ? 2.0
            : f <= 5
                ? 5.0
                : 10.0;
    return n * e;
  }

  /// Górna granica osi Q [kJ/mm]: co najmniej 2 i 1,6 × bieżące Q.
  static double qTop(double q) =>
      niceCeil(math.max(2.0, 1.6 * q)).clamp(0.5, kQSearchMaxKjMm).toDouble();

  /// Górna granica osi t8/5 [s].
  static double tTop(double t, double? wMax) =>
      niceCeil(math.max(10.0, math.max(1.4 * t, 1.5 * (wMax ?? 0))));

  CoolingTimeResult? _at(double q) => coolingTime(
      heatInputKjMm: q,
      preheatC: result.preheatC,
      thicknessMm: result.thicknessMm,
      shape: result.shape);

  @override
  void paint(Canvas canvas, Size size) {
    final labelSize = 10.0 * textScale.clamp(1.0, 1.6);
    final left = 30.0 + 8 * (textScale - 1).clamp(0, 1);
    final bottom = 16.0 + labelSize;
    const top = 8.0;
    const right = 8.0;
    final plot =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    if (plot.width <= 10 || plot.height <= 10) return;

    final xMax = qTop(result.heatInputKjMm);
    final yMax = tTop(result.t85MaxS, windowMax);
    double x(double q) => plot.left + plot.width * (q / xMax);
    double y(double t) => plot.bottom - plot.height * (t / yMax);

    final grid = Paint()
      ..color = kBorder
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      color: kTextMut,
      fontSize: labelSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    String fmt(double v) {
      final s = v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);
      return decimalComma ? s.replaceAll('.', ',') : s;
    }

    void label(String text, Offset anchor,
        {TextAlign align = TextAlign.center}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = switch (align) {
        TextAlign.right => anchor.dx - tp.width,
        TextAlign.left => anchor.dx,
        _ => anchor.dx - tp.width / 2,
      };
      tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
    }

    // Siatka.
    final yStep = niceStep(yMax / 4);
    for (var t = 0.0; t <= yMax + 1e-9; t += yStep) {
      canvas.drawLine(Offset(plot.left, y(t)), Offset(plot.right, y(t)), grid);
      label(fmt(t), Offset(left - 4, y(t)), align: TextAlign.right);
    }
    final xStep = niceStep(xMax / 4);
    for (var q = 0.0; q <= xMax + 1e-9; q += xStep) {
      canvas.drawLine(Offset(x(q), plot.top), Offset(x(q), plot.bottom), grid);
      label(fmt(q), Offset(x(q), plot.bottom + 4 + labelSize / 2));
    }
    label('s', Offset(plot.left + 4, plot.top + labelSize / 2),
        align: TextAlign.left);
    label('Q kJ/mm', Offset(plot.right, plot.bottom - labelSize / 2 - 2),
        align: TextAlign.right);

    canvas.save();
    canvas.clipRect(plot);

    // Okno t8/5 — pas.
    if (windowMin != null || windowMax != null) {
      final band = Rect.fromLTRB(
          plot.left, y(windowMax ?? yMax), plot.right, y(windowMin ?? 0));
      canvas.drawRect(band, Paint()..color = kPass.withValues(alpha: 0.14));
      final edge = Paint()
        ..color = kPass.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      if (windowMin != null) {
        canvas.drawLine(Offset(plot.left, y(windowMin!)),
            Offset(plot.right, y(windowMin!)), edge);
      }
      if (windowMax != null) {
        canvas.drawLine(Offset(plot.left, y(windowMax!)),
            Offset(plot.right, y(windowMax!)), edge);
      }
    }

    // Przejście 3D → 2D.
    final qStar = transitionHeatInputKjMm(
        preheatC: result.preheatC, thicknessMm: result.thicknessMm);
    if (qStar != null && qStar > 0 && qStar < xMax) {
      _dashedLine(
          canvas,
          Offset(x(qStar), plot.top),
          Offset(x(qStar), plot.bottom),
          Paint()
            ..color = kTextMut
            ..strokeWidth = 1);
      label('3D', Offset(x(qStar) - 4, plot.top + labelSize),
          align: TextAlign.right);
      label('2D', Offset(x(qStar) + 4, plot.top + labelSize),
          align: TextAlign.left);
    }

    // Krzywa t8/5(Q); przerwana przy zmianie modelu (skok, gdy F2 ≠ F3).
    const n = 160;
    final lo = Path();
    final hi = Path();
    HeatFlow? prev;
    for (var k = 1; k <= n; k++) {
      final q = xMax * k / n;
      final r = _at(q);
      if (r == null) continue;
      final pLo = Offset(x(q), y(r.t85MinS));
      final pHi = Offset(x(q), y(r.t85MaxS));
      if (prev != r.flow) {
        lo.moveTo(pLo.dx, pLo.dy);
        hi.moveTo(pHi.dx, pHi.dy);
      } else {
        lo.lineTo(pLo.dx, pLo.dy);
        hi.lineTo(pHi.dx, pHi.dy);
      }
      prev = r.flow;
    }
    final line = Paint()
      ..color = kText
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(lo, line);
    if (result.shape.hasF2Range) canvas.drawPath(hi, line);

    // Bieżący punkt.
    final dot = Paint()..color = kArc;
    final px = x(result.heatInputKjMm);
    if (result.isRange) {
      canvas.drawLine(
          Offset(px, y(result.t85MinS)),
          Offset(px, y(result.t85MaxS)),
          Paint()
            ..color = kArc
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
    }
    canvas.drawCircle(
        Offset(px, y((result.t85MinS + result.t85MaxS) / 2)), 5, dot);
    canvas.restore();
  }

  static void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    var t = 0.0;
    while (t < len) {
      final end = math.min(t + dash, len);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  @override
  bool shouldRepaint(CoolingTimePainter old) =>
      old.result.heatInputKjMm != result.heatInputKjMm ||
      old.result.preheatC != result.preheatC ||
      old.result.thicknessMm != result.thicknessMm ||
      old.result.shape != result.shape ||
      old.windowMin != windowMin ||
      old.windowMax != windowMax ||
      old.decimalComma != decimalComma ||
      old.textScale != textScale;
}
