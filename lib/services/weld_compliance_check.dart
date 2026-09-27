/// Kontrola spoiny z dziennika — WPS z biblioteki (w treści obowiązującej
/// w dniu spawania) i uprawnienia KAŻDEGO stempla spoiny (spawacz, grań,
/// lico) w dniu spawania.
///
/// Ta sama funkcja co znaczki na liście dziennika ([assessWeldCompliance]) —
/// karta spoiny i lista nie mogą się różnić werdyktem.
library;

import 'package:flutter/foundation.dart' show debugPrint;

import '../database/db.dart';
import '../database/wps_dao.dart';
import '../domain/weld_journal/weld_compliance.dart';
import '../domain/weld_journal/weld_entry.dart';
import 'welder_identity.dart';
import 'welder_qualification_service.dart';

/// Sygnatura kontroli — edytor spoiny dostaje ją z zewnątrz (testy).
typedef WeldComplianceCheck = Future<WeldCompliance> Function(
  WeldEntry entry, {
  String? wpsId,
});

/// [wpsId] — WPS wybrana z listy w edytorze; bez niej `entry.wpsId`, a na
/// końcu wpis `wps_ref` (także stary wolny tekst, także z rewizją „rev. B”)
/// dopasowany do biblioteki przez [resolveWpsRefDetailed].
Future<WeldCompliance> checkWeldCompliance(
  WeldEntry entry, {
  String? wpsId,
  DateTime? now,
}) async {
  final wpsDao = WpsDao();
  final library = await wpsDao.listAll();
  final versions = await wpsDao.versionsByWps();
  final certificates =
      await WelderQualificationService.instance.listCertificates();
  final owner = (await WelderIdentityService.instance.get())?.stamp;
  var rows = const <Map<String, Object?>>[];
  try {
    rows = await (await AppDatabase.get()).query('weld_journal');
  } catch (e) {
    debugPrint('[weld_journal] journal read failed: $e');
  }
  return assessWeldCompliance(
    entry: entry,
    wpsLibrary: library,
    certificates: certificates,
    journalRows: rows,
    defaultStamp: owner,
    wpsId: wpsId,
    today: now ?? DateTime.now(),
    wpsVersions: versions,
  );
}
