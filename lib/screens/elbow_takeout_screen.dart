import 'package:flutter/material.dart';

import '../data/elbow_takeouts.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);
const _kAccent = Color(0xFF4A9EFF);

/// Quick reference: centre-to-face dimensions for butt-weld elbows.
/// Long-press any number to copy it.
class ElbowTakeoutScreen extends StatefulWidget {
  const ElbowTakeoutScreen({super.key});

  @override
  State<ElbowTakeoutScreen> createState() => _ElbowTakeoutScreenState();
}

class _ElbowTakeoutScreenState extends State<ElbowTakeoutScreen> {
  final _filter = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<ElbowTakeout> get _rows {
    if (_q.trim().isEmpty) return kElbowTakeouts;
    final q = _q.trim().toLowerCase();
    return kElbowTakeouts.where((e) =>
        '${e.dn}'.contains(q) ||
        e.nps.toLowerCase().contains(q) ||
        'dn${e.dn}'.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Wymiary kolan (centre–face)',
            en: 'Elbow takeouts (centre-to-face)')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
          const _LegendBar(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              itemCount: _rows.length,
              itemBuilder: (_, i) => _Row(e: _rows[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  const _LegendBar();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: const [
          _LegendChip(label: 'DN / NPS', color: _kMuted),
          _LegendChip(label: 'LR 90°',   color: _kOrange),
          _LegendChip(label: 'SR 90°',   color: _kAccent),
          _LegendChip(label: 'LR 45°',   color: _kSec),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final ElbowTakeout e;
  const _Row({required this.e});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DN${e.dn}',
                    style: const TextStyle(
                        color: Color(0xFFE8ECF0),
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                Text('NPS ${e.nps}"',
                    style: const TextStyle(color: _kMuted, fontSize: 11)),
              ],
            ),
          ),
          _Cell(value: '${e.lr90}', unit: 'mm', color: _kOrange),
          _Cell(value: '${e.sr90}', unit: 'mm', color: _kAccent),
          _Cell(value: '${e.lr45}', unit: 'mm', color: _kSec),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final String unit;
  final Color color;
  const _Cell({required this.value, required this.unit, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CopyOnLongPress(
        value: value,
        label: 'centre–face',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text(unit,
                  style: const TextStyle(
                      color: _kMuted, fontSize: 10, height: 1)),
            ],
          ),
        ),
      ),
    );
  }
}
