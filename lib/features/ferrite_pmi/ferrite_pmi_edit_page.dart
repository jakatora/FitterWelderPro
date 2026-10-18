// Edycja protokołu „Ferryt i PMI”: część „Ferryt” (wymagany zakres ze
// specyfikacji albo preset typowy, jednostka ferrytomierza, reguła oceny,
// odczyty w wielu miejscach) i część „PMI (XRF)” (wymagany gatunek i norma,
// odczyty pierwiastków z niepewnością przyrządu). Zapis przy każdej zmianie.
//
// Logika werdyktów: lib/domain/ferrite_pmi/ (testy w test/domain/ferrite_pmi).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/ferrite_pmi/ferrite.dart';
import '../../domain/ferrite_pmi/ferrite_pmi_protocol.dart';
import '../../domain/ferrite_pmi/ferrite_pmi_sources.dart';
import '../../domain/ferrite_pmi/ferrite_pmi_text.dart';
import '../../domain/ferrite_pmi/pmi.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/number_field.dart';
import '../quotes/quote_widgets.dart' show FieldPair, QuoteNotice, QuoteSection;
import 'ferrite_pmi_page.dart' show ferriteVerdictColor, pmiVerdictColor;
import 'ferrite_pmi_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef FerritePmiShareText = Future<void> Function(String text, String subject);

Future<void> ferritePmiDefaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

class FerritePmiEditPage extends StatefulWidget {
  const FerritePmiEditPage({
    super.key,
    required this.initial,
    this.store = const FerritePmiStore(),
    this.now = DateTime.now,
    this.shareText = ferritePmiDefaultShareText,
  });

  final FerritePmiProtocol initial;
  final FerritePmiStore store;
  final DateTime Function() now;
  final FerritePmiShareText shareText;

  @override
  State<FerritePmiEditPage> createState() => _FerritePmiEditPageState();
}

enum _Part { ferrite, pmi }

class _FerritePmiEditPageState extends State<FerritePmiEditPage> {
  late FerritePmiProtocol _p = widget.initial;
  _Part _part = _Part.ferrite;
  int _seq = 0;

  late final _title = TextEditingController(text: _p.title);
  late final _inspector = TextEditingController(text: _p.inspector);
  late final _instrument = TextEditingController(text: _p.instrument);
  late final _notes = TextEditingController(text: _p.notes);
  late final _min = TextEditingController(text: _p.customMin);
  late final _max = TextEditingController(text: _p.customMax);
  late final _count = TextEditingController(text: _p.minCount);

  final Map<String, TextEditingController> _siteLabel = {};
  final Map<String, TextEditingController> _siteInput = {};
  final Map<String, String?> _siteInputError = {};
  final Map<String, TextEditingController> _pmiLabel = {};
  final Map<String, Map<PmiElement, TextEditingController>> _pmiR = {};
  final Map<String, Map<PmiElement, TextEditingController>> _pmiU = {};

  bool get _en => context.language == AppLanguage.en;

  TextEditingController _ctl(
          Map<String, TextEditingController> m, String id, String text) =>
      m.putIfAbsent(id, () => TextEditingController(text: text));

  TextEditingController _el(Map<String, Map<PmiElement, TextEditingController>> m,
          String id, PmiElement e, String text) =>
      m
          .putIfAbsent(id, () => {})
          .putIfAbsent(e, () => TextEditingController(text: text));

  @override
  void dispose() {
    for (final c in [_title, _inspector, _instrument, _notes, _min, _max, _count]) {
      c.dispose();
    }
    for (final m in [_siteLabel, _siteInput, _pmiLabel]) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final m in [_pmiR, _pmiU]) {
      for (final inner in m.values) {
        for (final c in inner.values) {
          c.dispose();
        }
      }
    }
    super.dispose();
  }

  // ── Zmiany i zapis ─────────────────────────────────────────────────────

  void _set(FerritePmiProtocol Function(FerritePmiProtocol p) change) {
    setState(() => _p = change(_p)
        .copyWith(updatedAt: widget.now().millisecondsSinceEpoch));
    final snapshot = _p;
    unawaited(widget.store.upsert(snapshot).catchError((Object e) {
      debugPrint('[ferrite_pmi] save failed: $e');
      _reportSaveFailure(full: e is FerritePmiStoreFull);
    }));
  }

  bool _saveFailureShown = false;

  /// Raz na ekran: protokół, który się nie zapisuje, nie może tego robić po
  /// cichu.
  void _reportSaveFailure({bool full = false}) {
    if (!mounted || _saveFailureShown) return;
    _saveFailureShown = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: ValueKey(full ? 'fp-store-full' : 'fp-save-failed'),
      content: Text(full
          ? context.tr(
              pl: 'Historia pełna (${FerritePmiStore.maxEntries} protokołów) '
                  '— ten protokół NIE jest zapisany. Udostępnij go i usuń '
                  'stare protokoły z historii.',
              en: 'History full (${FerritePmiStore.maxEntries} records) — '
                  'this record is NOT saved. Share it and delete old records '
                  'from the history.')
          : context.tr(
              pl: 'Nie udało się zapisać protokołu w telefonie — udostępnij '
                  'go, żeby nie przepadł.',
              en: 'Could not save the record on this phone — share it so it '
                  'is not lost.')),
    ));
  }

  String _newId(String prefix) =>
      '${_p.id}-$prefix${widget.now().microsecondsSinceEpoch}-${_seq++}';

  void _updateSite(String id, FerriteSite Function(FerriteSite s) f) =>
      _set((p) => p.copyWith(sites: [
            for (final s in p.sites) s.id == id ? f(s) : s,
          ]));

  void _updatePmi(String id, PmiItem Function(PmiItem i) f) =>
      _set((p) => p.copyWith(pmi: [
            for (final i in p.pmi) i.id == id ? f(i) : i,
          ]));

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _share() async {
    final en = _en;
    try {
      await widget.shareText(
          ferritePmiProtocolText(_p, en: en, now: widget.now()),
          ferritePmiSubject(en: en));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się udostępnić: $e', en: 'Sharing failed: $e'))));
    }
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_p.date) ?? widget.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: widget.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    _set((p) => p.copyWith(date: ferritePmiDate(picked)));
  }

  // ── Widżety pomocnicze ─────────────────────────────────────────────────

  Widget _caption(String text, {Key? key, Color color = kTextMut}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: color, height: 1.35)),
      );

  Widget _chips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required String Function(T) keyOf,
    required ValueChanged<T> onSelected,
  }) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final v in values)
            ChoiceChip(
              key: ValueKey(keyOf(v)),
              label: Text(label(v)),
              selected: v == selected,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onSelected(v),
            ),
        ],
      );

  InputDecoration _dec(String label, {String? suffix, String? error}) =>
      InputDecoration(
        labelText: label,
        suffixText: suffix,
        errorText: error,
        errorMaxLines: 3,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _pickerTile({
    required Key key,
    required VoidCallback onTap,
    required List<Widget> children,
  }) =>
      Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                  const Icon(Icons.expand_more, color: kTextSec),
                ],
              ),
            ),
          ),
        ),
      );

  // ── Ekran ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Ferryt i PMI', en: 'Ferrite and PMI')),
        actions: [
          IconButton(
            key: const ValueKey('fp-share-bar'),
            tooltip: context.tr(pl: 'Udostępnij tekst', en: 'Share text'),
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('fp-edit-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _header(),
          SegmentedButton<_Part>(
            key: const ValueKey('fp-part'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, kMinTapTarget)),
            ),
            segments: [
              ButtonSegment(
                value: _Part.ferrite,
                label: Text(context.tr(pl: 'Ferryt', en: 'Ferrite'),
                    key: const ValueKey('fp-part-ferrite')),
              ),
              ButtonSegment(
                value: _Part.pmi,
                label: Text('PMI (XRF)', key: const ValueKey('fp-part-pmi')),
              ),
            ],
            selected: {_part},
            onSelectionChanged: (s) => setState(() => _part = s.first),
          ),
          const SizedBox(height: 12),
          if (_part == _Part.ferrite) ..._ferrite() else ..._pmi(),
          _notesSection(),
          OutlinedButton.icon(
            key: const ValueKey('fp-share'),
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
            label: Text(context.tr(
                pl: 'Udostępnij protokół (tekst)',
                en: 'Share the record (text)')),
          ),
          const SizedBox(height: 12),
          _sourcesSection(),
          QuoteNotice(
            key: const ValueKey('fp-disclaimer'),
            icon: Icons.gavel_outlined,
            text: ferritePmiDisclaimer(en: _en),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return QuoteSection(
      title: context.tr(pl: 'Protokół', en: 'Record'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${context.tr(pl: 'Data', en: 'Date')}: ${_p.date}',
                style: const TextStyle(color: kText, fontSize: 14),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('fp-date'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(context.tr(pl: 'Zmień', en: 'Change')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('fp-title'),
          controller: _title,
          onChanged: (v) => _set((p) => p.copyWith(title: v)),
          decoration: _dec(context.tr(
              pl: 'Obiekt / linia / nr spoiny', en: 'Item / line / weld no.')),
        ),
        const SizedBox(height: 10),
        FieldPair(
          left: TextField(
            key: const ValueKey('fp-inspector'),
            controller: _inspector,
            onChanged: (v) => _set((p) => p.copyWith(inspector: v)),
            decoration: _dec(context.tr(pl: 'Wykonał', en: 'Inspector')),
          ),
          right: TextField(
            key: const ValueKey('fp-instrument'),
            controller: _instrument,
            onChanged: (v) => _set((p) => p.copyWith(instrument: v)),
            decoration: _dec(context.tr(
                pl: 'Przyrząd (model, kalibracja)',
                en: 'Instrument (model, calibration)')),
          ),
        ),
      ],
    );
  }

  Widget _notesSection() {
    return QuoteSection(
      title: context.tr(pl: 'Uwagi', en: 'Notes'),
      children: [
        TextField(
          key: const ValueKey('fp-notes'),
          controller: _notes,
          minLines: 1,
          maxLines: 5,
          onChanged: (v) => _set((p) => p.copyWith(notes: v)),
          decoration: _dec(context.tr(pl: 'Uwagi', en: 'Notes')),
        ),
      ],
    );
  }

  Widget _sourcesSection() {
    return QuoteSection(
      title: context.tr(pl: 'Źródła i wartości', en: 'Sources and values'),
      children: [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('fp-sources'),
            tilePadding: EdgeInsets.zero,
            minTileHeight: kMinTapTarget,
            title: Text(
                context.tr(pl: 'Pokaż źródła', en: 'Show sources'),
                style: const TextStyle(fontSize: 14, color: kText)),
            children: [
              for (final s in kFerritePmiSources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• ${s.label(en: _en)}',
                      style: const TextStyle(
                          fontSize: 12, color: kTextSec, height: 1.35)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // FERRYT
  // ══════════════════════════════════════════════════════════════════════

  String _groupTitle(FerritePresetGroup g) => switch (g) {
        FerritePresetGroup.duplex => context.tr(
            pl: 'Duplex / super duplex', en: 'Duplex / super duplex'),
        FerritePresetGroup.austenitic => context.tr(
            pl: 'Spoiny austenityczne', en: 'Austenitic welds'),
        FerritePresetGroup.lowFerrite => context.tr(
            pl: 'Niski ferryt (usługi specjalne)',
            en: 'Low ferrite (special services)'),
      };

  Future<void> _pickPreset() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        Widget tile(String id, String title, String subtitle) => ListTile(
              key: ValueKey('fp-preset-${id.isEmpty ? 'custom' : id}'),
              selected: id == _p.presetId,
              selectedColor: kArc,
              minVerticalPadding: 10,
              title: Text(title),
              subtitle: Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: kTextMut)),
              onTap: () => Navigator.of(ctx).pop(id),
            );
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                      context.tr(
                          pl: 'Wymagany zakres ferrytu',
                          en: 'Required ferrite range'),
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                tile(
                  '',
                  context.tr(
                      pl: 'Ze specyfikacji projektu (wpisz)',
                      en: 'From the project specification (enter)'),
                  context.tr(
                      pl: 'Min–max i jednostka dokładnie jak w specyfikacji',
                      en: 'Min–max and unit exactly as in the specification'),
                ),
                for (final g in FerritePresetGroup.values)
                  if (kFerritePresets.any((p) => p.group == g)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                      child: Text(
                          '${_groupTitle(g).toUpperCase()} — '
                          '${context.tr(pl: 'TYPOWE', en: 'TYPICAL')}',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: kTextSec)),
                    ),
                    for (final p in kFerritePresets)
                      if (p.group == g)
                        tile(
                          p.id,
                          '${p.requirement.text(en: _en)} — ${p.title(en: _en)}',
                          p.source(en: _en),
                        ),
                  ],
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    _set((p) => p.copyWith(presetId: picked));
  }

  List<Widget> _ferrite() {
    final req = _p.requirement;
    final preset = _p.preset;
    final results = _p.evaluateFerrite();
    final unknownPreset = _p.presetId.isNotEmpty && preset == null;
    final customInvalid =
        _p.presetId.isEmpty && req != null && !req.isValid;
    final mismatch = req != null && req.isValid && req.unit != _p.readingUnit;
    final overall = _p.ferriteVerdict;

    return [
      QuoteSection(
        title: context.tr(
            pl: 'Wymagany zakres (specyfikacja)',
            en: 'Required range (specification)'),
        children: [
          _pickerTile(
            key: const ValueKey('fp-preset-picker'),
            onTap: _pickPreset,
            children: [
              Text(
                unknownPreset
                    ? context.tr(
                        pl: 'Nieznany preset „${_p.presetId}”',
                        en: 'Unknown preset “${_p.presetId}”')
                    : preset == null
                        ? context.tr(
                            pl: 'Ze specyfikacji projektu',
                            en: 'From the project specification')
                        : preset.title(en: _en),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: kText),
              ),
              if (req != null && req.isValid)
                Text(req.text(en: _en),
                    key: const ValueKey('fp-req-text'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: kArc)),
              if (preset != null)
                Text(preset.source(en: _en),
                    style: const TextStyle(fontSize: 12, color: kTextMut)),
            ],
          ),
          if (preset != null) ...[
            const SizedBox(height: 8),
            QuoteNotice(
              key: const ValueKey('fp-preset-typical'),
              icon: Icons.info_outline,
              text: [
                context.tr(
                    pl: 'TYPOWE — decyduje specyfikacja projektu.',
                    en: 'TYPICAL — the project specification governs.'),
                if (preset.note(en: _en).isNotEmpty) preset.note(en: _en),
                '${context.tr(pl: 'Dotyczy', en: 'Applies to')}: '
                    '${[for (final l in FerriteLocation.values) if (preset.appliesTo.contains(l)) l.label(en: _en)].join(', ')}.',
              ].join(' '),
            ),
          ],
          if (_p.presetId.isEmpty) ...[
            const SizedBox(height: 12),
            FieldPair(
              left: TextField(
                key: const ValueKey('fp-req-min'),
                controller: _min,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                onChanged: (v) => _set((p) => p.copyWith(customMin: v)),
                decoration: _dec('Min', suffix: _p.customUnit.symbol),
              ),
              right: TextField(
                key: const ValueKey('fp-req-max'),
                controller: _max,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                onChanged: (v) => _set((p) => p.copyWith(customMax: v)),
                decoration: _dec('Max', suffix: _p.customUnit.symbol),
              ),
            ),
            const SizedBox(height: 8),
            Text(context.tr(pl: 'Jednostka wymagania', en: 'Requirement unit'),
                style: const TextStyle(color: kTextSec, fontSize: 13)),
            const SizedBox(height: 4),
            _chips<FerriteUnit>(
              values: FerriteUnit.values,
              selected: _p.customUnit,
              label: (u) => u.label(en: _en),
              keyOf: (u) => 'fp-req-unit-${u.name}',
              onSelected: (u) => _set((p) => p.copyWith(customUnit: u)),
            ),
            if (customInvalid)
              _caption(
                  ferriteNoVerdictText(FerriteNoVerdict.invalidRequirement,
                      en: _en),
                  key: const ValueKey('fp-req-invalid'),
                  color: kFail),
          ],
        ],
      ),
      QuoteSection(
        title: context.tr(
            pl: 'Ferrytomierz i reguła oceny', en: 'Instrument and rule'),
        children: [
          Text(
              context.tr(
                  pl: 'Jednostka odczytów (wyświetlacz przyrządu)',
                  en: 'Reading unit (instrument display)'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 4),
          _chips<FerriteUnit>(
            values: FerriteUnit.values,
            selected: _p.readingUnit,
            label: (u) => u.label(en: _en),
            keyOf: (u) => 'fp-read-unit-${u.name}',
            onSelected: (u) => _set((p) => p.copyWith(readingUnit: u)),
          ),
          if (mismatch) ...[
            const SizedBox(height: 8),
            QuoteNotice(
              key: const ValueKey('fp-unit-mismatch'),
              color: kFail,
              icon: Icons.block,
              text: context.tr(
                  pl: 'BRAK WERDYKTU: odczyty w ${_p.readingUnit.symbol}, '
                      'wymaganie w ${req.unit.symbol}. FN to nie % ferrytu — '
                      'aplikacja nie przelicza. Ustaw przyrząd na jednostkę '
                      'ze specyfikacji albo zmierz metodą, którą wymaga '
                      'specyfikacja.',
                  en: 'NO VERDICT: readings in ${_p.readingUnit.symbol}, '
                      'requirement in ${req.unit.symbol}. FN is not % ferrite '
                      '— the app does not convert. Set the instrument to the '
                      'specification unit or measure by the method the '
                      'specification requires.'),
            ),
          ],
          _caption(ferriteFnPercentNote(en: _en),
              key: const ValueKey('fp-fn-note')),
          const SizedBox(height: 12),
          Text(context.tr(pl: 'Reguła oceny', en: 'Acceptance rule'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 4),
          _chips<FerriteRule>(
            values: FerriteRule.values,
            selected: _p.rule,
            label: (r) => ferriteRuleLabel(r, en: _en),
            keyOf: (r) => 'fp-rule-${r.name}',
            onSelected: (r) => _set((p) => p.copyWith(rule: r)),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('fp-min-count'),
            controller: _count,
            keyboardType: numberKeyboard(decimal: false),
            inputFormatters: numberInputFormatters(decimal: false),
            onChanged: (v) => _set((p) => p.copyWith(minCount: v)),
            decoration: _dec(
              _p.rule == FerriteRule.average
                  ? context.tr(
                      pl: 'N — średnia z min. N odczytów (ze specyfikacji)',
                      en: 'N — mean of at least N readings (from the spec)')
                  : context.tr(
                      pl: 'Min. odczytów na miejsce (puste = 1)',
                      en: 'Min. readings per location (empty = 1)'),
              error: ferriteEffectiveMinCount(_count.text,
                          rule: _p.rule, preset: preset) ==
                      null
                  ? ferriteNoVerdictText(FerriteNoVerdict.invalidCount,
                      en: _en)
                  : null,
            ),
          ),
          if (preset != null && preset.minReadings > 1)
            _caption(
                context.tr(
                    pl: 'Preset wymaga co najmniej ${preset.minReadings} '
                        'odczytów na miejsce — pole może to tylko podnieść.',
                    en: 'The preset requires at least ${preset.minReadings} '
                        'readings per location — the field can only raise '
                        'it.'),
                key: const ValueKey('fp-preset-min-readings'),
                color: kWarn),
          _caption(_p.rule == FerriteRule.average
              ? context.tr(
                  pl: 'Średnia ze wszystkich odczytów miejsca; mniej odczytów '
                      'niż N — brak werdyktu.',
                  en: 'Mean of all readings at the location; fewer readings '
                      'than N — no verdict.')
              : context.tr(
                  pl: 'Domyślna i ostrzejsza: każdy pojedynczy odczyt musi '
                      'mieścić się w zakresie; mniej odczytów niż wymagane — '
                      'brak werdyktu.',
                  en: 'Default and stricter: every single reading must be in '
                      'range; fewer readings than required — no verdict.')),
        ],
      ),
      QuoteSection(
        title: context.tr(pl: 'Odczyty', en: 'Readings'),
        subtitle: context.tr(
            pl: 'Odczyty porównywane tak, jak wpisano — bez zaokrąglania. '
                'Granica (równość) = w zakresie.',
            en: 'Readings compared exactly as entered — no rounding. '
                'Equal to a limit = in range.'),
        children: [
          for (final (i, r) in results.indexed) _siteCard(i, r, req),
          if (_p.sites.isEmpty)
            _caption(context.tr(
                pl: 'Brak miejsc — dodaj poniżej.',
                en: 'No locations — add one below.')),
          const SizedBox(height: 4),
          Text(context.tr(pl: 'Dodaj miejsce', en: 'Add location'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in FerriteLocation.values)
                ActionChip(
                  key: ValueKey('fp-add-site-${l.name}'),
                  avatar: const Icon(Icons.add, size: 18),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(l.label(en: _en)),
                  onPressed: () => _set((p) => p.copyWith(sites: [
                        ...p.sites,
                        FerriteSite(id: _newId('s'), location: l),
                      ])),
                ),
            ],
          ),
        ],
      ),
      QuoteSection(
        title: context.tr(pl: 'Wynik ferrytu', en: 'Ferrite result'),
        children: [
          KeyedSubtree(
            key: ValueKey('fp-ferrite-verdict-${overall.name}'),
            child: QuoteNotice(
              color: ferriteVerdictColor(overall),
              icon: switch (overall) {
                FerriteVerdict.pass => Icons.check_circle_outline,
                FerriteVerdict.fail => Icons.error_outline,
                FerriteVerdict.none => Icons.help_outline,
              },
              text: '${ferriteVerdictLabel(overall, en: _en)}\n'
                  '${_overallDetail(results, overall)}',
            ),
          ),
        ],
      ),
    ];
  }

  String _overallDetail(List<FerriteSiteResult> results, FerriteVerdict v) {
    final filled = results.where((r) => !r.site.isBlank).toList();
    final pass = filled.where((r) => r.verdict == FerriteVerdict.pass).length;
    final fail = filled.where((r) => r.verdict == FerriteVerdict.fail).length;
    final none = filled.length - pass - fail;
    if (filled.isEmpty) {
      return context.tr(
          pl: 'Wpisz odczyty co najmniej w jednym miejscu.',
          en: 'Enter readings at one location at least.');
    }
    return context.tr(
        pl: 'Miejsca: ${filled.length} · w zakresie: $pass · poza: $fail · '
            'bez werdyktu: $none. Zielony tylko, gdy każde miejsce jest '
            'w zakresie.',
        en: 'Locations: ${filled.length} · in range: $pass · out: $fail · '
            'no verdict: $none. Green only when every location is in range.');
  }

  void _addReading(FerriteSite site) {
    final input = _siteInput[site.id]!;
    final t = input.text.trim();
    if (t.isEmpty) return;
    if (parseFerriteReading(t, _p.readingUnit) == null) {
      setState(() => _siteInputError[site.id] = context.tr(
          pl: 'Nieczytelna liczba albo poza skalą (0–100 %)',
          en: 'Unreadable number or off the scale (0–100 %)'));
      return;
    }
    _siteInputError[site.id] = null;
    input.clear();
    _updateSite(site.id, (s) => s.copyWith(readings: [...s.readings, t]));
  }

  Future<void> _readingMenu(FerriteSite site, int j) async {
    final v = site.readings[j];
    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Odczyt $v', en: 'Reading $v')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('fp-reading-delete'),
            style: FilledButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr(pl: 'Usuń odczyt', en: 'Delete reading')),
          ),
        ],
      ),
    );
    if (del != true || !mounted) return;
    _updateSite(site.id, (s) {
      final list = [...s.readings];
      if (j < list.length && list[j] == v) list.removeAt(j);
      return s.copyWith(readings: list);
    });
  }

  Widget _siteCard(int i, FerriteSiteResult r, FerriteRequirement? req) {
    final site = r.site;
    final color = site.isBlank ? kBorder : ferriteVerdictColor(r.verdict);
    final label = _ctl(_siteLabel, site.id, site.label);
    final input = _ctl(_siteInput, site.id, '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: ValueKey('fp-site-$i'),
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${i + 1}. ${site.location.label(en: _en)}',
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: kText),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('fp-site-$i-del'),
                    tooltip:
                        context.tr(pl: 'Usuń miejsce', en: 'Remove location'),
                    icon: const Icon(Icons.delete_outline),
                    color: kTextSec,
                    onPressed: () => _set((p) => p.copyWith(sites: [
                          for (final s in p.sites)
                            if (s.id != site.id) s,
                        ])),
                  ),
                ],
              ),
              _chips<FerriteLocation>(
                values: FerriteLocation.values,
                selected: site.location,
                label: (l) => l.label(en: _en),
                keyOf: (l) => 'fp-site-$i-loc-${l.name}',
                onSelected: (l) =>
                    _updateSite(site.id, (s) => s.copyWith(location: l)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextField(
                  key: ValueKey('fp-site-$i-label'),
                  controller: label,
                  onChanged: (v) =>
                      _updateSite(site.id, (s) => s.copyWith(label: v)),
                  decoration: _dec(context.tr(
                      pl: 'Oznaczenie (np. spoina 12, lico)',
                      en: 'Designation (e.g. weld 12, cap)')),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('fp-site-$i-input'),
                      controller: input,
                      keyboardType: numberKeyboard(),
                      inputFormatters: numberInputFormatters(),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addReading(site),
                      onChanged: (_) {
                        if (_siteInputError[site.id] != null) {
                          setState(() => _siteInputError[site.id] = null);
                        }
                      },
                      decoration: _dec(
                        context.tr(pl: 'Odczyt', en: 'Reading'),
                        suffix: _p.readingUnit.symbol,
                        error: _siteInputError[site.id],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    key: ValueKey('fp-site-$i-add'),
                    tooltip: context.tr(pl: 'Dodaj odczyt', en: 'Add reading'),
                    constraints: const BoxConstraints(
                        minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                    icon: const Icon(Icons.add),
                    onPressed: () => _addReading(site),
                  ),
                ],
              ),
              if (site.readings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (j, raw) in site.readings.indexed)
                      _readingChip(i, j, raw, r, site),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              KeyedSubtree(
                key: ValueKey('fp-site-$i-verdict-${r.verdict.name}'),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    site.isBlank
                        ? context.tr(
                            pl: 'Brak odczytów', en: 'No readings yet')
                        : ferriteSiteSummary(r, req,
                            en: _en, readingUnit: _p.readingUnit),
                    key: ValueKey('fp-site-$i-status'),
                    style: TextStyle(
                        fontSize: 13,
                        color: site.isBlank ? kTextSec : color,
                        fontWeight: FontWeight.w700,
                        height: 1.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readingChip(
      int i, int j, String raw, FerriteSiteResult r, FerriteSite site) {
    final v = j < r.values.length ? r.values[j] : null;
    final status = j < r.statuses.length ? r.statuses[j] : null;
    final color = switch (status) {
      FerriteReadingStatus.inRange => kPass,
      FerriteReadingStatus.below || FerriteReadingStatus.above => kFail,
      FerriteReadingStatus.invalid => kWarn,
      null => kTextSec,
    };
    final mark = switch (status) {
      FerriteReadingStatus.below => ' ↓',
      FerriteReadingStatus.above => ' ↑',
      FerriteReadingStatus.invalid => ' ?',
      _ => '',
    };
    return ActionChip(
      key: ValueKey('fp-site-$i-r-$j'),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      side: BorderSide(color: color.withValues(alpha: 0.7)),
      label: Text(
        '${v == null ? raw : ferriteRawText(raw, en: _en)}$mark',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      onPressed: () => _readingMenu(site, j),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PMI
  // ══════════════════════════════════════════════════════════════════════

  String _familyTitle(PmiFamily f) => switch (f) {
        PmiFamily.austenitic => context.tr(
            pl: 'Austenityczne', en: 'Austenitic'),
        PmiFamily.duplex => context.tr(pl: 'Duplex', en: 'Duplex'),
        PmiFamily.crMo => context.tr(
            pl: 'Cr-Mo (rurociągi wysokotemperaturowe)',
            en: 'Cr-Mo (high-temperature piping)'),
      };

  Future<void> _pickGrade(PmiItem item) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                    context.tr(pl: 'Wymagany gatunek', en: 'Required grade'),
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final f in PmiFamily.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Text(_familyTitle(f).toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: kTextSec)),
                ),
                for (final g in kPmiGrades)
                  if (g.family == f)
                    ListTile(
                      key: ValueKey('fp-grade-${g.id}'),
                      selected: g.id == item.gradeId,
                      selectedColor: kArc,
                      minVerticalPadding: 10,
                      title: Text(g.title),
                      subtitle: Text(
                          g.specs.map((s) => s.standard).join(' · '),
                          style:
                              const TextStyle(fontSize: 12, color: kTextMut)),
                      onTap: () => Navigator.of(ctx).pop(g.id),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _updatePmi(item.id, (i) => i.copyWith(gradeId: picked, specKey: ''));
  }

  List<Widget> _pmi() {
    return [
      QuoteNotice(
        key: const ValueKey('fp-xrf-carbon'),
        color: kWarn,
        icon: Icons.warning_amber_outlined,
        text: pmiCarbonNote(en: _en),
      ),
      for (final (i, item) in _p.pmi.indexed) _pmiCard(i, item),
      if (_p.pmi.isEmpty)
        _caption(context.tr(
            pl: 'Brak pozycji — dodaj poniżej.',
            en: 'No items — add one below.')),
      OutlinedButton.icon(
        key: const ValueKey('fp-pmi-add'),
        onPressed: () => _set((p) =>
            p.copyWith(pmi: [...p.pmi, PmiItem(id: _newId('p'))])),
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Dodaj pozycję PMI', en: 'Add PMI item')),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _pmiCard(int i, PmiItem item) {
    final r = item.evaluate();
    final g = item.grade;
    final spec = item.spec;
    final label = _ctl(_pmiLabel, item.id, item.label);
    final near = pmiNearestText(item, en: _en);
    final checks = {for (final c in r.checks) c.element: c};
    return QuoteSection(
      key: ValueKey('fp-pmi-$i'),
      title: '${context.tr(pl: 'Pozycja', en: 'Item')} ${i + 1}',
      trailing: IconButton(
        key: ValueKey('fp-pmi-$i-del'),
        tooltip: context.tr(pl: 'Usuń pozycję', en: 'Remove item'),
        icon: const Icon(Icons.delete_outline),
        color: kTextSec,
        onPressed: () => _set((p) => p.copyWith(pmi: [
              for (final e in p.pmi)
                if (e.id != item.id) e,
            ])),
      ),
      children: [
        TextField(
          key: ValueKey('fp-pmi-$i-label'),
          controller: label,
          onChanged: (v) => _updatePmi(item.id, (e) => e.copyWith(label: v)),
          decoration: _dec(context.tr(
              pl: 'Element (np. rura poz. 3, wytop)',
              en: 'Item (e.g. pipe pos. 3, heat no.)')),
        ),
        const SizedBox(height: 10),
        _pickerTile(
          key: ValueKey('fp-pmi-$i-grade'),
          onTap: () => _pickGrade(item),
          children: [
            Text(
              g == null
                  ? (item.gradeId.isEmpty
                      ? context.tr(
                          pl: 'Wybierz wymagany gatunek',
                          en: 'Pick the required grade')
                      : context.tr(
                          pl: 'Nieznany gatunek „${item.gradeId}”',
                          en: 'Unknown grade “${item.gradeId}”'))
                  : g.title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: kText),
            ),
            if (spec != null)
              Text('${spec.designation} — ${spec.standard}',
                  style: const TextStyle(fontSize: 12, color: kTextMut)),
          ],
        ),
        if (g != null && g.specs.length > 1) ...[
          const SizedBox(height: 8),
          Text(context.tr(pl: 'Ocena wg normy', en: 'Judge per standard'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 4),
          _chips<String>(
            values: [for (final s in g.specs) s.key],
            selected: spec?.key ?? '',
            label: (k) => g.specByKey(k)!.standard,
            keyOf: (k) => 'fp-pmi-$i-spec-$k',
            onSelected: (k) =>
                _updatePmi(item.id, (e) => e.copyWith(specKey: k)),
          ),
        ],
        if (g != null && spec == null)
          _caption(
              context.tr(
                  pl: 'Zapisany wariant normy „${item.specKey}” nie istnieje — '
                      'wybierz normę.',
                  en: 'The saved standard variant “${item.specKey}” does not '
                      'exist — pick the standard.'),
              color: kFail),
        if (g != null && g.note(en: _en).isNotEmpty)
          _caption(g.note(en: _en), key: ValueKey('fp-pmi-$i-note')),
        if (spec != null) _caption(spec.source(en: _en)),
        const SizedBox(height: 10),
        for (final e in PmiElement.values) _elementRow(i, item, e, g, spec, checks[e]),
        const SizedBox(height: 4),
        KeyedSubtree(
          key: ValueKey('fp-pmi-$i-verdict-${r.verdict.name}'),
          child: QuoteNotice(
            color: pmiVerdictColor(r.verdict),
            icon: switch (r.verdict) {
              PmiVerdict.conforming ||
              PmiVerdict.conformingNoCarbon =>
                Icons.check_circle_outline,
              PmiVerdict.nonConforming => Icons.error_outline,
              _ => Icons.help_outline,
            },
            text: [
              pmiVerdictLabel(r.verdict, en: _en),
              if (r.reason != null) pmiNoVerdictText(r.reason!, en: _en),
              if (r.verdict == PmiVerdict.conformingNoCarbon)
                context.tr(
                    pl: 'O gatunku decyduje też C — potwierdź OES / '
                        'laboratorium, jeśli wymaga tego specyfikacja.',
                    en: 'Carbon also defines this grade — confirm by OES / '
                        'laboratory if the specification requires it.'),
              if (r.withStatus(PmiElementStatus.carbonDependent).isNotEmpty)
                context.tr(
                    pl: 'Minimum Ti zależy od C (XRF nie mierzy C) — '
                        'potrzebny OES.',
                    en: 'Ti minimum depends on C (XRF does not measure C) — '
                        'OES needed.'),
            ].join('\n'),
          ),
        ),
        if (near != null)
          _caption(near, key: ValueKey('fp-pmi-$i-nearest'), color: kTextSec),
      ],
    );
  }

  Widget _elementRow(int i, PmiItem item, PmiElement e, PmiGrade? g,
      PmiSpec? spec, PmiElementCheck? check) {
    // Wymagany: kluczowy albo z dolną granicą w wybranej normie.
    final key = g != null &&
        spec != null &&
        g.requiredIn(spec).contains(e);
    final control = g != null &&
        spec != null &&
        spec.ranges[e] == null &&
        g.controlElements.containsKey(e);
    final rc = _el(_pmiR, item.id, e, item.readings[e] ?? '');
    final uc = _el(_pmiU, item.id, e, item.uncertainty[e] ?? '');
    final ranges = <String>[];
    if (g != null) {
      for (final s in g.specs) {
        final range = s.ranges[e];
        final same = s == spec;
        if (range == null) continue;
        ranges.add('${same ? '▶ ' : ''}${s.standard}: ${range.text(en: _en)}');
      }
    }
    final (Color color, String status) = check == null
        ? (kTextSec, '')
        : (
            switch (check.status) {
              PmiElementStatus.inRange => kPass,
              PmiElementStatus.outOfRange => kFail,
              PmiElementStatus.notSpecified => kTextSec,
              _ => kWarn,
            },
            g == null
                ? pmiElementStatusLabel(check.status, en: _en)
                : pmiElementStatusText(check, grade: g, en: _en),
          );
    return Padding(
      key: ValueKey('fp-pmi-$i-${e.name}-row'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: e.symbol,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: kText, fontSize: 14)),
              if (key || control)
                TextSpan(
                    text: key
                        ? context.tr(pl: '  wymagany', en: '  required')
                        : context.tr(
                            pl: '  kontrolny (spoza składu)',
                            en: '  control (not in the grade)'),
                    style: const TextStyle(
                        color: kArc,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              if (ranges.isNotEmpty)
                TextSpan(
                    text: '\n${ranges.join('\n')}',
                    style: const TextStyle(fontSize: 12, color: kTextMut)),
            ]),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: ValueKey('fp-pmi-$i-${e.name}'),
                  controller: rc,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  onChanged: (v) => _updatePmi(item.id,
                      (it) => it.copyWith(readings: {...it.readings, e: v})),
                  decoration: _dec('${e.symbol} [%]'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey('fp-pmi-$i-${e.name}-u'),
                  controller: uc,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  onChanged: (v) => _updatePmi(
                      item.id,
                      (it) =>
                          it.copyWith(uncertainty: {...it.uncertainty, e: v})),
                  decoration: _dec('± u'),
                ),
              ),
            ],
          ),
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(status,
                  key: ValueKey('fp-pmi-$i-${e.name}-status'),
                  style: TextStyle(
                      color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
