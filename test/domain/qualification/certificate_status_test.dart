import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/certificate_status.dart';
import 'package:cut_list_app/domain/qualification/journal_welds.dart';
import 'package:cut_list_app/domain/qualification/weld_process.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';

WelderCertificate _cert({
  QualificationStandard standard = QualificationStandard.iso9606_1,
  DateTime? test,
  DateTime? expiry,
  DateTime? confirmed,
  String processes = '141',
}) =>
    WelderCertificate(
      id: 'c1',
      standard: standard,
      certNo: 'PL-001/2026',
      testDate: test,
      expiryDate: expiry,
      lastConfirmedDate: confirmed,
      processes: processes,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  final today = DateTime(2026, 9, 24, 15, 30);

  group('ISO 9606-1 — potwierdzenie co 6 miesięcy (§9.2)', () {
    for (final (name, cert, state, deadline) in <(
      String,
      WelderCertificate,
      QualificationState,
      DateTime?
    )>[
      (
        'świeży egzamin — ważny',
        _cert(test: DateTime(2026, 8, 1), expiry: DateTime(2029, 8, 1)),
        QualificationState.valid,
        DateTime(2027, 2, 1),
      ),
      (
        'termin za 30 dni — wymaga potwierdzenia',
        _cert(test: DateTime(2026, 4, 24)),
        QualificationState.confirmationDue,
        DateTime(2026, 10, 24),
      ),
      (
        'termin za 31 dni — jeszcze ważny',
        _cert(test: DateTime(2026, 4, 25)),
        QualificationState.valid,
        DateTime(2026, 10, 25),
      ),
      (
        'termin dziś — jeszcze ważny, wymaga potwierdzenia',
        _cert(test: DateTime(2026, 3, 24)),
        QualificationState.confirmationDue,
        DateTime(2026, 9, 24),
      ),
      (
        'termin wczoraj — przeterminowany',
        _cert(test: DateTime(2026, 3, 23)),
        QualificationState.lapsed,
        DateTime(2026, 9, 23),
      ),
      (
        'potwierdzenie przesuwa termin od swojej daty',
        _cert(test: DateTime(2025, 1, 10), confirmed: DateTime(2026, 7, 1)),
        QualificationState.valid,
        DateTime(2027, 1, 1),
      ),
      (
        'potwierdzenie z przyszłości (literówka) się nie liczy',
        _cert(test: DateTime(2026, 3, 1), confirmed: DateTime(2026, 12, 1)),
        QualificationState.lapsed,
        DateTime(2026, 9, 1),
      ),
      (
        'data ważności minęła — wygasł (wygrywa z brakiem potwierdzenia)',
        _cert(test: DateTime(2023, 1, 1), expiry: DateTime(2026, 9, 1)),
        QualificationState.expired,
        DateTime(2023, 7, 1),
      ),
      (
        'data ważności za 10 dni — wygasa wkrótce',
        _cert(
            test: DateTime(2023, 10, 4),
            confirmed: DateTime(2026, 9, 1),
            expiry: DateTime(2026, 10, 4)),
        QualificationState.expiringSoon,
        DateTime(2027, 3, 1),
      ),
      (
        'brak daty egzaminu i potwierdzenia — tylko data ważności',
        _cert(expiry: DateTime(2028, 1, 1)),
        QualificationState.valid,
        null,
      ),
    ]) {
      test(name, () {
        final e = evaluateCertificate(cert, asOf: today);
        expect(e.state, state);
        expect(e.rule, ContinuityRule.confirmation);
        expect(e.continuityDeadline, deadline);
      });
    }

    test('spoiny w dzienniku NIE przedłużają ISO 9606-1 (potrzebny podpis)',
        () {
      final e = evaluateCertificate(
        _cert(test: DateTime(2026, 3, 1)),
        asOf: today,
        journalWelds: [DateTime(2026, 9, 20)],
      );
      expect(e.state, QualificationState.lapsed);
      // …ale ostatnia spoina jest pokazana jako dowód dla koordynatora.
      expect(e.lastJournalWeld, DateTime(2026, 9, 20));
    });

    test('bez daty egzaminu i potwierdzenia ciągłość jest „nieznana"', () {
      final e = evaluateCertificate(_cert(), asOf: today);
      expect(e.continuityUnknown, isTrue);
      expect(e.state, QualificationState.valid);
    });
  });

  group('ASME IX QW-322.1(a) — spawanie procesem co 6 miesięcy', () {
    WelderCertificate asme({DateTime? test, DateTime? confirmed}) => _cert(
          standard: QualificationStandard.asmeIx,
          test: test,
          confirmed: confirmed,
        );

    for (final (name, cert, welds, state, deadline) in <(
      String,
      WelderCertificate,
      List<DateTime>,
      QualificationState,
      DateTime?
    )>[
      (
        'bez spoin od egzaminu 7 mies. — wygasło',
        asme(test: DateTime(2026, 2, 20)),
        const <DateTime>[],
        QualificationState.lapsed,
        DateTime(2026, 8, 20),
      ),
      (
        'spoiny co kilka miesięcy utrzymują łańcuch',
        asme(test: DateTime(2025, 6, 1)),
        [DateTime(2025, 11, 1), DateTime(2026, 4, 15), DateTime(2026, 9, 1)],
        QualificationState.valid,
        DateTime(2027, 3, 1),
      ),
      (
        'przerwa > 6 mies. — późniejsza spoina NIE wskrzesza WPQ',
        asme(test: DateTime(2025, 1, 10)),
        [DateTime(2025, 5, 1), DateTime(2026, 9, 1)],
        QualificationState.lapsed,
        DateTime(2025, 11, 1),
      ),
      (
        'spoina sprzed egzaminu się nie liczy',
        asme(test: DateTime(2026, 4, 20)),
        [DateTime(2026, 4, 1)],
        QualificationState.confirmationDue,
        DateTime(2026, 10, 20),
      ),
      (
        'spoina z przyszłości się nie liczy',
        asme(test: DateTime(2026, 4, 20)),
        [DateTime(2026, 12, 1)],
        QualificationState.confirmationDue,
        DateTime(2026, 10, 20),
      ),
      (
        'wpis ciągłości pracodawcy przesuwa termin jak spoina',
        asme(test: DateTime(2025, 12, 1), confirmed: DateTime(2026, 5, 20)),
        const <DateTime>[],
        QualificationState.valid,
        DateTime(2026, 11, 20),
      ),
      (
        'ostatnia spoina 5 mies. i 10 dni temu — wymaga uwagi',
        asme(test: DateTime(2025, 12, 1)),
        [DateTime(2026, 4, 14)],
        QualificationState.confirmationDue,
        DateTime(2026, 10, 14),
      ),
    ]) {
      test(name, () {
        final e = evaluateCertificate(cert, asOf: today, journalWelds: welds);
        expect(e.rule, ContinuityRule.processUse);
        expect(e.state, state);
        expect(e.continuityDeadline, deadline);
      });
    }
  });

  test('inna norma — tylko data ważności, bez ciągłości', () {
    final e = evaluateCertificate(
      _cert(
          standard: QualificationStandard.other,
          test: DateTime(2020, 1, 1),
          expiry: DateTime(2027, 1, 1)),
      asOf: today,
    );
    expect(e.rule, ContinuityRule.none);
    expect(e.continuityDeadline, isNull);
    expect(e.state, QualificationState.valid);
  });

  test('godzina „teraz" nie zmienia statusu w dniu ważności', () {
    final cert = _cert(
        standard: QualificationStandard.other,
        expiry: DateTime(2026, 9, 24));
    for (final hour in [0, 12, 23]) {
      final e = evaluateCertificate(cert,
          asOf: DateTime(2026, 9, 24, hour, 59));
      expect(e.state, QualificationState.expiringSoon, reason: 'godz. $hour');
      expect(e.daysToExpiry, 0);
    }
    expect(
      evaluateCertificate(cert, asOf: DateTime(2026, 9, 25)).state,
      QualificationState.expired,
    );
  });

  group('journalWeldsFor — ciągłość z dziennika tylko tym procesem', () {
    final journal = [
      JournalWeld(DateTime(2026, 9, 1), {WeldProcessFamily.gtaw}),
      JournalWeld(DateTime(2026, 9, 5), {WeldProcessFamily.smaw}),
      JournalWeld(DateTime(2026, 8, 1), {WeldProcessFamily.gtaw}),
    ];

    test('TIG z certyfikatu 141 — tylko spoiny TIG, posortowane', () {
      expect(journalWeldsFor(_cert(processes: '141'), journal),
          [DateTime(2026, 8, 1), DateTime(2026, 9, 1)]);
    });

    test('certyfikat bez procesu — żadna spoina się nie liczy', () {
      expect(journalWeldsFor(_cert(processes: ''), journal), isEmpty);
    });
  });

  group('journalWeldFromRow — ostrożny odczyt dziennika', () {
    final now = DateTime(2026, 9, 24);
    Map<String, Object?> row(
            {String welder = 'JK-014',
            String date = '2026-09-10',
            String method = 'TIG'}) =>
        {'welder': welder, 'date': date, 'method': method};

    test('poprawny wiersz', () {
      final w = journalWeldFromRow(row(), stamp: 'jk-014', today: now)!;
      expect(w.date, DateTime(2026, 9, 10));
      expect(w.families, {WeldProcessFamily.gtaw});
    });

    for (final (name, r, stamp) in <(String, Map<String, Object?>, String?)>[
      ('cudzy stempel', row(welder: 'AB-1'), 'JK-014'),
      ('brak stempla spawacza', row(), null),
      ('pusty stempel', row(), '  '),
      ('zła data', row(date: '2026-02-30'), 'JK-014'),
      ('data w przyszłości', row(date: '2026-10-01'), 'JK-014'),
      ('nieznana metoda', row(method: '???'), 'JK-014'),
    ]) {
      test('pomija: $name', () {
        expect(journalWeldFromRow(r, stamp: stamp, today: now), isNull);
      });
    }

    test('dziennik v20: spoina usunięta (deleted_at) się nie liczy', () {
      expect(
        journalWeldFromRow({...row(), 'deleted_at': 1758700000000},
            stamp: 'JK-014', today: now),
        isNull,
      );
      expect(
        journalWeldFromRow({...row(), 'deleted_at': null},
            stamp: 'JK-014', today: now),
        isNotNull,
      );
    });

    test('dziennik v20: stempel graniowy albo licowy też jest „spawał"', () {
      for (final column in ['root_welder', 'cap_welder']) {
        final w = journalWeldFromRow(
          {...row(welder: 'AB-1'), column: ' jk-014 '},
          stamp: 'JK-014',
          today: now,
        );
        expect(w, isNotNull, reason: column);
      }
    });

    test('kolumna `process` (jeśli dziennik ją doda) też jest czytana', () {
      final w = journalWeldFromRow(
        {'welder': 'JK-014', 'date': '10.09.2026', 'method': '', 'process': '135'},
        stamp: 'JK-014',
        today: now,
      )!;
      expect(w.families, {WeldProcessFamily.gmaw});
    });
  });

  group('QualificationOverview', () {
    test('najgorszy status i kolejność „do uwagi"', () {
      final ok = evaluateCertificate(
          _cert(test: DateTime(2026, 9, 1)), asOf: today);
      final due = evaluateCertificate(
          _cert(test: DateTime(2026, 4, 10)), asOf: today);
      final dead = evaluateCertificate(
          _cert(test: DateTime(2025, 1, 1)), asOf: today);
      final overview = QualificationOverview([ok, due, dead]);
      expect(overview.worstState.severity, 2);
      expect(overview.needingAttention, [dead, due]);
      expect(QualificationOverview.empty.worstState, QualificationState.valid);
    });
  });
}
