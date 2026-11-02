import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

  Future<String> _resolveLocked(Iterable<String> legacyDirectories) async {
    final marker = File(p.join(supportDirectory.path, _markerName));
    final stable =
        p.normalize(p.absolute(p.join(supportDirectory.path, 'databases')));
    String? selectedPreviously;
    if (await marker.exists()) {
      final Object? json = jsonDecode(await marker.readAsString());
      if (json is! Map ||
          json['version'] != 1 ||
          json['directory'] is! String) {
        throw const FormatException('Invalid database location marker');
      }
      selectedPreviously = json['directory'] as String;
      if (!p.isAbsolute(selectedPreviously) ||
          !await File(p.join(selectedPreviously, _databaseName)).exists()) {
        throw StateError(
            'The previously selected database is unavailable: $selectedPreviously');
      }
    }

    final candidates = <String>[];
    for (final directory in [
      stable,
      if (selectedPreviously != null) selectedPreviously,
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
    if (candidates.length > 1) {
      throw StateError(
          'Multiple existing databases found: ${candidates.join(' | ')}');
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
