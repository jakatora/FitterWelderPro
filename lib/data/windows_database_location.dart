import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_location_problem.dart';

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
      final chosen = p.normalize(p.absolute(directory));
      final known =
          acknowledged.map((value) => p.normalize(p.absolute(value))).toList();
      if (!known.any((value) => p.equals(value, chosen)) ||
          !await File(p.join(chosen, _databaseName)).exists()) {
        throw StateError(
            'The selected database is no longer available: $chosen');
      }
      await _validateDatabase(File(p.join(chosen, _databaseName)));
      await File(p.join(supportDirectory.path, _markerName)).writeAsString(
        jsonEncode({'version': 2, 'directory': chosen, 'acknowledged': known}),
        flush: true,
      );
    } finally {
      await lock.close();
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
      await db.rawQuery('SELECT name FROM sqlite_master LIMIT 1');
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

  Future<String> _resolveLocked(Iterable<String> legacyDirectories) async {
    final marker = File(p.join(supportDirectory.path, _markerName));
    final stable =
        p.normalize(p.absolute(p.join(supportDirectory.path, 'databases')));
    String? selectedPreviously;
    List<String> acknowledged = const [];
    if (await marker.exists()) {
      final Object? json = jsonDecode(await marker.readAsString());
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
    }

    final candidates = <String>[];
    for (final directory in [
      stable,
      if (selectedPreviously != null) selectedPreviously,
      ...acknowledged,
      ...legacyDirectories,
    ]) {
      final absolute = p.normalize(p.absolute(directory));
      if (candidates.any((candidate) => p.equals(candidate, absolute))) {
        continue;
      }
      if (await File(p.join(absolute, _databaseName)).exists()) {
        candidates.add(absolute);
      }
    }
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
    if (selectedPreviously != null) return selectedPreviously;
    if (candidates.isEmpty || p.equals(candidates.single, stable)) {
      return stable;
    }

    // Do not write a pointer to a database that has disappeared during the
    // scan. Existing database contents are never touched by the resolver.
    final selected = candidates.single;
    if (!await File(p.join(selected, _databaseName)).exists()) {
      throw StateError('The existing database is unavailable: $selected');
    }
    await marker.writeAsString(
      jsonEncode({'version': 1, 'directory': selected}),
      flush: true,
    );
    return selected;
  }
}
