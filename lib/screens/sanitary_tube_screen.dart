import 'package:flutter/material.dart';

import '../data/sanitary_tube.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kMuted  = Color(0xFF55607A);

/// Sanitary / hygienic TUBE lookup — the table a food & pharma fitter actually
/// works to (OD-based, not Schedule). Long-press any value to copy it.
class SanitaryTubeScreen extends StatefulWidget {
  const SanitaryTubeScreen({super.key});

  @override
  State<SanitaryTubeScreen> createState() => _SanitaryTubeScreenState();
}

class _SanitaryTubeScreenState extends State<SanitaryTubeScreen> {
  bool _bpe = true;
  String _q = '';
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<SanitaryTube> get _rows {
    final src = _bpe ? kBpeTube : kDin11850Tube;
    if (_q.trim().isEmpty) return src;
    final q = _q.trim().toLowerCase();
    return src.where((t) => t.size.toLowerCase().contains(q) ||
        t.od.toStringAsFixed(0).contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Rury sanitarne (tube)', en: 'Sanitary tube')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('ASME BPE'),
                  selected: _bpe,
                  onSelected: (_) => setState(() => _bpe = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('DIN 11850'),
                  selected: !_bpe,
                  onSelected: (_) => setState(() => _bpe = false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: context.tr(
                    pl: 'Szukaj: 2", DN50, 51…',
                    en: 'Search: 2", DN50, 51…'),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              _bpe
                  ? context.tr(
                      pl: 'ASME BPE / ASTM A270 — standard farmaceutyczny, wymiar = OD calowy.',
                      en: 'ASME BPE / ASTM A270 — pharma standard, sized by imperial OD.')
                  : context.tr(
                      pl: 'DIN 11850 — metryczna rura mleczarska, standard spożywczy UE.',
                      en: 'DIN 11850 — metric dairy tube, EU food-industry standard.'),
              style: const TextStyle(color: _kMuted, fontSize: 11),
            ),
          ),
          const _HeaderRow(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              itemCount: _rows.length,
              itemBuilder: (_, i) => _Row(t: _rows[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();
  @override
  Widget build(BuildContext context) {
    TextStyle s(Color c) => TextStyle(
        color: c, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text('SIZE', style: s(_kMuted))),
          Expanded(child: Text('OD', textAlign: TextAlign.center, style: s(_kOrange))),
          Expanded(child: Text('WALL', textAlign: TextAlign.center, style: s(_kBlue))),
          Expanded(child: Text('ID', textAlign: TextAlign.center, style: s(_kMuted))),
          Expanded(child: Text('kg/m', textAlign: TextAlign.center, style: s(_kMuted))),
          Expanded(child: Text('L/m', textAlign: TextAlign.center, style: s(_kGreen))),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final SanitaryTube t;
  const _Row({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.size,
                    style: const TextStyle(
                        color: Color(0xFFE8ECF0),
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                if (t.wallNote.isNotEmpty)
                  Text(t.wallNote,
                      style: const TextStyle(color: _kMuted, fontSize: 9)),
              ],
            ),
          ),
          _Cell(value: t.od.toStringAsFixed(2), color: _kOrange, label: '${t.size} OD'),
          _Cell(value: t.wall.toStringAsFixed(2), color: _kBlue, label: '${t.size} wall'),
          _Cell(value: t.id.toStringAsFixed(2), color: const Color(0xFFE8ECF0), label: '${t.size} ID'),
          _Cell(value: t.massPerMeter.toStringAsFixed(2), color: _kMuted, label: '${t.size} kg/m'),
          _Cell(value: t.litresPerMeter.toStringAsFixed(3), color: _kGreen, label: '${t.size} L/m'),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final Color color;
  final String label;
  const _Cell({required this.value, required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CopyOnLongPress(
        value: value,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
