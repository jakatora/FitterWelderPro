import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../data/nps_dn_od_r.dart';
import '../widgets/help_button.dart';

class DnMmScreen extends StatefulWidget {
  const DnMmScreen({super.key});

  @override
  State<DnMmScreen> createState() => _DnMmScreenState();
}

class _DnMmScreenState extends State<DnMmScreen> {
  final _dnCtrl = TextEditingController();
  final _mmCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _dnCtrl.dispose();
    _mmCtrl.dispose();
    super.dispose();
  }

  List<NpsRow> _filter() {
    final q = _q.trim().toLowerCase();
    int? dn = int.tryParse(_dnCtrl.text.trim());
    double? mm = double.tryParse(_mmCtrl.text.replaceAll(',', '.').trim());

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
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'DN', hintText: context.tr(pl: 'np. 50', en: 'e.g. 50')),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _mmCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'OD [mm]', hintText: context.tr(pl: 'np. 60.3', en: 'e.g. 60.3')),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(labelText: context.tr(pl: 'Szukaj (NPS/DN/OD/R)', en: 'Search (NPS/DN/OD/R)'), prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('NPS')),
                    DataColumn(label: Text('DN')),
                    DataColumn(label: Text('OD [mm]')),
                    DataColumn(label: Text('R [mm]')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(cells: [
                        DataCell(Text(r.nps)),
                        DataCell(Text(r.dn.toString())),
                        DataCell(Text(r.odMm.toStringAsFixed(r.odMm % 1 == 0 ? 0 : 2))),
                        DataCell(Text(r.rMm.toStringAsFixed(r.rMm % 1 == 0 ? 0 : 2))),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
