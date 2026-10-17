/// Rejestr uprawnień spawacza — spina bazę, tożsamość, dziennik i
/// przypomnienia. Jedno miejsce, z którego czytają baner w menu SPAWACZ,
/// ekran rejestru i (przez [checkWeld]) dziennik spoin.
///
/// Migracja danych: do v21 uprawnienie było JEDNYM numerem i JEDNĄ datą
/// w tożsamości spawacza (SharedPreferences `welder_identity_v1`, pola
/// `wpqrNo` / `wpqrExpiry` / `certBody`). [ensureLegacyMigrated] przenosi je
/// jednorazowo do pierwszego wpisu rejestru. Stempel ZOSTAJE w tożsamości —
/// dziennik spoin czyta `WelderIdentityService.instance.current?.stamp` jako
/// domyślnego spawacza i tego nie zmieniamy. Stare pola w preferencjach też
/// zostają (nic nie kasujemy) — tylko nie są już edytowane ani pokazywane.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/db.dart';
import '../database/welder_certificate_dao.dart';
import '../database/wps_dao.dart';
import '../domain/qualification/certificate_status.dart';
import '../domain/qualification/journal_welds.dart';
import '../domain/qualification/reminder_plan.dart';
import '../domain/qualification/welder_certificate.dart';
import '../domain/weld_journal/weld_compliance.dart' show certificatesForStamp;
import '../domain/wps/weld_range_check.dart';
import '../domain/wps/wps_record.dart';
import '../i18n/app_language.dart';
import 'heat_photo_storage.dart';
import 'qualification_reminders.dart';
import 'welder_identity.dart';

/// Klucz flagi „stare pola WPQR już przeniesione do rejestru".
const String kLegacyCertMigratedPrefsKey = 'welder_cert_legacy_migrated_v1';

/// Klucz tożsamości spawacza — ten sam co w `welder_identity.dart`.
const String _kIdentityPrefsKey = 'welder_identity_v1';

/// Etykiety starego enuma CertificationBody (tożsamość) → tekst egzaminatora.
const Map<String, String> _kLegacyBodies = <String, String>{
  'tuv': 'TÜV',
  'udt': 'UDT',
  'lrs': "Lloyd's Register",
  'dnv': 'DNV',
  'bv': 'Bureau Veritas',
  'asme': 'ASME',
};

/// Przenosi stare pola uprawnienia z tożsamości do rejestru — raz.
///
/// Czysta wobec platformy (dostaje bazę i preferencje), żeby test mógł ją
/// zawołać na prawdziwym SQLite i atrapie preferencji. Zasady:
///  • flaga [kLegacyCertMigratedPrefsKey] ustawiona → nic nie robi (usunięty
///    przez spawacza wpis nie wraca przy następnym starcie);
///  • rejestr niepusty (np. odtworzony z kopii) → nie dopisuje duplikatu;
///  • tożsamość bez numeru i bez daty → nie ma czego przenosić;
///  • stary „nr WPQR / WPS" mógł być numerem WPS (pole to mieszało) — trafia
///    do numeru certyfikatu, a uwaga mówi skąd pochodzi, żeby spawacz mógł
///    to poprawić.
/// Zwraca przeniesiony certyfikat albo `null`.
Future<WelderCertificate?> migrateLegacyQualification(
  DatabaseExecutor db,
  SharedPreferences prefs, {
  DateTime? now,
  String Function()? newId,
}) async {
  if (prefs.getBool(kLegacyCertMigratedPrefsKey) ?? false) return null;
  WelderCertificate? migrated;
  final dao = WelderCertificateDao();
  final raw = prefs.getString(_kIdentityPrefsKey);
  Map<String, Object?>? identity;
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) identity = Map<String, Object?>.from(decoded);
    } catch (_) {
      identity = null;
    }
  }
  if (identity != null) {
    final no = (identity['wpqrNo'] as String?)?.trim() ?? '';
    final expiryRaw = identity['wpqrExpiry'] as String?;
    final expiry = expiryRaw == null ? null : DateTime.tryParse(expiryRaw);
    if ((no.isNotEmpty || expiry != null) && await dao.count(db: db) == 0) {
      final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
      final body = _kLegacyBodies[identity['certBody']];
      final stamp = (identity['stamp'] as String?)?.trim();
      migrated = WelderCertificate(
        id: newId?.call() ?? const Uuid().v4(),
        welderStamp: (stamp == null || stamp.isEmpty) ? null : stamp,
        // Stary formularz nie pytał o normę. W PL/UE to prawie zawsze
        // EN ISO 9606-1; spawacz poprawia w edycji, jeśli to WPQ ASME.
        standard: QualificationStandard.iso9606_1,
        certNo: no.isEmpty ? null : no,
        examiner: body,
        expiryDate: expiry == null
            ? null
            : DateTime(expiry.year, expiry.month, expiry.day),
        notes: 'Przeniesione z tożsamości spawacza (dawne pole „Nr WPQR / '
            'WPS"). Uzupełnij normę, zakres i datę egzaminu.',
        createdAt: ts,
        updatedAt: ts,
      );
      await dao.upsert(migrated, db: db);
    }
  }
  await prefs.setBool(kLegacyCertMigratedPrefsKey, true);
  return migrated;
}

/// Wynik [WelderQualificationService.checkWeld] — dla dziennika spoin.
class WeldCheckReport {
  /// WPS użyta do kontroli (albo `null`, gdy nie wybrano / nie znaleziono).
  final WpsRecord? wps;

  /// Niezgodności z WPS (pusta, gdy brak WPS albo spoina w zakresie).
  final List<RangeIssue> wpsIssues;

  /// Uprawnienia spawacza w dniu spawania.
  final WelderCoverage welder;

  const WeldCheckReport({
    required this.wps,
    required this.wpsIssues,
    required this.welder,
  });

  /// Coś wymaga ostrzeżenia przy zapisie spoiny.
  bool get hasWarnings =>
      wpsIssues.isNotEmpty || (!welder.noCertificates && !welder.covered);
}

class WelderQualificationService {
  WelderQualificationService._();
  static final WelderQualificationService instance =
      WelderQualificationService._();

  final WelderCertificateDao _dao = WelderCertificateDao();

  /// Ostatnio policzony stan rejestru — słucha go baner w menu SPAWACZ
  /// i w profilu. `null` do pierwszego [refresh].
  final ValueNotifier<QualificationOverview?> overview =
      ValueNotifier<QualificationOverview?>(null);

  /// Jednorazowe przeniesienie starych pól WPQR (patrz
  /// [migrateLegacyQualification]).
  Future<void> ensureLegacyMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kLegacyCertMigratedPrefsKey) ?? false) return;
    final db = await AppDatabase.get();
    await migrateLegacyQualification(db, prefs);
  }

  Future<List<WelderCertificate>> listCertificates() async {
    await ensureLegacyMigrated();
    return _dao.listAll();
  }

  /// Spoiny spawacza [stamp] z dziennika — TYLKO ODCZYT tabeli
  /// `weld_journal` (należy do modułu dziennika). Brak tabeli albo błąd
  /// odczytu = brak spoin, nigdy wyjątek.
  Future<List<JournalWeld>> readJournalWelds({
    required String? stamp,
    required DateTime today,
  }) async {
    if (stamp == null || stamp.trim().isEmpty) return const <JournalWeld>[];
    try {
      final db = await AppDatabase.get();
      final rows = await db.query('weld_journal');
      return journalWeldsFromRows(rows, stamp: stamp, today: today);
    } catch (e) {
      debugPrint('[qualification] journal read failed: $e');
      return const <JournalWeld>[];
    }
  }

  /// Ocena całego rejestru na dziś; aktualizuje [overview] i plan przypomnień.
  ///
  /// Celowo BEZ współdzielenia trwającego wywołania: zapamiętana przyszłość
  /// potrafi przeżyć właściciela (ekran zamknięty w trakcie, strefa
  /// zakończonego testu) i wtedy każdy kolejny zapis czekałby na nią bez
  /// końca. Dwa równoległe przeliczenia są nieszkodliwe — czytają to samo,
  /// a identyfikatory przypomnień są deterministyczne, więc drugie
  /// planowanie nadpisuje pierwsze zamiast je dublować.
  Future<QualificationOverview> refresh({DateTime? now}) =>
      _refresh(now ?? DateTime.now());

  /// Numer ostatnio rozpoczętego przeliczenia — wynik starszego, które
  /// skończyło się później (np. start ekranu kontra zapis), nie nadpisuje
  /// nowszego stanu ani planu przypomnień.
  int _generation = 0;

  Future<QualificationOverview> _refresh(DateTime now) async {
    final generation = ++_generation;
    try {
      final certificates = await listCertificates();
      final identity = await WelderIdentityService.instance.get();
      final journal =
          await readJournalWelds(stamp: identity?.stamp, today: now);
      final result = QualificationOverview([
        for (final c in certificates)
          evaluateCertificate(c,
              asOf: now, journalWelds: journalWeldsFor(c, journal)),
      ]);
      if (generation != _generation) return result;
      overview.value = result;
      await QualificationReminders.instance.reschedule(
        planQualificationReminders(result.evaluations,
            now: now, english: AppLanguageController.isEnglish),
      );
      return result;
    } catch (e) {
      // Brak bazy (np. test widżetu bez SQLite) albo uszkodzony wiersz: baner
      // po prostu nic nie pokaże, reszta aplikacji działa.
      debugPrint('[qualification] refresh failed: $e');
      return overview.value ?? QualificationOverview.empty;
    }
  }

  Future<void> save(WelderCertificate certificate) async {
    await _dao.upsert(certificate);
    await refresh();
  }

  /// Dopisuje potwierdzenie 6-miesięczne (ISO 9606-1 §9.2) / wpis ciągłości
  /// WPQ do historii certyfikatu. Nic nie nadpisuje — dawne potwierdzenia
  /// zostają ogniwami łańcucha.
  Future<void> addConfirmation(
    WelderCertificate certificate, {
    required DateTime date,
    String confirmedBy = '',
    String notes = '',
    DateTime? now,
  }) async {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await _dao.addConfirmation(CertificateConfirmation(
      id: const Uuid().v4(),
      certificateId: certificate.id,
      date: DateTime(date.year, date.month, date.day),
      confirmedBy: confirmedBy.trim(),
      notes: notes.trim(),
      createdAt: ts,
    ));
    await refresh();
  }

  /// Usuwa błędny wpis z historii potwierdzeń.
  Future<void> deleteConfirmation(CertificateConfirmation confirmation) async {
    await _dao.deleteConfirmation(confirmation);
    await refresh();
  }

  /// Ile certyfikatów ma stempel [stamp] (bez rozróżniania wielkości liter).
  Future<int> countCertificatesWithStamp(String stamp) async {
    final key = stamp.trim().toUpperCase();
    if (key.isEmpty) return 0;
    final all = await listCertificates();
    return all.where((c) => c.stampKey == key).length;
  }

  /// Ile spoin (nieusuniętych) dziennika podpisano stemplem [stamp] —
  /// jako spawacz, grań albo lico. Brak tabeli / błąd = 0.
  Future<int> countJournalWeldsWithStamp(String stamp) async {
    final key = stamp.trim().toUpperCase();
    if (key.isEmpty) return 0;
    try {
      final db = await AppDatabase.get();
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM weld_journal WHERE deleted_at IS NULL '
          'AND (UPPER(TRIM(welder)) = ? OR UPPER(TRIM(root_welder)) = ? '
          'OR UPPER(TRIM(cap_welder)) = ?)',
          <Object?>[key, key, key]);
      return (rows.single['n'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[qualification] journal count failed: $e');
      return 0;
    }
  }

  /// Zmiana stempla w tożsamości: przepisuje stempel certyfikatów ze
  /// [from] na [to] (tylko za zgodą spawacza — spoin nie ruszamy, to dowód).
  Future<int> reassignStamp(String from, String to) async {
    final n = await _dao.reassignStamp(from, to);
    await refresh();
    return n;
  }

  /// Usuwa certyfikat i jego zdjęcie (kopię w `heat_photos`).
  Future<void> delete(WelderCertificate certificate) async {
    await _dao.delete(certificate.id);
    await deleteOwnedFile(certificate.photoPath);
    await refresh();
  }

  /// „Usuń moje dane": cały rejestr, zdjęcia certyfikatów i zaplanowane
  /// przypomnienia. Nigdy nie rzuca (baza może być niedostępna).
  Future<void> clearAll() async {
    try {
      final removed = await _dao.deleteAll();
      for (final c in removed) {
        await deleteOwnedFile(c.photoPath);
      }
    } catch (e) {
      debugPrint('[qualification] clear failed: $e');
    }
    try {
      await QualificationReminders.instance.disable();
    } catch (e) {
      debugPrint('[qualification] reminders disable failed: $e');
    }
    _generation++; // przeliczenie w toku nie przywróci skasowanych wpisów
    overview.value = QualificationOverview.empty;
  }

  /// Kasuje plik tylko wtedy, gdy leży w `heat_photos` — nigdy oryginału
  /// z galerii, do którego ktoś kiedyś zapisał ścieżkę.
  Future<void> deleteOwnedFile(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final dir = await heatPhotosDirectory();
      if (!p.isWithin(p.normalize(dir.path), p.normalize(path))) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[qualification] photo delete failed: $e');
    }
  }

  /// Kontrola spoiny dla dziennika spoin (API dla modułu dziennika).
  ///
  /// [wpsId] albo [wpsNo] (stary wolny tekst `weld_journal.wps_ref`) wskazują
  /// WPS z biblioteki; bez nich sprawdzane są tylko uprawnienia. [welderStamp]
  /// domyślnie stempel z tożsamości. Uprawnienia oceniane na [weldDate] —
  /// z ciągłością ASME liczoną ze spoin tego spawacza do tego dnia.
  ///
  /// Parametry spoiny z wpisu dziennika daje `weldParametersOf`
  /// (lib/domain/weld_journal/weld_compliance.dart) — razem z danymi do
  /// ograniczeń z próby ISO 9606-1 (wyrób z OD, grupa FM z oznaczenia
  /// spoiwa, odgałęzienie BR); dziennik na liście liczy to samo przez
  /// `assessWeldCompliance`.
  ///
  /// Przykład (zapis spoiny w dzienniku):
  /// ```dart
  /// final report = await WelderQualificationService.instance.checkWeld(
  ///   weld: weldParametersOf(entry),
  ///   weldDate: parseFlexibleDate(entry.date) ?? DateTime.now(),
  ///   wpsNo: entry.wpsRef,
  ///   welderStamp: entry.welder,
  /// );
  /// if (report.hasWarnings) { /* dialog z report.wpsIssues / report.welder */ }
  /// ```
  Future<WeldCheckReport> checkWeld({
    required WeldParameters weld,
    required DateTime weldDate,
    String? wpsId,
    String? wpsNo,
    String? welderStamp,
  }) async {
    final wpsDao = WpsDao();
    WpsRecord? wps;
    if (wpsId != null && wpsId.isNotEmpty) {
      wps = await wpsDao.getById(wpsId);
    }
    if (wps == null && wpsNo != null && wpsNo.trim().isNotEmpty) {
      wps = await wpsDao.findByNumber(wpsNo);
    }
    final owner = (await WelderIdentityService.instance.get())?.stamp;
    final stamp = (welderStamp != null && welderStamp.trim().isNotEmpty)
        ? welderStamp
        : owner;
    // Certyfikat bez stempla należy do właściciela telefonu — nie do
    // każdego spawacza brygady (patrz certificatesForStamp).
    final certificates = certificatesForStamp(
        await listCertificates(), stamp,
        ownerStamp: owner);
    final journal = await readJournalWelds(stamp: stamp, today: weldDate);
    return WeldCheckReport(
      wps: wps,
      wpsIssues: wps == null ? const <RangeIssue>[] : checkWeldAgainstWps(weld, wps),
      welder: checkWelderCoverage(
        weld: weld,
        weldDate: weldDate,
        certificates: certificates,
        journal: journal,
      ),
    );
  }
}
