/// Kontrola spoiny z dziennika przez [WelderQualificationService.checkWeld]
/// — WPS z biblioteki i uprawnienia KAŻDEGO stempla spoiny (spawacz, grań,
/// lico) w dniu spawania.
library;

import '../database/wps_dao.dart';
import '../domain/weld_journal/weld_compliance.dart';
import '../domain/weld_journal/weld_entry.dart';
import '../domain/wps/weld_range_check.dart';
import 'welder_qualification_service.dart';

/// Sygnatura kontroli — edytor spoiny dostaje ją z zewnątrz (testy).
typedef WeldComplianceCheck = Future<WeldCompliance> Function(
  WeldEntry entry, {
  String? wpsId,
});

/// [wpsId] — WPS wybrana z listy w edytorze; bez niej wpis `wps_ref`
/// (także stary wolny tekst, także z rewizją „rev. B") jest dopasowywany do
/// biblioteki przez [resolveWpsRef].
Future<WeldCompliance> checkWeldCompliance(
  WeldEntry entry, {
  String? wpsId,
  DateTime? now,
}) async {
  var id = wpsId;
  // After a library lookup by text the number fallback of checkWeld has
  // nothing left to find — resolveWpsRef already tried the bare number.
  var wpsNo = entry.wpsRef;
  if ((id == null || id.isEmpty) && entry.wpsRef.trim().isNotEmpty) {
    id = resolveWpsRef(entry.wpsRef, await WpsDao().listAll())?.id;
    wpsNo = '';
  }
  final weld = weldParametersOf(entry);
  final date = weldDateOf(entry, fallback: now ?? DateTime.now());
  final service = WelderQualificationService.instance;
  WeldCheckReport? first;
  final welders = <WelderStampCoverage>[];
  for (final stamp in stampsToCheck(entry)) {
    final report = await service.checkWeld(
      weld: weld,
      weldDate: date,
      wpsId: id,
      wpsNo: wpsNo,
      welderStamp: stamp.isEmpty ? null : stamp,
    );
    first ??= report;
    welders.add(WelderStampCoverage(stamp, report.welder));
  }
  return WeldCompliance(
    wpsRef: entry.wpsRef,
    wps: first?.wps,
    wpsIssues: first?.wpsIssues ?? const <RangeIssue>[],
    welders: welders,
    weldDate: date,
  );
}
