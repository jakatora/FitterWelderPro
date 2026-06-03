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

void _showSourceInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kCard,
      title: Text(context.tr(
          pl: 'Źródło wymiarów i wzory',
          en: 'Dimension source & formulas')),
      content: SingleChildScrollView(
        child: Text(
          context.tr(
            pl: 'ASME BPE / ASTM A270 — rura calowa hygenic (1/2"–6"), '
                'wymiar = OD imperialny, ścianki klasy A270 std.\n\n'
                'DIN 11850 — rura metryczna mleczarska, seria II '
                '(domyślnie), OD w mm.\n\n'
                'Wzory tabelaryczne:\n'
                '  ID = OD − 2·wall\n'
                '  kg/m = π · (OD − wall) · wall · ρ / 1000\n'
                '     gdzie ρ = 7.93 g/cm³ (stal 316L)\n'
                '  L/m = π · ID² / 4000  (ID w mm → litry)\n\n'
                'Tolerancje OD/ścianki wg normy — sprawdź atest rury '
                'przed obliczeniem wsadu spawalniczego.',
            en: 'ASME BPE / ASTM A270 — imperial hygienic tube '
                '(1/2"–6"), sized by imperial OD, A270 standard wall.\n\n'
                'DIN 11850 — metric dairy tube, series II (default), '
                'OD in mm.\n\n'
                'Table formulas:\n'
                '  ID = OD − 2·wall\n'
                '  kg/m = π · (OD − wall) · wall · ρ / 1000\n'
                '     where ρ = 7.93 g/cm³ (316L stainless)\n'
                '  L/m = π · ID² / 4000  (ID in mm → litres)\n\n'
                'OD/wall tolerances per the standard — check the mill '
                'cert before sizing weld consumables.',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(context.tr(pl: 'OK', en: 'OK')),
        ),
      ],
    ),
  );
}

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
        actions: [
          IconButton(
            tooltip: context.tr(pl: 'Skąd te liczby?', en: 'Where do these come from?'),
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSourceInfo(context),
          ),
        ],
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
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('DIN 11850'),
                  selected: !_bpe,
                  onSelected: (_) => setState(() => _bpe = false),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
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
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 8),
                Tooltip(
                  message: context.tr(
                      pl: 'Przytrzymaj dowolną liczbę aby skopiować',
                      en: 'Long-press any value to copy'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app, size: 11, color: _kMuted),
                      const SizedBox(width: 3),
                      Text(
                        context.tr(pl: 'przytrzymaj = kopiuj',
                            en: 'hold = copy'),
                        style: const TextStyle(
                            color: _kMuted,
                            fontSize: 10,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
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
