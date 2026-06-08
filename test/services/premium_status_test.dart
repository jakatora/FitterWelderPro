// Regression net for PremiumStatus boundary conditions — pins the data
// model that the P0-04 / P0r-10 downgrade-grace fix relies on. Without
// these, a future refactor of `isActive` semantics could silently strip
// PRO from a paying customer (P0-04's root scenario) and the test suite
// would not catch it.
//
// Full PremiumService.refreshFromBackend tests require ApiClient mocking
// which we don't have a seam for yet (P0-07 backend audit lens flagged
// DI gap). Until then these isActive boundary tests are the regression
// floor we can ship without invasive refactor.

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/premium_service.dart';

void main() {
  group('PremiumStatus.isActive', () {
    test('free → never active', () {
      expect(PremiumStatus.free().isActive, isFalse);
    });

    test('lifetime → always active regardless of expiresAt', () {
      const s = PremiumStatus(plan: PremiumPlan.lifetime);
      expect(s.isActive, isTrue);
      // Even with an expiry deep in the past, lifetime never expires.
      final past = PremiumStatus(
        plan: PremiumPlan.lifetime,
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(past.isActive, isTrue);
    });

    test('monthly with expiresAt in the future → active', () {
      final s = PremiumStatus(
        plan: PremiumPlan.monthly,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(s.isActive, isTrue);
    });

    test('monthly with expiresAt in the past → inactive', () {
      final s = PremiumStatus(
        plan: PremiumPlan.monthly,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.isActive, isFalse);
    });

    test('monthly with null expiresAt → inactive (defensive)', () {
      // This is the edge case the P0-04 grace logic protects against: a
      // backend response that returns plan=monthly but no period_end. Old
      // code would have treated this as active (subscription record present)
      // — current code correctly reads as inactive.
      const s = PremiumStatus(plan: PremiumPlan.monthly);
      expect(s.isActive, isFalse);
    });

    test('yearly with expiresAt just-now → inactive (boundary)', () {
      // Boundary: isActive uses `isBefore(exp)`. If exp == now exactly the
      // user is NOT active. This is the tightest boundary the downgrade
      // grace has to defend — a paying user whose subscription expires
      // mid-job should still get the 2-min grace before PRO is stripped.
      final exp = DateTime.now();
      final s = PremiumStatus(plan: PremiumPlan.yearly, expiresAt: exp);
      expect(s.isActive, isFalse);
    });
  });

  group('PremiumStatus.copyWith', () {
    test('copyWith preserves unspecified fields', () {
      final s = PremiumStatus(
        plan: PremiumPlan.yearly,
        expiresAt: DateTime(2027, 1, 1),
        lastVerifiedAt: DateTime(2026, 6, 1),
      );
      final touched = s.copyWith(lastVerifiedAt: DateTime(2026, 6, 8));
      expect(touched.plan, PremiumPlan.yearly);
      expect(touched.expiresAt, DateTime(2027, 1, 1));
      expect(touched.lastVerifiedAt, DateTime(2026, 6, 8));
    });

    test('copyWith only-plan downgrade', () {
      final s = PremiumStatus(
        plan: PremiumPlan.monthly,
        expiresAt: DateTime(2027, 1, 1),
      );
      final downgraded = s.copyWith(plan: PremiumPlan.free);
      // expiresAt is preserved by copyWith — caller is responsible for
      // wiping it when plan changes to free. Documents the contract.
      expect(downgraded.plan, PremiumPlan.free);
      expect(downgraded.expiresAt, DateTime(2027, 1, 1));
    });
  });

  group('PremiumStatus.label', () {
    test('every plan has a non-empty label', () {
      for (final p in PremiumPlan.values) {
        final s = PremiumStatus(plan: p);
        expect(s.label, isNotEmpty);
      }
    });

    test('free label matches paywall copy', () {
      expect(PremiumStatus.free().label, 'FREE');
    });
  });
}
