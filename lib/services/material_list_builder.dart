import '../database/component_library_dao.dart';
import '../database/segment_dao.dart';
import '../models/material_item.dart';

class MaterialListBuilder {
  final SegmentDao _segments;
  final ComponentLibraryDao _library;

  MaterialListBuilder(this._segments, this._library);

  Future<List<MaterialItem>> buildForProject(String projectId) async {
    final segs = await _segments.listForProject(projectId);

    // PIPE totals (length sum by diameter+wall)
    final pipeMap = <String, double>{};
    for (final s in segs) {
      final key = 'PIPE|${s.diameterMm}|${s.wallThicknessMm}';
      pipeMap[key] = (pipeMap[key] ?? 0) + s.cutMm;
    }

    // Component counts: każdy unikalny library_id = jeden fizyczny element.
    //
    // NAPRAWIONO: poprzedni kod liczył addComp(start) + addComp(end)
    // co powodowało podwójne liczenie złączki będącej jednocześnie
    // końcem segmentu N i początkiem segmentu N+1 (np. trójnik w środku trasy).
    //
    // Poprawne podejście: zbieramy unikalne ID (Set), każde ID = 1 sztuka.
    final uniqueCompIds = <String>{};
    for (final s in segs) {
      if (s.startLibraryId != null) uniqueCompIds.add(s.startLibraryId!);
      if (s.endLibraryId != null) uniqueCompIds.add(s.endLibraryId!);
    }
    final compCounts = {for (final id in uniqueCompIds) id: 1};

    // Resolve component labels
    final items = <MaterialItem>[];

    // Pipes first
    for (final e in pipeMap.entries) {
      final parts = e.key.split('|');
      final diameter = double.parse(parts[1]);
      final wall = double.parse(parts[2]);
      items.add(
        MaterialItem(
          category: 'PIPE',
          description: 'Pipe Ø${diameter.toStringAsFixed(1)} x ${wall.toStringAsFixed(1)}',
          totalLengthMm: e.value,
        ),
      );
    }

    // Components
    for (final entry in compCounts.entries) {
      final comp = await _library.getById(entry.key);
      if (comp == null) continue;
      items.add(
        MaterialItem(
          category: comp.type,
          description: comp.displayLabel(),
          quantity: entry.value,
        ),
      );
    }

    // Sort: pipes first, then by category
    items.sort((a, b) {
      if (a.category == 'PIPE' && b.category != 'PIPE') return -1;
      if (a.category != 'PIPE' && b.category == 'PIPE') return 1;
      return a.category.compareTo(b.category);
    });

    return items;
  }
}
