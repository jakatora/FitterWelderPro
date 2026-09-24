import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../data/nps_dn_od_r.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

/// Short label of the dimensional series of an OD row.
String _seriesLabel(BuildContext context, OdSeries s) => switch (s) {
      OdSeries.asme => 'ASME',
      OdSeries.en1 => 'EN s.1',
      OdSeries.asmeAndEn1 => 'ASME / EN s.1',
      OdSeries.en2 => 'EN s.2',
      OdSeries.en3 => 'EN s.3',
      OdSeries.other => context.tr(pl: 'inna', en: 'other'),
    };

class DnMmScreen extends StatefulWidget {
  const DnMmScreen({super.key});

  @override
  State<DnMmScreen> createState() => _DnMmScreenState();
}

class _DnMmScreenState extends State<DnMmScreen> {
  final _dnCtrl = TextEditingController();
  final _mmCtrl = TextEditingController();
  final _mmFocus = FocusNode();
  final _searchFocus = FocusNode();
  String _q = '';

  @override
  void dispose() {
    _dnCtrl.dispose();
    _mmCtrl.dispose();
    _mmFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<NpsRow> _filter() {
    final q = _q.trim().toLowerCase();
    int? dn = int.tryParse(_dnCtrl.text.trim());
    double? mm = parseDecimal(_mmCtrl.text);

    return kNpsTable.where((r) {
      if (dn != null && r.dn == dn) return true;
      if (mm != null && (r.odMm - mm).abs() < 0.25) return true;
      if (q.isEmpty) return dn == null && mm == null;
      return r.nps.toLowerCase().contains(q) ||
          r.dn.toString().contains(q) ||
          r.odMm.toString().contains(q) ||
          r.rMm.toString().contains(q);
    }).toList();
  }

  void _clear() {
    setState(() {
      _dnCtrl.clear();
      _mmCtrl.clear();
      _q = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filter();
    return Scaffold(
      appBar: AppBar(
        title: const Text('DN-MM'),
        actions: [
          HelpButton(help: kHelpDnMm),
          IconButton(tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'), icon: const Icon(Icons.clear_all), onPressed: _clear),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dnCtrl,
                    keyboardType: numberKeyboard(decimal: false),
                    inputFormatters: numberInputFormatters(decimal: false),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: 'DN', hintText: context.tr(pl: 'np. 50', en: 'e.g. 50')),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _mmFocus.requestFocus(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _mmCtrl,
                    focusNode: _mmFocus,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: 'OD [mm]', hintText: context.tr(pl: 'np. 60,3', en: 'e.g. 60.3')),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _searchFocus.requestFocus(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(labelText: context.tr(pl: 'Szukaj (NPS/DN/OD/R)', en: 'Search (NPS/DN/OD/R)'), prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          (_dnCtrl.text.trim().isEmpty && _mmCtrl.text.trim().isEmpty && _q.trim().isEmpty)
                              ? context.tr(
                                  pl: 'Wpisz DN, OD [mm] lub szukaj, aby zobaczyć wymiary.',
                                  en: 'Enter DN, OD [mm], or search to see sizes.')
                              : context.tr(
                                  pl: 'Brak wyników dla podanych kryteriów.',
                                  en: 'No results for the given criteria.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  : _table(context, rows),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context, List<NpsRow> rows) {
    String fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: [
                const DataColumn(label: Text('NPS')),
                const DataColumn(label: Text('DN')),
                const DataColumn(label: Text('OD [mm]')),
                const DataColumn(label: Text('R [mm]')),
                DataColumn(label: Text(context.tr(pl: 'Seria', en: 'Series'))),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    // Long-press a reference row to copy it as a
                    // single line (e.g. into a chat/SMS to a foreman).
                    // copyToClipboard already fires Haptic.copied().
                    onLongPress: () => copyToClipboard(
                      context,
                      '${r.nps}  DN${r.dn}  OD ${fmt(r.odMm)} mm  R ${fmt(r.rMm)} mm',
                      label: 'DN/OD',
                    ),
                    cells: [
                      DataCell(Text(r.nps)),
                      DataCell(Text(r.dn.toString())),
                      DataCell(Text(fmt(r.odMm))),
                      DataCell(Text(fmt(r.rMm))),
                      DataCell(Text(_seriesLabel(context, r.series))),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              context.tr(
                pl: 'R — promień kolana LR (= wymiar A kolana 90°) wg ASME B16.9 / EN 10253-2 dla serii ASME i EN s.1. '
                    'Dla EN s.2 / s.3 i „inna” wartość orientacyjna — sprawdź kartę kolana. '
                    'NPS 3 1/2" to DN90.',
                en: 'R — LR elbow radius (= dimension A of the 90° elbow) per ASME B16.9 / EN 10253-2 for the ASME and EN s.1 series. '
                    'For EN s.2 / s.3 and "other" it is indicative only — check the elbow datasheet. '
                    'NPS 3 1/2" is DN90.',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
