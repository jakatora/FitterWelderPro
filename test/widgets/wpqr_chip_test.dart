// Regression net for `lib/widgets/wpqr_chip.dart`.
//
// v21: the banner no longer says "WPQR" — a WPQR is the PROCEDURE record
// (EN ISO 15614-1); the welder holds a qualification (EN ISO 9606-1
// certificate / ASME WPQ). These legacy-chip tests pin the corrected wording;
// the register-backed banner is covered in qualification_banner_test.dart.
//
// The bug this covers is an ABSENCE: `WelderIdentity.wpqrExpiringSoon` and
// `.wpqrExpired` were implemented and unit-tested at P0-08, then never read
// by any screen, so the app never warned anyone. A model getter nobody
// renders warns nobody — these tests pin the three states as they reach the
// glass, not as they reach the model.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/welder_identity.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/wpqr_chip.dart';

/// WpqrChip calls `context.tr`, which needs AppLanguageScope in the tree —
/// mirror the app's main() setup. `Align` keeps the constraints loose so the
/// chip's own size is measurable (a tight parent would mask the
/// "renders nothing" case).
Widget _wrap(Widget child, {AppLanguage lang = AppLanguage.en}) {
  return AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// A fully-populated welder, varying only the one field under test.
WelderIdentity _welder({DateTime? expiry}) => WelderIdentity(
      stamp: 'JK-014',
      wpqrNo: 'WPS-2026-014',
      wpqrExpiry: expiry,
      certBody: CertificationBody.udt,
      displayName: 'Jan Kowalski',
      gdprConsentAt: DateTime.now(),
      qualificationDeclaredAt: DateTime.now(),
    );

/// Colour is the whole point of the chip on a noisy site screen: amber means
/// "book the renewal", red means "stop stamping joints".
Color? _accent(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(of: find.byType(WpqrChip), matching: find.byType(Icon)),
    )
    .color;

/// Padding must NOT be reserved when there is nothing to warn about,
/// otherwise every host layout gets a hole on the happy path.
const _padding = EdgeInsets.only(top: 16, bottom: 12);

void main() {
  group('WpqrChip — nothing to warn about', () {
    testWidgets('null identity draws nothing and takes no space',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const WpqrChip(identity: null, padding: _padding)),
      );

      expect(find.textContaining('qualification'), findsNothing);
      expect(tester.getSize(find.byType(WpqrChip)), Size.zero);
    });

    testWidgets('no expiry date recorded draws nothing', (tester) async {
      // Most welders leave the optional date blank; the chip must not nag.
      await tester.pumpWidget(
        _wrap(WpqrChip(identity: _welder(), padding: _padding)),
      );

      expect(find.textContaining('qualification'), findsNothing);
      expect(tester.getSize(find.byType(WpqrChip)), Size.zero);
    });

    testWidgets('expiry far in the future draws nothing', (tester) async {
      await tester.pumpWidget(_wrap(
        WpqrChip(
          identity:
              _welder(expiry: DateTime.now().add(const Duration(days: 400))),
          padding: _padding,
        ),
      ));

      expect(find.textContaining('qualification'), findsNothing);
      expect(tester.getSize(find.byType(WpqrChip)), Size.zero);
    });
  });

  group('WpqrChip — expiring soon', () {
    testWidgets('amber chip states how many days are left', (tester) async {
      // +1 h so the floor of `difference(now).inDays` lands on 12 and not on
      // 11 while the test itself is running.
      await tester.pumpWidget(_wrap(
        WpqrChip(
          identity: _welder(
            expiry: DateTime.now().add(const Duration(days: 12, hours: 1)),
          ),
        ),
      ));

      expect(find.textContaining('Welder qualification expires in 12 days'), findsOneWidget);
      expect(find.textContaining('expired'), findsNothing);
      expect(_accent(tester), kWarn);
      expect(tester.getSize(find.byType(WpqrChip)).height, greaterThan(0));
    });

    testWidgets('Polish singular is "dzień", plural is "dni"', (tester) async {
      await tester.pumpWidget(_wrap(
        WpqrChip(
          identity: _welder(
            expiry: DateTime.now().add(const Duration(days: 1, hours: 1)),
          ),
        ),
        lang: AppLanguage.pl,
      ));
      expect(find.textContaining('Uprawnienie spawacza wygasa za 1 dzień'), findsOneWidget);

      await tester.pumpWidget(_wrap(
        WpqrChip(
          identity: _welder(
            expiry: DateTime.now().add(const Duration(days: 5, hours: 1)),
          ),
        ),
        lang: AppLanguage.pl,
      ));
      expect(find.textContaining('Uprawnienie spawacza wygasa za 5 dni'), findsOneWidget);
    });
  });

  group('WpqrChip — expired', () {
    testWidgets('red chip naming the date the qualification lapsed',
        (tester) async {
      final expiry = DateTime.now().subtract(const Duration(days: 3));
      await tester
          .pumpWidget(_wrap(WpqrChip(identity: _welder(expiry: expiry))));

      final stamped = '${expiry.year}-'
          '${expiry.month.toString().padLeft(2, "0")}-'
          '${expiry.day.toString().padLeft(2, "0")}';
      expect(find.textContaining('Welder qualification expired $stamped'), findsOneWidget);
      expect(_accent(tester), kFail);
    });

    testWidgets('lapsed a few hours ago is RED, not amber "expires today"',
        (tester) async {
      // The trap this pins: `wpqrExpiringSoon` computes
      // `difference(now).inDays`, and Duration truncates toward zero, so a
      // WPQR that died five hours ago still reports 0 days left and passes
      // the `daysLeft >= 0` guard — BOTH getters are true. Reading them in
      // the wrong order would show a calm amber "expires today" on a
      // certificate that is already dead.
      await tester.pumpWidget(_wrap(
        WpqrChip(
          identity: _welder(
            expiry: DateTime.now().subtract(const Duration(hours: 5)),
          ),
        ),
      ));

      expect(_accent(tester), kFail);
      expect(find.textContaining('Welder qualification expired'), findsOneWidget);
      expect(find.textContaining('expires today'), findsNothing);
    });
  });

  testWidgets('the banner never calls the welder qualification "WPQR"',
      (tester) async {
    for (final lang in AppLanguage.values) {
      for (final expiry in [
        DateTime.now().add(const Duration(days: 5, hours: 1)),
        DateTime.now().subtract(const Duration(days: 3)),
      ]) {
        await tester.pumpWidget(
            _wrap(WpqrChip(identity: _welder(expiry: expiry)), lang: lang));
        expect(find.textContaining('WPQR'), findsNothing,
            reason: '$lang, $expiry');
      }
    }
  });

  group('wpqrWarningOf', () {
    test('maps every state, expired winning the overlap', () {
      expect(wpqrWarningOf(null), WpqrWarning.none);
      expect(wpqrWarningOf(_welder()), WpqrWarning.none);
      expect(
        wpqrWarningOf(
            _welder(expiry: DateTime.now().add(const Duration(days: 400)))),
        WpqrWarning.none,
      );
      expect(
        wpqrWarningOf(
            _welder(expiry: DateTime.now().add(const Duration(days: 12)))),
        WpqrWarning.expiringSoon,
      );
      expect(
        wpqrWarningOf(
            _welder(expiry: DateTime.now().subtract(const Duration(days: 3)))),
        WpqrWarning.expired,
      );
      expect(
        wpqrWarningOf(
            _welder(expiry: DateTime.now().subtract(const Duration(hours: 5)))),
        WpqrWarning.expired,
      );
    });
  });

  group('wpqrDaysLeft', () {
    test('floors the remaining days, matching the getter it mirrors', () {
      // UTC on both sides: a wall-clock difference taken across a DST
      // boundary is an hour short, which would flip these by one day on a
      // machine in a southern-hemisphere timezone.
      final now = DateTime.utc(2026, 8, 29, 12);
      expect(
        wpqrDaysLeft(_welder(expiry: DateTime.utc(2026, 9, 10, 11)), now: now),
        11, // 11 d 23 h — floored, never rounded up past the 30-day rule
      );
      expect(
        wpqrDaysLeft(_welder(expiry: DateTime.utc(2026, 9, 10, 13)), now: now),
        12,
      );
      expect(wpqrDaysLeft(_welder(), now: now), 0);
    });
  });
}
