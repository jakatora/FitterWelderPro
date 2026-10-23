/// Wspólny wzorzec tabeli z właścicielem danych (`owner_scope`): właściciel
/// uchwycony na początku operacji i sprawdzany po każdym oczekiwaniu, każdy
/// odczyt/zapis zawężony do niego, cudze id zajęte (nie wolne). Tak samo jak
/// kupony i WPS (v33), dla prostych rejestrów v34.
library;

import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor;

import '../services/account_service.dart' show AccountException;
import 'db.dart';
import 'local_record_owner.dart';

class OwnedTable {
  OwnedTable(this.table,
      {required this.foreignMessage,
      Future<LocalRecordOwner> Function()? captureOwner})
      : _captureOwner = captureOwner ?? LocalRecordOwner.capture;

  final String table;

  /// Komunikat, gdy id należy do innego konta („Ten wpis należy…”).
  final String foreignMessage;
  final Future<LocalRecordOwner> Function() _captureOwner;

  Future<(LocalRecordOwner, Database)> ownerAndDb() async {
    final owner = await _captureOwner();
    owner.requireCurrent();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    return (owner, db);
  }

  /// `owner_scope = ?` albo `owner_scope = ? AND (extra)`.
  String where([String? extra]) =>
      extra == null ? 'owner_scope = ?' : 'owner_scope = ? AND ($extra)';

  Future<void> refuseForeign(
      DatabaseExecutor db, String id, LocalRecordOwner owner) async {
    final rows = await db.query(table,
        columns: ['owner_scope'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.single['owner_scope'] != owner.key) {
      throw AccountException(foreignMessage);
    }
  }

  Map<String, Object?> owned(Map<String, Object?> row, LocalRecordOwner owner) =>
      {...row, 'owner_scope': owner.key};
}

/// Projekty listy cięć (v34 `projects.owner_scope`) i ich dzieci — segmenty,
/// znaczniki cięcia, wytopy, zdjęcia — które NIE mają własnego właściciela:
/// należą do właściciela projektu (jak historia kuponu do kuponu).
class OwnedProjects {
  OwnedProjects({Future<LocalRecordOwner> Function()? captureOwner})
      : table = OwnedTable('projects',
            captureOwner: captureOwner,
            foreignMessage: 'Ten projekt należy do innego konta. / '
                'This project belongs to another account.');

  final OwnedTable table;

  /// Warunek dla tabel-dzieci: wiersz należy do projektu właściciela.
  static const String childOfOwnedProject =
      'project_id IN (SELECT id FROM projects WHERE owner_scope = ?)';

  Future<(LocalRecordOwner, Database)> ownerAndDb() => table.ownerAndDb();

  /// Dziecko można dopisać do projektu właściciela; projekt innego konta
  /// jest zajęty. Brak projektu (np. usunięty w międzyczasie) nie jest
  /// cudzy — zachowanie jak przed v34.
  Future<void> requireProject(
          DatabaseExecutor db, String projectId, LocalRecordOwner owner) =>
      table.refuseForeign(db, projectId, owner);
}
