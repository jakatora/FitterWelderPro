// Model sygnału feedbacku: zgodność z fixture kontraktu (ten sam plik ma
// backend) i reguły pól.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/config/app_version.dart';
import 'package:cut_list_app/feedback/feedback_signal.dart';
import 'package:cut_list_app/i18n/app_language.dart';

Map<String, Object?> _fixture() => (jsonDecode(
            File('test/fixtures/feedback_signal_v1.json').readAsStringSync())
        as Map)
    .cast<String, Object?>();

Map<String, Object?> _fixtureItem() =>
    ((_fixture()['items'] as List).single as Map).cast<String, Object?>();

void main() {
  group('fixture feedback_signal_v1.json', () {
    test('fromJson → toJson daje dokładnie element z fixture', () {
      final item = _fixtureItem();
      final s = FeedbackSignal.fromJson(item);

      expect(s.id, '3f0c2b7e-5d8a-4b7e-9a7b-2f1d9c0e4a11');
      expect(s.kind, FeedbackKind.notUnderstood);
      expect(s.text, 'narysuj mi trójnik równoprzelotowy');
      expect(s.tool, 'iso_notebook');
      expect(s.skill, isNull);
      expect(s.skillsVersion, 1);
      expect(s.app, '0.5.0+19');
      expect(s.platform, 'android');
      expect(s.lang, 'pl');
      expect(s.at, DateTime.utc(2026, 10, 19, 12));
      expect(s.at.isUtc, isTrue);
      expect(s.errorType, isNull);

      final out = s.toJson();
      expect(out, item);
      expect(out.keys.toList(), item.keys.toList(), reason: 'kolejność kluczy');
      expect(jsonEncode(out), jsonEncode(item));
    });

    test('feedbackPayload([sygnał]) = całe ciało z fixture', () {
      final s = FeedbackSignal.fromJson(_fixtureItem());
      expect(feedbackPayload([s]), _fixture());
      expect(jsonEncode(feedbackPayload([s])), jsonEncode(_fixture()));
    });

    test('rodzaje w JSON mają nazwy z kontraktu', () {
      expect(FeedbackKind.values.map((k) => k.name), [
        'explicit',
        'complaint',
        'cantFind',
        'notUnderstood',
        'error',
      ]);
    });
  });

  group('FeedbackSignal.create', () {
    test('maskuje tekst, ustawia wersję, platformę, język i czas UTC (ms)', () {
      final s = FeedbackSignal.create(
        kind: FeedbackKind.explicit,
        text: '  zadzwoń 600-100-200 albo jan@x.pl  ',
        tool: 'pipe_weight',
        lang: AppLanguage.en,
        at: DateTime.utc(2026, 10, 19, 12, 0, 0, 123, 456),
      );
      expect(s.text, 'zadzwoń *** albo ***');
      expect(s.app, kAppVersion);
      expect(s.platform, 'android', reason: 'flutter_test = android');
      expect(s.lang, 'en');
      expect(s.at, DateTime.utc(2026, 10, 19, 12, 0, 0, 123));
      expect(s.toJson()['at'], '2026-10-19T12:00:00.123Z');
      expect(s.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(FeedbackSignal.fromJson(s.toJson()), s);
    });

    test('czas lokalny zamieniany na UTC', () {
      final local = DateTime(2026, 10, 19, 14);
      final s = FeedbackSignal.create(kind: FeedbackKind.complaint, at: local);
      expect(s.at.isUtc, isTrue);
      expect(s.at.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
      expect(s.toJson()['at'], endsWith('Z'));
    });

    test('error ma zawsze pusty tekst, typ błędu zostaje', () {
      final s = FeedbackSignal.create(
        kind: FeedbackKind.error,
        text: 'stack trace z danymi',
        tool: 'cut_list',
        errorType: 'RangeError',
      );
      expect(s.text, '');
      expect(s.errorType, 'RangeError');
    });

    test('tekst ≤ 500, tool/skill ≤ 64, errorType ≤ 80, puste → null', () {
      final s = FeedbackSignal.create(
        kind: FeedbackKind.notUnderstood,
        text: 'a' * 800,
        tool: 't' * 100,
        skill: '   ',
        errorType: 'E' * 100,
      );
      expect(s.text.length, kFeedbackTextMax);
      expect(s.tool!.length, kFeedbackTagMax);
      expect(s.skill, isNull);
      expect(s.errorType!.length, kFeedbackErrorTypeMax);
      expect(kFeedbackErrorTypeMax, 80);
      expect(s.isValidForUpload, isTrue);
      expect(FeedbackSignal.fromJson(s.toJson()), s);

      final e = FeedbackSignal.create(kind: FeedbackKind.error, errorType: '');
      expect(e.errorType, isNull);
    });

    test('każde wywołanie ma nowe id', () {
      final a = FeedbackSignal.create(kind: FeedbackKind.complaint, text: 'x');
      final b = FeedbackSignal.create(kind: FeedbackKind.complaint, text: 'x');
      expect(a.id, isNot(b.id));
    });

    test('pusty tekst wolno tylko dla error', () {
      for (final kind in FeedbackKind.values) {
        final s = FeedbackSignal.create(kind: kind, text: '   ');
        expect(s.isValidForUpload, kind == FeedbackKind.error,
            reason: kind.name);
        if (kind != FeedbackKind.error) expect(s.contractViolation, 'text');
      }
    });
  });

  group('contractViolation: reguły serwera', () {
    final cases = <String, (String, Object?)>{
      'text > 500': ('text', 'x' * 501),
      'pusty text przy notUnderstood': ('text', ''),
      'tool > 64': ('tool', 't' * 65),
      'tool pusty': ('tool', ''),
      'skill > 64': ('skill', 's' * 65),
      'errorType > 80': ('errorType', 'E' * 81),
      'platform spoza listy': ('platform', 'linux'),
      'lang spoza listy': ('lang', 'de'),
      'app pusty': ('app', ''),
      'id > 64': ('id', 'i' * 65),
      'skillsVersion ujemne': ('skillsVersion', -1),
    };
    cases.forEach((name, c) {
      test(name, () {
        final item = {..._fixtureItem(), c.$1: c.$2};
        final s = FeedbackSignal.fromJson(item);
        expect(s.contractViolation, c.$1);
        expect(s.isValidForUpload, isFalse);
      });
    });

    test('granice przechodzą: text 500, tool 64, errorType 80', () {
      final s = FeedbackSignal.fromJson({
        ..._fixtureItem(),
        'text': 'x' * 500,
        'tool': 't' * 64,
        'skill': 's' * 64,
        'errorType': 'E' * 80,
      });
      expect(s.contractViolation, isNull);
    });

    test('error z treścią jest niezgodny (treść błędu nie wychodzi)', () {
      final s = FeedbackSignal.fromJson(
          {..._fixtureItem(), 'kind': 'error', 'text': 'stack trace'});
      expect(s.contractViolation, 'text');
      expect(s.sanitized().isValidForUpload, isTrue);
      expect(s.sanitized().text, '');
    });

    test('fixture jest zgodny z kontraktem', () {
      expect(FeedbackSignal.fromJson(_fixtureItem()).contractViolation, isNull);
    });
  });

  group('fromJson odrzuca złą STRUKTURĘ', () {
    final bad = <String, (String, Object?)>{
      'kind spoza listy': ('kind', 'praise'),
      'text nie jest tekstem': ('text', 5),
      'text null': ('text', null),
      'tool liczbą': ('tool', 7),
      'at nie jest datą': ('at', 'wczoraj'),
      'skillsVersion tekstem': ('skillsVersion', '1'),
      'id pusty': ('id', ''),
      'platform null': ('platform', null),
      'errorType liczbą': ('errorType', 1),
    };
    bad.forEach((name, c) {
      test(name, () {
        final item = {..._fixtureItem(), c.$1: c.$2};
        expect(() => FeedbackSignal.fromJson(item), throwsFormatException);
      });
    });

    test('brak wymaganego pola', () {
      final item = {..._fixtureItem()}..remove('text');
      expect(() => FeedbackSignal.fromJson(item), throwsFormatException);
    });
  });

  test('najgorsza partia mieści się w limicie ciała serwera (128 KB)', () {
    // 500 znaków sterujących = 6 bajtów każdy po jsonEncode (\u0001).
    final worst = [
      for (var i = 0; i < kFeedbackBatchMax; i++)
        FeedbackSignal(
          id: 'i' * 64,
          kind: FeedbackKind.explicit,
          text: '\u0001' * kFeedbackTextMax,
          tool: '"' * kFeedbackTagMax,
          skill: '"' * kFeedbackTagMax,
          skillsVersion: 1 << 30,
          app: 'a' * 32,
          platform: 'windows',
          lang: 'pl',
          at: DateTime.utc(2026, 10, 19),
          errorType: '"' * kFeedbackErrorTypeMax,
        ),
    ];
    final bytes = utf8.encode(jsonEncode(feedbackPayload(worst))).length;
    expect(bytes, lessThan(128 * 1024));
  });
}
