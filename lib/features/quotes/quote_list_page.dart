// Wyceny spawalnicze — lista ofert: status, klient, kwota; nowa wycena,
// duplikat („jak poprzednio"), kosz z przywracaniem, „Moje stawki i firma".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../database/weld_quote_dao.dart';
import '../../domain/quotes/quote_calculator.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../services/quote_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/help_button.dart';
import 'quote_edit_page.dart';
import 'quote_help.dart';
import 'quote_settings_page.dart';

class QuoteListPage extends StatefulWidget {
  final WeldQuoteDao? dao;
  final QuoteSettingsStore store;

  const QuoteListPage({
    super.key,
    this.dao,
    this.store = const QuoteSettingsStore(),
  });

  @override
  State<QuoteListPage> createState() => _QuoteListPageState();
}

class _QuoteListPageState extends State<QuoteListPage> {
  late final WeldQuoteDao _dao = widget.dao ?? WeldQuoteDao();
  final _search = TextEditingController();
  List<WeldQuote> _all = const [];
  QuoteSettings _settings = const QuoteSettings();
  QuoteStatus? _filter;
  bool _trash = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var failed = false;
    List<WeldQuote> all = const [];
    try {
      _settings = await widget.store.load();
      all = await _dao.listAll(onlyDeleted: _trash);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _all = all;
      _failed = failed;
      _loading = false;
    });
  }

  List<WeldQuote> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _all.where((w) {
      if (_filter != null && w.status != _filter) return false;
      if (q.isEmpty) return true;
      final hay =
          [w.number, w.title, w.client, w.notes].join(' ').toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList();
  }

  Future<void> _open(WeldQuote q, {int tab = 1, bool isNew = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuoteEditPage(
          quote: q,
          settings: _settings,
          initialTab: tab,
          dao: _dao,
          isNew: isNew),
    ));
    await _load();
  }

  Future<void> _new() async {
    final now = DateTime.now();
    String number;
    try {
      number = await _dao.nextNumber(now);
    } catch (_) {
      number = '';
    }
    final s = _settings;
    final q = WeldQuote(
      id: const Uuid().v4(),
      number: number,
      material: s.material,
      scheme: s.scheme,
      site: s.site,
      purge: s.material.purgeByDefault,
      validityDays: s.validityDays,
      rates: s.ratesFor(s.material),
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
    );
    if (!mounted) return;
    await _open(q, isNew: true);
  }

  Future<void> _duplicate(WeldQuote q) async {
    final copy = await _dao.duplicate(q,
        titleSuffix: context.tr(pl: '(kopia)', en: '(copy)'));
    await _load();
    if (!mounted) return;
    await _open(copy, tab: 0);
  }

  Future<void> _delete(WeldQuote q) async {
    await _dao.softDelete(q.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Wycena przeniesiona do kosza.',
            en: 'Quote moved to the bin.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () async {
            await _dao.restore(q.id);
            await _load();
          },
        ),
      ));
  }

  Future<void> _restore(WeldQuote q) async {
    await _dao.restore(q.id);
    await _load();
  }

  Future<void> _openSettings() async {
    final s = await Navigator.of(context).push<QuoteSettings>(
      MaterialPageRoute(
          builder: (_) =>
              QuoteSettingsPage(settings: _settings, store: widget.store)),
    );
    if (s != null) setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final visible = _visible;
    final accepted = _all.where((q) => q.status == QuoteStatus.accepted);
    final acceptedNet =
        accepted.fold<int>(0, (s, q) => s + computeQuote(q).netGrosze);
    return Scaffold(
      appBar: AppBar(
        title: Text(_trash
            ? context.tr(pl: 'Kosz wycen', en: 'Quote bin')
            : context.tr(pl: 'Wyceny', en: 'Quotes')),
        actions: [
          HelpButton(help: kHelpQuotes),
          IconButton(
            key: const ValueKey('quote-settings'),
            tooltip: context.tr(
                pl: 'Moje stawki i firma', en: 'My rates and company'),
            icon: const Icon(Icons.tune),
            onPressed: _openSettings,
          ),
          IconButton(
            key: const ValueKey('quote-trash'),
            tooltip: _trash
                ? context.tr(pl: 'Wróć do wycen', en: 'Back to quotes')
                : context.tr(pl: 'Kosz', en: 'Bin'),
            icon: Icon(_trash ? Icons.list_alt : Icons.delete_outline),
            onPressed: () {
              setState(() {
                _trash = !_trash;
                _loading = true;
              });
              unawaited(_load());
            },
          ),
        ],
      ),
      floatingActionButton: _trash
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('new-quote'),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
              onPressed: _loading || _failed ? null : _new,
              icon: const Icon(Icons.add),
              label: Text(context.tr(pl: 'Nowa wycena', en: 'New quote'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (_failed)
                  Text(
                    context.tr(
                        pl: 'Nie udało się odczytać wycen z bazy.',
                        en: 'Could not read quotes from the database.'),
                    style: const TextStyle(color: kFail),
                  ),
                if (!_trash && _all.isEmpty && !_failed) ...[
                  const SizedBox(height: 12),
                  const Icon(Icons.request_quote_outlined,
                      size: 56, color: kTextMut),
                  const SizedBox(height: 12),
                  Text(
                    context.tr(
                        pl: 'Ile kosztuje ta robota?',
                        en: 'What does this job cost?'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      pl: 'Wpisz spoiny (DN, ścianka, liczba, pozycja), a aplikacja '
                          'policzy roboczogodziny, spoiwo, gaz, prąd i badania. '
                          'Dodaj swoje stawki, narzut i zysk — i wyślij klientowi '
                          'ofertę PDF.',
                      en: 'Enter the welds (DN, wall, count, position) and the app '
                          'works out man-hours, filler, gas, power and testing. Add '
                          'your rates, overhead and profit — and send the client a '
                          'PDF quote.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextSec, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  if (_settings.company.isEmpty)
                    OutlinedButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.tune),
                      label: Text(context.tr(
                          pl: 'Najpierw: moje stawki i dane firmy',
                          en: 'First: my rates and company details')),
                    ),
                ],
                if (_trash && _all.isEmpty)
                  Text(
                      context.tr(
                          pl: 'Kosz jest pusty.', en: 'The bin is empty.'),
                      style: const TextStyle(color: kTextSec)),
                if (!_trash && _all.isNotEmpty) ...[
                  if (accepted.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kPass.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: kPass.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.handshake_outlined, color: kPass),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr(
                                  pl: 'Przyjęte: ${accepted.length} · ${formatPln(acceptedNet)} netto',
                                  en: 'Accepted: ${accepted.length} · ${formatPln(acceptedNet)} net'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_all.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: context.tr(
                              pl: 'Szukaj: klient, numer, przedmiot…',
                              en: 'Search: client, number, subject…'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text(context.tr(pl: 'Wszystkie', en: 'All')),
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                        for (final s in QuoteStatus.values) ...[
                          const SizedBox(width: 6),
                          ChoiceChip(
                            key: ValueKey('filter-${s.code}'),
                            label: Text(en ? s.labelEn : s.labelPl),
                            selected: _filter == s,
                            onSelected: (_) => setState(
                                () => _filter = _filter == s ? null : s),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final q in visible)
                  _QuoteCard(
                    key: ValueKey('quote-${q.id}'),
                    quote: q,
                    trash: _trash,
                    onOpen: () => _open(q, tab: 3),
                    onDuplicate: () => _duplicate(q),
                    onDelete: () => _delete(q),
                    onRestore: () => _restore(q),
                  ),
              ],
            ),
    );
  }
}

Color _statusColor(QuoteStatus s) => switch (s) {
      QuoteStatus.draft => kTextMut,
      QuoteStatus.sent => const Color(0xFF4A9EFF),
      QuoteStatus.accepted => kPass,
      QuoteStatus.rejected => kFail,
    };

class _QuoteCard extends StatelessWidget {
  final WeldQuote quote;
  final bool trash;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  const _QuoteCard({
    super.key,
    required this.quote,
    required this.trash,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final r = computeQuote(quote);
    final d = DateTime.fromMillisecondsSinceEpoch(quote.updatedAt);
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(d.day)}.${two(d.month)}.${d.year}';
    final color = _statusColor(quote.status);
    // Ink zamiast dekoracji Containera — fala dotknięcia ma być widoczna.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Ink(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: InkWell(
          onTap: trash ? null : onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              quote.number.isEmpty ? '—' : quote.number,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextMut,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              en ? quote.status.labelEn : quote.status.labelPl,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        quote.title.trim().isEmpty
                            ? context.tr(
                                pl: 'Wycena bez nazwy', en: 'Untitled quote')
                            : quote.title.trim(),
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                      if (quote.client.trim().isNotEmpty)
                        Text(quote.client.trim(),
                            style:
                                const TextStyle(fontSize: 13, color: kTextSec)),
                      const SizedBox(height: 6),
                      Text(
                        '${formatPln(r.netGrosze)} ${context.tr(pl: 'netto', en: 'net')}'
                        '  ·  ${r.weldCount} ${context.tr(pl: 'spoin', en: 'welds')}'
                        '  ·  $date',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kText,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (trash)
                  TextButton(
                    onPressed: onRestore,
                    child: Text(context.tr(pl: 'Przywróć', en: 'Restore')),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: context.tr(pl: 'Więcej', en: 'More'),
                    onSelected: (v) => switch (v) {
                      'dup' => onDuplicate(),
                      'del' => onDelete(),
                      _ => onOpen(),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'open',
                          child: Text(context.tr(pl: 'Otwórz', en: 'Open'))),
                      PopupMenuItem(
                          value: 'dup',
                          child: Text(context.tr(
                              pl: 'Duplikuj (nowa oferta)',
                              en: 'Duplicate (new quote)'))),
                      PopupMenuItem(
                          value: 'del',
                          child: Text(
                              context.tr(pl: 'Do kosza', en: 'Move to bin'))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
