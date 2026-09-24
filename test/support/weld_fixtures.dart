import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/domain/weld_journal/weld_repair.dart';

/// Spoina do testów: podajesz tylko to, co test sprawdza, reszta jest pusta
/// tak, jak zostawia ją niewypełniony formularz.
WeldEntry weld(
  String id, {
  String? weldNo,
  String project = 'Blok 4',
  String line = 'L-12',
  String iso = '',
  String welder = 'JK-12',
  String rootWelder = '',
  String capWelder = '',
  String date = '2026-09-20',
  String status = 'PENDING',
  String material = '316L',
  Map<NdtMethod, WeldNdt> ndt = const {},
  List<WeldRepair> repairs = const [],
  int? deletedAt,
}) =>
    WeldEntry(
      id: id,
      weldNo: weldNo ?? id,
      projectName: project,
      pipeName: line,
      material: material,
      od: '60.3',
      t: '2.0',
      method: 'TIG',
      welder: welder,
      date: date,
      notes: '',
      status: status,
      isoDrawing: iso,
      rootWelder: rootWelder,
      capWelder: capWelder,
      ndt: ndt,
      repairs: repairs,
      deletedAt: deletedAt,
    );

/// Wynik badania w skrócie: `ndtOf(NdtScope.selected, NdtResult.ok)`.
WeldNdt ndtOf(String scope, [String result = '', String report = '']) =>
    WeldNdt(scope: scope, result: result, reportNo: report);
