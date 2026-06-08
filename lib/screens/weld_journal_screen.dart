// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../database/db.dart';
import '../i18n/app_language.dart';
import '../widgets/help_button.dart';

// ── Kolory ─────────────────────────────────────────────────────────────────
const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kMuted  = Color(0xFF55607A);
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

// ── DAO ─────────────────────────────────────────────────────────────────────
class WeldJournalDao {
  static const _table = 'weld_journal';

  Future<void> _ensureTable() async {
    final db = await AppDatabase.get();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        weld_no TEXT,
        project_name TEXT,
        pipe_name TEXT,
        material TEXT,
        od TEXT,
        t TEXT,
        method TEXT,
        welder TEXT,
        date TEXT,
        notes TEXT,
        status TEXT,
        weld_type TEXT,
        fitter TEXT,
        heat_no1 TEXT,
        heat_no2 TEXT,
        coupon_ref TEXT,
        exam TEXT,
        wps_ref TEXT
      )
    ''');
    // Migrate older databases that predate the ASME BPE weld-map columns.
    //
    // P0r-08: query the actual schema via PRAGMA table_info instead of
    // relying on SQLite's localized error messages. Substring-matching
    // "duplicate column" / "already exists" breaks on Huawei/Xiaomi ROMs
    // that translate SQLite error strings — a benign re-migration would
    // rethrow as fatal and block the journal cold-start. The PRAGMA path
    // is idempotent by construction and never raises the exception in the
    // first place.
    final existing = <String>{};
    try {
      final info = await db.rawQuery('PRAGMA table_info($_table)');
      for (final row in info) {
        final name = row['name'] as String?;
        if (name != null) existing.add(name);
      }
    } catch (_) {
      // PRAGMA failure is rare but recoverable — fall back to the original
      // try/catch ALTER approach so legacy DBs still migrate.
    }
    for (final col in const [
      'weld_type', 'fitter', 'heat_no1', 'heat_no2', 'coupon_ref', 'exam',
      'wps_ref',
    ]) {
      if (existing.contains(col)) continue;
      try {
        await db.execute('ALTER TABLE $_table ADD COLUMN $col TEXT');
      } catch (e) {
        // Belt-and-braces: if PRAGMA missed the column (e.g. concurrent
        // migration on another isolate) and ALTER fails as a duplicate,
        // silently swallow only that case. Anything else bubbles up.
        final msg = e.toString().toLowerCase();
        final isDuplicate = msg.contains('duplicate column') ||
            msg.contains('already exists');
        if (!isDuplicate) rethrow;
      }
    }
  }

  Future<List<WeldEntry>> listAll() async {
    await _ensureTable();
    final db = await AppDatabase.get();
    final rows = await db.query(_table, orderBy: 'weld_no ASC');
    return rows.map(WeldEntry.fromRow).toList();
  }

  Future<void> insert(WeldEntry e) async {
    await _ensureTable();
    final db = await AppDatabase.get();
    await db.insert(_table, e.toRow());
  }

  Future<void> update(WeldEntry e) async {
    await _ensureTable();
    final db = await AppDatabase.get();
    await db.update(_table, e.toRow(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(String id) async {
    await _ensureTable();
    final db = await AppDatabase.get();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// EKRAN DZIENNIKA
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class WeldJournalScreen extends StatefulWidget {
  const WeldJournalScreen({super.key});
  @override State<WeldJournalScreen> createState() => _WeldJournalScreenState();
}

class _WeldJournalScreenState extends State<WeldJournalScreen> {
  final _dao = WeldJournalDao();
  List<WeldEntry> _entries = [];
  bool _loading = true;
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

  List<WeldEntry> get _filtered =>
      _filter == 'ALL' ? _entries : _entries.where((e) => e.status == _filter).toList();

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

  Future<void> _openEditor(WeldEntry? existing) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1D26),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WeldEditor(
        entry: existing,
        suggestedNo: suggestNextWeldNo(existing?.projectName),
        suggester: suggestNextWeldNo,
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
                    Text(entry.weldNo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFE8ECF0))),
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
  const _WeldEditor({
    required this.entry,
    required this.suggestedNo,
    required this.suggester,
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

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _noCtrl     = TextEditingController(text: e?.weldNo     ?? widget.suggestedNo);
    _projCtrl   = TextEditingController(text: e?.projectName ?? '');
    _pipeCtrl   = TextEditingController(text: e?.pipeName    ?? '');
    _matCtrl    = TextEditingController(text: e?.material    ?? '316L');
    _odCtrl     = TextEditingController(text: e?.od          ?? '');
    _tCtrl      = TextEditingController(text: e?.t           ?? '');
    _welderCtrl = TextEditingController(text: e?.welder      ?? '');
    _dateCtrl   = TextEditingController(text: e?.date        ?? _today());
    _notesCtrl  = TextEditingController(text: e?.notes       ?? '');
    _fitterCtrl = TextEditingController(text: e?.fitter      ?? '');
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.entry == null ? _tr('Nowa spoina', 'New weld') : _tr('Edytuj spoinę', 'Edit weld'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFE8ECF0)),
            ),
            const SizedBox(height: 16),
            // Numer spoiny
            TextField(
              controller: _noCtrl,
              decoration: InputDecoration(
                labelText: _tr('Numer spoiny', 'Weld number'),
                hintText: 'W-001 lub SP-001-W005',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  tooltip: _tr('Następny numer wg projektu', 'Next number for this project'),
                  onPressed: () => setState(() {
                    _noCtrl.text = widget.suggester(_projCtrl.text);
                  }),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              // Keyboard Next advances Project -> Pipe -> Material in one tap
              // so gloved fingers don't have to dismiss + re-tap each field.
              Expanded(child: TextField(
                controller: _projCtrl,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: InputDecoration(labelText: _tr('Projekt', 'Project')),
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
                            color: Color(0xFFE8ECF0)),
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
