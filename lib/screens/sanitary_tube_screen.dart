import 'package:flutter/material.dart';
import '../assistant/core/tool_bridge.dart';

import '../data/sanitary_tube.dart';
import '../i18n/app_language.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/clipboard_helper.dart';

const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kBlue = Color(0xFF4A9EFF);
const _kGreen = Color(0xFF2ECC71);
const _kMuted = kTextMut; // token motywu (kontrast ≥ 4,5:1)

void _showSourceInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kCard,
      title: Text(context.tr(
          pl: 'Źródło wymiarów i wzory', en: 'Dimension source & formulas')),
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
                '     gdzie ρ = 8.0 g/cm³ (stal 316L, EN 10088-1)\n'
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
                '     where ρ = 8.0 g/cm³ (316L stainless, EN 10088-1)\n'
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

class _SanitaryTubeScreenState extends State<SanitaryTubeScreen>
    with ToolHandleHost<SanitaryTubeScreen> {
  String? _assistantSize;
  @override
  String get toolId => 'sanitary_tube';
  @override
  Set<String> get supportedFields => const {'standard', 'size'};
  @override
  void initState() {
    super.initState();
    markReady();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (fields.keys.any((k) => !supportedFields.contains(k))) {
      return fields.keys.toSet();
    }
    final standard = fields['standard'], size = fields['size'];
    if (!const ['bpe', 'din11850_ii'].contains(standard)) return {'standard'};
    final rows = standard == 'bpe' ? kBpeTube : kDin11850Tube;
    if (size is! String || !rows.any((row) => row.size == size)) {
      return {'size'};
    }
    if (!mounted) return {'size'};
    setState(() {
      _bpe = standard == 'bpe';
      _assistantSize = size;
      _q = size;
      _filter.text = size;
    });
    return {};
  }

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
    if (_assistantSize != null) {
      return src.where((row) => row.size == _assistantSize).toList();
    }
    if (_q.trim().isEmpty) return src;
    final q = _q.trim().toLowerCase();
    return src
        .where((t) =>
            t.size.toLowerCase().contains(q) ||
            t.od.toStringAsFixed(0).contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(context.tr(pl: 'Rury sanitarne (tube)', en: 'Sanitary tube')),
        actions: [
          IconButton(
            tooltip: context.tr(
                pl: 'Skąd te liczby?', en: 'Where do these come from?'),
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
                  onSelected: (_) => setState(() {
                    _bpe = true;
                    _assistantSize = null;
                  }),
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('DIN 11850'),
                  selected: !_bpe,
                  onSelected: (_) => setState(() {
                    _bpe = false;
                    _assistantSize = null;
                  }),
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    pl: 'Szukaj: 2", DN50, 51…', en: 'Search: 2", DN50, 51…'),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _q = v;
                _assistantSize = null;
              }),
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
                            pl:
                                'ASME BPE / ASTM A270 — standard farmaceutyczny, wymiar = OD calowy.',
                            en:
                                'ASME BPE / ASTM A270 — pharma standard, sized by imperial OD.')
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
                        context.tr(
                            pl: 'przytrzymaj = kopiuj', en: 'hold = copy'),
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
            child: _rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        context.tr(
                            pl: 'Brak wyników dla "${_q.trim()}" w tej normie — '
                                'sprawdź drugą zakładkę (BPE / DIN 11850).',
                            en: 'No results for "${_q.trim()}" in this standard — '
                                'check the other tab (BPE / DIN 11850).'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _kMuted, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.builder(
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
        color: c,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3);
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
          SizedBox(
              width: 64,
              child: Text(context.tr(pl: 'ROZMIAR', en: 'SIZE'),
                  style: s(_kMuted))),
          Expanded(
              child:
                  Text('OD', textAlign: TextAlign.center, style: s(_kOrange))),
          Expanded(
              child: Text(context.tr(pl: 'ŚCIANKA', en: 'WALL'),
                  textAlign: TextAlign.center, style: s(_kBlue))),
          Expanded(
              child:
                  Text('ID', textAlign: TextAlign.center, style: s(_kMuted))),
          Expanded(
              child:
                  Text('kg/m', textAlign: TextAlign.center, style: s(_kMuted))),
          Expanded(
              child:
                  Text('L/m', textAlign: TextAlign.center, style: s(_kGreen))),
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
                        color: Color(0xFFE7ECF3),
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                if (t.wallNote.isNotEmpty)
                  Text(t.wallNote,
                      style: const TextStyle(color: _kMuted, fontSize: 9)),
              ],
            ),
          ),
          _Cell(
              value: t.od.toStringAsFixed(2),
              color: _kOrange,
              label: '${t.size} OD'),
          _Cell(
              value: t.wall.toStringAsFixed(2),
              color: _kBlue,
              label: '${t.size} wall'),
          _Cell(
              value: t.id.toStringAsFixed(2),
              color: const Color(0xFFE7ECF3),
              label: '${t.size} ID'),
          _Cell(
              value: t.massPerMeter.toStringAsFixed(2),
              color: _kMuted,
              label: '${t.size} kg/m'),
          _Cell(
              value: t.litresPerMeter.toStringAsFixed(3),
              color: _kGreen,
              label: '${t.size} L/m'),
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
