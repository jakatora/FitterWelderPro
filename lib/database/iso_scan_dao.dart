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

import 'db.dart';

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

class IsoScanDao {
  static const String table = 'iso_scans';

  /// How many readings are kept; older ones are dropped on insert. The
  /// photos stay in `heat_photos` only as long as their row does.
  static const int keep = 30;

  Future<void> insert(IsoScanRecord r) async {
    final db = await AppDatabase.get();
    await db.insert(table, r.toRow());
    final stale = await db.query(
      table,
      columns: ['id', 'image_path'],
      orderBy: 'created_at DESC, id DESC',
      offset: keep,
      limit: -1,
    );
    for (final row in stale) {
      await db.delete(table, where: 'id = ?', whereArgs: [row['id']]);
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
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        orderBy: 'created_at DESC, id DESC', limit: 1);
    return rows.isEmpty ? null : IsoScanRecord.fromRow(rows.first);
  }

  /// Newest first.
  Future<List<IsoScanRecord>> listRecent({int limit = keep}) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        orderBy: 'created_at DESC, id DESC', limit: limit);
    return rows.map(IsoScanRecord.fromRow).toList();
  }

  Future<void> deleteById(String id) async {
    final db = await AppDatabase.get();
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}
