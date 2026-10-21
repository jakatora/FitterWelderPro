// Zawiesia i podwieszanie: nośność układu zawiesia (pas płaski EN 1492-1,
// pas okrągły EN 1492-2, łańcuch kl. 8 EN 818-4, lina EN 13414-1) dla
// spoola, kształtki albo zbiornika — WLL × współczynnik trybu ≥ masa → OK,
// inaczej STOP z potrzebnym WLL; kod kolorów pasów (decyduje etykieta);
// lista kontrolna przed podniesieniem.
//
// Logika, źródła i teksty: lib/domain/rigging/. Ostatnie dane kalkulatora
// pamiętane w SharedPreferences (rigging_store.dart); etykieta i lista
// kontrolna — nigdy (przed każdym podniesieniem od nowa).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/nps_dn_od_r.dart';
import '../../domain/fitter/fitter_calcs.dart' show PipeMaterial;
import '../../domain/rigging/rigging_calc.dart';
import '../../domain/rigging/rigging_checklist.dart';
import '../../domain/rigging/rigging_colors.dart';
import '../../domain/rigging/colour_reference.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/rigging/rigging_inputs.dart';
import '../../domain/rigging/rigging_sources.dart';
import '../../domain/rigging/rigging_text.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'rigging_store.dart';

class RiggingPage extends StatefulWidget {
  const RiggingPage({super.key});

  @override
  State<RiggingPage> createState() => _RiggingPageState();
}

class _RiggingPageState extends State<RiggingPage>
    with ToolHandleHost<RiggingPage> {
  SlingColour? _referenceColour;
  bool _referenceTag = false;
  final _scroll = ScrollController();
  @override
  String get toolId => 'rigging';
  @override
  Set<String> get supportedFields =>
      const {'reference_colour', 'reference_part'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final c = SlingColour.values
        .where((v) => v.name == fields['reference_colour'])
        .firstOrNull;
    final tag = fields['reference_part'] == 'tag';
    if (fields.length != 2 ||
        c == null ||
        c.nominalT == null ||
        !const ['tag', 'body'].contains(fields['reference_part']) ||
        (tag && !slingTagMaterials.containsKey(c))) {
      return fields.keys.toSet();
    }
    setState(() {
      _referenceColour = c;
      _referenceTag = tag;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
    return {};
  }

  static const RiggingStore _store = RiggingStore();

  bool _fromPipe = false;
  MassUnit _unit = MassUnit.kg;
  final _mass = TextEditingController();
  final _od = TextEditingController();
  final _wall = TextEditingController();
  final _length = TextEditingController();
  final _extra = TextEditingController();
  PipeMaterial _material = PipeMaterial.cs;
  SlingType _sling = SlingType.webbing;
  HitchMode _mode = HitchMode.twoLeg;
  bool _chokedLegs = false;
  AngleKind _angleKind = AngleKind.fromVertical;
  final _angle = TextEditingController();
  bool _asymmetric = false;
  final _wll = TextEditingController();
  SlingColour? _colour;

  /// 2 / 3–4 cięgna: co podaje zawieszka (`null` — nie wybrano = brak
  /// werdyktu) i dla jakiego zakresu kąta (WLL zespołu).
  WllBasis? _wllBasis;
  TagAngleRange? _tagRange;

  /// Nie zapisywane — przed każdym podniesieniem od nowa.
  LabelState _label = LabelState.unknown;
  final Map<String, CheckMark> _marks = {};

  /// Monter już coś zmienił — późniejszy odczyt zapisu tego nie nadpisze.
  bool _touched = false;
  bool _restoreDamaged = false;

  bool get _en => context.language == AppLanguage.en;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_mass, _od, _wall, _length, _extra, _angle, _wll]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Zapis ostatnich ustawień ─────────────────────────────────────────────

  /// Wracają tylko ustawienia widoczne od razu na ekranie — żadnych liczb
  /// (masa, wymiary, kąt, WLL) ani koloru: wczorajsze WLL innego pasa
  /// i jedno kliknięcie „etykieta czytelna” dałyby fałszywe OK.
  Future<void> _restore() async {
    final loaded = await _store.load();
    if (!mounted) return;
    markReady();
    if (_touched) return;
    final s = loaded.inputs;
    setState(() {
      _restoreDamaged = loaded.damaged;
      if (s == null) return;
      _fromPipe = s.fromPipe;
      _unit = s.unit;
      _material = s.material;
      _sling = s.sling;
      _mode = s.mode;
      _chokedLegs = s.chokedLegs;
      _angleKind = s.angleKind;
    });
  }

  RiggingSavedInputs get _saved => RiggingSavedInputs(
        fromPipe: _fromPipe,
        unit: _unit,
        material: _material,
        sling: _sling,
        mode: _mode,
        chokedLegs: _chokedLegs,
        angleKind: _angleKind,
      );

  /// Zmiana danych kalkulatora: przelicz i zapamiętaj.
  void _change(VoidCallback f) {
    setState(() {
      _touched = true;
      f();
    });
    unawaited(_store.save(_saved));
  }

  // ── Model ────────────────────────────────────────────────────────────────

  /// Puste → `null`, nieczytelne → NaN (nigdy cicha zero).
  static double? _num(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t) ?? double.nan;
  }

  PipeLoadResult get _pipe => pipeLoadMass(
        odMm: _num(_od),
        wallMm: _num(_wall),
        lengthM: _num(_length),
        material: _material,
        extraKg: _num(_extra) ?? 0,
      );

  bool get _pipeTouched =>
      [_od, _wall, _length, _extra].any((c) => c.text.trim().isNotEmpty);

  /// Pole w kg z zapisem „12,500” — separator tysięcy czy ułamek?
  bool _ambiguousKg(TextEditingController c, {bool alwaysKg = false}) =>
      (alwaysKg || _unit == MassUnit.kg) && isAmbiguousThousands(c.text);

  bool get _massAmbiguous =>
      _fromPipe ? _ambiguousKg(_extra, alwaysKg: true) : _ambiguousKg(_mass);

  bool get _wllAmbiguous => _ambiguousKg(_wll);

  double? get _massKg {
    if (_fromPipe) {
      final p = _pipe;
      if (p.mass != null) return p.mass!.totalKg.toDouble();
      return _pipeTouched ? double.nan : null;
    }
    final v = _num(_mass);
    return v == null ? null : toKg(v, _unit);
  }

  double? get _wllKg {
    final v = _num(_wll);
    return v == null ? null : toKg(v, _unit);
  }

  RiggingInput get _input => RiggingInput(
        massKg: _massKg,
        massAmbiguous: _massAmbiguous,
        sling: _sling,
        mode: _mode,
        chokedLegs: _chokedLegs,
        angleValue: _num(_angle),
        angleKind: _angleKind,
        asymmetric: _asymmetric,
        wllKg: _wllKg,
        wllAmbiguous: _wllAmbiguous,
        wllBasis: _wllBasis,
        tagRange: _tagRange,
        label: _label,
      );

  // ── Akcje ────────────────────────────────────────────────────────────────

  /// Pole w nowej jednostce — ta sama masa, inny zapis. Niejednoznacznego
  /// „12,500” w kg nie przeliczamy (12,5 kg → 0,0125 t rozstrzygałoby po
  /// cichu): zostaje jak jest, w t to 12,5 t = 12 500 kg — nigdy mniej.
  void _convertField(TextEditingController c, MassUnit from, MassUnit to) {
    if (from == MassUnit.kg && isAmbiguousThousands(c.text)) return;
    final v = parseDecimal(c.text);
    if (v == null) return;
    c.text = numText(fromKg(toKg(v, from), to), decimals: 4);
  }

  /// Zmiana konfiguracji. WLL ZESPOŁU z zawieszki obowiązuje tylko dla tej
  /// konfiguracji — przy każdej zmianie trybu pole WLL i wybór „co podaje
  /// zawieszka” są czyszczone (zespół 2,8 t nie jest WLL jednego cięgna).
  void _setMode(HitchMode m) {
    if (m == _mode) return;
    _change(() {
      if (_wllBasis == WllBasis.assembly) {
        _wll.clear();
        _wllBasis = null;
        _tagRange = null;
      }
      _mode = m;
    });
  }

  void _setWllBasis(WllBasis b) => _change(() {
        _wllBasis = _wllBasis == b ? null : b;
        if (_wllBasis != WllBasis.assembly) _tagRange = null;
      });

  void _setTagRange(TagAngleRange r) =>
      _change(() => _tagRange = _tagRange == r ? null : r);

  void _setUnit(MassUnit u) {
    if (u == _unit) return;
    _change(() {
      _convertField(_mass, _unit, u);
      _convertField(_wll, _unit, u);
      _unit = u;
    });
  }

  void _setAngleKind(AngleKind k) {
    if (k == _angleKind) return;
    _change(() {
      final v = parseDecimal(_angle.text);
      if (v != null) {
        _angle.text = numText(convertAngle(v, from: _angleKind), decimals: 2);
      }
      _angleKind = k;
    });
  }

  /// Inne zawiesie = inne WLL, kolor, zawieszka i etykieta — wszystko, co
  /// opisywało poprzednie, jest czyszczone.
  void _setSling(SlingType s) {
    if (s == _sling) return;
    _change(() {
      _sling = s;
      _wll.clear();
      _colour = null;
      _wllBasis = null;
      _tagRange = null;
      // Inna lista pozycji — oceny innego zawiesia nie przechodzą.
      _marks.clear();
      _label = LabelState.unknown;
    });
  }

  void _fillWllFromColour(SlingColour c) {
    final t = c.nominalT;
    if (t == null) return;
    _change(() => _wll.text = numText(fromKg(t * 1000, _unit), decimals: 4));
  }

  void _setLabel(LabelState s) => setState(() {
        _touched = true;
        _label = _label == s ? LabelState.unknown : s;
      });

  void _setMark(String id, CheckMark m) => setState(() {
        _touched = true;
        if (_marks[id] == m) {
          _marks.remove(id);
        } else {
          _marks[id] = m;
        }
      });

  void _resetChecklist() => setState(() {
        _marks.clear();
        _label = LabelState.unknown;
      });

  // ── Widżety pomocnicze ───────────────────────────────────────────────────

  String _n(double v, [int decimals = 2]) =>
      rigNum(v, decimals: decimals, en: _en);

  String _kg(num kg) => kgText(kg, en: _en);

  String _mass2(int kg) => massInUnit(kg, _unit, en: _en);

  Widget _caption(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _label2(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, color: kTextSec, fontWeight: FontWeight.w600)),
      );

  Widget _kv(String k, String v, {Key? key}) => CopyOnLongPress(
        key: key,
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

  Widget _chips<T>({
    required List<T> values,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
    required String Function(T) keyOf,
    Widget? Function(T)? avatar,
  }) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final v in values)
            ChoiceChip(
              key: ValueKey(keyOf(v)),
              label: Text(label(v)),
              avatar: avatar?.call(v),
              // Próbka koloru zostaje widoczna po zaznaczeniu.
              showCheckmark: avatar == null,
              selected: selected == v,
              onSelected: (_) => onSelected(v),
            ),
        ],
      );

  Widget _numField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? suffix,
    String? helper,
    String? error,
  }) =>
      TextField(
        key: key,
        controller: controller,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: (_) => _change(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  /// Błąd pola masy / WLL (puste = bez błędu — brak to osobny komunikat):
  /// niejednoznaczny zapis w kg, nie liczba > 0, ponad 1000 t.
  /// [alwaysKg] — pole zawsze w kg (dodatki), [allowZero] — 0 dozwolone.
  String? _massFieldError(
    TextEditingController c, {
    bool alwaysKg = false,
    bool allowZero = false,
  }) {
    if (_ambiguousKg(c, alwaysKg: alwaysKg)) return ambiguousKgText(en: _en);
    final v = _num(c);
    if (v == null) return null;
    if (!v.isFinite || v < 0 || (v == 0 && !allowZero)) {
      return allowZero
          ? context.tr(pl: 'Wpisz liczbę ≥ 0', en: 'Enter a number ≥ 0')
          : context.tr(pl: 'Wpisz liczbę > 0', en: 'Enter a number > 0');
    }
    if (toKg(v, alwaysKg ? MassUnit.kg : _unit) > kRiggingMaxKg) {
      return context.tr(
          pl: 'Najwyżej 1000 t — sprawdź zera',
          en: 'At most 1000 t — check the zeros');
    }
    return null;
  }

  /// „Do obliczeń: 12 500 kg (12,5 t)” — jak aplikacja odczytała liczbę.
  String _forCalc(int kg) => context.tr(
      pl: 'Do obliczeń: ${massForCalcText(kg, en: false)}',
      en: 'Used in the calculation: ${massForCalcText(kg, en: true)}');

  // ── Budowa ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final result = evaluateRigging(_input);
    final list = evaluateChecklist(_sling, _marks, _label);
    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Zawiesia i podwieszanie', en: 'Slings and rigging'))),
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (_referenceColour != null)
            Card(
                key: const ValueKey('rig-assistant-reference'),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(slingColourReference(_referenceColour!,
                              tag: _referenceTag, en: _en)),
                          TextButton(
                              onPressed: () =>
                                  setState(() => _referenceColour = null),
                              child: Text(context.tr(
                                  pl: 'Zamknij informację o kolorze',
                                  en: 'Close colour reference'))),
                        ]))),
          if (_restoreDamaged)
            QuoteNotice(
              key: const ValueKey('rig-restore-damaged'),
              text: context.tr(
                  pl: 'Nie udało się odczytać ostatnich danych kalkulatora — '
                      'wczytano wartości domyślne. Sprawdź dane przed '
                      'oceną.',
                  en: 'The last calculator data could not be read — defaults '
                      'loaded. Check the data before rating.'),
            ),
          _loadSection(result),
          _slingSection(result),
          _hitchSection(result),
          _resultSection(result),
          _checklistSection(list),
          _readiness(result, list),
          _sourcesSection(),
          _disclaimer(),
        ],
      ),
    );
  }

  // ── Ładunek ──────────────────────────────────────────────────────────────

  Widget _loadSection(RiggingResult r) {
    final massKg = r.massKg;
    return QuoteSection(
      title: context.tr(pl: 'Ładunek', en: 'Load'),
      children: [
        _chips<bool>(
          values: const [false, true],
          selected: _fromPipe,
          label: (v) => v
              ? context.tr(pl: 'Policz z rury', en: 'From the pipe')
              : context.tr(pl: 'Wpisz masę', en: 'Enter the mass'),
          keyOf: (v) => v ? 'rig-mass-pipe' : 'rig-mass-manual',
          onSelected: (v) => _change(() => _fromPipe = v),
        ),
        _label2(
            context.tr(pl: 'Jednostka masy i WLL', en: 'Unit of mass and WLL')),
        _chips<MassUnit>(
          values: MassUnit.values,
          selected: _unit,
          label: unitLabel,
          keyOf: (u) => 'rig-unit-${u.name}',
          onSelected: _setUnit,
        ),
        const SizedBox(height: 12),
        if (_fromPipe)
          ..._pipeFields()
        else
          _numField(
            key: const ValueKey('rig-mass'),
            controller: _mass,
            label: context.tr(pl: 'Masa ładunku', en: 'Load mass'),
            suffix: unitLabel(_unit),
            helper: massKg == null ? null : _forCalc(massKg),
            error: _massFieldError(_mass),
          ),
        _caption(context.tr(
            pl: 'Masę bierz z rysunku, dokumentów albo z wagi hakowej — nie '
                'zgaduj. Spool to rura + kołnierze, armatura, izolacja '
                'i woda, jeśli została po próbie.',
            en: 'Take the mass from the drawing, papers or a crane scale — do '
                'not guess. A spool is pipe + flanges, valves, insulation and '
                'water left from the pressure test.')),
      ],
    );
  }

  List<Widget> _pipeFields() {
    final p = _pipe;
    // Niejednoznaczne dodatki („12,500”) — sumy nie pokazujemy wcale.
    final m = _massAmbiguous ? null : p.mass;
    final problem = _pipeTouched ? p.problem : null;
    return [
      // Szybkie wpisanie OD z tabeli DN — zawsze pokazuje podpowiedź, bo
      // OD można potem poprawić ręcznie (inaczej wisiałby stary DN).
      InputDecorator(
        decoration: const InputDecoration(
          labelText: 'DN → OD',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            key: const ValueKey('rig-pipe-dn'),
            isExpanded: true,
            value: null,
            hint: Text(
                context.tr(
                    pl: 'Wybierz DN, aby wpisać OD',
                    en: 'Pick a DN to fill the OD'),
                overflow: TextOverflow.ellipsis),
            items: [
              for (final (i, r) in kNpsTable.indexed)
                DropdownMenuItem(
                  value: i,
                  child: Text('DN${r.dn} · ${_n(r.odMm)} mm (${r.nps})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (i) {
              if (i == null) return;
              _change(() => _od.text = numText(kNpsTable[i].odMm, decimals: 2));
            },
          ),
        ),
      ),
      const SizedBox(height: 10),
      _numField(
        key: const ValueKey('rig-pipe-od'),
        controller: _od,
        label:
            context.tr(pl: 'Średnica zewnętrzna OD', en: 'Outside diameter OD'),
        suffix: 'mm',
      ),
      const SizedBox(height: 10),
      _numField(
        key: const ValueKey('rig-pipe-wall'),
        controller: _wall,
        label: context.tr(pl: 'Grubość ścianki', en: 'Wall thickness'),
        suffix: 'mm',
      ),
      const SizedBox(height: 10),
      _numField(
        key: const ValueKey('rig-pipe-length'),
        controller: _length,
        label: context.tr(pl: 'Długość', en: 'Length'),
        suffix: 'm',
      ),
      const SizedBox(height: 10),
      _numField(
        key: const ValueKey('rig-pipe-extra'),
        controller: _extra,
        label: context.tr(
            pl: 'Dodatki (kołnierze, armatura, woda)',
            en: 'Extras (flanges, valves, water)'),
        suffix: 'kg',
        helper: context.tr(pl: 'Puste = 0 kg', en: 'Empty = 0 kg'),
        error: _massFieldError(_extra, alwaysKg: true, allowZero: true),
      ),
      _label2(
          context.tr(pl: 'Materiał rury [kg/m³]', en: 'Pipe material [kg/m³]')),
      _chips<PipeMaterial>(
        values: const [
          PipeMaterial.cs,
          PipeMaterial.ss304,
          PipeMaterial.ss316,
          PipeMaterial.al,
        ],
        selected: _material,
        label: (m) => pipeMaterialLabel(m, en: _en),
        keyOf: (m) => 'rig-pipe-mat-${m.name}',
        onSelected: (m) => _change(() => _material = m),
      ),
      const SizedBox(height: 8),
      if (m != null) ...[
        _kv(context.tr(pl: 'Rura', en: 'Pipe'),
            '${_n(m.kgPerM, 2)} kg/m · ${_n(m.pipeKg, 1)} kg',
            key: const ValueKey('rig-pipe-kgm')),
        _kv(
            context.tr(
                pl: 'Masa ładunku (w górę)', en: 'Load mass (rounded up)'),
            _mass2(m.totalKg),
            key: const ValueKey('rig-pipe-total')),
        _caption(context.tr(
            pl: 'm = ρ · π · (OD − t) · t — masa teoretyczna rury, ta sama co '
                'w module „Ciężar rury”.',
            en: 'm = ρ · π · (OD − t) · t — theoretical pipe mass, the same as '
                'in the “Pipe weight” tool.')),
      ],
      if (problem != null)
        _caption(pipeProblemText(problem, en: _en),
            key: const ValueKey('rig-pipe-problem')),
    ];
  }

  // ── Zawiesie ─────────────────────────────────────────────────────────────

  /// Podpowiedź pod polem WLL — co dokładnie wpisać.
  String _wllHelper(RiggingResult r) {
    final basis = _mode.isMultiLeg ? _wllBasis : null;
    final what = !_mode.isMultiLeg
        ? context.tr(
            pl: 'WLL podnoszenia prostego z etykiety (jedno cięgno, pionowo)',
            en: 'Straight-lift WLL from the label (one leg, vertical)')
        : switch (basis) {
            null => context.tr(
                pl: 'Najpierw wybierz wyżej, co podaje zawieszka',
                en: 'First pick above what the tag gives'),
            WllBasis.perLeg => context.tr(
                pl: 'WLL jednego cięgna (pionowo) — mnożone przez współczynnik',
                en: 'WLL of one leg (vertical) — multiplied by the factor'),
            WllBasis.assembly => context.tr(
                pl: 'WLL zespołu z zawieszki dla '
                    '${_tagRange == null ? 'zakresu kąta' : tagRangeLabel(_tagRange!, en: false)}'
                    ' — bez mnożenia',
                en: 'Assembly WLL from the tag for '
                    '${_tagRange == null ? 'the angle range' : tagRangeLabel(_tagRange!, en: true)}'
                    ' — not multiplied'),
          };
    final w = r.wllKg;
    return w == null ? what : '$what. ${_forCalc(floorKg(w))}';
  }

  Widget _slingSection(RiggingResult r) {
    final wll = _wllKg;
    final c = _colour;
    final assembly = _mode.isMultiLeg && _wllBasis == WllBasis.assembly;
    // Kolor mówi o WLL jednego pasa / cięgna — z WLL zespołu nie porównujemy.
    final match = c != null && wll != null && !assembly && !_wllAmbiguous
        ? colourMatchesWll(c, wll)
        : null;
    return QuoteSection(
      title: context.tr(pl: 'Zawiesie', en: 'Sling'),
      children: [
        _chips<SlingType>(
          values: SlingType.values,
          selected: _sling,
          label: (s) => slingTypeLabel(s, en: _en),
          keyOf: (s) => 'rig-sling-${s.name}',
          onSelected: _setSling,
        ),
        _caption(slingTypeStandard(_sling)),
        _label2(context.tr(
            pl: 'Etykieta / zawieszka z WLL', en: 'Label / tag with the WLL')),
        _chips<LabelState>(
          values: const [LabelState.readable, LabelState.missing],
          selected: _label,
          label: (s) => s == LabelState.readable
              ? context.tr(pl: 'Jest, czytelna', en: 'Present, legible')
              : context.tr(pl: 'Brak / nieczytelna', en: 'Missing / illegible'),
          keyOf: (s) => 'rig-label-${s.name}',
          onSelected: _setLabel,
        ),
        if (_label == LabelState.missing)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: QuoteNotice(
              key: const ValueKey('rig-label-stop'),
              color: kFail,
              icon: Icons.block,
              text: context.tr(
                  pl: 'STOP — zawiesia bez czytelnej etykiety nie wolno '
                      'używać, także gdy kolor wskazuje nośność. Odłóż, '
                      'oznacz, zgłoś.',
                  en: 'STOP — a sling without a legible label must not be '
                      'used, even when the colour suggests the WLL. Set it '
                      'aside, mark it, report it.'),
            ),
          ),
        if (_sling.isTextile) ..._colourPicker(match, assembly: assembly),
        if (_mode.isMultiLeg) ..._wllBasisPicker(),
        const SizedBox(height: 12),
        _numField(
          key: const ValueKey('rig-wll'),
          controller: _wll,
          label: assembly
              ? context.tr(
                  pl: 'WLL zespołu z zawieszki',
                  en: 'Assembly WLL from the tag')
              : context.tr(
                  pl: 'WLL z etykiety (podnoszenie proste)',
                  en: 'WLL from the label (straight lift)'),
          suffix: unitLabel(_unit),
          helper: _wllHelper(r),
          error: _massFieldError(_wll),
        ),
      ],
    );
  }

  /// 2 / 3–4 cięgna: co jest na zawieszce. Fabryczne zawiesie łańcuchowe
  /// albo linowe podaje WLL ZESPOŁU dla zakresu kąta — mnożenie go jeszcze
  /// raz przez 1,4 / 2,1 zawyżyłoby nośność.
  List<Widget> _wllBasisPicker() => [
        _label2(context.tr(
            pl: 'Co podaje zawieszka / etykieta?',
            en: 'What does the tag / label give?')),
        _chips<WllBasis>(
          values: WllBasis.values,
          selected: _wllBasis,
          label: (b) => wllBasisLabel(b, en: _en),
          keyOf: (b) => 'rig-wll-basis-${b.name}',
          onSelected: _setWllBasis,
        ),
        if (_wllBasis == WllBasis.assembly) ...[
          _label2(context.tr(
              pl: 'Dla jakiego kąta jest ta wartość?',
              en: 'Which angle is that value for?')),
          _chips<TagAngleRange>(
            values: TagAngleRange.values,
            selected: _tagRange,
            label: (t) => tagRangeLabel(t, en: _en),
            keyOf: (t) => 'rig-tag-range-${t.name}',
            onSelected: _setTagRange,
          ),
        ],
        _caption(
            context.tr(
                pl: 'Zawieszka zawiesia łańcuchowego albo linowego zwykle '
                    'podaje WLL całego zespołu dla zakresu kąta (np. „2,8 t / '
                    '0–45°”) — wtedy bez mnożenia. Dwa osobne pasy: WLL '
                    'jednego pasa. Bez wyboru nie ma werdyktu.',
                en: 'A chain or wire rope sling tag usually gives the WLL of '
                    'the whole assembly for an angle range (e.g. “2.8 t / '
                    '0–45°”) — then no multiplying. Two separate slings: the '
                    'WLL of one sling. No choice, no verdict.'),
            key: const ValueKey('rig-wll-basis-note')),
      ];

  List<Widget> _colourPicker(bool? match, {required bool assembly}) {
    final c = _colour;
    return [
      _label2(context.tr(
          pl: 'Kolor pasa (tylko podpowiedź)', en: 'Sling colour (hint only)')),
      _chips<SlingColour>(
        values: SlingColour.values,
        selected: c,
        label: (s) => s.nominalT == null
            ? s.label(en: _en)
            : '${s.label(en: _en)} ${_n(s.nominalT!)}${s.orAbove ? '+' : ''} t',
        keyOf: (s) => 'rig-colour-${s.name}',
        avatar: (s) => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Color(s.argb),
            shape: BoxShape.circle,
            border: Border.all(color: kBorder),
          ),
        ),
        onSelected: (s) => _change(() => _colour = _colour == s ? null : s),
      ),
      // Kolor = WLL jednego pasa / cięgna; do pola WLL ZESPOŁU go nie wpisujemy.
      if (c != null && c.nominalT != null && !assembly) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const ValueKey('rig-colour-fill'),
            avatar: const Icon(Icons.input, size: 18),
            label: Text(context.tr(
                pl: 'Wpisz ${_n(c.nominalT!)} t do WLL',
                en: 'Put ${_n(c.nominalT!)} t into WLL')),
            onPressed: () => _fillWllFromColour(c),
          ),
        ),
      ],
      if (c != null && c.nominalT != null && assembly)
        _caption(
            context.tr(
                pl: 'Kolor cięgna mówi o WLL jednego cięgna, nie zespołu — WLL '
                    'zespołu weź z zawieszki.',
                en: 'A leg’s colour gives the WLL of one leg, not of the '
                    'assembly — take the assembly WLL from the tag.'),
            key: const ValueKey('rig-colour-assembly')),
      if (match == false)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: QuoteNotice(
            key: const ValueKey('rig-colour-mismatch'),
            icon: Icons.warning_amber_outlined,
            text: context.tr(
                pl: 'Kolor nie pasuje do WLL z etykiety. Decyduje etykieta — '
                    'sprawdź, czy to na pewno etykieta tego pasa.',
                en: 'The colour does not match the WLL on the label. The label '
                    'governs — check that it belongs to this sling.'),
          ),
        ),
      _caption(
          context.tr(
              pl: 'Kod kolorów EN 1492: fioletowy 1 t, zielony 2 t, żółty 3 t, '
                  'szary 4 t, czerwony 5 t, brązowy 6 t, niebieski 8 t, '
                  'pomarańczowy 10 t i więcej. Decyduje etykieta, nie kolor — '
                  'pas bez etykiety to STOP. Kolor etykiety mówi o materiale '
                  '(niebieska PES, zielona PA, brązowa PP).',
              en: 'EN 1492 colour code: violet 1 t, green 2 t, yellow 3 t, grey '
                  '4 t, red 5 t, brown 6 t, blue 8 t, orange 10 t and more. The '
                  'label governs, not the colour — no label means STOP. The '
                  'label colour tells the material (blue PES, green PA, brown '
                  'PP).'),
          key: const ValueKey('rig-colour-note')),
    ];
  }

  // ── Sposób zawiązania ────────────────────────────────────────────────────

  String _modeHint(HitchMode m) => switch (m) {
        HitchMode.straight => context.tr(
            pl: 'Jedno cięgno pionowo — ×1,0.',
            en: 'One leg, vertical — ×1.0.'),
        HitchMode.choke => context.tr(
            pl: 'Pętla zaciskowa na ładunku — tracisz 20 %: ×0,8.',
            en: 'Choke around the load — you lose 20 %: ×0.8.'),
        HitchMode.basketParallel => context.tr(
            pl: 'Ładunek w pętli, oba końce na haku, cięgna pionowe (odchyłka '
                'do 6°). Rozchylone — wybierz „koszowe pod kątem”.',
            en: 'Load in the loop, both ends on the hook, legs vertical (up to '
                '6° off). Spread legs — pick “basket, angled”.'),
        HitchMode.basketAngled => context.tr(
            pl: 'Ładunek w pętli, oba końce na haku, cięgna rozchylone.',
            en: 'Load in the loop, both ends on the hook, legs spread.'),
        HitchMode.twoLeg => context.tr(
            pl: 'Zawiesie dwucięgnowe albo dwa pasy na jednym haku.',
            en: 'Two-leg sling or two slings on one hook.'),
        HitchMode.multiLeg => context.tr(
            pl: '×2,1 / ×1,5 tylko dla zawiesia wielocięgnowego z cięgnami '
                'równej długości. Na sztywnym ładunku (spool, zbiornik) często '
                'niosą tylko 2 cięgna — wtedy włącz „niesymetryczny” albo licz '
                'jak 2 cięgna.',
            en: '×2.1 / ×1.5 only for a multi-leg sling with equal legs. On a '
                'rigid load (spool, tank) often only 2 legs carry — then '
                'switch on “asymmetric” or rate it as 2 legs.'),
      };

  Widget _hitchSection(RiggingResult r) {
    final beta = r.betaDeg;
    final angleText = _angle.text.trim();
    final angleError = _mode.needsAngle &&
            angleText.isNotEmpty &&
            r.issues.contains(RiggingIssue.angleInvalid)
        ? context.tr(
            pl: _angleKind == AngleKind.fromVertical
                ? 'β od pionu: 0–89°'
                : 'α między cięgnami: 0–179°',
            en: _angleKind == AngleKind.fromVertical
                ? 'β from vertical: 0–89°'
                : 'α between legs: 0–179°')
        : null;
    final otherAngle = _mode.needsAngle && beta != null && angleError == null
        ? (_angleKind == AngleKind.fromVertical
            ? context.tr(
                pl: 'α między cięgnami = ${degText(beta * 2, en: false)}',
                en: 'α between legs = ${degText(beta * 2, en: true)}')
            : context.tr(
                pl: '= β ${degText(beta, en: false)} od pionu (to ten kąt '
                    'jest w tabeli)',
                en: '= β ${degText(beta, en: true)} from vertical (the table '
                    'uses this one)'))
        : null;

    return QuoteSection(
      title: context.tr(pl: 'Sposób zawiązania', en: 'Hitch'),
      children: [
        _chips<HitchMode>(
          values: HitchMode.values,
          selected: _mode,
          label: (m) => hitchModeLabel(m, en: _en),
          keyOf: (m) => 'rig-mode-${m.name}',
          onSelected: _setMode,
        ),
        _caption(_modeHint(_mode), key: const ValueKey('rig-mode-hint')),
        if (_mode.isMultiLeg)
          SwitchListTile(
            key: const ValueKey('rig-choked-legs'),
            contentPadding: EdgeInsets.zero,
            value: _chokedLegs,
            onChanged: (v) => _change(() => _chokedLegs = v),
            title: Text(context.tr(
                pl: 'Cięgna zawiązane na zadusznik (×0,8)',
                en: 'Legs choked around the load (×0.8)')),
          ),
        if (_mode.isBasket && _sling == SlingType.chain)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: QuoteNotice(
              key: const ValueKey('rig-chain-basket'),
              icon: Icons.info_outline,
              color: kTextSec,
              text: context.tr(
                  pl: 'Łańcuch w koszowym liczony ×1,0 (przyjęte w aplikacji): '
                      'gdy hak cięgna wraca na ogniwo zawieszenia, całość '
                      'niesie ogniwo. Wyższą wartość weź tylko z tabeli '
                      'producenta tego zawiesia.',
                  en: 'Chain in basket hitch rated ×1.0 (adopted in the app): '
                      'when the leg hook goes back to the master link, the link '
                      'carries it all. Use a higher value only from this '
                      'sling’s maker table.'),
            ),
          ),
        if (_mode.isBasket && _sling == SlingType.wireRope)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: QuoteNotice(
              key: const ValueKey('rig-rope-basket'),
              icon: Icons.warning_amber_outlined,
              text: context.tr(
                  pl: 'Lina zgięta na małej średnicy (cienka rura, ostra '
                      'krawędź) traci nośność — współczynnik koszowy zakłada '
                      'łagodne zgięcie. Sprawdź tabelę D/d producenta; przy '
                      'wątpliwości licz jak proste ×1,0.',
                  en: 'A rope bent over a small diameter (thin pipe, sharp '
                      'edge) loses capacity — the basket factor assumes a '
                      'gentle bend. Check the maker’s D/d table; if in doubt '
                      'rate it as straight ×1.0.'),
            ),
          ),
        if (_mode.needsAngle) ...[
          _label2(context.tr(pl: 'Jak podajesz kąt?', en: 'Which angle?')),
          _chips<AngleKind>(
            values: AngleKind.values,
            selected: _angleKind,
            label: (k) => k == AngleKind.fromVertical
                ? context.tr(pl: 'β od pionu', en: 'β from vertical')
                : context.tr(pl: 'α między cięgnami', en: 'α between legs'),
            keyOf: (k) => 'rig-angle-kind-${k.name}',
            onSelected: _setAngleKind,
          ),
          const SizedBox(height: 10),
          _AngleDiagram(
            key: const ValueKey('rig-angle-diagram'),
            betaDeg: beta ?? 30,
            included: _angleKind == AngleKind.included,
            en: _en,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('rig-angle'),
            controller: _angle,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            onChanged: (_) => _change(() {}),
            decoration: InputDecoration(
              labelText: _angleKind == AngleKind.fromVertical
                  ? context.tr(
                      pl: 'Kąt β cięgna od pionu',
                      en: 'Leg angle β from vertical')
                  : context.tr(
                      pl: 'Kąt α między cięgnami (wierzchołkowy)',
                      en: 'Angle α between legs (included)'),
              suffixText: '°',
              helperText: otherAngle,
              helperMaxLines: 2,
              errorText: angleError,
              errorMaxLines: 2,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          _caption(context.tr(
              pl: 'Kąt nieznany = brak werdyktu. Gdy każde cięgno jest nie '
                  'krótsze niż rozstaw punktów zaczepienia, β ≤ 30°. Przy 4 '
                  'cięgnach α mierz między cięgnami po przekątnej.',
              en: 'Unknown angle = no verdict. When every leg is at least as '
                  'long as the spacing of the attachment points, β ≤ 30°. With '
                  '4 legs measure α between diagonally opposite legs.')),
        ],
        SwitchListTile(
          key: const ValueKey('rig-asym'),
          contentPadding: EdgeInsets.zero,
          value: _asymmetric,
          onChanged: (v) => _change(() => _asymmetric = v),
          title: Text(context.tr(
              pl: 'Ładunek niesymetryczny / środek ciężkości poza osią',
              en: 'Asymmetric load / centre of gravity off-axis')),
          subtitle: Text(
              context.tr(
                  pl: 'Liczone tak, jakby całość niosło jedno cięgno '
                      '(konserwatywnie): różne kąty albo długości cięgien, '
                      'sztywny ładunek, nieznany środek ciężkości.',
                  en: 'Rated as if one leg carried everything (conservative): '
                      'different leg angles or lengths, rigid load, unknown '
                      'centre of gravity.'),
              style: const TextStyle(fontSize: 12, color: kTextMut)),
        ),
      ],
    );
  }

  // ── Wynik ────────────────────────────────────────────────────────────────

  String _issues(RiggingResult r) =>
      r.issues.map((i) => issueText(i, en: _en)).join(', ');

  String _verdictDetail(RiggingResult r) {
    final cap = r.capacityKg;
    final mass = r.massKg;
    switch (r.verdict) {
      case RiggingVerdict.ok:
        return context.tr(
            pl: 'Nośność układu ${_mass2(cap!)} ≥ masa ${_mass2(mass!)}.',
            en: 'System capacity ${_mass2(cap)} ≥ mass ${_mass2(mass)}.');
      case RiggingVerdict.overload:
        final need = r.requiredWllKg!;
        final series = r.suggestedSeriesT;
        final pick = !_sling.isTextile
            ? context.tr(
                pl: 'dobierz z tabeli producenta',
                en: 'pick from the maker table')
            : series == null
                ? context.tr(
                    pl: 'ponad 50 t — plan podnoszenia',
                    en: 'over 50 t — lift plan')
                : context.tr(
                    pl: 'pas z typoszeregu: ${_n(series)} t',
                    en: 'sling from the series: ${_n(series)} t');
        final assembly = r.wllBasis == WllBasis.assembly;
        final pickText = assembly
            ? context.tr(
                pl: 'zawiesie o większym WLL zespołu dla tego zakresu kąta',
                en: 'a sling with a higher assembly WLL for this angle range')
            : pick;
        return context.tr(
            pl: 'Nośność układu ${_mass2(cap!)} < masa ${_mass2(mass!)}. '
                'Potrzebne ${_requiredLabel(r, en: false)} co najmniej '
                '${_kg(need)} — $pickText.',
            en: 'System capacity ${_mass2(cap)} < mass ${_mass2(mass)}. '
                'Needed ${_requiredLabel(r, en: true)} at least ${_kg(need)} '
                '— $pickText.');
      case RiggingVerdict.angleNotAllowed:
        final b = r.betaDeg!;
        return context.tr(
            pl: 'β = ${degText(b, en: false)} od pionu (α = '
                '${degText(b * 2, en: false)}). Ponad 60° nie wolno — '
                'dłuższe cięgna albo trawers.',
            en: 'β = ${degText(b, en: true)} from vertical (α = '
                '${degText(b * 2, en: true)}). Above 60° is not allowed — '
                'longer legs or a spreader beam.');
      case RiggingVerdict.noLabel:
        return context.tr(
            pl: 'Zawiesie bez czytelnej etykiety nie może być użyte — także '
                'gdy kolor wskazuje nośność.',
            en: 'A sling without a legible label cannot be used — even when '
                'the colour suggests the WLL.');
      case RiggingVerdict.incomplete:
        return context.tr(
            pl: 'Brakuje: ${_issues(r)}. Bez tego nie ma werdyktu — to nie '
                'jest OK.',
            en: 'Missing: ${_issues(r)}. Without it there is no verdict — this '
                'is not OK.');
    }
  }

  (Color, IconData) _look(RiggingVerdict v) => switch (v) {
        RiggingVerdict.ok => (kPass, Icons.check_circle_outline),
        RiggingVerdict.incomplete => (kTextSec, Icons.help_outline),
        _ => (kFail, Icons.dangerous_outlined),
      };

  /// Jakie WLL jest „potrzebne” — w tej samej podstawie, co wpisane.
  String _requiredLabel(RiggingResult r, {required bool en}) =>
      switch (r.wllBasis) {
        WllBasis.assembly => en ? 'assembly WLL' : 'WLL zespołu',
        WllBasis.perLeg => en ? 'WLL of one leg' : 'WLL jednego cięgna',
        null => 'WLL',
      };

  String _factorDetail(RiggingResult r) {
    final f = r.factor!;
    final parts = <String>[
      factorText(f.value, en: _en),
      hitchModeLabel(_mode, en: _en),
      if (r.wllBasis == WllBasis.assembly)
        context.tr(
            pl: 'WLL zespołu z zawieszki, bez mnożenia',
            en: 'assembly WLL from the tag, not multiplied'),
      if (_mode.isMultiLeg && _chokedLegs)
        context.tr(pl: 'na zadusznik', en: 'choked'),
      if (r.band != null) angleBandLabel(r.band!, en: _en),
    ];
    final adopted = f.adopted
        ? context.tr(pl: ' (przyjęte w aplikacji)', en: ' (adopted in the app)')
        : '';
    return '${parts.join(' · ')}$adopted';
  }

  Widget _resultSection(RiggingResult r) {
    final (color, icon) = _look(r.verdict);
    final cap = r.capacityKg;
    final t = r.tension;
    return QuoteSection(
      title: context.tr(pl: 'Wynik', en: 'Result'),
      children: [
        KeyedSubtree(
          key: ValueKey('rig-verdict-${r.verdict.name}'),
          child: QuoteNotice(
            color: color,
            icon: icon,
            text: '${verdictTitle(r.verdict, en: _en)}\n${_verdictDetail(r)}',
          ),
        ),
        // Zawsze, jednoznacznie w obu jednostkach — „12,500” nie przejdzie
        // niezauważone jako 12,5 kg.
        if (r.massKg != null) ...[
          _kv(context.tr(pl: 'Masa do obliczeń', en: 'Mass used'),
              massForCalcText(r.massKg!, en: _en),
              key: const ValueKey('rig-mass-used')),
          const SizedBox(height: 8),
        ],
        if (cap != null) ...[
          Readout(
            key: const ValueKey('rig-capacity'),
            label: context.tr(
                pl: 'Nośność układu (w dół)',
                en: 'System capacity (rounded down)'),
            value: _unit == MassUnit.t
                ? tText(cap, en: _en).replaceAll(' t', '')
                : rigNum(cap.toDouble(), decimals: 0, en: _en),
            unit: '${unitLabel(_unit)} · WLL '
                '${factorText(r.factor!.value, en: _en)}',
            hot: true,
          ),
          const SizedBox(height: 8),
        ],
        if (r.wllKg != null && cap != null)
          _kv(
              r.wllBasis == null
                  ? context.tr(pl: 'WLL do obliczeń', en: 'WLL used')
                  : _requiredLabel(r, en: _en),
              massForCalcText(floorKg(r.wllKg!), en: _en),
              key: const ValueKey('rig-wll-used')),
        if (r.factor != null)
          _kv(context.tr(pl: 'Współczynnik trybu', en: 'Mode factor'),
              _factorDetail(r),
              key: const ValueKey('rig-factor')),
        if (r.asymmetryReduced)
          _caption(
              context.tr(
                  pl: 'Niesymetrycznie: ${factorText(r.symmetricFactor!.value, en: false)} '
                      '→ ${factorText(r.factor!.value, en: false)} — liczone jak '
                      'jedno cięgno, bo przy przesuniętym środku ciężkości '
                      'jedno cięgno może przejąć prawie cały ciężar.',
                  en: 'Asymmetric: ${factorText(r.symmetricFactor!.value, en: true)} '
                      '→ ${factorText(r.factor!.value, en: true)} — rated as one '
                      'leg, because with the centre of gravity off-axis one '
                      'leg can take nearly all the weight.'),
              key: const ValueKey('rig-asym-note')),
        if (r.requiredWllKg != null) ...[
          _kv(
              context.tr(
                  pl: 'Minimalne ${_requiredLabel(r, en: false)} dla tego '
                      'układu',
                  en: 'Minimum ${_requiredLabel(r, en: true)} for this '
                      'set-up'),
              _mass2(r.requiredWllKg!),
              key: const ValueKey('rig-required')),
          if (r.suggestedSeriesT != null)
            _kv(
                context.tr(
                    pl: 'Pas z typoszeregu', en: 'Sling from the series'),
                '${_n(r.suggestedSeriesT!)} t',
                key: const ValueKey('rig-series')),
        ],
        if (t != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              key: const ValueKey('rig-tension'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder),
              ),
              child: Text(
                context.tr(
                    pl: 'Informacyjnie (fizyka, NIE werdykt): T = W / (n · cos β) '
                        '= ${_kg(r.massKg!)} / (${t.legs} · cos '
                        '${degText(t.betaDeg, en: false)}) ≈ ${_kg(t.perLegKg)} '
                        'na cięgno.'
                        '${t.perLegIfTwoCarryKg != null ? ' Gdy niosą tylko 2 cięgna: ≈ ${_kg(t.perLegIfTwoCarryKg!)}.' : ''}'
                        ' Werdykt liczy się z tabeli współczynników.',
                    en: 'For information (physics, NOT the verdict): T = W / '
                        '(n · cos β) = ${_kg(r.massKg!)} / (${t.legs} · cos '
                        '${degText(t.betaDeg, en: true)}) ≈ ${_kg(t.perLegKg)} '
                        'per leg.'
                        '${t.perLegIfTwoCarryKg != null ? ' If only 2 legs carry: ≈ ${_kg(t.perLegIfTwoCarryKg!)}.' : ''}'
                        ' The verdict uses the mode factor table.'),
                style: const TextStyle(
                    fontSize: 12.5, color: kTextSec, height: 1.4),
              ),
            ),
          ),
      ],
    );
  }

  // ── Lista kontrolna ──────────────────────────────────────────────────────

  CheckMark? _markOf(RiggingCheck c) => effectiveMark(c, _marks, _label);

  void _tapMark(RiggingCheck c, CheckMark m) {
    if (c.id == kRiggingLabelCheckId) {
      _setLabel(m == CheckMark.ok ? LabelState.readable : LabelState.missing);
    } else {
      _setMark(c.id, m);
    }
  }

  Widget _checkRow(RiggingCheck c) {
    final mark = _markOf(c);
    final color = switch (mark) {
      CheckMark.ok => kPass,
      CheckMark.defect => kFail,
      CheckMark.na => kTextSec,
      null => kBorder,
    };
    String markLabel(CheckMark m) => switch (m) {
          CheckMark.ok => 'OK',
          CheckMark.defect => context.tr(pl: 'Wada', en: 'Defect'),
          CheckMark.na => context.tr(pl: 'Nie dotyczy', en: 'N/A'),
        };
    return Padding(
      key: ValueKey('rig-check-${c.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.label(en: _en),
                style: const TextStyle(
                    fontSize: 13.5, color: kText, height: 1.35)),
            Text(c.source,
                style: const TextStyle(fontSize: 11.5, color: kTextMut)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in [
                  CheckMark.ok,
                  CheckMark.defect,
                  if (c.naAllowed) CheckMark.na,
                ])
                  ChoiceChip(
                    key: ValueKey('rig-check-${c.id}-${m.name}'),
                    label: Text(markLabel(m)),
                    selected: mark == m,
                    onSelected: (_) => _tapMark(c, m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklistSection(ChecklistStatus s) {
    final checks = riggingChecksFor(_sling);
    final (Color color, IconData icon) = switch (s.verdict) {
      ChecklistVerdict.complete => (kPass, Icons.check_circle_outline),
      ChecklistVerdict.incomplete => (kWarn, Icons.pending_outlined),
      ChecklistVerdict.rejected => (kFail, Icons.dangerous_outlined),
    };
    return QuoteSection(
      title: context.tr(
          pl: 'Lista kontrolna przed podniesieniem', en: 'Pre-lift checklist'),
      subtitle: context.tr(
          pl: 'Każda pozycja musi mieć ocenę — niezaznaczona to nie OK. Lista '
              'nie jest zapisywana: przed każdym podniesieniem od nowa.',
          en: 'Every item needs a mark — an unchecked item is not OK. The list '
              'is not saved: start over before every lift.'),
      children: [
        for (final g in RiggingCheckGroup.values) ...[
          if (checks.any((c) => c.group == g))
            _label2(g.label(en: _en).toUpperCase()),
          for (final c in checks)
            if (c.group == g) _checkRow(c),
        ],
        const SizedBox(height: 4),
        KeyedSubtree(
          key: ValueKey('rig-checklist-${s.verdict.name}'),
          child: QuoteNotice(
            color: color,
            icon: icon,
            text: checklistVerdictText(s, en: _en),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('rig-checklist-reset'),
            onPressed: _resetChecklist,
            icon: const Icon(Icons.restart_alt),
            label: Text(context.tr(
                pl: 'Wyczyść listę (następne podniesienie)',
                en: 'Clear the list (next lift)')),
          ),
        ),
      ],
    );
  }

  Widget _readiness(RiggingResult r, ChecklistStatus s) {
    final ready = liftReadiness(r, s);
    final (Color color, IconData icon) = switch (ready) {
      LiftReadiness.go => (kPass, Icons.check_circle),
      LiftReadiness.stop => (kFail, Icons.dangerous),
      LiftReadiness.notReady => (kWarn, Icons.pending_outlined),
    };
    return KeyedSubtree(
      key: ValueKey('rig-ready-${ready.name}'),
      child: QuoteNotice(
        color: color,
        icon: icon,
        text: '${readinessTitle(ready, en: _en)}\n'
            '${context.tr(pl: 'Kalkulator', en: 'Calculator')}: '
            '${verdictTitle(r.verdict, en: _en)}\n'
            '${checklistVerdictText(s, en: _en)}',
      ),
    );
  }

  // ── Źródła i zastrzeżenie ────────────────────────────────────────────────

  Widget _sourcesSection() {
    Widget item(RiggingSource s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('• ${s.label(en: _en)}',
              style:
                  const TextStyle(fontSize: 12, color: kTextSec, height: 1.4)),
        );
    return QuoteSection(
      key: const ValueKey('rig-sources'),
      title: context.tr(pl: 'Źródła', en: 'Sources'),
      children: [
        for (final s in kRiggingSources) item(s),
        _label2(
            context.tr(pl: 'Przyjęte w aplikacji', en: 'Adopted in the app')),
        KeyedSubtree(
          key: const ValueKey('rig-adopted'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final s in kRiggingAdopted) item(s)],
          ),
        ),
      ],
    );
  }

  Widget _disclaimer() {
    return QuoteNotice(
      key: const ValueKey('rig-disclaimer'),
      text: context.tr(
          pl: 'Kalkulator nie zastępuje planu podnoszenia, osoby kierującej '
              'ani instrukcji producenta zawiesia i dźwigu. Wiąże etykieta '
              'zawiesia i tabela producenta — gdy podają niższe wartości, '
              'obowiązują one. Normy EN 1492, EN 818 i EN 13414 — w wydaniu '
              'przywołanym w instrukcji zawiesia.',
          en: 'The calculator does not replace a lift plan, the person in '
              'charge or the sling and crane maker’s instructions. The sling '
              'label and the maker’s table govern — when they give lower '
              'values, those apply. EN 1492, EN 818 and EN 13414 — in the '
              'edition named in the sling instructions.'),
    );
  }
}

/// Rysunek: który kąt jest który — β od pionu (ten jest w tabeli) i α między
/// cięgnami (α = 2β). Wybrany kąt świeci bursztynem; opis pod rysunkiem
/// zwykłym tekstem (skaluje się z czcionką).
class _AngleDiagram extends StatelessWidget {
  final double betaDeg;
  final bool included;
  final bool en;

  const _AngleDiagram({
    super.key,
    required this.betaDeg,
    required this.included,
    required this.en,
  });

  Widget _legend(String symbol, String text, bool active) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(symbol,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: active ? kArc : kTextMut)),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: active ? kText : kTextMut,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: en
              ? 'Diagram: β is the angle of one leg from the vertical, α is '
                  'the angle between the legs, α = 2β'
              : 'Rysunek: β to kąt jednego cięgna od pionu, α to kąt między '
                  'cięgnami, α = 2β',
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _AnglePainter(betaDeg: betaDeg, included: included),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _legend(
            'β',
            en
                ? 'one leg from the vertical — the tables use this angle'
                : 'jedno cięgno od pionu — ten kąt jest w tabelach',
            !included),
        const SizedBox(height: 2),
        _legend(
            'α',
            en
                ? 'between the legs (included angle), α = 2β'
                : 'między cięgnami (wierzchołkowy), α = 2β',
            included),
      ],
    );
  }
}

class _AnglePainter extends CustomPainter {
  final double betaDeg;
  final bool included;

  _AnglePainter({required this.betaDeg, required this.included});

  @override
  void paint(Canvas canvas, Size size) {
    final b = betaDeg.clamp(5.0, 70.0) * math.pi / 180;
    final cx = size.width / 2;
    const top = 10.0;
    // Ładunek zawsze na tej samej wysokości; szerokie rozchylenie — niżej
    // hak (mniejsza wysokość), żeby cięgna zmieściły się w szerokości.
    final maxDx = size.width / 2 - 20;
    final h = math.min(size.height - top - 18, maxDx / math.tan(b));
    final dx = h * math.tan(b);
    final hook = Offset(cx, top);
    final left = Offset(cx - dx, top + h);
    final right = Offset(cx + dx, top + h);

    // Ładunek.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(left.dx - 10, top + h, right.dx + 10, top + h + 14),
          const Radius.circular(3)),
      Paint()..color = kBorder,
    );
    // Pion (przerywany).
    final dash = Paint()
      ..color = kTextMut
      ..strokeWidth = 1.2;
    for (var y = top; y < top + h; y += 8) {
      canvas.drawLine(
          Offset(cx, y), Offset(cx, math.min(y + 4, top + h)), dash);
    }
    // Cięgna i hak.
    final leg = Paint()
      ..color = kText
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(hook, left, leg);
    canvas.drawLine(hook, right, leg);
    canvas.drawCircle(hook, 4.5, Paint()..color = kTextSec);

    final betaColor = included ? kTextMut : kArc;
    final alphaColor = included ? kArc : kTextMut;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // β: od pionu do prawego cięgna.
    final rBeta = math.min(30.0, h * 0.45);
    canvas.drawArc(
        Rect.fromCircle(center: hook, radius: rBeta),
        math.pi / 2 - b,
        b,
        false,
        arc
          ..color = betaColor
          ..strokeWidth = included ? 1.5 : 3);
    // α: między cięgnami.
    final rAlpha = math.min(54.0, h * 0.75);
    canvas.drawArc(
        Rect.fromCircle(center: hook, radius: rAlpha),
        math.pi / 2 - b,
        2 * b,
        false,
        arc
          ..color = alphaColor
          ..strokeWidth = included ? 3 : 1.5);

    void letter(String text, Color color, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    // β przy łuku β (po prawej), α przy łuku α (po lewej).
    final midB = math.pi / 2 - b / 2;
    letter('β', betaColor,
        hook + Offset(math.cos(midB), math.sin(midB)) * (rBeta + 10));
    final midA = math.pi / 2 + b / 2;
    letter('α', alphaColor,
        hook + Offset(math.cos(midA), math.sin(midA)) * (rAlpha + 10));
  }

  @override
  bool shouldRepaint(_AnglePainter old) =>
      old.betaDeg != betaDeg || old.included != included;
}
