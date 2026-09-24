// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/db.dart';
import '../database/project_dao.dart';
import '../i18n/app_language.dart';
import '../services/weld_journal_export.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../widgets/help_button.dart';

// ── Kolory ─────────────────────────────────────────────────────────────────
const _kOrange = Color(0xFFFF8E1E);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)
const _kSec    = Color(0xFF9BA3C7);

// Locale-aware decimal separator for stored numeric strings (OD, t).
// Welders may type "60.3" or "60,3" — display matches the UI language so
// the journal feels native on PL shop floors and reads correctly in EN.
String _localizedNum(String raw) {
  if (AppLanguageController.isEnglish) {
    return raw.replaceAll(',', '.');
  }
  return raw.replaceAll('.', ',');
}

// ── Ostatni projekt ────────────────────────────────────────────────────────

/// SharedPreferences key holding the project last used in the journal.
///
/// A welder logs ~30 joints a shift, all on the same job, and "Projekt" opened
/// as an empty TextField on every one of them. Retyping a name 30 times with a
/// glove on is not just slow: one slip ("Blok 4" vs "Blok4") silently splits
/// the status filter, the weld-number suggester — which matches entries on
/// `projectName` — and the CSV/PDF export into two projects that no longer
/// reconcile at an audit. Remembering the last name costs one string.
const String kLastWeldProjectPrefsKey = 'weld_journal.last_project_v1';

/// Reads the remembered project name, or `''` when there is none.
///
/// Never throws. A preferences store that cannot be read is a convenience
/// lost, not a reason to keep a welder from logging a joint.
Future<String> loadLastWeldProject() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kLastWeldProjectPrefsKey)?.trim() ?? '';
  } catch (e) {
    debugPrint('[weld_journal] read last project failed: $e');
    return '';
  }
}

/// Remembers [name] as the project to pre-fill next time.
///
/// An empty name CLEARS the memory instead of storing a blank: a welder who
/// deliberately saved a weld with no project is telling us the old one no
/// longer applies, and pre-filling it again on the next entry would put a
/// wrong project on a joint.
Future<void> saveLastWeldProject(String name) async {
  final trimmed = name.trim();
  try {
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(kLastWeldProjectPrefsKey);
    } else {
      await prefs.setString(kLastWeldProjectPrefsKey, trimmed);
    }
  } catch (e) {
    debugPrint('[weld_journal] persist last project failed: $e');
  }
}

// ── Model spoiny ───────────────────────────────────────────────────────────
class WeldEntry {
  final String id;
  String weldNo;
  String projectName;
  String pipeName;
  String material;
  String od;
  String t;
  String method;
  String welder;
  String date;
  String notes;
  String status; // OK / NOK / PENDING
  // ── ASME BPE weld-map fields ──────────────────────────────────────────────
  String weldType;   // ORBITAL / AUTO / MANUAL — auto vs manual welding
  String fitter;     // fitter who set up the joint
  String heatNo1;    // material heat/lot number, part 1 (traceability)
  String heatNo2;    // material heat/lot number, part 2
  String couponRef;  // reference of the test coupon welded that shift
  String exam;       // examination result, e.g. VT OK / borescope OK
  String wpsRef;     // qualified WPS / pWPS reference used for this joint

  WeldEntry({
    required this.id,
    required this.weldNo,
    required this.projectName,
    required this.pipeName,
    required this.material,
    required this.od,
    required this.t,
    required this.method,
    required this.welder,
    required this.date,
    required this.notes,
    required this.status,
    this.weldType = 'MANUAL',
    this.fitter = '',
    this.heatNo1 = '',
    this.heatNo2 = '',
    this.couponRef = '',
    this.exam = '',
    this.wpsRef = '',
  });

  Map<String, Object?> toRow() => {
    'id': id, 'weld_no': weldNo, 'project_name': projectName,
    'pipe_name': pipeName, 'material': material, 'od': od, 't': t,
    'method': method, 'welder': welder, 'date': date,
    'notes': notes, 'status': status,
    'weld_type': weldType, 'fitter': fitter,
    'heat_no1': heatNo1, 'heat_no2': heatNo2,
    'coupon_ref': couponRef, 'exam': exam,
    'wps_ref': wpsRef,
  };

  /// Immutable snapshot handed to the export layer.
  ///
  /// Written out field by field (instead of reusing [toRow]) so the compiler
  /// flags any journal field that gets added here and forgotten in the CSV /
  /// PDF — a silently missing heat number is exactly the kind of hole that
  /// only shows up when an inspector asks for it.
  WeldJournalRecord toExportRecord() => WeldJournalRecord(
        weldNo: weldNo,
        projectName: projectName,
        pipeName: pipeName,
        material: material,
        od: od,
        t: t,
        method: method,
        welder: welder,
        date: date,
        notes: notes,
        status: status,
        weldType: weldType,
        fitter: fitter,
        heatNo1: heatNo1,
        heatNo2: heatNo2,
        couponRef: couponRef,
        exam: exam,
        wpsRef: wpsRef,
      );

  static WeldEntry fromRow(Map<String, Object?> r) => WeldEntry(
    id: r['id'] as String,
    weldNo: (r['weld_no'] as String?) ?? '',
    projectName: (r['project_name'] as String?) ?? '',
    pipeName: (r['pipe_name'] as String?) ?? '',
    material: (r['material'] as String?) ?? '',
    od: (r['od'] as String?) ?? '',
    t: (r['t'] as String?) ?? '',
    method: (r['method'] as String?) ?? 'TIG',
    welder: (r['welder'] as String?) ?? '',
    date: (r['date'] as String?) ?? '',
    notes: (r['notes'] as String?) ?? '',
    status: (r['status'] as String?) ?? 'PENDING',
    weldType: (r['weld_type'] as String?) ?? 'MANUAL',
    fitter: (r['fitter'] as String?) ?? '',
    heatNo1: (r['heat_no1'] as String?) ?? '',
    heatNo2: (r['heat_no2'] as String?) ?? '',
    couponRef: (r['coupon_ref'] as String?) ?? '',
    exam: (r['exam'] as String?) ?? '',
    wpsRef: (r['wps_ref'] as String?) ?? '',
  );
}

// ── Filtr = eksport ─────────────────────────────────────────────────────────

/// The entries the journal list shows for [filter] (`ALL` / `OK` / `NOK` /
/// `PENDING`), in the order given.
///
/// This is the ONE place the status filter is decided. The list on screen and
/// the CSV/PDF export both go through it, so "what I see" and "what the
/// inspector gets" cannot drift apart. `ALL` returns a copy, never the
/// caller's list, so the result can be handed around without aliasing the
/// screen state.
List<WeldEntry> filterWeldEntries(List<WeldEntry> entries, String filter) =>
    filter == 'ALL'
        ? List<WeldEntry>.of(entries)
        : entries.where((e) => e.status == filter).toList();

/// Rows handed to the exporter for [filter] — exactly [filterWeldEntries],
/// mapped to export records, order preserved.
List<WeldJournalRecord> weldJournalExportRecords(
        List<WeldEntry> entries, String filter) =>
    filterWeldEntries(entries, filter)
        .map((e) => e.toExportRecord())
        .toList();

// ── DAO ─────────────────────────────────────────────────────────────────────

/// The `weld_journal` table is part of the schema in `lib/database/db.dart`
/// (v18). It used to be created — and later widened with ALTER TABLE — right
/// here on the first screen open, which meant a phone that had never shown
/// the journal had no table, and restoring a backup onto it silently dropped
/// every weld. Opening the database now guarantees the table and every
/// column, so this DAO only reads and writes.
class WeldJournalDao {
  static const _table = 'weld_journal';

  Future<List<WeldEntry>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query(_table, orderBy: 'weld_no ASC');
    return rows.map(WeldEntry.fromRow).toList();
  }

  Future<void> insert(WeldEntry e) async {
    final db = await AppDatabase.get();
    await db.insert(_table, e.toRow());
  }

  Future<void> update(WeldEntry e) async {
    final db = await AppDatabase.get();
    await db.update(_table, e.toRow(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.get();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EKRAN DZIENNIKA
// ═══════════════════════════════════════════════════════════════════════════
class WeldJournalScreen extends StatefulWidget {
  const WeldJournalScreen({super.key});
  @override State<WeldJournalScreen> createState() => _WeldJournalScreenState();
}

class _WeldJournalScreenState extends State<WeldJournalScreen> {
  final _dao = WeldJournalDao();
  List<WeldEntry> _entries = [];
  bool _loading = true;
  bool _exporting = false;
  String _filter = 'ALL'; // ALL / OK / NOK / PENDING

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final all = await _dao.listAll();
      if (!mounted) return;
      setState(() {
        _entries = all;
        _loading = false;
      });
    } catch (e) {
      // DAO failures (locked DB, schema migration partial-apply) used to
      // strand the orange spinner forever — welder force-quits, loses
      // unsaved editor state. Surface a SnackBar with Ponów action so the
      // shift can recover without restarting the app.
      debugPrint('WeldJournal load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Nie udało się wczytać dziennika. Spróbuj ponownie.',
          'Failed to load journal. Try again.',
        )),
        action: SnackBarAction(
          label: _tr('Ponów', 'Retry'),
          onPressed: _load,
        ),
      ));
    }
  }

  List<WeldEntry> get _filtered => filterWeldEntries(_entries, _filter);

  /// Project names already present in the journal, de-duplicated and sorted.
  ///
  /// Feeds the editor's project picker alongside [ProjectDao]. Kept here
  /// rather than queried again in the sheet because the journal is already in
  /// memory, and because a name a welder typed himself is exactly the one the
  /// cut-list side of the app does not know about.
  ///
  /// De-duplicated case-insensitively but stored in the casing first seen —
  /// "blok 4" and "Blok 4" are the same job, and offering both would recreate
  /// the split this picker exists to prevent.
  List<String> get _journalProjects {
    final seen = <String>{};
    final out = <String>[];
    for (final e in _entries) {
      final n = e.projectName.trim();
      if (n.isEmpty || !seen.add(n.toLowerCase())) continue;
      out.add(n);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  int get _nextNo {
    if (_entries.isEmpty) return 1;
    final nos = _entries
        .map((e) => int.tryParse(e.weldNo.replaceAll(RegExp(r'[^\d]'), '')) ?? 0)
        .toList();
    return (nos.reduce((a, b) => a > b ? a : b)) + 1;
  }

  /// Suggests the next weld number. If a project name is given and that
  /// project already has entries, the suggestion keeps the same prefix and
  /// width (e.g. "SP-001-W005" → "SP-001-W006"). Otherwise falls back to a
  /// global "W-NNN" counter.
  String suggestNextWeldNo(String? projectName) {
    final hit = RegExp(r'^(.*?)(\d+)$');
    final inProject = (projectName != null && projectName.trim().isNotEmpty)
        ? _entries.where((e) => e.projectName.trim() == projectName.trim()).toList()
        : <WeldEntry>[];
    if (inProject.isNotEmpty) {
      WeldEntry? best;
      int bestNum = -1;
      for (final e in inProject) {
        final m = hit.firstMatch(e.weldNo.trim());
        if (m == null) continue;
        final n = int.tryParse(m.group(2)!) ?? -1;
        if (n > bestNum) {
          bestNum = n;
          best = e;
        }
      }
      if (best != null && bestNum >= 0) {
        final m = hit.firstMatch(best.weldNo.trim())!;
        final prefix = m.group(1)!;
        final width = m.group(2)!.length;
        return '$prefix${(bestNum + 1).toString().padLeft(width, '0')}';
      }
    }
    return 'W-${_nextNo.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    // Single-pass tally — avoids three separate .where().length scans of the
    // entire journal on every rebuild (filter tap, status cycle, etc.).
    var okCount = 0, nokCount = 0, pendingCount = 0;
    for (final e in _entries) {
      switch (e.status) {
        case 'OK': okCount++; break;
        case 'NOK': nokCount++; break;
        case 'PENDING': pendingCount++; break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Dziennik spoin', 'Weld journal')),
        actions: [
          HelpButton(help: kHelpWeldJournal),
          // Data OUT. The journal is the only document a welder can put on
          // the table at a quality audit, yet nothing could leave the phone
          // — no PDF, no CSV, not even a clipboard copy — even though
          // README.md and kHelpWeldJournal both promise "PDF lub CSV".
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
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : Column(
              children: [
                // Statystyki
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      _StatBadge(_tr('Razem', 'Total'), '${_entries.length}', _kSec),
                      const SizedBox(width: 8),
                      _StatBadge('OK', '$okCount', _kGreen),
                      const SizedBox(width: 8),
                      _StatBadge('NOK', '$nokCount', _kRed),
                      const SizedBox(width: 8),
                      _StatBadge(_tr('Oczekuje', 'Pending'), '$pendingCount', _kOrange),
                    ],
                  ),
                ),
                // Filtry
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in [('ALL', _tr('Wszystkie', 'All')), ('OK', 'OK'), ('NOK', 'NOK'), ('PENDING', _tr('Oczekuje', 'Pending'))])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _filter = f.$1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _filter == f.$1 ? _kOrange.withValues(alpha: 0.15) : _kCard,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _filter == f.$1 ? _kOrange : _kBorder, width: _filter == f.$1 ? 1.5 : 1),
                                ),
                                child: Text(f.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _filter == f.$1 ? _kOrange : _kSec)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Lista
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.fact_check_outlined, size: 56, color: _kMuted),
                              const SizedBox(height: 12),
                              Text(_tr('Brak spoin. Kliknij + aby dodać.', 'No welds. Tap + to add.'), style: const TextStyle(color: _kMuted)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + MediaQuery.viewPaddingOf(context).bottom),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) => _WeldTile(
                            entry: filtered[i],
                            onTap: () => _openEditor(filtered[i]),
                            onDelete: () => _delete(filtered[i]),
                            onStatusTap: () => _cycleStatus(filtered[i]),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add),
        label: Text(_tr('Nowa spoina', 'New weld')),
        backgroundColor: _kOrange,
        foregroundColor: Colors.black,
      ),
    );
  }

  Future<void> _cycleStatus(WeldEntry e) async {
    final prev = e.status;
    final next = prev == 'PENDING' ? 'OK' : (prev == 'OK' ? 'NOK' : 'PENDING');
    // P0r-09: optimistic mutation is fine for snappy UX, but we MUST be able
    // to roll back if the DAO write fails — otherwise the on-screen NOK
    // reads as OK while the DB still says PENDING, breaking traceability.
    e.status = next;
    try {
      await _dao.update(e);
    } catch (err) {
      debugPrint('WeldJournal cycleStatus error: $err');
      e.status = prev; // roll back the optimistic mutation
      if (!mounted) return;
      setState(() {}); // refresh the row to show the reverted status
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Nie udało się zmienić statusu spoiny.',
          'Failed to update weld status.',
        )),
      ));
      return;
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _delete(WeldEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_tr('Usuń spoinę', 'Delete weld')),
        content: Text(_tr('Usunąć spoinę ${e.weldNo}?', 'Delete weld ${e.weldNo}?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_tr('Anuluj', 'Cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('Usuń', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _dao.delete(e.id);
    } catch (err) {
      debugPrint('WeldJournal delete error: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Nie udało się usunąć spoiny.',
          'Failed to delete weld.',
        )),
      ));
      return;
    }
    if (!mounted) return;
    await _load();
  }

  /// Rows handed to the exporter — the CURRENT view, filter included.
  ///
  /// Exporting the filtered list is deliberate: "give me only the NOKs" is a
  /// real request from QA, and WYSIWYG is the only rule a welder can verify
  /// on the spot. The filter is written into the file name and printed in
  /// the PDF header so a partial journal can never be mistaken for the whole
  /// one. Goes through [weldJournalExportRecords], the same selection the
  /// list uses via [filterWeldEntries].
  List<WeldJournalRecord> _exportRecords() =>
      weldJournalExportRecords(_entries, _filter);

  bool _hasSomethingToExport() {
    if (_filtered.isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_tr(
        'Brak spoin do wyeksportowania.',
        'No welds to export.',
      )),
    ));
    return false;
  }

  /// Shared wrapper: renders/writes/shares, and never leaves the buttons
  /// dead. A failed export used to be impossible; now that it exists it must
  /// not fail silently either — a welder who thinks the file went out and
  /// finds nothing in the mail is worse off than one who sees an error.
  Future<void> _runExport(Future<void> Function() job) async {
    // Guards a double tap: PDF rendering takes a moment on a big journal and
    // two share sheets racing each other end with the second one holding a
    // stale file handle.
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await job();
    } catch (err) {
      debugPrint('WeldJournal export error: $err');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tr(
            'Nie udało się wyeksportować dziennika.',
            'Failed to export the journal.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv() async {
    if (!_hasSomethingToExport()) return;
    final records = _exportRecords();
    await _runExport(() => WeldJournalExport.shareCsv(
          records: records,
          filterLabel: _filter,
        ));
  }

  Future<void> _exportPdf() async {
    if (!_hasSomethingToExport()) return;
    final records = _exportRecords();
    // Identity stamp is only a fallback — if the rows already name their
    // welders, those go on the header instead.
    final stamp = WelderIdentityService.instance.current?.stamp ?? '';
    await _runExport(() => WeldJournalExport.sharePdf(
          records: records,
          filterLabel: _filter,
          welderFallback: stamp,
        ));
  }

  Future<void> _openEditor(WeldEntry? existing) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // The editor holds up to 15 hand-typed traceability fields (heat
      // numbers, WPS, coupon, exam result). With the defaults, one stray tap
      // on the scrim — or a gloved thumb brushing downwards — closed the
      // sheet and threw all of it away without a word. Both gestures are off
      // now; the only ways out are the X button and the system back gesture,
      // and both route through the "Porzucić wpis?" confirmation in
      // _WeldEditorState._handleClose().
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF141821),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WeldEditor(
        entry: existing,
        suggestedNo: suggestNextWeldNo(existing?.projectName),
        suggester: suggestNextWeldNo,
        journalProjects: _journalProjects,
      ),
    );
    if (!mounted) return;
    if (result == true) await _load();
  }
}

// ── Kafelek spoiny ──────────────────────────────────────────────────────────
class _WeldTile extends StatelessWidget {
  final WeldEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onStatusTap;

  const _WeldTile({required this.entry, required this.onTap, required this.onDelete, required this.onStatusTap});

  Color get _statusColor => entry.status == 'OK' ? _kGreen : (entry.status == 'NOK' ? _kRed : _kOrange);
  IconData get _statusIcon => entry.status == 'OK' ? Icons.check_circle_outline : (entry.status == 'NOK' ? Icons.cancel_outlined : Icons.pending_outlined);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Status badge
            GestureDetector(
              onTap: onStatusTap,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(entry.weldNo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFE7ECF3))),
                    if (entry.projectName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.projectName, style: const TextStyle(fontSize: 12, color: _kSec), overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    [
                      // Show OD / wall thickness with locale-aware decimal
                      // separator: comma in PL, dot in EN. Stored value may
                      // be either depending on how the welder typed it.
                      if (entry.od.isNotEmpty) 'OD ${_localizedNum(entry.od)}',
                      if (entry.t.isNotEmpty) 't ${_localizedNum(entry.t)}',
                      if (entry.material.isNotEmpty) entry.material,
                      if (entry.method.isNotEmpty) entry.method,
                      if (entry.welder.isNotEmpty) entry.welder,
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 12, color: _kMuted),
                  ),
                  if (entry.date.isNotEmpty)
                    Text(entry.date, style: const TextStyle(fontSize: 11, color: _kMuted)),
                  if (entry.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(entry.notes, style: const TextStyle(fontSize: 11, color: _kSec), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            // Delete — 48dp square hit target so gloved fingertips don't
            // miss and accidentally tap the tile (which would open editor).
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.delete_outline, size: 20, color: _kMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edytor spoiny ────────────────────────────────────────────────────────────
class _WeldEditor extends StatefulWidget {
  final WeldEntry? entry;
  final String suggestedNo;
  /// Called when the user taps the auto-number icon; returns a suggestion
  /// based on the current project name typed in the editor.
  final String Function(String? projectName) suggester;

  /// Project names already used in the journal — one half of what the project
  /// picker offers; the other half comes from [ProjectDao].
  final List<String> journalProjects;

  const _WeldEditor({
    required this.entry,
    required this.suggestedNo,
    required this.suggester,
    required this.journalProjects,
  });
  @override State<_WeldEditor> createState() => _WeldEditorState();
}

class _WeldEditorState extends State<_WeldEditor> {
  final _dao = WeldJournalDao();
  static const _uuid = Uuid();

  late final TextEditingController _noCtrl;
  late final TextEditingController _projCtrl;
  late final TextEditingController _pipeCtrl;
  late final TextEditingController _matCtrl;
  late final TextEditingController _odCtrl;
  late final TextEditingController _tCtrl;
  late final TextEditingController _welderCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _fitterCtrl;
  late final TextEditingController _heat1Ctrl;
  late final TextEditingController _heat2Ctrl;
  late final TextEditingController _couponCtrl;
  late final TextEditingController _examCtrl;
  late final TextEditingController _wpsCtrl;
  String _method = 'TIG';
  String _status = 'PENDING';
  String _weldType = 'MANUAL';

  bool _saving = false;
  bool _showBpe = false;
  bool _closing = false;

  /// True while the weld number is still the app's own suggestion.
  ///
  /// The suggester keys off the project name, so picking a project has to be
  /// able to re-run it ("W-007" → "SP-001-W006"). It must NOT do that once the
  /// welder has typed his own number — hence the flag: any keystroke in the
  /// number field hands ownership over and the picker stops rewriting it.
  bool _autoNo = false;

  /// The form exactly as it was opened. Compared field by field, so a sheet
  /// nobody touched closes silently (a NEW entry already arrives pre-filled
  /// with the suggested number, 316L, today's date, the owner's stamp and —
  /// since the project picker landed — the last project used; prompting for
  /// that would train the welder to dismiss the dialog), while one typed
  /// character arms the discard guard.
  ///
  /// Not `final`: the remembered project arrives from an async preferences
  /// read AFTER initState has taken the first snapshot, and that pre-fill has
  /// to be folded in — see [_restoreLastProject].
  late Map<String, String> _initial;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    // P0-08: On NEW entry (entry == null) auto-fill welder + fitter from
    // the persistent identity store. The user can still type a substitute
    // (e.g. when documenting a coworker's weld) but every new joint is
    // welder-stamped by default — no more anonymous "ghost weld" rows
    // that fail ISO 3834 audit. Existing entries keep their original
    // stamp untouched.
    final identityStamp = WelderIdentityService.instance.current?.stamp ?? '';
    _noCtrl     = TextEditingController(text: e?.weldNo     ?? widget.suggestedNo);
    _projCtrl   = TextEditingController(text: e?.projectName ?? '');
    _pipeCtrl   = TextEditingController(text: e?.pipeName    ?? '');
    _matCtrl    = TextEditingController(text: e?.material    ?? '316L');
    _odCtrl     = TextEditingController(text: e?.od          ?? '');
    _tCtrl      = TextEditingController(text: e?.t           ?? '');
    _welderCtrl = TextEditingController(text: e?.welder      ?? identityStamp);
    _dateCtrl   = TextEditingController(text: e?.date        ?? _today());
    _notesCtrl  = TextEditingController(text: e?.notes       ?? '');
    _fitterCtrl = TextEditingController(text: e?.fitter      ?? identityStamp);
    _heat1Ctrl  = TextEditingController(text: e?.heatNo1     ?? '');
    _heat2Ctrl  = TextEditingController(text: e?.heatNo2     ?? '');
    _couponCtrl = TextEditingController(text: e?.couponRef   ?? '');
    _examCtrl   = TextEditingController(text: e?.exam        ?? '');
    _wpsCtrl    = TextEditingController(text: e?.wpsRef      ?? '');
    _method     = e?.method ?? 'TIG';
    _status     = e?.status ?? 'PENDING';
    _weldType   = e?.weldType ?? 'MANUAL';
    // Open the BPE section automatically if any field already has data.
    _showBpe = (e != null) && [
      e.fitter, e.heatNo1, e.heatNo2, e.couponRef, e.exam, e.wpsRef,
    ].any((s) => s.trim().isNotEmpty);
    // Only a NEW entry carries an app-generated number; an existing weld's
    // number is the welder's and must never be rewritten under him.
    _autoNo = e == null;
    _initial = _snapshot();
    if (e == null) _restoreLastProject();
  }

  /// Pre-fills the project on a NEW entry from the last one used.
  ///
  /// Runs after initState because SharedPreferences is async, which is why it
  /// has to re-take [_initial]: the first snapshot was captured before this
  /// value landed, so without the re-take an untouched sheet would read as
  /// dirty and "Porzucić wpis?" would fire on every close. A value the APP
  /// filled in is not work worth protecting — the same reasoning that already
  /// covers the suggested number, 316L, today's date and the owner's stamp.
  Future<void> _restoreLastProject() async {
    final last = await loadLastWeldProject();
    if (!mounted || last.isEmpty) return;
    // Do not fight the welder: if he started typing while the preference was
    // still loading, his text wins.
    if (_projCtrl.text.trim().isNotEmpty) return;
    setState(() {
      _projCtrl.text = last;
      if (_autoNo) _noCtrl.text = widget.suggester(last);
      _initial = _snapshot();
    });
  }

  /// Opens the project list and applies the pick.
  ///
  /// The field itself stays free text — a welder documenting a job that is not
  /// in the app has to be able to type its name — so this only removes the
  /// reason to retype one that already exists.
  Future<void> _pickProject() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProjectPickerSheet(
        journalProjects: widget.journalProjects,
        current: _projCtrl.text.trim(),
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _projCtrl.text = picked;
      // Project-scoped numbering only makes sense while the number is still
      // ours to change.
      if (_autoNo) _noCtrl.text = widget.suggester(picked);
    });
    // Remembered now, not only on save: a welder who picks the project and
    // then abandons the sheet has still told us which job he is on.
    await saveLastWeldProject(picked);
  }

  /// Every user-editable value in one flat map — the dropdowns too, because
  /// switching TIG -> MMA or PENDING -> NOK is work worth protecting.
  Map<String, String> _snapshot() => {
        'no': _noCtrl.text,
        'proj': _projCtrl.text,
        'pipe': _pipeCtrl.text,
        'mat': _matCtrl.text,
        'od': _odCtrl.text,
        't': _tCtrl.text,
        'welder': _welderCtrl.text,
        'date': _dateCtrl.text,
        'notes': _notesCtrl.text,
        'fitter': _fitterCtrl.text,
        'heat1': _heat1Ctrl.text,
        'heat2': _heat2Ctrl.text,
        'coupon': _couponCtrl.text,
        'exam': _examCtrl.text,
        'wps': _wpsCtrl.text,
        'method': _method,
        'status': _status,
        'weldType': _weldType,
      };

  /// True once anything differs from the state the sheet was opened in.
  bool get _isDirty {
    final now = _snapshot();
    for (final field in _initial.entries) {
      if (now[field.key] != field.value) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Porzucić wpis?', 'Discard entry?')),
        content: Text(_tr(
          'Wypełnione pola spoiny zostaną utracone.',
          'The weld data you entered will be lost.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('Wróć do edycji', 'Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Porzuć', 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// The one and only exit path. The X button and the system back gesture
  /// both land here, so neither can slip past the confirmation.
  Future<void> _handleClose() async {
    if (_saving) return;  // a write is in flight — let _save() close the sheet
    if (_closing) return; // second back press must not stack a second dialog
    final nav = Navigator.of(context);
    if (!_isDirty) {
      nav.pop();
      return;
    }
    _closing = true;
    final discard = await _confirmDiscard();
    _closing = false;
    if (discard && mounted) nav.pop();
  }

  @override
  void dispose() {
    for (final c in [
      _noCtrl, _projCtrl, _pipeCtrl, _matCtrl, _odCtrl, _tCtrl, _welderCtrl,
      _dateCtrl, _notesCtrl, _fitterCtrl, _heat1Ctrl, _heat2Ctrl, _couponCtrl,
      _examCtrl, _wpsCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
  }

  Future<void> _save() async {
    if (_noCtrl.text.trim().isEmpty) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final e = WeldEntry(
      id:          widget.entry?.id ?? _uuid.v4(),
      weldNo:      _noCtrl.text.trim(),
      projectName: _projCtrl.text.trim(),
      pipeName:    _pipeCtrl.text.trim(),
      material:    _matCtrl.text.trim(),
      od:          _odCtrl.text.trim(),
      t:           _tCtrl.text.trim(),
      method:      _method,
      welder:      _welderCtrl.text.trim(),
      date:        _dateCtrl.text.trim(),
      notes:       _notesCtrl.text.trim(),
      status:      _status,
      weldType:    _weldType,
      fitter:      _fitterCtrl.text.trim(),
      heatNo1:     _heat1Ctrl.text.trim(),
      heatNo2:     _heat2Ctrl.text.trim(),
      couponRef:   _couponCtrl.text.trim(),
      exam:        _examCtrl.text.trim(),
      wpsRef:      _wpsCtrl.text.trim(),
    );
    try {
      if (widget.entry == null) {
        await _dao.insert(e);
      } else {
        await _dao.update(e);
      }
      // Remember the project for the next joint. Done here rather than only in
      // the picker so a name typed by hand is remembered too — that is the
      // case the picker cannot cover, and the one where retyping hurts most.
      await saveLastWeldProject(e.projectName);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      // Without this, a DAO failure would leave _saving=true forever and the
      // editor sheet sits at "Zapisywanie…" with no way to retry — welder
      // loses 30s of typed traceability data.
      debugPrint('WeldJournal save error: $err');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Nie udało się zapisać spoiny. Dane zostają w edytorze — spróbuj ponownie.',
          'Failed to save weld. Your data is kept in the editor — try again.',
        )),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // canPop is a constant `false`, not `!_isDirty` as in
    // segment_builder_screen.dart, and that difference is deliberate: typing
    // into a TextField does NOT rebuild this sheet, so a `!_isDirty` value
    // would stay registered as it was on the first build (`true`, because an
    // untouched form is clean) and the back gesture would drop 15 filled
    // fields without asking — the exact bug being fixed here. With `false`
    // the decision is made in the callback, at pop time, on fresh state.
    // Navigator.pop() from _save() / _handleClose() is unconditional and is
    // not blocked by this.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleClose();
      },
      child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  widget.entry == null ? _tr('Nowa spoina', 'New weld') : _tr('Edytuj spoinę', 'Edit weld'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFE7ECF3)),
                ),
              ),
              // Required, not decorative: with isDismissible/enableDrag off
              // there is no scrim tap and no drag-down left, and iOS has no
              // hardware back button — without this the sheet would have no
              // exit at all on an iPhone.
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: _kSec),
                tooltip: _tr('Zamknij', 'Close'),
                onPressed: _saving ? null : _handleClose,
              ),
            ]),
            const SizedBox(height: 16),
            // Numer spoiny
            TextField(
              controller: _noCtrl,
              // Typing here takes the number away from the app: the project
              // picker must not overwrite a number the welder chose himself.
              onChanged: (_) => _autoNo = false,
              decoration: InputDecoration(
                labelText: _tr('Numer spoiny', 'Weld number'),
                hintText: 'W-001 lub SP-001-W005',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  tooltip: _tr('Następny numer wg projektu', 'Next number for this project'),
                  onPressed: () => setState(() {
                    _noCtrl.text = widget.suggester(_projCtrl.text);
                    // Asking for a suggestion hands the number back to the app.
                    _autoNo = true;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              // Keyboard Next advances Project -> Pipe -> Material in one tap
              // so gloved fingers don't have to dismiss + re-tap each field.
              // Projekt: free text WITH a picker, not one or the other.
              //
              // Thirty joints a shift, one job — and this was a bare TextField
              // retyped by thumb every time. A single typo ("Blok 4"/"Blok4")
              // forks the filter, the number suggester and the export into two
              // projects nobody can reconcile at an audit. The list fixes the
              // common path; the field stays typable because a welder is often
              // documenting a job that exists only on the drawing.
              Expanded(child: TextField(
                controller: _projCtrl,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: InputDecoration(
                  labelText: _tr('Projekt', 'Project'),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    tooltip: _tr('Wybierz projekt z listy',
                        'Pick a project from the list'),
                    onPressed: _saving ? null : _pickProject,
                  ),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _pipeCtrl,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: InputDecoration(labelText: _tr('Rura / linia', 'Pipe / line')),
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(
                controller: _matCtrl,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: InputDecoration(labelText: _tr('Materiał', 'Material'), hintText: '316L'),
              )),
              const SizedBox(width: 10),
              // OD and wall thickness are physically positive — restrict the
              // soft keyboard to digits + decimal separator (no minus, no
              // letters) so invalid values can't be typed in the first place.
              Expanded(child: TextField(
                controller: _odCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'OD (mm)', hintText: '60.3'),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _tCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 't (mm)', hintText: '2.0'),
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: InputDecoration(labelText: _tr('Metoda', 'Method')),
                items: const [
                  DropdownMenuItem(value: 'TIG', child: Text('TIG')),
                  DropdownMenuItem(value: 'MIG/MAG', child: Text('MIG/MAG')),
                  DropdownMenuItem(value: 'MMA', child: Text('MMA')),
                  DropdownMenuItem(value: 'Tandem', child: Text('Tandem TIG')),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'TIG'),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _welderCtrl, decoration: InputDecoration(labelText: _tr('Spawacz', 'Welder')))),
            ]),
            const SizedBox(height: 10),
            // Date field gets a calendar suffix so the welder doesn't have
            // to type YYYY-MM-DD by hand — keyboard stays text-based for
            // edge cases (back-dating, ranges) but the picker covers the
            // common path.
            TextField(
              controller: _dateCtrl,
              decoration: InputDecoration(
                labelText: _tr('Data', 'Date'),
                hintText: 'YYYY-MM-DD',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined, size: 20),
                  tooltip: _tr('Wybierz datę', 'Pick date'),
                  onPressed: () async {
                    final now = DateTime.now();
                    DateTime? initial;
                    final txt = _dateCtrl.text.trim();
                    if (txt.isNotEmpty) {
                      initial = DateTime.tryParse(txt);
                    }
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial ?? now,
                      firstDate: DateTime(now.year - 5),
                      lastDate: DateTime(now.year + 1),
                    );
                    if (picked != null) {
                      final yyyy = picked.year.toString().padLeft(4, '0');
                      final mm = picked.month.toString().padLeft(2, '0');
                      final dd = picked.day.toString().padLeft(2, '0');
                      _dateCtrl.text = '$yyyy-$mm-$dd';
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Status
            Row(children: [
              Text(_tr('Status:', 'Status:'), style: const TextStyle(fontSize: 13, color: _kSec)),
              const SizedBox(width: 12),
              for (final s in [('OK', _kGreen), ('NOK', _kRed), ('PENDING', _kOrange)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _status = s.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _status == s.$1 ? s.$2.withValues(alpha: 0.15) : _kCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _status == s.$1 ? s.$2 : _kBorder, width: _status == s.$1 ? 1.5 : 1),
                      ),
                      child: Text(s.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _status == s.$1 ? s.$2 : _kSec)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _notesCtrl, maxLines: 3, decoration: InputDecoration(labelText: _tr('Uwagi', 'Notes'), hintText: _tr('Np. grań OK, lico do szlifowania', 'E.g. root OK, cap to grind'))),
            const SizedBox(height: 12),

            // ── ASME BPE weld-map section (collapsible) ──────────────────────
            InkWell(
              onTap: () => setState(() => _showBpe = !_showBpe),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 18, color: _kOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _tr('Weld map ASME BPE — śledzenie',
                            'ASME BPE weld map — traceability'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE7ECF3)),
                      ),
                    ),
                    Icon(_showBpe ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: _kSec),
                  ],
                ),
              ),
            ),
            if (_showBpe) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _weldType,
                decoration: InputDecoration(labelText: _tr('Typ spoiny', 'Weld type')),
                items: [
                  DropdownMenuItem(value: 'ORBITAL', child: Text(_tr('Orbitalna (auto)', 'Orbital (auto)'))),
                  DropdownMenuItem(value: 'AUTO', child: Text(_tr('Automatyczna', 'Automatic'))),
                  DropdownMenuItem(value: 'MANUAL', child: Text(_tr('Ręczna', 'Manual'))),
                ],
                onChanged: (v) => setState(() => _weldType = v ?? 'MANUAL'),
              ),
              const SizedBox(height: 10),
              TextField(controller: _fitterCtrl, decoration: InputDecoration(labelText: _tr('Monter (fit-up)', 'Fitter (fit-up)'))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _heat1Ctrl, decoration: InputDecoration(labelText: _tr('Nr wytopu 1', 'Heat no. 1'), hintText: 'MTR'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _heat2Ctrl, decoration: InputDecoration(labelText: _tr('Nr wytopu 2', 'Heat no. 2'), hintText: 'MTR'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _wpsCtrl, decoration: InputDecoration(labelText: _tr('Nr WPS / pWPS', 'WPS / pWPS no.'), hintText: _tr('np. WPS-316L-TIG-01', 'e.g. WPS-316L-TIG-01'))),
              const SizedBox(height: 10),
              TextField(controller: _couponCtrl, decoration: InputDecoration(labelText: _tr('Kupon próbny (ref.)', 'Test coupon (ref.)'), hintText: _tr('np. C-2026-05-17-A', 'e.g. C-2026-05-17-A'))),
              const SizedBox(height: 10),
              TextField(controller: _examCtrl, decoration: InputDecoration(labelText: _tr('Wynik badania', 'Examination result'), hintText: _tr('np. VT OK, boroskop poz. 2', 'e.g. VT OK, borescope lvl 2'))),
            ],

            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? _tr('Zapisywanie...', 'Saving...') : _tr('Zapisz', 'Save')),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Wybór projektu ──────────────────────────────────────────────────────────

/// Bottom sheet offering the projects a weld can be filed under.
///
/// Two sources, merged and de-duplicated:
///   * [ProjectDao] — projects created on the cut-list side of the app;
///   * the names already used in this journal — a welder is often documenting
///     a job that exists only on the drawing, and once he has typed it on the
///     first joint the other twenty-nine should come from a list.
///
/// Returns the picked name through `Navigator.pop`, or `null` when dismissed.
/// It never offers a "new project" action: creating a project belongs to the
/// project screen, and typing a fresh name straight into the field behind this
/// sheet already works.
class _ProjectPickerSheet extends StatefulWidget {
  final List<String> journalProjects;

  /// Name currently in the field, so the list can show which one is in use.
  final String current;

  const _ProjectPickerSheet({
    required this.journalProjects,
    required this.current,
  });

  @override
  State<_ProjectPickerSheet> createState() => _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends State<_ProjectPickerSheet> {
  List<String> _appProjects = const [];
  bool _loading = true;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await ProjectDao().listAll();
      if (!mounted) return;
      setState(() {
        _appProjects = projects
            .map((p) => (p.name ?? '').trim())
            .where((n) => n.isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (e) {
      // Degrade, don't empty: the journal half of the list needs no database
      // and is the half a welder reaches for most. A DAO failure here must not
      // turn the picker into a dead sheet.
      debugPrint('[weld_journal] project list failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Merged list, de-duplicated case-insensitively and sorted by name.
  ///
  /// App projects are added first so they win a duplicate: when the same name
  /// exists on both sides it is one job, and "project in the app" is the more
  /// informative label of the two.
  List<({String name, bool fromApp})> get _entries {
    final seen = <String>{};
    final out = <({String name, bool fromApp})>[];
    for (final n in _appProjects) {
      if (seen.add(n.toLowerCase())) out.add((name: n, fromApp: true));
    }
    for (final n in widget.journalProjects) {
      if (seen.add(n.toLowerCase())) out.add((name: n, fromApp: false));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              _tr('Wybierz projekt', 'Pick a project'),
              style: const TextStyle(
                  color: _kOrange,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2),
            ),
            const SizedBox(height: 4),
            Text(
              _tr(
                'Projekty z aplikacji i nazwy już użyte w dzienniku. Nazwę spoza '
                'listy nadal wpiszesz ręcznie w polu "Projekt".',
                'Projects from the app plus names already used in the journal. '
                'A name that is not here can still be typed into the "Project" '
                'field by hand.',
              ),
              style: const TextStyle(color: _kMuted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                    child: CircularProgressIndicator(color: _kOrange)),
              )
            else if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _tr(
                    'Brak projektów. Wpisz nazwę w polu "Projekt" — pojawi się '
                    'tu przy następnej spoinie.',
                    'No projects yet. Type a name into the "Project" field — it '
                    'will show up here on the next weld.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _kMuted, fontSize: 13, height: 1.4),
                ),
              )
            else
              // Capped and scrollable: a foreman's phone can hold dozens of
              // projects and the sheet must not grow past the screen.
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final it = entries[i];
                    final selected = it.name.toLowerCase() ==
                        widget.current.toLowerCase();
                    return InkWell(
                      onTap: () => Navigator.pop(context, it.name),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        // 48 dp minimum: gloved thumbs, and a mis-tap here
                        // files the weld under the wrong job.
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? _kOrange.withValues(alpha: 0.12)
                              : const Color(0xFF12141C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: selected ? _kOrange : _kBorder,
                              width: selected ? 1.5 : 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              it.fromApp
                                  ? Icons.folder_outlined
                                  : Icons.history,
                              size: 18,
                              color: selected ? _kOrange : _kMuted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    it.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? _kOrange
                                          : const Color(0xFFE7ECF3),
                                    ),
                                  ),
                                  Text(
                                    it.fromApp
                                        ? _tr('projekt w aplikacji',
                                            'project in the app')
                                        : _tr('użyty w dzienniku',
                                            'used in the journal'),
                                    style: const TextStyle(
                                        fontSize: 10, color: _kMuted),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check, size: 18, color: _kOrange),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(_tr('Anuluj', 'Cancel'),
                  style: const TextStyle(color: _kSec)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Statystyki badge ─────────────────────────────────────────────────────────
class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBadge(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: _kMuted)),
      ],
    ),
  );
}
