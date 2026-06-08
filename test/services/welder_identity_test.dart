// Regression net for P0-08 welder identity model + JSON round-trip.
// Persistence-layer (SharedPreferences) tests need an integration test
// harness; here we pin the model invariants the audit relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/welder_identity.dart';

void main() {
  group('kStampRegex', () {
    test('accepts valid welder stamps', () {
      final accepted = ['JK-014', 'WP12', 'AB-001', 'X1', '123', 'JANKOWAL'];
      for (final s in accepted) {
        expect(kStampRegex.hasMatch(s), isTrue, reason: 'expected $s valid');
      }
    });

    test('rejects invalid welder stamps', () {
      final rejected = [
        '', // empty
        'A', // too short
        'A234567890123', // 13 chars > max 12
        'jk-014', // lowercase — UI uppercases before validate
        'JK 014', // space disallowed
        'JK_014', // underscore disallowed
        'JK#1', // special char
        'Jan Kowalski', // mixed case + space
      ];
      for (final s in rejected) {
        expect(kStampRegex.hasMatch(s), isFalse, reason: 'expected $s invalid');
      }
    });
  });

  group('WelderIdentity JSON round-trip', () {
    test('all fields populated → identical after fromJson(toJson())', () {
      final original = WelderIdentity(
        stamp: 'JK-014',
        wpqrNo: 'WPS-2026-014',
        wpqrExpiry: DateTime.utc(2028, 6, 9),
        certBody: CertificationBody.udt,
        displayName: 'Jan Kowalski',
        email: 'jan@example.pl',
        gdprConsentAt: DateTime.utc(2026, 6, 9, 14, 32),
        qualificationDeclaredAt: DateTime.utc(2026, 6, 9, 14, 33),
      );
      final restored = WelderIdentity.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.stamp, original.stamp);
      expect(restored.wpqrNo, original.wpqrNo);
      expect(restored.wpqrExpiry, original.wpqrExpiry);
      expect(restored.certBody, original.certBody);
      expect(restored.displayName, original.displayName);
      expect(restored.email, original.email);
      expect(restored.gdprConsentAt, original.gdprConsentAt);
      expect(restored.qualificationDeclaredAt,
          original.qualificationDeclaredAt);
    });

    test('only required fields → restores with defaults', () {
      final original = WelderIdentity(
        stamp: 'AB-001',
        gdprConsentAt: DateTime.utc(2026, 6, 9),
        qualificationDeclaredAt: DateTime.utc(2026, 6, 9),
      );
      final restored = WelderIdentity.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.stamp, 'AB-001');
      expect(restored.wpqrNo, isNull);
      expect(restored.wpqrExpiry, isNull);
      expect(restored.certBody, CertificationBody.other);
      expect(restored.displayName, isNull);
      expect(restored.email, isNull);
    });

    test('missing required field → null (defensive)', () {
      expect(
        WelderIdentity.fromJson({
          'gdprConsentAt': '2026-06-09T00:00:00.000Z',
          'qualificationDeclaredAt': '2026-06-09T00:00:00.000Z',
        }),
        isNull,
      );
    });

    test('unknown certBody name → falls back to "other"', () {
      final json = {
        'stamp': 'JK-014',
        'certBody': 'utterly-bogus',
        'gdprConsentAt': '2026-06-09T00:00:00.000Z',
        'qualificationDeclaredAt': '2026-06-09T00:00:00.000Z',
      };
      final restored = WelderIdentity.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.certBody, CertificationBody.other);
    });
  });

  group('WelderIdentity.wpqrExpiring / expired', () {
    test('no expiry set → both flags false', () {
      final id = WelderIdentity(
        stamp: 'JK-014',
        gdprConsentAt: DateTime.now(),
        qualificationDeclaredAt: DateTime.now(),
      );
      expect(id.wpqrExpiringSoon, isFalse);
      expect(id.wpqrExpired, isFalse);
    });

    test('expiry > 30 days out → neither flag', () {
      final id = WelderIdentity(
        stamp: 'JK-014',
        wpqrExpiry: DateTime.now().add(const Duration(days: 60)),
        gdprConsentAt: DateTime.now(),
        qualificationDeclaredAt: DateTime.now(),
      );
      expect(id.wpqrExpiringSoon, isFalse);
      expect(id.wpqrExpired, isFalse);
    });

    test('expiry within 30 days → expiringSoon true, expired false', () {
      final id = WelderIdentity(
        stamp: 'JK-014',
        wpqrExpiry: DateTime.now().add(const Duration(days: 10)),
        gdprConsentAt: DateTime.now(),
        qualificationDeclaredAt: DateTime.now(),
      );
      expect(id.wpqrExpiringSoon, isTrue);
      expect(id.wpqrExpired, isFalse);
    });

    test('expiry in the past → expired true', () {
      final id = WelderIdentity(
        stamp: 'JK-014',
        wpqrExpiry: DateTime.now().subtract(const Duration(days: 1)),
        gdprConsentAt: DateTime.now(),
        qualificationDeclaredAt: DateTime.now(),
      );
      expect(id.wpqrExpired, isTrue);
      // ExpiringSoon is for "approaching" — already-expired returns false.
      expect(id.wpqrExpiringSoon, isFalse);
    });
  });

  group('CertificationBody labels', () {
    test('every body has a non-empty label', () {
      for (final c in CertificationBody.values) {
        expect(c.label, isNotEmpty, reason: 'label missing for $c');
      }
    });
  });
}
