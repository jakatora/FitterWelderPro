import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cut_list_app/services/heat_photo_storage.dart';

void main() {
  late Directory sandbox;
  late Directory heatDir;
  late File picked;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fwp_heat_photo_');
    heatDir = Directory(p.join(sandbox.path, 'documents', 'heat_photos'));
    final cache = Directory(p.join(sandbox.path, 'cache', 'file_picker'));
    await cache.create(recursive: true);
    picked = File(p.join(cache.path, 'IMG_0001.JPG'));
    await picked.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0x10, 0x20]);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('kopiuje wybrane zdjęcie do heat_photos i zwraca nową ścieżkę', () async {
    final stored = await persistPickedHeatPhoto(picked.path, heatPhotosDir: heatDir);

    expect(p.isWithin(heatDir.path, stored), isTrue);
    expect(p.extension(stored), '.JPG');
    expect(await File(stored).readAsBytes(), <int>[0xFF, 0xD8, 0xFF, 0x10, 0x20]);
    // The picker's copy is not ours to move or delete.
    expect(await picked.exists(), isTrue);
  });

  test('dwa wybory tego samego pliku to dwie osobne kopie', () async {
    final a = await persistPickedHeatPhoto(picked.path, heatPhotosDir: heatDir);
    final b = await persistPickedHeatPhoto(picked.path, heatPhotosDir: heatDir);
    expect(a, isNot(b));
    expect(await File(a).exists(), isTrue);
    expect(await File(b).exists(), isTrue);
  });

  test('plik, który już jest w heat_photos, nie jest kopiowany drugi raz', () async {
    await heatDir.create(recursive: true);
    final owned = File(p.join(heatDir.path, 'already-here.jpg'));
    await owned.writeAsBytes(<int>[1, 2, 3]);

    expect(await persistPickedHeatPhoto(owned.path, heatPhotosDir: heatDir), owned.path);
    expect(heatDir.listSync(), hasLength(1));
  });

  test('brak rozszerzenia dostaje .jpg', () async {
    final bare = File(p.join(sandbox.path, 'cache', 'blob'));
    await bare.writeAsBytes(<int>[9]);
    final stored = await persistPickedHeatPhoto(bare.path, heatPhotosDir: heatDir);
    expect(p.extension(stored), '.jpg');
  });

  test('nieistniejący plik źródłowy to błąd, nie cichy pusty wpis', () async {
    await expectLater(
      persistPickedHeatPhoto(p.join(sandbox.path, 'nope.jpg'), heatPhotosDir: heatDir),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('ekran komponentów zapisuje kopię, nie ścieżkę z pickera', () {
    // FilePicker cannot be driven from a widget test; this pins the wiring.
    final source =
        File('lib/screens/project_components_screen.dart').readAsStringSync();
    expect(source, contains('persistPickedHeatPhoto('));
    expect(source, isNot(contains("'image_path': imgPath")));
  });
}
