import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/db.dart';
import '../i18n/app_language.dart';
import '../utils/haptic.dart';

const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kMuted  = Color(0xFF55607A);
const _kSec    = Color(0xFF9BA3C7);

/// A test coupon ("kupon próbny") is a sacrificial weld a welder makes — on
/// food & pharma work, usually at the start of every shift and on every
/// machine — and gets accepted before touching production. This screen is
/// that daily log, which an auditor will ask for.
class CouponEntry {
  final String id;
  String date;
  String welder;
  String machine;   // orbital machine / weld-head identifier
  String size;      // tube OD × wall
  String result;    // OK / NOK
  String notes;

  CouponEntry({
    required this.id,
    required this.date,
    required this.welder,
    required this.machine,
    required this.size,
    required this.result,
    required this.notes,
  });

  Map<String, Object?> toRow() => {
        'id': id, 'date': date, 'welder': welder, 'machine': machine,
        'size': size, 'result': result, 'notes': notes,
      };

  static CouponEntry fromRow(Map<String, Object?> r) => CouponEntry(
        id: r['id'] as String,
        date: (r['date'] as String?) ?? '',
        welder: (r['welder'] as String?) ?? '',
        machine: (r['machine'] as String?) ?? '',
        size: (r['size'] as String?) ?? '',
        result: (r['result'] as String?) ?? 'OK',
        notes: (r['notes'] as String?) ?? '',
      );
}

class CouponDao {
  static const _table = 'weld_coupons';

  Future<void> _ensure() async {
    final db = await AppDatabase.get();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        date TEXT, welder TEXT, machine TEXT,
        size TEXT, result TEXT, notes TEXT
      )
    ''');
  }

  Future<List<CouponEntry>> listAll() async {
    await _ensure();
    final db = await AppDatabase.get();
    final rows = await db.query(_table, orderBy: 'date DESC');
    return rows.map(CouponEntry.fromRow).toList();
  }

  Future<void> insert(CouponEntry e) async {
    await _ensure();
    final db = await AppDatabase.get();
    await db.insert(_table, e.toRow());
  }

  Future<void> delete(String id) async {
    await _ensure();
    final db = await AppDatabase.get();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}

class CouponLogScreen extends StatefulWidget {
  const CouponLogScreen({super.key});

  @override
  State<CouponLogScreen> createState() => _CouponLogScreenState();
}

class _CouponLogScreenState extends State<CouponLogScreen> {
  final _dao = CouponDao();
  List<CouponEntry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _dao.listAll();
    if (!mounted) return;
    setState(() {
      _items = all;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CouponEditor(),
    );
    if (saved == true) {
      await Haptic.saved();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Log kuponów próbnych', en: 'Test coupon log')),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _add),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.science_outlined,
                            size: 48, color: _kMuted),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            pl: 'Brak kuponów. Dotknij + aby dodać pierwszy kupon dnia.',
                            en: 'No coupons yet. Tap + to add the first coupon of the day.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _kMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _CouponTile(
                    entry: _items[i],
                    onDelete: () async {
                      await _dao.delete(_items[i].id);
                      _load();
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Kupon', en: 'Coupon')),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  final CouponEntry entry;
  final VoidCallback onDelete;
  const _CouponTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final ok = entry.result == 'OK';
    final c = ok ? _kGreen : _kRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.withValues(alpha: 0.4)),
            ),
            child: Text(entry.result,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (entry.welder.isNotEmpty) entry.welder,
                    if (entry.machine.isNotEmpty) entry.machine,
                    if (entry.size.isNotEmpty) entry.size,
                  ].join('  ·  '),
                  style: const TextStyle(
                      color: Color(0xFFE8ECF0),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                if (entry.date.isNotEmpty)
                  Text(entry.date,
                      style: const TextStyle(color: _kMuted, fontSize: 11)),
                if (entry.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(entry.notes,
                        style: const TextStyle(color: _kSec, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.delete_outline, size: 20, color: _kMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponEditor extends StatefulWidget {
  const _CouponEditor();
  @override
  State<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<_CouponEditor> {
  static const _uuid = Uuid();
  final _dao = CouponDao();
  final _welder = TextEditingController();
  final _machine = TextEditingController();
  final _size = TextEditingController();
  final _notes = TextEditingController();
  late final TextEditingController _date;
  String _result = 'OK';
  bool _saving = false;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _date = TextEditingController(
        text: '${n.year}-${n.month.toString().padLeft(2, '0')}-'
            '${n.day.toString().padLeft(2, '0')}');
  }

  @override
  void dispose() {
    for (final c in [_welder, _machine, _size, _notes, _date]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _dao.insert(CouponEntry(
        id: _uuid.v4(),
        date: _date.text.trim(),
        welder: _welder.text.trim(),
        machine: _machine.text.trim(),
        size: _size.text.trim(),
        result: _result,
        notes: _notes.text.trim(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie zapisano kuponu. Spróbuj ponownie.',
          en: 'Coupon not saved. Try again.',
        )),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            16, 18, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_tr('Nowy kupon próbny', 'New test coupon'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE8ECF0))),
              const SizedBox(height: 16),
              TextField(controller: _date, decoration: InputDecoration(labelText: _tr('Data', 'Date'))),
              const SizedBox(height: 10),
              TextField(controller: _welder, decoration: InputDecoration(labelText: _tr('Spawacz', 'Welder'))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _machine, decoration: InputDecoration(labelText: _tr('Maszyna / głowica', 'Machine / head')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _size, decoration: InputDecoration(labelText: _tr('Wymiar (OD×t)', 'Size (OD×t)'), hintText: '2"×1.65'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Text(_tr('Wynik:', 'Result:'),
                    style: const TextStyle(fontSize: 13, color: _kSec)),
                const SizedBox(width: 12),
                for (final r in [('OK', _kGreen), ('NOK', _kRed)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _result = r.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: _result == r.$1
                              ? r.$2.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _result == r.$1 ? r.$2 : _kBorder,
                              width: _result == r.$1 ? 1.5 : 1),
                        ),
                        child: Text(r.$1,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _result == r.$1 ? r.$2 : _kSec)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: _tr('Uwagi', 'Notes'),
                    hintText: _tr('np. boroskop poz. 2, przetop OK',
                        'e.g. borescope lvl 2, full penetration OK')),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving
                    ? _tr('Zapisywanie...', 'Saving...')
                    : _tr('Zapisz', 'Save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
