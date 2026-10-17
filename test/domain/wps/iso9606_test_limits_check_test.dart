// Kontrola spoiny z ograniczeniami z próby ISO 9606-1 zapisanymi w uwagach
// certyfikatu (`[ISO9606 v1] …`): każde ograniczenie naruszone → „poza
// zakresem” z powodem, spełnione → OK, brak danych spoiny → „nie da się
// porównać”; brak linii → nic; linia uszkodzona → „nie da się porównać”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/iso9606_limits.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/wps/weld_range_check.dart';

List<RangeIssue> _check(WeldParameters w, String notes) {
  final out = <RangeIssue>[];
  checkIso9606TestLimits(w, notes, out);
  return out;
}

List<WeldCheckField> _out(List<RangeIssue> i) => [
      for (final x in i)
        if (x.severity == RangeIssueSeverity.outOfRange) x.field,
    ];

RangeIssue? _unknown(List<RangeIssue> i) {
  for (final x in i) {
    if (x.field == WeldCheckField.testLimits) return x;
  }
  return null;
}

void main() {
  group('każde ograniczenie: naruszone / spełnione / brak danych', () {
    test('root (tab. 11): ss nb przy root=mb,bs → poza zakresem z powodem', () {
      const line = '[ISO9606 v1] root=mb,bs';
      final bad = _check(
          const WeldParameters(root: RootCondition.nb), line);
      expect(_out(bad), [WeldCheckField.rootBacking]);
      expect(bad.single.messagePl,
          'Prowadzenie grani: ss nb — poza zakresem (ss mb, bs). Takie '
          'prowadzenie grani obejmuje próba (ISO 9606-1 tab. 11).');
      expect(bad.single.messageEn, contains('out of range (ss mb, bs)'));
      expect(_check(const WeldParameters(root: RootCondition.bs), line),
          isEmpty);
      final none = _check(const WeldParameters(), line);
      expect(_out(none), isEmpty);
      expect(_unknown(none)!.severity, RangeIssueSeverity.cannotCompare);
      expect(_unknown(none)!.actual, 'root');
      expect(_unknown(none)!.allowed, 'root=mb,bs');
      // Spoina pachwinowa — grań nie dotyczy.
      expect(
          _check(const WeldParameters(jointKind: WeldJointKind.fw), line),
          isEmpty);
      // Wszystkie sposoby dozwolone — brak ograniczenia.
      expect(
          _check(const WeldParameters(),
              '[ISO9606 v1] root=nb,mb,bs,gb,ci,fb'),
          isEmpty);
    });

    test('dip (§5.2): zwarciowe przy dip=0 → poza zakresem; tylko MIG/MAG', () {
      const line = '[ISO9606 v1] dip=0';
      final bad = _check(
          const WeldParameters(process: '135', dipTransfer: true), line);
      expect(_out(bad), [WeldCheckField.metalTransfer]);
      expect(bad.single.messagePl, contains('ISO 9606-1 §5.2'));
      expect(
          _check(const WeldParameters(process: 'MIG/MAG', dipTransfer: false),
              line),
          isEmpty);
      expect(_unknown(_check(const WeldParameters(process: '135'), line))!
          .actual, 'dip');
      // Proces nieznany — może być MIG/MAG, więc „nie da się porównać”.
      expect(_unknown(_check(const WeldParameters(), line)), isNotNull);
      // TIG — przenoszenie nie dotyczy.
      expect(_check(const WeldParameters(process: 'TIG'), line), isEmpty);
      // dip=1 — brak ograniczenia.
      expect(
          _check(const WeldParameters(process: '135', dipTransfer: true),
              '[ISO9606 v1] dip=1'),
          isEmpty);
    });

    test('plates (§5.3 a): blacha przy plates=0 → poza zakresem', () {
      const line = '[ISO9606 v1] plates=0';
      final bad = _check(
          const WeldParameters(productForm: WeldProductForm.plate), line);
      expect(_out(bad), [WeldCheckField.productForm]);
      expect(bad.single.messagePl,
          'Wyrób (P blacha / T rura): P — poza zakresem (T). Próba na rurze '
          'D ≤ 25 mm nie obejmuje blach (ISO 9606-1 §5.3 a).');
      expect(
          _check(const WeldParameters(productForm: WeldProductForm.pipe),
              line),
          isEmpty);
      expect(_unknown(_check(const WeldParameters(), line))!.actual, 'P/T');
      expect(
          _check(const WeldParameters(productForm: WeldProductForm.plate),
              '[ISO9606 v1] plates=1'),
          isEmpty);
    });

    test('fm (tab. 3): FM5 przy fm=FM1,FM2 → poza zakresem', () {
      const line = '[ISO9606 v1] fm=FM1,FM2';
      final bad = _check(const WeldParameters(fillerGroup: 'FM5'), line);
      expect(_out(bad), [WeldCheckField.fillerGroup]);
      expect(bad.single.messagePl,
          'Grupa spoiwa: FM5 — poza zakresem (FM1, FM2). Grupy spoiw objęte '
          'próbą (ISO 9606-1 tab. 3).');
      expect(_check(const WeldParameters(fillerGroup: 'fm2'), line), isEmpty);
      expect(_unknown(_check(const WeldParameters(), line))!.allowed,
          'fm=FM1,FM2');
    });

    test('branch (§5.4): odgałęzienie przy branch=0 → poza zakresem; '
        'przy 60 kąt nieznany', () {
      final bad = _check(const WeldParameters(branch: true),
          '[ISO9606 v1] branch=0');
      expect(_out(bad), [WeldCheckField.branch]);
      expect(bad.single.messagePl, contains('§5.4 a, c'));
      expect(_check(const WeldParameters(branch: false),
          '[ISO9606 v1] branch=0'), isEmpty);
      final angle = _check(const WeldParameters(branch: true),
          '[ISO9606 v1] branch=60');
      expect(_out(angle), isEmpty);
      expect(_unknown(angle)!.actual, 'BR ≥ 60°');
      expect(_unknown(_check(const WeldParameters(),
          '[ISO9606 v1] branch=60'))!.actual, 'BR');
    });

    test('layers / dir — spoina nie ma tych pól: „nie da się porównać” '
        'tylko gdy dotyczą', () {
      expect(_unknown(_check(
              const WeldParameters(jointKind: WeldJointKind.fw),
              '[ISO9606 v1] layers=sl'))!
          .actual, 'sl/ml');
      expect(
          _check(const WeldParameters(jointKind: WeldJointKind.bw),
              '[ISO9606 v1] layers=sl'),
          isEmpty);
      expect(
          _check(const WeldParameters(jointKind: WeldJointKind.fw),
              '[ISO9606 v1] layers=sl,ml'),
          isEmpty);
      expect(_unknown(_check(const WeldParameters(process: '311'),
          '[ISO9606 v1] dir=lw'))!.actual, 'lw/rw');
      expect(_check(const WeldParameters(process: '141'),
          '[ISO9606 v1] dir=lw'), isEmpty);
    });

    test('kilka braków → JEDNO zbiorcze „nie da się porównać”', () {
      final i = _check(const WeldParameters(process: '135'),
          '[ISO9606 v1] root=mb,bs; dip=0; plates=0; fm=FM1,FM2; branch=60');
      expect(i, hasLength(1));
      expect(i.single.actual, 'root, dip, P/T, FM, BR');
      expect(i.single.allowed,
          'root=mb,bs; dip=0; plates=0; fm=FM1,FM2; branch=60');
      expect(i.single.messagePl, contains('sprawdź z blokiem OGRANICZENIA'));
    });

    test('nofiller i proc2 nie są tu porównywane (pilnuje ich proces)', () {
      expect(
          _check(const WeldParameters(process: '111', materialGroup: '8.1'),
              '[ISO9606 v1] nofiller=1.1; proc2=111'),
          isEmpty);
    });
  });

  group('linia w uwagach', () {
    test('brak linii → żadnych ograniczeń (certyfikat ręczny)', () {
      expect(
          _check(const WeldParameters(root: RootCondition.nb),
              'UDT Gliwice, egzamin 2026'),
          isEmpty);
    });

    test('uszkodzona albo nowsza wersja → „nie da się porównać”, nie '
        '„poza zakresem”', () {
      for (final notes in [
        '[ISO9606 v1] fm=FM9',
        '[ISO9606 v2] fm=FM1',
        '[ISO9606 v1] fm=FM1\n[ISO9606 v1] fm=FM5',
      ]) {
        final i = _check(
            const WeldParameters(fillerGroup: 'FM5', root: RootCondition.nb),
            notes);
        expect(i, hasLength(1), reason: notes);
        expect(i.single.field, WeldCheckField.testLimits);
        expect(i.single.severity, RangeIssueSeverity.cannotCompare);
        expect(i.single.messagePl, contains('uszkodzona'));
      }
    });
  });

  group('checkWelderCoverage', () {
    WelderCertificate cert(String notes) => WelderCertificate(
          id: 'c',
          standard: QualificationStandard.iso9606_1,
          // Egzamin 1,5 mies. przed spoiną — ważny, w terminie ciągłości.
          testDate: DateTime(2026, 9, 1),
          expiryDate: DateTime(2029, 9, 1),
          processes: '135, 138',
          positions: 'PA, PC',
          jointKinds: const {WeldJointKind.bw},
          notes: notes,
          createdAt: 0,
          updatedAt: 0,
        );

    WelderCoverage cover(WeldParameters w, String notes) =>
        checkWelderCoverage(
            weld: w,
            weldDate: DateTime(2026, 10, 17),
            certificates: [cert(notes)]);

    const notes = 'OGRANICZENIA z próby …\n'
        '• grań: tylko ss mb, bs\n'
        '[ISO9606 v1] root=mb,bs; dip=0; plates=0; fm=FM1,FM2; branch=60\n'
        '\nZakres z próbki…';

    test('naruszone ograniczenie → spoina nieobjęta, z powodem', () {
      final c = cover(
          const WeldParameters(
              process: '135',
              position: 'PA',
              jointKind: WeldJointKind.bw,
              root: RootCondition.mb,
              dipTransfer: false,
              productForm: WeldProductForm.pipe,
              fillerGroup: 'FM5',
              branch: false),
          notes);
      expect(c.covered, isFalse);
      final issue = c.certificates.single.issues
          .singleWhere((i) => i.field == WeldCheckField.fillerGroup);
      expect(issue.messagePl, contains('FM5 — poza zakresem (FM1, FM2)'));
    });

    test('wszystko spełnione → objęta, bez uwag', () {
      final c = cover(
          const WeldParameters(
              process: '135',
              position: 'PA',
              jointKind: WeldJointKind.bw,
              root: RootCondition.mb,
              dipTransfer: false,
              productForm: WeldProductForm.pipe,
              fillerGroup: 'FM2',
              branch: false),
          notes);
      expect(c.covered, isTrue);
      expect(
          c.certificates.single.issues
              .where((i) => i.field == WeldCheckField.testLimits),
          isEmpty);
    });

    test('brak danych → objęta, ale z „nie da się porównać”', () {
      final c = cover(
          const WeldParameters(
              process: '135', position: 'PA', jointKind: WeldJointKind.bw),
          notes);
      expect(c.covered, isTrue);
      final unknown = c.certificates.single.issues
          .singleWhere((i) => i.field == WeldCheckField.testLimits);
      expect(unknown.severity, RangeIssueSeverity.cannotCompare);
    });

    test('certyfikat bez linii (ręczny) — jak dotąd, bez nowych uwag', () {
      final c = cover(
          const WeldParameters(
              process: '135',
              position: 'PA',
              root: RootCondition.nb,
              fillerGroup: 'FM5'),
          'Egzamin UDT');
      expect(c.covered, isTrue);
      expect(c.certificates.single.issues
          .where((i) => i.field == WeldCheckField.testLimits ||
              i.field == WeldCheckField.fillerGroup ||
              i.field == WeldCheckField.rootBacking), isEmpty);
    });
  });
}
