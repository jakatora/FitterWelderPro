/// Spoiny zapisanego odczytu skanera izometryku jako [ImportWeld] dla
/// importu do wyceny (`domain/quotes/quote_import.dart`).
///
/// Mapa spoin powstaje TĄ SAMĄ ścieżką co na ekranie przeglądu skanu
/// ([weldMapOfScan]: id odcinków → [planFromScan] → [buildWeldMap]) — numer,
/// rodzaj, rozmiar i warsztat/obiekt spoiny znaczą tu to samo co w mapie
/// spoin i w dzienniku. Rozmiar spoiny to rozmiar jej odcinka z planu;
/// gdy rysunek go nie podaje (brak DN, brak schedule) — zostaje pusty
/// i spoina trafia do pominiętych, nic nie jest zgadywane.
///
/// Odgałęzienie (BR) wymaga dwóch rozmiarów: króćca i rury głównej. Mapa
/// spoin podaje jeden (dla oletu wyprowadzonego z trasy — rury głównej),
/// więc oba są brane z odcinków spoiny i odcinków, które kończą się na jej
/// kształtce: dwa różne rozmiary → mniejszy to króciec, większy rura
/// główna; jeden rozmiar → króciec to odcinek kończący się na kształtce
/// (rura główna przechodzi przez olet). Gdy znany jest tylko rozmiar rury
/// głównej — rozmiaru króćca nie ma i spoina jest pominięta.
library;

import '../domain/quotes/quote_import.dart';
import '../domain/weld_journal/weld_entry.dart' show WeldJointType;
import 'iso_scanner_ai.dart';
import 'scan_outputs.dart';
import 'scan_to_project.dart';

/// Spoiny mapy spoin odczytu [scan], w kolejności mapy.
List<ImportWeld> importWeldsFromScan(AiScanResult scan) {
  final map = weldMapOfScan(scan);
  return [for (final w in map.welds) _importWeld(w, map.segments)];
}

ImportLocation _location(String? l) => switch (l) {
      'shop' => ImportLocation.shop,
      'field' => ImportLocation.field,
      _ => ImportLocation.unknown,
    };

ImportWeld _importWeld(PlannedWeld w, List<PlannedSegment> segments) {
  final type = w.jointType.trim().toUpperCase();
  if (type != WeldJointType.branch) {
    return ImportWeld(
      ref: w.number,
      jointType: type,
      odMm: w.odMm,
      wallMm: w.wallMm,
      position: w.position ?? '',
      location: _location(w.location),
    );
  }
  final b = _branchSizes(w, segments);
  return ImportWeld(
    ref: w.number,
    jointType: type,
    odMm: b?.branch.diameterMm,
    wallMm: b?.branch.wallThicknessMm,
    headerOdMm: b?.headerOd,
    position: w.position ?? '',
    location: _location(w.location),
  );
}

/// Króciec i rura główna spoiny odgałęzienia [w] — patrz opis biblioteki.
({PlannedSegment branch, double? headerOd})? _branchSizes(
    PlannedWeld w, List<PlannedSegment> segments) {
  final comp = w.componentId;
  bool endsAtFitting(PlannedSegment s) =>
      comp != null &&
      (s.start.componentId == comp || s.end.componentId == comp);
  final known = [
    for (final s in segments)
      if ((w.segmentIds.contains(s.sourceId) || endsAtFitting(s)) &&
          (s.diameterMm ?? 0) > 0 &&
          (s.wallThicknessMm ?? 0) > 0)
        s,
  ];
  if (known.isEmpty) return null;
  final sizes = known.map((s) => s.diameterMm!).toSet();
  if (sizes.length > 1) {
    known.sort((a, b) => a.diameterMm!.compareTo(b.diameterMm!));
    return (branch: known.first, headerOd: known.last.diameterMm);
  }
  if (comp == null) {
    // Wstawka bez kształtki: spawany jest odcinek spoiny; dwa odcinki
    // jednego rozmiaru = króciec równy rurze głównej.
    return (
      branch: known.first,
      headerOd: known.length > 1 ? known.last.diameterMm : null,
    );
  }
  final branch = known.where(endsAtFitting).toList();
  if (branch.isEmpty) return null;
  final header = known.where((s) => !endsAtFitting(s)).toList();
  return (
    branch: branch.first,
    headerOd: header.isEmpty ? null : header.first.diameterMm,
  );
}

/// Etykieta pozycji wyceny dla odczytu: „ISO 12-345 rev B" (numer rysunku
/// i rewizja z tabelki), inaczej numer linii, inaczej [fallbackName].
String scanImportLabel(AiScanResult scan, {String? fallbackName}) {
  final tb = scan.titleBlock;
  final dwg = tb.drawingNumber?.trim() ?? '';
  final rev = tb.revision?.trim() ?? '';
  if (dwg.isNotEmpty) {
    final base = dwg.toUpperCase().startsWith('ISO') ? dwg : 'ISO $dwg';
    return rev.isEmpty ? base : '$base rev $rev';
  }
  final line = tb.lineNumber?.trim() ?? '';
  if (line.isNotEmpty) return line;
  return fallbackName?.trim() ?? '';
}
