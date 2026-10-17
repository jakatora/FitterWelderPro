// „Importuj spoiny" — pełnoekranowe okno z zakładki „Spoiny" wyceny: źródło
// (zapisany skan izometryku albo dziennik spoin) → wybór skanu albo
// projektu / pakietu → PODGLĄD zgrupowanych pozycji → „Dodaj do wyceny".
// Okno tylko zwraca pozycje; dodaje je zakładka (onUpdate, od aktualnej
// wyceny). Grupowanie i mapowanie: domain/quotes/quote_import.dart.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../database/iso_scan_dao.dart';
import '../../database/weld_journal_dao.dart';
import '../../domain/quotes/quote_import.dart';
import '../../domain/quotes/quote_labels.dart';
import '../../domain/quotes/weld_geometry.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../domain/weld_journal/weld_entry.dart';
import '../../i18n/app_language.dart';
import '../../services/iso_scanner_ai.dart';
import '../../services/scan_quote_import.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import 'quote_widgets.dart';

/// Otwiera import dla [quote]; zwraca pozycje do dodania albo null.
Future<List<QuoteJoint>?> showQuoteImport(
  BuildContext context, {
  required WeldQuote quote,
  IsoScanDao? scanDao,
  WeldJournalDao? journalDao,
}) =>
    Navigator.of(context).push<List<QuoteJoint>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => QuoteImportSheet(
          quote: quote, scanDao: scanDao, journalDao: journalDao),
    ));

enum _Stage { source, scans, journal, preview }

class _ScanItem {
  final IsoScanRecord record;
  final AiScanResult? scan;
  final String label;
  const _ScanItem(this.record, this.scan, this.label);
}

/// Wartość listy pakietów „wszystkie" (null w liście rozwijanej bywa
/// mylony z „nic nie wybrano").
const String _kAllPackages = '\u0000all';

class QuoteImportSheet extends StatefulWidget {
  /// Wycena, do której idą pozycje — warunki pracy (domyślna pozycja) i
  /// materiał (schedule w etykiecie rozmiaru).
  final WeldQuote quote;

  /// Do testów; domyślnie zwykłe DAO.
  final IsoScanDao? scanDao;
  final WeldJournalDao? journalDao;

  const QuoteImportSheet({
    super.key,
    required this.quote,
    this.scanDao,
    this.journalDao,
  });

  @override
  State<QuoteImportSheet> createState() => _QuoteImportSheetState();
}

class _QuoteImportSheetState extends State<QuoteImportSheet> {
  late final IsoScanDao _scanDao = widget.scanDao ?? IsoScanDao();
  late final WeldJournalDao _journalDao = widget.journalDao ?? WeldJournalDao();

  _Stage _stage = _Stage.source;
  bool _loading = false;
  String? _error;

  List<_ScanItem> _scans = const [];
  _ScanItem? _scan;

  List<WeldEntry> _journal = const [];
  String? _project;
  String? _package;
  bool _onlyOpen = false;

  QuoteImportPlan? _plan;
  String _label = '';
  Set<String> _selected = {};
  final Map<String, WeldPosition> _positions = {};

  WeldPosition get _defaultPosition => defaultImportPosition(widget.quote.site);

  bool get _stainless =>
      widget.quote.material == QuoteMaterial.stainless ||
      widget.quote.material == QuoteMaterial.duplex;

  bool get _en => context.language == AppLanguage.en;

  // ─── Źródła ───────────────────────────────────────────────────────────────

  Future<void> _openScans() async {
    setState(() {
      _stage = _Stage.scans;
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _scanDao.listRecent();
      if (!mounted) return;
      setState(() {
        _scans = [for (final r in rows) _scanItem(r)];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr(
            pl: 'Nie udało się odczytać zapisanych skanów.',
            en: 'Could not read the stored scans.');
      });
    }
  }

  _ScanItem _scanItem(IsoScanRecord r) {
    final env = r.envelope;
    AiScanResult? scan;
    if (env != null) {
      try {
        scan = AiScanResult.fromEnvelope(env);
      } catch (_) {
        // Uszkodzony odczyt — na liście, ale nie do otwarcia.
      }
    }
    final label =
        scan == null ? (r.name ?? '') : scanImportLabel(scan, fallbackName: r.name);
    return _ScanItem(r, scan, label);
  }

  void _pickScan(_ScanItem item) {
    final scan = item.scan;
    QuoteImportPlan? plan;
    if (scan != null) {
      try {
        plan = planQuoteImport(importWeldsFromScan(scan),
            defaultPosition: _defaultPosition, stainless: _stainless);
      } catch (_) {
        plan = null;
      }
    }
    if (plan == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Tego odczytu nie da się otworzyć.',
              en: 'This reading cannot be opened.')),
        ));
      return;
    }
    final label = item.label.isNotEmpty
        ? item.label
        : context.tr(
            pl: 'Skan ISO ${_date(item.record.createdAt)}',
            en: 'ISO scan ${_date(item.record.createdAt)}');
    setState(() {
      _scan = item;
      _stage = _Stage.preview;
      _setPlan(plan!, label);
    });
  }

  Future<void> _openJournal() async {
    setState(() {
      _stage = _Stage.journal;
      _loading = true;
      _error = null;
      _plan = null;
    });
    try {
      final all = await _journalDao.listAll();
      if (!mounted) return;
      final live = all.where((e) => !e.isDeleted).toList();
      final projects = journalImportProjects(live);
      setState(() {
        _journal = live;
        _project = projects.isEmpty ? null : projects.first;
        _package = null;
        _loading = false;
        _recomputeJournal();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr(
            pl: 'Nie udało się odczytać dziennika spoin.',
            en: 'Could not read the weld journal.');
      });
    }
  }

  /// Bez setState — wołane z setState.
  void _recomputeJournal() {
    if (_journal.isEmpty) {
      _plan = null;
      return;
    }
    final filter = JournalImportFilter(
        project: _project, testPackage: _package, onlyOpen: _onlyOpen);
    final entries = journalEntriesForImport(_journal, filter);
    final plan = planQuoteImport(entries.map(importWeldFromJournal),
        defaultPosition: _defaultPosition, stainless: _stainless);
    final label = journalImportLabel(filter);
    _setPlan(
        plan,
        label.isNotEmpty
            ? label
            : context.tr(pl: 'Dziennik spoin', en: 'Weld journal'));
  }

  /// Bez setState — wołane z setState. Nowy podgląd: wszystko zaznaczone,
  /// pozycje jak z danych.
  void _setPlan(QuoteImportPlan plan, String label) {
    _plan = plan;
    _label = label;
    _selected = {for (final g in plan.groups) g.key};
    _positions.clear();
  }

  void _back() {
    setState(() {
      switch (_stage) {
        case _Stage.source:
          break;
        case _Stage.scans:
        case _Stage.journal:
          _stage = _Stage.source;
          _plan = null;
          _error = null;
        case _Stage.preview:
          _stage = _Stage.scans;
          _plan = null;
          _scan = null;
      }
    });
  }

  void _confirm() {
    final plan = _plan;
    if (plan == null) return;
    final joints = quoteJointsFromImport(
      plan,
      selected: _selected,
      positions: _positions,
      label: _label,
      newId: () => const Uuid().v4(),
    );
    if (joints.isEmpty) return;
    Haptic.saved();
    Navigator.of(context).pop(joints);
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  // ─── Widoki ───────────────────────────────────────────────────────────────

  String get _title => switch (_stage) {
        _Stage.source => context.tr(pl: 'Importuj spoiny', en: 'Import welds'),
        _Stage.scans =>
          context.tr(pl: 'Zapisane skany ISO', en: 'Stored ISO scans'),
        _Stage.journal => context.tr(pl: 'Dziennik spoin', en: 'Weld journal'),
        _Stage.preview => context.tr(pl: 'Podgląd importu', en: 'Import preview'),
      };

  Widget _sourceTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kArc.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: kArc),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15.5)),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 12.5, color: kTextSec, height: 1.35)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: kTextMut),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _sourceStage() => [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            context.tr(
                pl: 'Spoiny, które masz już w aplikacji, trafią do wyceny jako '
                    'pozycje — zgrupowane po rodzaju złącza, wymiarze i '
                    'pozycji. Przed dodaniem zobaczysz podgląd i odznaczysz '
                    'to, co nie wchodzi.',
                en: 'Welds you already have in the app go into the quote as '
                    'items — grouped by joint type, size and position. You see '
                    'a preview first and untick what is not part of the job.'),
            style: const TextStyle(color: kTextSec, height: 1.45),
          ),
        ),
        _sourceTile(
          key: const ValueKey('import-source-scan'),
          icon: Icons.document_scanner_outlined,
          title: context.tr(pl: 'Skan izometryku', en: 'Isometric scan'),
          subtitle: context.tr(
              pl: 'Zapisany odczyt skanera ISO — mapa spoin z rysunku.',
              en: 'A stored ISO scanner reading — the weld map of the drawing.'),
          onTap: _openScans,
        ),
        _sourceTile(
          key: const ValueKey('import-source-journal'),
          icon: Icons.menu_book_outlined,
          title: context.tr(pl: 'Dziennik spoin', en: 'Weld journal'),
          subtitle: context.tr(
              pl: 'Spoiny projektu albo pakietu testowego — np. wycena '
                  'dokończenia pakietu.',
              en: 'Welds of a project or a test package — e.g. a quote to '
                  'finish a package.'),
          onTap: _openJournal,
        ),
      ];

  List<Widget> _scanStage() {
    if (_scans.isEmpty) {
      return [
        Text(
          context.tr(
              pl: 'Nie ma zapisanych skanów. Zeskanuj izometryk w Skanerze '
                  'ISO — odczyt zapisze się sam i wróci tutaj.',
              en: 'There are no stored scans. Scan an isometric in the ISO '
                  'scanner — the reading is stored and shows up here.'),
          style: const TextStyle(color: kTextSec, height: 1.45),
        ),
      ];
    }
    return [
      QuoteSection(
        title: context.tr(
            pl: 'Wybierz odczyt (najnowsze na górze)',
            en: 'Pick a reading (newest first)'),
        children: [
          for (final item in _scans)
            ListTile(
              key: ValueKey('import-scan-${item.record.id}'),
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 10,
              enabled: item.scan != null,
              leading: const Icon(Icons.history, color: kArc),
              title: Text(item.label.isEmpty
                  ? context.tr(pl: 'Skan bez nazwy', en: 'Unnamed scan')
                  : item.label),
              subtitle: Text(
                [
                  _date(item.record.createdAt),
                  if ((item.record.name ?? '').trim().isNotEmpty &&
                      item.record.name!.trim() != item.label)
                    item.record.name!.trim(),
                  if (item.scan == null)
                    context.tr(pl: 'uszkodzony odczyt', en: 'damaged reading'),
                ].join('  ·  '),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
              trailing: const Icon(Icons.chevron_right, color: kTextMut),
              onTap: () => _pickScan(item),
            ),
        ],
      ),
    ];
  }

  String _projectName(String p) =>
      p.isEmpty ? context.tr(pl: '(bez projektu)', en: '(no project)') : p;

  List<Widget> _journalStage() {
    if (_journal.isEmpty) {
      return [
        Text(
          context.tr(
              pl: 'Dziennik spoin jest pusty. Spoiny trafiają do niego ręcznie '
                  'albo z mapy spoin skanu ISO.',
              en: 'The weld journal is empty. Welds get there by hand or from '
                  'the weld map of an ISO scan.'),
          style: const TextStyle(color: kTextSec, height: 1.45),
        ),
      ];
    }
    final projects = journalImportProjects(_journal);
    final packages = journalImportPackages(_journal, project: _project);
    final counts = <String, int>{};
    for (final e in _journal) {
      final p = e.projectName.trim();
      counts[p] = (counts[p] ?? 0) + 1;
    }
    InputDecoration dec(String l) => InputDecoration(
        labelText: l, isDense: true, border: const OutlineInputBorder());
    return [
      QuoteSection(
        title: context.tr(pl: 'Zakres z dziennika', en: 'Journal scope'),
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('import-project'),
            initialValue: _project,
            isExpanded: true,
            decoration: dec(context.tr(pl: 'Projekt', en: 'Project')),
            items: [
              for (final p in projects)
                DropdownMenuItem(
                  value: p,
                  child: Text('${_projectName(p)}  (${counts[p] ?? 0})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _project = v;
              _package = null;
              _recomputeJournal();
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            // Inny projekt = inna lista pakietów: pole zaczyna od nowa.
            key: ValueKey('import-package-${_project ?? ''}'),
            initialValue: _package ?? _kAllPackages,
            isExpanded: true,
            decoration:
                dec(context.tr(pl: 'Pakiet testowy', en: 'Test package')),
            items: [
              DropdownMenuItem(
                value: _kAllPackages,
                child: Text(
                    context.tr(pl: 'Wszystkie pakiety', en: 'All packages')),
              ),
              for (final p in packages)
                DropdownMenuItem(
                  value: p,
                  child: Text(
                      p.isEmpty
                          ? context.tr(pl: '(bez pakietu)', en: '(no package)')
                          : p,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _package = (v == null || v == _kAllPackages) ? null : v;
              _recomputeJournal();
            }),
          ),
          SwitchListTile(
            key: const ValueKey('import-only-open'),
            contentPadding: EdgeInsets.zero,
            value: _onlyOpen,
            onChanged: (v) => setState(() {
              _onlyOpen = v;
              _recomputeJournal();
            }),
            title: Text(context.tr(
                pl: 'Tylko spoiny jeszcze niewykonane',
                en: 'Only welds not made yet')),
            subtitle: Text(
              context.tr(
                  pl: 'Bez daty spawania i bez stempla spawacza — np. wycena '
                      'dokończenia pakietu.',
                  en: 'No weld date and no welder stamp — e.g. a quote to '
                      'finish a package.'),
              style: const TextStyle(fontSize: 12, color: kTextMut),
            ),
          ),
        ],
      ),
      if (_plan != null) ..._previewStage(_plan!),
    ];
  }

  List<Widget> _previewStage(QuoteImportPlan plan) {
    final en = _en;
    final selectedGroups =
        plan.groups.where((g) => _selected.contains(g.key)).toList();
    final selectedWelds = selectedGroups.fold(0, (a, g) => a + g.count);
    final noSize = plan.skipped
        .where((s) => s.reason == ImportSkipReason.noSize)
        .toList();
    final badSize = plan.skipped
        .where((s) => s.reason == ImportSkipReason.badSize)
        .toList();
    return [
      if (_stage == _Stage.preview && _scan != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '$_label  ·  ${_date(_scan!.record.createdAt)}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: kTextSec, fontSize: 13),
          ),
        ),
      if (plan.isEmpty)
        QuoteNotice(
          text: context.tr(
              pl: 'W tym źródle nie ma spoin.',
              en: 'There are no welds in this source.'),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.tr(
                pl: 'Zaznaczone: ${selectedGroups.length} z ${plan.groups.length} '
                    'pozycji ($selectedWelds z ${plan.weldCount} spoin). Etykieta '
                    'pozycji: „$_label”.',
                en: 'Selected: ${selectedGroups.length} of ${plan.groups.length} '
                    'items ($selectedWelds of ${plan.weldCount} welds). Item '
                    'label: "$_label".'),
            key: const ValueKey('import-summary'),
            style: const TextStyle(fontSize: 13, color: kTextSec, height: 1.4),
          ),
        ),
        if (noSize.isNotEmpty)
          QuoteNotice(
            key: const ValueKey('import-skipped'),
            icon: Icons.straighten,
            text: context.tr(
                pl: 'Pominięte (brak wymiaru): ${noSize.length} — spoiny bez '
                    'średnicy OD albo ścianki nie są zgadywane.'
                    '${_refsText(noSize.map((s) => s.weld.ref), en: false)} '
                    'Uzupełnij wymiar w źródle albo dodaj je ręcznie.',
                en: 'Skipped (no size): ${noSize.length} — welds without an '
                    'outside diameter or wall are not guessed.'
                    '${_refsText(noSize.map((s) => s.weld.ref), en: true)} '
                    'Fill in the size at the source or add them by hand.'),
          ),
        if (badSize.isNotEmpty)
          QuoteNotice(
            key: const ValueKey('import-bad-size'),
            color: kFail,
            icon: Icons.error_outline,
            text: context.tr(
                pl: 'Pominięte (wymiar poza zakresem): ${badSize.length} — '
                    'sprawdź OD i ściankę w źródle (literówka?).'
                    '${_refsText(badSize.map((s) => s.weld.ref), en: false)}',
                en: 'Skipped (size out of range): ${badSize.length} — check '
                    'the OD and wall at the source (typo?).'
                    '${_refsText(badSize.map((s) => s.weld.ref), en: true)}'),
          ),
        for (final g in plan.groups)
          _GroupTile(
            key: ValueKey('import-group-${g.key}'),
            group: g,
            selected: _selected.contains(g.key),
            position: _positions[g.key] ?? g.position,
            en: en,
            onSelected: (v) => setState(() {
              if (v) {
                _selected.add(g.key);
              } else {
                _selected.remove(g.key);
              }
            }),
            onPosition: (p) => setState(() {
              if (p == g.position) {
                _positions.remove(g.key);
              } else {
                _positions[g.key] = p;
              }
            }),
          ),
      ],
    ];
  }

  static String _refsText(Iterable<String> refs, {required bool en}) {
    final named = refs.where((r) => r.trim().isNotEmpty).toList();
    if (named.isEmpty) return '';
    const max = 8;
    final shown = named.take(max).join(', ');
    final more = named.length > max ? ' … (+${named.length - max})' : '';
    return en ? ' Welds: $shown$more.' : ' Spoiny: $shown$more.';
  }

  Widget? _bottomBar() {
    final plan = _plan;
    if (plan == null ||
        plan.groups.isEmpty ||
        (_stage != _Stage.preview && _stage != _Stage.journal)) {
      return null;
    }
    final welds = plan.groups
        .where((g) => _selected.contains(g.key))
        .fold(0, (a, g) => a + g.count);
    return Material(
      color: kCard,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kBorder))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: FilledButton.icon(
            key: const ValueKey('import-confirm'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
            ),
            onPressed: welds > 0 ? _confirm : null,
            icon: const Icon(Icons.playlist_add_check),
            label: Text(
              context.tr(
                  pl: 'Dodaj do wyceny ($welds spoin)',
                  en: 'Add to quote ($welds welds)'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children;
    if (_loading) {
      children = const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (_error != null) {
      children = [
        QuoteNotice(text: _error!, color: kFail, icon: Icons.error_outline),
      ];
    } else {
      children = switch (_stage) {
        _Stage.source => _sourceStage(),
        _Stage.scans => _scanStage(),
        _Stage.journal => _journalStage(),
        _Stage.preview => _plan == null ? const [] : _previewStage(_plan!),
      };
    }
    return PopScope(
      canPop: _stage == _Stage.source,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _stage == _Stage.source
              ? IconButton(
                  tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : IconButton(
                  key: const ValueKey('import-back'),
                  tooltip: context.tr(pl: 'Wstecz', en: 'Back'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _back,
                ),
          title: Text(_title),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
          children: children,
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }
}

/// Krótka nazwa pozycji: „PF·PH / 5G".
String _positionShort(WeldPosition p, {required bool en}) =>
    (en ? p.labelEn : p.labelPl).split(' — ').first;

class _GroupTile extends StatelessWidget {
  final QuoteImportGroup group;
  final bool selected;
  final WeldPosition position;
  final bool en;
  final ValueChanged<bool> onSelected;
  final ValueChanged<WeldPosition> onPosition;

  const _GroupTile({
    super.key,
    required this.group,
    required this.selected,
    required this.position,
    required this.en,
    required this.onSelected,
    required this.onPosition,
  });

  @override
  Widget build(BuildContext context) {
    final g = group;
    final joint = g.toJoint(id: '', position: position);
    final changed = position != g.position;
    final positionNote = changed
        ? context.tr(pl: 'zmieniona ręcznie', en: 'changed by hand')
        : g.positionAssumedCount == g.count
            ? context.tr(
                pl: 'przyjęta z wyceny (brak w danych)',
                en: 'from the quote (not in the data)')
            : g.positionAssumedCount > 0
                ? context.tr(
                    pl: '${g.positionAssumedCount} bez pozycji w danych — '
                        'przyjęto z wyceny',
                    en: '${g.positionAssumedCount} with no position in the '
                        'data — taken from the quote')
                : '';
    final where = [
      if (g.shopCount > 0)
        context.tr(pl: 'warsztat ${g.shopCount}', en: 'shop ${g.shopCount}'),
      if (g.fieldCount > 0)
        context.tr(pl: 'obiekt ${g.fieldCount}', en: 'field ${g.fieldCount}'),
      if (g.unknownLocationCount > 0 && (g.shopCount > 0 || g.fieldCount > 0))
        context.tr(
            pl: 'bez oznaczenia ${g.unknownLocationCount}',
            en: 'unmarked ${g.unknownLocationCount}'),
    ];
    final refs = _QuoteImportSheetState._refsText(g.refs, en: en).trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: selected ? kArc.withValues(alpha: 0.6) : kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelected(!selected),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => onSelected(v ?? false),
                  activeColor: kArc,
                  checkColor: kOnArc,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (selected ? kArc : kTextMut)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${g.count}×',
                        style: TextStyle(
                            color: selected ? kArc : kTextMut,
                            fontWeight: FontWeight.w900,
                            fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(jointKindShort(g.kind, en: en),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(jointSizeLabel(joint, en: en),
                            style: const TextStyle(
                                fontSize: 12.5, color: kTextSec)),
                        Text(
                          [
                            _positionShort(position, en: en),
                            if (positionNote.isNotEmpty) positionNote,
                          ].join('  ·  '),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: changed ? kArc : kTextSec),
                        ),
                        if (where.isNotEmpty)
                          Text(where.join('  ·  '),
                              style: const TextStyle(
                                  fontSize: 12, color: kTextMut)),
                        if (g.kindAssumedCount > 0)
                          Text(
                            context.tr(
                                pl: 'Rodzaj nieoznaczony (${g.kindAssumedCount}) '
                                    '— przyjęto doczołową',
                                en: 'Joint type not marked (${g.kindAssumedCount}) '
                                    '— taken as butt weld'),
                            style:
                                const TextStyle(fontSize: 12, color: kWarn),
                          ),
                        if (g.kind == JointKind.branch && g.headerOdMm <= 0)
                          Text(
                            context.tr(
                                pl: 'Rura główna nieznana — uzupełnij w pozycji',
                                en: 'Header unknown — fill it in the item'),
                            style:
                                const TextStyle(fontSize: 12, color: kWarn),
                          ),
                        if (refs.isNotEmpty)
                          Text(refs,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: kTextMut)),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<WeldPosition>(
                  tooltip:
                      context.tr(pl: 'Pozycja spawania', en: 'Welding position'),
                  icon: const Icon(Icons.swap_vert, color: kTextSec),
                  onSelected: onPosition,
                  itemBuilder: (_) => [
                    for (final p in WeldPosition.values)
                      CheckedPopupMenuItem(
                        value: p,
                        checked: p == position,
                        child: Text(en ? p.labelEn : p.labelPl),
                      ),
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
