import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/audit/module_manifest.dart';

final _screenClass =
    RegExp(r'^class ([A-Z][A-Za-z0-9]+Screen)\b', multiLine: true);

Set<String> discoverPublicScreens(Directory root) {
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) {
        final path = file.path.replaceAll('\\', '/');
        return (path.startsWith('lib/screens/') &&
                path.endsWith('_screen.dart')) ||
            (path.contains('/modules/') &&
                path.contains('/ui/') &&
                path.endsWith('_screen.dart'));
      })
      .expand((file) => _screenClass
          .allMatches(file.readAsStringSync())
          .map((match) => match.group(1)!))
      .toSet();
}

void main() {
  test('każdy publiczny ekran ma dokładnie jeden wpis audytu', () {
    final discovered = discoverPublicScreens(Directory('lib'));
    final entryPoints =
        moduleManifest.map((entry) => entry.entryPoint).toList();
    final declared = entryPoints.toSet();

    expect(declared, discovered);
    expect(declared.length, entryPoints.length);
  });

  test('manifest odrzuca powtórzone identyfikatory oraz puste pola', () {
    expect(moduleManifest.map((entry) => entry.id).toSet().length,
        moduleManifest.length);
    expect(moduleManifest.where((entry) => entry.sourcePath.isEmpty), isEmpty);
    expect(moduleManifest.where((entry) => entry.scenario.isEmpty), isEmpty);
  });

  test('zaliczony status wskazuje dowód', () {
    final invalid = moduleManifest.where(
      (entry) => entry.status == AuditStatus.passed && entry.evidence.isEmpty,
    );

    expect(invalid, isEmpty);
  });
}
