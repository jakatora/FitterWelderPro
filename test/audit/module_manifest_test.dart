import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/audit/module_manifest.dart';
import '../../tool/audit/render_audit_report.dart';

final _screenClass =
    RegExp(r'^class ([A-Z][A-Za-z0-9]+Screen)\b', multiLine: true);

/// Strony modułów w lib/features (rejestr uprawnień, Biblioteka WPS).
final _pageClass =
    RegExp(r'^class ([A-Z][A-Za-z0-9]+Page)\b', multiLine: true);

Set<String> discoverPublicScreens(Directory root) {
  final files = root.listSync(recursive: true).whereType<File>();
  final screens = files
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
          .map((match) => match.group(1)!));
  final pages = files
      .where((file) {
        final path = file.path.replaceAll('\\', '/');
        return path.startsWith('lib/features/') && path.endsWith('_page.dart');
      })
      .expand((file) => _pageClass
          .allMatches(file.readAsStringSync())
          .map((match) => match.group(1)!));
  return {...screens, ...pages};
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

  group('raport częściowy', () {
    test('zapisany raport odpowiada bieżącemu manifestowi i rendererowi', () {
      final file = File('docs/audits/2026-08-30-module-audit.md');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync().replaceAll('\r\n', '\n'),
          renderAuditReport(moduleManifest));
      expect(renderAuditReport(moduleManifest), isNot(endsWith('\n\n')));
    });

    test('kolejka oddziela pilność weryfikacji według ryzyka', () {
      final markdown = renderAuditReport(moduleManifest);
      final p0 =
          markdown.split('### P0 — weryfikacja').last.split('### P1').first;
      final p1 =
          markdown.split('### P1 — weryfikacja').last.split('### P2').first;
      final p2 =
          markdown.split('### P2 — weryfikacja').last.split('### P3').first;
      final p3 = markdown
          .split('### P3 — weryfikacja')
          .last
          .split('### Rozstrzygnięcia')
          .first;
      expect(p0, contains('- [unverified] `bolt-torque`:'));
      expect(p0, contains('- [unverified] `iso-scanner`:'));
      expect(p1, contains('- [unverified] `ai-chat`:'));
      expect(p2, contains('- [unverified] `chat`:'));
      expect(p3, contains('- [unverified] `fitter-menu`:'));
    });

    test('nie pomija ani nie powiela wpisów i zachowuje wszystkie pola', () {
      final markdown = renderAuditReport(moduleManifest);
      final rows = markdown.split('\n').where((line) => line.startsWith('| `'));
      expect(rows.length, 85);
      for (final entry in moduleManifest) {
        final row =
            rows.singleWhere((line) => line.startsWith('| `${entry.id}` |'));
        expect(row, contains(entry.entryPoint));
        expect(row, contains(entry.sourcePath));
        expect(row, contains(entry.category.name));
        expect(row, contains(entry.risk.name));
        expect(row, contains(entry.status.name));
        expect(row, contains(entry.scenario));
        if (entry.evidence.isEmpty) {
          expect(row, contains('Brak dowodu scenariusza'));
        } else {
          for (final evidence in entry.evidence) {
            expect(row, contains(evidence));
          }
        }
      }
    });

    test(
        'podaje dokładne liczby i jawnie wymienia niezweryfikowane scenariusze',
        () {
      final markdown = renderAuditReport(moduleManifest);
      expect(markdown, contains('Moduły: 85'));
      expect(markdown, contains('| passed | 37 |'));
      expect(markdown, contains('| unverified | 47 |'));
      expect(markdown, contains('| domainReview | 1 |'));
      expect(markdown, contains('| broken | 0 |'));
      expect(markdown, contains('| simplify | 0 |'));
      final queued = markdown
          .split('\n')
          .where((line) => line.startsWith('- [unverified]'));
      expect(queued.length, 47);
      for (final entry
          in moduleManifest.where((e) => e.status == AuditStatus.unverified)) {
        expect(
            queued.where(
                (line) => line.startsWith('- [unverified] `${entry.id}`:')),
            hasLength(1));
      }
      expect(markdown, contains('AUDYT CZĘŚCIOWY'));
      expect(markdown, contains('Pełny audyt pozostaje nieukończony'));
      expect(markdown, isNot(contains('Pełny audyt zakończony')));
    });

    test('liczy dostarczony zakres zamiast drukować stałe wyniki audytu', () {
      final markdown = renderAuditReport([moduleManifest.first]);
      expect(markdown, contains('Moduły: 1'));
      expect(markdown, contains('| passed | 0 |'));
      expect(markdown, contains('| unverified | 1 |'));
      expect(markdown, contains('| domainReview | 0 |'));
      expect(markdown.split('\n').where((line) => line.startsWith('| `')),
          hasLength(1));
    });

    test('chroni strukturę tabeli przed separatorem i nową linią w danych', () {
      final markdown = renderAuditReport(const [
        ModuleAuditEntry(
          id: 'fixture',
          entryPoint: 'FixtureScreen',
          sourcePath: 'fixture.dart',
          category: AuditCategory.document,
          risk: AuditRisk.low,
          status: AuditStatus.unverified,
          scenario: 'A | B\nC',
          evidence: ['test | fixture\nresult'],
        )
      ]);
      final row = markdown
          .split('\n')
          .singleWhere((line) => line.startsWith('| `fixture` |'));
      expect(row, contains('A &#124; B<br>C'));
      expect(row, contains('test &#124; fixture<br>result'));
    });
  });
}
