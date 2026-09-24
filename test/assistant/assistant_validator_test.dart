// Walidator asystenta: jedyna brama między propozycją (parser lokalny albo
// model na serwerze) a zapisem. Nieznana intencja, pole spoza listy, zły typ,
// wartość spoza zakresu → odrzucenie. Brak istotnego pola → jedno pytanie.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/i18n/app_language.dart';

Map<String, Object?> _base() => {
      'material': 'SS',
      'process': 'TIG',
      'filler': false,
      'wall_mm': 2.0,
      'current_a': 60.0,
    };

void main() {
  group('kompletne → gotowe do podsumowania', () {
    test('minimum ze specyfikacji', () {
      final r = validateAssistantProposal(kIntentSaveWeldParameter, _base());
      expect(r, isA<AssistantReadyToSave>());
      final d = (r as AssistantReadyToSave).draft;
      expect(d.material, 'SS');
      expect(d.process, 'TIG');
      expect(d.filler, isFalse);
      expect(d.wallMm, 2.0);
      expect(d.currentA, 60.0);
      expect(d.diameterMm, isNull);
    });

    test('pola opcjonalne przechodzą, null traktowany jak brak', () {
      final r = validateAssistantProposal(kIntentSaveWeldParameter, {
        ..._base(),
        'diameter_mm': 60.3,
        'position': 'PF',
        'gas': 'AR',
        'flow_lpm': 8,
        'electrode_mm': 2.4,
        'joint': 'BUTT',
      });
      final d = (r as AssistantReadyToSave).draft;
      expect(d.diameterMm, 60.3);
      expect(d.position, 'PF');
      expect(d.gas, 'AR');
      expect(d.flowLpm, 8.0);
      expect(d.electrodeMm, 2.4);
      expect(d.joint, 'BUTT');

      final withNull = validateAssistantProposal(
          kIntentSaveWeldParameter, {..._base(), 'diameter_mm': null});
      expect((withNull as AssistantReadyToSave).draft.diameterMm, isNull);
    });

    test('MIG/MAG i MMA mają drut z definicji', () {
      final r = validateAssistantProposal(kIntentSaveWeldParameter,
          {..._base(), 'process': 'MIG_MAG'}..remove('filler'));
      expect((r as AssistantReadyToSave).draft.filler, isTrue);
    });

    test('open_tool z zapytaniem', () {
      final r = validateAssistantProposal(kIntentOpenTool, {'query': 'heat input'});
      expect(r, isA<AssistantReadyToOpen>());
      expect((r as AssistantReadyToOpen).query, 'heat input');
    });
  });

  group('brak istotnego pola → jedno pytanie', () {
    for (final field in kSaveWeldRequiredOrder) {
      test(field, () {
        final fields = _base()..remove(field);
        final r = validateAssistantProposal(kIntentSaveWeldParameter, fields);
        expect(r, isA<AssistantNeedsField>(), reason: field);
        final q = r as AssistantNeedsField;
        expect(q.field, field);
        expect(assistantQuestionFor(field, AppLanguage.pl), endsWith('?'));
        expect(assistantQuestionFor(field, AppLanguage.en), endsWith('?'));
      });
    }

    test('pyta o pierwsze brakujące pole, nie o wszystkie naraz', () {
      final r = validateAssistantProposal(
          kIntentSaveWeldParameter, {'material': 'SS'});
      expect((r as AssistantNeedsField).field, 'process');
    });
  });

  group('odrzucenia', () {
    void rejects(String intent, Map<String, Object?> fields,
        AssistantRejectReason reason) {
      final r = validateAssistantProposal(intent, fields);
      expect(r, isA<AssistantRejected>(), reason: '$fields');
      expect((r as AssistantRejected).reason, reason, reason: '$fields');
    }

    test('nieznana intencja', () {
      rejects('delete_all_params', _base(), AssistantRejectReason.unknownIntent);
      rejects('unknown', const {}, AssistantRejectReason.unknownIntent);
      rejects('SAVE_WELD_PARAMETER', _base(),
          AssistantRejectReason.unknownIntent);
    });

    test('pole spoza listy', () {
      rejects(kIntentSaveWeldParameter, {..._base(), 'sql': 'DROP TABLE'},
          AssistantRejectReason.extraField);
      rejects(kIntentSaveWeldParameter, {..._base(), 'id': 'x'},
          AssistantRejectReason.extraField);
      rejects(kIntentOpenTool, {'query': 'heat', 'then': 'save'},
          AssistantRejectReason.extraField);
    });

    test('zły typ', () {
      rejects(kIntentSaveWeldParameter, {..._base(), 'current_a': '60'},
          AssistantRejectReason.wrongType);
      rejects(kIntentSaveWeldParameter, {..._base(), 'filler': 'false'},
          AssistantRejectReason.wrongType);
      rejects(kIntentSaveWeldParameter, {..._base(), 'filler': 0},
          AssistantRejectReason.wrongType);
      rejects(kIntentSaveWeldParameter, {..._base(), 'material': 1},
          AssistantRejectReason.wrongType);
      rejects(kIntentOpenTool, {'query': 42}, AssistantRejectReason.wrongType);
      rejects(kIntentSaveWeldParameter, {..._base(), 'wall_mm': double.nan},
          AssistantRejectReason.wrongType);
      rejects(kIntentSaveWeldParameter,
          {..._base(), 'current_a': double.infinity},
          AssistantRejectReason.wrongType);
    });

    test('wartość spoza zakresu', () {
      rejects(kIntentSaveWeldParameter, {..._base(), 'current_a': 5000},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'current_a': 4.9},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'wall_mm': 0.2},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'wall_mm': 51},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'diameter_mm': 2.9},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'diameter_mm': 2001},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'current_a': -60},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'flow_lpm': 400},
          AssistantRejectReason.outOfRange);
      rejects(kIntentSaveWeldParameter, {..._base(), 'electrode_mm': 20},
          AssistantRejectReason.outOfRange);
    });

    test('granice zakresów są dozwolone', () {
      for (final f in [
        {'current_a': 5},
        {'current_a': 500},
        {'wall_mm': 0.3},
        {'wall_mm': 50},
        {'diameter_mm': 3},
        {'diameter_mm': 2000},
      ]) {
        expect(
            validateAssistantProposal(
                kIntentSaveWeldParameter, {..._base(), ...f}),
            isA<AssistantReadyToSave>(),
            reason: '$f');
      }
    });

    test('wartość spoza słownika', () {
      rejects(kIntentSaveWeldParameter, {..._base(), 'material': 'UNOBTAINIUM'},
          AssistantRejectReason.notAllowed);
      rejects(kIntentSaveWeldParameter, {..._base(), 'process': 'LASER_X'},
          AssistantRejectReason.notAllowed);
      rejects(kIntentSaveWeldParameter, {..._base(), 'position': 'ZZ'},
          AssistantRejectReason.notAllowed);
      rejects(kIntentSaveWeldParameter, {..._base(), 'gas': 'XENON'},
          AssistantRejectReason.notAllowed);
      rejects(kIntentSaveWeldParameter, {..._base(), 'joint': 'GLUE'},
          AssistantRejectReason.notAllowed);
    });

    test('sprzeczność: MIG/MAG albo MMA bez drutu', () {
      rejects(kIntentSaveWeldParameter,
          {..._base(), 'process': 'MIG_MAG', 'filler': false},
          AssistantRejectReason.inconsistent);
      rejects(kIntentSaveWeldParameter,
          {..._base(), 'process': 'MMA', 'filler': false},
          AssistantRejectReason.inconsistent);
    });

    test('open_tool: puste albo za długie zapytanie', () {
      rejects(kIntentOpenTool, {'query': '   '}, AssistantRejectReason.outOfRange);
      rejects(kIntentOpenTool, {'query': 'x' * 81},
          AssistantRejectReason.outOfRange);
    });
  });

  group('szkic → rekord WeldParam', () {
    test('mapowanie metody i notatka źródłowa', () {
      final draft = (validateAssistantProposal(kIntentSaveWeldParameter, {
        ..._base(),
        'position': 'PF',
        'gas': 'AR',
        'joint': 'BUTT',
      }) as AssistantReadyToSave)
          .draft;
      final at = DateTime(2026, 9, 25, 14, 3);
      final p = draft.toWeldParam(
          id: 'abc', at: at, byVoice: true, lang: AppLanguage.pl);
      expect(p.id, 'abc');
      expect(p.method, 'TIG_AUTOGEN');
      expect(p.baseMaterial, 'SS');
      expect(p.wallThicknessMm, 2.0);
      expect(p.amps, 60.0);
      expect(p.diameterMm, 0, reason: 'brak średnicy = 0 (kolumna NOT NULL)');
      expect(p.createdAt, at.millisecondsSinceEpoch);
      expect(p.note, startsWith('Głosowo, 2026-09-25 14:03'));
      expect(p.note, contains('PF'));
      expect(p.note, contains('argon'));
      expect(p.note, contains('doczołowe'));

      final wire = draft.copyWith(filler: true).toWeldParam(
          id: 'b', at: at, byVoice: false, lang: AppLanguage.en);
      expect(wire.method, 'TIG_WIRE');
      expect(wire.note, startsWith('Assistant (text), 2026-09-25 14:03'));
      expect(draft.copyWith(process: 'MIG_MAG', filler: true)
              .toWeldParam(id: 'c', at: at, byVoice: true, lang: AppLanguage.pl)
              .method,
          'MAG');
      expect(draft.copyWith(process: 'MMA', filler: true)
              .toWeldParam(id: 'd', at: at, byVoice: true, lang: AppLanguage.pl)
              .method,
          'MMA');
    });
  });

  test('lista intencji jest wersjonowana', () {
    expect(kAssistantIntentsVersion, 1);
    expect(kAssistantIntentsV1.keys.toSet(),
        {kIntentSaveWeldParameter, kIntentOpenTool});
  });
}
