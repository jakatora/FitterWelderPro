/// Where heat / MTR certificate photos live, and how a picked one gets there.
///
/// FilePicker hands back a path in its own cache (wiped by "clear cache") or,
/// on some Android versions, straight into the user's gallery. A heat number
/// whose photo is only a reference to such a file loses its evidence the day
/// the cache is cleared, and was never included in a backup: the backup
/// carries `<documents>/heat_photos` (see `data_backup.dart`). So every
/// picked photo is COPIED into that folder and the copy's path is what the
/// database stores — the same rule `heat_photos_screen.dart` already follows.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Tests only: a folder used instead of `<documents>/heat_photos`, so screen
/// tests can save a photo without the path_provider plugin.
@visibleForTesting
Directory? debugHeatPhotosDirectoryOverride;

/// `<documents>/heat_photos` — the one folder the backup archives.
Future<Directory> heatPhotosDirectory() async =>
    debugHeatPhotosDirectoryOverride ??
    Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'heat_photos'),
    );

/// Copies [sourcePath] into [heatPhotosDir] (default: [heatPhotosDirectory])
/// under a fresh UUID name, keeping the extension, and returns the new path.
///
/// A file that is already inside the folder is returned unchanged rather
/// than duplicated. Throws [FileSystemException] when the source cannot be
/// read or the copy cannot be written — the caller decides what to tell the
/// user; nothing is recorded half-way here.
Future<String> persistPickedHeatPhoto(
  String sourcePath, {
  Directory? heatPhotosDir,
}) async {
  final dir = heatPhotosDir ?? await heatPhotosDirectory();
  if (p.isWithin(p.normalize(dir.path), p.normalize(sourcePath))) {
    return sourcePath;
  }
  final source = File(sourcePath);
  if (!await source.exists()) {
    throw FileSystemException('Picked photo does not exist', sourcePath);
  }
  if (!await dir.exists()) await dir.create(recursive: true);
  final ext = p.extension(sourcePath);
  final name = '${const Uuid().v4()}${ext.isEmpty ? '.jpg' : ext}';
  final copy = await source.copy(p.join(dir.path, name));
  return copy.path;
}
