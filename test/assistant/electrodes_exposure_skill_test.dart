import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/domain/welding/electrode_reference.dart';
import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_exposure_page.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

class NoReminders implements ReminderPlatform {
  @override
  bool get supported => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> cancel(Iterable<int> ids) async {}
  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {}
}

void main() {
  test('bare 7018 asks the actual R/M variant, origin and reference basis',
      () async {
    final h = BrainHarness();
    final first = (await h.say('Ile elektroda 7018 może leżeć na powietrzu?'))
        .result as AskResult;
    expect(first.slot, 'variant');
    await h.say('H4R');
    expect(h.brain.pending!.slot, 'origin');
    await h.say('z piecyka');
    expect(h.brain.pending!.slot, 'reference');
    final a = (await h.say('tak')).result as AnswerResult;
    expect(
        a.answer.text.pl,
        electrodeReferenceText(ElectrodeClass.e7018R, ElectrodeSource.oven,
            en: false));
    expect(a.show!.fields['reference_only'], isTrue);
  });
  for (final (label, c) in [
    ('E7018 bez R', ElectrodeClass.e7018),
    ('E7018-1 bez R', ElectrodeClass.e7018dash1),
    ('E7018H4R', ElectrodeClass.e7018R),
    ('E7018-1H4R', ElectrodeClass.e7018R),
    ('E7018M', ElectrodeClass.e7018M),
    ('E7018-A1', ElectrodeClass.e7018X),
    ('E7018 A1', ElectrodeClass.e7018X),
    ('E8018-B2', ElectrodeClass.e8018X),
    ('E9018-B3', ElectrodeClass.e9018X),
    ('E10018-D2', ElectrodeClass.e10018X),
    ('E11018-M', ElectrodeClass.e11018X),
  ]) {
    test('classification $label uses the actual domain default', () async {
      final a = (await BrainHarness()
              .say('Limit ekspozycji $label z piecyka model 2020'))
          .result as AnswerResult;
      expect(a.show!.fields['electrode_class'], c.name);
      expect(a.answer.text.en,
          electrodeReferenceText(c, ElectrodeSource.oven, en: true));
    });
  }
  test(
      'EN fresh pack remains a manufacturer-based model default, never a batch clearance',
      () async {
    final a = (await BrainHarness().say(
            'Ekspozycja EN ISO 2560-A B H5 świeże opakowanie hermetyczne model domyślny'))
        .result as AnswerResult;
    expect(
        a.answer.text.pl,
        electrodeReferenceText(
            ElectrodeClass.enIso2560B, ElectrodeSource.hermeticPack,
            en: false));
    expect(a.answer.text.pl,
        contains('Sama klasyfikacja EN nie ustanawia tego czasu'));
  });
  test(
      'ambiguous classes can be corrected without retaining 7018 variant state',
      () async {
    final h = BrainHarness();
    final q = (await h.say('Ekspozycja E7018 i E8018-B2 z piecyka model 2020'))
        .result as AskResult;
    expect(q.slot, 'classes');
    final a = (await h.say('E8018-X')).result as AnswerResult;
    expect(a.show!.fields['electrode_class'], 'e8018X');
  });
  for (final question in [
    'Ekspozycja E6013 z piecyka model 2020',
    'Ekspozycja E308L z piecyka model 2020',
    'Ekspozycja E8018-B2 H4R z piecyka model 2020',
    'Ekspozycja E7018 bez R z piecyka AWS D1.1:2025'
  ]) {
    test('unsupported data is reported: $question', () async {
      final r = (await BrainHarness().say(question)).result as FailedResult;
      expect(r.reportMissingCapability, isTrue);
    });
  }
  test('wet electrodes do not receive fitness approval from a time default',
      () async {
    final r = (await BrainHarness()
            .say('Mokre elektrody E7018 bez R z piecyka model 2020'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isFalse);
    expect(r.message.pl, contains('zawilgoconych'));
  });
  test(
      'declining the historical reference does not show a default as an actual batch limit',
      () async {
    final h = BrainHarness();
    final q =
        (await h.say('Ekspozycja E7018 bez R z piecyka')).result as AskResult;
    expect(q.slot, 'reference');
    final a = (await h.say('nie')).result as AnswerResult;
    expect(a.show, isNull);
    expect(a.answer.text.pl, contains('kartę produktu'));
  });
  test('requesting another edition as a follow-up reports the missing table',
      () async {
    final h = BrainHarness();
    await h.say('Ekspozycja E7018 bez R z piecyka');
    final r = (await h.say('2025')).result as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  test(
      'unknown stainless electrode without a model year is still recognized as a gap',
      () async {
    final r = (await BrainHarness().say('Ekspozycja E308L z piecyka')).result
        as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  test(
      'a spoken classification uses the shared tokenizer without creating a batch',
      () async {
    final a = (await BrainHarness().say(
            'Elektroda e siedem tysięcy osiemnaście bez R z piecyka model 2020',
            byVoice: true))
        .result as AnswerResult;
    expect(a.show!.fields['electrode_class'], 'e7018');
  });
  test(
      'conflicting R designation asks instead of picking the longer or shorter default',
      () async {
    final h = BrainHarness();
    final q = (await h.say('Ekspozycja E7018H4R bez R z piecyka model 2020'))
        .result as AskResult;
    expect(q.slot, 'variant');
    final a = (await h.say('bez R')).result as AnswerResult;
    expect(a.show!.fields['electrode_class'], 'e7018');
  });
  test('low-alloy A1 with R never inherits the A5.1 nine-hour row', () async {
    for (final label in [
      'E7018-A1 H4R',
      'E7018-A1H4R',
      'E7018 A1 H4R',
      'E8018R'
    ]) {
      final r =
          (await BrainHarness().say('Ekspozycja $label z piecyka model 2020'))
              .result as FailedResult;
      expect(r.reportMissingCapability, isTrue, reason: label);
    }
  });
  test(
      'a dash before M requires clarification instead of assuming its table family',
      () async {
    final h = BrainHarness();
    final q = (await h.say('Ekspozycja E7018-M z piecyka model 2020')).result
        as AskResult;
    expect(q.slot, 'classes');
    final a = (await h.say('E7018M')).result as AnswerResult;
    expect(a.show!.fields['electrode_class'], 'e7018M');
  });
  test('every offered class choice resolves to its source enum group',
      () async {
    final initial = (await BrainHarness()
            .say('Limit ekspozycji elektrod z piecyka model 2020'))
        .result as AskResult;
    expect(initial.choices.length, ElectrodeClass.values.length);
    for (var i = 0; i < initial.choices.length; i++) {
      final h = BrainHarness();
      await h.say('Limit ekspozycji elektrod z piecyka model 2020');
      final a =
          (await h.say(initial.choices[i].utterance)).result as AnswerResult;
      expect(a.show!.fields['electrode_class'], ElectrodeClass.values[i].name,
          reason: initial.choices[i].utterance);
    }
  });
  testWidgets(
      'reference handle preserves the stored batch, custom limit and event log',
      (tester) async {
    ToolBridge.reset();
    final batch = ElectrodeBatch.takenOut(
        id: 'existing',
        electrode: ElectrodeClass.e7018,
        at: DateTime(2026, 10, 21, 8),
        limitMinutes: 17,
        maxRedries: 4);
    final raw = encodeBatches([batch]);
    SharedPreferences.setMockInitialValues({kElectrodeBatchesPrefsKey: raw});
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: MaterialApp(
            home: ElectrodeExposurePage(
                now: () => DateTime(2026, 10, 21, 8, 5),
                reminders: QualificationReminders(platform: NoReminders())))));
    await tester.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    expect(ToolBridge.instance.isReady(handle), isTrue);
    final fields = {
      'electrode_class': 'e7018R',
      'origin': 'oven',
      'reference_only': true
    };
    expect(await handle.apply(fields), isEmpty);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('electrode-assistant-reference')),
        findsOneWidget);
    expect(find.textContaining('Domyślny limit ekspozycji'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesPrefsKey), raw);
    expect(await handle.apply({...fields, 'reference_only': false}),
        fields.keys.toSet());
    expect(prefs.getString(kElectrodeBatchesPrefsKey), raw);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
