import 'package:flutter/material.dart';

import '../data/pipe_schedules.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kMuted  = Color(0xFF55607A);

/// Wall thickness lookup per ASME B36.10M / B36.19M.
/// Long-press a wall to copy. Switch between wall-mm and kg/m view via the
/// chip row at the top — same table, two readings a fitter actually asks for.
class PipeScheduleScreen extends StatefulWidget {
  const PipeScheduleScreen({super.key});

  @override
  State<PipeScheduleScreen> createState() => _PipeScheduleScreenState();
}

class _PipeScheduleScreenState extends State<PipeScheduleScreen> {
  String _q = '';
  bool _showMass = false;
  bool _stainless = false;
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<PipeRow> get _rows {
    if (_q.trim().isEmpty) return kPipeWalls;
    final q = _q.trim().toLowerCase();
    return kPipeWalls.where((r) =>
        '${r.dn}'.contains(q) ||
        r.nps.toLowerCase().contains(q) ||
        'dn${r.dn}'.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Grubości ścianek / Sch',
            en: 'Wall thickness / Sch')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: context.tr(
                    pl: 'Szukaj: DN50, 2", 100…',
                    en: 'Search: DN50, 2", 100…'),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(context.tr(pl: 'Ścianka mm', en: 'Wall mm')),
                  selected: !_showMass,
                  onSelected: (_) => setState(() => _showMass = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('kg/m'),
                  selected: _showMass,
                  onSelected: (_) => setState(() => _showMass = true),
                ),
                const Spacer(),
                if (_showMass)
                  ChoiceChip(
                    label: Text(_stainless ? 'SS' : 'CS'),
                    selected: _stainless,
                    onSelected: (_) => setState(() => _stainless = !_stainless),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _Header(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              itemCount: _rows.length,
              itemBuilder: (_, i) => _Row(
                row: _rows[i],
                showMass: _showMass,
                stainless: _stainless,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text('DN / OD',
                style: TextStyle(
                    color: _kMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          ...kSchedules.map((s) => Expanded(
                child: Text(s,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _kOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4)),
              )),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final PipeRow row;
  final bool showMass;
  final bool stainless;
  const _Row({
    required this.row,
    required this.showMass,
    required this.stainless,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DN${row.dn}',
                    style: const TextStyle(
                        color: Color(0xFFE8ECF0),
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                Text('Ø ${row.od.toStringAsFixed(1)}',
                    style: const TextStyle(color: _kMuted, fontSize: 10)),
              ],
            ),
          ),
          ...kSchedules.map((s) {
            final w = row.walls[s];
            if (w == null) {
              return const Expanded(
                child: Text('—',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kMuted, fontSize: 12)),
              );
            }
            final txt = showMass
                ? massPerMeter(row, s, stainless: stainless)!.toStringAsFixed(1)
                : w.toStringAsFixed(2);
            return Expanded(
              child: CopyOnLongPress(
                value: txt,
                label: 'DN${row.dn} Sch $s',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(txt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _kBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
