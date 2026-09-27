// Kontrakt POST /api/fitter/ai/intent wspólny z backendem. Plik
// fixtures/assistant_intent_contract_v1.json leży też w repo backendu
// (test/fixtures/) i jest tam czytany przez test/intent-contract.test.js.
// Tu sprawdzamy stronę aplikacji: te same słowniki, zakresy i kolejność pytań,
// te same aliasy, a KAŻDA odpowiedź serwera z przykładów przechodzi walidator
// aplikacji (dawniej serwer oddawał „Ar"/„BW", a aplikacja odrzucała całość).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/assistant/assistant_engine.dart';
import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/premium_service.dart';

final Map<String, dynamic> _contract = jsonDecode(
  File('test/assistant/fixtures/assistant_intent_contract_v1.json')
      .readAsStringSync(),
) as Map<String, dynamic>;

List<String> _list(Object? v) => (v as List).cast<String>();

void main() {
  test('wersja, intencje, pola, słowniki, zakresy i kolejność pytań', () {
    expect(kAssistantIntentsVersion, _contract['intents_version']);
    expect({...kAssistantRemoteIntents, kIntentUnknown},
        _list(_contract['intents']).toSet());

    final fields = _contract['fields'] as Map<String, dynamic>;
    for (final e in fields.entries) {
      final spec = kAssistantIntentsV1[e.key]!;
      final f = e.value as Map<String, dynamic>;
      expect(spec.required, _list(f['required']).toSet(), reason: e.key);
      expect(spec.optional, _list(f['optional']).toSet(), reason: e.key);
    }
    expect(kSaveWeldRequiredOrder, _list(_contract['ask_order']));

    final enums = _contract['enums'] as Map<String, dynamic>;
    expect(kAssistantMaterials, _list(enums['material']).toSet());
    expect(kAssistantProcesses, _list(enums['process']).toSet());
    expect(kAssistantGases, _list(enums['gas']).toSet());
    expect(kAssistantJoints, _list(enums['joint']).toSet());
    expect(kAssistantPositions, _list(enums['position']).toSet());

    final ranges = _contract['ranges'] as Map<String, dynamic>;
    expect(kAssistantRangesV1, ranges.keys.toSet());
    for (final e in ranges.entries) {
      final r = kAssistantRanges[e.key]!;
      final minMax = (e.value as List).cast<num>();
      expect([r.min, r.max], [minMax[0].toDouble(), minMax[1].toDouble()],
          reason: e.key);
    }
    expect(kAssistantMaxQueryLength, _contract['max_query_length']);
  });

  test('aliasy gazu, złącza i pozycji → kody aplikacji (jak na serwerze)', () {
    final aliases = _contract['aliases'] as Map<String, dynamic>;
    final enums = _contract['enums'] as Map<String, dynamic>;
    for (final group in aliases.entries) {
      for (final a in (group.value as Map<String, dynamic>).entries) {
        expect(normalizeAssistantCode(group.key, a.key), a.value,
            reason: '${group.key}: ${a.key}');
      }
      for (final code in _list(enums[group.key])) {
        expect(normalizeAssistantCode(group.key, code), code);
      }
    }
    final rejected = _contract['rejected_values'] as Map<String, dynamic>;
    for (final group in rejected.entries) {
      for (final raw in _list(group.value)) {
        expect(normalizeAssistantCode(group.key, raw), isNull,
            reason: '${group.key}: $raw');
      }
    }
  });

  group('odpowiedzi serwera z przykładów przechodzą walidator aplikacji', () {
    for (final ex in (_contract['server_examples'] as List)
        .cast<Map<String, dynamic>>()) {
      test(ex['name'] as String, () {
        final resp = ex['response'] as Map<String, dynamic>;
        final intent = resp['intent'] as String;
        final fields = (resp['fields'] as Map).cast<String, Object?>();
        final asks = resp['asks'] as String?;
        if (intent == kIntentUnknown) {
          expect(fields, isEmpty);
          return;
        }
        expect(findAssistantRejection(intent, fields), isNull);
        final check = validateAssistantProposal(intent, fields);
        if (asks != null) {
          expect((check as AssistantNeedsField).field, asks);
        } else {
          expect(check,
              anyOf(isA<AssistantReadyToSave>(), isA<AssistantReadyToOpen>()));
        }
      });
    }
  });

  group('silnik: odpowiedź serwera przez HTTP (atrapa) → ten sam wynik', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'fitter_device_id': '0123456789abcdef0123456789abcdef',
        'fitter_install_secret': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE',
      });
      PremiumService.instance.resetForTest();
    });

    test('stary serwer z „Ar 99.996"/„BW"/„pf" → kody, nie odrzucenie', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await http.runWithClient(
        () => engine.interpret('spawałem wczoraj rurkę', lang: AppLanguage.pl),
        () => MockClient((_) async => http.Response(
              jsonEncode({
                'intent': 'save_weld_parameter',
                'fields': {
                  'material': 'SS',
                  'process': 'TIG',
                  'filler': true,
                  'wall_mm': 3,
                  'current_a': 90,
                  'gas': 'Ar 99.996',
                  'joint': 'BW',
                  'position': 'pf',
                },
                'question': null,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      expect(out.remoteRejected, isNull);
      final d = (out.check as AssistantReadyToSave).draft;
      expect(d.gas, 'AR');
      expect(d.joint, 'BUTT');
      expect(d.position, 'PF');
    });

    test('nieznany gaz z serwera odpada sam, reszta zostaje', () async {
      final engine = AssistantEngine(remoteAllowed: () async => true);
      final out = await http.runWithClient(
        () => engine.interpret('spawałem wczoraj rurkę', lang: AppLanguage.pl),
        () => MockClient((_) async => http.Response(
              jsonEncode({
                'intent': 'save_weld_parameter',
                'fields': {
                  'material': 'SS',
                  'process': 'TIG',
                  'filler': true,
                  'wall_mm': 3,
                  'current_a': 90,
                  'gas': 'hel z butli nr 5 i coś jeszcze',
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      final d = (out.check as AssistantReadyToSave).draft;
      expect(d.gas, isNull);
      expect(d.currentA, 90.0);
    });
  });
}
