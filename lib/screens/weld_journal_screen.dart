// Weld journal (weld log / weld map) — the list screen.
//
// The model, numbering, filter, history, statistics and storage live in
// lib/domain/weld_journal/ and lib/database/weld_journal_dao.dart; the weld
// card and the sheets in lib/widgets/weld_journal/. This file wires them
// together. What changed for the inspector (schema v20):
//   * every change is logged (who — welder stamp, when, field, old → new),
//     deleting is soft and reversible, and the status changes only through
//     an explicit, confirmed choice — the badge no longer cycles on a tap;
//   * NDT per method, repairs R1/R2 keeping the previous result, PWHT,
//     acceptance, and a summary with the B31.3 §341.3.4 counter;
//   * filters by project, line/ISO, welder, dates, status and NDT — and the
//     CSV/PDF export is exactly the visible set;
//   * natural weld-number order, prefix-preserving number suggestion and a
//     duplicate warning; "next weld" and remembered values for gloved hands.
// v25 (quality documentation):
//   * document consistency (status / acceptance vs NDT, dates, PWHT, coupon)
//     is a badge on the list and an explicit warning on a status change;
//   * the coupon link is live — a NOK or deleted coupon shows on the tile;
//   * compliance uses the WPS content in force on the weld date;
//   * the PDF carries the QC remarks ("saved despite warnings") and the
//     change history as an appendix;
//   * a banner asks for the welder stamp when none is set (after a restore).
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/coupon_dao.dart';
import '../database/weld_journal_dao.dart';
import '../database/wps_dao.dart';
import '../domain/weld_journal/coupon_entry.dart';
import '../domain/weld_journal/weld_consistency.dart';
import '../domain/weld_journal/weld_history.dart';
import '../domain/qualification/certificate_status.dart' show JournalWeld;
import '../domain/weld_journal/weld_compliance.dart';
import '../domain/weld_journal/weld_dates.dart';
import '../domain/weld_journal/weld_defaults.dart';
import '../domain/weld_journal/weld_entry.dart';
import '../domain/weld_journal/weld_filter.dart';
import '../domain/weld_journal/weld_journal_settings.dart';
import '../domain/weld_journal/weld_numbering.dart';
import '../domain/weld_journal/weld_stats.dart';
import '../i18n/app_language.dart';
import '../services/weld_journal_export.dart';
import '../services/welder_identity.dart';
import '../services/welder_qualification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/help_button.dart';
import 'welder_identity_setup_screen.dart';
import '../widgets/weld_journal/weld_compliance_view.dart';
import '../widgets/weld_journal/weld_editor_sheet.dart';
import '../widgets/weld_journal/weld_filter_sheet.dart';
import '../widgets/weld_journal/weld_history_view.dart';
import '../widgets/weld_journal/weld_repair_dialog.dart';
import '../widgets/weld_journal/weld_settings_sheet.dart';
import '../widgets/weld_journal/weld_status_dialog.dart';
import '../widgets/weld_journal/weld_summary_sheet.dart';
import '../widgets/weld_journal/wj_ui.dart';

// Kept importable from here: tests and the backup restore reach the journal
// model, filter, DAO and last-project helpers through this screen's library.
export '../database/weld_journal_dao.dart' show WeldJournalDao;
export '../domain/weld_journal/weld_defaults.dart'
    show kLastWeldProjectPrefsKey, loadLastWeldProject, saveLastWeldProject;
export '../domain/weld_journal/weld_entry.dart';
export '../domain/weld_journal/weld_filter.dart';

// Locale-aware decimal separator for stored numeric strings (OD, t).
String _localizedNum(String raw) => AppLanguageController.isEnglish
    ? raw.replaceAll(',', '.')
    : raw.replaceAll('.', ',');

class WeldJournalScreen extends StatefulWidget {
  const WeldJournalScreen({super.key});
  @override
  State<WeldJournalScreen> createState() => _WeldJournalScreenState();
}

class _WeldJournalScreenState extends State<WeldJournalScreen> {
  static const _uuid = Uuid();
  final _dao = WeldJournalDao();
  final _settingsDao = WeldJournalSettingsDao();

  /// Every entry, soft-deleted included, in natural weld-number order.
  List<WeldEntry> _entries = [];
  Map<String, WeldJournalProjectSettings> _settings = const {};

  /// WPS / qualification check per weld id (live welds only). Empty when the
  /// WPS library and the qualification register are both empty — nothing to
  /// check, nothing to show.
  Map<String, WeldCompliance> _compliance = const {};

  /// Coupon log rows by id (deleted included) — the live coupon link.
  /// `null` when the log could not be read.
  Map<String, CouponEntry>? _coupons;
  WeldJournalFilter _filter = const WeldJournalFilter();
  String _lastWeldId = '';
  bool _loading = true;
  bool _exporting = false;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  /// Stamp recorded as "who" in the history.
  String get _stamp => WelderIdentityService.instance.current?.stamp ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    // Hydrates the identity cache so the stamp is there for the first save.
    WelderIdentityService.instance.get().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      debugPrint('[weld_journal] identity load failed: $e');
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // Log kuponów czytany równolegle z dziennikiem (bez dodatkowego
      // czekania na liście).
      final couponsFuture = CouponDao()
          .listAll(includeDeleted: true)
          .then<List<CouponEntry>?>((v) => v, onError: (Object e) {
        debugPrint('[weld_journal] coupon log load failed: $e');
        return null;
      });
      final all = await _dao.listAll();
      var settings = const <String, WeldJournalProjectSettings>{};
      try {
        settings = await _settingsDao.listAll();
      } catch (e) {
        debugPrint('[weld_journal] settings load failed: $e');
      }
      final defaults = await loadWeldDefaults();
      final compliance = await _assess(all);
      final couponList = await couponsFuture;
      final coupons =
          couponList == null ? null : {for (final c in couponList) c.id: c};
      if (!mounted) return;
      setState(() {
        _entries = all;
        _settings = settings;
        _compliance = compliance;
        _coupons = coupons;
        _lastWeldId = defaults.lastWeldId;
        _loading = false;
      });
    } catch (e) {
      // A locked DB or a half-applied migration used to strand the spinner
      // forever. Surface a retry instead.
      debugPrint('WeldJournal load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Nie udało się wczytać dziennika. Spróbuj ponownie.',
            'Failed to load journal. Try again.')),
        action: SnackBarAction(label: _tr('Ponów', 'Retry'), onPressed: _load),
      ));
    }
  }

  /// One read of the WPS library and the qualification register for the
  /// whole list. A failure only hides the badges.
  Future<Map<String, WeldCompliance>> _assess(List<WeldEntry> all) async {
    try {
      final wpsDao = WpsDao();
      final versionsFuture = wpsDao.versionsByWps();
      final certificatesFuture =
          WelderQualificationService.instance.listCertificates();
      final library = await wpsDao.listAll();
      final versions = await versionsFuture;
      final certificates = await certificatesFuture;
      if (library.isEmpty && certificates.isEmpty) return const {};
      final rows = [for (final e in all) e.toRow()];
      final cache = <String, List<JournalWeld>>{};
      final today = DateTime.now();
      return {
        for (final e in all)
          if (!e.isDeleted)
            e.id: assessWeldCompliance(
              entry: e,
              wpsLibrary: library,
              certificates: certificates,
              journalRows: rows,
              defaultStamp: _stamp,
              today: today,
              journalCache: cache,
              wpsVersions: versions,
            ),
      };
    } catch (e) {
      debugPrint('[weld_journal] compliance badges failed: $e');
      return const {};
    }
  }

  List<WeldEntry> get _visible => filterWeldEntries(_entries, _filter);

  /// Document-consistency issues of [e] (with the live coupon).
  List<WeldConsistencyIssue> _issuesOf(WeldEntry e) {
    final coupons = _coupons;
    return weldConsistencyIssues(e,
        coupon: coupons?[e.couponId],
        couponKnown: coupons != null,
        today: DateTime.now());
  }

  /// Most frequent stamp in the journal — a hint for the identity banner.
  String get _likelyStamp {
    final counts = <String, int>{};
    for (final e in _entries) {
      for (final s in e.stamps) {
        final k = s.toUpperCase();
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '';
    return (counts.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }

  Future<void> _openIdentity() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const WelderIdentitySetupScreen(),
    ));
    await WelderIdentityService.instance.get();
    if (mounted) await _load();
  }

  /// Everything the filter selects except the status — what the badges and
  /// the NDT summary count, so tapping a status chip does not zero them.
  List<WeldEntry> get _scope =>
      filterWeldEntries(_entries, _filter.copyWith(status: 'ALL'));

  List<String> _distinct(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in values) {
      final t = v.trim();
      if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
      out.add(t);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<String> get _journalProjects =>
      _distinct(_entries.map((e) => e.projectName));

  List<String> get _journalWelders =>
      _distinct(_entries.expand((e) => e.stamps));

  Map<String, double?> get _targets => {
        for (final s in _settings.entries) s.key: s.value.volumetricTargetPct,
      };

  WeldEntry? get _lastWeld {
    for (final e in _entries) {
      if (e.id == _lastWeldId && !e.isDeleted) return e;
    }
    return null;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final scope = _scope;
    var ok = 0, nok = 0, pending = 0;
    for (final e in scope) {
      switch (e.status) {
        case WeldStatus.ok:
          ok++;
        case WeldStatus.nok:
          nok++;
        case WeldStatus.pending:
          pending++;
      }
    }
    final stats = computeWeldJournalStats(scope, volumetricTargets: _targets);
    final describe = _filter
        .copyWith(status: 'ALL')
        .describe(en: AppLanguageController.isEnglish);
    final last = _lastWeld;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Dziennik spoin', 'Weld journal')),
        actions: [
          HelpButton(help: kHelpWeldJournal),
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: _tr('Eksport CSV (Excel)', 'Export CSV (Excel)'),
            onPressed: _exporting ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: _tr('Eksport PDF', 'Export PDF'),
            onPressed: _exporting ? null : _exportPdf,
          ),
          PopupMenuButton<String>(
            tooltip: _tr('Więcej', 'More'),
            onSelected: (v) => switch (v) {
              'new' => _newWeld(),
              'settings' => _openProjectSettings(),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'new',
                  child: Text(_tr('Nowa spoina (pusta)', 'New weld (blank)'))),
              PopupMenuItem(
                  value: 'settings',
                  child: Text(_tr('Ustawienia projektu (PDF, cel RT/UT)',
                      'Project settings (PDF, RT/UT target)'))),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_stamp.isEmpty && _entries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Material(
                      color: kWarn.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        key: const ValueKey('weld-journal-stamp-banner'),
                        leading: const Icon(Icons.badge_outlined, color: kWarn),
                        title: Text(
                          _tr(
                            'Ustaw stempel spawacza — bez niego ciągłość ASME '
                                'i autor zmian w historii nie działają.',
                            'Set your welder stamp — without it ASME '
                                'continuity and the change author do not work.',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: _likelyStamp.isEmpty
                            ? null
                            : Text(_tr(
                                'Najczęstszy w dzienniku: $_likelyStamp',
                                'Most frequent in the journal: '
                                    '$_likelyStamp')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openIdentity,
                      ),
                    ),
                  ),
                if (!_filter.deleted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Row(children: [
                      _StatBadge(
                          _tr('Razem', 'Total'), '${scope.length}', kTextSec),
                      const SizedBox(width: 8),
                      _StatBadge('OK', '$ok', kPass),
                      const SizedBox(width: 8),
                      _StatBadge('NOK', '$nok', kFail),
                      const SizedBox(width: 8),
                      _StatBadge(_tr('Oczekuje', 'Pending'), '$pending', kArc),
                    ]),
                  ),
                // Status chips + filters — every one ≥ 48 dp for gloves.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    for (final f in [
                      ('ALL', _tr('Wszystkie', 'All'), kArc),
                      (WeldStatus.ok, 'OK', kPass),
                      (WeldStatus.nok, 'NOK', kFail),
                      (WeldStatus.pending, _tr('Oczekuje', 'Pending'), kArc),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: WjChoiceChip(
                          label: f.$2,
                          color: f.$3,
                          selected: _filter.status == f.$1,
                          onTap: () => setState(
                              () => _filter = _filter.copyWith(status: f.$1)),
                        ),
                      ),
                    WjChoiceChip(
                      icon: Icons.filter_list,
                      label: _filter.extraFilterCount == 0
                          ? _tr('Filtry', 'Filters')
                          : '${_tr('Filtry', 'Filters')} '
                              '(${_filter.extraFilterCount})',
                      selected: _filter.extraFilterCount > 0,
                      onTap: _openFilters,
                    ),
                  ]),
                ),
                if (describe.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: Text(
                      describe,
                      style: const TextStyle(fontSize: 12, color: kArc),
                    ),
                  ),
                if (!_filter.deleted && scope.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                    child: InkWell(
                      onTap: () => showWeldSummarySheet(context,
                          stats: stats, scopeDescription: describe),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        constraints:
                            const BoxConstraints(minHeight: kMinTapTarget),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kBorder),
                        ),
                        child: Row(children: [
                          const Icon(Icons.analytics_outlined,
                              size: 18, color: kArc),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'NDT: ${weldStatsLine(context, stats)}',
                              style: const TextStyle(
                                  fontSize: 12, color: kTextSec),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: kTextSec),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _entries.isEmpty
                                  ? _tr('Brak spoin. Dotknij „Nowa spoina”.',
                                      'No welds. Tap "New weld".')
                                  : _tr('Żadna spoina nie pasuje do filtrów.',
                                      'No weld matches the filters.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: kTextMut),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(14, 0, 14,
                              88 + MediaQuery.viewPaddingOf(context).bottom),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final e = visible[i];
                            return _WeldTile(
                              entry: e,
                              compliance: _compliance[e.id],
                              issues: e.isDeleted ? const [] : _issuesOf(e),
                              onTap: () => _openEditor(e, isNew: false),
                              onStatusTap:
                                  e.isDeleted ? null : () => _changeStatus(e),
                              onAction: (a) => _onTileAction(e, a),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _filter.deleted
          ? null
          : FloatingActionButton.extended(
              onPressed: () => last == null ? _newWeld() : _nextAfter(last),
              icon: Icon(last == null ? Icons.add : Icons.skip_next),
              label: Text(last == null
                  ? _tr('Nowa spoina', 'New weld')
                  : '${_tr('Następna po', 'Next after')} ${last.weldNo}'),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
            ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _openFilters() async {
    final f = await showWeldFilterSheet(
      context,
      filter: _filter,
      projects: _journalProjects,
      welders: _journalWelders,
    );
    if (f != null && mounted) setState(() => _filter = f);
  }

  String? _projectIdFor(String projectName) {
    final key = projectName.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final e in _entries.reversed) {
      if (e.projectId != null && e.projectName.trim().toLowerCase() == key) {
        return e.projectId;
      }
    }
    return null;
  }

  /// A new weld pre-filled with the last used values (never an invented
  /// material) and the next number of the last project.
  Future<void> _newWeld() async {
    final defaults = await loadWeldDefaults();
    final project = _filter.project.isNotEmpty
        ? _filter.project
        : await loadLastWeldProject();
    if (!mounted) return;
    final e = newWeldFromDefaults(
      defaults,
      id: _uuid.v4(),
      weldNo: suggestNextWeldNo(_entries, projectName: project),
      date: isoDate(DateTime.now()),
      stamp: _stamp,
      projectName: project,
      projectId: _projectIdFor(project),
    );
    await _openEditor(e, isNew: true);
  }

  /// "Następna spoina": copies [prev] and increments its number; falls back
  /// to the project's next free number when that one is taken.
  Future<void> _nextAfter(WeldEntry prev) async {
    final inc = incrementWeldNo(prev.weldNo);
    final project = prev.projectName.trim().toLowerCase();
    // Taken = used in the project by any entry, deleted ones included.
    final taken = inc != null &&
        _entries.any((e) =>
            e.projectName.trim().toLowerCase() == project &&
            e.weldNo.trim().toUpperCase() == inc.toUpperCase());
    final weldNo = inc != null && !taken
        ? inc
        : suggestNextWeldNo(_entries, projectName: prev.projectName);
    final e = nextWeldFrom(prev,
        id: _uuid.v4(),
        weldNo: weldNo,
        date: isoDate(DateTime.now()),
        stamp: _stamp);
    await _openEditor(e, isNew: true);
  }

  Future<void> _openEditor(WeldEntry e, {required bool isNew}) async {
    final result = await showWeldEditor(
      context,
      initial: e,
      isNew: isNew,
      journal: _entries,
      journalProjects: _journalProjects,
      stamp: _stamp,
      dao: _dao,
    );
    if (!mounted || result == null) return;
    await _load();
    if (!mounted) return;
    if (result.next) await _nextAfter(result.saved);
  }

  Future<void> _changeStatus(WeldEntry e) async {
    final picked = await showWeldStatusDialog(context,
        weldNo: e.weldNo, current: e.status);
    if (picked == null || !mounted) return;
    // Status OK przy NDT NOK / badaniu bez wyniku / kuponie NOK itd. — jawne
    // ostrzeżenie; „Zmień mimo to” trafia do historii.
    final fresh = newConsistencyIssues(
        _issuesOf(e), _issuesOf(e.copyWith(status: picked)));
    String? warning;
    if (fresh.isNotEmpty) {
      final en = AppLanguageController.isEnglish;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_tr('Niespójny dokument odbiorowy',
              'Inconsistent acceptance record')),
          content: Text(fresh.map((i) => '• ${i.text(en: en)}').join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr('Anuluj', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr('Zmień mimo to', 'Change anyway')),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      warning = consistencyHistoryText(fresh, en: en);
    }
    try {
      await _dao.setStatus(e.id, picked, by: _stamp, warning: warning);
    } catch (err) {
      debugPrint('WeldJournal setStatus error: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Nie udało się zmienić statusu spoiny.',
            'Failed to update weld status.')),
      ));
      return;
    }
    await _load();
  }

  Future<void> _onTileAction(WeldEntry e, _TileAction a) async {
    switch (a) {
      case _TileAction.status:
        await _changeStatus(e);
      case _TileAction.next:
        await _nextAfter(e);
      case _TileAction.repair:
        await _repair(e);
      case _TileAction.history:
        await showWeldHistorySheet(context,
            weldId: e.id, weldNo: e.weldNo, dao: _dao);
      case _TileAction.delete:
        await _delete(e);
      case _TileAction.restore:
        await _restore(e);
    }
  }

  Future<void> _repair(WeldEntry e) async {
    final next = 'R${e.repairs.length + 1}';
    final input = await showWeldRepairDialog(context,
        weldNo: e.weldNo, nextLabel: next, repairsSoFar: e.repairs.length);
    if (input == null || !mounted) return;
    try {
      final r = await _dao.addRepair(e.id,
          date: input.date, reason: input.reason, by: _stamp);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
            'Zapisano naprawę ${r.label} spoiny ${e.weldNo}. Spoina czeka na '
                'ponowne badanie.',
            'Repair ${r.label} of weld ${e.weldNo} saved. The weld awaits '
                're-examination.')),
      ));
    } catch (err) {
      debugPrint('WeldJournal repair error: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
            'Nie udało się zapisać naprawy.', 'Failed to save the repair.')),
      ));
    }
  }

  Future<void> _delete(WeldEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Usuń spoinę', 'Delete weld')),
        content: Text(_tr(
          'Usunąć spoinę ${e.weldNo}? Wpis zniknie z listy i z eksportu, ale '
              'zostanie w historii — przywrócisz go filtrem „Pokaż usunięte”.',
          'Delete weld ${e.weldNo}? It disappears from the list and the '
              'export but stays in the history — restore it with the '
              '"Show deleted" filter.',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr('Anuluj', 'Cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Usuń', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _dao.softDelete(e.id, by: _stamp);
    } catch (err) {
      debugPrint('WeldJournal delete error: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(_tr('Nie udało się usunąć spoiny.', 'Failed to delete weld.')),
      ));
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          _tr('Usunięto spoinę ${e.weldNo}.', 'Weld ${e.weldNo} deleted.')),
      action: SnackBarAction(
        label: _tr('Cofnij', 'Undo'),
        onPressed: () => _restore(e, quiet: true),
      ),
    ));
  }

  Future<void> _restore(WeldEntry e, {bool quiet = false}) async {
    try {
      await _dao.restore(e.id, by: _stamp);
    } catch (err) {
      debugPrint('WeldJournal restore error: $err');
    }
    await _load();
    if (quiet || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          _tr('Przywrócono spoinę ${e.weldNo}.', 'Weld ${e.weldNo} restored.')),
    ));
  }

  Future<void> _openProjectSettings() async {
    var project = _filter.project;
    if (project.isEmpty) {
      final projects = _journalProjects;
      if (projects.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tr('Najpierw zapisz spoinę z nazwą projektu.',
              'Save a weld with a project name first.')),
        ));
        return;
      }
      final picked = projects.length == 1
          ? projects.single
          : await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(_tr('Który projekt?', 'Which project?')),
                children: [
                  for (final p in projects)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(p),
                      ),
                    ),
                ],
              ),
            );
      if (picked == null || !mounted) return;
      project = picked;
    }
    final saved = await showWeldProjectSettingsSheet(context,
        projectName: project, dao: _settingsDao);
    if (saved == true) await _load();
  }

  // ── Export — exactly the visible set ───────────────────────────────────

  bool _hasSomethingToExport() {
    if (_visible.isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(_tr('Brak spoin do wyeksportowania.', 'No welds to export.')),
    ));
    return false;
  }

  /// Settings of the one project the export covers, if it covers one.
  WeldJournalPdfHeader _pdfHeader(List<WeldJournalRecord> records) {
    final keys = records
        .map((r) => WeldJournalProjectSettings.keyFor(r.projectName))
        .toSet();
    if (keys.length != 1) return const WeldJournalPdfHeader();
    final s = _settings[keys.single];
    if (s != null) return WeldJournalPdfHeader.fromSettings(s);
    return WeldJournalPdfHeader(projectTitle: records.first.projectName.trim());
  }

  Future<void> _runExport(Future<void> Function() job) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await job();
    } catch (err) {
      debugPrint('WeldJournal export error: $err');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tr('Nie udało się wyeksportować dziennika.',
              'Failed to export the journal.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// QC remarks and history lines of the exported welds (v25).
  Future<(Map<String, List<String>>, Map<String, List<String>>)>
      _exportExtras() async {
    final en = AppLanguageController.isEnglish;
    final visible = _visible;
    var history = const <String, List<WeldHistoryEntry>>{};
    try {
      history = await _dao.historyFor(visible.map((e) => e.id));
    } catch (e) {
      debugPrint('[weld_journal] history for export failed: $e');
    }
    final remarks = <String, List<String>>{};
    final lines = <String, List<String>>{};
    for (final e in visible) {
      final h = history[e.id] ?? const <WeldHistoryEntry>[];
      remarks[e.id] = weldQcRemarks(
        current: [
          ...?_compliance[e.id]?.warningLines(en: en),
          for (final i in _issuesOf(e)) i.text(en: en),
        ],
        history: h,
      );
      lines[e.id] = weldHistoryLines(h, en: en);
    }
    return (remarks, lines);
  }

  Future<void> _exportCsv() async {
    if (!_hasSomethingToExport()) return;
    final (remarks, _) = await _exportExtras();
    final records =
        weldJournalExportRecords(_entries, _filter, qcRemarks: remarks);
    await _runExport(() => WeldJournalExport.shareCsv(
          records: records,
          filterLabel: _filter.fileTag,
        ));
  }

  Future<void> _exportPdf() async {
    if (!_hasSomethingToExport()) return;
    final (remarks, history) = await _exportExtras();
    final records = weldJournalExportRecords(_entries, _filter,
        qcRemarks: remarks, history: history);
    final description = _filter.describe(en: AppLanguageController.isEnglish);
    await _runExport(() => WeldJournalExport.sharePdf(
          records: records,
          filterLabel: _filter.fileTag,
          filterDescription: description,
          header: _pdfHeader(records),
          welderFallback: _stamp,
        ));
  }
}

// ── Weld tile ─────────────────────────────────────────────────────────────

enum _TileAction { status, next, repair, history, delete, restore }

class _WeldTile extends StatelessWidget {
  final WeldEntry entry;
  final WeldCompliance? compliance;

  /// Document-consistency issues (v25).
  final List<WeldConsistencyIssue> issues;
  final VoidCallback onTap;
  final VoidCallback? onStatusTap;
  final ValueChanged<_TileAction> onAction;

  const _WeldTile({
    required this.entry,
    this.compliance,
    this.issues = const [],
    required this.onTap,
    required this.onStatusTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.isDeleted ? kTextMut : weldStatusColor(e.status);
    final ndt = [
      for (final n in e.ndt.entries)
        if (n.value.hasResult)
          '${n.key.name.toUpperCase()} ${n.value.result}'
        else if (n.value.isAwaiting)
          '${n.key.name.toUpperCase()} …',
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            // Status badge: opens the confirmed status dialog — it no longer
            // cycles the status on a tap.
            Semantics(
              button: onStatusTap != null,
              label: context.tr(
                  pl: 'Status ${e.status} — zmień',
                  en: 'Status ${e.status} — change'),
              child: InkWell(
                onTap: onStatusTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      e.isDeleted
                          ? Icons.delete_outline
                          : weldStatusIcon(e.status),
                      color: color,
                      size: 24),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        e.weldNo,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kText,
                          decoration:
                              e.isDeleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (e.repairs.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(e.repairs.last.label,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kWarn)),
                    ],
                    if (e.projectName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.projectName,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 12, color: kTextSec)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (e.pipeName.isNotEmpty) e.pipeName,
                      if (e.isoDrawing.isNotEmpty)
                        [e.isoDrawing, e.isoRev]
                            .where((s) => s.isNotEmpty)
                            .join(' rev. '),
                      if (e.od.isNotEmpty) 'OD ${_localizedNum(e.od)}',
                      if (e.t.isNotEmpty) 't ${_localizedNum(e.t)}',
                      if (e.material.isNotEmpty) e.material,
                      if (e.method.isNotEmpty) e.method,
                    ].join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: kTextMut),
                  ),
                  Text(
                    [
                      if (e.date.isNotEmpty) e.date,
                      if (e.stamps.isNotEmpty) e.stamps.join(' / '),
                      ...ndt,
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: kTextMut),
                  ),
                  if (compliance != null &&
                      WeldComplianceBadges.hasAny(compliance!))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: WeldComplianceBadges(compliance: compliance!),
                    ),
                  if (issues.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Tooltip(
                        message: issues
                            .map((i) =>
                                i.text(en: AppLanguageController.isEnglish))
                            .join('\n'),
                        child: Text(
                          '⚠ ${issues.first.text(en: AppLanguageController.isEnglish)}'
                          '${issues.length > 1 ? ' (+${issues.length - 1})' : ''}',
                          key: ValueKey('weld-issues-${e.id}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: kFail,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (e.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(e.notes,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 11, color: kTextSec)),
                    ),
                ],
              ),
            ),
            // 48 dp menu instead of a bare delete icon next to the tile.
            PopupMenuButton<_TileAction>(
              tooltip: context.tr(pl: 'Akcje spoiny', en: 'Weld actions'),
              icon: const Icon(Icons.more_vert, color: kTextSec),
              onSelected: onAction,
              itemBuilder: (_) => [
                if (!e.isDeleted) ...[
                  PopupMenuItem(
                      value: _TileAction.status,
                      child: Text(context.tr(
                          pl: 'Zmień status…', en: 'Change status…'))),
                  PopupMenuItem(
                      value: _TileAction.next,
                      child: Text(context.tr(
                          pl: 'Następna spoina (kopia)',
                          en: 'Next weld (copy)'))),
                  PopupMenuItem(
                      value: _TileAction.repair,
                      child: Text(context.tr(
                          pl: 'Naprawa R${e.repairs.length + 1}…',
                          en: 'Repair R${e.repairs.length + 1}…'))),
                ],
                PopupMenuItem(
                    value: _TileAction.history,
                    child: Text(context.tr(
                        pl: 'Historia zmian', en: 'Change history'))),
                if (e.isDeleted)
                  PopupMenuItem(
                      value: _TileAction.restore,
                      child: Text(context.tr(pl: 'Przywróć', en: 'Restore')))
                else
                  PopupMenuItem(
                      value: _TileAction.delete,
                      child: Text(context.tr(pl: 'Usuń…', en: 'Delete…'),
                          style: const TextStyle(color: kFail))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat badge ────────────────────────────────────────────────────────────
class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBadge(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kTextMut)),
            ],
          ),
        ),
      );
}
