// Wspólne atrapy dla testów mózgu i umiejętności asystenta.

import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/assistant/core/assistant_actions_port.dart';
import 'package:cut_list_app/assistant/core/brain.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/weld_timer_service.dart';
import 'package:cut_list_app/assistant/skills/own_data/instruments_due_skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/certificates_expiry_skill.dart';
import '../../support/fake_weld_timer_effects.dart';

/// Atrapa zapisów: nic nie zapisuje naprawdę, liczy wywołania.
class FakeActionsPort implements AssistantActionsPort {
  final List<WeldParamDraft> savedParams = [];
  final List<PreparedJournal> savedJournal = [];
  int undos = 0;

  /// Numery spoin „zajęte" w dzienniku (projekt → numery).
  final Map<String, Set<String>> takenWeldNos = {};

  @override
  AssistantAnswer weldParamSummary(WeldParamDraft draft,
          {required bool byVoice, required AppLanguage lang}) =>
      AssistantAnswer(
        text: AssistantText(
          'Zapisać: ${draft.process} ${draft.material} '
              '${draft.wallMm} mm ${draft.currentA} A?',
          'Save: ${draft.process} ${draft.material} '
              '${draft.wallMm} mm ${draft.currentA} A?',
        ),
      );

  @override
  Future<UndoAction?> saveWeldParam(WeldParamDraft draft,
      {required bool byVoice, required AppLanguage lang}) async {
    savedParams.add(draft);
    return () async {
      undos++;
      savedParams.remove(draft);
    };
  }

  @override
  Future<JournalPreparation> prepareJournal(WeldJournalDraft draft,
      {required bool byVoice, required AppLanguage lang}) async {
    if (takenWeldNos[draft.project]?.contains(draft.weldNo) ?? false) {
      return JournalWeldNoTaken(
          weldNo: draft.weldNo, project: draft.project, wps: draft.wps);
    }
    return PreparedJournal(
      draft: draft,
      summary: AssistantAnswer(
          text:
              AssistantText.same('Spoina ${draft.weldNo} · ${draft.project}')),
    );
  }

  @override
  Future<UndoAction?> saveJournal(PreparedJournal prepared,
      {required bool byVoice, required AppLanguage lang}) async {
    savedJournal.add(prepared);
    return () async {
      undos++;
      savedJournal.remove(prepared);
    };
  }
}

/// Mózg z pełnym katalogiem i zapisami w atrapie.
class BrainHarness {
  BrainHarness({
    this.lang = AppLanguage.pl,
    String? activeToolId,
    bool onHome = true,
    FakeActionsPort? actions,
    WeldTimerService? timer,
    InstrumentReader? instruments,
    CertificateReader? certificates,
  })  : actions = actions ?? FakeActionsPort(),
        clock = DateTime(2026, 10, 19, 12) {
    this.timer = timer ??
        WeldTimerService(
            now: () => clock,
            effects: FakeEffects(notificationsSupported: false),
            startTicker: (_) => null,
            observeLifecycle: false);
    brain = AssistantBrain(
        skills: buildSkillCatalog(
            actions: this.actions,
            timer: () => this.timer,
            instruments: instruments ?? () async => [],
            certificates: certificates ?? (_) async => []));
    modules = FixedModuleContext(
        activeToolId: activeToolId, onHomeOrAssistant: onHome);
    ctx = AssistantContext(lang: lang, modules: modules, now: () => clock);
  }

  late final WeldTimerService timer;
  final AppLanguage lang;
  final FakeActionsPort actions;
  DateTime clock;
  late final AssistantBrain brain;
  late final FixedModuleContext modules;
  late final AssistantContext ctx;

  Future<BrainReply> say(String text,
          {List<String> alternatives = const [], bool byVoice = false}) =>
      brain.handle(
          Utterance(text,
              lang: lang, byVoice: byVoice, alternatives: alternatives),
          ctx);

  void wait(Duration d) => clock = clock.add(d);
}

/// Tekst odpowiedzi (karta) w języku polskim albo opis wyniku.
String textOf(SkillResult r, [AppLanguage lang = AppLanguage.pl]) =>
    switch (r) {
      AnswerResult(:final answer) => answer.text.of(lang),
      AskResult(:final question) => question.of(lang),
      ConfirmResult(:final summary) => summary.text.of(lang),
      NotUnderstood() => '<nie rozumiem>',
      FailedResult(:final message) => message.of(lang),
    };
