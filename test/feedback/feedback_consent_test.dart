import 'package:cut_list_app/services/legal_consent.dart';
// Zgoda na feedback (domyślnie brak) i losowy identyfikator X-Feedback-Id.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/legal/legal_texts.dart';

import 'feedback_test_utils.dart';

FeedbackConsent get consent => FeedbackConsent.instance;

void main() {
  setUp(seedFeedback);

  group('zgoda', () {
    test('domyślnie brak zgody', () async {
      expect(await consent.isGranted(), isFalse);
      final st = await consent.read();
      expect(st.granted, isFalse);
      expect(st.at, isNull);
      expect(st.policy, isNull);
    });

    test('grant zapisuje datę zgody i datę polityki kLegalUpdated', () async {
      final now = DateTime.utc(2026, 10, 19, 8, 30);
      expect(await consent.grant(now: now), isTrue);

      final st = await consent.read();
      expect(st.granted, isTrue);
      expect(st.at, now);
      expect(st.policy, kLegalUpdated);

      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString(FeedbackConsent.prefsKey)!) as Map;
      expect(raw, {
        'granted': true,
        'at': '2026-10-19T08:30:00.000Z',
        'policy': kLegalUpdated,
      });
    });

    test('zgoda na feedback nie udziela zgody na serwer AI', () async {
      LegalConsent.instance.resetForTest();
      await LegalConsent.instance.load();
      expect(LegalConsent.instance.isAccepted, isFalse);
      await consent.grant();
      expect(LegalConsent.instance.isAccepted, isFalse);
    });

    test('revoke: brak zgody, identyfikator zostaje (do kasowania na serwerze)',
        () async {
      await consent.grant();
      final id = await consent.installId();
      await consent.revoke();
      expect(await consent.isGranted(), isFalse);
      expect(await consent.storedInstallId(), id);
    });

    test('nieczytelny zapis zgody = brak zgody', () async {
      for (final raw in ['{', '[]', '{"granted":"tak"}', '{"granted":false}']) {
        seedFeedback({FeedbackConsent.prefsKey: raw});
        expect(await consent.isGranted(), isFalse, reason: raw);
      }
    });
  });

  group('identyfikator instalacji', () {
    test('tworzony leniwie: nic nie ma, dopóki ktoś nie poprosi', () async {
      expect(await consent.storedInstallId(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(FeedbackConsent.installIdKey), isFalse);

      final id = await feedbackInstallId();
      expect(prefs.getString(FeedbackConsent.installIdKey), id);
    });

    test('format base64url 22–64 znaki, stały między wywołaniami', () async {
      final id = await consent.installId();
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{22,64}$')));
      expect(id.length, 32);
      expect(await consent.installId(), id);
      consent.resetForTest();
      expect(await consent.installId(), id, reason: 'odczyt z dysku');
    });

    test('równoległe wywołania dają ten sam identyfikator', () async {
      final ids =
          await Future.wait([for (var i = 0; i < 5; i++) consent.installId()]);
      expect(ids.toSet(), hasLength(1));
    });

    test('to nie jest device_id czatu', () async {
      const deviceId = '0123456789abcdef0123456789abcdef';
      seedFeedback({'fitter_device_id': deviceId});
      final id = await consent.installId();
      expect(id, isNot(deviceId));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitter_device_id'), deviceId);
    });

    test('zapisany w złym formacie → nowy losowy', () async {
      seedFeedback({FeedbackConsent.installIdKey: 'za-krotki'});
      final id = await consent.installId();
      expect(id, isNot('za-krotki'));
      expect(FeedbackConsent.installIdFormat.hasMatch(id), isTrue);
    });

    test('generateInstallId: 24 losowe bajty → 32 znaki base64url', () {
      final a = FeedbackConsent.generateInstallId(math.Random(1));
      final b = FeedbackConsent.generateInstallId(math.Random(2));
      expect(a.length, 32);
      expect(a, isNot(b));
      expect(FeedbackConsent.installIdFormat.hasMatch(a), isTrue);
      expect(FeedbackConsent.generateInstallId(),
          isNot(FeedbackConsent.generateInstallId()));
    });

    test('zawsze pasuje do regexu serwera, nigdy z dopełnieniem „=”', () {
      final server = RegExp(r'^[A-Za-z0-9_-]{22,64}$');
      for (var seed = 0; seed < 300; seed++) {
        final id = FeedbackConsent.generateInstallId(math.Random(seed));
        expect(id, matches(server));
        expect(id, isNot(contains('=')));
      }
    });
  });

  test('clearAll czyści zgodę, identyfikator, kolejkę i kopię uszkodzonej',
      () async {
    await consent.grant();
    await consent.installId();
    await fill(0, 3);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FeedbackStore.corruptKey, 'stary');

    await consent.clearAll();

    expect(await consent.isGranted(), isFalse);
    expect(await consent.storedInstallId(), isNull);
    expect(await FeedbackStore.instance.list(), isEmpty);
    expect(prefs.containsKey(FeedbackStore.corruptKey), isFalse);
    expect(prefs.containsKey(FeedbackStore.prefsKey), isFalse);
  });
}
