// Dziennik spoin → ograniczenia z próby ISO 9606-1: co dziennik już ma
// (OD → rura, oznaczenie spoiwa → grupa FM, typ złącza BR → odgałęzienie),
// a czego nie (prowadzenie grani, przenoszenie metalu) i jak to działa
// z certyfikatem zapisanym przez „Zakres uprawnień z próbki”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/iso9606_limits.dart';
import 'package:cut_list_app/domain/qualification/iso9606_range.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/weld_journal/weld_compliance.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/wps/weld_range_check.dart';

WeldEntry _entry({
  String od = '60,3',
  String t = '4',
  String filler = 'ER70S-6',
  String joint = 'BW',
  String method = 'TIG',
  String position = 'PH',
}) =>
    WeldEntry(
      id: 'w1',
      weldNo: 'W-1',
      projectName: 'P',
      pipeName: 'L-1',
      material: '',
      od: od,
      t: t,
      method: method,
      welder: '',
      date: '2026-10-10',
      notes: '',
      status: WeldStatus.ok,
      jointType: joint,
      position: position,
      fillerClass: filler,
    );

/// Certyfikat zapisany z próbki (jak „Zapisz jako uprawnienie”), z datą
/// egzaminu, żeby był ważny w dniu spoiny.
WelderCertificate _certFrom(Iso9606Sample s) {
  final range = evaluateIso9606(s).range!;
  return iso9606CertificateDraft(range, en: false)
      .certificate!
      .copyWith(testDate: DateTime(2026, 9, 1), expiryDate: DateTime(2029, 9, 1));
}

const _pipe141 = Iso9606Sample(
  product: Iso9606Product.pipe,
  first: Iso9606ProcessInput(
      process: Iso9606Process.p141,
      filler: Iso9606Filler.solid,
      thicknessMm: 3),
  fm: Iso9606FmGroup.fm1,
  parentGroup: '1.1',
  diameterMm: 60.3,
  position: Iso6947Position.ph,
  backing: Iso9606Backing.ssNb,
);

WeldCompliance _assess(WeldEntry e, WelderCertificate c) =>
    assessWeldCompliance(
      entry: e,
      wpsLibrary: const [],
      certificates: [c],
      today: DateTime(2026, 10, 17),
    );

void main() {
  test('weldParametersOf: rura z OD, FM z oznaczenia spoiwa, BR; grań '
      'i przenoszenie „nie podano” → puste', () {
    final p = weldParametersOf(
        _entry(filler: 'ER316LSi', joint: 'BR', od: '60,3'));
    expect(p.productForm, WeldProductForm.pipe);
    expect(p.fillerGroup, 'FM5');
    expect(p.branch, isTrue);
    expect(p.root, isNull);
    expect(p.dipTransfer, isNull);
    // Puste OD ≠ blacha; nazwa handlowa ≠ grupa; brak typu złącza ≠ BW.
    final q = weldParametersOf(_entry(od: '', filler: 'OK 48.00', joint: ''));
    expect(q.productForm, isNull);
    expect(q.fillerGroup, isNull);
    expect(q.branch, isNull);
    expect(branchOfWeld('SW'), isFalse);
    expect(productFormOfWeld('0'), isNull);
  });

  test('certyfikat z próbki: spoiwo nierdzewne przy FM1 → nieobjęta, '
      'z powodem w ostrzeżeniu', () {
    final c = _certFrom(_pipe141);
    expect(parseIso9606Limits(c.notes).status, Iso9606LimitsStatus.ok);
    final bad = _assess(_entry(filler: 'ER316LSi'), c);
    expect(bad.welderNotQualified, isTrue);
    final lines = bad.warningLines(en: false).join('\n');
    expect(lines, contains('Grupa spoiwa: FM5 — poza zakresem (FM1, FM2).'));
    expect(lines, contains('ISO 9606-1 tab. 3'));
  });

  test('to samo spoiwo FM1 → objęta (grań: tylko „nie da się porównać”)', () {
    final c = _certFrom(_pipe141);
    final ok = _assess(_entry(filler: 'ER70S-6'), c);
    expect(ok.welderNotQualified, isFalse);
    final issues = ok.welders.single.coverage.certificates.single.issues;
    final unknown =
        issues.singleWhere((i) => i.field == WeldCheckField.testLimits);
    expect(unknown.severity, RangeIssueSeverity.cannotCompare);
    expect(unknown.actual, 'root');
  });

  test('próba na blasze → odgałęzienie (BR) poza zakresem', () {
    final c = _certFrom(const Iso9606Sample(
      first: Iso9606ProcessInput(
          process: Iso9606Process.p135,
          filler: Iso9606Filler.solid,
          transfer: Iso9606Transfer.dip,
          thicknessMm: 8),
      fm: Iso9606FmGroup.fm1,
      position: Iso6947Position.pa,
      backing: Iso9606Backing.ssMb,
    ));
    final br = _assess(
        _entry(od: '', t: '6', method: 'MIG/MAG', position: 'PA', joint: 'BR'),
        c);
    expect(br.welderNotQualified, isTrue);
    expect(br.warningLines(en: false).join('\n'),
        contains('Odgałęzienie: BR — poza zakresem (branch=0).'));
    final bw = _assess(
        _entry(od: '', t: '6', method: 'MIG/MAG', position: 'PA', joint: 'BW'),
        c);
    expect(bw.welderNotQualified, isFalse);
  });

  // ── v28: grań, przenoszenie metalu i wyrób z karty spoiny ──────────────

  group('v28 — szczegóły do kontroli uprawnień', () {
    /// Certyfikat z ręcznie wpisaną linią ograniczeń, bez innych zawężeń
    /// zakresu (procesy 141 i 135, wszystkie pozycje), ważny w dniu spoiny.
    WelderCertificate limitsCert(String line) => WelderCertificate(
          id: 'c-lim',
          standard: QualificationStandard.iso9606_1,
          certNo: 'LIM-1',
          testDate: DateTime(2026, 9, 1),
          expiryDate: DateTime(2029, 9, 1),
          processes: '141, 135',
          positions: 'wszystkie',
          notes: 'Uwagi egzaminatora\n$line',
          createdAt: 0,
          updatedAt: 0,
        );

    List<RangeIssue> issuesOf(WeldCompliance c) =>
        c.welders.single.coverage.certificates.single.issues;

    test('weldParametersOf bierze grań, przenoszenie i wyrób z wpisu; '
        'wybrany wyrób wygrywa z OD', () {
      final p = weldParametersOf(_entry(method: 'MIG/MAG').copyWith(
        rootBacking: WeldRootBacking.nb,
        metalTransfer: WeldMetalTransfer.dip,
        productForm: WeldProductKind.plate,
      ));
      expect(p.root, RootCondition.nb);
      expect(p.dipTransfer, isTrue);
      expect(p.productForm, WeldProductForm.plate,
          reason: 'jawny wybór „blacha” mimo wpisanego OD');
      final q = weldParametersOf(_entry(od: '').copyWith(
          metalTransfer: WeldMetalTransfer.other,
          productForm: WeldProductKind.pipe));
      expect(q.dipTransfer, isFalse);
      expect(q.productForm, WeldProductForm.pipe);
      expect(rootConditionOfWeld('ss mb'), RootCondition.mb);
      expect(rootConditionOfWeld('xx'), isNull);
      expect(dipTransferOfWeld(''), isNull);
      expect(productFormOfWeld('', form: 'p'), WeldProductForm.plate);
    });

    test('spoina ss nb przy uprawnieniu root=mb,bs → poza zakresem z powodem',
        () {
      final c = limitsCert('[ISO9606 v1] root=mb,bs');
      final res = _assess(
          _entry().copyWith(rootBacking: WeldRootBacking.nb), c);
      expect(res.welderNotQualified, isTrue);
      final issue = issuesOf(res)
          .singleWhere((i) => i.field == WeldCheckField.rootBacking);
      expect(issue.severity, RangeIssueSeverity.outOfRange);
      expect(issue.actual, 'ss nb');
      expect(issue.allowed, 'ss mb, bs');
      final lines = res.warningLines(en: false).join('\n');
      expect(lines,
          contains('Prowadzenie grani: ss nb — poza zakresem (ss mb, bs).'));
      expect(lines, contains('ISO 9606-1 tab. 11'));
      expect(res.warningLines(en: true).join('\n'),
          contains('Root / backing: ss nb — out of range (ss mb, bs).'));

      // Ta sama spoina z granią na podkładce — objęta, bez „nie da się”.
      final ok =
          _assess(_entry().copyWith(rootBacking: WeldRootBacking.mb), c);
      expect(ok.welderNotQualified, isFalse);
      expect(issuesOf(ok), isEmpty);
    });

    test('„nie podano” → nie da się porównać, nigdy poza zakresem', () {
      final c = limitsCert('[ISO9606 v1] root=mb,bs; dip=0; plates=0');
      final res = _assess(
          _entry(od: '', method: 'MIG/MAG', position: 'PA'), c);
      expect(res.welderNotQualified, isFalse);
      final issues = issuesOf(res);
      expect(issues.where((i) => i.severity == RangeIssueSeverity.outOfRange),
          isEmpty);
      final unknown =
          issues.singleWhere((i) => i.field == WeldCheckField.testLimits);
      expect(unknown.severity, RangeIssueSeverity.cannotCompare);
      expect(unknown.actual, 'root, dip, P/T');
    });

    test('plates=0 i wyrób blacha → poza zakresem; rura → objęta', () {
      final c = limitsCert('[ISO9606 v1] plates=0');
      final plate = _assess(
          _entry(od: '').copyWith(productForm: WeldProductKind.plate), c);
      expect(plate.welderNotQualified, isTrue);
      final issue = issuesOf(plate)
          .singleWhere((i) => i.field == WeldCheckField.productForm);
      expect(issue.severity, RangeIssueSeverity.outOfRange);
      expect(plate.warningLines(en: false).join('\n'),
          contains('Wyrób (P blacha / T rura): P — poza zakresem (T).'));

      final pipe = _assess(
          _entry(od: '').copyWith(productForm: WeldProductKind.pipe), c);
      expect(pipe.welderNotQualified, isFalse);
      expect(issuesOf(pipe), isEmpty);
    });

    test('dip=0: MIG/MAG zwarciowe → poza zakresem; inne → objęta; TIG — '
        'przenoszenie nie dotyczy', () {
      final c = limitsCert('[ISO9606 v1] dip=0');
      final dip = _assess(
          _entry(method: 'MIG/MAG')
              .copyWith(metalTransfer: WeldMetalTransfer.dip),
          c);
      expect(dip.welderNotQualified, isTrue);
      expect(
          issuesOf(dip).single.field, WeldCheckField.metalTransfer);
      final other = _assess(
          _entry(method: 'MIG/MAG')
              .copyWith(metalTransfer: WeldMetalTransfer.other),
          c);
      expect(other.welderNotQualified, isFalse);
      expect(issuesOf(other), isEmpty);
      final tig = _assess(_entry(method: 'TIG'), c);
      expect(issuesOf(tig), isEmpty);
    });
  });
}
