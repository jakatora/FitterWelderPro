/// One-file backup and restore for everything this phone keeps locally.
///
/// Until now a fitter's work could not leave the device. The cut-list
/// database and the heat/MTR certificate photos live in the app sandbox, so
/// handing the documentation to a foreman at the end of a contract, moving
/// from Android to iOS, or recovering after a lost phone were all impossible.
/// This file closes that hole with a plain `.zip` the user owns.
///
/// ## Nothing is uploaded
/// The archive is written to the app's temporary directory and handed to the
/// OS share sheet ([Share.shareXFiles]). The archive is never uploaded to the
/// backend. Resolving an existing session may refresh account identity; where
/// the archive goes is the user's decision in the system share sheet.
///
/// ## Why a hand-written ZIP writer
/// The task allowed `package:archive` "if it is in pubspec.lock". It IS in
/// the lock file — but only as a **transitive** dependency (nothing in
/// `pubspec.yaml` declares it). Importing a transitive package directly
/// breaks the `depend_on_referenced_packages` lint that `flutter_lints`
/// enables, and it silently breaks the build the day the package that
/// actually pulls `archive` in drops it. Declaring it properly would mean
/// editing `pubspec.yaml`, which is outside this change's scope. So this file
/// carries its own ~150-line ZIP writer/reader, STORE method (no
/// compression), no ZIP64. Consequences, stated honestly:
///   * the archive is not smaller than the sum of its parts — but its bulk is
///     JPEGs, which do not compress anyway;
///   * every desktop OS opens it with a double-click, so the foreman does not
///     need this app to read the photos;
///   * the reader only understands STORE, and says so in plain language if it
///     meets a deflated archive from some other tool.
///
/// ## Layout of the archive
/// ```
/// manifest.json          — what this is, when it was made, what is inside
/// db/cutlist.db          — main database (projects, cut lists, weld journal,
///                          welder certificate register, WPS library)
/// db/cut_list_app.db     — welder-pipe module database
/// heat_photos/<uuid>.jpg — heat / MTR certificate photos, scans of welder
///                          certificates and WPS files (PDF / photo)
/// ```
///
/// ## All-or-nothing restore
/// Restore runs in two strictly separated phases:
///   1. **Read phase** — the archive is opened, the manifest validated, every
///      database extracted to a staging directory, opened read-only and read
///      into memory, and every photo extracted to staging. Nothing the app
///      currently owns is touched. A foreign file, a truncated download or a
///      corrupt entry fails here, and the user's live data never moved.
///   1b. **Validation** — BOTH live databases get a full dry-run refill
///      (schema self-heal, wipe, every insert, foreign-key check where the
///      database enforces keys) that is rolled back on purpose. A backup one
///      of the databases cannot take fails here, before anything is written.
///   2. **Commit phase** — each live database is first snapshotted
///      (`VACUUM INTO`) as a rollback point. Photos are copied into place (a
///      same-name file is saved first), then each database is refilled inside
///      a single `transaction`.
///
/// The app owns two SQLite files and SQLite has no two-phase commit across
/// them. So if the second database fails after the first was written (disk
/// full), the first is refilled from its snapshot and the photos are put
/// back: the phone ends up exactly as before the attempt, and the user is
/// told so. Only if that undo itself fails does the message say the data may
/// be mixed and ask to restore again.
///
/// ## Why absolute photo paths are rewritten
/// `heat_photos.image_path` and `component_heats.image_path` store absolute
/// paths. iOS changes the app container UUID on every reinstall and Android
/// paths do not exist on iOS at all, so a byte-identical database restored on
/// another phone would point at photos that are not there. Every restored row
/// whose file name is present in the archive is re-anchored to this device's
/// `heat_photos` directory ([relinkPhotoPath]).
///
/// Some rows point OUTSIDE `heat_photos` — component heats picked before the
/// picker started copying into the app store the gallery path FilePicker
/// returned. Backup pulls those files into the archive too, under a
/// collision-free name ([archiveNameForExternalPhoto]), and points the
/// database SNAPSHOT at that name; the live row is never touched. After a
/// restore they sit in `heat_photos` like every other photo.
///
/// ## Nothing is skipped silently
/// A backup table the device lacks is created first when it belongs to the
/// app's schema ([cutlist_db.AppDatabase.ensureTables]); one this version
/// does not know at all, or a column with data that has no place to go, is
/// listed in the [RestoreReport] ([RestoreReport.warningPl]) instead of
/// vanishing.
///
/// ## What is deliberately NOT in the backup
/// Everything stored in `SharedPreferences`: the user profile, the welder
/// identity (stamp), the accepted rules version, and — decisively — the
/// Premium entitlement. (Since v21 the welder's CERTIFICATES are rows in
/// `cutlist.db` and DO travel with the backup; only the stamp stays behind.) A backup file is user-editable and freely
/// shareable; restoring preferences would turn "send me your backup" into a
/// way to copy someone's paid status and to bypass the consent gate. The
/// restore dialog says this out loud instead of pretending otherwise.
///
/// ## Shape of this file
/// As in `weld_journal_export.dart`, the top half is PURE Dart — file naming,
/// the ZIP codec, manifest parsing, archive validation, row projection — with
/// no I/O, no plugins and no globals, and is covered by
/// `test/services/data_backup_test.dart`. The bottom half ([DataBackup],
/// [restoreTablesInto]) does the platform work and is driven end to end on
/// real SQLite files by `test/services/data_backup_restore_test.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart' as module_db;
import '../database/db.dart' as cutlist_db;
import '../database/local_record_owner.dart';
import 'heat_photo_storage.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF — naming, ZIP codec, manifest, validation, row projection.
// Keep free of I/O so the tests stay honest.
// ═══════════════════════════════════════════════════════════════════════════

/// Marker written into every manifest. A file without it is not ours.
const String kBackupApp = 'fitter-welder-pro';

/// Archive layout version. Bump only on a breaking layout change; the reader
/// refuses anything newer than it understands rather than guessing.
const String kBackupFormatKey = 'format';

/// Current archive layout version.
const int kBackupFormatVersion = 1;

/// Entry that identifies the archive. Its absence is the "foreign file" test.
const String kManifestEntry = 'manifest.json';

/// Folder inside the archive holding the SQLite files.
const String kDbEntryPrefix = 'db/';

/// Folder inside the archive holding the heat / MTR photos.
const String kPhotoEntryPrefix = 'heat_photos/';

/// First bytes of every SQLite 3 file, per the file-format spec.
const String kSqliteMagic = 'SQLite format 3\u0000';

/// Columns that hold an absolute photo path and therefore need re-anchoring
/// after a restore, keyed by table.
const Map<String, String> kPhotoPathColumns = {
  'heat_photos': 'image_path',
  'component_heats': 'image_path',
  // v21: skan certyfikatu uprawnień spawacza i plik WPS (PDF / zdjęcie).
  // Oba kopiowane do <documents>/heat_photos (persistPickedHeatPhoto), więc
  // lecą w archiwum razem z katalogiem i muszą być przepięte przy restore
  // tak samo jak zdjęcia wytopów.
  'welder_certificates': 'photo_path',
  'wps_library': 'attachment_path',
  // v24: zdjęcie izometryku przy zapisanym odczycie skanera — kopia
  // w <documents>/heat_photos, jak wyżej.
  'iso_scans': 'image_path',
};

/// A problem with the *file the user picked*, phrased for the user.
///
/// Carries both languages because a service has no `BuildContext` and must
/// not guess the UI language; the screen picks with `context.tr`.
class BackupFormatException implements Exception {
  final String messagePl;
  final String messageEn;

  const BackupFormatException(
      {required this.messagePl, required this.messageEn});

  @override
  String toString() => 'BackupFormatException: $messageEn';
}

/// `fitter-welder-pro-backup-2026-08-30-143502.zip`.
///
/// Sortable (year first), free of characters any file system or share target
/// dislikes, and second-resolution so two backups taken in the same minute do
/// not overwrite each other in the temp directory. Local time on purpose —
/// the name is read by a human who knows when they pressed the button.
String backupFileName(DateTime when) {
  String two(int v) => v.toString().padLeft(2, '0');
  final year = when.year.toString().padLeft(4, '0');
  return 'fitter-welder-pro-backup-$year-${two(when.month)}-${two(when.day)}'
      '-${two(when.hour)}${two(when.minute)}${two(when.second)}.zip';
}

/// `2026-08-30 14:35` — shown in the overwrite warning so the user can tell
/// whether they picked the backup they meant to.
String formatBackupTimestamp(DateTime when) {
  String two(int v) => v.toString().padLeft(2, '0');
  final local = when.isUtc ? when.toLocal() : when;
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// True when [bytes] starts with the SQLite 3 file signature.
///
/// Guards the restore against an archive that carries the right entry name
/// with the wrong content (a renamed text file, a half-finished download).
bool looksLikeSqliteDatabase(List<int> bytes) {
  final magic = utf8.encode(kSqliteMagic);
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

/// Last path segment, accepting BOTH separators.
///
/// A backup made on Android carries `/data/.../heat_photos/x.jpg` and one
/// made on a desktop build carries `C:\...\heat_photos\x.jpg`; the restoring
/// device may use the other one, so `p.basename` (host-separator only) is not
/// enough here.
String zipEntryBaseName(String path) {
  var cut = -1;
  for (var i = path.length - 1; i >= 0; i--) {
    final c = path.codeUnitAt(i);
    if (c == 0x2F /* / */ || c == 0x5C /* \ */) {
      cut = i;
      break;
    }
  }
  return path.substring(cut + 1);
}

/// Re-anchors one stored photo path onto this device.
///
/// Returns [stored] unchanged when it is null/blank, or when the archive did
/// not carry that file — losing the original string would destroy the only
/// record of which file the row ever pointed at, and an unreadable path is
/// still better evidence than an empty column.
String? relinkPhotoPath(
  String? stored, {
  required String heatPhotosDir,
  required Set<String> restoredPhotoNames,
}) {
  if (stored == null) return null;
  if (stored.trim().isEmpty) return stored;
  final base = zipEntryBaseName(stored);
  if (base.isEmpty || !restoredPhotoNames.contains(base)) return stored;
  return p.join(heatPhotosDir, base);
}

final RegExp _kPlainTableName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Tables the restore is allowed to wipe and refill.
///
/// Excludes SQLite's own bookkeeping (`sqlite_sequence`, `sqlite_stat1`) and
/// Android's injected `android_metadata`; overwriting those breaks the live
/// connection instead of restoring user data. The name-shape check also means
/// every table name this file interpolates into a `PRAGMA` is a plain
/// identifier, never attacker-controlled SQL.
bool isRestorableTable(String name) {
  if (!_kPlainTableName.hasMatch(name)) return false;
  if (name.toLowerCase().startsWith('sqlite_')) return false;
  if (name == 'android_metadata') return false;
  return true;
}

/// Name under which a photo that lives OUTSIDE `heat_photos` (a gallery or
/// Downloads file an older build referenced in place) is stored in the
/// archive, and therefore in `heat_photos` after a restore.
///
/// Why not the plain file name: restore re-anchors rows by file name
/// ([relinkPhotoPath]), and `IMG_0001.jpg` from the camera, `photo.jpg` from
/// Downloads and an app-owned `photo.jpg` would all collapse into one entry —
/// the row would silently end up showing somebody else's certificate. The
/// prefix is a CRC of the full source path (stable across two backups of the
/// same data) plus a counter when even that collides. [taken] holds every
/// name already used in this archive and is updated.
String archiveNameForExternalPhoto(String sourcePath, Set<String> taken) {
  var base = zipEntryBaseName(sourcePath).trim();
  if (base.isEmpty || base == '.' || base == '..') base = 'photo.jpg';
  final tag = crc32(utf8.encode(sourcePath)).toRadixString(16).padLeft(8, '0');
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot) : '';
  var candidate = 'ext-$tag-$base';
  var n = 2;
  while (taken.contains(candidate)) {
    candidate = 'ext-$tag-$stem-$n$ext';
    n++;
  }
  taken.add(candidate);
  return candidate;
}

/// Columns of one table's backup [rows] that the live table does not have
/// ([liveColumns]) AND that actually held a value in at least one row,
/// sorted.
///
/// [prepareRows] has to drop such columns (there is nowhere to put them),
/// but it must not do so silently: a column that was only ever NULL loses
/// nothing, one that carried data is reported to the user.
List<String> droppedColumnsWithData(
  List<Map<String, Object?>> rows,
  Set<String> liveColumns,
) {
  final lost = <String>{};
  for (final row in rows) {
    for (final entry in row.entries) {
      if (entry.value == null) continue;
      if (liveColumns.contains(entry.key)) continue;
      lost.add(entry.key);
    }
  }
  return lost.toList()..sort();
}

/// A table the backup carried that this device had no place for.
class SkippedTable {
  /// Database file the table came from, e.g. `cutlist.db`.
  final String database;
  final String table;
  final int rowCount;

  const SkippedTable({
    required this.database,
    required this.table,
    required this.rowCount,
  });

  @override
  String toString() => '$database/$table ($rowCount)';
}

/// Keeps only columns the *live* schema still has, and re-anchors photo paths.
///
/// A backup made by an older build carries fewer columns than the current
/// schema (fine — SQLite fills the defaults) and a backup made by a newer
/// build carries columns this one has never heard of (dropping them is the
/// only option that does not fail the whole restore). Rows that share no
/// column at all with the live table are skipped rather than inserted empty.
List<Map<String, Object?>> prepareRows({
  required String table,
  required List<Map<String, Object?>> rows,
  required Set<String> liveColumns,
  required String heatPhotosDir,
  required Set<String> restoredPhotoNames,
}) {
  final pathColumn = kPhotoPathColumns[table];
  final out = <Map<String, Object?>>[];
  for (final row in rows) {
    final projected = <String, Object?>{};
    for (final entry in row.entries) {
      if (!liveColumns.contains(entry.key)) continue;
      projected[entry.key] = entry.value;
    }
    if (projected.isEmpty) continue;
    if (pathColumn != null && projected.containsKey(pathColumn)) {
      projected[pathColumn] = relinkPhotoPath(
        projected[pathColumn] as String?,
        heatPhotosDir: heatPhotosDir,
        restoredPhotoNames: restoredPhotoNames,
      );
    }
    out.add(projected);
  }
  return out;
}

/// What the archive says about itself.
class BackupManifest {
  final String app;
  final int formatVersion;
  final DateTime createdAt;
  final List<String> databases;
  final int photoCount;

  const BackupManifest({
    required this.app,
    required this.formatVersion,
    required this.createdAt,
    required this.databases,
    required this.photoCount,
  });

  /// UTC on the wire so a backup made in one time zone and read in another
  /// still reports the moment it was taken; rendered back in local time by
  /// [formatBackupTimestamp].
  String encode() => jsonEncode({
        'app': app,
        kBackupFormatKey: formatVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'databases': databases,
        'photoCount': photoCount,
      });

  static BackupManifest decode(List<int> bytes) {
    Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw _notOurBackup;
    }
    if (raw is! Map) throw _notOurBackup;
    if (raw['app'] != kBackupApp) throw _notOurBackup;

    final format = raw[kBackupFormatKey];
    if (format is! int || format < 1) throw _notOurBackup;
    if (format > kBackupFormatVersion) {
      throw const BackupFormatException(
        messagePl: 'Ta kopia pochodzi z nowszej wersji aplikacji. '
            'Zaktualizuj Fitter Welder Pro i spróbuj ponownie.',
        messageEn: 'This backup was made by a newer version of the app. '
            'Update Fitter Welder Pro and try again.',
      );
    }

    DateTime created;
    try {
      created = DateTime.parse(raw['createdAt'] as String).toLocal();
    } catch (_) {
      throw _notOurBackup;
    }

    final dbs = raw['databases'];
    if (dbs is! List || dbs.any((value) => value is! String)) {
      throw _notOurBackup;
    }

    final photos = raw['photoCount'];

    return BackupManifest(
      app: kBackupApp,
      formatVersion: format,
      createdAt: created,
      databases: dbs.cast<String>().toList(growable: false),
      photoCount: photos is int ? photos : 0,
    );
  }
}

const BackupFormatException _notOurBackup = BackupFormatException(
  messagePl: 'To nie jest kopia zapasowa Fitter Welder Pro. '
      'Wybierz plik, który aplikacja sama zapisała.',
  messageEn: 'This is not a Fitter Welder Pro backup. '
      'Pick a file this app created itself.',
);

/// The validated inventory of an archive: manifest plus the entry names the
/// restore is going to read.
class BackupContents {
  final BackupManifest manifest;

  /// `cutlist.db` -> `db/cutlist.db`.
  final Map<String, String> databaseEntries;

  /// Full entry names under `heat_photos/`.
  final List<String> photoEntries;

  const BackupContents({
    required this.manifest,
    required this.databaseEntries,
    required this.photoEntries,
  });

  int get photoCount => photoEntries.length;
}

/// Validates an archive from its entry list and manifest bytes alone.
///
/// Pure on purpose: this is the whole "is this our file, and is it complete"
/// decision, and it is made before a single byte of live data is touched.
BackupContents describeBackup({
  required List<String> entryNames,
  required List<int>? manifestBytes,
}) {
  if (manifestBytes == null) throw _notOurBackup;
  final manifest = BackupManifest.decode(manifestBytes);

  void requirePortableFileName(String file) {
    if (file == '.' || file == '..' ||
        file.codeUnits.any((unit) => unit < 32 || unit == 0x5c || unit == 0x3a)) {
      throw const BackupFormatException(
        messagePl: 'Kopia zawiera nieprawidłową ścieżkę pliku. '
            'Nie można bezpiecznie jej odczytać.',
        messageEn: 'The backup contains an unsafe file path. '
            'It cannot be read safely.',
      );
    }
  }

  final databaseEntries = <String, String>{};
  final photoEntries = <String>[];
  for (final name in entryNames) {
    if (name.startsWith(kDbEntryPrefix)) {
      final file = name.substring(kDbEntryPrefix.length);
      if (file.isEmpty || file.contains('/')) continue;
      requirePortableFileName(file);
      databaseEntries[file] = name;
    } else if (name.startsWith(kPhotoEntryPrefix)) {
      final file = name.substring(kPhotoEntryPrefix.length);
      if (file.isEmpty || file.contains('/')) continue;
      requirePortableFileName(file);
      photoEntries.add(name);
    }
  }

  if (databaseEntries.isEmpty) {
    throw const BackupFormatException(
      messagePl: 'Ta kopia nie zawiera bazy danych — nie ma czego przywrócić.',
      messageEn:
          'This backup contains no database — there is nothing to restore.',
    );
  }

  // A manifest that promises a database the archive does not carry means a
  // truncated or hand-edited file. Restoring half of it would silently drop
  // whole modules, so refuse before the warning dialog is ever shown.
  for (final declared in manifest.databases) {
    if (!databaseEntries.containsKey(declared)) {
      throw const BackupFormatException(
        messagePl: 'Kopia jest niekompletna — brakuje w niej pliku bazy '
            'wymienionego w opisie. Plik mógł się nie doczytać do końca.',
        messageEn: 'The backup is incomplete — a database listed in its '
            'manifest is missing. The file may have been truncated.',
      );
    }
  }

  return BackupContents(
    manifest: manifest,
    databaseEntries: databaseEntries,
    photoEntries: photoEntries,
  );
}

// ───────────────────────────── minimal ZIP codec ───────────────────────────

const int _kLocalHeaderSig = 0x04034b50;
const int _kCentralHeaderSig = 0x02014b50;
const int _kEocdSig = 0x06054b50;
const int _kMaxUint16 = 0xFFFF;
const int _kMaxUint32 = 0xFFFFFFFF;

Uint32List? _crcTable;

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var bit = 0; bit < 8; bit++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

/// CRC-32 (IEEE 802.3), the checksum the ZIP format mandates per entry.
int crc32(List<int> data) {
  final table = _crcTable ??= _buildCrcTable();
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & _kMaxUint32;
}

void _u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);

void _u32(BytesBuilder b, int v) => b.add([
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ]);

int _rd16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _rd32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _dosTime(DateTime t) => (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);

int _dosDate(DateTime t) {
  // The DOS date epoch is 1980; clamp rather than write a negative year field.
  final year = t.year < 1980 ? 1980 : t.year;
  return ((year - 1980) << 9) | (t.month << 5) | t.day;
}

class _CentralRecord {
  final Uint8List name;
  final int crc;
  final int size;
  final int offset;
  final int dosTime;
  final int dosDate;

  const _CentralRecord({
    required this.name,
    required this.crc,
    required this.size,
    required this.offset,
    required this.dosTime,
    required this.dosDate,
  });
}

/// Streaming ZIP writer, STORE method only.
///
/// Writes through a callback rather than returning bytes so the caller can
/// pipe straight into an [IOSink] and never hold more than one photo in
/// memory — a fitter with 400 certificate photos would otherwise OOM the
/// phone. Tests pass `BytesBuilder.add` and get the archive in memory.
class ZipBuilder {
  final void Function(List<int> chunk) _write;
  final List<_CentralRecord> _records = [];
  int _offset = 0;
  bool _finished = false;

  ZipBuilder(this._write);

  /// Bytes written so far, i.e. the size of the archive once [finish] ran.
  int get length => _offset;

  void _emit(List<int> chunk) {
    _write(chunk);
    _offset += chunk.length;
  }

  /// Appends one stored (uncompressed) entry.
  void addFile(String name, List<int> data, {DateTime? modified}) {
    if (_finished) {
      throw StateError('ZipBuilder.addFile() after finish()');
    }
    if (data.length > _kMaxUint32 || _offset > _kMaxUint32) {
      throw const BackupFormatException(
        messagePl:
            'Kopia przekracza 4 GB — tyle nie zmieści się w tym formacie.',
        messageEn: 'The backup exceeds 4 GB, which this format cannot hold.',
      );
    }
    final nameBytes = Uint8List.fromList(utf8.encode(name));
    final when = modified ?? DateTime.now();
    final dosTime = _dosTime(when);
    final dosDate = _dosDate(when);
    final crc = crc32(data);
    final offset = _offset;

    final header = BytesBuilder();
    _u32(header, _kLocalHeaderSig);
    _u16(header, 20); // version needed to extract: 2.0
    _u16(header, 0x0800); // flag bit 11: file name is UTF-8
    _u16(header, 0); // method 0 = stored
    _u16(header, dosTime);
    _u16(header, dosDate);
    _u32(header, crc);
    _u32(header, data.length); // compressed == uncompressed when stored
    _u32(header, data.length);
    _u16(header, nameBytes.length);
    _u16(header, 0); // no extra field

    _emit(header.takeBytes());
    _emit(nameBytes);
    _emit(data);

    _records.add(_CentralRecord(
      name: nameBytes,
      crc: crc,
      size: data.length,
      offset: offset,
      dosTime: dosTime,
      dosDate: dosDate,
    ));
  }

  /// Writes the central directory and end-of-central-directory record.
  void finish() {
    if (_finished) return;
    _finished = true;
    if (_records.length > _kMaxUint16) {
      throw const BackupFormatException(
        messagePl: 'Kopia ma zbyt wiele plików (limit 65535).',
        messageEn: 'The backup has too many files (limit is 65535).',
      );
    }

    final directoryOffset = _offset;
    for (final r in _records) {
      final entry = BytesBuilder();
      _u32(entry, _kCentralHeaderSig);
      _u16(entry, 20); // version made by
      _u16(entry, 20); // version needed
      _u16(entry, 0x0800); // UTF-8 name
      _u16(entry, 0); // stored
      _u16(entry, r.dosTime);
      _u16(entry, r.dosDate);
      _u32(entry, r.crc);
      _u32(entry, r.size);
      _u32(entry, r.size);
      _u16(entry, r.name.length);
      _u16(entry, 0); // extra
      _u16(entry, 0); // comment
      _u16(entry, 0); // disk number start
      _u16(entry, 0); // internal attributes
      _u32(entry, 0); // external attributes
      _u32(entry, r.offset);
      _emit(entry.takeBytes());
      _emit(r.name);
    }
    final directorySize = _offset - directoryOffset;

    final eocd = BytesBuilder();
    _u32(eocd, _kEocdSig);
    _u16(eocd, 0); // this disk
    _u16(eocd, 0); // disk with directory
    _u16(eocd, _records.length);
    _u16(eocd, _records.length);
    _u32(eocd, directorySize);
    _u32(eocd, directoryOffset);
    _u16(eocd, 0); // no archive comment
    _emit(eocd.takeBytes());
  }
}

/// Random-access byte source the ZIP reader walks.
///
/// Abstracted so restore can seek inside a multi-hundred-megabyte file on
/// disk ([FileZipSource]) while tests work on an in-memory buffer
/// ([BytesZipSource]) — same reader code, no temp files in the test run.
abstract class ZipSource {
  int get length;

  /// Returns exactly [count] bytes at [offset], or throws.
  Uint8List read(int offset, int count);
}

class BytesZipSource implements ZipSource {
  final Uint8List _bytes;

  BytesZipSource(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  @override
  int get length => _bytes.length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > _bytes.length) {
      throw _damagedArchive;
    }
    return Uint8List.sublistView(_bytes, offset, offset + count);
  }
}

class FileZipSource implements ZipSource {
  final RandomAccessFile _raf;
  final int _length;

  FileZipSource._(this._raf, this._length);

  factory FileZipSource.open(File file) {
    final raf = file.openSync();
    return FileZipSource._(raf, raf.lengthSync());
  }

  @override
  int get length => _length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > _length) {
      throw _damagedArchive;
    }
    _raf.setPositionSync(offset);
    final bytes = _raf.readSync(count);
    if (bytes.length != count) throw _damagedArchive;
    return bytes;
  }

  void close() => _raf.closeSync();
}

const BackupFormatException _damagedArchive = BackupFormatException(
  messagePl: 'Plik kopii jest uszkodzony albo niedokończony. '
      'Skopiuj go jeszcze raz z miejsca, w którym go trzymasz.',
  messageEn: 'The backup file is damaged or incomplete. '
      'Copy it again from wherever you keep it.',
);

/// One entry as described by the central directory.
class ZipEntry {
  final String name;
  final int method;
  final int crc;
  final int size;
  final int compressedSize;
  final int localHeaderOffset;

  const ZipEntry({
    required this.name,
    required this.method,
    required this.crc,
    required this.size,
    required this.compressedSize,
    required this.localHeaderOffset,
  });
}

/// Parses the central directory — the authoritative index of a ZIP file.
///
/// Reads the index rather than scanning local headers forward, so a file with
/// junk prepended (some mail clients do this) still reads correctly.
List<ZipEntry> readZipDirectory(ZipSource source) {
  final total = source.length;
  if (total < 22) throw _notOurBackup;

  // The EOCD sits at the very end, after an optional comment of up to 64 KiB.
  final tailLength = total < 66000 ? total : 66000;
  final tail = source.read(total - tailLength, tailLength);
  var eocd = -1;
  for (var i = tail.length - 22; i >= 0; i--) {
    if (_rd32(tail, i) == _kEocdSig) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw _notOurBackup;

  final count = _rd16(tail, eocd + 10);
  final directorySize = _rd32(tail, eocd + 12);
  final directoryOffset = _rd32(tail, eocd + 16);
  if (directoryOffset + directorySize > total) throw _damagedArchive;

  final directory = source.read(directoryOffset, directorySize);
  final entries = <ZipEntry>[];
  var pos = 0;
  for (var i = 0; i < count; i++) {
    if (pos + 46 > directory.length ||
        _rd32(directory, pos) != _kCentralHeaderSig) {
      throw _damagedArchive;
    }
    final flags = _rd16(directory, pos + 8);
    final nameLength = _rd16(directory, pos + 28);
    final extraLength = _rd16(directory, pos + 30);
    final commentLength = _rd16(directory, pos + 32);
    if (pos + 46 + nameLength > directory.length) throw _damagedArchive;
    final nameBytes =
        Uint8List.sublistView(directory, pos + 46, pos + 46 + nameLength);
    entries.add(ZipEntry(
      name: (flags & 0x0800) != 0
          ? utf8.decode(nameBytes, allowMalformed: true)
          : latin1.decode(nameBytes),
      method: _rd16(directory, pos + 10),
      crc: _rd32(directory, pos + 16),
      compressedSize: _rd32(directory, pos + 20),
      size: _rd32(directory, pos + 24),
      localHeaderOffset: _rd32(directory, pos + 42),
    ));
    pos += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

/// Reads and CRC-verifies one entry.
///
/// The CRC check is the reason a half-copied backup is caught in the read
/// phase instead of being written over the fitter's live database.
Uint8List readZipEntryBytes(ZipSource source, ZipEntry entry) {
  if (entry.method != 0) {
    throw const BackupFormatException(
      messagePl: 'Ten plik ZIP jest skompresowany przez inny program. '
          'Przywracaj kopię dokładnie w tej postaci, w jakiej zapisała ją '
          'aplikacja — bez rozpakowywania i pakowania na nowo.',
      messageEn: 'This ZIP was compressed by another tool. Restore the backup '
          'exactly as the app wrote it — do not unpack and re-zip it.',
    );
  }
  final header = source.read(entry.localHeaderOffset, 30);
  if (_rd32(header, 0) != _kLocalHeaderSig) throw _damagedArchive;
  final dataOffset = entry.localHeaderOffset +
      30 +
      _rd16(header, 26) + // file name length
      _rd16(header, 28); // extra field length
  final bytes = source.read(dataOffset, entry.compressedSize);
  if (crc32(bytes) != entry.crc) throw _damagedArchive;
  return bytes;
}

/// What a completed restore actually put back, for the confirmation snackbar.
class RestoreReport {
  final DateTime createdAt;
  final int databaseCount;
  final int rowCount;
  final int photoCount;

  /// Tables in the backup this app version has no table for (typically a
  /// backup made by a NEWER version). Their rows were not restored. A table
  /// that belongs to this app's own schema is never listed here: it is
  /// created first and then refilled.
  final List<SkippedTable> skippedTables;

  /// `db/table` → columns that carried data in the backup but do not exist
  /// on this device, so their values could not be restored.
  final Map<String, List<String>> droppedColumns;

  const RestoreReport({
    required this.createdAt,
    required this.databaseCount,
    required this.rowCount,
    required this.photoCount,
    this.skippedTables = const [],
    this.droppedColumns = const {},
  });

  /// Skipped tables that actually held rows — the ones worth telling the
  /// user about. An empty table left behind loses nothing.
  List<SkippedTable> get lostTables =>
      skippedTables.where((t) => t.rowCount > 0).toList(growable: false);

  /// True when everything the backup carried found a place on this device.
  bool get isComplete => lostTables.isEmpty && droppedColumns.isEmpty;

  /// One-line warning for the restore confirmation, or null when
  /// [isComplete]. Both languages, because a service has no BuildContext —
  /// the screen picks with `context.tr(pl: warningPl!, en: warningEn!)`.
  String? get warningPl {
    if (isComplete) return null;
    final parts = <String>[
      for (final t in lostTables) '${t.table} (rekordy: ${t.rowCount})',
      for (final e in droppedColumns.entries) '${e.key}: ${e.value.join(', ')}',
    ];
    return 'Części danych z kopii ta wersja aplikacji nie umie zapisać — '
        'zaktualizuj aplikację i przywróć kopię jeszcze raz. '
        'Pominięto: ${parts.join('; ')}.';
  }

  String? get warningEn {
    if (isComplete) return null;
    final parts = <String>[
      for (final t in lostTables) '${t.table} (records: ${t.rowCount})',
      for (final e in droppedColumns.entries) '${e.key}: ${e.value.join(', ')}',
    ];
    return 'This app version cannot store part of the backup — update the '
        'app and restore the backup again. Skipped: ${parts.join('; ')}.';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF — files, sqflite, share sheet. Covered end to end by
// test/services/data_backup_restore_test.dart on real SQLite files.
// ═══════════════════════════════════════════════════════════════════════════

/// Outcome of refilling one database with [restoreTablesInto].
class TableRestoreResult {
  final int rowsWritten;

  /// Table → number of backup rows that had no live table to go into.
  final Map<String, int> skippedTables;

  /// Table → columns whose values had no live column to go into.
  final Map<String, List<String>> droppedColumns;

  const TableRestoreResult({
    required this.rowsWritten,
    required this.skippedTables,
    required this.droppedColumns,
  });
}

/// Wipes and refills [db] from [tables] inside a single transaction.
///
/// Only tables the backup mentions are wiped — that is how a table added by
/// a newer schema version (and its seeded reference data) survives restoring
/// an older backup instead of ending up empty.
///
/// A backup table the live file does not have is NOT silently dropped any
/// more. [ensureKnownTables], when given, runs first (inside the same
/// transaction) and creates every table the app's own schema defines; only
/// what is still missing after that — a table this app version does not
/// know — is left out, and it is listed in the result so the user hears
/// about it. The same goes for columns that carried data but have no live
/// column ([droppedColumnsWithData]).
///
/// [dryRun] does the whole refill — schema self-heal, wipe, every insert —
/// and then rolls it back on purpose. It is how [DataBackup.restore]
/// validates BOTH databases before writing either: a NOT NULL column the
/// backup cannot fill, a type clash or (where `foreign_keys` is ON) an
/// orphaned child row fails here, while nothing has changed yet. Foreign
/// keys are checked explicitly with `PRAGMA foreign_key_check`, because a
/// deferred violation would otherwise only surface at the COMMIT a dry run
/// never reaches.
///
/// [wipeTablesNotInBackup] also empties live tables the map does not
/// mention. Only the rollback of a failed restore uses it: there the map is
/// the full pre-restore content of the database, so a table that was
/// created (and filled) by the aborted restore must go back to empty.
Future<TableRestoreResult> restoreTablesInto(
  Database db,
  Map<String, List<Map<String, Object?>>> tables, {
  required String heatPhotosDir,
  required Set<String> restoredPhotoNames,
  Future<void> Function(DatabaseExecutor txn)? ensureKnownTables,
  bool dryRun = false,
  bool wipeTablesNotInBackup = false,
  String? weldParamsOwner,
  bool preserveWeldParamOwner = false,
  void Function()? validateOwner,
}) async {
  var written = 0;
  final skipped = <String, int>{};
  final dropped = <String, List<String>>{};
  try {
    await _refill(db, tables,
        heatPhotosDir: heatPhotosDir,
        restoredPhotoNames: restoredPhotoNames,
        ensureKnownTables: ensureKnownTables,
        dryRun: dryRun,
        wipeTablesNotInBackup: wipeTablesNotInBackup,
        weldParamsOwner: weldParamsOwner,
        preserveWeldParamOwner: preserveWeldParamOwner,
        validateOwner: validateOwner,
        onWritten: (n) => written += n,
        skipped: skipped,
        dropped: dropped);
  } on _DryRunRollback {
    // Expected: the dry run succeeded and was rolled back on purpose.
  }
  return TableRestoreResult(
    rowsWritten: written,
    skippedTables: skipped,
    droppedColumns: dropped,
  );
}

/// Thrown at the end of a successful dry run to roll its transaction back.
class _DryRunRollback implements Exception {
  const _DryRunRollback();
}

/// Call only on a staged snapshot. VACUUM also removes other owners' bytes
/// from free SQLite pages, not merely from query results inside the ZIP.
const _ownedLocalTables = {
  'weld_params',
  'iso_drawings',
  'weld_journal',
  'weld_journal_history',
  'weld_repairs',
  'weld_journal_projects',
  // schema32: rejestr uprawnień należy do konta (owner_scope).
  'welder_certificates',
  // schema33: log kuponów i biblioteka WPS.
  'weld_coupons',
  'wps_library',
  // schema34: wyceny i rejestry.
  'weld_quotes',
  'hydrotest_records',
  'passivation_records',
  'instruments',
  // schema34: projekty listy cięć, biblioteka kształtek, odczyty ISO.
  'projects',
  'component_library',
  'iso_scans',
};

/// Dzieci projektu listy cięć (schema34): bez własnego owner_scope, należą
/// do konta projektu (`project_id`).
const _projectChildren = {
  'segments',
  'heat_photos',
  'component_heats',
  'cut_marks',
};

/// Przywracanie drzewa projektów do konta. Projekt, segment, kształtka albo
/// wpis-dziecko z kopii, którego id na telefonie należy do INNEGO konta,
/// dostaje nowe id, a odwołania (`project_id`, `segment_id`,
/// `start/end_library_id`, `library_component_id`, `component_key`) idą za
/// nim. Dzieci projektów innego konta (stara kopia sprzed przycinania,
/// cofnięcie restore) są pomijane — nigdy nie trafiają do cudzego projektu.
class _ProjectTree {
  final projectMap = <Object?, String>{};
  final segmentMap = <Object?, String>{};
  final libraryMap = <Object?, String>{};
  final droppedProjects = <Object?>{};
  final foreignProjects = <Object?>{};
  final foreignChildIds = <String, Set<Object?>>{};

  static const _ownedProject =
      'project_id IN (SELECT id FROM projects WHERE owner_scope = ?)';

  static Future<_ProjectTree?> prepare(
    DatabaseExecutor txn,
    Map<String, List<Map<String, Object?>>> tables,
    Set<String> liveTables, {
    required String owner,
    required bool preserveOwner,
  }) async {
    if (!liveTables.contains('projects')) return null;
    final columns = (await txn.rawQuery('PRAGMA table_info(projects)'))
        .map((r) => r['name'])
        .toSet();
    if (!columns.contains('owner_scope')) return null;
    bool otherOwner(Map<String, Object?> row) =>
        preserveOwner &&
        (row['owner_scope'] ?? LocalRecordOwner.guest) != owner;

    final tree = _ProjectTree();
    tree.foreignProjects.addAll((await txn.query('projects',
            columns: ['id'], where: 'owner_scope != ?', whereArgs: [owner]))
        .map((r) => r['id']));
    for (final row in tables['projects'] ?? const <Map<String, Object?>>[]) {
      final id = row['id'];
      if (otherOwner(row)) {
        tree.droppedProjects.add(id);
      } else if (tree.foreignProjects.contains(id)) {
        tree.projectMap.putIfAbsent(id, () => const Uuid().v4());
      }
    }
    Future<Set<Object?>> notOwned(String table) async =>
        !liveTables.contains(table)
            ? <Object?>{}
            : (await txn.rawQuery(
                    'SELECT id FROM $table WHERE NOT ($_ownedProject)',
                    [owner]))
                .map((r) => r['id'])
                .toSet();
    final foreignSegments = await notOwned('segments');
    for (final row in tables['segments'] ?? const <Map<String, Object?>>[]) {
      if (foreignSegments.contains(row['id'])) {
        tree.segmentMap.putIfAbsent(row['id'], () => const Uuid().v4());
      }
    }
    for (final child in const ['heat_photos', 'component_heats']) {
      tree.foreignChildIds[child] = await notOwned(child);
    }
    if (liveTables.contains('component_library')) {
      final foreignLibrary = (await txn.query('component_library',
              columns: ['id'], where: 'owner_scope != ?', whereArgs: [owner]))
          .map((r) => r['id'])
          .toSet();
      for (final row
          in tables['component_library'] ?? const <Map<String, Object?>>[]) {
        if (otherOwner(row)) continue;
        if (foreignLibrary.contains(row['id'])) {
          tree.libraryMap.putIfAbsent(row['id'], () => const Uuid().v4());
        }
      }
    }
    return tree;
  }

  /// Usuwa dzieci projektów [owner] (przed samymi projektami).
  static void deleteOwnedChildren(Batch batch, String table, String owner) =>
      batch.rawDelete('DELETE FROM $table WHERE $_ownedProject', [owner]);

  /// Wiersz dziecka po przemapowaniu id, albo null, gdy należy do projektu
  /// innego konta.
  Map<String, Object?>? child(String table, Map<String, Object?> row) {
    final project = row['project_id'];
    if (droppedProjects.contains(project)) return null;
    if (foreignProjects.contains(project) && !projectMap.containsKey(project)) {
      return null;
    }
    final out = Map<String, Object?>.of(row);
    out['project_id'] = projectMap[project] ?? project;
    Object? mapped(Map<Object?, String> map, Object? id) => map[id] ?? id;
    if (table == 'segments') {
      out['id'] = mapped(segmentMap, row['id']);
      for (final column in const ['start_library_id', 'end_library_id']) {
        if (out.containsKey(column)) {
          out[column] = mapped(libraryMap, out[column]);
        }
      }
    } else {
      final segment = row['segment_id'];
      if (segment != null) out['segment_id'] = mapped(segmentMap, segment);
      final key = row['component_key'];
      final newSegment = segmentMap[segment];
      if (table == 'component_heats' &&
          key is String &&
          segment is String &&
          newSegment != null &&
          key.startsWith('${segment}_')) {
        out['component_key'] = '$newSegment${key.substring(segment.length)}';
      }
      if (out.containsKey('library_component_id')) {
        out['library_component_id'] =
            mapped(libraryMap, out['library_component_id']);
      }
    }
    if (foreignChildIds[table]?.contains(out['id']) ?? false) {
      out['id'] = const Uuid().v4();
    }
    return out;
  }
}

/// Tabela właściciela, której wiersze mają tabelę-dziecko BEZ owner_scope
/// (historia / wersje należą do właściciela rodzica, jak w DAO) i do której
/// inne tabele właściciela odwołują się po id. Gdy przy przywracaniu id
/// rodzica jest zajęte przez inne konto, rodzic dostaje nowe id, a dziecko
/// i odwołania idą za nim.
class _OwnedParent {
  const _OwnedParent(this.child, this.childKey,
      {this.references = const <String, String>{}});

  final String child;
  final String childKey;

  /// Inna tabela właściciela → kolumna z id tego rodzica.
  final Map<String, String> references;
}

const _ownedParents = <String, _OwnedParent>{
  'welder_certificates':
      _OwnedParent('welder_cert_confirmations', 'certificate_id'),
  'weld_coupons': _OwnedParent('weld_coupon_history', 'coupon_id',
      references: {'weld_journal': 'coupon_id'}),
  'wps_library': _OwnedParent('wps_versions', 'wps_id',
      references: {'weld_journal': 'wps_id'}),
};

/// Stan jednego rodzica w trakcie restore.
class _ParentRestore {
  final idMap = <Object?, String>{};
  final restored = <Object?>{};
  final dropped = <Object?>{};
  final owned = <Object?>{};
  final foreignChildIds = <Object?>{};
}

// Historical function name retained for callers. All account-owned tables
// must be pruned, including their bytes in SQLite free pages.
Future<void> pruneWeldParamsSnapshot(Database db, String owner) async {
  var found = false;
  for (final table in _ownedLocalTables) {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]);
    if (tables.isEmpty) continue;
    found = true;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    await db.execute('PRAGMA secure_delete = ON');
    if (columns.any((r) => r['name'] == 'owner_scope')) {
      await db.delete(table, where: 'owner_scope != ?', whereArgs: [owner]);
    } else if (table == 'projects') {
      // The module database's own legacy `projects` (integer ids, no owner):
      // device data, not the cut-list projects of an account.
      continue;
    } else if (owner != LocalRecordOwner.guest) {
      await db.delete(table);
    }
  }
  final projectsLeft = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='projects'");
  for (final child in _projectChildren) {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [child]);
    if (exists.isEmpty) continue;
    found = true;
    await db.execute('PRAGMA secure_delete = ON');
    if (projectsLeft.isEmpty) {
      if (owner != LocalRecordOwner.guest) await db.delete(child);
    } else {
      await db.rawDelete('DELETE FROM $child WHERE '
          'project_id NOT IN (SELECT id FROM projects)');
    }
  }
  for (final entry in _ownedParents.entries) {
    final child = entry.value.child;
    final children = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [child]);
    if (children.isEmpty) continue;
    found = true;
    await db.execute('PRAGMA secure_delete = ON');
    final parents = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [entry.key]);
    if (parents.isEmpty) {
      await db.delete(child);
    } else {
      await db.rawDelete('DELETE FROM $child WHERE '
          '${entry.value.childKey} NOT IN (SELECT id FROM ${entry.key})');
    }
  }
  if (found) await db.execute('VACUUM');
}

/// Basenames of the photos [db] points at through [kPhotoPathColumns].
/// Compared before and after pruning, it tells which files only another
/// account's rows referenced — those must not travel with this backup.
@visibleForTesting
Future<Set<String>> referencedPhotoNames(Database db) async {
  final names = <String>{};
  for (final entry in kPhotoPathColumns.entries) {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [entry.key]);
    if (exists.isEmpty) continue;
    final columns = (await db.rawQuery('PRAGMA table_info("${entry.key}")'))
        .map((r) => r['name'])
        .toSet();
    if (!columns.contains(entry.value)) continue;
    for (final row in await db.query(entry.key, columns: [entry.value])) {
      final path = row[entry.value];
      if (path is String && path.trim().isNotEmpty) {
        names.add(p.basename(path.replaceAll(r'\', '/')));
      }
    }
  }
  return names;
}

Future<void> _refill(
  Database db,
  Map<String, List<Map<String, Object?>>> tables, {
  required String heatPhotosDir,
  required Set<String> restoredPhotoNames,
  required Future<void> Function(DatabaseExecutor txn)? ensureKnownTables,
  required bool dryRun,
  required bool wipeTablesNotInBackup,
  required String? weldParamsOwner,
  required bool preserveWeldParamOwner,
  required void Function()? validateOwner,
  required void Function(int rows) onWritten,
  required Map<String, int> skipped,
  required Map<String, List<String>> dropped,
}) async {
  var written = 0;
  await db.transaction((txn) async {
    validateOwner?.call();
    // `cut_list_app.db` switches `foreign_keys` ON, so deleting parents
    // before children (or inserting children before parents) would trip a
    // constraint mid-restore. Deferring the check to COMMIT lets the whole
    // refill be judged once, as a unit — which is exactly the guarantee the
    // user was promised.
    try {
      await txn.execute('PRAGMA defer_foreign_keys = ON');
    } catch (_) {
      // Older SQLite without the pragma: the transaction still rolls back
      // as a whole, we just lose the ordering freedom.
    }

    Future<Set<String>> liveTableNames() async => (await txn
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((row) => row['name'] as String)
        .where(isRestorableTable)
        .toSet();

    var liveTables = await liveTableNames();
    if (ensureKnownTables != null &&
        tables.keys.any((table) => !liveTables.contains(table))) {
      await ensureKnownTables(txn);
      liveTables = await liveTableNames();
    }

    // Tables of the account by name AND by column: the module database has
    // its own legacy `projects` without an owner — that one is device data.
    final ownedLive = <String>{
      for (final table in liveTables)
        if (_ownedLocalTables.contains(table) &&
            (await txn.rawQuery('PRAGMA table_info("$table")'))
                .any((r) => r['name'] == 'owner_scope'))
          table,
    };

    final journalIdMap = <Object?, String>{};
    final validJournalIds = <Object?>{};
    if (weldParamsOwner != null && liveTables.contains('weld_journal')) {
      final parentColumns =
          (await txn.rawQuery('PRAGMA table_info(weld_journal)'))
              .map((r) => r['name'])
              .toSet();
      if (parentColumns.contains('owner_scope')) {
        final existing =
            await txn.query('weld_journal', columns: ['id', 'owner_scope']);
        final foreign = existing
            .where((r) => r['owner_scope'] != weldParamsOwner)
            .map((r) => r['id'])
            .toSet();
        if (tables.containsKey('weld_journal') || wipeTablesNotInBackup) {
          for (final row
              in tables['weld_journal'] ?? const <Map<String, Object?>>[]) {
            if (preserveWeldParamOwner &&
                (row['owner_scope'] ?? LocalRecordOwner.guest) !=
                    weldParamsOwner) {
              continue;
            }
            final sourceId = row['id'];
            if (foreign.contains(sourceId)) {
              journalIdMap.putIfAbsent(sourceId, () => const Uuid().v4());
            }
            validJournalIds.add(journalIdMap[sourceId] ?? sourceId);
          }
        } else {
          validJournalIds.addAll(existing
              .where((r) => r['owner_scope'] == weldParamsOwner)
              .map((r) => r['id']));
        }
      }
    }

    // Rejestr uprawnień (schema32), log kuponów i biblioteka WPS (schema33):
    // wiersz z kopii, którego id na telefonie należy do INNEGO właściciela,
    // dostaje nowe id, a jego historia / wersje i odwołania z dziennika idą
    // za nim. Historia wierszy innych właścicieli ze starej kopii (sprzed
    // przycinania eksportu) jest świadomie pomijana.
    final parentStates = <String, _ParentRestore>{};
    if (weldParamsOwner != null) {
      for (final spec in _ownedParents.entries) {
        final parent = spec.key;
        if (!liveTables.contains(parent)) continue;
        final parentColumns =
            (await txn.rawQuery('PRAGMA table_info($parent)'))
                .map((r) => r['name'])
                .toSet();
        if (!parentColumns.contains('owner_scope')) continue;
        final state = parentStates[parent] = _ParentRestore();
        final existing =
            await txn.query(parent, columns: ['id', 'owner_scope']);
        final foreign = existing
            .where((r) => r['owner_scope'] != weldParamsOwner)
            .map((r) => r['id'])
            .toSet();
        if (tables.containsKey(parent) || wipeTablesNotInBackup) {
          for (final row
              in tables[parent] ?? const <Map<String, Object?>>[]) {
            final sourceId = row['id'];
            if (preserveWeldParamOwner &&
                (row['owner_scope'] ?? LocalRecordOwner.guest) !=
                    weldParamsOwner) {
              state.dropped.add(sourceId);
              continue;
            }
            if (foreign.contains(sourceId)) {
              state.idMap.putIfAbsent(sourceId, () => const Uuid().v4());
            }
            state.restored.add(state.idMap[sourceId] ?? sourceId);
          }
        } else {
          state.owned.addAll(existing
              .where((r) => r['owner_scope'] == weldParamsOwner)
              .map((r) => r['id']));
        }
        final child = spec.value.child;
        if (liveTables.contains(child)) {
          state.foreignChildIds.addAll((await txn.rawQuery(
                  'SELECT id FROM $child WHERE ${spec.value.childKey} '
                  'NOT IN (SELECT id FROM $parent WHERE owner_scope = ?)',
                  [weldParamsOwner]))
              .map((r) => r['id']));
        }
      }
    }
    final childParent = <String, String>{
      for (final parent in parentStates.keys) _ownedParents[parent]!.child: parent,
    };
    final projectTree = weldParamsOwner == null
        ? null
        : await _ProjectTree.prepare(txn, tables, liveTables,
            owner: weldParamsOwner, preserveOwner: preserveWeldParamOwner);

    final batch = txn.batch();
    if (projectTree != null) {
      for (final child in _projectChildren) {
        if (liveTables.contains(child) &&
            (wipeTablesNotInBackup || tables.containsKey(child))) {
          // Przed kasowaniem projektów — podzapytanie musi je jeszcze widzieć.
          _ProjectTree.deleteOwnedChildren(batch, child, weldParamsOwner!);
        }
      }
    }
    for (final parent in parentStates.keys) {
      final spec = _ownedParents[parent]!;
      if (liveTables.contains(spec.child) &&
          (wipeTablesNotInBackup ||
              tables.containsKey(parent) ||
              tables.containsKey(spec.child))) {
        // Przed kasowaniem rodziców — podzapytanie musi ich jeszcze widzieć.
        batch.rawDelete(
            'DELETE FROM ${spec.child} WHERE ${spec.childKey} IN '
            '(SELECT id FROM $parent WHERE owner_scope = ?)',
            [weldParamsOwner]);
      }
    }
    for (final table in liveTables) {
      if (childParent.containsKey(table)) continue;
      if (projectTree != null && _projectChildren.contains(table)) continue;
      if (wipeTablesNotInBackup || tables.containsKey(table)) {
        if (ownedLive.contains(table) && weldParamsOwner != null) {
          batch.delete(table,
              where: 'owner_scope = ?', whereArgs: [weldParamsOwner]);
        } else {
          batch.delete(table);
        }
      }
    }
    for (final entry in tables.entries) {
      if (!liveTables.contains(entry.key)) {
        skipped[entry.key] = entry.value.length;
        continue;
      }
      // Safe to interpolate: isRestorableTable() already proved the name is
      // a plain identifier.
      final columns = (await txn.rawQuery('PRAGMA table_info("${entry.key}")'))
          .map((row) => row['name'] as String)
          .toSet();
      final lost = droppedColumnsWithData(entry.value, columns);
      if (lost.isNotEmpty) dropped[entry.key] = lost;
      final sourceRows = ownedLive.contains(entry.key) &&
              weldParamsOwner != null &&
              preserveWeldParamOwner
          ? entry.value
              .where((r) =>
                  (r['owner_scope'] ?? LocalRecordOwner.guest) ==
                  weldParamsOwner)
              .toList()
          : entry.value;
      final rows = prepareRows(
        table: entry.key,
        rows: sourceRows,
        liveColumns: columns,
        heatPhotosDir: heatPhotosDir,
        restoredPhotoNames: restoredPhotoNames,
      );
      final foreignIds = ownedLive.contains(entry.key) &&
              weldParamsOwner != null &&
              columns.contains('id')
          ? (await txn.query(entry.key,
                  columns: ['id'],
                  where: 'owner_scope != ?',
                  whereArgs: [weldParamsOwner]))
              .map((r) => r['id'])
              .toSet()
          : const <Object?>{};
      var skippedChildren = 0;
      for (final row in rows) {
        var ownedRow = Map<String, Object?>.of(row);
        if (projectTree != null && _projectChildren.contains(entry.key)) {
          final child = projectTree.child(entry.key, ownedRow);
          if (child == null) {
            skippedChildren++; // dziecko projektu innego konta
            continue;
          }
          ownedRow = child;
        }
        final parentOfChild = childParent[entry.key];
        if (parentOfChild != null) {
          final state = parentStates[parentOfChild]!;
          final key = _ownedParents[parentOfChild]!.childKey;
          final source = ownedRow[key];
          if (state.dropped.contains(source)) {
            skippedChildren++; // historia wiersza innego właściciela
            continue;
          }
          final mapped = state.idMap[source] ?? source;
          if (!state.restored.contains(mapped) &&
              !state.owned.contains(mapped)) {
            throw const BackupFormatException(
                messagePl: 'Historia lub wersja wskazuje na brakujący wpis '
                    '(certyfikat, kupon albo WPS). Nic nie zmieniono.',
                messageEn: 'History or a version references a missing entry '
                    '(certificate, coupon or WPS). Nothing changed.');
          }
          ownedRow[key] = mapped;
          if (state.foreignChildIds.contains(ownedRow['id'])) {
            ownedRow['id'] = const Uuid().v4();
          }
        }
        if (ownedLive.contains(entry.key) && weldParamsOwner != null) {
          ownedRow['owner_scope'] = weldParamsOwner;
          if (entry.key == 'weld_journal') {
            ownedRow['id'] = journalIdMap[ownedRow['id']] ?? ownedRow['id'];
          } else if (parentStates.containsKey(entry.key)) {
            ownedRow['id'] =
                parentStates[entry.key]!.idMap[ownedRow['id']] ?? ownedRow['id'];
          } else if (projectTree != null && entry.key == 'projects') {
            ownedRow['id'] =
                projectTree.projectMap[ownedRow['id']] ?? ownedRow['id'];
          } else if (projectTree != null && entry.key == 'component_library') {
            ownedRow['id'] =
                projectTree.libraryMap[ownedRow['id']] ?? ownedRow['id'];
          } else if (foreignIds.contains(ownedRow['id'])) {
            ownedRow['id'] = const Uuid().v4();
          }
          for (final parent in parentStates.entries) {
            final column = _ownedParents[parent.key]!.references[entry.key];
            if (column == null) continue;
            final mapped = parent.value.idMap[ownedRow[column]];
            if (mapped != null) ownedRow[column] = mapped;
          }
          if (const {'weld_journal_history', 'weld_repairs'}
              .contains(entry.key)) {
            ownedRow['weld_id'] =
                journalIdMap[ownedRow['weld_id']] ?? ownedRow['weld_id'];
            if (!validJournalIds.contains(ownedRow['weld_id'])) {
              throw const BackupFormatException(
                  messagePl:
                      'Historia lub naprawa wskazuje na brakującą spoinę. Nic nie zmieniono.',
                  messageEn:
                      'History or a repair references a missing weld. Nothing changed.');
            }
          }
        }
        batch.insert(entry.key, ownedRow,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      written += rows.length - skippedChildren;
    }
    await batch.commit(noResult: true);
    validateOwner?.call();

    if (dryRun) {
      final enforced =
          (await txn.rawQuery('PRAGMA foreign_keys')).firstOrNull?.values.first;
      if (enforced == 1) {
        final violations = await txn.rawQuery('PRAGMA foreign_key_check');
        if (violations.isNotEmpty) {
          final where = violations
              .map((v) => '${v['table']} → ${v['parent']}')
              .toSet()
              .join(', ');
          throw BackupFormatException(
            messagePl: 'Kopii nie da się przywrócić: część wierszy wskazuje na '
                'nieistniejące rekordy ($where). Nic nie zostało zmienione.',
            messageEn: 'The backup cannot be restored: some rows point at '
                'records that do not exist ($where). Nothing was changed.',
          );
        }
      }
      onWritten(written);
      throw const _DryRunRollback();
    }
  });
  onWritten(written);
}

/// One live SQLite file the app owns, with the things backup needs: where its
/// file is, how to reach the open handle the rest of the app uses, and —
/// where the owner exposes one — how to create the tables its schema knows.
class _LiveDatabase {
  final String fileName;
  final Future<String> Function() resolvePath;
  final Future<Database> Function() open;
  final Future<void> Function(DatabaseExecutor txn)? ensureKnownTables;

  const _LiveDatabase(
    this.fileName,
    this.resolvePath,
    this.open, {
    this.ensureKnownTables,
  });
}

/// Copies restored photos into `heat_photos` and remembers how to undo it:
/// a file that already existed under the same name is saved to [saveDir]
/// before being overwritten, a new one is deleted again by [undo].
class _PhotoRollback {
  _PhotoRollback(this.heatDir, this.saveDir);

  final Directory heatDir;
  final Directory saveDir;
  final List<String> _added = [];
  final List<String> _replaced = [];

  Future<void> put(File source, String base) async {
    final target = File(p.join(heatDir.path, base));
    if (await target.exists()) {
      if (!await saveDir.exists()) await saveDir.create(recursive: true);
      await target.copy(p.join(saveDir.path, base));
      _replaced.add(base);
    } else {
      _added.add(base);
    }
    await source.copy(target.path);
  }

  Future<void> undo() async {
    for (final base in _added) {
      final f = File(p.join(heatDir.path, base));
      if (await f.exists()) await f.delete();
    }
    for (final base in _replaced) {
      await File(p.join(saveDir.path, base)).copy(p.join(heatDir.path, base));
    }
  }
}

/// A photo going into the archive under `heat_photos/<name>`.
class _ArchivedPhoto {
  final String name;
  final File source;

  const _ArchivedPhoto(this.name, this.source);
}

class DataBackup {
  static final _archiveOwners = Expando<LocalRecordOwner>();
  DataBackup._();

  /// Test hook: called right before each database is written during a
  /// restore (after both passed validation). A test throws from here to
  /// simulate a disk-full error between the two databases.
  @visibleForTesting
  static Future<void> Function(String fileName)? debugBeforeDatabaseCommit;

  /// The app writes TWO databases and a fitter's data is split across both, so
  /// backing up only `cutlist.db` would quietly lose the welder-pipe module.
  /// Everything below is generic over this list — nothing knows the schemas.
  static final List<_LiveDatabase> _databases = [
    // Wrapped in closures rather than torn off, because the accessor on the
    // main database is literally named `get` and a bare tear-off of it reads
    // like a property access to anyone maintaining this list.
    _LiveDatabase(
      'cutlist.db',
      _cutListDbPath,
      () => cutlist_db.AppDatabase.get(),
      // Every register (weld journal, coupons, pressure tests, ISO sketches)
      // lives in this file's schema, so a table of ours that the live file
      // lacks is created and refilled instead of skipped.
      ensureKnownTables: cutlist_db.AppDatabase.ensureTables,
    ),
    // `lib/data/app_database.dart` creates its whole schema on open and
    // exposes no table-level hook; a backup table it lacks is reported.
    _LiveDatabase(
      'cut_list_app.db',
      _moduleDbPath,
      () => module_db.AppDatabase.instance.db,
    ),
  ];

  static Future<String> _cutListDbPath() async =>
      p.join(await getDatabasesPath(), 'cutlist.db');

  static Future<String> _moduleDbPath() async => p.join(
      (await getApplicationDocumentsDirectory()).path, 'cut_list_app.db');

  /// `<documents>/heat_photos`: where `heat_photos_screen.dart` and the
  /// component-heat picker (via `heat_photo_storage.dart`) copy picked
  /// certificate photos precisely so they survive a cache wipe.
  static Future<Directory> _heatPhotosDir() => heatPhotosDirectory();

  /// Writes the archive into the temporary directory and returns it.
  ///
  /// Split from [shareBackupFile] so the file-producing half can be driven
  /// from a driver test without opening a share sheet nobody can dismiss.
  static Future<File> createBackupFile({DateTime? now}) async {
    final owner = await LocalRecordOwner.capture();
    final stamp = now ?? DateTime.now();
    final tempDir = await getTemporaryDirectory();
    final target = File(p.join(tempDir.path, backupFileName(stamp)));
    if (await target.exists()) await target.delete();

    final staging = Directory(
      p.join(tempDir.path, 'fwp_backup_${stamp.millisecondsSinceEpoch}'),
    );
    await staging.create(recursive: true);

    try {
      final snapshots = <String, File>{};
      // Zdjęcia wskazywane WYŁĄCZNIE przez wiersze innych właścicieli (np. skan
      // cudzego certyfikatu) zostają na telefonie. Reszta katalogu leci jak
      // dotąd — także pliki, na które nie wskazuje znana kolumna.
      final before = <String>{};
      final kept = <String>{};
      for (final db in _databases) {
        final live = File(await db.resolvePath());
        if (!await live.exists()) continue;
        final snapshot = await _snapshot(db, live, staging);
        final stagedDb = await databaseFactory.openDatabase(snapshot.path,
            options: OpenDatabaseOptions(singleInstance: false));
        try {
          before.addAll(await referencedPhotoNames(stagedDb));
          await pruneWeldParamsSnapshot(stagedDb, owner.key);
          kept.addAll(await referencedPhotoNames(stagedDb));
        } finally {
          await stagedDb.close();
        }
        owner.requireCurrent();
        snapshots[db.fileName] = snapshot;
      }

      final foreignOnly = before.difference(kept);
      final heatDir = await _heatPhotosDir();
      final photos = <_ArchivedPhoto>[];
      if (await heatDir.exists()) {
        final owned = <File>[
          for (final item in heatDir.listSync(followLinks: false))
            if (item is File &&
                !foreignOnly.contains(p.basename(item.path)))
              item,
        ];
        // Stable order keeps two backups of unchanged data byte-comparable,
        // which is how a user can tell nothing was lost between them.
        owned.sort((a, b) => a.path.compareTo(b.path));
        photos.addAll(owned.map((f) => _ArchivedPhoto(p.basename(f.path), f)));
      }

      // Rows that point OUTSIDE heat_photos — component heats picked before
      // the picker started copying into the app, older heat photos — would
      // otherwise reference a file the archive never carries. Pull those
      // files in and point the SNAPSHOT (never the live row) at their
      // archive name, which restore then re-anchors like any other photo.
      final takenNames = photos.map((photo) => photo.name).toSet();
      for (final snapshot in snapshots.values) {
        photos.addAll(
          await _adoptExternalPhotos(snapshot, heatDir.path, takenNames),
        );
      }

      final manifest = BackupManifest(
        app: kBackupApp,
        formatVersion: kBackupFormatVersion,
        createdAt: stamp,
        databases: snapshots.keys.toList(growable: false),
        photoCount: photos.length,
      );

      final sink = target.openWrite();
      final zip = ZipBuilder(sink.add);
      try {
        zip.addFile(kManifestEntry, utf8.encode(manifest.encode()),
            modified: stamp);
        for (final entry in snapshots.entries) {
          zip.addFile(
              '$kDbEntryPrefix${entry.key}', await entry.value.readAsBytes(),
              modified: stamp);
          // Flush between entries so the sink's buffer never grows past one
          // file; without this the whole archive would queue up in RAM.
          await sink.flush();
        }
        for (final photo in photos) {
          zip.addFile('$kPhotoEntryPrefix${photo.name}',
              await photo.source.readAsBytes(),
              modified: stamp);
          await sink.flush();
        }
        zip.finish();
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (!await target.exists() || await target.length() < 22) {
        throw const BackupFormatException(
          messagePl: 'Nie udało się zapisać kopii — sprawdź, czy w telefonie '
              'jest wolne miejsce.',
          messageEn: 'Could not write the backup — check that the phone has '
              'free storage.',
        );
      }
      owner.requireCurrent();
      _archiveOwners[target] = owner;
      return target;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// A consistent copy of one live database.
  ///
  /// `VACUUM INTO` produces a transactionally consistent, defragmented file
  /// even while the app holds the database open — the correct primitive here.
  /// It needs SQLite 3.27+, which old Android system libraries predate, so the
  /// fallback checkpoints the WAL (folding recent writes back into the main
  /// file) and copies. Copying without the checkpoint could ship a database
  /// missing the last few saves.
  static Future<File> _snapshot(
    _LiveDatabase db,
    File live,
    Directory staging,
  ) async {
    final target = File(p.join(staging.path, db.fileName));
    final handle = await db.open();
    try {
      if (await target.exists()) await target.delete();
      await handle.execute('VACUUM INTO ?', [target.path]);
      if (await target.exists() && await target.length() > 0) return target;
    } catch (_) {
      // Fall through to the checkpoint + copy path below.
    }
    try {
      await handle.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Not in WAL mode, or the pragma is unavailable: the plain copy below
      // is already correct in that case.
    }
    return live.copy(target.path);
  }

  /// Finds photo paths in [snapshot] that live outside [heatDirPath], and
  /// returns those files as archive entries under collision-free names
  /// ([archiveNameForExternalPhoto]), rewriting the snapshot's rows to
  /// `<heatDirPath>/<that name>` so restore re-anchors them by file name.
  ///
  /// Works on the staged SNAPSHOT only: the live database keeps pointing at
  /// the original file, so making a backup never changes the user's data.
  /// A path whose file is gone or unreadable is left exactly as stored —
  /// that string is the only record of which photo the row once had.
  static Future<List<_ArchivedPhoto>> _adoptExternalPhotos(
    File snapshot,
    String heatDirPath,
    Set<String> takenNames,
  ) async {
    final root = p.normalize(heatDirPath);
    final names = Set<String>.of(takenNames);
    final adopted = <String, String>{}; // source path → archive name
    Database? db;
    try {
      db = await databaseFactory.openDatabase(
        snapshot.path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final tables = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((row) => row['name'] as String)
          .toSet();
      final targets = <(String, String)>[]; // (table, column) to rewrite
      for (final entry in kPhotoPathColumns.entries) {
        final table = entry.key;
        final column = entry.value;
        if (!tables.contains(table)) continue;
        targets.add((table, column));
        // Identifiers come from the const map above, never from the file.
        final rows = await db.rawQuery(
          'SELECT DISTINCT "$column" AS path FROM "$table" '
          'WHERE "$column" IS NOT NULL',
        );
        for (final row in rows) {
          final stored = row['path'];
          if (stored is! String || stored.trim().isEmpty) continue;
          if (adopted.containsKey(stored)) continue;
          if (p.isWithin(root, p.normalize(stored))) continue;
          if (!await _isReadableFile(stored)) continue;
          adopted[stored] = archiveNameForExternalPhoto(stored, names);
        }
      }
      if (adopted.isEmpty) return const [];
      // All rewrites or none: a half-rewritten snapshot would point rows at
      // archive names whose files were never added.
      await db.transaction((txn) async {
        for (final (table, column) in targets) {
          for (final e in adopted.entries) {
            await txn.update(
              table,
              <String, Object?>{column: p.join(heatDirPath, e.value)},
              where: '"$column" = ?',
              whereArgs: <Object?>[e.key],
            );
          }
        }
      });
    } catch (e) {
      // Never let this extra step fail a backup that worked before it
      // existed: the rows keep their original paths, as they always did.
      debugPrint('Backup: adopting photos outside heat_photos failed: $e');
      return const [];
    } finally {
      await db?.close();
    }
    takenNames.addAll(names);
    return [
      for (final e in adopted.entries) _ArchivedPhoto(e.value, File(e.key)),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  static Future<bool> _isReadableFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final handle = await file.open();
      await handle.close();
      return true;
    } catch (_) {
      // No permission (Android scoped storage) or a vanished mount: the row
      // keeps its path, the backup still succeeds.
      return false;
    }
  }

  /// Hands an already-written archive to the system share sheet.
  ///
  /// The share sheet is the whole delivery mechanism: the file goes wherever
  /// the user sends it and nowhere else. Kept separate from
  /// [createBackupFile] so the caller can take its progress indicator down
  /// before the sheet appears — a spinner stranded behind a system sheet
  /// looks like the app hung.
  ///
  /// The explicit `application/zip` MIME type is the same fix
  /// `iso_pdf_export.dart` documents: without it some Android launchers offer
  /// only text targets and the file appears unshareable.
  static Future<void> shareBackupFile(File file) async {
    final owner = _archiveOwners[file];
    try {
      if (owner == null) throw StateError('Unbound backup');
      owner.requireCurrent();
    } catch (_) {
      throw const BackupFormatException(
          messagePl:
              'Sesja zmieniła się. Utwórz kopię ponownie przed udostępnieniem.',
          messageEn:
              'The session changed. Create the backup again before sharing.');
    }
    final name = p.basename(file.path);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/zip', name: name)],
      subject: 'Fitter Welder Pro — $name',
    );
  }

  /// Validates a picked file and reports what is inside it. Writes nothing.
  static Future<BackupContents> inspect(String path) async {
    final source = FileZipSource.open(File(path));
    try {
      return _describe(source, _indexEntries(source));
    } finally {
      source.close();
    }
  }

  static Map<String, ZipEntry> _indexEntries(ZipSource source) {
    final entries = <String, ZipEntry>{};
    final names = <String>{};
    for (final entry in readZipDirectory(source)) {
      // Backups travel between platforms, including case-insensitive targets.
      if (!names.add(entry.name.toLowerCase())) {
        throw const BackupFormatException(
          messagePl: 'Kopia zawiera powtarzające się nazwy plików. '
              'Nie można bezpiecznie jej odczytać.',
          messageEn: 'The backup contains duplicate file names. '
              'It cannot be read safely.',
        );
      }
      entries[entry.name] = entry;
    }
    return entries;
  }

  static BackupContents _describe(
    ZipSource source,
    Map<String, ZipEntry> entries,
  ) {
    final manifestEntry = entries[kManifestEntry];
    return describeBackup(
      entryNames: entries.keys.toList(growable: false),
      manifestBytes: manifestEntry == null
          ? null
          : readZipEntryBytes(source, manifestEntry),
    );
  }

  /// Replaces this device's data with the contents of [path].
  ///
  /// See the library doc for the two-phase guarantee: everything that can fail
  /// because of the *file* fails before any live write happens.
  static Future<RestoreReport> restore(String path,
      {LocalRecordOwner? expectedOwner}) async {
    final owner = expectedOwner ?? await LocalRecordOwner.capture();
    owner.requireCurrent();
    final tempDir = await getTemporaryDirectory();
    final staging = await tempDir.createTemp('fwp_restore_');
    FileZipSource? source;

    try {
      source = FileZipSource.open(File(path));
      final entries = _indexEntries(source);
      final contents = _describe(source, entries);

      // ---- Phase 1: read the whole archive. Live data still untouched.
      final tablesByDatabase =
          <String, Map<String, List<Map<String, Object?>>>>{};
      for (final db in contents.databaseEntries.entries) {
        final bytes = readZipEntryBytes(source, entries[db.value]!);
        if (!looksLikeSqliteDatabase(bytes)) {
          throw const BackupFormatException(
            messagePl: 'Plik w kopii nie jest bazą danych. '
                'Kopia jest uszkodzona albo została podmieniona.',
            messageEn: 'A file inside the backup is not a database. '
                'The backup is damaged or was tampered with.',
          );
        }
        final staged = File(p.join(staging.path, db.key));
        await staged.writeAsBytes(bytes, flush: true);
        tablesByDatabase[db.key] = await _readAllTables(staged.path);
      }

      final stagedPhotos = Directory(p.join(staging.path, 'heat_photos'));
      await stagedPhotos.create(recursive: true);
      final photoNames = <String>{};
      for (final name in contents.photoEntries) {
        final base = zipEntryBaseName(name);
        // '.' / '..' would resolve outside the photo folder; this app never
        // writes such an entry, so it can only come from a doctored file.
        if (base.isEmpty || base == '.' || base == '..') continue;
        final bytes = readZipEntryBytes(source, entries[name]!);
        await File(p.join(stagedPhotos.path, base))
            .writeAsBytes(bytes, flush: true);
        photoNames.add(base);
      }

      final heatDir = await _heatPhotosDir();
      final targets = [
        for (final db in _databases)
          if (tablesByDatabase[db.fileName] != null) db,
      ];

      // ---- Phase 1b: validate BOTH databases against the live schema — a
      // full refill of each, rolled back on purpose. Still nothing written.
      for (final db in targets) {
        await restoreTablesInto(
          await db.open(),
          tablesByDatabase[db.fileName]!,
          heatPhotosDir: heatDir.path,
          restoredPhotoNames: photoNames,
          ensureKnownTables: db.ensureKnownTables,
          dryRun: true,
          weldParamsOwner: owner.key,
          validateOwner: owner.requireCurrent,
        );
      }

      // ---- Phase 2: commit, with a way back. SQLite has no two-phase
      // commit across two files, so each live database is snapshotted first;
      // if anything fails after the first write, every database already
      // written is refilled from its snapshot and the photos are put back.
      final rollbackDir = Directory(p.join(staging.path, 'rollback'));
      await rollbackDir.create(recursive: true);
      final rollbackDbs = <_LiveDatabase, File>{};
      for (final db in targets) {
        final live = File(await db.resolvePath());
        await db.open(); // creates the file on a fresh install
        rollbackDbs[db] = await _snapshot(db, live, rollbackDir);
      }

      final photoRollback = _PhotoRollback(
          heatDir, Directory(p.join(rollbackDir.path, 'heat_photos')));
      final committed = <_LiveDatabase>[];
      var rows = 0;
      var restoredDatabases = 0;
      final skipped = <SkippedTable>[];
      final dropped = <String, List<String>>{};
      try {
        // Photos first: a file nothing references is harmless, a row
        // pointing at a missing file is not.
        if (!await heatDir.exists()) await heatDir.create(recursive: true);
        for (final base in photoNames) {
          await photoRollback.put(File(p.join(stagedPhotos.path, base)), base);
        }

        for (final db in targets) {
          await debugBeforeDatabaseCommit?.call(db.fileName);
          final result = await restoreTablesInto(
            await db.open(),
            tablesByDatabase[db.fileName]!,
            heatPhotosDir: heatDir.path,
            restoredPhotoNames: photoNames,
            ensureKnownTables: db.ensureKnownTables,
            weldParamsOwner: owner.key,
            validateOwner: owner.requireCurrent,
          );
          committed.add(db);
          rows += result.rowsWritten;
          restoredDatabases++;
          for (final e in result.skippedTables.entries) {
            skipped.add(SkippedTable(
                database: db.fileName, table: e.key, rowCount: e.value));
          }
          for (final e in result.droppedColumns.entries) {
            dropped['${db.fileName}/${e.key}'] = e.value;
          }
        }
      } catch (error) {
        final rollbackErrors = <Object>[];
        for (final db in committed.reversed) {
          try {
            await restoreTablesInto(
              await db.open(),
              await _readAllTables(rollbackDbs[db]!.path),
              heatPhotosDir: heatDir.path,
              restoredPhotoNames: const <String>{},
              wipeTablesNotInBackup: true,
              weldParamsOwner: owner.key,
              preserveWeldParamOwner: true,
            );
          } catch (e) {
            rollbackErrors.add(e);
          }
        }
        try {
          await photoRollback.undo();
        } catch (e) {
          rollbackErrors.add(e);
        }
        if (rollbackErrors.isNotEmpty) {
          debugPrint('Restore rollback failed: $rollbackErrors (after $error)');
          throw BackupFormatException(
            messagePl:
                'Przywracanie przerwane ($error) i nie udało się w pełni '
                'cofnąć zmian. Nie usuwaj kopii — przywróć ją ponownie, gdy '
                'zwolnisz miejsce w telefonie.',
            messageEn: 'The restore was interrupted ($error) and could not be '
                'fully undone. Keep the backup file and restore it again once '
                'the phone has free storage.',
          );
        }
        if (error is BackupFormatException) rethrow;
        throw BackupFormatException(
          messagePl: 'Przywracanie przerwane: $error. Nic nie zostało '
              'zmienione — dane w telefonie są takie jak przed próbą.',
          messageEn: 'The restore was interrupted: $error. Nothing was '
              'changed — the data on the phone is as it was before.',
        );
      }
      // A database file this version does not own at all (a future module)
      // is not restored either — and is not allowed to vanish silently.
      final known = _databases.map((db) => db.fileName).toSet();
      for (final db in tablesByDatabase.entries) {
        if (known.contains(db.key)) continue;
        for (final t in db.value.entries) {
          skipped.add(SkippedTable(
              database: db.key, table: t.key, rowCount: t.value.length));
        }
      }

      return RestoreReport(
        createdAt: contents.manifest.createdAt,
        databaseCount: restoredDatabases,
        rowCount: rows,
        photoCount: photoNames.length,
        skippedTables: skipped,
        droppedColumns: dropped,
      );
    } finally {
      try {
        source?.close();
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    }
  }

  /// Reads every restorable table out of a staged database file.
  ///
  /// Opened read-only and with `singleInstance: false` so this temporary
  /// handle can never collide with, or be handed out in place of, one of the
  /// app's own cached connections.
  static Future<Map<String, List<Map<String, Object?>>>> _readAllTables(
    String path,
  ) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final names = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((row) => row['name'] as String)
          .where(isRestorableTable)
          .toList();
      final out = <String, List<Map<String, Object?>>>{};
      for (final table in names) {
        out[table] = (await db.query(table))
            .map((row) => Map<String, Object?>.from(row))
            .toList();
      }
      return out;
    } finally {
      await db.close();
    }
  }
}
