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
  test('weldParametersOf: rura z OD, FM z oznaczenia spoiwa, BR; grani '
      'i przenoszenia dziennik nie zna', () {
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
}
