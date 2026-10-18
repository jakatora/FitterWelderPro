// Plan ściegów i elektrod — przed zmianą: ile ściegów wyjdzie na złącze,
// ile elektrod wziąć z suszarki / termosu i ile to potrwa.
//
// 1. Złącze: rura z typoszeregu (DN + Sch) albo ręcznie, blacha, pachwina;
//    rowek, szczelina, próg, kąt; liczba złączy.
// 2. Warstwy: grań, ścieg gorący, wypełnienie, lico — spoiwo każdej.
// 3. Elektrody zasadowe: klasa i źródło z modułu ekspozycji, kolejność
//    pracy, zmiana — „weź z suszarki” i porcje na zmianę.
// 4. Założenia do korekty: przekroje ściegów, współczynnik jarzenia łuku.
// Logika: domain/pass_plan/. Ostatnie wejścia w SharedPreferences
// (pass_plan_store.dart). Puste albo nieczytelne pole to komunikat, nie
// wynik.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/pipe_schedules.dart';
import '../../domain/pass_plan/pass_plan.dart';
import '../../domain/pass_plan/pass_plan_form.dart';
import '../../domain/pass_plan/pass_plan_sources.dart';
import '../../domain/pass_plan/pass_plan_text.dart';
import '../../domain/quotes/quote_labels.dart';
import '../../domain/quotes/quote_process.dart';
import '../../domain/quotes/weld_geometry.dart';
import '../../domain/welding/electrode_exposure.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'pass_plan_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef PassPlanShareText = Future<void> Function(String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

/// Przygotowanie rowka: faza 30° (EN ISO 9692-1, α = 60°) albo 37,5°
/// (ASME B16.25, α = 75°, próg 1,6) — te same wartości co w wycenie.
class _Bevel {
  final String id;
  final String labelPl;
  final String labelEn;
  final double angle;
  final double rootFace;
  final double gap;
  const _Bevel(
      this.id, this.labelPl, this.labelEn, this.angle, this.rootFace, this.gap);
}

const _kBevels = [
  _Bevel('en', 'Faza 30° (EN 9692)', 'Bevel 30° (EN 9692)', 60, 1.5, 2.5),
  _Bevel('asme', 'Faza 37,5° (ASME B16.25)', 'Bevel 37.5° (ASME B16.25)', 75,
      1.6, 3.0),
];

class PassPlanPage extends StatefulWidget {
  const PassPlanPage({
    super.key,
    this.shareText = _defaultShareText,
    this.store = const PassPlanStore(),
  });

  final PassPlanShareText shareText;
  final PassPlanStore store;

  @override
  State<PassPlanPage> createState() => _PassPlanPageState();
}

class _PassPlanPageState extends State<PassPlanPage> {
  final Map<String, TextEditingController> _c = {
    for (final k in PassPlanField.numeric) k: TextEditingController(),
  };

  /// Pola wyboru (rodzaj, rowek, spoiwa…) jako tekst formularza.
  final Map<String, String> _choices = {};

  bool _edited = false;

  /// Odczyt zapisu zakończony — do tego czasu nic nie zapisujemy.
  bool _loaded = false;
  bool _loadLossy = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _applyForm(passPlanDefaultForm());
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  // ── Formularz ──────────────────────────────────────────────────────────

  /// Separator dziesiętny języka ekranu (zapis i rachunek przyjmują oba).
  static String _display(String v) => AppLanguageController.isEnglish
      ? v.replaceAll(',', '.')
      : v.replaceAll('.', ',');

  void _applyForm(Map<String, String> form) {
    final numeric = PassPlanField.numeric;
    for (final e in form.entries) {
      if (numeric.contains(e.key)) {
        _c[e.key]!.text = _display(e.value);
      } else {
        _choices[e.key] = e.value;
      }
    }
  }

  Map<String, String> get _form => {
        ..._choices,
        for (final e in _c.entries) e.key: e.value.text,
      };

  Future<void> _load() async {
    ({Map<String, String> form, bool lossy})? saved;
    try {
      saved = await widget.store.load();
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    // Dopiero teraz wolno zapisywać: odczyt zdążył zachować kopię
    // uszkodzonego zapisu, a zapis nie nadpisze go wartościami domyślnymi.
    _loaded = true;
    if (_edited) {
      // Spawacz zaczął pisać, zanim zapis się wczytał — jego wpisy wygrywają.
      _save();
      return;
    }
    if (saved == null) return;
    setState(() {
      _applyForm(saved!.form);
      _loadLossy = saved.lossy;
    });
  }

  void _save() {
    unawaited(widget.store.save(_form).catchError((Object _) {}));
  }

  void _changed() {
    _edited = true;
    setState(() {});
    if (_loaded) _save();
  }

  void _choose(String key, String value) {
    _choices[key] = value;
    _changed();
  }

  String _choice(String key) => _choices[key] ?? passPlanDefaultForm()[key]!;

  void _setNumber(String key, double v) {
    final s = v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    _c[key]!.text = _display(s);
  }

  // ── Rura z typoszeregu ─────────────────────────────────────────────────

  PipeRow? get _row {
    final dn = int.tryParse(_choice(PassPlanField.dn));
    return dn == null ? null : kPipeWalls.where((r) => r.dn == dn).firstOrNull;
  }

  List<String> _schedulesOf(PipeRow row) =>
      kSchedulesCarbon.where((s) => row.walls[s] != null).toList();

  void _pickDn(int? dn) {
    final row = kPipeWalls.where((r) => r.dn == dn).firstOrNull;
    if (row == null) return;
    _choices[PassPlanField.dn] = '${row.dn}';
    _setNumber(PassPlanField.od, row.od);
    final list = _schedulesOf(row);
    var sch = _choice(PassPlanField.sch);
    if (!list.contains(sch)) {
      sch = list.contains('40') ? '40' : (list.isEmpty ? '' : list.first);
    }
    _choices[PassPlanField.sch] = sch;
    final wall = row.walls[sch];
    if (wall != null) _setNumber(PassPlanField.wall, wall);
    _changed();
  }

  void _pickSch(String sch) {
    final wall = _row?.walls[sch];
    if (wall == null) return;
    _choices[PassPlanField.sch] = sch;
    _setNumber(PassPlanField.wall, wall);
    _changed();
  }

  /// Ręczna zmiana OD / ścianki: lista DN i Sch pokazują tylko to, co
  /// naprawdę pasuje do wpisanych wymiarów.
  void _syncPipePick() {
    final od = parseDecimal(_c[PassPlanField.od]!.text);
    final wall = parseDecimal(_c[PassPlanField.wall]!.text);
    final row = od == null
        ? null
        : kPipeWalls.where((r) => (r.od - od).abs() <= 0.05).firstOrNull;
    _choices[PassPlanField.dn] = row == null ? '' : '${row.dn}';
    var sch = '';
    if (row != null && wall != null) {
      for (final s in _schedulesOf(row)) {
        if ((row.walls[s]! - wall).abs() < 0.005) {
          sch = s;
          break;
        }
      }
    }
    _choices[PassPlanField.sch] = sch;
  }

  void _applyBevel(_Bevel b) {
    _choices[PassPlanField.groove] = GrooveType.v.code;
    _setNumber(PassPlanField.angle, b.angle);
    _setNumber(PassPlanField.rootFace, b.rootFace);
    _setNumber(PassPlanField.gap, b.gap);
    _changed();
  }

  void _resetAssumptions() {
    final d = passPlanDefaultForm();
    for (final c in PassConsumable.values) {
      final k = PassPlanField.bead(c);
      _c[k]!.text = _display(d[k]!);
    }
    for (final p in kPassPlanProcesses) {
      final k = PassPlanField.arcOn(p);
      _c[k]!.text = _display(d[k]!);
    }
    _changed();
  }

  // ── Akcje ──────────────────────────────────────────────────────────────

  Future<void> _share(PassPlanResult r) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final text = passPlanShareText(r, en: _en);
      unawaited(Haptic.tap());
      await widget.shareText(text, passPlanTitle(en: _en));
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
    final input = passPlanInputFromForm(_form);
    final problems = passPlanProblems(input);
    final r = problems.isEmpty ? planPasses(input) : null;

    return Scaffold(
      appBar: AppBar(title: Text(passPlanTitle(en: _en))),
      body: ListView(
        key: const ValueKey('pp-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (_loadLossy)
            KeyedSubtree(
              key: const ValueKey('pp-load-notice'),
              child: QuoteNotice(
                color: kWarn,
                icon: Icons.restore,
                text: context.tr(
                    pl: 'Zapisane wejścia były uszkodzone — pola, których nie '
                        'dało się odczytać, mają wartości domyślne.',
                    en: 'The saved inputs were damaged — fields that could not '
                        'be read are back to their defaults.'),
              ),
            ),
          _jointSection(input),
          if (input.isButt) _grooveSection(input),
          _layersSection(input),
          _exposureInputSection(input),
          _assumptionsSection(input),
          if (problems.isNotEmpty)
            KeyedSubtree(
              key: const ValueKey('pp-problems'),
              child: QuoteNotice(
                color: kFail,
                icon: Icons.error_outline,
                text: problems
                    .map((p) => passPlanProblemText(p, en: _en))
                    .join('\n'),
              ),
            ),
          if (r != null) ...[
            _jointResultSection(r),
            _jobSection(r),
            if (r.exposure != null) _takeSection(r.exposure!),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                key: const ValueKey('pp-share'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: kArc,
                  foregroundColor: kOnArc,
                ),
                onPressed: _sharing ? null : () => unawaited(_share(r)),
                icon: const Icon(Icons.share_outlined),
                label: Text(
                    context.tr(pl: 'Udostępnij plan', en: 'Share the plan'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
          _sourcesSection(),
          KeyedSubtree(
            key: const ValueKey('pp-disclaimer'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.engineering_outlined,
              text: passPlanDisclaimer(en: _en),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pomocnicze widżety ─────────────────────────────────────────────────

  Widget _field(String key, String label,
          {String? unit,
          String? helper,
          bool decimal = true,
          VoidCallback? after,
          EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: 10)}) =>
      Padding(
        padding: padding,
        child: TextField(
          key: ValueKey('pp-${_fieldId(key)}'),
          controller: _c[key],
          keyboardType: numberKeyboard(decimal: decimal),
          inputFormatters: numberInputFormatters(decimal: decimal),
          onChanged: (_) {
            after?.call();
            _changed();
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

  /// Klucz widżetu pola: `bead.mma32` → `bead-mma32`, `arcOn.MMA` →
  /// `arcon-mma`, `rootFace` → `root-face`.
  static String _fieldId(String key) {
    if (key.startsWith('arcOn.')) {
      return 'arcon-${key.substring(6).toLowerCase()}';
    }
    if (key.startsWith('bead.')) return 'bead-${key.substring(5)}';
    return key.replaceAllMapped(
        RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _note(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _chips(List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: chips),
      );

  Widget _choiceChip(
          String key, String label, bool selected, VoidCallback on) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: selected,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => on(),
      );

  Widget _kv(String k, String v, {Key? key, bool strong = false}) =>
      CopyOnLongPress(
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
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: strong ? kArc : kText,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );

  // ── Sekcja: złącze ─────────────────────────────────────────────────────

  Widget _jointSection(PassPlanInput i) {
    final kind = i.kind;
    final row = _row;
    return QuoteSection(
      title: context.tr(pl: 'Złącze', en: 'Joint'),
      children: [
        _chips([
          for (final k in kPassPlanJointKinds)
            _choiceChip(
                'pp-kind-${k.name}', jointKindShort(k, en: _en), kind == k, () {
              _choices[PassPlanField.kind] = k.code;
              // Rura spawana z jednej strony — rowek X tylko na blachach.
              if (k.onPipe && i.groove == GrooveType.x) {
                _choices[PassPlanField.groove] = GrooveType.v.code;
              }
              _changed();
            }),
        ]),
        if (kind.onPipe) ...[
          KeyedSubtree(
            key: const ValueKey('pp-dn'),
            child: DropdownButtonFormField<int>(
              // Klucz z wartością: ręczna zmiana OD przestawia listę.
              key: ValueKey('pp-dn-${row?.dn ?? 0}'),
              initialValue: row?.dn,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Rura z typoszeregu (DN)',
                    en: 'Pipe from the table (DN)'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final r in kPipeWalls)
                  DropdownMenuItem(
                    value: r.dn,
                    child: Text(
                        'DN${r.dn} · ${r.nps}" · Ø${ppNum(r.od, en: _en)}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _pickDn,
            ),
          ),
          const SizedBox(height: 10),
          if (row != null && kind == JointKind.pipeButt)
            _chips([
              for (final s in _schedulesOf(row))
                _choiceChip(
                    'pp-sch-$s',
                    'Sch $s · ${ppNum(row.walls[s]!, en: _en)}',
                    _choice(PassPlanField.sch) == s,
                    () => _pickSch(s)),
            ]),
          _field(PassPlanField.od,
              context.tr(pl: 'Średnica zewnętrzna OD', en: 'Outside dia. OD'),
              unit: 'mm', after: _syncPipePick),
        ],
        if (!kind.isFillet)
          _field(
              PassPlanField.wall,
              kind.onPipe
                  ? context.tr(pl: 'Ścianka t', en: 'Wall t')
                  : context.tr(pl: 'Grubość blachy t', en: 'Plate thickness t'),
              unit: 'mm',
              after: kind.onPipe ? _syncPipePick : null),
        if (kind.isFillet)
          _field(PassPlanField.throat,
              context.tr(pl: 'Grubość spoiny a', en: 'Throat a'),
              unit: 'mm'),
        if (kind.hasLength)
          _field(PassPlanField.length,
              context.tr(pl: 'Długość jednej spoiny', en: 'Length of one weld'),
              unit: 'm'),
        _field(PassPlanField.count,
            context.tr(pl: 'Liczba złączy', en: 'Number of joints'),
            unit: context.tr(pl: 'szt.', en: 'pcs'), decimal: false),
      ],
    );
  }

  // ── Sekcja: rowek ──────────────────────────────────────────────────────

  Widget _grooveSection(PassPlanInput i) {
    final grooves = [
      GrooveType.v,
      if (!i.kind.onPipe) GrooveType.x,
      GrooveType.square,
    ];
    final square = i.groove == GrooveType.square;
    return QuoteSection(
      title: context.tr(pl: 'Rowek', en: 'Groove'),
      subtitle: context.tr(
          pl: 'Kąt CAŁKOWITY rowka (faza 30° na obu elementach = 60°).',
          en: 'TOTAL groove angle (30° bevel on both members = 60°).'),
      children: [
        _chips([
          for (final g in grooves)
            _choiceChip(
                'pp-groove-${g.code}',
                switch (g) {
                  GrooveType.v => 'V',
                  GrooveType.x =>
                    context.tr(pl: 'X (dwustronny)', en: 'X (double)'),
                  GrooveType.square =>
                    context.tr(pl: 'I (bez fazy)', en: 'I (square)'),
                },
                i.groove == g,
                () => _choose(PassPlanField.groove, g.code)),
        ]),
        if (!square)
          _chips([
            for (final b in _kBevels)
              ActionChip(
                key: ValueKey('pp-bevel-${b.id}'),
                label: Text(_en ? b.labelEn : b.labelPl),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => _applyBevel(b),
              ),
          ]),
        if (!square)
          FieldPair(
            left: _field(PassPlanField.angle,
                context.tr(pl: 'Kąt rowka α', en: 'Groove angle α'),
                unit: '°', padding: EdgeInsets.zero),
            right: _field(PassPlanField.rootFace,
                context.tr(pl: 'Próg c', en: 'Root face c'),
                unit: 'mm', padding: EdgeInsets.zero),
          ),
        if (!square) const SizedBox(height: 10),
        _field(PassPlanField.gap, context.tr(pl: 'Szczelina b', en: 'Gap b'),
            unit: 'mm'),
      ],
    );
  }

  // ── Sekcja: warstwy ────────────────────────────────────────────────────

  String _cons(PassConsumable c) => consumableShort(c, en: _en);

  Widget _consumableChips(String field, List<PassConsumable> choices,
          {bool withNone = false}) =>
      _chips([
        if (withNone)
          _choiceChip(
              'pp-$field-none',
              context.tr(pl: 'brak', en: 'none'),
              _choice(field) == kPassPlanNone,
              () => _choose(field, kPassPlanNone)),
        for (final c in choices)
          _choiceChip('pp-$field-${c.name}', _cons(c), _choice(field) == c.name,
              () => _choose(field, c.name)),
      ]);

  Widget _layersSection(PassPlanInput i) {
    final longOk = i.layerConsumables
        .any((c) => c == PassConsumable.mma32 || c == PassConsumable.mma40);
    return QuoteSection(
      title: context.tr(pl: 'Warstwy i spoiwa', en: 'Layers and fillers'),
      subtitle: context.tr(
          pl: 'Elektrody zasadowe wg karty ESAB OK 48.00. Grań do 3 mm '
              'wysokości, lico — górne 2 mm rowka z nadlewem.',
          en: 'Low-hydrogen electrodes per the ESAB OK 48.00 data sheet. Root '
              'up to 3 mm high, cap — the top 2 mm of the groove plus '
              'reinforcement.'),
      children: [
        _label(layerName(PassLayer.root, en: _en)),
        _consumableChips(PassPlanField.root, kRootChoices),
        _label(layerName(PassLayer.hot, en: _en)),
        if (i.hotApplicable)
          _consumableChips(PassPlanField.hot, kHotChoices, withNone: true)
        else
          _note(
              context.tr(
                  pl: 'Ścieg gorący tylko w rowku spawanym z jednej strony '
                      '(rura, blacha V / I).',
                  en: 'Hot pass only in a groove welded from one side (pipe, '
                      'V / I plate).'),
              key: const ValueKey('pp-hot-na')),
        _label(layerName(PassLayer.fill, en: _en)),
        _consumableChips(PassPlanField.fill, kFillChoices),
        _label(layerName(PassLayer.cap, en: _en)),
        _consumableChips(PassPlanField.cap, kCapChoices),
        if (longOk) ...[
          _label(context.tr(
              pl: 'Długość elektrod Ø3,2 / Ø4,0',
              en: 'Electrode length Ø3.2 / Ø4.0')),
          _chips([
            _choiceChip(
                'pp-len-350',
                '350 mm',
                _choice(PassPlanField.long) == '0',
                () => _choose(PassPlanField.long, '0')),
            _choiceChip(
                'pp-len-450',
                '450 mm',
                _choice(PassPlanField.long) == '1',
                () => _choose(PassPlanField.long, '1')),
          ]),
        ],
        if (i.usesTig) ...[
          _label(context.tr(pl: 'Pręt TIG', en: 'TIG rod')),
          _chips([
            for (final d in kTigRodDiametersMm)
              _choiceChip(
                  'pp-rod-$d',
                  'Ø${formatDiameter(d, en: _en)}',
                  parseDecimal(_choice(PassPlanField.rod)) == d,
                  () => _choose(PassPlanField.rod, '$d')),
          ]),
        ],
        if (i.usesElectrodes)
          _field(
              PassPlanField.stub,
              context.tr(
                  pl: 'Ogarek (wyrzucana końcówka)',
                  en: 'Stub (discarded end)'),
              unit: 'mm',
              helper: context.tr(
                  pl: 'Przyjęte 50 mm. Dłuższy ogarek = mniej stopiwa z '
                      'elektrody, więcej sztuk.',
                  en: 'Assumed 50 mm. A longer stub = less weld metal per '
                      'electrode, more pieces.')),
        _field(PassPlanField.reserve,
            context.tr(pl: 'Zapas na całość', en: 'Reserve for the job'),
            unit: '%',
            helper: context.tr(
                pl: 'Na pękniętą otulinę, sczepy, poprawki — 0 do 100 %, '
                    'nigdy ujemny.',
                en: 'For cracked coating, tacks, repairs — 0 to 100 %, never '
                    'negative.')),
      ],
    );
  }

  // ── Sekcja: ekspozycja (wejście) ───────────────────────────────────────

  /// Wpisany limit (w dół do minuty) dłuższy niż tabela.
  static bool _typedAboveTable(PassPlanInput i, int table) {
    final t = i.limitMinutes;
    return t != null && t.isFinite && floorTol(t) > table;
  }

  Widget _exposureInputSection(PassPlanInput i) {
    if (!i.usesElectrodes) {
      return QuoteSection(
        title: context.tr(
            pl: 'Elektrody poza suszarką', en: 'Electrodes out of the oven'),
        children: [
          _note(
              context.tr(
                  pl: 'W planie nie ma elektrod otulonych — limit czasu na '
                      'powietrzu nie dotyczy.',
                  en: 'No covered electrodes in the plan — the exposure limit '
                      'does not apply.'),
              key: const ValueKey('pp-no-electrodes')),
        ],
      );
    }
    final cls = i.electrodeClass;
    final tableLimit = cls == null ? null : defaultLimitMinutes(cls, i.source);
    return QuoteSection(
      title: context.tr(
          pl: 'Elektrody poza suszarką', en: 'Electrodes out of the oven'),
      subtitle: context.tr(
          pl: 'Limit czasu na powietrzu z modułu „Elektrody zasadowe: czas '
              'i suszenie”.',
          en: 'Exposure limit from the “Low-hydrogen electrodes: exposure” '
              'module.'),
      children: [
        KeyedSubtree(
          key: const ValueKey('pp-class'),
          child: DropdownButtonFormField<String>(
            // Klucz z wartością: odczyt zapisu po pierwszej klatce podmienia
            // wybór (initialValue działa tylko przy tworzeniu pola).
            key: ValueKey('pp-class-${_choice(PassPlanField.electrodeClass)}'),
            initialValue: _choice(PassPlanField.electrodeClass),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr(pl: 'Elektroda', en: 'Electrode'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final c in ElectrodeClass.values)
                DropdownMenuItem(
                  value: c.name,
                  child: Text(c.code, overflow: TextOverflow.ellipsis),
                ),
              DropdownMenuItem(
                value: kPassPlanNone,
                child: Text(
                    context.tr(
                        pl: 'Nie zasadowa (rutylowa, celulozowa)',
                        en: 'Not low-hydrogen (rutile, cellulosic)'),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (v) {
              if (v != null) _choose(PassPlanField.electrodeClass, v);
            },
          ),
        ),
        _note(
            cls == null
                ? context.tr(
                    pl: 'Bez limitu czasu na powietrzu.',
                    en: 'No exposure limit.')
                : '${cls.desc(en: _en)} · '
                    '${context.tr(pl: 'limit z tabeli', en: 'table limit')} '
                    '${formatSpan(Duration(minutes: tableLimit!))}',
            key: const ValueKey('pp-class-desc')),
        if (cls != null) ...[
          _chips([
            for (final s in ElectrodeSource.values)
              _choiceChip('pp-src-${s.name}', electrodeSourceText(s, en: _en),
                  i.source == s, () => _choose(PassPlanField.source, s.name)),
          ]),
          _field(
              PassPlanField.limit,
              context.tr(
                  pl: 'Limit z WPS / karty (opcjonalnie)',
                  en: 'Limit from WPS / data sheet (optional)'),
              unit: 'min',
              decimal: false,
              helper: context.tr(
                  pl: 'Puste — z tabeli. Krótszy zawsze ma pierwszeństwo; '
                      'dłuższy niż tabela tylko z potwierdzeniem niżej.',
                  en: 'Empty — from the table. A shorter one always takes '
                      'precedence; longer than the table only with the '
                      'confirmation below.')),
          if (_typedAboveTable(i, tableLimit!))
            SwitchListTile(
              key: const ValueKey('pp-limit-up'),
              contentPadding: EdgeInsets.zero,
              value: _choice(PassPlanField.limitUp) == '1',
              onChanged: (v) => _choose(PassPlanField.limitUp, v ? '1' : '0'),
              title: Text(
                  context.tr(
                      pl: 'WPS / karta producenta pozwala na dłużej '
                          '(potwierdzam)',
                      en: 'The WPS / manufacturer’s data sheet allows longer '
                          '(I confirm)'),
                  style: const TextStyle(fontSize: 13.5, color: kText)),
              subtitle: Text(
                  context.tr(
                      pl: 'Bez potwierdzenia liczę z tabeli: '
                          '${formatSpan(Duration(minutes: tableLimit))}.',
                      en: 'Without the confirmation the table is used: '
                          '${formatSpan(Duration(minutes: tableLimit))}.'),
                  style: const TextStyle(fontSize: 12, color: kTextMut)),
            ),
        ],
        if (i.rootsFirstAvailable) ...[
          _label(context.tr(pl: 'Kolejność pracy', en: 'Work order')),
          _chips([
            for (final o in WorkOrder.values)
              _choiceChip('pp-order-${o.name}', workOrderText(o, en: _en),
                  i.order == o, () => _choose(PassPlanField.order, o.name)),
          ]),
          _note(context.tr(
              pl: 'Złącze po złączu: elektrody leżą też w czasie grani TIG — '
                  'bierz mniej naraz. Najpierw granie: elektrody wyjmujesz '
                  'dopiero do wypełnienia.',
              en: 'Joint by joint: the electrodes are also out while you weld '
                  'the TIG root — take fewer at once. Roots first: take the '
                  'electrodes out only for the fill.')),
        ],
        _field(PassPlanField.shift, context.tr(pl: 'Zmiana', en: 'Shift'),
            unit: 'h'),
      ],
    );
  }

  // ── Sekcja: założenia ──────────────────────────────────────────────────

  String? _runOutHelper(PassPlanInput i, PassConsumable c) {
    if (!c.isElectrode) return null;
    final area = i.beadArea(c);
    if (!(area.isFinite && area > 0) || !i.stubMm.isFinite) return null;
    final row = electrodeRowFor(c, long: i.longElectrodes);
    final g = depositPerElectrodeG(row, i.stubMm);
    if (!(g > 0)) return null;
    final mm = g / kSteelGPerMm3 / area;
    final size = electrodeSizeText(row, en: _en);
    return context.tr(
        pl: '≈ ${mm.round()} mm ściegu z elektrody $size',
        en: '≈ ${mm.round()} mm of bead per $size electrode');
  }

  /// Opis pola współczynnika jarzenia łuku: co liczy się z jakiej wartości
  /// (kierunek ostrożny — patrz pass_plan_sources.dart).
  String _arcOnHelper(PassPlanInput i, QuoteProcess p) {
    final lo = ppNum(arcOnLowerBoundPct(p), en: _en);
    final hi = ppNum(arcOnUpperBoundPct(p), en: _en);
    final capped = i.arcOnCappedForTime(p);
    return context.tr(
        pl: 'TWI: $lo–$hi %. Czas złącza z wpisanego, najwyżej $hi %'
            '${capped ? ' (tu liczę $hi %)' : ''}; „ile naraz” z najwyżej '
            '$lo % — wolniejsze zużycie, mniej elektrod na powietrzu.',
        en: 'TWI: $lo–$hi %. Joint time from the typed value, at most $hi %'
            '${capped ? ' (using $hi % here)' : ''}; “at once” from at most '
            '$lo % — slower use, fewer electrodes out.');
  }

  Widget _assumptionsSection(PassPlanInput i) {
    return QuoteSection(
      title:
          context.tr(pl: 'Założenia do korekty', en: 'Adjustable assumptions'),
      subtitle: context.tr(
          pl: 'Przekroje ściegów są przyjęte w aplikacji — zmierz na pierwszym '
              'złączu, ile mm ściegu daje jedna elektroda, i popraw.',
          en: 'Bead areas are assumed in the app — measure on the first joint '
              'how many mm of bead one electrode gives, and correct them.'),
      trailing: TextButton(
        key: const ValueKey('pp-reset-assumptions'),
        style: TextButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
        onPressed: _resetAssumptions,
        child: Text(context.tr(pl: 'Domyślne', en: 'Defaults')),
      ),
      children: [
        for (final c in i.beadConsumables)
          _field(
              PassPlanField.bead(c),
              context.tr(
                  pl: 'Przekrój ściegu ${_cons(c)}',
                  en: 'Bead area ${_cons(c)}'),
              unit: 'mm²',
              helper: _runOutHelper(i, c)),
        for (final p in i.usedProcesses)
          _field(
              PassPlanField.arcOn(p),
              context.tr(
                  pl: 'Współczynnik jarzenia łuku ${p.code}',
                  en: 'Arc-on factor ${p.code}'),
              unit: '%',
              helper: _arcOnHelper(i, p)),
      ],
    );
  }

  // ── Wynik: jedno złącze ────────────────────────────────────────────────

  Widget _layerCard(PassLayerPlan l, PassPlanInput i) {
    final facts = [
      '${massText(l.depositG, en: _en)} '
          '${context.tr(pl: 'stopiwa', en: 'weld metal')}',
      layerQuantityText(l, en: _en),
      '${context.tr(pl: 'łuk', en: 'arc')} ${minutesText(l.arcMin)}',
      '${context.tr(pl: 'czas', en: 'time')} ${minutesText(l.workMin)}',
    ];
    return Container(
      key: ValueKey('pp-layer-${l.layer.name}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${layerName(l.layer, en: _en)} · '
                  '${layerConsumableText(l, i, en: _en)}',
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: kText),
                ),
              ),
              const SizedBox(width: 8),
              Text(passesText(l.passes, en: _en),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: kArc,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 4),
          Text(facts.join(' · '),
              style:
                  const TextStyle(fontSize: 13, color: kTextSec, height: 1.35)),
        ],
      ),
    );
  }

  Widget _jointResultSection(PassPlanResult r) {
    return QuoteSection(
      title: context.tr(pl: 'Plan na jedno złącze', en: 'Plan per joint'),
      subtitle: jointDescription(r.input, en: _en),
      children: [
        KeyedSubtree(
          key: const ValueKey('pp-passes'),
          child: Readout(
            label: context.tr(pl: 'Ściegi na złącze', en: 'Passes per joint'),
            value: '${r.passesPerJoint}',
            unit: context.tr(
                pl: 'czas złącza ${minutesText(r.workMinPerJoint)} · łuk '
                    '${minutesText(r.arcMinPerJoint)}',
                en: 'joint time ${minutesText(r.workMinPerJoint)} · arc '
                    '${minutesText(r.arcMinPerJoint)}'),
          ),
        ),
        for (final l in r.layers) _layerCard(l, r.input),
        const SizedBox(height: 6),
        _kv(context.tr(pl: 'Stopiwo na złącze', en: 'Weld metal per joint'),
            massText(r.depositGPerJoint, en: _en),
            key: const ValueKey('pp-joint-deposit')),
        if (r.hotNoRoom)
          _note(
              context.tr(
                  pl: 'Ścianka cienka — po grani nie ma miejsca na ścieg '
                      'gorący, od razu lico.',
                  en: 'Thin wall — no room for a hot pass after the root, cap '
                      'straight away.'),
              key: const ValueKey('pp-note-hot')),
        if (r.fillMerged)
          _note(
              context.tr(
                  pl: 'Resztka wypełnienia (mniej niż pół ściegu) doliczona do '
                      'lica.',
                  en: 'The fill remainder (less than half a bead) is added to '
                      'the cap.'),
              key: const ValueKey('pp-note-merged')),
        _note(context.tr(
            pl: 'Ilości i czasy w górę. Suma liczona z dokładnych ilości — '
                'niedokończona elektroda idzie na następną warstwę.',
            en: 'Quantities and times rounded up. Totals use exact amounts — '
                'an unfinished electrode carries on into the next layer.')),
      ],
    );
  }

  // ── Wynik: całość ──────────────────────────────────────────────────────

  Widget _jobSection(PassPlanResult r) {
    return QuoteSection(
      title: context.tr(
          pl: 'Na całość — ${jointsText(r.jointCount, en: false)}',
          en: 'Whole job — ${jointsText(r.jointCount, en: true)}'),
      subtitle: context.tr(
          pl: 'Zapas ${ppNum(r.input.reservePct, en: false)} % — w nawiasie.',
          en: 'Reserve ${ppNum(r.input.reservePct, en: true)} % — in brackets.'),
      children: [
        for (final s in r.supplies)
          _kv(supplyName(s, en: _en), supplyJobText(s, en: _en),
              key: ValueKey('pp-supply-${s.consumable.name}')),
        _kv(context.tr(pl: 'Stopiwo', en: 'Weld metal'),
            '${ppFixed(r.depositKgJob, 2, en: _en)} kg',
            key: const ValueKey('pp-job-deposit')),
        _kv(context.tr(pl: 'Czas łuku', en: 'Arc time'),
            minutesText(r.arcMinJob),
            key: const ValueKey('pp-job-arc')),
        _kv(context.tr(pl: 'Czas pracy', en: 'Working time'),
            minutesText(r.workMinJob),
            key: const ValueKey('pp-job-time'), strong: true),
      ],
    );
  }

  // ── Wynik: weź z suszarki ──────────────────────────────────────────────

  Widget _takeSection(ExposurePlan e) {
    return QuoteSection(
      title: context.tr(pl: 'Weź z suszarki', en: 'Take from the oven'),
      subtitle: e.hasLimit
          ? '${electrodeClassText(e.electrodeClass, en: _en)} · '
              '${electrodeSourceText(e.source, en: _en)}'
              '${e.limitFromTable ? '' : context.tr(pl: ' · limit z WPS', en: ' · WPS limit')}'
          : electrodeClassText(e.electrodeClass, en: _en),
      children: [
        KeyedSubtree(
          key: const ValueKey('pp-take'),
          child: Readout(
            label: context.tr(pl: 'Naraz najwyżej', en: 'At most at once'),
            value: '${e.totalTakeNow}',
            unit: context.tr(pl: 'szt. elektrod', en: 'electrodes'),
            hot: true,
          ),
        ),
        const SizedBox(height: 8),
        for (final t in e.takes)
          _kv(electrodeSizeText(t.electrode, en: _en),
              piecesText(t.takeNow, en: _en),
              key: ValueKey('pp-take-${t.electrode.diameterMm}'), strong: true),
        const SizedBox(height: 4),
        if (e.limitRaiseIgnored)
          KeyedSubtree(
            key: const ValueKey('pp-limit-ignored'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: exposureLimitNoteText(e, en: _en)!,
            ),
          ),
        if (e.limitRaiseConfirmed)
          KeyedSubtree(
            key: const ValueKey('pp-limit-confirmed'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.verified_outlined,
              text: exposureLimitNoteText(e, en: _en)!,
            ),
          ),
        if (exposureBelowOneText(e, en: _en) case final text?)
          KeyedSubtree(
            key: const ValueKey('pp-below-one'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.warning_amber_outlined,
              text: text,
            ),
          ),
        KeyedSubtree(
          key: const ValueKey('pp-exposure-rule'),
          child: QuoteNotice(
            color: e.hasLimit ? kArc : kTextSec,
            icon: e.hasLimit ? Icons.hourglass_bottom : Icons.info_outline,
            text: exposureRuleText(e, en: _en),
          ),
        ),
        if (e.hasLimit)
          _kv(context.tr(pl: 'Porcje', en: 'Batches'),
              exposurePortionsText(e, en: _en),
              key: const ValueKey('pp-portions')),
      ],
    );
  }

  // ── Źródła ─────────────────────────────────────────────────────────────

  Widget _sourcesSection() {
    return QuoteSection(
      key: const ValueKey('pp-sources'),
      title:
          context.tr(pl: 'Źródła i założenia', en: 'Sources and assumptions'),
      children: [
        for (final (n, s) in kPassPlanSources.indexed) ...[
          if (n > 0) const Divider(height: 16, color: kBorder),
          Text(s.text(en: _en),
              key: ValueKey('pp-source-${s.id}'),
              style:
                  const TextStyle(fontSize: 12.5, color: kText, height: 1.4)),
        ],
        _note(context.tr(
            pl: 'Karta: $kCardElectrodeName.',
            en: 'Data sheet: $kCardElectrodeName.')),
      ],
    );
  }
}
