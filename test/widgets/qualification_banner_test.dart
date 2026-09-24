// Baner rejestru uprawnień (menu SPAWACZ, profil) — stany, kolory, teksty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/certificate_status.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/wpqr_chip.dart';

Widget _wrap(Widget child, {AppLanguage lang = AppLanguage.pl}) =>
    AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );

final _today = DateTime(2026, 9, 24);

CertificateEvaluation _eval({
  String id = 'c1',
  QualificationStandard standard = QualificationStandard.iso9606_1,
  DateTime? test,
  DateTime? expiry,
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
      asOf: _today,
    );

Color? _iconColor(WidgetTester tester) => tester
    .widget<Icon>(find.descendant(
        of: find.byType(QualificationBanner), matching: find.byType(Icon)).first)
    .color;

void main() {
  group('QualificationBanner', () {
    testWidgets('pusty rejestr i wszystko ważne — nic, zero miejsca',
        (tester) async {
      for (final overview in [
        null,
        QualificationOverview.empty,
        QualificationOverview([_eval(test: DateTime(2026, 9, 1))]),
      ]) {
        await tester.pumpWidget(_wrap(QualificationBanner(
          overview: overview,
          padding: const EdgeInsets.all(20),
        )));
        expect(tester.getSize(find.byType(QualificationBanner)), Size.zero);
      }
    });

    testWidgets('wymaga potwierdzenia — bursztyn, termin i koordynator',
        (tester) async {
      final due = _eval(test: DateTime(2026, 4, 10)); // termin 2026-10-10
      await tester.pumpWidget(
          _wrap(QualificationBanner(overview: QualificationOverview([due]))));
      expect(find.textContaining('Potwierdzenie 6-miesięczne za 16 dni'),
          findsOneWidget);
      expect(find.textContaining('2026-10-10'), findsOneWidget);
      expect(find.textContaining('koordynatora'), findsOneWidget);
      expect(_iconColor(tester), kWarn);
    });

    testWidgets('przeterminowany wygrywa z bursztynowym i liczy resztę',
        (tester) async {
      final due = _eval(id: 'a', test: DateTime(2026, 4, 10));
      final dead = _eval(id: 'b', expiry: DateTime(2026, 9, 1));
      await tester.pumpWidget(_wrap(
        QualificationBanner(overview: QualificationOverview([due, dead])),
        lang: AppLanguage.en,
      ));
      expect(find.textContaining('Welder qualification expired 2026-09-01'),
          findsOneWidget);
      expect(find.textContaining('+1 more'), findsOneWidget);
      expect(_iconColor(tester), kFail);
    });

    testWidgets('stuknięcie woła onTap (otwarcie rejestru)', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(QualificationBanner(
        overview:
            QualificationOverview([_eval(expiry: DateTime(2026, 10, 1))]),
        onTap: () => taps++,
      )));
      await tester.tap(find.byType(QualificationBanner));
      expect(taps, 1);
    });
  });

  group('qualificationWarningText', () {
    test('ASME — mowa o spoinie tym procesem, nie o podpisie', () {
      final lapsed = _eval(
          standard: QualificationStandard.asmeIx, test: DateTime(2026, 1, 1));
      final pl = qualificationWarningText(lapsed, english: false);
      expect(pl, contains('WPQ wygasło'));
      expect(pl, contains('QW-322.1'));
      final due = _eval(
          standard: QualificationStandard.asmeIx, test: DateTime(2026, 4, 10));
      expect(qualificationWarningText(due, english: true),
          contains('Weld with this process'));
    });

    test('ISO po terminie — brak potwierdzenia §9.2', () {
      final lapsed = _eval(test: DateTime(2026, 1, 1));
      expect(qualificationWarningText(lapsed, english: false),
          contains('brak potwierdzenia'));
      expect(qualificationWarningText(lapsed, english: false),
          contains('9606-1 §9.2'));
    });

    test('termin dziś — „dziś”, nie „za 0 dni”', () {
      final today = _eval(
          standard: QualificationStandard.other, expiry: _today);
      expect(qualificationWarningText(today, english: false),
          contains('wygasa dziś'));
      final tomorrow = _eval(
          standard: QualificationStandard.other,
          expiry: _today.add(const Duration(days: 1)));
      expect(qualificationWarningText(tomorrow, english: false),
          contains('za 1 dzień'));
    });

    test('żaden tekst nie nazywa uprawnienia spawacza „WPQR”', () {
      for (final e in [
        _eval(test: DateTime(2026, 1, 1)),
        _eval(test: DateTime(2026, 4, 10)),
        _eval(expiry: DateTime(2026, 9, 1)),
        _eval(expiry: DateTime(2026, 10, 1)),
        _eval(standard: QualificationStandard.asmeIx, test: DateTime(2026, 1, 1)),
      ]) {
        for (final english in [false, true]) {
          expect(qualificationWarningText(e, english: english),
              isNot(contains('WPQR')));
        }
      }
    });
  });
}
