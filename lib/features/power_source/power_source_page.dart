// Spawarka: cykl pracy i przewody — „spawarka się wyłącza”, „na końcu
// 40 m przewodu łuk słaby”, „jaki przekrój kupić”.
//
// 1. Cykl pracy z tabliczki znamionowej (do 3 punktów I / X) przy prądzie
//    spawania: minuty spawania i przerwy na 10 min, prąd przy 100 %.
// 2. Przewody: spadek napięcia na całej pętli, obciążalność przekroju przy
//    danym cyklu, najdłuższa pętla dla progu.
// 3. Dobór najmniejszego przekroju (w górę do typoszeregu).
// 4. Szybkie wskazówki ze źródłami, udostępnianie tekstem.
// Logika i źródła: domain/welding/power_source.dart. Ostatnia tabliczka
// w SharedPreferences (power_source_plate_store.dart), bez bazy. Puste albo
// nieczytelne pole to komunikat, nie wynik.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/welding/power_source.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'power_source_plate_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef PowerSourceShareText = Future<void> Function(
    String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

class PowerSourcePage extends StatefulWidget {
  const PowerSourcePage({
    super.key,
    this.shareText = _defaultShareText,
    this.plateStore = const PowerSourcePlateStore(),
  });

  final PowerSourceShareText shareText;
  final PowerSourcePlateStore plateStore;

  @override
  State<PowerSourcePage> createState() => _PowerSourcePageState();
}

class _PowerSourcePageState extends State<PowerSourcePage>
    with ToolHandleHost<PowerSourcePage> {
  @override
  String get toolId => 'power_source';
  static const _cableFields = {
    'cable_mode',
    'weld_lead_m',
    'return_lead_m',
    'section_mm2',
    'duty_pct',
    'ambient_c',
    'drop_limit_v'
  };
  @override
  Set<String> get supportedFields =>
      const {'plate', 'weld_current_a', ..._cableFields};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.keys.any(_cableFields.contains)) return _applyCable(fields);
    final rejected = fields.keys.toSet().difference(supportedFields);
    final points = fields['plate'];
    final current = fields['weld_current_a'];
    final rows = <PlateRowInput>[];
    if (points is! List || points.isEmpty || points.length > kPlateRows) {
      rejected.add('plate');
    } else {
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        if (p is! Map ||
            p.keys.toSet().difference({'current_a', 'duty_pct'}).isNotEmpty ||
            p['current_a'] is! num ||
            p['duty_pct'] is! num) {
          rejected.add('plate');
        } else {
          rows.add(PlateRowInput(
              row: i + 1,
              currentA: (p['current_a'] as num).toDouble(),
              dutyPct: (p['duty_pct'] as num).toDouble()));
        }
      }
    }
    if (current is! num || !current.isFinite) rejected.add('weld_current_a');
    if (rejected.isEmpty &&
        computeDutyCycle(DutyCycleInput(
                rows: rows, weldCurrentA: (current as num).toDouble())) ==
            null) {
      rejected.addAll({'plate', 'weld_current_a'});
    }
    if (rejected.isNotEmpty || !mounted) {
      return rejected.isEmpty ? fields.keys.toSet() : rejected;
    }
    setState(() {
      _plateEdited = true;
      _fillPlate([for (final r in rows) PlatePoint(r.currentA, r.dutyPct)]);
      _current.text = current.toString();
      // A new duty calculation does not supply a cable installation.
      _leadWeld.clear();
      _leadReturn.clear();
      _cableDuty.clear();
      _dropLimit.clear();
    });
    return {};
  }

  Future<Set<String>> _applyCable(Map<String, Object?> fields) async {
    final rejected =
        fields.keys.toSet().difference({..._cableFields, 'weld_current_a'});
    final mode = fields['cable_mode'];
    if (!const ['check', 'size'].contains(mode)) rejected.add('cable_mode');
    double n(String k) =>
        fields[k] is num ? (fields[k] as num).toDouble() : double.nan;
    final section = n('section_mm2'), ambient = n('ambient_c');
    final input = CableInput(
        currentA: n('weld_current_a'),
        weldLeadM: n('weld_lead_m'),
        returnLeadM: n('return_lead_m'),
        sectionMm2: section.isFinite && section == section.roundToDouble()
            ? section.toInt()
            : 0,
        dutyPct: n('duty_pct'),
        ambientC: ambient.isFinite && ambient == ambient.roundToDouble()
            ? ambient.toInt()
            : 0,
        dropLimitV: n('drop_limit_v'));
    if (mode == 'size' && fields.containsKey('section_mm2')) {
      rejected.add('section_mm2');
    }
    for (final p in cableProblems(input, forSizing: mode == 'size')) {
      rejected.add(switch (p) {
        CableProblem.current => 'weld_current_a',
        CableProblem.weldLead => 'weld_lead_m',
        CableProblem.returnLead => 'return_lead_m',
        CableProblem.noLength => 'weld_lead_m',
        CableProblem.section => 'section_mm2',
        CableProblem.duty => 'duty_pct',
        CableProblem.ambient => 'ambient_c',
        CableProblem.dropLimit => 'drop_limit_v'
      });
    }
    if (rejected.isNotEmpty || !mounted) {
      return rejected.isEmpty ? fields.keys.toSet() : rejected;
    }
    final selected =
        mode == 'size' ? sizeCable(input)!.sectionMm2 : input.sectionMm2;
    setState(() {
      _plateEdited = true;
      _fillPlate([]);
      _current.text = input.currentA.toString();
      _leadWeld.text = input.weldLeadM.toString();
      _leadReturn.text = input.returnLeadM.toString();
      _cableDuty.text = input.dutyPct.toString();
      _dropLimit.text = input.dropLimitV.toString();
      _section = selected;
      _ambient = input.ambientC;
    });
    return {};
  }

  // Przykład z typowej tabliczki MMA/TIG.
  static const _defaultPlate = [
    PlatePoint(200, 35),
    PlatePoint(160, 60),
    PlatePoint(130, 100),
  ];

  final _plateI = List.generate(kPlateRows, (_) => TextEditingController());
  final _plateX = List.generate(kPlateRows, (_) => TextEditingController());
  final _current = TextEditingController(text: '150');
  final _leadWeld = TextEditingController(text: '25');
  final _leadReturn = TextEditingController(text: '25');
  final _cableDuty = TextEditingController(text: '60');
  final _dropLimit = TextEditingController();

  int? _section = 35;
  int _ambient = 30;
  bool _plateEdited = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _fillPlate(_defaultPlate);
    _dropLimit.text = psNum(kDefaultDropLimitV, en: false);
    unawaited(_loadPlate().whenComplete(markReady));
  }

  @override
  void dispose() {
    for (final c in [
      ..._plateI,
      ..._plateX,
      _current,
      _leadWeld,
      _leadReturn,
      _cableDuty,
      _dropLimit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  String _n(double v) => psNum(v, en: _en);
  String _f(double v, int d) => psFixed(v, d, en: _en);

  /// Liczba z pola; puste albo nieczytelne → NaN (domena zgłosi problem).
  double _val(TextEditingController c) => parseDecimal(c.text) ?? double.nan;

  void _fillPlate(List<PlatePoint> points) {
    for (var k = 0; k < kPlateRows; k++) {
      final p = k < points.length ? points[k] : null;
      _plateI[k].text = p == null ? '' : numText(p.currentA);
      _plateX[k].text = p == null ? '' : numText(p.dutyPct);
    }
  }

  Future<void> _loadPlate() async {
    final List<PlatePoint> saved;
    try {
      saved = await widget.plateStore.load();
    } catch (_) {
      return;
    }
    if (!mounted || saved.isEmpty || _plateEdited) return;
    setState(() => _fillPlate(saved));
  }

  void _plateChanged() {
    _plateEdited = true;
    setState(() {});
    final points = validPlatePoints(_plateRows);
    unawaited(widget.plateStore.save(points).catchError((Object _) {}));
  }

  /// Wiersze tabliczki, w których coś wpisano (oba pola puste → pominięty).
  List<PlateRowInput> get _plateRows => [
        for (var k = 0; k < kPlateRows; k++)
          if (_plateI[k].text.trim().isNotEmpty ||
              _plateX[k].text.trim().isNotEmpty)
            PlateRowInput(
              row: k + 1,
              currentA: _val(_plateI[k]),
              dutyPct: _val(_plateX[k]),
            ),
      ];

  DutyCycleInput get _dutyInput =>
      DutyCycleInput(rows: _plateRows, weldCurrentA: _val(_current));

  CableInput get _cableInput => CableInput(
        currentA: _val(_current),
        weldLeadM: _val(_leadWeld),
        returnLeadM: _val(_leadReturn),
        sectionMm2: _section ?? 0,
        dutyPct: _val(_cableDuty),
        ambientC: _ambient,
        dropLimitV: _val(_dropLimit),
      );

  // ── Komunikaty ─────────────────────────────────────────────────────────

  String _dutyProblem(DutyProblem p) => switch (p.kind) {
        DutyProblemKind.noPlate => context.tr(
            pl: 'Wpisz co najmniej jeden punkt z tabliczki: prąd i cykl pracy.',
            en: 'Enter at least one rating plate point: current and duty '
                'cycle.'),
        DutyProblemKind.plateCurrent => context.tr(
            pl: 'Wiersz ${p.row}: podaj prąd z tabliczki (do '
                '${_n(kMaxCurrentA)} A).',
            en: 'Row ${p.row}: enter the plate current (up to '
                '${_n(kMaxCurrentA)} A).'),
        DutyProblemKind.plateDuty => context.tr(
            pl: 'Wiersz ${p.row}: cykl pracy od ${_n(kMinDutyPct)} do '
                '${_n(kMaxDutyPct)} %.',
            en: 'Row ${p.row}: duty cycle from ${_n(kMinDutyPct)} to '
                '${_n(kMaxDutyPct)} %.'),
        DutyProblemKind.duplicateCurrent => context.tr(
            pl: 'Dwa wiersze z tym samym prądem — zostaw jeden.',
            en: 'Two rows with the same current — keep one.'),
        DutyProblemKind.inconsistentPlate => context.tr(
            pl: 'Sprzeczna tabliczka: przy większym prądzie cykl pracy musi '
                'być mniejszy. Sprawdź, czy prąd i cykl nie są zamienione.',
            en: 'Inconsistent plate: a higher current must have a lower duty '
                'cycle. Check that current and duty cycle are not swapped.'),
        DutyProblemKind.weldCurrent => context.tr(
            pl: 'Podaj prąd spawania (do ${_n(kMaxCurrentA)} A).',
            en: 'Enter the welding current (up to ${_n(kMaxCurrentA)} A).'),
      };

  String _cableProblem(CableProblem p) => switch (p) {
        CableProblem.current => context.tr(
            pl: 'Podaj prąd spawania na górze ekranu (do '
                '${_n(kMaxCurrentA)} A).',
            en: 'Enter the welding current at the top of the screen (up to '
                '${_n(kMaxCurrentA)} A).'),
        CableProblem.weldLead => context.tr(
            pl: 'Długość przewodu spawalniczego od 0 do ${_n(kMaxLeadM)} m.',
            en: 'Welding lead length from 0 to ${_n(kMaxLeadM)} m.'),
        CableProblem.returnLead => context.tr(
            pl: 'Długość przewodu masowego od 0 do ${_n(kMaxLeadM)} m.',
            en: 'Return lead length from 0 to ${_n(kMaxLeadM)} m.'),
        CableProblem.noLength => context.tr(
            pl: 'Pętla ma długość 0 m — wpisz długości przewodów.',
            en: 'The loop is 0 m long — enter the lead lengths.'),
        CableProblem.section => context.tr(
            pl: 'Wybierz przekrój przewodu.', en: 'Choose the cable size.'),
        CableProblem.duty => context.tr(
            pl: 'Cykl pracy przewodu od ${_n(kMinDutyPct)} do '
                '${_n(kMaxDutyPct)} %.',
            en: 'Cable duty cycle from ${_n(kMinDutyPct)} to '
                '${_n(kMaxDutyPct)} %.'),
        CableProblem.ambient => context.tr(
            pl: 'Wybierz temperaturę otoczenia.',
            en: 'Choose the ambient temperature.'),
        CableProblem.dropLimit => context.tr(
            pl: 'Próg spadku napięcia od ${_n(kMinDropLimitV)} do '
                '${_n(kMaxDropLimitV)} V.',
            en: 'Voltage drop limit from ${_n(kMinDropLimitV)} to '
                '${_n(kMaxDropLimitV)} V.'),
      };

  // ── Akcje ──────────────────────────────────────────────────────────────

  Future<void> _share(DutyCycleResult? duty, CableCheckResult? cable,
      CableSizingResult? sizing) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final text = powerSourceShareText(
          en: _en, duty: duty, cable: cable, sizing: sizing);
      unawaited(Haptic.tap());
      await widget.shareText(
          text,
          context.tr(
              pl: 'Spawarka: cykl pracy i przewody',
              en: 'Welder: duty cycle and cables'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się udostępnić.', en: 'Could not share.'))));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dutyInput = _dutyInput;
    final dutyProblemList = dutyProblems(dutyInput);
    final duty = computeDutyCycle(dutyInput);
    final cableInput = _cableInput;
    final cableProblemList = cableProblems(cableInput);
    final cable = checkCable(cableInput);
    final sizing = sizeCable(cableInput);

    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Spawarka: cykl pracy i przewody',
              en: 'Welder: duty cycle and cables'))),
      body: ListView(
        key: const ValueKey('ps-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _dutySection(dutyProblemList, duty),
          _cableSection(cableProblemList, cable),
          _sizingSection(sizing),
          _tipsSection(),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              key: const ValueKey('ps-share'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: kArc,
                foregroundColor: kOnArc,
              ),
              onPressed: _sharing
                  ? null
                  : () => unawaited(_share(duty, cable, sizing)),
              icon: const Icon(Icons.share_outlined),
              label: Text(
                  context.tr(pl: 'Udostępnij wynik', en: 'Share the result'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          KeyedSubtree(
            key: const ValueKey('ps-disclaimer'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.engineering_outlined,
              text: powerSourceDisclaimer(en: _en),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pomocnicze widżety ─────────────────────────────────────────────────

  Widget _field(TextEditingController c, String label,
          {required Key key,
          String? unit,
          String? helper,
          VoidCallback? onChanged,
          EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: 10)}) =>
      Padding(
        padding: padding,
        child: TextField(
          key: key,
          controller: c,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          onChanged: (_) {
            if (onChanged != null) {
              onChanged();
            } else {
              setState(() {});
            }
          },
          decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            helperText: helper,
            helperMaxLines: 4,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _note(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _chips(List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: chips),
      );

  Widget _choice(String key, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(onTap),
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
              // Flexible: długa wartość („szacunek z 200 A / 35 %”) zawija
              // się na wąskim ekranie zamiast wychodzić poza kartę.
              Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );

  Widget _verdict(String key, bool ok, String text) => KeyedSubtree(
        key: ValueKey(key),
        child: QuoteNotice(
          color: ok ? kPass : kFail,
          icon: ok ? Icons.check_circle_outline : Icons.error_outline,
          text: text,
        ),
      );

  // ── Sekcja 1: cykl pracy ───────────────────────────────────────────────

  Widget _dutySection(List<DutyProblem> problems, DutyCycleResult? r) {
    return QuoteSection(
      title: context.tr(
          pl: 'Cykl pracy z tabliczki', en: 'Duty cycle from the plate'),
      subtitle: context.tr(
          pl: 'Ile minut na każde 10 możesz spawać przy danym prądzie, '
              'zanim spawarka się przegrzeje.',
          en: 'How many minutes in every 10 you can weld at a given current '
              'before the welder overheats.'),
      children: [
        _field(_current,
            context.tr(pl: 'Prąd spawania I₂', en: 'Welding current I₂'),
            key: const ValueKey('ps-current'), unit: 'A'),
        _label(context.tr(
            pl: 'Tabliczka znamionowa: prąd I₁ przy cyklu pracy X₁',
            en: 'Rating plate: current I₁ at duty cycle X₁')),
        for (var k = 0; k < kPlateRows; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    _plateI[k],
                    context.tr(pl: 'Prąd ${k + 1}', en: 'Current ${k + 1}'),
                    key: ValueKey('ps-plate-i-${k + 1}'),
                    unit: 'A',
                    onChanged: _plateChanged,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(
                    _plateX[k],
                    context.tr(pl: 'Cykl ${k + 1}', en: 'Duty ${k + 1}'),
                    key: ValueKey('ps-plate-x-${k + 1}'),
                    unit: '%',
                    onChanged: _plateChanged,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        _note(context.tr(
            pl: 'Pary z tabliczki dla procesu, którym spawasz (np. 200 A / '
                '35 %, 160 A / 60 %, 130 A / 100 %). Pusty wiersz pomijamy. '
                'Ostatnia tabliczka zapisuje się na telefonie.',
            en: 'Pairs from the plate for the process you weld with (e.g. '
                '200 A / 35 %, 160 A / 60 %, 130 A / 100 %). An empty row is '
                'skipped. The last plate is saved on the phone.')),
        const SizedBox(height: 8),
        if (problems.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('ps-duty-problems'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: problems.map(_dutyProblem).join('\n'),
            ),
          ),
        if (r != null) ...[
          if (r.outOfRange)
            KeyedSubtree(
              key: const ValueKey('ps-out-of-range'),
              child: QuoteNotice(
                color: kFail,
                icon: Icons.block,
                text: context.tr(
                    pl: 'Poza zakresem źródła: ${_n(r.weldCurrentA)} A to '
                        'więcej niż największy prąd z tabliczki '
                        '(${_n(r.maxPoint.currentA)} A). Nie szacujemy — '
                        'zmniejsz prąd albo weź mocniejsze źródło.',
                    en: 'Outside the rating of the power source: '
                        '${_n(r.weldCurrentA)} A is more than the highest '
                        'plate current (${_n(r.maxPoint.currentA)} A). No '
                        'estimate — reduce the current or use a bigger '
                        'power source.'),
              ),
            )
          else ...[
            KeyedSubtree(
              key: const ValueKey('ps-duty'),
              child: Readout(
                label: context.tr(
                    pl: 'Dopuszczalny cykl pracy',
                    en: 'Permissible duty cycle'),
                value: '${r.dutyPct}',
                unit: context.tr(
                    pl: '% · przy ${_n(r.weldCurrentA)} A · w dół do 1 %',
                    en: '% · at ${_n(r.weldCurrentA)} A · down to 1 %'),
                hot: true,
              ),
            ),
            const SizedBox(height: 10),
            _kv(
                context.tr(
                    pl: 'Spawanie na każde 10 min',
                    en: 'Welding in every 10 min'),
                '${_f(r.weldMinutes!, 1)} min',
                key: const ValueKey('ps-weld-min')),
            _kv(context.tr(pl: 'Przerwa (chłodzenie)', en: 'Rest (cooling)'),
                '${_f(r.restMinutes!, 1)} min',
                key: const ValueKey('ps-rest-min')),
            _kv(
                context.tr(pl: 'Skąd', en: 'Basis'),
                r.fromPlate
                    ? context.tr(
                        pl: 'tabliczka ${platePointText(r.plateBasis!, en: _en)}',
                        en: 'plate ${platePointText(r.plateBasis!, en: _en)}')
                    : context.tr(
                        pl: 'szacunek z '
                            '${platePointText(r.estimateBasis!, en: _en)}',
                        en: 'estimate from '
                            '${platePointText(r.estimateBasis!, en: _en)}'),
                key: const ValueKey('ps-duty-basis')),
          ],
          _kv(
              context.tr(
                  pl: 'Praca ciągła (100 %) do',
                  en: 'Continuous (100 %) up to'),
              '${r.i100A} A',
              key: const ValueKey('ps-i100')),
          _kv(
              context.tr(
                  pl: 'Największy prąd z tabliczki',
                  en: 'Highest plate current'),
              platePointText(r.maxPoint, en: _en)),
        ],
        _note(dutyFormulaNote(en: _en), key: const ValueKey('ps-duty-formula')),
        _note(dutyAmbientNote(en: _en)),
      ],
    );
  }

  // ── Sekcja 2: przewody ─────────────────────────────────────────────────

  Widget _cableInputs() {
    final loop = _val(_leadWeld) + _val(_leadReturn);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv(context.tr(pl: 'Prąd (pole wyżej)', en: 'Current (field above)'),
            _val(_current).isFinite ? '${_n(_val(_current))} A' : '—',
            key: const ValueKey('ps-cable-current')),
        const SizedBox(height: 6),
        _field(
            _leadWeld,
            context.tr(
                pl: 'Przewód spawalniczy (do uchwytu)',
                en: 'Welding lead (to the holder)'),
            key: const ValueKey('ps-lead-weld'),
            unit: 'm'),
        _field(_leadReturn,
            context.tr(pl: 'Przewód masowy', en: 'Return (work) lead'),
            key: const ValueKey('ps-lead-return'), unit: 'm'),
        _kv(
            context.tr(
                pl: 'Cała pętla (spawalniczy + masowy)',
                en: 'Whole loop (welding + return)'),
            loop.isFinite ? '${_n(loop)} m' : '—',
            key: const ValueKey('ps-loop')),
        const SizedBox(height: 8),
        _label(context.tr(pl: 'Przekrój (miedź)', en: 'Size (copper)')),
        _chips([
          for (final s in kCableSectionsMm2)
            _choice(
                'ps-section-$s', '$s mm²', _section == s, () => _section = s),
        ]),
        _field(
            _cableDuty,
            context.tr(
                pl: 'Cykl pracy przewodu (łuk na 10 min)',
                en: 'Cable duty cycle (arc time in 10 min)'),
            key: const ValueKey('ps-cable-duty'),
            unit: '%',
            helper: context.tr(
                pl: '6 min łuku na 10 min = 60 %.',
                en: '6 min of arc in 10 min = 60 %.')),
        _label(
            context.tr(pl: 'Temperatura otoczenia', en: 'Ambient temperature')),
        _chips([
          for (final (t, _) in kCableAmbientFactors)
            _choice('ps-amb-$t', context.tr(pl: 'do $t °C', en: 'up to $t °C'),
                _ambient == t, () => _ambient = t),
        ]),
        _field(_dropLimit,
            context.tr(pl: 'Próg spadku napięcia', en: 'Voltage drop limit'),
            key: const ValueKey('ps-drop-limit'), unit: 'V'),
      ],
    );
  }

  Widget _cableSection(List<CableProblem> problems, CableCheckResult? r) {
    final limit = r == null ? '' : _n(r.input.dropLimitV);
    return QuoteSection(
      title: context.tr(
          pl: 'Przewody: spadek napięcia i nagrzewanie',
          en: 'Cables: voltage drop and heating'),
      subtitle: context.tr(
          pl: 'Słaby łuk i klejąca się elektroda na końcu długiego przewodu '
              '— to spadek napięcia na całej pętli.',
          en: 'A weak arc and a sticking electrode at the end of a long lead '
              '— that is the voltage drop over the whole loop.'),
      children: [
        _cableInputs(),
        if (problems.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('ps-cable-problems'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: problems.map(_cableProblem).join('\n'),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 4),
          KeyedSubtree(
            key: const ValueKey('ps-drop'),
            child: Readout(
              label: context.tr(
                  pl: 'Spadek napięcia na przewodach',
                  en: 'Voltage drop in the leads'),
              value: _f(r.dropV, 1),
              unit: context.tr(
                  pl: 'V · ${r.sectionMm2} mm² · pętla ${_n(r.loopM)} m',
                  en: 'V · ${r.sectionMm2} mm² · loop ${_n(r.loopM)} m'),
            ),
          ),
          const SizedBox(height: 10),
          _verdict(
              'ps-drop-verdict',
              r.dropOk,
              r.dropOk
                  ? context.tr(
                      pl: 'Spadek ${_f(r.dropV, 1)} V mieści się w progu '
                          '$limit V.',
                      en: 'Drop of ${_f(r.dropV, 1)} V is within the $limit V '
                          'limit.')
                  : context.tr(
                      pl: 'Za duży spadek: ${_f(r.dropV, 1)} V > $limit V. '
                          'Łuk słabszy, elektroda może się kleić — grubszy '
                          'przewód albo krótsza pętla.',
                      en: 'Drop too large: ${_f(r.dropV, 1)} V > $limit V. '
                          'Weaker arc, the electrode may stick — a thicker '
                          'cable or a shorter loop.')),
          _kv(
              context.tr(
                  pl: 'Najdłuższa pętla dla $limit V (${r.sectionMm2} mm²)',
                  en: 'Longest loop for $limit V (${r.sectionMm2} mm²)'),
              r.maxLoopM > 0
                  ? '${r.maxLoopM} m'
                  : context.tr(pl: 'poniżej 1 m', en: 'under 1 m'),
              key: const ValueKey('ps-max-loop')),
          const SizedBox(height: 6),
          _kv(
              context.tr(
                  pl: 'Obciążalność ${r.sectionMm2} mm² (kolumna '
                      '${r.dutyColumnPct} %, do ${r.input.ambientC} °C)',
                  en: 'Rating of ${r.sectionMm2} mm² (${r.dutyColumnPct} % '
                      'column, up to ${r.input.ambientC} °C)'),
              '${r.ampacityA} A',
              key: const ValueKey('ps-ampacity')),
          const SizedBox(height: 6),
          _verdict(
              'ps-heat-verdict',
              r.heatOk,
              r.heatOk
                  ? context.tr(
                      pl: 'Nagrzewanie: przekrój OK — ${r.ampacityA} A ≥ '
                          '${_n(r.input.currentA)} A.',
                      en: 'Heating: size OK — ${r.ampacityA} A ≥ '
                          '${_n(r.input.currentA)} A.')
                  : context.tr(
                      pl: 'Nagrzewanie: przekrój za mały — ${r.ampacityA} A '
                          '< ${_n(r.input.currentA)} A. Przewód się '
                          'przegrzeje.',
                      en: 'Heating: size too small — ${r.ampacityA} A < '
                          '${_n(r.input.currentA)} A. The cable will '
                          'overheat.')),
        ],
        _note(cableDropNote(en: _en), key: const ValueKey('ps-drop-formula')),
        _note(dropLimitNote(en: _en)),
        _note(cableHeatNote(en: _en)),
      ],
    );
  }

  // ── Sekcja 3: dobór przekroju ──────────────────────────────────────────

  static String _whyNone(CableSizingResult s, {required bool en}) {
    final heat = s.heatSectionMm2 == null, drop = s.dropSectionMm2 == null;
    if (heat && drop) {
      return en ? 'heating and voltage drop' : 'nagrzewanie i spadek napięcia';
    }
    return heat
        ? (en ? 'heating' : 'nagrzewanie')
        : (en ? 'voltage drop' : 'spadek napięcia');
  }

  Widget _sizingSection(CableSizingResult? s) {
    final check = s?.check;
    return QuoteSection(
      title: context.tr(pl: 'Jaki przekrój kupić', en: 'Which size to buy'),
      subtitle: context.tr(
          pl: 'Najmniejszy przekrój z typoszeregu 16–95 mm² dla tego prądu, '
              'pętli, cyklu, otoczenia i progu — w górę.',
          en: 'The smallest size from the 16–95 mm² range for this current, '
              'loop, duty cycle, ambient and limit — rounded up.'),
      children: [
        if (s == null)
          Text(
              context.tr(
                  pl: 'Popraw dane przewodów wyżej.',
                  en: 'Correct the cable data above.'),
              style: const TextStyle(fontSize: 13, color: kTextMut))
        else if (s.sectionMm2 == null)
          KeyedSubtree(
            key: const ValueKey('ps-min-none'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: context.tr(
                  pl: 'Żaden przekrój do 95 mm² nie wystarcza '
                      '(${_whyNone(s, en: false)}). Skróć pętlę (źródło '
                      'bliżej) albo zmniejsz prąd.',
                  en: 'No size up to 95 mm² is enough '
                      '(${_whyNone(s, en: true)}). Shorten the loop (power '
                      'source closer) or reduce the current.'),
            ),
          )
        else ...[
          KeyedSubtree(
            key: const ValueKey('ps-min-section'),
            child: Readout(
              label:
                  context.tr(pl: 'Najmniejszy przekrój', en: 'Smallest size'),
              value: '${s.sectionMm2}',
              unit: context.tr(
                  pl: 'mm² · miedź · oba przewody',
                  en: 'mm² · copper · both leads'),
            ),
          ),
          const SizedBox(height: 10),
          _kv(
              context.tr(pl: 'Decyduje', en: 'Governed by'),
              s.heatGoverns && s.dropGoverns
                  ? context.tr(
                      pl: 'nagrzewanie i spadek', en: 'heating and drop')
                  : s.heatGoverns
                      ? context.tr(pl: 'nagrzewanie', en: 'heating')
                      : context.tr(pl: 'spadek napięcia', en: 'voltage drop'),
              key: const ValueKey('ps-min-governs')),
          _kv(context.tr(pl: 'Spadek przy nim', en: 'Drop with it'),
              '${_f(check!.dropV, 1)} V',
              key: const ValueKey('ps-min-drop')),
          _kv(context.tr(pl: 'Obciążalność', en: 'Rating'),
              '${check.ampacityA} A',
              key: const ValueKey('ps-min-ampacity')),
        ],
      ],
    );
  }

  // ── Sekcja 4: wskazówki ────────────────────────────────────────────────

  Widget _tipsSection() {
    return QuoteSection(
      title: context.tr(pl: 'Szybkie wskazówki', en: 'Quick tips'),
      children: [
        for (final (i, t) in kPowerSourceTips.indexed) ...[
          if (i > 0) const Divider(height: 20, color: kBorder),
          Column(
            key: ValueKey('ps-tip-${t.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.title(en: _en),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: kText)),
              const SizedBox(height: 4),
              Text(t.text(en: _en),
                  style: const TextStyle(
                      fontSize: 13.5, color: kText, height: 1.4)),
              const SizedBox(height: 4),
              Text('${context.tr(pl: 'Źródło', en: 'Source')}: ${t.source}',
                  style: const TextStyle(
                      fontSize: 11.5, color: kTextMut, height: 1.3)),
            ],
          ),
        ],
      ],
    );
  }
}
