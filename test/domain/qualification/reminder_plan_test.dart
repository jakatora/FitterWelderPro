// Logika harmonogramu przypomnień — które i kiedy — bez wołania platformy.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/certificate_status.dart';
import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';

CertificateEvaluation _eval({
  String id = 'c1',
  QualificationStandard standard = QualificationStandard.iso9606_1,
  DateTime? test,
  DateTime? expiry,
  required DateTime now,
}) =>
    evaluateCertificate(
      WelderCertificate(
        id: id,
        standard: standard,
        certNo: 'PL-7',
        testDate: test,
        expiryDate: expiry,
        processes: '141',
        createdAt: 0,
        updatedAt: 0,
      ),
      asOf: now,
    );

List<(ReminderKind, int, DateTime)> _summary(List<PlannedReminder> plan) => [
      for (final r in plan) (r.kind, r.daysBefore, r.fireAt),
    ];

void main() {
  final now = DateTime(2026, 9, 24, 10);

  test('daleki termin ważności i ciągłości — cztery przypomnienia o 9:00', () {
    final e = _eval(
      test: DateTime(2026, 9, 1), // ciągłość do 2027-03-01
      expiry: DateTime(2029, 9, 1),
      now: now,
    );
    final plan = planQualificationReminders([e], now: now, english: false);
    expect(_summary(plan), [
      (ReminderKind.continuity, 30, DateTime(2027, 1, 30, 9)),
      (ReminderKind.continuity, 7, DateTime(2027, 2, 22, 9)),
      (ReminderKind.expiry, 30, DateTime(2029, 8, 2, 9)),
      (ReminderKind.expiry, 7, DateTime(2029, 8, 25, 9)),
    ]);
  });

  test('termin za 12 dni — tylko przypomnienie 7 dni przed', () {
    final e = _eval(
      standard: QualificationStandard.other,
      expiry: DateTime(2026, 10, 6),
      now: now,
    );
    final plan = planQualificationReminders([e], now: now, english: false);
    expect(_summary(plan), [(ReminderKind.expiry, 7, DateTime(2026, 9, 29, 9))]);
  });

  test('przypomnienie „dziś o 9:00" po 9:00 już nie jest planowane', () {
    // Termin za dokładnie 7 dni, a jest 10:00.
    final e = _eval(
      standard: QualificationStandard.other,
      expiry: DateTime(2026, 10, 1),
      now: now,
    );
    expect(planQualificationReminders([e], now: now, english: false), isEmpty);
    // O 8:00 tego samego dnia — jeszcze tak.
    final early = DateTime(2026, 9, 24, 8);
    expect(
      _summary(planQualificationReminders([e], now: early, english: false)),
      [(ReminderKind.expiry, 7, DateTime(2026, 9, 24, 9))],
    );
  });

  test('termin po czasie — żadnych przypomnień (mówi baner)', () {
    final e = _eval(
      test: DateTime(2025, 1, 1),
      expiry: DateTime(2026, 9, 1),
      now: now,
    );
    expect(planQualificationReminders([e], now: now, english: false), isEmpty);
  });

  test('ciągłość po dacie ważności — bez podwójnych przypomnień', () {
    // Egzamin 2026-09-01 → ciągłość 2027-03-01, ale ważny tylko do 2026-12-01.
    final e = _eval(
      test: DateTime(2026, 9, 1),
      expiry: DateTime(2026, 12, 1),
      now: now,
    );
    final plan = planQualificationReminders([e], now: now, english: false);
    expect(plan.map((r) => r.kind).toSet(), {ReminderKind.expiry});
  });

  test('identyfikatory stabilne między planowaniami i różne w planie', () {
    final a = _eval(id: 'a', test: DateTime(2026, 9, 1),
        expiry: DateTime(2029, 1, 1), now: now);
    final b = _eval(id: 'b', test: DateTime(2026, 9, 1),
        expiry: DateTime(2029, 1, 1), now: now);
    final first = planQualificationReminders([a, b], now: now, english: false);
    final second = planQualificationReminders([a, b], now: now, english: true);
    expect(first.map((r) => r.id).toList(), second.map((r) => r.id).toList());
    expect(first.map((r) => r.id).toSet(), hasLength(first.length));
    for (final r in first) {
      expect(r.id, greaterThan(0));
      expect(r.id, lessThanOrEqualTo(0x7FFFFFFF));
    }
    expect(reminderId('a', ReminderKind.expiry, 30),
        reminderId('a', ReminderKind.expiry, 30));
    expect(reminderId('a', ReminderKind.expiry, 30),
        isNot(reminderId('a', ReminderKind.expiry, 7)));
  });

  test('limit iOS — najbliższe przypomnienia, posortowane', () {
    final many = [
      for (var i = 0; i < 20; i++)
        _eval(
          id: 'c$i',
          test: DateTime(2026, 9, 1),
          expiry: DateTime(2029, 1, 1 + i),
          now: now,
        ),
    ];
    final plan = planQualificationReminders(many,
        now: now, english: false, maxCount: 10);
    expect(plan, hasLength(10));
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].fireAt.isBefore(plan[i - 1].fireAt), isFalse);
    }
  });

  test('treść: ISO mówi o potwierdzeniu koordynatora, ASME o spoinie', () {
    final iso = _eval(test: DateTime(2026, 9, 1), now: now);
    final asme = _eval(
        id: 'x',
        standard: QualificationStandard.asmeIx,
        test: DateTime(2026, 9, 1),
        now: now);
    final pl = planQualificationReminders([iso, asme], now: now, english: false);
    final isoBody = pl.firstWhere((r) => r.certificateId == 'c1').body;
    final asmeBody = pl.firstWhere((r) => r.certificateId == 'x').body;
    expect(isoBody, contains('koordynator'));
    expect(isoBody, contains('9606-1'));
    expect(asmeBody, contains('QW-322.1'));
    expect(pl.first.title, contains('30 dni'));

    final en = planQualificationReminders([iso], now: now, english: true);
    expect(en.first.title, contains('30 days'));
    expect(en.first.body, contains('coordinator'));
  });
}
