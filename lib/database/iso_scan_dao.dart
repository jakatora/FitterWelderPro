/// Persistence for ISO scanner readings (`iso_scans`, schema v24).
///
/// A scan is a paid Vision call against a daily limit, and its result used
/// to live only in the scanner screen's memory: killing the app, or
/// "Discard" on the way back, threw the reading away and the next look at it
/// cost another scan. Every successful reading is now a row here — the
/// server's envelope exactly as it came (`{result, tookMs, model}`) and the
/// path of a copy of the photo in `<documents>/heat_photos`, the folder the
/// backup archive carries (`data_backup.dart`, `kPhotoPathColumns`).
///
/// Only the reading is stored, not the fitter's corrections on the review
/// screen: those end up in the project he saves from it.
library;

import 'dart:convert';
import 'dart:io';

import 'local_record_owner.dart';
import 'owned_table.dart';

/// One stored reading.
class IsoScanRecord {
  final String id;

  /// Pipe run / line name at the time of the scan, when there was one.
  final String? name;

  /// Copy of the photographed drawing, or null when it could not be kept.
  final String? imagePath;

  /// The server's response exactly as received.
  final String envelopeJson;

  /// `millisecondsSinceEpoch` of the scan.
  final int createdAt;

  const IsoScanRecord({
    required this.id,
    required this.envelopeJson,
    required this.createdAt,
    this.name,
    this.imagePath,
  });

  /// The envelope decoded, or null when the stored text is not a JSON object
  /// (never thrown at the screen — a broken row is simply not reopenable).
  Map<String, dynamic>? get envelope {
    try {
      final v = jsonDecode(envelopeJson);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'image_path': imagePath,
        'envelope_json': envelopeJson,
        'created_at': createdAt,
      };

  static IsoScanRecord fromRow(Map<String, Object?> r) => IsoScanRecord(
        id: r['id'] as String,
        name: r['name'] as String?,
        imagePath: r['image_path'] as String?,
        envelopeJson: (r['envelope_json'] as String?) ?? '',
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// v34: odczyty należą do konta (`owner_scope`); limit [keep] liczy się
/// osobno dla każdego konta.
class IsoScanDao {
  IsoScanDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _owned = OwnedTable(table,
            captureOwner: captureOwner,
            foreignMessage: 'Ten odczyt należy do innego konta. / '
                'This reading belongs to another account.');
  final OwnedTable _owned;

  static const String table = 'iso_scans';

  /// How many readings are kept; older ones are dropped on insert. The
  /// photos stay in `heat_photos` only as long as their row does.
  static const int keep = 30;

  Future<void> insert(IsoScanRecord r) async {
    final (owner, db) = await _owned.ownerAndDb();
    final stale = await db.transaction((txn) async {
      owner.requireCurrent();
      await _owned.refuseForeign(txn, r.id, owner);
      await txn.insert(table, _owned.owned(r.toRow(), owner));
      final stale = await txn.query(
        table,
        columns: ['id', 'image_path'],
        where: _owned.where(),
        whereArgs: [owner.key],
        orderBy: 'created_at DESC, id DESC',
        offset: keep,
        limit: -1,
      );
      for (final row in stale) {
        await txn.delete(table, where: 'id = ?', whereArgs: [row['id']]);
      }
      owner.requireCurrent();
      return stale;
    });
    // Files only after the commit — a rollback cannot un-delete a photo.
    for (final row in stale) {
      final path = row['image_path'];
      if (path is String && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {
          // A photo that cannot be removed only costs disk space.
        }
      }
    }
  }

  /// The most recent reading, or null when there is none.
  Future<IsoScanRecord?> latest() async {
    final rows = await listRecent(limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Newest first.
  Future<List<IsoScanRecord>> listRecent({int limit = keep}) async {
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.query(table,
        where: _owned.where(),
        whereArgs: [owner.key],
        orderBy: 'created_at DESC, id DESC',
        limit: limit);
    owner.requireCurrent();
    return rows.map(IsoScanRecord.fromRow).toList();
  }

  Future<void> deleteById(String id) async {
    final (owner, db) = await _owned.ownerAndDb();
    await db.delete(table,
        where: _owned.where('id = ?'), whereArgs: [owner.key, id]);
    owner.requireCurrent();
  }
}
