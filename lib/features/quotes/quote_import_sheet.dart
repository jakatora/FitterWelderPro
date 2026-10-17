// „Importuj spoiny" — pełnoekranowe okno z zakładki „Spoiny" wyceny: źródło
// (zapisany skan izometryku, dziennik spoin albo projekt CUT) → wybór
// skanu, projektu / pakietu albo projektu CUT → PODGLĄD zgrupowanych pozycji
// → „Dodaj do wyceny". Okno tylko zwraca pozycje; dodaje je zakładka
// (onUpdate, od aktualnej wyceny). Grupowanie i mapowanie:
// domain/quotes/quote_import.dart; spoiny projektu CUT (reguły liczenia):
// services/cut_quote_import.dart.

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
import '../../services/cut_quote_import.dart';
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
  Future<List<CutImportProject>> Function()? loadCutProjects,
}) =>
    Navigator.of(context).push<List<QuoteJoint>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => QuoteImportSheet(
        quote: quote,
        scanDao: scanDao,
        journalDao: journalDao,
        loadCutProjects: loadCutProjects,
      ),
    ));

enum _Stage { source, scans, journal, cut, preview }

class _ScanItem {
  final IsoScanRecord record;
  final AiScanResult? scan;
  final String label;
  const _ScanItem(this.record, this.scan, this.label);
}

/// Projekt CUT na liście: spoiny do wyceny i do sprawdzenia przy typach
/// kołnierzy / zaworów jeszcze niewybranych.
class _CutItem {
  final CutImportProject data;
  final int weldCount;
  final int checkCount;
  const _CutItem(this.data, this.weldCount, this.checkCount);
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

  /// Do testów; domyślnie [loadCutProjectsForImport].
  final Future<List<CutImportProject>> Function()? loadCutProjects;

  const QuoteImportSheet({
    super.key,
    required this.quote,
    this.scanDao,
    this.journalDao,
    this.loadCutProjects,
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

  List<_CutItem> _cutProjects = const [];
  _CutItem? _cut;
  CutProjectWelds? _cutWelds;
  CutEndJoint _flanges = CutEndJoint.unknown;
  CutEndJoint _valves = CutEndJoint.unknown;

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

  Future<void> _openCut() async {
    setState(() {
      _stage = _Stage.cut;
      _loading = true;
      _error = null;
      _plan = null;
    });
    try {
      final list =
          await (widget.loadCutProjects ?? loadCutProjectsForImport)();
      if (!mounted) return;
      setState(() {
        _cutProjects = [for (final p in list) _cutItem(p)];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr(
            pl: 'Nie udało się odczytać projektów CUT.',
            en: 'Could not read the CUT projects.');
      });
    }
  }

  bool _cutStainless(CutImportProject p) =>
      _stainless || cutProjectIsStainless(p.project);

  _CutItem _cutItem(CutImportProject p) {
    final plan = planQuoteImport(importWeldsFromCutProject(p).welds,
        defaultPosition: _defaultPosition, stainless: _cutStainless(p));
    return _CutItem(p, plan.weldCount, plan.skippedCount);
  }

  void _pickCut(_CutItem item) {
    setState(() {
      _cut = item;
      _flanges = CutEndJoint.unknown;
      _valves = CutEndJoint.unknown;
      _stage = _Stage.preview;
      _recomputeCut(keepSelection: false);
    });
  }

  /// Bez setState — wołane z setState. Zmiana typu kołnierzy / zaworów
  /// zostawia odznaczone grupy i zmienione pozycje.
  void _recomputeCut({bool keepSelection = true}) {
    final item = _cut;
    if (item == null) return;
    final res = importWeldsFromCutProject(
      item.data,
      options: CutImportOptions(
        flanges: _flanges,
        valves: _valves,
        startTag: context.tr(pl: 'pocz.', en: 'start'),
        endTag: context.tr(pl: 'kon.', en: 'end'),
      ),
    );
    _cutWelds = res;
    final plan = planQuoteImport(res.welds,
        defaultPosition: _defaultPosition,
        stainless: _cutStainless(item.data));
    final label = cutImportLabel(item.data.project, english: _en);
    _setPlan(
      plan,
      label.isNotEmpty
          ? label
          : context.tr(
              pl: 'Projekt CUT ${_date(item.data.project.createdAt)}',
              en: 'CUT project ${_date(item.data.project.createdAt)}'),
      keepSelection: keepSelection,
    );
  }

  /// Bez setState — wołane z setState. Nowy podgląd: wszystko zaznaczone,
  /// pozycje jak z danych. [keepSelection] — ten sam podgląd przeliczony:
  /// odznaczone grupy zostają odznaczone, nowe grupy są zaznaczone.
  void _setPlan(QuoteImportPlan plan, String label,
      {bool keepSelection = false}) {
    final old = _plan;
    _plan = plan;
    _label = label;
    if (keepSelection && old != null) {
      final oldKeys = {for (final g in old.groups) g.key};
      _selected = {
        for (final g in plan.groups)
          if (_selected.contains(g.key) || !oldKeys.contains(g.key)) g.key,
      };
      final keys = {for (final g in plan.groups) g.key};
      _positions.removeWhere((k, _) => !keys.contains(k));
    } else {
      _selected = {for (final g in plan.groups) g.key};
      _positions.clear();
    }
  }

  void _back() {
    setState(() {
      switch (_stage) {
        case _Stage.source:
          break;
        case _Stage.scans:
        case _Stage.journal:
        case _Stage.cut:
          _stage = _Stage.source;
          _plan = null;
          _error = null;
        case _Stage.preview:
          _stage = _cut != null ? _Stage.cut : _Stage.scans;
          _plan = null;
          _scan = null;
          _cut = null;
          _cutWelds = null;
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
        _Stage.cut => context.tr(pl: 'Projekty CUT', en: 'CUT projects'),
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
        _sourceTile(
          key: const ValueKey('import-source-cut'),
          icon: Icons.content_cut,
          title: context.tr(pl: 'Projekt CUT', en: 'CUT project'),
          subtitle: context.tr(
              pl: 'Trasa z listy cięć — spoina na każdym połączeniu '
                  'rura–kształtka, z wymiarem odcinka.',
              en: 'A route from the cut list — a weld at every '
                  'pipe-to-fitting joint, in the size of the pipe piece.'),
          onTap: _openCut,
        ),
      ];

  List<Widget> _cutStage() {
    if (_cutProjects.isEmpty) {
      return [
        Text(
          context.tr(
              pl: 'Nie ma projektów CUT. Zbuduj trasę z odcinków i kształtek '
                  'w module Lista cięć — projekt pojawi się tutaj.',
              en: 'There are no CUT projects. Build a route of pipe pieces '
                  'and fittings in the Cut list module — the project shows '
                  'up here.'),
          style: const TextStyle(color: kTextSec, height: 1.45),
        ),
      ];
    }
    return [
      QuoteSection(
        title: context.tr(
            pl: 'Wybierz projekt (ostatnio zmieniane na górze)',
            en: 'Pick a project (last changed first)'),
        children: [
          for (final item in _cutProjects) _cutTile(item),
        ],
      ),
    ];
  }

  Widget _cutTile(_CutItem item) {
    final p = item.data.project;
    final name = p.name?.trim() ?? '';
    final title = name.isNotEmpty
        ? name
        : cutImportLabel(p, english: _en).isNotEmpty
            ? cutImportLabel(p, english: _en)
            : context.tr(pl: 'Projekt bez nazwy', en: 'Unnamed project');
    final empty = item.data.segments.isEmpty;
    return ListTile(
      key: ValueKey('import-cut-${p.id}'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      enabled: !empty,
      leading: const Icon(Icons.content_cut, color: kArc),
      title: Text(title),
      subtitle: Text(
        [
          _date(p.updatedAt),
          if (empty)
            context.tr(pl: 'brak odcinków', en: 'no pipe pieces')
          else ...[
            context.tr(
                pl: 'spoiny: ${item.weldCount}', en: 'welds: ${item.weldCount}'),
            if (item.checkCount > 0)
              context.tr(
                  pl: 'do sprawdzenia: ${item.checkCount}',
                  en: 'to check: ${item.checkCount}'),
          ],
        ].join('  ·  '),
        style: const TextStyle(fontSize: 12, color: kTextMut),
      ),
      trailing: const Icon(Icons.chevron_right, color: kTextMut),
      onTap: () => _pickCut(item),
    );
  }

  /// Nad podglądem projektu CUT: nazwa i data, zgodność materiału, wybór
  /// typu kołnierzy / zaworów (CUT go nie zapisuje).
  List<Widget> _cutPreviewHead() {
    final item = _cut;
    final res = _cutWelds;
    if (item == null || res == null) return const [];
    final p = item.data.project;
    final projectSs = cutProjectIsStainless(p);
    final material = widget.quote.material;
    final quoteSs = _stainless;
    final mismatch =
        projectSs != quoteSs || material == QuoteMaterial.aluminium;
    InputDecoration dec(String l) => InputDecoration(
        labelText: l, isDense: true, border: const OutlineInputBorder());
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          '$_label  ·  ${_date(p.updatedAt)}',
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: kTextSec, fontSize: 13),
        ),
      ),
      if (mismatch)
        QuoteNotice(
          key: const ValueKey('import-cut-material'),
          icon: Icons.science_outlined,
          text: context.tr(
              pl: 'Projekt CUT: ${projectSs ? 'stal nierdzewna (SS)' : 'stal '
                  'węglowa (CS)'}, a wycena: ${material.labelPl}. Stopiwo i '
                  'czas liczą się z materiału wyceny — sprawdź go.',
              en: 'CUT project: ${projectSs ? 'stainless steel (SS)' : 'carbon '
                  'steel (CS)'}, but the quote: ${material.labelEn}. Filler '
                  'metal and time follow the quote material — check it.'),
        ),
      if (res.flangeEnds > 0 || res.valveEnds > 0)
        QuoteSection(
          key: const ValueKey('import-cut-joints'),
          title: context.tr(pl: 'Kołnierze i zawory', en: 'Flanges and valves'),
          subtitle: context.tr(
              pl: 'Projekt CUT nie zapisuje, jak są połączone z rurą. Wybierz '
                  '— bez wyboru ich spoiny trafią do sprawdzenia.',
              en: 'The CUT project does not store how they join the pipe. '
                  'Pick it — otherwise their welds go to the check list.'),
          children: [
            if (res.flangeEnds > 0)
              _jointChoice(
                key: const ValueKey('import-cut-flanges'),
                decoration: dec(context.tr(
                    pl: 'Kołnierze — połączeń z rurą: ${res.flangeEnds}',
                    en: 'Flanges — pipe joints: ${res.flangeEnds}')),
                value: _flanges,
                labels: {
                  CutEndJoint.unknown: context.tr(
                      pl: 'Nie wiem — do sprawdzenia',
                      en: 'Not sure — to check'),
                  CutEndJoint.butt: context.tr(
                      pl: 'Szyjkowe (WN) — doczołowa',
                      en: 'Weld neck (WN) — butt weld'),
                  CutEndJoint.fillet: context.tr(
                      pl: 'Płaskie (SO) / mufowe (SW) — pachwinowa',
                      en: 'Slip-on (SO) / socket (SW) — fillet weld'),
                  CutEndJoint.none: context.tr(
                      pl: 'Luźne / gwintowane — bez spoiny',
                      en: 'Lap-joint / threaded — no weld'),
                },
                onChanged: (v) => setState(() {
                  _flanges = v;
                  _recomputeCut();
                }),
              ),
            if (res.flangeEnds > 0 && res.valveEnds > 0)
              const SizedBox(height: 12),
            if (res.valveEnds > 0)
              _jointChoice(
                key: const ValueKey('import-cut-valves'),
                decoration: dec(context.tr(
                    pl: 'Zawory — połączeń z rurą: ${res.valveEnds}',
                    en: 'Valves — pipe joints: ${res.valveEnds}')),
                value: _valves,
                labels: {
                  CutEndJoint.unknown: context.tr(
                      pl: 'Nie wiem — do sprawdzenia',
                      en: 'Not sure — to check'),
                  CutEndJoint.butt: context.tr(
                      pl: 'Do wspawania (BW) — doczołowa',
                      en: 'Butt-weld ends (BW) — butt weld'),
                  CutEndJoint.fillet: context.tr(
                      pl: 'Mufowe (SW) — pachwinowa',
                      en: 'Socket-weld (SW) — fillet weld'),
                  CutEndJoint.none: context.tr(
                      pl: 'Kołnierzowe / gwintowane — bez spoiny',
                      en: 'Flanged / threaded — no weld'),
                },
                onChanged: (v) => setState(() {
                  _valves = v;
                  _recomputeCut();
                }),
              ),
          ],
        ),
    ];
  }

  Widget _jointChoice({
    required Key key,
    required InputDecoration decoration,
    required CutEndJoint value,
    required Map<CutEndJoint, String> labels,
    required ValueChanged<CutEndJoint> onChanged,
  }) =>
      DropdownButtonFormField<CutEndJoint>(
        key: key,
        initialValue: value,
        isExpanded: true,
        itemHeight: null,
        decoration: decoration,
        selectedItemBuilder: (_) => [
          for (final j in CutEndJoint.values)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(labels[j]!,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        items: [
          for (final j in CutEndJoint.values)
            DropdownMenuItem(
              value: j,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(labels[j]!),
              ),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  /// Pod podglądem projektu CUT: reguły liczenia spoin
  /// (services/cut_quote_import.dart).
  List<Widget> _cutAssumptions() {
    if (_cut == null) return const [];
    final rules = [
      context.tr(
          pl: 'Spoina na każdym końcu odcinka przy kształtce — tam, gdzie CUT '
              'odejmuje szczelinę spoiny. Wymiar: OD i ścianka tego odcinka.',
          en: 'A weld at every end of a pipe piece that meets a fitting — '
              'where CUT takes off the root gap. Size: OD and wall of that '
              'piece.'),
      context.tr(
          pl: 'Kolano, trójnik, redukcja — doczołowa (BW): trójnik to 3 '
              'spoiny, redukcja — 2 o różnych średnicach. Kształtka osiowa '
              'ze skanu bez typu — spoina jest, rodzaj przyjęty jako '
              'doczołowa.',
          en: 'Elbow, tee, reducer — butt weld (BW): a tee is 3 welds, a '
              'reducer 2 of different sizes. An axial fitting from a scan '
              'with no type — the weld is there, taken as a butt weld.'),
      context.tr(
          pl: 'Kołnierz: WN — doczołowa, SO / SW — pachwinowa, luźny / '
              'gwintowany — bez spoiny. Zawór: BW — doczołowa, SW — '
              'pachwinowa, kołnierzowy / gwintowany — bez spoiny. Bez '
              'wyboru — do sprawdzenia.',
          en: 'Flange: WN — butt weld, SO / SW — fillet weld, lap-joint / '
              'threaded — no weld. Valve: BW — butt weld, SW — fillet weld, '
              'flanged / threaded — no weld. Not picked — to check.'),
      context.tr(
          pl: 'Odcinek dłuższy niż sztanga — doczołowa rura–rura na każdy '
              'podział z listy cięć.',
          en: 'A piece longer than the stock bar — a pipe-to-pipe butt weld '
              'for every split on the cut list.'),
      context.tr(
          pl: 'Koniec otwarty — bez spoiny. Spoin rura–rura na końcach '
              'otwartych (np. montażowych) ani odgałęzień wspawanych bez '
              'trójnika (olet, króciec) projekt nie zapisuje — dodaj je '
              'ręcznie.',
          en: 'Open end — no weld. Pipe-to-pipe welds at open ends (e.g. '
              'field welds) and branches welded on without a tee (olet, '
              'set-on) are not in the project — add them by hand.'),
      context.tr(
          pl: 'Pozycja spawania — z wyceny (warsztat PA, obiekt PF); zmienisz '
              'ją przy grupie.',
          en: 'Welding position — from the quote (shop PA, field PF); change '
              'it on the group.'),
    ];
    return [
      QuoteSection(
        key: const ValueKey('import-cut-assumptions'),
        title: context.tr(
            pl: 'Założenia liczenia spoin', en: 'How welds are counted'),
        children: [
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(color: kTextSec, height: 1.4)),
                  Expanded(
                    child: Text(r,
                        style: const TextStyle(
                            fontSize: 12.5, color: kTextSec, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

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
    List<String> refsFor(ImportSkipReason r) => [
          for (final s in plan.skipped)
            if (s.reason == r) s.weld.ref,
        ];
    final flanges = refsFor(ImportSkipReason.flangeType);
    final valves = refsFor(ImportSkipReason.valveEnds);
    final untyped = refsFor(ImportSkipReason.fittingType);
    final openPorts = refsFor(ImportSkipReason.openPort);
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
        if (flanges.isNotEmpty)
          QuoteNotice(
            key: const ValueKey('import-check-flanges'),
            icon: Icons.help_outline,
            text: context.tr(
                pl: 'Do sprawdzenia — kołnierze: ${flanges.length}. Projekt '
                    'CUT nie zapisuje typu kołnierza (WN, SO, luźny), a od '
                    'niego zależy spoina — wybierz typ wyżej.'
                    '${_refsText(flanges, en: false)}',
                en: 'To check — flanges: ${flanges.length}. The CUT project '
                    'does not store the flange type (WN, SO, lap-joint) and '
                    'the weld depends on it — pick the type above.'
                    '${_refsText(flanges, en: true)}'),
          ),
        if (valves.isNotEmpty)
          QuoteNotice(
            key: const ValueKey('import-check-valves'),
            icon: Icons.help_outline,
            text: context.tr(
                pl: 'Do sprawdzenia — końce zaworów: ${valves.length}. '
                    'Projekt CUT nie zapisuje, czy zawór jest do wspawania, '
                    'mufowy czy kołnierzowy — wybierz wyżej.'
                    '${_refsText(valves, en: false)}',
                en: 'To check — valve ends: ${valves.length}. The CUT project '
                    'does not store whether a valve is butt-weld, socket-weld '
                    'or flanged — pick it above.'
                    '${_refsText(valves, en: true)}'),
          ),
        if (untyped.isNotEmpty)
          QuoteNotice(
            key: const ValueKey('import-check-untyped'),
            icon: Icons.help_outline,
            text: context.tr(
                pl: 'Do sprawdzenia — kształtki bez typu: ${untyped.length}. '
                    'Projekt ze skanu lub szkicu ISO (albo wpis usunięty z '
                    'biblioteki) nie mówi, czy to kołnierz, zawór czy '
                    'redukcja — spoina nie jest zgadywana. Spoiny takiego '
                    'rysunku dokładniej zaimportujesz ze skanu ISO.'
                    '${_refsText(untyped, en: false)}',
                en: 'To check — fittings without a type: ${untyped.length}. '
                    'A project from an ISO scan or sketch (or a deleted '
                    'library entry) does not say whether it is a flange, a '
                    'valve or a reducer — the weld is not guessed. Import '
                    'the welds of such a drawing from the ISO scan instead.'
                    '${_refsText(untyped, en: true)}'),
          ),
        if (openPorts.isNotEmpty)
          QuoteNotice(
            key: const ValueKey('import-check-open-ports'),
            icon: Icons.help_outline,
            text: context.tr(
                pl: 'Do sprawdzenia — wolne końce kształtek: '
                    '${openPorts.length}. Kształtka ma tam spoinę, ale po '
                    'drugiej stronie nie ma odcinka rury w projekcie (spoina '
                    'kształtka–kształtka albo poza projektem) — dodaj ją '
                    'ręcznie, jeśli wchodzi. Kształtki: '
                    '${_countedList(openPorts)}.',
                en: 'To check — free fitting ends: ${openPorts.length}. The '
                    'fitting has a weld there, but no pipe piece on the other '
                    'side in the project (fitting-to-fitting or outside the '
                    'project) — add it by hand if it is part of the job. '
                    'Fittings: ${_countedList(openPorts)}.'),
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

  /// „TEE Ø114.3 ×2, ELB90 Ø60.3" — powtórzenia zliczone, kolejność źródła.
  static String _countedList(Iterable<String> items) {
    final counts = <String, int>{};
    for (final i in items) {
      counts[i] = (counts[i] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries)
        e.value > 1 ? '${e.key} ×${e.value}' : e.key,
    ].join(', ');
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
        _Stage.cut => _cutStage(),
        _Stage.preview => _plan == null
            ? const []
            : [
                ..._cutPreviewHead(),
                ..._previewStage(_plan!),
                ..._cutAssumptions(),
              ],
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
