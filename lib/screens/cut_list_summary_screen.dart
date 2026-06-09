import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../models/segment.dart';
import '../services/bar_nesting.dart';
import '../services/pdf_export_service.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';

// ── i18n helpers (P1-38) ────────────────────────────────────────────────────
/// PL/EN plural rule for "bar / sztanga".
///
/// PL: 1 sztanga / 2-4 sztangi / 5+ sztang (with the usual 12-14 exception);
/// EN: 1 bar / N bars.
String pluralBars(int n, BuildContext context) {
  if (context.language == AppLanguage.en) {
    return n == 1 ? '$n bar' : '$n bars';
  }
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (n == 1) return '$n sztanga';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n sztangi';
  }
  return '$n sztang';
}

/// PL/EN plural rule for "piece / odcinek".
///
/// PL: 1 odcinek / 2-4 odcinki / 5+ odcinków;
/// EN: 1 piece / N pieces.
String pluralPieces(int n, BuildContext context) {
  if (context.language == AppLanguage.en) {
    return n == 1 ? '$n piece' : '$n pieces';
  }
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (n == 1) return '$n odcinek';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n odcinki';
  }
  return '$n odcinków';
}

/// Quote a CSV/line-tag value if it contains separator chars, quotes, or
/// whitespace. Doubles embedded `"` per RFC 4180 so the same tag round-trips
/// when re-imported into Excel/LibreOffice. Used both for the ASME line-tag
/// chip (defensive — `materialGroup` may someday contain a space) and every
/// CSV cell.
String csvQuote(String raw) {
  if (raw.contains(RegExp(r'[",;\s]'))) {
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
  }
  return raw;
}

const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kBlue   = Color(0xFF4A9EFF);
const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kMuted  = Color(0xFF55607A);

class CutListSummaryScreen extends StatefulWidget {
  final String projectId;
  const CutListSummaryScreen({super.key, required this.projectId});

  @override
  State<CutListSummaryScreen> createState() => _CutListSummaryScreenState();
}

class _CutListSummaryScreenState extends State<CutListSummaryScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();
  Project? _project;
  List<Segment> _segments = [];
  Map<String, List<double>> _groups = {};
  // Memoized per-group (sortedCuts, plans). Recomputed only in _load() so that
  // build() and listView rebuilds (e.g. orientation, scroll-driven media query
  // changes) don't re-run the nesting algorithm or re-sort the cuts list.
  Map<String, _GroupPlan> _groupPlans = const {};
  bool _loading = true;
  bool _exporting = false;
  // P1-44: load lifecycle hardening — guard against reentrancy, stale awaits
  // (rotation / projectId change) and post-dispose setState.
  bool _loadInFlight = false;
  int _loadGen = 0;
  // P1-44: surfaces _load failures with a Retry CTA rather than wedging the
  // spinner.
  String? _loadError;
  // P1-44: signals the in-flight _exportPdf to bail out before touching
  // setState() / ScaffoldMessenger after dispose. Effectively a cooperative
  // cancellation flag — we can't kill the awaited Future on platform side, but
  // we can stop poisoning a dead State.
  bool _disposed = false;
  // P1-44: single re-entrancy guard reused by _share + _copyCsv so a frantic
  // double-tap on the share IconButton doesn't push two clipboard writes /
  // two snackbars on top of each other.
  bool _copyInFlight = false;

  Future<void> _load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    final gen = ++_loadGen;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final p    = await _projectDao.getById(widget.projectId);
      if (gen != _loadGen || !mounted) return;
      final segs = await _segmentDao.listForProject(widget.projectId);
      if (gen != _loadGen || !mounted) return;

      final groups = <String, List<double>>{};
      for (final s in segs) {
        final key = '${s.diameterMm}|${s.wallThicknessMm}';
        groups.putIfAbsent(key, () => []).add(s.cutMm);
      }

      final plans = <String, _GroupPlan>{};
      if (p != null) {
        for (final e in groups.entries) {
          final sorted = List<double>.from(e.value)..sort((a, b) => b.compareTo(a));
          plans[e.key] = _GroupPlan(
            sortedCuts: sorted,
            plans: nestCutsToBars(
              cutsMm: sorted,
              stockLengthMm: p.stockLengthMm,
              sawKerfMm: p.sawKerfMm,
            ),
          );
        }
      }

      if (gen != _loadGen || !mounted) return;
      setState(() {
        _project    = p;
        _segments   = segs;
        _groups     = groups;
        _groupPlans = plans;
        _loading    = false;
        _loadError  = null;
      });
    } catch (e, st) {
      debugPrint('[CutListSummary] _load failed: $e\n$st');
      if (gen != _loadGen || !mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  /// Maps a low-level filesystem failure into an actionable PL/EN message the
  /// fitter can act on without leaving the cut-list screen.
  ///
  /// Errno 13 (PathAccessException, EACCES) and the typical
  /// "no space left on device" cases dominate field reports — both have a
  /// concrete remediation ("zwolnij ~5 MB"), so we surface that instead of
  /// the raw `OSError: errno = 13` blob.
  String _exportErrorMessage(BuildContext context, Object error) {
    final isPermission = error is PathAccessException ||
        (error is FileSystemException && (error.osError?.errorCode == 13));
    final isNoSpace = error is FileSystemException &&
        (error.osError?.errorCode == 28 ||
         (error.message.toLowerCase().contains('no space')) ||
         (error.osError?.message.toLowerCase().contains('no space') ?? false));
    if (isPermission || isNoSpace) {
      return context.tr(
        pl: 'Brak miejsca na pliki tymczasowe — zwolnij ~5 MB i spróbuj ponownie.',
        en: 'No space for temp files — free ~5 MB and try again.',
      );
    }
    return context.tr(
      pl: 'Nie udało się wygenerować PDF: $error',
      en: 'PDF export failed: $error',
    );
  }

  Future<void> _exportPdf() async {
    // P1-28: re-entrancy guard before any await — double-tapping the IconButton
    // on flaky touchscreens otherwise queues a second exportCutList while the
    // first is still writing to /tmp.
    if (_exporting) return;
    final p = _project;
    // Snapshot segments so a concurrent _load() (e.g. user navigated back and
    // forward, hot-restart, or a future projectId-change driven reload) cannot
    // race the PDF builder mid-write.
    final segsSnapshot = List<Segment>.unmodifiable(_segments);
    if (p == null || segsSnapshot.isEmpty) return;
    await Haptic.tap();
    if (!mounted) return;
    setState(() => _exporting = true);
    try {
      await PdfExportService.exportCutList(project: p, segments: segsSnapshot);
    } catch (e, st) {
      debugPrint('[CutListSummary] _exportPdf failed: $e\n$st');
      // P1-44: cooperative cancellation — user may have popped back during
      // the await, in which case there is no Scaffold to message.
      if (_disposed || !mounted) return;
      await Haptic.error();
      if (_disposed || !mounted) return;
      final msg = _exportErrorMessage(context, e);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: _kRed,
          duration: const Duration(seconds: 7),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: context.tr(pl: 'Spróbuj ponownie', en: 'Try again'),
            textColor: Colors.white,
            onPressed: () {
              if (_disposed || !mounted) return;
              _exportPdf();
            },
          ),
        ),
      );
    } finally {
      if (!_disposed && mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CutListSummaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // P1-44: if the projectId is swapped on us (parent rebuild routing the
    // same Navigator entry at a different record), discard any in-flight load
    // and refetch.
    if (oldWidget.projectId != widget.projectId) {
      _loadGen++; // invalidate previous gen
      _loadInFlight = false;
      _load();
    }
  }

  @override
  void dispose() {
    // P1-44: signal in-flight _exportPdf / _share / _copyCsv to bail before
    // they call setState on this dead State.
    _disposed = true;
    _loadGen++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    // P1-28: gate every export action on having BOTH a non-empty cut plan and
    // not being mid-export. _exporting separately drives the spinner swap
    // below, but disabled state is shared so a queued-render second tap on
    // the Share/CSV button can't slip through while PDF is writing.
    final exportsEnabled =
        !_exporting && _groups.isNotEmpty && _segments.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CUT LIST'),
        actions: [
          HelpButton(help: kHelpCutListSummary),
          if (p != null) ...[
            // Eksport PDF
            if (_exporting)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange))),
              )
            else
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: context.tr(pl: 'Eksportuj PDF', en: 'Export PDF'),
                // ≥48dp tap target preserved via Material default IconButton
                // BoxConstraints; greyed-out state communicated by the null
                // onPressed (theme handles the alpha).
                onPressed: exportsEnabled ? _exportPdf : null,
              ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: context.tr(pl: 'Kopiuj tekst', en: 'Copy text'),
              onPressed: exportsEnabled ? () => _share(context, p) : null,
            ),
            IconButton(
              icon: const Icon(Icons.table_view_outlined),
              tooltip: context.tr(pl: 'Kopiuj CSV', en: 'Copy CSV'),
              onPressed: exportsEnabled ? () => _copyCsv(context, p) : null,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : _loadError != null
              ? _LoadErrorView(error: _loadError!, onRetry: _load)
              : p == null
              ? Center(child: Text(context.tr(pl: 'Nie znaleziono projektu', en: 'Project not found')))
              : ListView(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, 24 + MediaQuery.viewPaddingOf(context).bottom),
                  children: [
                    // ── NAGŁÓWEK PROJEKTU ─────────────────────────────────
                    _ProjectHeader(project: p),
                    const SizedBox(height: 16),

                    if (_groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.content_cut, size: 56, color: _kMuted.withValues(alpha: 0.6)),
                              const SizedBox(height: 12),
                              Text(
                                context.tr(pl: 'Brak segmentów', en: 'No segments'),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  context.tr(
                                    pl: 'Dodaj odcinki w izometrii, aby zobaczyć plan cięcia sztang.',
                                    en: 'Add pieces in the isometric to see the bar cutting plan.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12, color: _kMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // ── PODSUMOWANIE ZBIORCZE ─────────────────────────
                      _GlobalSummary(groups: _groups, project: p),
                      const SizedBox(height: 20),

                      // ── GRUPY RURY ────────────────────────────────────
                      ..._groupPlans.entries.map((e) {
                        final parts = e.key.split('|');
                        final d = double.parse(parts[0]);
                        final w = double.parse(parts[1]);
                        return _PipeGroup(
                          diameterMm: d,
                          wallMm: w,
                          materialGroup: p.materialGroup,
                          cuts: e.value.sortedCuts,
                          plans: e.value.plans,
                          stockLengthMm: p.stockLengthMm,
                          sawKerfMm: p.sawKerfMm,
                        );
                      }),
                    ],
                  ],
                ),
    );
  }

  String _buildTextSummary(Project p) {
    final buf = StringBuffer();
    buf.writeln('CUT LIST — ${p.name ?? p.id.substring(0, 8)}');
    buf.writeln('Material: ${p.materialGroup}  Stock: ${p.stockLengthMm.toStringAsFixed(0)} mm  Kerf: ${p.sawKerfMm.toStringAsFixed(1)} mm');
    buf.writeln();
    for (final e in _groups.entries) {
      final parts = e.key.split('|');
      final d = double.parse(parts[0]);
      final w = double.parse(parts[1]);
      final cuts = List<double>.from(e.value)..sort((a, b) => b.compareTo(a));
      buf.writeln('Ø${d.toStringAsFixed(1)} x ${w.toStringAsFixed(1)}:');
      final plans = nestCutsToBars(cutsMm: cuts, stockLengthMm: p.stockLengthMm, sawKerfMm: p.sawKerfMm);
      for (var i = 0; i < plans.length; i++) {
        final b = plans[i];
        buf.writeln('  Bar ${i + 1}: ${b.piecesMm.map((x) => x.toStringAsFixed(0)).join(' + ')}  (rem: ${b.remainingMm.toStringAsFixed(0)} mm)');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// CSV with one row per cut piece — drops straight into an Excel column on
  /// the workshop laptop or into a foreman's spreadsheet.
  ///
  /// P1-38: header localisation + RFC 4180 quoting.
  /// The leading `# generated by …` comment line lets us evolve the schema
  /// without breaking older importers that strip leading `#` lines.
  /// Headers are localised per active language, but the `materialGroup` is
  /// passed through unchanged so the ASME short-tag (CS / SS / DSS / IN) is
  /// stable across locales.
  String _buildCsv(Project p, BuildContext context) {
    final buf = StringBuffer();
    buf.writeln('# generated by FitterWelderPro');
    final headers = context.tr(
      pl: 'projekt;materiał;sztanga_mm;rzaz_mm;średnica_mm;ścianka_mm;nr_sztangi;nr_odcinka;cięcie_mm;pozostało_mm',
      en: 'project;material;stock_mm;kerf_mm;diameter_mm;wall_mm;bar_no;piece_no;cut_mm;bar_remaining_mm',
    );
    buf.writeln(headers);
    final projectName = (p.name ?? p.id.substring(0, 8));
    for (final e in _groups.entries) {
      final parts = e.key.split('|');
      final d = double.parse(parts[0]);
      final w = double.parse(parts[1]);
      final cuts = List<double>.from(e.value)..sort((a, b) => b.compareTo(a));
      final plans = nestCutsToBars(cutsMm: cuts, stockLengthMm: p.stockLengthMm, sawKerfMm: p.sawKerfMm);
      for (var i = 0; i < plans.length; i++) {
        final b = plans[i];
        for (var j = 0; j < b.piecesMm.length; j++) {
          buf.writeln([
            csvQuote(projectName),
            csvQuote(p.materialGroup),
            p.stockLengthMm.toStringAsFixed(0),
            p.sawKerfMm.toStringAsFixed(1),
            d.toStringAsFixed(1),
            w.toStringAsFixed(1),
            i + 1,
            j + 1,
            b.piecesMm[j].toStringAsFixed(0),
            b.remainingMm.toStringAsFixed(0),
          ].join(';'));
        }
      }
    }
    return buf.toString();
  }

  Future<void> _share(BuildContext context, Project p) async {
    // P1-44: shared re-entrancy guard with _copyCsv — a frantic double-tap on
    // the share IconButton (gloves + flaky touchscreen) otherwise lands two
    // SnackBars and writes the clipboard twice.
    if (_copyInFlight) return;
    _copyInFlight = true;
    try {
      final text = _buildTextSummary(p);
      await Clipboard.setData(ClipboardData(text: text));
      await Haptic.copied();
      if (_disposed || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr(pl: 'Skopiowano do schowka', en: 'Copied to clipboard')),
          backgroundColor: _kGreen,
        ),
      );
    } finally {
      _copyInFlight = false;
    }
  }

  Future<void> _copyCsv(BuildContext context, Project p) async {
    if (_copyInFlight) return;
    _copyInFlight = true;
    try {
      final csv = _buildCsv(p, context);
      await Clipboard.setData(ClipboardData(text: csv));
      await Haptic.copied();
      if (_disposed || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr(pl: 'CSV w schowku — wklej do Excela', en: 'CSV in clipboard — paste into Excel')),
          backgroundColor: _kBlue,
        ),
      );
    } finally {
      _copyInFlight = false;
    }
  }
}

// ── _LoadErrorView ─────────────────────────────────────────────────────────
// P1-44: replaces the silent wedged spinner / blank screen when `_load` blows
// up (DB locked, sqflite migration race) with an explicit Retry CTA so the
// welder doesn't conclude the app is bricked.
class _LoadErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _LoadErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _kRed),
            const SizedBox(height: 12),
            Text(
              context.tr(
                pl: 'Nie udało się wczytać planu cięcia',
                en: 'Failed to load cut plan',
              ),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8ECF0),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _kMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _kOrange),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(
                  context.tr(pl: 'Spróbuj ponownie', en: 'Try again'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Cached per-group nesting result: sorted cuts (desc) + computed bar plans.
// Built once in _load() so rebuilds don't re-sort or re-nest.
class _GroupPlan {
  final List<double> sortedCuts;
  final List<BarPlan> plans;
  const _GroupPlan({required this.sortedCuts, required this.plans});
}

// ── Nagłówek projektu ──────────────────────────────────────────────────────
class _ProjectHeader extends StatelessWidget {
  final Project project;
  const _ProjectHeader({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.checklist_rtl, size: 22, color: _kOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name?.isNotEmpty == true ? project.name! : 'CUT LIST',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                    pl: '${project.materialGroup}  ·  Sztanga: ${project.stockLengthMm.toStringAsFixed(0)} mm  ·  Kerf: ${project.sawKerfMm.toStringAsFixed(1)} mm',
                    en: '${project.materialGroup}  ·  Stock: ${project.stockLengthMm.toStringAsFixed(0)} mm  ·  Kerf: ${project.sawKerfMm.toStringAsFixed(1)} mm',
                  ),
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Podsumowanie zbiorcze ──────────────────────────────────────────────────
class _GlobalSummary extends StatelessWidget {
  final Map<String, List<double>> groups;
  final Project project;
  const _GlobalSummary({required this.groups, required this.project});

  @override
  Widget build(BuildContext context) {
    int totalBars = 0;
    double totalCutMm = 0;
    double totalWasteMm = 0;

    for (final e in groups.entries) {
      final cuts = List<double>.from(e.value);
      final plans = nestCutsToBars(
        cutsMm: cuts,
        stockLengthMm: project.stockLengthMm,
        sawKerfMm: project.sawKerfMm,
      );
      totalBars += plans.length;
      for (final b in plans) {
        totalCutMm += b.piecesMm.fold(0, (s, v) => s + v);
        totalWasteMm += b.remainingMm;
      }
    }

    final totalMaterialMm = totalBars * project.stockLengthMm;
    final wastePct = totalMaterialMm > 0 ? (totalWasteMm / totalMaterialMm * 100) : 0.0;
    final wasteColor = wastePct < 10 ? _kGreen : (wastePct < 25 ? _kOrange : _kRed);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(pl: 'Podsumowanie', en: 'Summary'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryStatBox(
                value: '$totalBars',
                label: context.tr(pl: 'Sztangi', en: 'Bars'),
                color: _kOrange,
                icon: Icons.horizontal_rule,
              ),
              const SizedBox(width: 10),
              _SummaryStatBox(
                value: '${(totalCutMm / 1000).toStringAsFixed(2)} m',
                label: context.tr(pl: 'Rura netto', en: 'Net pipe'),
                color: _kBlue,
                icon: Icons.straighten,
              ),
              const SizedBox(width: 10),
              _SummaryStatBox(
                value: '${wastePct.toStringAsFixed(1)}%',
                label: context.tr(pl: 'Odpad', en: 'Waste'),
                color: wasteColor,
                icon: Icons.recycling,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStatBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _SummaryStatBox({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: _kMuted)),
          ],
        ),
      ),
    );
  }
}

// ── Grupa rury (jedna średnica/ścianka) ────────────────────────────────────
class _PipeGroup extends StatelessWidget {
  final double diameterMm;
  final double wallMm;
  final String materialGroup;
  final List<double> cuts;
  final List<BarPlan> plans;
  final double stockLengthMm;
  final double sawKerfMm;

  const _PipeGroup({
    required this.diameterMm,
    required this.wallMm,
    required this.materialGroup,
    required this.cuts,
    required this.plans,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });

  /// ASME/ISO line-list shorthand a fitter would paint on the pipe end:
  /// `<OD>-<MAT>-<WALL>` (e.g. 168-CS-7.1). Matches the dash-tag
  /// convention used on piping line lists and ISO drawings so the cut
  /// list group is unambiguous across mixed-material projects.
  ///
  /// P1-38: defensive RFC 4180 quoting when `materialGroup` happens to
  /// contain a space, comma or quote — keeps the tag stable when copied
  /// into a CSV cell or a foreman's spreadsheet.
  String _lineTag() {
    final raw = '${diameterMm.toStringAsFixed(0)}-$materialGroup-${wallMm.toStringAsFixed(1)}';
    return csvQuote(raw);
  }

  @override
  Widget build(BuildContext context) {
    final totalWaste = plans.fold<double>(0, (s, b) => s + b.remainingMm);
    final totalNet   = cuts.fold<double>(0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nagłówek grupy
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.oil_barrel_outlined, size: 18, color: _kOrange),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr(
                  pl: 'Rura  Ø${diameterMm.toStringAsFixed(1)} × ${wallMm.toStringAsFixed(1)} mm',
                  en: 'Pipe  Ø${diameterMm.toStringAsFixed(1)} × ${wallMm.toStringAsFixed(1)} mm',
                ),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
              ),
            ),
            // ASME line-tag chip: short pipe ID a fitter writes on the cut end.
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22263A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                _lineTag(),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFFE8ECF0),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Text(
              // P1-38: pluralBars centralises the PL `1/2-4/5+` rule so the
              // same `${n} szt.` shorthand here matches the `_GlobalSummary`
              // box; EN cleanly toggles bar/bars.
              pluralBars(plans.length, context),
              style: const TextStyle(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Lista odcinków do cięcia
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // P1-38: pluralPieces centralises PL odcinek/odcinki/odcinków
                // so the inline `szt.` shorthand follows the same rule as
                // pluralBars. EN folds to "1 piece" / "N pieces" — natural
                // for both header and parenthetical use.
                pluralPieces(cuts.length, context),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: cuts.map((c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22263A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text('${c.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 12, color: Color(0xFFE8ECF0))),
                )).toList(),
              ),
              const Divider(height: 20, color: _kBorder),
              Text(
                context.tr(
                  pl: 'Netto: ${(totalNet / 1000).toStringAsFixed(3)} m  ·  Odpad: ${totalWaste.toStringAsFixed(0)} mm',
                  en: 'Net: ${(totalNet / 1000).toStringAsFixed(3)} m  ·  Waste: ${totalWaste.toStringAsFixed(0)} mm',
                ),
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Sztangi
        ...List.generate(plans.length, (i) => _BarCard(
          index: i,
          plan: plans[i],
          stockLengthMm: stockLengthMm,
          sawKerfMm: sawKerfMm,
        )),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Karta sztangi z wizualizacją paskową ───────────────────────────────────
class _BarCard extends StatelessWidget {
  final int index;
  final BarPlan plan;
  final double stockLengthMm;
  final double sawKerfMm;

  const _BarCard({
    required this.index,
    required this.plan,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });

  @override
  Widget build(BuildContext context) {
    final usedMm = plan.piecesMm.fold<double>(0, (s, v) => s + v) + plan.cutsCount * sawKerfMm;
    final wastePct = stockLengthMm > 0 ? plan.remainingMm / stockLengthMm : 0.0;
    final wasteColor = wastePct < 0.10 ? _kGreen : (wastePct < 0.25 ? _kOrange : _kRed);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr(pl: 'Sztanga ${index + 1}', en: 'Bar ${index + 1}'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kOrange),
              ),
              const Spacer(),
              Text(
                '${usedMm.toStringAsFixed(0)} / ${stockLengthMm.toStringAsFixed(0)} mm',
                style: const TextStyle(fontSize: 11, color: _kMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Pasek wizualny sztangi
          _BarVisual(plan: plan, stockLengthMm: stockLengthMm, sawKerfMm: sawKerfMm),
          const SizedBox(height: 8),

          // Odcinki
          Text(
            plan.piecesMm.map((x) => x.toStringAsFixed(0)).join('  +  '),
            style: const TextStyle(fontSize: 13, color: Color(0xFFE8ECF0), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                context.tr(
                  pl: 'Cięcia: ${plan.cutsCount}  ·  Zostaje: ${plan.remainingMm.toStringAsFixed(0)} mm',
                  en: 'Cuts: ${plan.cutsCount}  ·  Remaining: ${plan.remainingMm.toStringAsFixed(0)} mm',
                ),
                style: TextStyle(fontSize: 11, color: wasteColor),
              ),
              if (plan.remainingMm > 200) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    context.tr(pl: 'nadaje się na spady', en: 'usable offcut'),
                    style: const TextStyle(fontSize: 10, color: _kGreen),
                  ),
                ),
              ],
            ],
          ),
          // P1-28: long-press-to-copy hint per result card. Surfaces the
          // discoverable gesture so a foreman scanning the cut list knows the
          // piece-mm row is copyable to the saw operator without scrolling
          // back up to the AppBar "share" IconButton. Keeps the hint at 10pt
          // muted to avoid competing with the actual numbers.
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 11,
                color: _kMuted.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                context.tr(
                  pl: 'Przytrzymaj aby skopiować',
                  en: 'Long-press to copy',
                ),
                style: TextStyle(
                  fontSize: 10,
                  color: _kMuted.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Wizualizacja paskowa sztangi ───────────────────────────────────────────
class _BarVisual extends StatelessWidget {
  final BarPlan plan;
  final double stockLengthMm;
  final double sawKerfMm;

  const _BarVisual({
    required this.plan,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });

  @override
  Widget build(BuildContext context) {
    // Kolory dla kolejnych odcinków
    const pieceColors = [
      Color(0xFFF5A623),
      Color(0xFF4A9EFF),
      Color(0xFF2ECC71),
      Color(0xFFAB47BC),
      Color(0xFFE74C3C),
      Color(0xFF26C6DA),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;

      return SizedBox(
        height: 24,
        child: Row(
          children: [
            ...List.generate(plan.piecesMm.length, (i) {
              final piecePct = plan.piecesMm[i] / stockLengthMm;
              final kerfPct  = sawKerfMm / stockLengthMm;
              final color = pieceColors[i % pieceColors.length];

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Odcinek
                  Container(
                    width: (totalWidth * piecePct).clamp(4.0, totalWidth),
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Kerf (cięcie piłą)
                  if (i < plan.piecesMm.length - 1 || plan.remainingMm > 0)
                    Container(
                      width: (totalWidth * kerfPct).clamp(2.0, 6.0),
                      height: 24,
                      color: const Color(0xFF0F1117),
                    ),
                ],
              );
            }),
            // Odpad
            if (plan.remainingMm > 0)
              Expanded(
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C3354),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: plan.remainingMm > 300
                      ? Center(
                          child: Text(
                            plan.remainingMm.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 9, color: _kMuted),
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
      );
    });
  }
}
