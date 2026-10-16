// Edytor wyceny: zakładki Dane / Spoiny / Koszty / Wynik i pasek sumy na
// dole każdej zakładki. Zapis automatyczny (z opóźnieniem) — monter nie
// traci wyceny, gdy telefon zadzwoni w połowie.

import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../database/weld_quote_dao.dart';
import '../../domain/quotes/quote_calculator.dart';
import '../../domain/quotes/quote_process.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../services/quote_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/help_button.dart';
import '../../widgets/number_field.dart';
import 'quote_costs_tab.dart';
import 'quote_help.dart';
import 'quote_scope_tab.dart';
import 'quote_summary_tab.dart';
import 'quote_widgets.dart';

typedef QuoteChanged = void Function(WeldQuote q);

class QuoteEditPage extends StatefulWidget {
  final WeldQuote quote;
  final QuoteSettings settings;

  /// Zakładka na start (0 Dane, 1 Spoiny, 2 Koszty, 3 Wynik).
  final int initialTab;

  /// Do testów: wstrzyknięte DAO i opóźnienie zapisu.
  final WeldQuoteDao? dao;
  final Duration saveDelay;

  /// Wycena dopiero utworzona (jeszcze nie ma jej w bazie). Tylko taką
  /// wolno pominąć przy zapisie, gdy jest pusta — zapisanej wyceny, z której
  /// usunięto wszystko, nie wolno zostawić w bazie w starej postaci.
  final bool isNew;

  const QuoteEditPage({
    super.key,
    required this.quote,
    required this.settings,
    this.initialTab = 1,
    this.dao,
    this.saveDelay = const Duration(milliseconds: 600),
    this.isNew = false,
  });

  @override
  State<QuoteEditPage> createState() => _QuoteEditPageState();
}

class _QuoteEditPageState extends State<QuoteEditPage>
    with SingleTickerProviderStateMixin {
  late WeldQuote _q = widget.quote;
  late QuoteSettings _settings = widget.settings;
  late final WeldQuoteDao _dao = widget.dao ?? WeldQuoteDao();
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
  Timer? _saveTimer;
  bool _dirty = false;
  bool _saving = false;
  bool _saveFailed = false;
  late bool _persisted = !widget.isNew;

  /// Zapisy idą po kolei — dwa równoległe `save` nowej wyceny mogłyby
  /// wpaść na siebie między UPDATE a INSERT.
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Bez setState — element już schodzi ze sceny.
    if (_dirty) unawaited(_enqueueSave(silent: true));
    _tabs.dispose();
    super.dispose();
  }

  /// Pusta wycena (nic nie wpisano) nie zaśmieca listy.
  bool get _worthSaving =>
      _q.joints.isNotEmpty ||
      _q.extras.isNotEmpty ||
      _q.title.trim().isNotEmpty ||
      _q.client.trim().isNotEmpty;

  void _change(WeldQuote q) {
    setState(() {
      _q = q;
      _dirty = true;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(widget.saveDelay, () => unawaited(_saveNow()));
  }

  /// Zmiana liczona od AKTUALNEGO stanu (np. „Cofnij" z SnackBara, który
  /// trzyma stary obiekt wyceny).
  void _update(WeldQuote Function(WeldQuote current) f) => _change(f(_q));

  Future<void> _saveNow() => _enqueueSave(silent: false);

  Future<void> _enqueueSave({required bool silent}) {
    _saveTimer?.cancel();
    final next = _queue.then((_) => _doSave(silent: silent));
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _doSave({required bool silent}) async {
    if (!_dirty) return;
    if (!_persisted && !_worthSaving) return;
    _dirty = false;
    final snapshot = _q;
    if (!silent && mounted) setState(() => _saving = true);
    var failed = false;
    try {
      await _dao.save(snapshot);
      _persisted = true;
    } catch (_) {
      failed = true;
      _dirty = true;
    }
    if (silent || !mounted) return;
    setState(() {
      _saving = false;
      _saveFailed = failed;
    });
  }

  /// `true` = można wyjść. Gdy zapis się nie udał — pytamy, zamiast
  /// po cichu zgubić wycenę.
  Future<bool> _onWillPop() async {
    await _saveNow();
    if (!_saveFailed || !mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.tr(
            pl: 'Wycena nie została zapisana', en: 'The quote was not saved')),
        content: Text(context.tr(
            pl: 'Zapis do pamięci telefonu się nie udał. Wyjście teraz '
                'oznacza utratę ostatnich zmian.',
            en: 'Saving to the phone failed. Leaving now loses the latest '
                'changes.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(context.tr(pl: 'Zostań', en: 'Stay'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kFail),
              onPressed: () => Navigator.pop(d, true),
              child: Text(context.tr(pl: 'Wyjdź bez zapisu', en: 'Leave unsaved'))),
        ],
      ),
    );
    if (leave == true) _dirty = false;
    return leave == true;
  }

  void _settingsChanged(QuoteSettings s) => setState(() => _settings = s);

  @override
  Widget build(BuildContext context) {
    final result = computeQuote(_q);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _onWillPop();
        if (leave && context.mounted) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _q.title.trim().isEmpty
                    ? context.tr(pl: 'Wycena', en: 'Quote')
                    : _q.title.trim(),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  if (_q.number.isNotEmpty) _q.number,
                  if (_saveFailed)
                    context.tr(pl: 'nie zapisano!', en: 'not saved!')
                  else if (_saving)
                    context.tr(pl: 'zapisywanie…', en: 'saving…')
                  else if (!_persisted && !_worthSaving)
                    context.tr(
                        pl: 'dodaj spoinę, żeby zapisać',
                        en: 'add a weld to save'),
                ].join('  ·  '),
                style: TextStyle(
                    fontSize: 12,
                    color: _saveFailed ? kFail : kTextMut,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [HelpButton(help: kHelpQuotes)],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: false,
            tabs: [
              Tab(text: context.tr(pl: 'Dane', en: 'Details')),
              Tab(
                text:
                    '${context.tr(pl: 'Spoiny', en: 'Welds')}${_q.joints.isEmpty ? '' : ' (${_q.joints.length})'}',
              ),
              Tab(text: context.tr(pl: 'Koszty', en: 'Costs')),
              Tab(text: context.tr(pl: 'Wynik', en: 'Result')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _DetailsTab(quote: _q, settings: _settings, onChanged: _change),
            QuoteScopeTab(
              quote: _q,
              result: result,
              onChanged: _change,
              onUpdate: _update,
              onOpenDetails: () => _tabs.animateTo(0),
            ),
            QuoteCostsTab(
              quote: _q,
              settings: _settings,
              onChanged: _change,
              onSettingsChanged: _settingsChanged,
            ),
            QuoteSummaryTab(
              quote: _q,
              result: result,
              settings: _settings,
              onChanged: _change,
              onUpdate: _update,
              beforeExport: _saveNow,
            ),
          ],
        ),
        bottomNavigationBar: _tabs.index == 3
            ? null
            : _TotalBar(result: result, onTap: () => _tabs.animateTo(3)),
      ),
    );
  }
}

class _TotalBar extends StatelessWidget {
  final QuoteResult result;
  final VoidCallback onTap;
  const _TotalBar({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      child: InkWell(
        key: const ValueKey('quote-total-bar'),
        onTap: onTap,
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kBorder))),
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr(pl: 'RAZEM NETTO', en: 'TOTAL NET'),
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: kTextMut,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2),
                      ),
                      Text(
                        formatPln(result.netGrosze),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kArc,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${context.tr(pl: 'brutto', en: 'gross')} ${formatPln(result.grossGrosze)}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: kTextSec,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    Text(
                      '${formatQty(result.labourHours, decimals: 1)} h · ${formatQty(result.depositedKg, decimals: 2)} kg',
                      style: const TextStyle(fontSize: 12, color: kTextMut),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: kTextMut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Zakładka „Dane" ─────────────────────────────────────────────────────────

class _DetailsTab extends StatefulWidget {
  final WeldQuote quote;
  final QuoteSettings settings;
  final QuoteChanged onChanged;
  const _DetailsTab(
      {required this.quote, required this.settings, required this.onChanged});

  @override
  State<_DetailsTab> createState() => _DetailsTabState();
}

class _DetailsTabState extends State<_DetailsTab>
    with AutomaticKeepAliveClientMixin {
  late final _number = TextEditingController(text: widget.quote.number);
  late final _title = TextEditingController(text: widget.quote.title);
  late final _client = TextEditingController(text: widget.quote.client);
  late final _notes = TextEditingController(text: widget.quote.notes);
  late final _validity =
      TextEditingController(text: '${widget.quote.validityDays}');
  late final _crew = TextEditingController(text: '${widget.quote.crew}');

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final c in [_number, _title, _client, _notes, _validity, _crew]) {
      c.dispose();
    }
    super.dispose();
  }

  WeldQuote get q => widget.quote;

  Future<void> _material(QuoteMaterial m) async {
    if (m == q.material) return;
    // Ceny spoiw idą za materiałem (nierdzewka ≠ czarna); reszta stawek
    // zostaje taka, jak w tej wycenie. Jeżeli ceny w wycenie były
    // poprawiane ręcznie — najpierw pytamy, bo zostaną nadpisane.
    final standard = widget.settings.ratesFor(q.material).fillerPrices;
    final customized = !mapEquals(q.rates.fillerPrices, standard);
    if (customized) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(context.tr(
              pl: 'Zmienić materiał na: ${m.labelPl}?',
              en: 'Change the material to: ${m.labelEn}?')),
          content: Text(context.tr(
              pl: 'Ceny spoiw w tej wycenie były zmieniane ręcznie. Zostaną '
                  'zastąpione cenami dla nowego materiału.',
              en: 'Filler prices in this quote were changed by hand. They will '
                  'be replaced with the prices for the new material.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(context.tr(pl: 'Zmień', en: 'Change'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final prices = widget.settings.ratesFor(m).fillerPrices;
    widget.onChanged(widget.quote.copyWith(
      material: m,
      purge: m.purgeByDefault,
      rates: widget.quote.rates.copyWith(fillerPrices: prices),
    ));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Ceny spoiw i formowanie ustawione dla: ${m.labelPl}.',
            en: 'Filler prices and purge set for: ${m.labelEn}.')),
      ));
  }

  InputDecoration _dec(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final en = context.language == AppLanguage.en;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        QuoteSection(
          title: context.tr(pl: 'Oferta', en: 'Quote'),
          children: [
            TextField(
              key: const ValueKey('quote-title'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: _dec(context.tr(
                  pl: 'Przedmiot, np. „Prefabrykacja kolektora DN200"',
                  en: 'Subject, e.g. "DN200 header prefabrication"')),
              onChanged: (v) => widget.onChanged(q.copyWith(title: v)),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('quote-client'),
              controller: _client,
              textCapitalization: TextCapitalization.words,
              decoration:
                  _dec(context.tr(pl: 'Zamawiający (klient)', en: 'Client')),
              onChanged: (v) => widget.onChanged(q.copyWith(client: v)),
            ),
            const SizedBox(height: 10),
            FieldPair(
              left: TextField(
                controller: _number,
                decoration: _dec(context.tr(pl: 'Numer', en: 'Number')),
                onChanged: (v) =>
                    widget.onChanged(q.copyWith(number: v.trim())),
              ),
              right: TextField(
                controller: _validity,
                keyboardType: numberKeyboard(decimal: false),
                inputFormatters: numberInputFormatters(decimal: false),
                decoration:
                    _dec(context.tr(pl: 'Ważna (dni)', en: 'Valid (days)')),
                onChanged: (v) {
                  final d = int.tryParse(v.trim());
                  if (d != null && d > 0) {
                    widget.onChanged(q.copyWith(validityDays: d));
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in QuoteStatus.values)
                  ChoiceChip(
                    key: ValueKey('status-${s.code}'),
                    label: Text(en ? s.labelEn : s.labelPl),
                    selected: q.status == s,
                    onSelected: (_) => widget.onChanged(q.copyWith(status: s)),
                  ),
              ],
            ),
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Materiał', en: 'Material'),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in QuoteMaterial.values)
                  ChoiceChip(
                    key: ValueKey('material-${m.code}'),
                    label: Text(en ? m.labelEn : m.labelPl),
                    selected: q.material == m,
                    onSelected: (_) => _material(m),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              key: const ValueKey('quote-purge'),
              contentPadding: EdgeInsets.zero,
              value: q.purge,
              onChanged: (v) => widget.onChanged(q.copyWith(purge: v)),
              title: Text(context.tr(
                  pl: 'Formowanie grani gazem',
                  en: 'Root purging (backing gas)')),
              subtitle: Text(
                context.tr(
                    pl: 'Nierdzewka, duplex, P91 — przedmuch odcinka między '
                        'przegrodami i przepływ w czasie grani.',
                    en: 'Stainless, duplex, P91 — pre-purge between dams and '
                        'flow while the root is welded.'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
            ),
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Metoda spawania', en: 'Welding method'),
          subtitle: context.tr(
              pl: 'Dla wszystkich pozycji — pojedynczą pozycję można zmienić osobno.',
              en: 'For all items — a single item can be changed separately.'),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in kCommonSchemes)
                  ChoiceChip(
                    key: ValueKey('scheme-${s.code}'),
                    label: Text(s.label),
                    selected: q.scheme == s,
                    onSelected: (_) => widget.onChanged(q.copyWith(scheme: s)),
                  ),
              ],
            ),
            if (q.scheme.isCombo) ...[
              const SizedBox(height: 6),
              Text(
                context.tr(
                    pl: 'Grań (~3 mm od dna rowka) ${q.scheme.root!.label}, '
                        'wypełnienie i lico ${q.scheme.fill.label}.',
                    en: 'Root (~3 mm from the groove bottom) ${q.scheme.root!.label}, '
                        'fill and cap ${q.scheme.fill.label}.'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
            ],
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Warunki pracy', en: 'Working conditions'),
          children: [
            for (final s in QuoteSite.values)
              ListTile(
                key: ValueKey('site-${s.code}'),
                contentPadding: EdgeInsets.zero,
                selected: q.site == s,
                selectedColor: kArc,
                onTap: () => widget.onChanged(q.copyWith(site: s)),
                leading: Icon(q.site == s
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(en ? s.labelEn : s.labelPl),
                subtitle: Text(
                  context.tr(
                      pl: 'robocizna ×${numText(s.factor)}',
                      en: 'labour ×${numText(s.factor)}'),
                  style: const TextStyle(fontSize: 12, color: kTextMut),
                ),
              ),
            const SizedBox(height: 6),
            TextField(
              controller: _crew,
              keyboardType: numberKeyboard(decimal: false),
              inputFormatters: numberInputFormatters(decimal: false),
              decoration: _dec(
                context.tr(pl: 'Osób w brygadzie', en: 'Crew size'),
                helper: context.tr(
                    pl: 'Tylko do terminu realizacji (dni po 8 h).',
                    en: 'Only for the lead time (8-hour days).'),
              ),
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null && n > 0) widget.onChanged(q.copyWith(crew: n));
              },
            ),
          ],
        ),
        QuoteSection(
          title: context.tr(pl: 'Uwagi na ofercie', en: 'Notes on the quote'),
          children: [
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: _dec(context.tr(
                  pl: 'Np. materiał powierza zamawiający, rusztowania po stronie klienta',
                  en: 'E.g. material supplied by the client, scaffolding by the client')),
              onChanged: (v) => widget.onChanged(q.copyWith(notes: v)),
            ),
          ],
        ),
      ],
    );
  }
}
