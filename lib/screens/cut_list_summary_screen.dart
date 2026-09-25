import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../models/segment.dart';
import '../services/bar_nesting.dart';
import '../services/cut_list_csv.dart';
import '../services/cut_list_summary.dart';
import '../services/pdf_export_service.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';
import '../theme/app_theme.dart' show kTextMut;

// csvQuote moved to services/cut_list_csv.dart; re-exported so existing
// imports of this screen keep working.
export '../services/cut_list_csv.dart' show csvQuote;

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

const _kOrange = Color(0xFFFF8E1E);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kBlue   = Color(0xFF4A9EFF);
const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kMuted  = kTextMut;
// Split cuts (longer than a stock bar) — amber, distinct from the orange
// brand accent so the extra-weld warning does not read as decoration.
const _kWarn   = Color(0xFFFFC107);
const _kText   = Color(0xFFE7ECF3);
// Segment tag on a dark chip: light enough for sunlight, quieter than the mm.
const _kTag    = Color(0xFFAAB4C8);

/// What the share/copy menu in the AppBar can do.
enum _ShareAction { csvFile, text, copyCsv, copyText }

class CutListSummaryScreen extends StatefulWidget {
  final String projectId;
  const CutListSummaryScreen({super.key, required this.projectId});

  @override
  State<CutListSummaryScreen> createState() => _CutListSummaryScreenState();
}

class _CutListSummaryScreenState extends State<CutListSummaryScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();
  // Anchor for the iPad share popover (the share menu button).
  final _shareButtonKey = GlobalKey();
  Project? _project;
  List<Segment> _segments = [];
  // Single nesting result shared by the global summary box and the group
  // cards. Built with summarizeCutList — the same function the PDF export
  // and the CSV use — so the screen, the PDF and the CSV can never disagree
  // on bars, waste or which segment sits on which bar.
  // Recomputed only in _load() so rebuilds don't re-run the nesting.
  CutListSummary? _summary;
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
  // P1-44: single re-entrancy guard for every share/copy action so a frantic
  // double-tap (gloves + flaky touchscreen) doesn't push two share sheets,
  // two clipboard writes or two snackbars on top of each other.
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

      final summary = p == null
          ? null
          : summarizeCutList(
              segments: segs,
              stockLengthMm: p.stockLengthMm,
              sawKerfMm: p.sawKerfMm,
            );

      if (gen != _loadGen || !mounted) return;
      setState(() {
        _project    = p;
        _segments   = segs;
        _summary    = summary;
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

  bool get _english => context.language == AppLanguage.en;

  /// Project name for exports; short id when the project has no name.
  static String _projectTitle(Project p) {
    final name = p.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return p.id.length > 8 ? p.id.substring(0, 8) : p.id;
  }

  /// Screen rect of the share button — iPad needs it to anchor the share
  /// popover (without it the share sheet throws on iPad).
  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
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
    final english = _english;
    await Haptic.tap();
    if (!mounted) return;
    setState(() => _exporting = true);
    try {
      await PdfExportService.exportCutList(
        project: p,
        segments: segsSnapshot,
        english: english,
        sharePositionOrigin: _shareOrigin(),
      );
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
    // P1-44: signal in-flight _exportPdf / share / copy actions to bail
    // before they call setState on this dead State.
    _disposed = true;
    _loadGen++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    final summary = _summary;
    final hasPlan = summary != null && summary.groups.isNotEmpty;
    // P1-28: gate every export action on having BOTH a non-empty cut plan and
    // not being mid-export. _exporting separately drives the spinner swap
    // below, but disabled state is shared so a queued-render second tap on
    // the share menu can't slip through while PDF is writing.
    final exportsEnabled = !_exporting && hasPlan && _segments.isNotEmpty;
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
            // The share icon SHARES: CSV as a file or the plan as text via the
            // OS share sheet; copying to the clipboard sits next to it in the
            // same menu.
            PopupMenuButton<_ShareAction>(
              key: _shareButtonKey,
              icon: const Icon(Icons.share_outlined),
              tooltip: context.tr(pl: 'Udostępnij / kopiuj', en: 'Share / copy'),
              enabled: exportsEnabled,
              onSelected: (a) => _onShareAction(a, p),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ShareAction.csvFile,
                  child: ListTile(
                    leading: const Icon(Icons.table_view_outlined),
                    title: Text(context.tr(pl: 'Udostępnij plik CSV', en: 'Share CSV file')),
                    subtitle: Text(context.tr(pl: 'Excel, e-mail, komunikator', en: 'Excel, e-mail, messenger')),
                  ),
                ),
                PopupMenuItem(
                  value: _ShareAction.text,
                  child: ListTile(
                    leading: const Icon(Icons.send_outlined),
                    title: Text(context.tr(pl: 'Udostępnij jako tekst', en: 'Share as text')),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _ShareAction.copyCsv,
                  child: ListTile(
                    leading: const Icon(Icons.copy_all_outlined),
                    title: Text(context.tr(pl: 'Kopiuj CSV', en: 'Copy CSV')),
                  ),
                ),
                PopupMenuItem(
                  value: _ShareAction.copyText,
                  child: ListTile(
                    leading: const Icon(Icons.content_copy_outlined),
                    title: Text(context.tr(pl: 'Kopiuj tekst', en: 'Copy text')),
                  ),
                ),
              ],
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

                    if (!hasPlan)
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
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kText),
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
                      CutListGlobalSummary(summary: summary),
                      const SizedBox(height: 12),

                      // ── OSTRZEŻENIE: ODCINEK DŁUŻSZY NIŻ SZTANGA ──────
                      if (summary.splitCuts.isNotEmpty) ...[
                        CutListOversizeWarning(
                          summary: summary,
                          stockLengthMm: p.stockLengthMm,
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),

                      // ── GRUPY RURY ────────────────────────────────────
                      ...summary.groups.map((g) {
                        return CutListPipeGroup(
                          group: g,
                          materialGroup: p.materialGroup,
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
    return buildCutListText(
      projectName: _projectTitle(p),
      materialGroup: p.materialGroup,
      stockLengthMm: p.stockLengthMm,
      sawKerfMm: p.sawKerfMm,
      summary: _summary ??
          summarizeCutList(
            segments: _segments,
            stockLengthMm: p.stockLengthMm,
            sawKerfMm: p.sawKerfMm,
          ),
      english: _english,
      identity: p.identity,
    );
  }

  /// CSV with one row per cut piece — drops straight into an Excel column on
  /// the workshop laptop or into a foreman's spreadsheet.
  ///
  /// P1-38: header localisation + RFC 4180 quoting. The row format lives in
  /// [buildCutListCsv] (services/cut_list_csv.dart) so it is testable without
  /// a widget tree; this method only picks the language.
  String _buildCsv(Project p) {
    return buildCutListCsv(
      projectName: _projectTitle(p),
      materialGroup: p.materialGroup,
      stockLengthMm: p.stockLengthMm,
      sawKerfMm: p.sawKerfMm,
      segments: _segments,
      english: _english,
      identity: p.identity,
    );
  }

  Future<void> _onShareAction(_ShareAction action, Project p) async {
    // P1-44: shared re-entrancy guard — see _copyInFlight.
    if (_copyInFlight) return;
    _copyInFlight = true;
    // Resolved before any await: the snackbars below run after async gaps.
    final csvCopied = context.tr(
      pl: 'CSV w schowku — wklej do Excela',
      en: 'CSV in clipboard — paste into Excel',
    );
    final textCopied =
        context.tr(pl: 'Skopiowano do schowka', en: 'Copied to clipboard');
    try {
      switch (action) {
        case _ShareAction.csvFile:
          final csv = _buildCsv(p);
          await Haptic.tap();
          await shareCutListCsvFile(
            csv: csv,
            projectName: _projectTitle(p),
            sharePositionOrigin: _shareOrigin(),
          );
        case _ShareAction.text:
          final text = _buildTextSummary(p);
          await Haptic.tap();
          await Share.share(
            text,
            subject: 'CUT LIST — ${_projectTitle(p)}',
            sharePositionOrigin: _shareOrigin(),
          );
        case _ShareAction.copyCsv:
          await Clipboard.setData(ClipboardData(text: _buildCsv(p)));
          await Haptic.copied();
          _snack(csvCopied, _kBlue);
        case _ShareAction.copyText:
          await Clipboard.setData(ClipboardData(text: _buildTextSummary(p)));
          await Haptic.copied();
          _snack(textCopied, _kGreen);
      }
    } catch (e, st) {
      debugPrint('[CutListSummary] share/copy failed: $e\n$st');
      if (_disposed || !mounted) return;
      await Haptic.error();
      if (_disposed || !mounted) return;
      _snack(
        context.tr(pl: 'Nie udało się udostępnić: $e', en: 'Sharing failed: $e'),
        _kRed,
      );
    } finally {
      _copyInFlight = false;
    }
  }

  void _snack(String text, Color color) {
    if (_disposed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
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
                color: _kText,
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

// ── Nagłówek projektu ──────────────────────────────────────────────────────
class _ProjectHeader extends StatelessWidget {
  final Project project;
  const _ProjectHeader({required this.project});

  @override
  Widget build(BuildContext context) {
    final identity = project.identity
        .summary(english: context.language == AppLanguage.en);
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kText),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                    pl: '${project.materialGroup}  ·  Sztanga: ${project.stockLengthMm.toStringAsFixed(0)} mm  ·  Kerf: ${project.sawKerfMm.toStringAsFixed(1)} mm',
                    en: '${project.materialGroup}  ·  Stock: ${project.stockLengthMm.toStringAsFixed(0)} mm  ·  Kerf: ${project.sawKerfMm.toStringAsFixed(1)} mm',
                  ),
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
                // Line / ISO + revision / client / class (schema v22) — what
                // QC and the foreman identify the job by.
                if (identity.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    identity,
                    style: const TextStyle(fontSize: 12, color: _kText),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Podsumowanie zbiorcze ──────────────────────────────────────────────────
/// Global totals box (bars, net pipe, waste). Reads everything from a
/// [CutListSummary] — the same object the PDF header uses — so the numbers on
/// screen always match the group cards below and the exported PDF.
class CutListGlobalSummary extends StatelessWidget {
  final CutListSummary summary;
  const CutListGlobalSummary({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final totalBars = summary.totalBars;
    final totalCutMm = summary.totalNetMm;
    final wastePct = summary.wastePct;
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

// ── Ostrzeżenie: odcinek dłuższy niż sztanga ───────────────────────────────
/// Lists every cut that is longer than a stock bar. The nesting splits such a
/// cut into full bars + remainder; the parts have to be joined by an extra
/// weld, and that weld's gap has to come off the pieces — the fitter must see
/// this before the saw, not discover it at fit-up.
class CutListOversizeWarning extends StatelessWidget {
  final CutListSummary summary;
  final double stockLengthMm;

  const CutListOversizeWarning({
    super.key,
    required this.summary,
    required this.stockLengthMm,
  });

  @override
  Widget build(BuildContext context) {
    final english = context.language == AppLanguage.en;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kWarn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kWarn.withValues(alpha: 0.8), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kWarn, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    pl: 'Odcinek dłuższy niż sztanga',
                    en: 'Piece longer than the stock bar',
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _kWarn),
                ),
                const SizedBox(height: 4),
                for (final piece in summary.splitCuts)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      oversizeCutWarning(
                        piece,
                        stockLengthMm: stockLengthMm,
                        english: english,
                      ),
                      style: const TextStyle(fontSize: 12, color: _kText, height: 1.3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Grupa rury (jedna średnica/ścianka) ────────────────────────────────────
/// One diameter/wall group: list of pieces to cut (with segment tags) and a
/// card per stock bar.
class CutListPipeGroup extends StatelessWidget {
  final CutListGroup group;
  final String materialGroup;
  final double stockLengthMm;
  final double sawKerfMm;

  const CutListPipeGroup({
    super.key,
    required this.group,
    required this.materialGroup,
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
    final raw = '${group.diameterMm.toStringAsFixed(0)}-$materialGroup-${group.wallMm.toStringAsFixed(1)}';
    return csvQuote(raw);
  }

  @override
  Widget build(BuildContext context) {
    final plans = group.plans;
    final cuts = group.cutsMm;
    // Older callers may hand a group without labelled pieces.
    final pieces = group.pieces.length == cuts.length
        ? group.pieces
        : [for (final c in cuts) CutRequest(c)];
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
                  pl: 'Rura  Ø${group.diameterMm.toStringAsFixed(1)} × ${group.wallMm.toStringAsFixed(1)} mm',
                  en: 'Pipe  Ø${group.diameterMm.toStringAsFixed(1)} × ${group.wallMm.toStringAsFixed(1)} mm',
                ),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kText),
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
                  color: _kText,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Text(
              // P1-38: pluralBars centralises the PL `1/2-4/5+` rule so the
              // same `${n} szt.` shorthand here matches the global summary
              // box; EN cleanly toggles bar/bars.
              pluralBars(plans.length, context),
              style: const TextStyle(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Lista odcinków do cięcia — each chip names its segment, so the
        // piece on the saw can be traced back to the drawing.
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
                children: [
                  for (final piece in pieces)
                    _PieceChip(
                      label: piece.label,
                      reference: piece.reference,
                      lengthMm: piece.lengthMm,
                      oversize: piece.lengthMm > stockLengthMm,
                    ),
                ],
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

/// `S03  3293 mm` chip; amber frame + split icon when the cut is longer than
/// a stock bar.
class _PieceChip extends StatelessWidget {
  final String? label;

  /// Segment's ISO expression — shown on long-press (tooltip), so the piece
  /// can be matched to the drawing dimension without leaving the cut list.
  final String? reference;
  final double lengthMm;
  final bool oversize;

  const _PieceChip({
    required this.label,
    required this.reference,
    required this.lengthMm,
    required this.oversize,
  });

  @override
  Widget build(BuildContext context) {
    final chip = _chip();
    final ref = reference;
    if (ref == null) return chip;
    return Tooltip(message: 'ISO: $ref', child: chip);
  }

  Widget _chip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF22263A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oversize ? _kWarn : _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (oversize) ...[
            const Icon(Icons.call_split, size: 13, color: _kWarn),
            const SizedBox(width: 4),
          ],
          if (label != null) ...[
            Text(label!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kTag)),
            const SizedBox(width: 5),
          ],
          Text('${lengthMm.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 12, color: _kText)),
        ],
      ),
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

  String _copyText(BuildContext context) {
    final rest = plan.remainingMm.toStringAsFixed(0);
    return context.tr(
      pl: 'Sztanga ${index + 1}: ${formatBarPieces(plan)} (zostaje $rest mm)',
      en: 'Bar ${index + 1}: ${formatBarPieces(plan)} (remaining $rest mm)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final usedMm = plan.piecesMm.fold<double>(0, (s, v) => s + v) + plan.cutsCount * sawKerfMm;
    final wastePct = stockLengthMm > 0 ? plan.remainingMm / stockLengthMm : 0.0;
    final wasteColor = wastePct < 0.10 ? _kGreen : (wastePct < 0.25 ? _kOrange : _kRed);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: plan.hasSplitPiece ? _kWarn.withValues(alpha: 0.7) : _kBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // P1-28: the card has always said "long-press to copy" — this is
          // what makes it true. Copies the bar with segment tags, ready to
          // paste to the saw operator.
          onLongPress: () => copyToClipboard(context, _copyText(context)),
          child: Padding(
            padding: const EdgeInsets.all(12),
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

                // Odcinki: segment tag + mm for every piece on this bar.
                Text.rich(
                  TextSpan(children: [
                    for (var i = 0; i < plan.pieces.length; i++) ...[
                      if (i > 0)
                        const TextSpan(text: '  +  ', style: TextStyle(color: _kMuted)),
                      if (plan.pieces[i].tag != null)
                        TextSpan(
                          text: '${plan.pieces[i].tag} ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: plan.pieces[i].isSplit ? _kWarn : _kTag,
                          ),
                        ),
                      TextSpan(
                        text: plan.pieces[i].lengthMm.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kText),
                      ),
                    ],
                  ]),
                ),
                if (plan.hasSplitPiece) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.call_split, size: 13, color: _kWarn),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          context.tr(
                            pl: 'Część odcinka dłuższego niż sztanga — dodatkowa spoina łącząca, uwzględnij gap',
                            en: 'Part of a piece longer than the bar — extra joining weld, allow for the gap',
                          ),
                          style: const TextStyle(fontSize: 11, color: _kWarn),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      context.tr(
                        pl: 'Cięcia: ${plan.cutsCount}  ·  Zostaje: ${plan.remainingMm.toStringAsFixed(0)} mm',
                        en: 'Cuts: ${plan.cutsCount}  ·  Remaining: ${plan.remainingMm.toStringAsFixed(0)} mm',
                      ),
                      style: TextStyle(fontSize: 11, color: wasteColor),
                    ),
                    if (plan.remainingMm > 200)
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
                ),
                // P1-28: long-press-to-copy hint per result card. Surfaces the
                // discoverable gesture so a foreman scanning the cut list knows the
                // piece-mm row is copyable to the saw operator without scrolling
                // back up to the AppBar share menu. Keeps the hint at 10pt
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
          ),
        ),
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
      Color(0xFFFF8E1E),
      Color(0xFF4A9EFF),
      Color(0xFF2ECC71),
      Color(0xFFAB47BC),
      Color(0xFFE74C3C),
      Color(0xFF26C6DA),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;
      final n = plan.piecesMm.length;
      final kerfPct = stockLengthMm > 0 ? sawKerfMm / stockLengthMm : 0.0;

      // Minimum widths keep a short piece and every saw cut visible, but on a
      // narrow phone with many short pieces those minimums used to add up
      // past the bar and overflow the row. Scale the fixed widths down when
      // they do not fit.
      final pieceWidths = [
        for (final mm in plan.piecesMm)
          (totalWidth * (stockLengthMm > 0 ? mm / stockLengthMm : 0))
              .clamp(4.0, totalWidth),
      ];
      final hasKerf = [
        for (var i = 0; i < n; i++) i < n - 1 || plan.remainingMm > 0,
      ];
      final kerfWidth = (totalWidth * kerfPct).clamp(2.0, 6.0);
      final fixed = pieceWidths.fold<double>(0, (s, w) => s + w) +
          hasKerf.where((k) => k).length * kerfWidth;
      final scale = fixed > totalWidth && fixed > 0 ? totalWidth / fixed : 1.0;

      return SizedBox(
        height: 24,
        child: Row(
          children: [
            ...List.generate(n, (i) {
              final color = pieceColors[i % pieceColors.length];

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Odcinek
                  Container(
                    width: pieceWidths[i] * scale,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Kerf (cięcie piłą)
                  if (hasKerf[i])
                    Container(
                      width: kerfWidth * scale,
                      height: 24,
                      color: const Color(0xFF0B0E13),
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
                    color: const Color(0xFF2A3140),
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
