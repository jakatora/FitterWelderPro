import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_location_problem.dart';

class _UnrecognizedDatabase implements Exception {
  const _UnrecognizedDatabase();

  @override
  String toString() =>
      'Nie rozpoznano struktury bazy FitterWelder Pro. Zachowaj plik i sprawdź kopię danych. '
      '/ The FitterWelder Pro database structure was not recognized. Keep the file and check your backup.';
}

/// Resolves the Windows database directory without copying or replacing data.
///
/// Existing databases stay in place, so old and new releases continue to use
/// the same SQLite file (including its WAL). Ambiguous or missing locations
/// fail closed: callers must explain the problem rather than create an empty DB.
class WindowsDatabaseLocation {
  WindowsDatabaseLocation(this.supportDirectory);

  final Directory supportDirectory;
  static const _databaseName = 'cutlist.db';
  static const _markerName = 'database-location.json';

  Future<String> resolve({required Iterable<String> legacyDirectories}) async {
    await supportDirectory.create(recursive: true);
    final lockFile =
        File(p.join(supportDirectory.path, 'database-location.lock'));
    final lock = await lockFile.open(mode: FileMode.append);
    try {
      await lock.lock();
      return await _resolveLocked(legacyDirectories);
    } finally {
      await lock.close();
    }
  }

  /// Records an explicit user choice without modifying either database.
  /// Any later, previously unseen database will trigger a new choice.
  Future<void> selectExisting(
      String directory, List<String> acknowledged) async {
    await supportDirectory.create(recursive: true);
    final lockFile =
        File(p.join(supportDirectory.path, 'database-location.lock'));
    final lock = await lockFile.open(mode: FileMode.append);
    try {
      await lock.lock();
      final marker = File(p.join(supportDirectory.path, _markerName));
      await _rejectNewerMarker(marker);
      final chosen = p.normalize(p.absolute(directory));
      final known =
          acknowledged.map((value) => p.normalize(p.absolute(value))).toList();
      if (!known.any((value) => p.equals(value, chosen)) ||
          !await File(p.join(chosen, _databaseName)).exists()) {
        throw StateError(
            'The selected database is no longer available: $chosen');
      }
      await _validateDatabase(File(p.join(chosen, _databaseName)));
      if (await marker.exists()) {
        // Preserve even malformed data before the explicit user choice. If
        // copying fails, leave the original marker untouched.
        final backup =
            await supportDirectory.createTemp('database-location-backup-');
        await marker.copy(p.join(backup.path, _markerName));
      }
      await marker.writeAsString(
        jsonEncode({'version': 2, 'directory': chosen, 'acknowledged': known}),
        flush: true,
      );
    } finally {
      await lock.close();
    }
  }

  Future<void> _rejectNewerMarker(File marker) async {
    if (!await marker.exists()) return;
    Object? json;
    try {
      json = jsonDecode(await marker.readAsString());
    } on FormatException {
      return; // A damaged record is preserved before an explicit replacement.
    }
    if (json is Map && json['version'] is num && (json['version'] as num) > 2) {
      throw UnsupportedError(
          'Zapis lokalizacji utworzono nowszą wersją aplikacji. / The location was saved by a newer app version.');
    }
  }

  /// Check the selected file before replacing an existing location marker.
  /// SQLite reads include committed WAL data; this does not rewrite the DB.
  Future<void> _validateDatabase(File file) async {
    RandomAccessFile? input;
    Database? db;
    try {
      input = await file.open();
      final signature = await input.read(16);
      if (signature.length != 16 ||
          !const [
            83,
            81,
            76,
            105,
            116,
            101,
            32,
            102,
            111,
            114,
            109,
            97,
            116,
            32,
            51,
            0
          ]
              .asMap()
              .entries
              .every((entry) => signature[entry.key] == entry.value)) {
        throw const FormatException('Not a SQLite database');
      }
      await input.close();
      input = null;
      db = await databaseFactoryFfi.openDatabase(file.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final projects = await db.rawQuery('PRAGMA table_info(projects)');
      final segments = await db.rawQuery('PRAGMA table_info(segments)');
      final projectColumns = projects.map((row) => row['name']).toSet();
      final segmentColumns = segments.map((row) => row['name']).toSet();
      if (!projectColumns.containsAll(
            const ['id', 'diameter_mm', 'wall_thickness_mm'],
          ) ||
          !segmentColumns.containsAll(
            const ['id', 'project_id', 'seq_no', 'iso_mm', 'cut_mm'],
          )) {
        throw const _UnrecognizedDatabase();
      }
    } on _UnrecognizedDatabase {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Nie można odczytać wybranej bazy SQLite. Sprawdź plik i spróbuj ponownie. '
        '/ The selected SQLite database could not be read. Check the file and retry.',
      );
    } finally {
      await input?.close();
      await db?.close();
    }
  }

  Future<void> _validateOrRecover(
      String directory, List<String> candidates) async {
    try {
      await _validateDatabase(File(p.join(directory, _databaseName)));
    } catch (error) {
      throw DatabaseLocationProblem(
          candidates: candidates, reason: error.toString());
    }
  }

  Future<List<String>> _existingDirectories(
      Iterable<String> directories) async {
    final result = <String>[];
    for (final directory in directories) {
      final absolute = p.normalize(p.absolute(directory));
      if (result.any((candidate) => p.equals(candidate, absolute))) continue;
      if (await File(p.join(absolute, _databaseName)).exists()) {
        result.add(absolute);
      }
    }
    return result;
  }

  Future<String> _resolveLocked(Iterable<String> legacyDirectories) async {
    final marker = File(p.join(supportDirectory.path, _markerName));
    final stable =
        p.normalize(p.absolute(p.join(supportDirectory.path, 'databases')));
    String? selectedPreviously;
    List<String> acknowledged = const [];
    if (await marker.exists()) {
      try {
        final Object? json = jsonDecode(await marker.readAsString());
        if (json is Map &&
            json['version'] is num &&
            (json['version'] as num) > 2) {
          throw UnsupportedError(
              'Zapis lokalizacji utworzono nowszą wersją aplikacji. / The location was saved by a newer app version.');
        }
        if (json is! Map ||
            ![1, 2].contains(json['version']) ||
            json['directory'] is! String) {
          throw const FormatException('Invalid database location marker');
        }
        selectedPreviously = json['directory'] as String;
        if (!p.isAbsolute(selectedPreviously)) {
          throw const FormatException('Invalid database location marker');
        }
        if (json['version'] == 2) {
          final known = json['acknowledged'];
          if (known is! List ||
              known.any((value) => value is! String || !p.isAbsolute(value))) {
            throw const FormatException('Invalid database location marker');
          }
          acknowledged = known.cast<String>();
        }
      } on FormatException {
        final candidates =
            await _existingDirectories([stable, ...legacyDirectories]);
        throw DatabaseLocationProblem(
          candidates: candidates,
          reason:
              'Nie można odczytać zapisu lokalizacji bazy. Wybierz właściwy plik; poprzedni zapis zostanie zachowany. '
              '/ The saved database location cannot be read. Select the correct file; the previous record will be preserved.',
        );
      }
    }

    final candidates = await _existingDirectories([
      stable,
      if (selectedPreviously != null) selectedPreviously,
      ...acknowledged,
      ...legacyDirectories,
    ]);
    if (selectedPreviously != null &&
        !candidates
            .any((candidate) => p.equals(candidate, selectedPreviously!))) {
      throw DatabaseLocationProblem(
          candidates: candidates, missing: selectedPreviously);
    }
    if (candidates.length > 1 &&
        (selectedPreviously == null ||
            candidates.any((candidate) =>
                !acknowledged.any((known) => p.equals(known, candidate))))) {
      throw DatabaseLocationProblem(candidates: candidates);
    }
    if (selectedPreviously != null) {
      await _validateOrRecover(selectedPreviously, candidates);
      return selectedPreviously;
    }
    if (candidates.isEmpty) {
      return stable;
    }
    if (p.equals(candidates.single, stable)) {
      await _validateOrRecover(stable, candidates);
      return stable;
    }

    // Do not write a pointer to a database that has disappeared during the
    // scan. Existing database contents are never touched by the resolver.
    final selected = candidates.single;
    if (!await File(p.join(selected, _databaseName)).exists()) {
      throw StateError('The existing database is unavailable: $selected');
    }
    await _validateOrRecover(selected, candidates);
    await marker.writeAsString(
      jsonEncode({'version': 1, 'directory': selected}),
      flush: true,
    );
    return selected;
  }
}
