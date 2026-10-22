/// Biblioteka WPS — tabela `wps_library` (schemat v21) i wersje treści
/// `wps_versions` (v25).
///
/// W `cutlist.db`, więc kopia zapasowa ją obejmuje; załącznik (PDF / zdjęcie
/// WPS, kolumna `attachment_path`) leży w `<documents>/heat_photos` i jest
/// przepinany przy odtwarzaniu (`kPhotoPathColumns` w data_backup.dart).
///
/// Wersjonowanie (v25): każdy zapis zmieniający TREŚĆ technologiczną WPS
/// dopisuje nową wersję obowiązującą od chwili zapisu. Pierwsza wersja
/// obowiązuje „od zawsze” (valid_from = 0) — WPS wpisana do aplikacji
/// później niż powstała na papierze nadal obejmuje wcześniejsze spoiny.
/// Dziennik ocenia spoinę wg wersji z dnia spawania (`wpsAsOf`).
///
/// Dla dziennika spoin (inny moduł): [listAll] do listy wyboru WPS,
/// [findByNumber] do dopasowania starego wolnego tekstu
/// `weld_journal.wps_ref` do rekordu, [versionsByWps] do oceny wg daty.
///
/// v33: biblioteka należy do właściciela danych (konto albo gość offline) —
/// `wps_library.owner_scope`; dawne wiersze zostają gościowi, wersje idą za
/// swoją WPS. Cudzego identyfikatora nie da się odczytać, nadpisać ani
/// usunąć.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/wps/wps_record.dart';
import '../services/account_service.dart';
import 'db.dart';
import 'local_record_owner.dart';

class WpsDao {
  static const String table = 'wps_library';
  static const String versionsTable = 'wps_versions';

  static const Uuid _uuid = Uuid();

  final int Function() _clock;
  final String Function() _newId;
  final Future<LocalRecordOwner> Function() _captureOwner;

  WpsDao(
      {int Function()? clock,
      String Function()? newId,
      Future<LocalRecordOwner> Function()? captureOwner})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _newId = newId ?? (() => _uuid.v4()),
        _captureOwner = captureOwner ?? LocalRecordOwner.capture;

  Future<(LocalRecordOwner, Database)> _ownerAndDb() async {
    final owner = await _captureOwner();
    owner.requireCurrent();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    return (owner, db);
  }

  /// Wszystkie WPS bieżącego właściciela po numerze i rewizji.
  Future<List<WpsRecord>> listAll() async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query(table,
        where: 'owner_scope = ?',
        whereArgs: <Object?>[owner.key],
        orderBy: 'wps_no COLLATE NOCASE ASC, revision COLLATE NOCASE ASC');
    owner.requireCurrent();
    return rows.map(WpsRecord.fromRow).toList();
  }

  Future<WpsRecord?> getById(String id) async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query(table,
        where: 'id = ? AND owner_scope = ?',
        whereArgs: <Object?>[id, owner.key],
        limit: 1);
    owner.requireCurrent();
    return rows.isEmpty ? null : WpsRecord.fromRow(rows.single);
  }

  /// WPS o numerze [wpsNo] (bez rozróżniania wielkości liter i spacji na
  /// brzegach); przy kilku rewizjach — najnowsza zapisana. [revision] zawęża.
  Future<WpsRecord?> findByNumber(String wpsNo, {String? revision}) async {
    final no = wpsNo.trim();
    if (no.isEmpty) return null;
    final (owner, db) = await _ownerAndDb();
    final rev = revision?.trim();
    final rows = await db.query(
      table,
      where: rev == null || rev.isEmpty
          ? 'owner_scope = ? AND TRIM(wps_no) = ? COLLATE NOCASE'
          : 'owner_scope = ? AND TRIM(wps_no) = ? COLLATE NOCASE AND '
              'TRIM(COALESCE(revision, \'\')) = ? COLLATE NOCASE',
      whereArgs: <Object?>[
        owner.key,
        no,
        if (rev != null && rev.isNotEmpty) rev
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    owner.requireCurrent();
    return rows.isEmpty ? null : WpsRecord.fromRow(rows.single);
  }

  /// Inne WPS o tym samym numerze i rewizji (duplikat) niż [exceptId].
  Future<List<WpsRecord>> duplicatesOf(String wpsNo, String revision,
      {String? exceptId}) async {
    final all = await listAll();
    String k(String s) => s.trim().toUpperCase();
    return [
      for (final w in all)
        if (w.id != exceptId &&
            k(w.wpsNo) == k(wpsNo) &&
            k(w.revision) == k(revision))
          w,
    ];
  }

  /// Zapis WPS z wersjonowaniem treści. Zwraca numer wersji, która po
  /// zapisie obowiązuje (nowej albo — bez zmiany treści — ostatniej).
  Future<int> upsert(WpsRecord wps, {String by = ''}) async {
    final (owner, db) = await _ownerAndDb();
    return db.transaction((txn) async {
      owner.requireCurrent();
      final storedRows = await txn.query(table,
          where: 'id = ?', whereArgs: <Object?>[wps.id], limit: 1);
      if (storedRows.isNotEmpty &&
          storedRows.single['owner_scope'] != owner.key) {
        throw AccountException('Ta WPS należy do innego konta. / '
            'This WPS belongs to another account.');
      }
      final stored =
          storedRows.isEmpty ? null : WpsRecord.fromRow(storedRows.single);
      final versions = await _versionsOf(txn, wps.id);
      await txn.insert(table, {...wps.toRow(), 'owner_scope': owner.key},
          conflictAlgorithm: ConflictAlgorithm.replace);
      var last = versions.isEmpty ? 0 : versions.last.versionNo;
      if (versions.isEmpty && stored != null && !stored.sameContentAs(wps)) {
        // Wiersz bez historii (np. z kopii sprzed v25): jego dotychczasowa
        // treść to wersja 1 „od zawsze”.
        last = 1;
        await txn.insert(
            versionsTable, _version(stored, 1, 0, by).toRow());
      }
      final lastContent = versions.isNotEmpty
          ? versions.last.snapshot
          : (last == 1 ? stored : null);
      if (lastContent == null || !lastContent.sameContentAs(wps)) {
        final no = last + 1;
        await txn.insert(versionsTable,
            _version(wps, no, no == 1 ? 0 : _clock(), by).toRow());
        return no;
      }
      return last;
    });
  }

  WpsVersion _version(WpsRecord w, int no, int validFrom, String by) =>
      WpsVersion(
        id: _newId(),
        wpsId: w.id,
        versionNo: no,
        validFrom: validFrom,
        snapshot: w,
        byStamp: by.trim(),
        createdAt: _clock(),
      );

  /// Wersje WPS [wpsId] bieżącego właściciela, od najstarszej.
  Future<List<WpsVersion>> versionsOf(String wpsId) async {
    final (owner, db) = await _ownerAndDb();
    final own = await db.query(table,
        columns: ['id'],
        where: 'id = ? AND owner_scope = ?',
        whereArgs: <Object?>[wpsId, owner.key],
        limit: 1);
    if (own.isEmpty) return const <WpsVersion>[];
    final versions = await _versionsOf(db, wpsId);
    owner.requireCurrent();
    return versions;
  }

  Future<List<WpsVersion>> _versionsOf(
      DatabaseExecutor db, String wpsId) async {
    final rows = await db.query(versionsTable,
        where: 'wps_id = ?',
        whereArgs: <Object?>[wpsId],
        orderBy: 'version_no ASC');
    return [
      for (final r in rows)
        if (WpsVersion.fromRow(r) case final v?) v,
    ];
  }

  /// Wszystkie wersje, pogrupowane po WPS — jedno czytanie na całą listę
  /// dziennika.
  Future<Map<String, List<WpsVersion>>> versionsByWps() async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.rawQuery(
        'SELECT v.* FROM $versionsTable v JOIN $table w ON w.id = v.wps_id '
        'WHERE w.owner_scope = ? ORDER BY v.wps_id, v.version_no',
        <Object?>[owner.key]);
    owner.requireCurrent();
    final out = <String, List<WpsVersion>>{};
    for (final r in rows) {
      final v = WpsVersion.fromRow(r);
      if (v == null) continue;
      (out[v.wpsId] ??= <WpsVersion>[]).add(v);
    }
    return out;
  }

  /// Usuwa WPS bieżącego właściciela (cudzy identyfikator: nic się nie
  /// dzieje — wiersz innego konta zostaje nietknięty).
  Future<void> delete(String id) async {
    final (owner, db) = await _ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      final removed = await txn.delete(table,
          where: 'id = ? AND owner_scope = ?',
          whereArgs: <Object?>[id, owner.key]);
      if (removed == 0) return;
      await txn.delete(versionsTable,
          where: 'wps_id = ?', whereArgs: <Object?>[id]);
      owner.requireCurrent();
    });
  }
}
