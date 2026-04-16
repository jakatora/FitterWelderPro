import 'package:flutter/material.dart';
import '../data/nps_dn_od_r.dart';

class NpsTableSheet extends StatefulWidget {
  const NpsTableSheet({super.key});

  static void open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const NpsTableSheet(),
    );
  }

  @override
  State<NpsTableSheet> createState() => _NpsTableSheetState();
}

class _NpsTableSheetState extends State<NpsTableSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = kNpsTable.where((r) {
      if (_q.trim().isEmpty) return true;
      final q = _q.trim().toLowerCase();
      return r.nps.toLowerCase().contains(q) ||
          r.dn.toString().contains(q) ||
          r.odMm.toString().contains(q) ||
          r.rMm.toString().contains(q);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          children: [
            const Text('DN-MM / NPS / OD / R', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Szukaj (np. 2", 50, 60.3)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
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
                    for (final r in filtered)
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
